params.input_table = params.input_table ?: "exm_images.tsv"
params.sheet_mode = params.sheet_mode ?: "local"
params.sheet_url = params.sheet_url ?: ""
params.sheet_name = params.sheet_name ?: ""
params.google_key = params.google_key ?: "${params.script_dir}/trec-tem-screen-e98a2e03f58b.json"
params.collection_table_url = params.collection_table_url ?: ""
params.collection_table_sheet = params.collection_table_sheet ?: "exm_collection_table"
params.local_collection_table = params.local_collection_table ?: "${params.logdir}/exm_collection_table.tsv"
params.dryrun = params.dryrun ?: "TRUE"
params.dryrun_n = params.dryrun_n ?: 2
params.script_dir = params.script_dir ?: baseDir.toString()
params.outdir = params.outdir ?: "exm_processed"
params.logdir = params.logdir ?: "exm_logs"
params.workflow_stage = params.workflow_stage ?: "discover"
// s3_bucket only sets the public URLs in the collection table, the data is copied into publish_dir
// (the S3 share mounted on /g, same bucket path)
params.s3_bucket = params.s3_bucket ?: "s3test/imatrec/central_data_processing/exm"
params.publish_dir = params.publish_dir ?: "/g/schwab/s3-public/imatrec/central_data_processing/exm"
params.zarr_format = params.zarr_format ?: 3
params.eubi_time = params.eubi_time ?: "2h"
params.default_x_scale = params.default_x_scale ?: ""
params.default_y_scale = params.default_y_scale ?: ""
params.default_z_scale = params.default_z_scale ?: ""
params.scale_unit = params.scale_unit ?: "nm"
params.persistent_metadata_dir = params.persistent_metadata_dir ?: "${params.outdir}/metadata"


