params.input_table = params.input_table ?: "hitt_images.tsv"
params.sheet_mode = params.sheet_mode ?: "local"
params.sheet_url = params.sheet_url ?: "https://docs.google.com/spreadsheets/d/1ePRpa56mmMvCeRTLXmwOywOLy5_I3AFrxJepSUYGR1s/edit?gid=0#gid=0"
params.sheet_name = params.sheet_name ?: ""
params.google_key = params.google_key ?: "${params.script_dir}/trec-tem-screen-e98a2e03f58b.json"
params.collection_table_url = params.collection_table_url ?: "https://docs.google.com/spreadsheets/d/1ePRpa56mmMvCeRTLXmwOywOLy5_I3AFrxJepSUYGR1s/edit?gid=1582290308#gid=1582290308"
params.collection_table_sheet = params.collection_table_sheet ?: "hitt_collection_table"
params.local_collection_table = params.local_collection_table ?: "${params.logdir}/hitt_collection_table.tsv"
params.dryrun = params.dryrun ?: "FALSE"
params.dryrun_n = params.dryrun_n ?: 2
params.script_dir = params.script_dir ?: baseDir.toString()
params.logdir = params.logdir ?: "hitt_logs"
params.workflow_stage = params.workflow_stage ?: "process"
params.s3_bucket = params.s3_bucket ?: "s3embl/hitttest"
params.zarr_format = params.zarr_format ?: 2
params.x_scale = params.x_scale ?: 650
params.y_scale = params.y_scale ?: 650
params.z_scale = params.z_scale ?: 650
params.input_suffix = params.input_suffix ?: "recon_111_1/tomo"
params.output_name = params.output_name ?: "omezarr"
params.overwrite = params.overwrite ?: "TRUE"
params.convert_uint16 = params.convert_uint16 ?: "TRUE"
params.uint16_lower_percentile = params.uint16_lower_percentile ?: 0.1
params.uint16_upper_percentile = params.uint16_upper_percentile ?: 99.9
params.uint16_sample_values = params.uint16_sample_values ?: 2000000
params.copy_data = params.copy_data ?: "TRUE"
params.copy_dest_root = params.copy_dest_root ?: "/scratch/rheinnec/tmp_hitt"
params.remote_user = params.remote_user ?: "p3l-yschwab"
params.remote_host = params.remote_host ?: "cerberus.embl-hamburg.de"
params.remote_port = params.remote_port ?: 22443


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
    val copy_dest_root
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
      --copy_dest_root "${copy_dest_root}" \
      --dryrun "${dryrun}" \
      --dryrun_n "${dryrun_n}"
    """
}


process COPYHITTDATA {

    cpus 1
    memory "1GB"
    time "4h"

    publishDir "${params.logdir}/copy", mode:"copy"
    containerOptions "--bind /g --bind /scratch --bind /home"
    errorStrategy "retry"
    maxRetries 1

    input:
    tuple val(filename), val(remote_tomo_path), val(tmp_copy_path), val(omezarr_path), val(req_mem)

    output:
    tuple val(filename), val(tmp_copy_path), val(omezarr_path), val(req_mem), emit: copied_images
    path "${filename}_copy_done.txt"

    script:
    """
    set -euo pipefail

    local_tomo_path="${tmp_copy_path}/${params.input_suffix}"

    case "${params.copy_data}" in
      TRUE|true|1|yes|YES)
        if [ -z "\${SSHPASS:-}" ]; then
          echo "SSHPASS is not set. Export SSHPASS before starting the workflow." >&2
          exit 1
        fi

        remote_source="${remote_tomo_path}"
        case "\$remote_source" in
          *:*) ;;
          *) remote_source="${params.remote_user}@${params.remote_host}:\$remote_source" ;;
        esac

        mkdir -p "\$local_tomo_path"
        sshpass -e rsync -avr \
          -e "ssh -p ${params.remote_port}" \
          "\${remote_source%/}/" \
          "\$local_tomo_path/"
        ;;
      *)
        if [ ! -d "\$local_tomo_path" ]; then
          echo "Copying is disabled and the local tomo directory does not exist: \$local_tomo_path" >&2
          exit 1
        fi
        ;;
    esac

    touch "${filename}_copy_done.txt"
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
    tuple val(filename), path(normalized_tomo), val(omezarr_path), val(req_mem)

    output:
    tuple val(filename), val(omezarr_path), emit: omezarr
    path "${filename}_conversion_done.txt"

    script:
    """
    set -euo pipefail

    input_path="${normalized_tomo}"
    output_path="${omezarr_path}"

    if [ ! -e "\$input_path" ]; then
      echo "Expected input path does not exist: \$input_path" >&2
      exit 1
    fi

    rm -rf "\$output_path"

    eubi to_zarr \
      "\$input_path" \
      "\$output_path" \
      --x_unit nm \
      --y_unit nm \
      --z_unit nm \
      --x_scale "${params.x_scale}" \
      --y_scale "${params.y_scale}" \
      --z_scale "${params.z_scale}" \
      --concatenation_axes z \
      --z_tag "Z" \
      --save_omexml True \
      --n_layers 11 \
      --zar_format "${params.zarr_format}" \
      --max_workers 1

    touch "${filename}_conversion_done.txt"
    """
}


