params.input_table = params.input_table ?: "cryo_images.tsv"
params.sheet_mode = params.sheet_mode ?: "local"
params.sheet_url = params.sheet_url ?: ""
params.sheet_name = params.sheet_name ?: ""
params.google_key = params.google_key ?: "${params.script_dir}/trec-tem-screen-e98a2e03f58b.json"
params.collection_table_url = params.collection_table_url ?: ""
params.collection_table_sheet = params.collection_table_sheet ?: "cryo_collection_table"
params.local_collection_table = params.local_collection_table ?: "${params.logdir}/cryo_collection_table.tsv"
params.dryrun = params.dryrun ?: "TRUE"
params.dryrun_n = params.dryrun_n ?: 2
params.script_dir = params.script_dir ?: baseDir.toString()
params.outdir = params.outdir ?: "cryo_processed"
params.logdir = params.logdir ?: "cryo_logs"
params.workflow_stage = params.workflow_stage ?: "discover"
params.s3_bucket = params.s3_bucket ?: "s3embl/cryotest"
params.zarr_format = params.zarr_format ?: 2
params.default_x_scale = params.default_x_scale ?: ""
params.default_y_scale = params.default_y_scale ?: ""
params.default_z_scale = params.default_z_scale ?: ""
params.scale_unit = params.scale_unit ?: "nm"
params.persistent_metadata_dir = params.persistent_metadata_dir ?: "${params.outdir}/metadata"


process CHECKEXISTINGCRYOS3FILES {

    cpus 1
    memory "1GB"
    time "10m"

    publishDir "${params.logdir}", mode:"copy"
    containerOptions "--bind /g --bind /scratch --bind /home"

    input:
    val s3_bucket
    val workflow_stage
    val dryrun

    output:
    path "existing_s3_entries.txt", emit: existing_s3

    script:
    """
    set -euo pipefail

    require_s3="FALSE"
    dryrun_is_false="FALSE"
    case "${dryrun}" in
      FALSE|false|0|no|NO)
        dryrun_is_false="TRUE"
        ;;
    esac

    if { [ "${workflow_stage}" = "all" ] || [ "${workflow_stage}" = "collection" ]; } && [ "\$dryrun_is_false" = "TRUE" ]; then
      require_s3="TRUE"
    fi

    if command -v mc >/dev/null 2>&1; then
      if ! mc ls --recursive "${s3_bucket}" > "existing_s3_entries.txt"; then
        if [ "\$require_s3" = "TRUE" ]; then
          echo "Failed to list ${s3_bucket}; refusing to continue because this run depends on S3 skip detection." >&2
          exit 1
        fi
        : > "existing_s3_entries.txt"
      fi
    else
      if [ "\$require_s3" = "TRUE" ]; then
        echo "mc command is not available; refusing to continue because this run depends on S3 skip detection." >&2
        exit 1
      fi
      : > "existing_s3_entries.txt"
    fi
    """
}


process SELECTCRYOIMAGES {

    cpus 1
    memory "1GB"
    time "10m"

    publishDir "${params.logdir}", mode:"copy"
    containerOptions "--bind /g --bind /scratch --bind /home"

    input:
    val input_table
    val sheet_mode
    val sheet_url
    val sheet_name
    val google_key
    val outdir
    val dryrun
    val dryrun_n
    path existing_s3
    val default_x_scale
    val default_y_scale
    val default_z_scale
    val scale_unit

    output:
    path "images_to_process.csv", emit: to_process
    path "all_datasets.tsv", emit: all_datasets

    script:
    """
    Rscript "${params.script_dir}/select_images.R" \
      --input_table "${input_table}" \
      --sheet_mode "${sheet_mode}" \
      --sheet_url "${sheet_url}" \
      --sheet_name "${sheet_name}" \
      --google_key "${google_key}" \
      --outdir "${outdir}" \
      --dryrun "${dryrun}" \
      --dryrun_n "${dryrun_n}" \
      --existing_s3 "${existing_s3}" \
      --default_x_scale "${default_x_scale}" \
      --default_y_scale "${default_y_scale}" \
      --default_z_scale "${default_z_scale}" \
      --scale_unit "${scale_unit}"
    """
}


