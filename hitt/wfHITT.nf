params.input_table = params.input_table ?: "hitt_images.tsv"
params.sheet_mode = params.sheet_mode ?: "local"
params.sheet_url = params.sheet_url ?: "https://docs.google.com/spreadsheets/d/1ePRpa56mmMvCeRTLXmwOywOLy5_I3AFrxJepSUYGR1s/edit?gid=0#gid=0"
params.sheet_name = params.sheet_name ?: ""
params.google_key = params.google_key ?: "${params.script_dir}/trec-tem-screen-e98a2e03f58b.json"
params.dryrun = params.dryrun ?: "FALSE"
params.dryrun_n = params.dryrun_n ?: 2
params.script_dir = params.script_dir ?: baseDir.toString()
params.logdir = params.logdir ?: "hitt_logs"
params.workflow_stage = params.workflow_stage ?: "process"
params.s3_bucket = params.s3_bucket ?: "s3embl/hitttest"
params.zarr_format = params.zarr_format ?: 2
params.x_scale = params.x_scale ?: 100
params.y_scale = params.y_scale ?: 100
params.input_suffix = params.input_suffix ?: "recon_111_1/tomo"
params.output_name = params.output_name ?: "omezarr"
params.overwrite = params.overwrite ?: "FALSE"


process SELECTHITTIMAGES {

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
    val dryrun
    val dryrun_n

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
      --dryrun "${dryrun}" \
      --dryrun_n "${dryrun_n}"
    """
}


process EUBIHITTCONVERSION {

    cpus 1
    memory { "${Math.min(Math.max((req_mem as Integer), 16), 128)}GB" }
    time "2h"

    publishDir "${params.logdir}/conversion", mode:"copy"
    containerOptions "--bind /g --bind /scratch --bind /home"
    errorStrategy "retry"
    maxRetries 1

    input:
    tuple val(filename), val(tmp_copy_path), val(omezarr_path), val(req_mem)

    output:
    tuple val(filename), val(omezarr_path), emit: omezarr
    path "${filename}_conversion_done.txt"

    script:
    """
    set -euo pipefail

    input_path="${tmp_copy_path}/${params.input_suffix}"
    output_path="${omezarr_path}"

    if [ ! -e "\$input_path" ]; then
      echo "Expected input path does not exist: \$input_path" >&2
      exit 1
    fi

    case "${params.overwrite}" in
      TRUE|true|1|yes|YES)
        rm -rf "\$output_path"
        ;;
    esac

    if [ ! -e "\$output_path" ]; then
      eubi to_zarr \
        "\$input_path" \
        "\$output_path" \
        --x_unit nm \
        --y_unit nm \
        --x_scale "${params.x_scale}" \
        --y_scale "${params.y_scale}" \
        --dimension_order xyzct \
        --concatenation_axes z \
        --z_tag "slice_" \
        --squeeze True \
        --save_omexml True \
        --zar_format "${params.zarr_format}" \
        --auto_chunk True \
        --max_workers 1
    else
      echo "Skipping conversion because output already exists: \$output_path"
    fi

    touch "${filename}_conversion_done.txt"
    """
}


process S3UPLOADHITT {

    cpus 1
    memory "1GB"
    time "30m"

    publishDir "${params.logdir}/upload", mode:"copy"
    containerOptions "--bind /g --bind /scratch --bind /home"
    errorStrategy "retry"
    maxRetries 1

    input:
    tuple val(filename), val(omezarr_path)

    output:
    path "${filename}_s3_upload_done.txt"

    script:
    """
    set -euo pipefail

    if [ ! -e "${omezarr_path}" ]; then
      echo "Expected OME-Zarr path does not exist: ${omezarr_path}" >&2
      exit 1
    fi

    mc cp "${omezarr_path}" "${params.s3_bucket}/${filename}" --recursive
    touch "${filename}_s3_upload_done.txt"
    """
}


process COLLECTHITTS3FILES {

    cpus 1
    memory "1GB"
    time "10m"

    publishDir "${params.logdir}", mode:"copy"
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


workflow {

    SELECTHITTIMAGES(
        params.input_table,
        params.sheet_mode,
        params.sheet_url,
        params.sheet_name,
        params.google_key,
        params.dryrun,
        params.dryrun_n
    )

    if (params.workflow_stage != "discover") {

        SELECTHITTIMAGES.out.to_process
            .splitCsv(header:true)
            .map { row -> tuple(row.filename, row.tmp_copy_path, "${row.tmp_copy_path}/${params.output_name}", row.req_mem) }
            .set { hitt_batch_ch }

        EUBIHITTCONVERSION(hitt_batch_ch)

        if (params.workflow_stage == "all") {
            upload_done_ch = S3UPLOADHITT(EUBIHITTCONVERSION.out.omezarr).collect()
            COLLECTHITTS3FILES(upload_done_ch)

            // TODO: Add MoBIE collection table generation here once the table schema is finalized.
        }
    }
}