process CHECKEXISTINGEXMS3FILES {

    cpus 1
    memory "1GB"
    time "1h"

    publishDir "${params.logdir}", mode:"copy"
    containerOptions "--bind /g --bind /scratch --bind /home"

    input:
    val publish_dir
    val workflow_stage
    val dryrun

    output:
    path "existing_s3_entries.txt", emit: existing_s3
    path "existing_s3_entries_all.txt"
    path "incomplete_s3_entries.txt"

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

    : > "existing_s3_entries_all.txt"
    : > "existing_s3_entries.txt"
    : > "incomplete_s3_entries.txt"

    if [ ! -d "${publish_dir}" ]; then
      if [ "\$require_s3" = "TRUE" ]; then
        echo "${publish_dir} is not accessible; refusing to continue because this run depends on skip detection." >&2
        exit 1
      fi
      exit 0
    fi

    # a dataset only counts as present when its root metadata exists: zarr.json (zarr v3) or .zattrs (v2).
    # PATCHEXMOMEZARRMETADATA copies into a hidden .partial directory and renames it when complete,
    # an incomplete dataset is listed in incomplete_s3_entries.txt and processed again.
    for entry in "${publish_dir}"/*/; do
      [ -d "\$entry" ] || continue
      name=\$(basename "\$entry")
      echo "\$name/" >> "existing_s3_entries_all.txt"
      if [ -e "\$entry/zarr.json" ] || [ -e "\$entry/.zattrs" ]; then
        echo "\$name/" >> "existing_s3_entries.txt"
      else
        echo "\$name" >> "incomplete_s3_entries.txt"
      fi
    done
    """
}


process SELECTEXMIMAGES {

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


process EXTRACTEXMMETADATA {

    tag "${filename}"
    cpus 1
    memory "2GB"
    time "20m"

    publishDir "${params.logdir}/metadata", mode:"copy"
    containerOptions "--bind /g --bind /scratch --bind /home"
    errorStrategy "ignore"

    input:
    tuple val(filename), val(raw_path), val(output_path), val(x_scale_override), val(y_scale_override), val(z_scale_override), val(scale_unit), val(req_mem)

    output:
    tuple val(filename), val(raw_path), val(output_path), path("${filename}_metadata.json"), path("${filename}_pixel_size.tsv"), path("${filename}_nd2_metadata.json"), val(req_mem), emit: metadata
    path "${filename}_metadata.json", emit: metadata_json

    script:
    """
    set -euo pipefail

    python3 "${params.script_dir}/extract_metadata.py" \
      --input "${raw_path}" \
      --name "${filename}" \
      --metadata-json "${filename}_metadata.json" \
      --pixel-size-tsv "${filename}_pixel_size.tsv" \
      --raw-metadata-json "${filename}_nd2_metadata.json" \
      --x-scale "${x_scale_override}" \
      --y-scale "${y_scale_override}" \
      --z-scale "${z_scale_override}" \
      --scale-unit "${scale_unit}"

    mkdir -p "${params.persistent_metadata_dir}"
    metadata_tmp="${params.persistent_metadata_dir}/${filename}_metadata.json.tmp.\$\$"
    pixel_tmp="${params.persistent_metadata_dir}/${filename}_pixel_size.tsv.tmp.\$\$"
    raw_metadata_tmp="${params.persistent_metadata_dir}/${filename}_nd2_metadata.json.tmp.\$\$"
    cp "${filename}_metadata.json" "\$metadata_tmp"
    cp "${filename}_pixel_size.tsv" "\$pixel_tmp"
    cp "${filename}_nd2_metadata.json" "\$raw_metadata_tmp"
    mv "\$metadata_tmp" "${params.persistent_metadata_dir}/${filename}_metadata.json"
    mv "\$pixel_tmp" "${params.persistent_metadata_dir}/${filename}_pixel_size.tsv"
    mv "\$raw_metadata_tmp" "${params.persistent_metadata_dir}/${filename}_nd2_metadata.json"
    """
}


process PREPAREEXMINPUT {

    tag "${filename}"
    cpus 1
    memory { "${Math.min(Math.max((req_mem as Integer), 16), 128)}GB" }
    time "2h"

    publishDir "${params.logdir}/prepared_inputs", mode:"copy", pattern:"*_prepared_input.tsv"
    containerOptions "--bind /g --bind /scratch --bind /home"
    errorStrategy "ignore"

    input:
    tuple val(filename), val(raw_path), val(output_path), path(metadata_json), path(pixel_size_tsv), path(raw_metadata_json), val(req_mem)

    output:
    tuple val(filename), path("prepared_input"), val(output_path), path(metadata_json), path(pixel_size_tsv), path(raw_metadata_json), val(req_mem), emit: prepared
    path "${filename}_prepared_input.tsv"

    script:
    """
    set -euo pipefail

    python3 "${params.script_dir}/prepare_input.py" \
      --name "${filename}" \
      --output-dir "prepared_input" \
      --metadata-json "${metadata_json}" \
      --prepared-log "${filename}_prepared_input.tsv"

    mkdir -p "${params.persistent_metadata_dir}"
    metadata_tmp="${params.persistent_metadata_dir}/${filename}_metadata.json.tmp.\$\$"
    cp "${metadata_json}" "\$metadata_tmp"
    mv "\$metadata_tmp" "${params.persistent_metadata_dir}/${filename}_metadata.json"
    """
}


process EUBIEXMCONVERSION {

    tag "${filename}"
    cpus 1
    // eubi peaks at ~3.3x the prepared OME-TIFF (35 GB for a 10.6 GB 4 x 250 x 2304 x 2304 stack, incl. the 8 GB JVM heap)
    // -> 4x the input + 8 GB, at least req_mem from the sheet
    // (input_gb is measured in the workflow block: inside this closure the staged input path is not resolvable)
    memory { "${Math.min(Math.max(Math.max((req_mem as Integer), 16), Math.ceil(4 * (input_gb as Double) + 8) as Integer), 192)}GB" }
    // timed-out images can be rerun with --eubi_time 6h (completed ones are on S3 and skipped)
    time "${params.eubi_time}"

    containerOptions "--bind /g --bind /scratch --bind /home"
    errorStrategy "ignore"

    input:
    tuple val(filename), path(prepared_input), val(output_path), path(metadata_json), path(pixel_size_tsv), path(raw_metadata_json), val(req_mem), val(input_gb)

    output:
    tuple val(filename), path("${filename}.ome.zarr"), path(metadata_json), path(raw_metadata_json), emit: omezarr
    path "${filename}_conversion_done.txt"

    script:
    """
    set -euo pipefail

    input_path=\$(find -L "${prepared_input}" -mindepth 1 -maxdepth 1 -type f | sort | head -n 1)
    if [ -z "\$input_path" ]; then
      echo "Prepared input directory is empty for ${filename}: ${prepared_input}" >&2
      ls -la "${prepared_input}" >&2 || true
      exit 1
    fi

    pixel_scale_x=\$(awk 'NR==2 {print \$1}' "${pixel_size_tsv}")
    pixel_scale_y=\$(awk 'NR==2 {print \$2}' "${pixel_size_tsv}")
    pixel_scale_z=\$(awk 'NR==2 {print \$3}' "${pixel_size_tsv}")

    if [ -z "\$pixel_scale_x" ] || [ -z "\$pixel_scale_y" ] || [ -z "\$pixel_scale_z" ]; then
      echo "Missing x/y/z scale values for ${filename}; add metadata to the file or sheet overrides." >&2
      exit 1
    fi

    rm -rf "${filename}.ome.zarr"

    # --overwrite True: if a eubi worker process dies (e.g. out of memory), eubi retries the scene once in a new
    # process; without overwrite that retry fails on the half-written array ("ContainsArrayError ... /0")

    eubi to_zarr \
      "\$input_path" \
      "${filename}.ome.zarr" \
      --x_unit nm \
      --y_unit nm \
      --z_unit nm \
      --x_scale "\${pixel_scale_x}" \
      --y_scale "\${pixel_scale_y}" \
      --z_scale "\${pixel_scale_z}" \
      --dimension_order xyzct \
      --squeeze True \
      --save_omexml True \
      --zarr_format "${params.zarr_format}" \
      --overwrite True \
      --auto_chunk True \
      --jvm_memory 8GB \
      --max_workers 1

    touch "${filename}_conversion_done.txt"
    """
}


process PATCHEXMOMEZARRMETADATA {

    tag "${filename}"
    cpus 1
    memory "1GB"
    time "2h"

    publishDir "${params.logdir}/omezarr_metadata", mode:"copy", pattern:"*_omezarr_metadata.tsv"
    containerOptions "--bind /g --bind /scratch --bind /home"
    errorStrategy "ignore"

    input:
    tuple val(filename), path(omezarr), path(metadata_json), path(raw_metadata_json)

    output:
    path "${filename}_omezarr_metadata.tsv"
    path "${filename}_published.txt", emit: published

    script:
    """
    set -euo pipefail

    python3 "${params.script_dir}/patch_omezarr_metadata.py" \
      --omezarr "${omezarr}" \
      --metadata-json "${metadata_json}" \
      --raw-metadata-json "${raw_metadata_json}" \
      --log "${filename}_omezarr_metadata.tsv"

    # eubi writes <name>.ome.zarr/<name>.zarr -> publish the directory holding the root metadata
    image_zarr="${omezarr}"
    if [ ! -e "\${image_zarr}/zarr.json" ] && [ ! -e "\${image_zarr}/.zattrs" ] && [ ! -e "\${image_zarr}/.zgroup" ]; then
      for candidate in "\${image_zarr}"/*.zarr "\${image_zarr}"/*.ome.zarr "\${image_zarr}"/*/*.zarr "\${image_zarr}"/*/*.ome.zarr; do
        if [ -d "\$candidate" ]; then
          image_zarr="\$candidate"
          break
        fi
      done
    fi
    if [ ! -e "\${image_zarr}/zarr.json" ] && [ ! -e "\${image_zarr}/.zattrs" ] && [ ! -e "\${image_zarr}/.zgroup" ]; then
      echo "Could not find an OME-Zarr root marker under ${omezarr}" >&2
      ls -la "${omezarr}" >&2 || true
      exit 1
    fi

    # publish into the mounted S3 share (only for --workflow_stage all): copy into a hidden .partial directory
    # and rename it at the end, so an interrupted copy never looks like a complete dataset
    if [ "${params.workflow_stage}" = "all" ]; then
      target="${params.publish_dir}/${filename}.ome.zarr"
      partial="${params.publish_dir}/.${filename}.ome.zarr.partial"
      mkdir -p "${params.publish_dir}"
      rm -rf "\$partial"
      mkdir "\$partial"
      cp -rL "\${image_zarr}/." "\$partial/"
      rm -rf "\$target"
      mv "\$partial" "\$target"
      echo "\$target" > "${filename}_published.txt"
    else
      echo "not published (workflow_stage ${params.workflow_stage})" > "${filename}_published.txt"
    fi
    """
}


process COLLECTEXMS3FILES {

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
    set -euo pipefail

    # complete datasets in the mounted S3 share (root metadata present)
    : > all_s3_entries.txt
    for entry in "${params.publish_dir}"/*/; do
      [ -d "\$entry" ] || continue
      if [ -e "\$entry/zarr.json" ] || [ -e "\$entry/.zattrs" ]; then
        echo "\$(basename "\$entry")/" >> all_s3_entries.txt
      fi
    done
    """
}


process MAKEEXMCOLLECTIONTABLE {

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
    path "exm_collection_table.tsv", optional:true

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
      --local_collection_table "exm_collection_table.tsv"
    """
}