process NORMALIZEHITTSLICES {

    cpus 1
    memory "32GB"
    time "60m"

    publishDir "${params.logdir}/slice_renaming", mode:"copy"
    containerOptions "--bind /g --bind /scratch --bind /home"

    input:
    tuple val(filename), val(tmp_copy_path), val(omezarr_path), val(req_mem)

    output:
    tuple val(filename), path("${filename}_normalized_tomo"), val(omezarr_path), val(req_mem), emit: normalized_images
    path "${filename}_slice_renaming.tsv"
    path "${filename}_uint16_metrics.tsv"

    script:
    """
    set -euo pipefail

    input_path="${tmp_copy_path}/${params.input_suffix}"
    normalized_path="${filename}_normalized_tomo"
    log_file="${filename}_slice_renaming.tsv"
    metrics_file="${filename}_uint16_metrics.tsv"

    if [ ! -d "\$input_path" ]; then
      echo "Expected tomo directory does not exist: \$input_path" >&2
      exit 1
    fi

    python3 "${params.script_dir}/prepare_slices.py" \
      --input-dir "\$input_path" \
      --output-dir "\$normalized_path" \
      --rename-log "\$log_file" \
      --metrics "\$metrics_file" \
      --convert-uint16 "${params.convert_uint16}" \
      --lower-percentile "${params.uint16_lower_percentile}" \
      --upper-percentile "${params.uint16_upper_percentile}" \
      --sample-values "${params.uint16_sample_values}"
    """
}


process EXTRACTHITTIMAGESTATS {

    cpus 1
    memory "2GB"
    time "20m"

    publishDir "${params.logdir}/image_stats", mode:"copy"
    containerOptions "--bind /g --bind /scratch --bind /home"

    input:
    tuple val(filename), path(normalized_tomo), val(omezarr_path), val(req_mem)

    output:
    path "${filename}_image_stats.tsv", emit: image_stats

    script:
    """
    python3 "${params.script_dir}/extract_stack_stats.py" \
      --input-dir "${normalized_tomo}" \
      --name "${filename}" \
      --output "${filename}_image_stats.tsv"
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

    mc cp "${omezarr_path}/" "${params.s3_bucket}/${filename}/" --recursive
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


process MAKEHITTCOLLECTIONTABLE {

    cpus 1
    memory "1GB"
    time "10m"

    publishDir "${params.logdir}", mode:"copy"
    containerOptions "--bind /g --bind /scratch --bind /home"

    input:
    path all_s3
    path all_datasets
    path image_stats

    output:
    path "done.tsv"
    path "hitt_collection_table.tsv", optional:true

    script:
    """
    Rscript "${params.script_dir}/make_collection_table.R" \
      --all_s3 "${all_s3}" \
      --all_datasets "${all_datasets}" \
      --image_stats_dir "." \
      --sheet_mode "${params.sheet_mode}" \
      --google_key "${params.google_key}" \
      --collection_table_url "${params.collection_table_url}" \
      --collection_table_sheet "${params.collection_table_sheet}" \
      --local_collection_table "hitt_collection_table.tsv"
    """
}


workflow {

    SELECTHITTIMAGES(
        params.input_table,
        params.sheet_mode,
        params.sheet_url,
        params.sheet_name,
        params.google_key,
        params.copy_dest_root,
        params.dryrun,
        params.dryrun_n
    )

    if (params.workflow_stage != "discover") {

        SELECTHITTIMAGES.out.to_process
            .splitCsv(header:true)
            .map { row -> tuple(row.filename, row.remote_tomo_path, row.tmp_copy_path, row.omezarr_path, row.req_mem) }
            .set { hitt_copy_batch_ch }

        COPYHITTDATA(hitt_copy_batch_ch)

        NORMALIZEHITTSLICES(COPYHITTDATA.out.copied_images)

        EUBIHITTCONVERSION(NORMALIZEHITTSLICES.out.normalized_images)
        EXTRACTHITTIMAGESTATS(NORMALIZEHITTSLICES.out.normalized_images)

        if (params.workflow_stage == "all") {
            upload_done_ch = S3UPLOADHITT(EUBIHITTCONVERSION.out.omezarr).collect()
            COLLECTHITTS3FILES(upload_done_ch)

            MAKEHITTCOLLECTIONTABLE(
                COLLECTHITTS3FILES.out.all_s3,
                SELECTHITTIMAGES.out.all_datasets,
                EXTRACTHITTIMAGESTATS.out.image_stats.collect()
            )
        }
    }
}