process EXTRACTCRYOMETADATA {

    cpus 1
    memory "2GB"
    time "20m"

    publishDir "${params.logdir}/metadata", mode:"copy"
    containerOptions "--bind /g --bind /scratch --bind /home"

    input:
    tuple val(filename), val(raw_path), val(output_path), val(x_scale_override), val(y_scale_override), val(z_scale_override), val(scale_unit), val(req_mem)

    output:
    tuple val(filename), val(raw_path), val(output_path), path("${filename}_metadata.json"), path("${filename}_pixel_size.tsv"), val(req_mem), emit: metadata
    path "${filename}_metadata.json", emit: metadata_json

    script:
    """
    set -euo pipefail

    python3 "${params.script_dir}/extract_metadata.py" \
      --input "${raw_path}" \
      --name "${filename}" \
      --metadata-json "${filename}_metadata.json" \
      --pixel-size-tsv "${filename}_pixel_size.tsv" \
      --x-scale "${x_scale_override}" \
      --y-scale "${y_scale_override}" \
      --z-scale "${z_scale_override}" \
      --scale-unit "${scale_unit}"

    mkdir -p "${params.persistent_metadata_dir}"
    metadata_tmp="${params.persistent_metadata_dir}/${filename}_metadata.json.tmp.\$\$"
    pixel_tmp="${params.persistent_metadata_dir}/${filename}_pixel_size.tsv.tmp.\$\$"
    cp "${filename}_metadata.json" "\$metadata_tmp"
    cp "${filename}_pixel_size.tsv" "\$pixel_tmp"
    mv "\$metadata_tmp" "${params.persistent_metadata_dir}/${filename}_metadata.json"
    mv "\$pixel_tmp" "${params.persistent_metadata_dir}/${filename}_pixel_size.tsv"
    """
}


process EUBICRYOCONVERSION {

    cpus 1
    memory { "${Math.min(Math.max((req_mem as Integer), 16), 128)}GB" }
    time "2h"

    publishDir "${params.outdir}/${filename}", mode:"copy"
    containerOptions "--bind /g --bind /scratch --bind /home"
    errorStrategy "ignore"

    input:
    tuple val(filename), val(raw_path), val(output_path), path(metadata_json), path(pixel_size_tsv), val(req_mem)

    output:
    tuple val(filename), path("${filename}_omezarr"), emit: omezarr
    path "${filename}_conversion_done.txt"

    script:
    """
    set -euo pipefail

    pixel_scale_x=\$(awk 'NR==2 {print \$1}' "${pixel_size_tsv}")
    pixel_scale_y=\$(awk 'NR==2 {print \$2}' "${pixel_size_tsv}")
    pixel_scale_z=\$(awk 'NR==2 {print \$3}' "${pixel_size_tsv}")

    if [ -z "\$pixel_scale_x" ] || [ -z "\$pixel_scale_y" ] || [ -z "\$pixel_scale_z" ]; then
      echo "Missing x/y/z scale values for ${filename}; add metadata to the file or sheet overrides." >&2
      exit 1
    fi

    rm -rf "${filename}_omezarr"

    eubi to_zarr \
      "${raw_path}" \
      "${filename}_omezarr" \
      --x_unit nm \
      --y_unit nm \
      --z_unit nm \
      --x_scale "\${pixel_scale_x}" \
      --y_scale "\${pixel_scale_y}" \
      --z_scale "\${pixel_scale_z}" \
      --dimension_order xyzct \
      --squeeze True \
      --save_omexml True \
      --zar_format "${params.zarr_format}" \
      --auto_chunk True \
      --jvm_memory 8GB \
      --max_workers 1

    touch "${filename}_conversion_done.txt"
    """
}