workflow {

    CHECKEXISTINGEXMS3FILES(
        params.publish_dir,
        params.workflow_stage,
        params.dryrun
    )

    SELECTEXMIMAGES(
        params.input_table,
        params.sheet_mode,
        params.sheet_url,
        params.sheet_name,
        params.google_key,
        params.outdir,
        params.dryrun,
        params.dryrun_n,
        CHECKEXISTINGEXMS3FILES.out.existing_s3,
        params.default_x_scale,
        params.default_y_scale,
        params.default_z_scale,
        params.scale_unit
    )

    if (params.workflow_stage != "discover" && params.workflow_stage != "collection") {

        SELECTEXMIMAGES.out.to_process
            .splitCsv(header:true)
            .map { row -> tuple(row.filename, row.raw_path, row.output_path, row.x_scale, row.y_scale, row.z_scale, row.scale_unit, row.req_mem) }
            .set { exm_batch_ch }

        EXTRACTEXMMETADATA(exm_batch_ch)

        PREPAREEXMINPUT(EXTRACTEXMMETADATA.out.metadata)

        // size of the prepared OME-TIFF in GB, sets the memory of the conversion job
        EUBIEXMCONVERSION(
            PREPAREEXMINPUT.out.prepared.map { filename, prepared_input, output_path, metadata_json, pixel_size_tsv, raw_metadata_json, req_mem ->
                def files = prepared_input.toFile().listFiles()
                def input_gb = files ? files.collect { it.length() }.sum() / 1e9 : 0
                tuple(filename, prepared_input, output_path, metadata_json, pixel_size_tsv, raw_metadata_json, req_mem, input_gb)
            }
        )
        PATCHEXMOMEZARRMETADATA(EUBIEXMCONVERSION.out.omezarr)

        if (params.workflow_stage == "all") {
            COLLECTEXMS3FILES(PATCHEXMOMEZARRMETADATA.out.published.collect())

            metadata_jsons_ch = EXTRACTEXMMETADATA.out.metadata_json.collect()
            MAKEEXMCOLLECTIONTABLE(
                COLLECTEXMS3FILES.out.all_s3,
                SELECTEXMIMAGES.out.all_datasets,
                params.persistent_metadata_dir,
                metadata_jsons_ch
            )
        }
    }

    if (params.workflow_stage == "collection") {
        COLLECTEXMS3FILES(Channel.value("collection_table_only"))

        MAKEEXMCOLLECTIONTABLE(
            COLLECTEXMS3FILES.out.all_s3,
            SELECTEXMIMAGES.out.all_datasets,
            params.persistent_metadata_dir,
            Channel.value("stored_metadata_ready")
        )
    }
}
