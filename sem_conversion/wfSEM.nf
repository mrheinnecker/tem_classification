params.dryrun = params.dryrun ?: "TRUE"
params.script_dir = params.script_dir ?: baseDir.toString()
params.rawdir = params.rawdir ?: "/g/schwab/Chandni/SEM/IMATREC SEM"
params.outdir = params.outdir ?: "sem_processed"
params.logdir = params.logdir ?: "sem_logs"
params.sheet_mode = params.sheet_mode ?: "local"
params.sheet_url = params.sheet_url ?: "https://docs.google.com/spreadsheets/d/143uVeeJ72SQE5eK01lzWYCEiT7pJUF3lX7hJl3R9s9I/edit?gid=258669282#gid=258669282"
params.collection_table_url = params.collection_table_url ?: "https://docs.google.com/spreadsheets/d/15WNNnse7OvlfiJwFOFYbQA4zIp-5nKc0icRZYfJS--o/edit?gid=1643802951#gid=1643802951"
params.google_key = params.google_key ?: "${params.script_dir}/trec-tem-screen-e98a2e03f58b.json"
params.local_log = params.local_log ?: "${params.outdir}/sem_image_log_local.tsv"
params.workflow_stage = params.workflow_stage ?: "discover"
params.s3_bucket = params.s3_bucket ?: "s3embl/semscreen"
params.zarr_format = params.zarr_format ?: 2


process SELECTSEMIMAGES {

    cpus 1
    memory "1GB"
    time "30m"

    publishDir "${params.logdir}", mode:"copy"
    containerOptions "--bind /g --bind /scratch --bind /home"

    input:
    val rawdir
    val outdir
    val dryrun
    val sheet_mode
    val sheet_url
    val google_key
    val local_log

    output:
    path "images_to_process.csv", emit: to_process
    path "all_datasets.tsv", emit: all_datasets

    script:
    """
    Rscript "${params.script_dir}/select_images.R" \
      --rawdir "${rawdir}" \
      --outdir "${outdir}" \
      --dryrun "${dryrun}" \
      --sheet_mode "${sheet_mode}" \
      --sheet_url "${sheet_url}" \
      --google_key "${google_key}" \
      --local_log "${local_log}"
    """
}


process EXTRACTSEMMETADATA {

    cpus 1
    memory "2GB"
    time "20m"

    publishDir "${params.outdir}/${filename}", mode:"copy"
    containerOptions "--bind /g --bind /scratch --bind /home"

    input:
    tuple val(filename), path(raw_tif), val(shortname), val(req_mem)

    output:
    tuple val(filename), path(raw_tif), path("${filename}_metadata.json"), path("${filename}_pixel_size.tsv"), val(req_mem), emit: sem_image
    path "${filename}_metadata.json", emit: metadata_json
    path "${filename}_pixel_size.tsv", emit: pixel_size_tsv

    script:
    """
    python3 "${params.script_dir}/extract_metadata.py" \
      "${raw_tif}" \
      "${filename}_metadata.json"

    python3 - "${filename}_metadata.json" > "${filename}_pixel_size.tsv" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    metadata = json.load(f)

pixel_size = metadata["pixel_size"]
print("x_nm\\ty_nm")
print(f"{pixel_size['x_nm']}\\t{pixel_size['y_nm']}")
PY
    """
}