process S3UPLOADCRYO {

    cpus 1
    memory "1GB"
    time "30m"

    publishDir "${params.logdir}/upload", mode:"copy"
    containerOptions "--bind /g --bind /scratch --bind /home"
    errorStrategy "ignore"

    input:
    tuple val(filename), path(omezarr)

    output:
    path "${filename}_s3_upload_done.txt"

    script:
    """
    set -euo pipefail

    image_zarr="${omezarr}"
    if [ ! -e "\${image_zarr}/.zattrs" ] && [ ! -e "\${image_zarr}/.zgroup" ]; then
      inner_zarr=\$(find "\${image_zarr}" -mindepth 1 -maxdepth 3 -type d \\( -name '*.zarr' -o -name '*.ome.zarr' \\) | head -n 1)
      if [ -n "\${inner_zarr}" ]; then
        image_zarr="\${inner_zarr}"
      fi
    fi

    mc cp "\${image_zarr}/" "${params.s3_bucket}/${filename}/" --recursive
    touch "${filename}_s3_upload_done.txt"
    """
}


process COLLECTCRYOS3FILES {

    cpus 1
    memory "1GB"
    time "10m"

    publishDir "${params.logdir}", mode:"copy"
    containerOptions "--bind /g --bind /scratch --bind /home"

    input:
    val trigger

    output:
    path "all_s3_entries.txt", emit: all_s3

    script:
    """
    mc ls --recursive "${params.s3_bucket}" > all_s3_entries.txt
    """
}


process MAKECRYOCOLLECTIONTABLE {

    cpus 1
    memory "1GB"
    time "10m"

    publishDir "${params.logdir}", mode:"copy"
    containerOptions "--bind /g --bind /scratch --bind /home"

    input:
    path all_s3
    path all_datasets
    val metadata_dir
    val metadata_ready

    output:
    path "done.tsv"
    path "cryo_collection_table.tsv", optional:true

    script:
    """
    Rscript "${params.script_dir}/make_collection_table.R" \
      --all_s3 "${all_s3}" \
      --all_datasets "${all_datasets}" \
      --metadata_dir "${metadata_dir}" \
      --s3_bucket "${params.s3_bucket}" \
      --sheet_mode "${params.sheet_mode}" \
      --google_key "${params.google_key}" \
      --collection_table_url "${params.collection_table_url}" \
      --collection_table_sheet "${params.collection_table_sheet}" \
      --local_collection_table "cryo_collection_table.tsv"
    """
}


workflow {

    CHECKEXISTINGCRYOS3FILES(
        params.s3_bucket,
        params.workflow_stage,
        params.dryrun
    )

    SELECTCRYOIMAGES(
        params.input_table,
        params.sheet_mode,
        params.sheet_url,
        params.sheet_name,
        params.google_key,
        params.outdir,
        params.dryrun,
        params.dryrun_n,
        CHECKEXISTINGCRYOS3FILES.out.existing_s3,
        params.default_x_scale,
        params.default_y_scale,
        params.default_z_scale,
        params.scale_unit
    )

    if (params.workflow_stage != "discover" && params.workflow_stage != "collection") {

        SELECTCRYOIMAGES.out.to_process
            .splitCsv(header:true)
            .map { row -> tuple(row.filename, row.raw_path, row.output_path, row.x_scale, row.y_scale, row.z_scale, row.scale_unit, row.req_mem) }
            .set { cryo_batch_ch }

        EXTRACTCRYOMETADATA(cryo_batch_ch)

        EUBICRYOCONVERSION(EXTRACTCRYOMETADATA.out.metadata)

        if (params.workflow_stage == "all") {
            upload_done_ch = S3UPLOADCRYO(EUBICRYOCONVERSION.out.omezarr).collect()
            COLLECTCRYOS3FILES(upload_done_ch)

            metadata_jsons_ch = EXTRACTCRYOMETADATA.out.metadata_json.collect()
            MAKECRYOCOLLECTIONTABLE(
                COLLECTCRYOS3FILES.out.all_s3,
                SELECTCRYOIMAGES.out.all_datasets,
                params.persistent_metadata_dir,
                metadata_jsons_ch
            )
        }
    }

    if (params.workflow_stage == "collection") {
        COLLECTCRYOS3FILES(Channel.value("collection_table_only"))

        MAKECRYOCOLLECTIONTABLE(
            COLLECTCRYOS3FILES.out.all_s3,
            SELECTCRYOIMAGES.out.all_datasets,
            params.persistent_metadata_dir,
            Channel.value("stored_metadata_ready")
        )
    }
}