process EUBISEMCONVERSION {

    cpus 1
    memory { "${Math.min(Math.max((req_mem as Integer) * 2, 16), 96)}GB" }
    time "1h"

    publishDir "${params.outdir}/${filename}", mode:"copy"
    containerOptions "--bind /g --bind /scratch --bind /home"
    errorStrategy "retry"
    maxRetries 1

    input:
    tuple val(filename), path(raw_tif), path(metadata_json), path(pixel_size_tsv), val(req_mem)

    output:
    tuple val(filename), path("${filename}_omezarr"), emit: omezarr
    path "conversion_done.txt"

    script:
    """
    pixel_scale_x=\$(awk 'NR==2 {print \$1}' "${pixel_size_tsv}")
    pixel_scale_y=\$(awk 'NR==2 {print \$2}' "${pixel_size_tsv}")

    eubi to_zarr \
      "${raw_tif}" \
      "${filename}_omezarr" \
      --x_unit nm \
      --y_unit nm \
      --x_scale "\${pixel_scale_x}" \
      --y_scale "\${pixel_scale_y}" \
      --dimension_order xyzct \
      --squeeze True \
      --save_omexml True \
      --zar_format "${params.zarr_format}" \
      --auto_chunk True \
      --jvm_memory 8GB \
      --max_workers 1

    touch conversion_done.txt
    """
}


process S3UPLOADSEM {

    cpus 1
    memory "1GB"
    time "10m"

    containerOptions "--bind /g --bind /scratch --bind /home"

    input:
    tuple val(filename), path(omezarr)

    output:
    path "${filename}_s3_upload_done.txt"

    script:
    """
    image_zarr="${omezarr}"

    if [ ! -e "\${image_zarr}/.zattrs" ] && [ ! -e "\${image_zarr}/.zgroup" ]; then
      inner_zarr=\$(find "\${image_zarr}" -mindepth 1 -maxdepth 3 -type d \\( -name '*.zarr' -o -name '*.ome.zarr' \\) | head -n 1)
      if [ -n "\${inner_zarr}" ]; then
        image_zarr="\${inner_zarr}"
      fi
    fi

    mc cp "\${image_zarr}/" "${params.s3_bucket}/" -r
    touch "${filename}_s3_upload_done.txt"
    """
}


process COLLECTSEMS3FILES {

    cpus 1
    memory "1GB"
    time "10m"

    containerOptions "--bind /g --bind /scratch --bind /home"

    input:
    path done_files

    output:
    path "all_s3_entries.txt", emit: all_s3

    script:
    """
    mc ls "${params.s3_bucket}" > all_s3_entries.txt
    """
}


process MAKESEMCOLLECTIONTABLE {

    cpus 1
    memory "1GB"
    time "10m"

    publishDir "${params.logdir}", mode:"copy"
    containerOptions "--bind /g --bind /scratch --bind /home"

    input:
    path all_s3
    path metadata_jsons

    output:
    path "done.tsv"
    path "sem_collection_table.tsv", optional:true

    script:
    """
    
    echo "letsgo"
    Rscript "${params.script_dir}/make_collection_table.R" \
      --all_s3 "${all_s3}" \
      --metadata_dir "." \
      --sheet_mode "${params.sheet_mode}" \
      --google_key "${params.google_key}" \
      --collection_table_url "${params.collection_table_url}" \
      --local_collection_table "sem_collection_table.tsv" \
      --image_log_url "${params.sheet_url}" \
      --local_image_log "${params.local_log}"
    """
}


workflow {

    SELECTSEMIMAGES(
        params.rawdir,
        params.outdir,
        params.dryrun,
        params.sheet_mode,
        params.sheet_url,
        params.google_key,
        params.local_log
    )

    if (params.workflow_stage != "discover") {

        SELECTSEMIMAGES.out.to_process
            .splitCsv(header:true)
            .map { row -> tuple(row.filename, file(row.file), row.shortname, row.req_mem) }
            .set { sem_batch_ch }

        EXTRACTSEMMETADATA(sem_batch_ch)
        EUBISEMCONVERSION(EXTRACTSEMMETADATA.out.sem_image)

        if (params.workflow_stage == "all") {
            upload_done_ch = S3UPLOADSEM(EUBISEMCONVERSION.out.omezarr).collect()
            COLLECTSEMS3FILES(upload_done_ch)

            metadata_jsons_ch = EXTRACTSEMMETADATA.out.metadata_json.collect()
            MAKESEMCOLLECTIONTABLE(
                COLLECTSEMS3FILES.out.all_s3,
                metadata_jsons_ch
            )
        }
    }
}
