#!/usr/bin/env bash
set -euo pipefail

PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
timestamp="$(date +%Y-%m-%d_%H-%M)"
resume="${RESUME:-TRUE}"
mode="${MODE:-interactive}"

usage() {
  cat <<EOF
Usage:
  bash plastic_main.sh [local|interactive|cluster] [options]

Options:
  --profile, --mode VALUE          Runtime profile: local, interactive, cluster.
  --input_table PATH               TSV/CSV table with a raw_path/file_path column.
  --sheet_mode VALUE               local or google, default depends on profile.
  --sheet_url URL                  Google Sheet URL for table input.
  --sheet_name VALUE               Google Sheet tab name. Empty/default reads the first tab.
  --google_key PATH                Google service-account JSON key.
  --collection_table_url URL       Google Sheet URL for collection table output.
  --collection_table_sheet VALUE   Output sheet name, default plastic_collection_table.
  --main_dir PATH                  Base PLASTIC workflow directory.
  --outdir PATH                    Converted-output directory.
  --logdir PATH                    Workflow log directory.
  --work_dir PATH                  Nextflow work directory.
  --workflow_stage VALUE           discover, process, all, or collection.
  --dryrun TRUE|FALSE              Limit to --dryrun_n rows when TRUE.
  --dryrun_n N                     Number of rows to process during dryrun.
  --s3_bucket VALUE                S3 bucket/prefix, default s3embl/plastictest.
  --zarr_format VALUE              OME-Zarr format version, default 2.
  --eubi_extra_args VALUE          Extra raw arguments appended to eubi to_zarr.
  --default_x_scale VALUE          Fallback X pixel size.
  --default_y_scale VALUE          Fallback Y pixel size.
  --default_z_scale VALUE          Fallback Z spacing.
  --scale_unit VALUE               Unit for sheet/default scales: nm, um, or mm.
  --persistent_metadata_dir PATH   Metadata cache used by collection-only mode.
  --resume TRUE|FALSE              Add Nextflow -resume when TRUE.
  --help                           Show this message.
EOF
}

to_upper_bool() {
  case "$1" in
    TRUE|true|1|yes|YES) echo "TRUE" ;;
    FALSE|false|0|no|NO) echo "FALSE" ;;
    *)
      echo "Boolean value must be TRUE or FALSE, got: $1" >&2
      exit 1
      ;;
  esac
}

if [[ $# -gt 0 && "${1:-}" != --* && "${1:-}" != "-resume" ]]; then
  mode="$1"
  shift
fi

scan_args=("$@")
for ((i = 0; i < ${#scan_args[@]}; i++)); do
  case "${scan_args[$i]}" in
    --profile|--mode)
      mode="${scan_args[$((i + 1))]:?${scan_args[$i]} requires a value}"
      ;;
    --profile=*|--mode=*)
      mode="${scan_args[$i]#*=}"
      ;;
  esac
done

case "$mode" in
  local)
    main_dir="${PLASTIC_SCREEN_DIR:-C:/projects/plastic_screen}"
    default_work_dir="${WORK_DIR:-${main_dir}/work}"
    profile="local"
    default_workflow_stage="discover"
    default_sheet_mode="local"
    default_dryrun="TRUE"
    ;;
  interactive)
    main_dir="${PLASTIC_SCREEN_DIR:-/scratch/rheinnec/plastic_screen}"
    default_work_dir="${WORK_DIR:-/scratch/rheinnec/plastic_screen/work}"
    profile="interactive"
    default_workflow_stage="all"
    default_sheet_mode="google"
    default_dryrun="FALSE"
    if command -v module >/dev/null 2>&1; then
      module load Nextflow/24.10.4
    fi
    ;;
  cluster)
    main_dir="${PLASTIC_SCREEN_DIR:-/scratch/rheinnec/plastic_screen}"
    default_work_dir="${WORK_DIR:-/scratch/rheinnec/plastic_screen/work}"
    profile="cluster"
    default_workflow_stage="all"
    default_sheet_mode="google"
    default_dryrun="FALSE"
    if command -v module >/dev/null 2>&1; then
      module load Nextflow/24.10.4
    fi
    ;;
  *)
    echo "Unknown profile: $mode" >&2
    usage
    exit 1
    ;;
esac

resume="$(to_upper_bool "$resume")"
workflow_stage="${WORKFLOW_STAGE:-$default_workflow_stage}"
sheet_mode="${SHEET_MODE:-$default_sheet_mode}"
dryrun="$(to_upper_bool "${DRYRUN:-$default_dryrun}")"
dryrun_n="${DRYRUN_N:-2}"
input_table="${INPUT_TABLE:-}"
sheet_url="${SHEET_URL:-}"
sheet_name="${SHEET_NAME:-}"
google_key="${GOOGLE_KEY:-${script_dir}/trec-tem-screen-e98a2e03f58b.json}"
collection_table_url="${COLLECTION_TABLE_URL:-}"
collection_table_sheet="${COLLECTION_TABLE_SHEET:-plastic_collection_table}"
outdir="${OUTDIR:-}"
logdir="${LOGDIR:-}"
work_dir="${WORK_DIR:-$default_work_dir}"
s3_bucket="${S3_BUCKET:-s3embl/plastictest}"
zarr_format="${ZARR_FORMAT:-2}"
eubi_extra_args="${EUBI_EXTRA_ARGS:-}"
default_x_scale="${DEFAULT_X_SCALE:-}"
default_y_scale="${DEFAULT_Y_SCALE:-}"
default_z_scale="${DEFAULT_Z_SCALE:-}"
scale_unit="${SCALE_UNIT:-nm}"
persistent_metadata_dir="${PERSISTENT_METADATA_DIR:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --profile|--mode)
      shift 2
      ;;
    --profile=*|--mode=*)
      shift
      ;;
    --resume)
      resume="$(to_upper_bool "${2:?--resume requires TRUE or FALSE}")"
      shift 2
      ;;
    --resume=*)
      resume="$(to_upper_bool "${1#*=}")"
      shift
      ;;
    -resume)
      resume="TRUE"
      shift
      ;;
    --dryrun)
      dryrun="$(to_upper_bool "${2:?--dryrun requires TRUE or FALSE}")"
      shift 2
      ;;
    --dryrun=*)
      dryrun="$(to_upper_bool "${1#*=}")"
      shift
      ;;
    --dryrun_n|--dryrun-n)
      dryrun_n="${2:?--dryrun_n requires a value}"
      shift 2
      ;;
    --dryrun_n=*|--dryrun-n=*)
      dryrun_n="${1#*=}"
      shift
      ;;
    --workflow_stage|--workflow-stage)
      workflow_stage="${2:?--workflow_stage requires a value}"
      shift 2
      ;;
    --workflow_stage=*|--workflow-stage=*)
      workflow_stage="${1#*=}"
      shift
      ;;
    --sheet_mode|--sheet-mode)
      sheet_mode="${2:?--sheet_mode requires a value}"
      shift 2
      ;;
    --sheet_mode=*|--sheet-mode=*)
      sheet_mode="${1#*=}"
      shift
      ;;
    --main_dir|--main-dir)
      main_dir="${2:?--main_dir requires a path}"
      shift 2
      ;;
    --main_dir=*|--main-dir=*)
      main_dir="${1#*=}"
      shift
      ;;
    --input_table|--input-table)
      input_table="${2:?--input_table requires a path}"
      shift 2
      ;;
    --input_table=*|--input-table=*)
      input_table="${1#*=}"
      shift
      ;;
    --sheet_url|--sheet-url)
      sheet_url="${2:?--sheet_url requires a URL}"
      shift 2
      ;;
    --sheet_url=*|--sheet-url=*)
      sheet_url="${1#*=}"
      shift
      ;;
    --sheet_name|--sheet-name)
      sheet_name="${2:?--sheet_name requires a value}"
      shift 2
      ;;
    --sheet_name=*|--sheet-name=*)
      sheet_name="${1#*=}"
      shift
      ;;
    --google_key|--google-key)
      google_key="${2:?--google_key requires a path}"
      shift 2
      ;;
    --google_key=*|--google-key=*)
      google_key="${1#*=}"
      shift
      ;;
    --collection_table_url|--collection-table-url)
      collection_table_url="${2:?--collection_table_url requires a URL}"
      shift 2
      ;;
    --collection_table_url=*|--collection-table-url=*)
      collection_table_url="${1#*=}"
      shift
      ;;
    --collection_table_sheet|--collection-table-sheet)
      collection_table_sheet="${2:?--collection_table_sheet requires a value}"
      shift 2
      ;;
    --collection_table_sheet=*|--collection-table-sheet=*)
      collection_table_sheet="${1#*=}"
      shift
      ;;
    --outdir)
      outdir="${2:?--outdir requires a path}"
      shift 2
      ;;
    --outdir=*)
      outdir="${1#*=}"
      shift
      ;;
    --logdir)
      logdir="${2:?--logdir requires a path}"
      shift 2
      ;;
    --logdir=*)
      logdir="${1#*=}"
      shift
      ;;
    --work_dir|--work-dir)
      work_dir="${2:?--work_dir requires a path}"
      shift 2
      ;;
    --work_dir=*|--work-dir=*)
      work_dir="${1#*=}"
      shift
      ;;
    --s3_bucket|--s3-bucket)
      s3_bucket="${2:?--s3_bucket requires a value}"
      shift 2
      ;;
    --s3_bucket=*|--s3-bucket=*)
      s3_bucket="${1#*=}"
      shift
      ;;
    --zarr_format|--zarr-format)
      zarr_format="${2:?--zarr_format requires a value}"
      shift 2
      ;;
    --zarr_format=*|--zarr-format=*)
      zarr_format="${1#*=}"
      shift
      ;;
    --eubi_extra_args|--eubi-extra-args)
      eubi_extra_args="${2:?--eubi_extra_args requires a value}"
      shift 2
      ;;
    --eubi_extra_args=*|--eubi-extra-args=*)
      eubi_extra_args="${1#*=}"
      shift
      ;;
    --default_x_scale|--default-x-scale)
      default_x_scale="${2:?--default_x_scale requires a value}"
      shift 2
      ;;
    --default_x_scale=*|--default-x-scale=*)
      default_x_scale="${1#*=}"
      shift
      ;;
    --default_y_scale|--default-y-scale)
      default_y_scale="${2:?--default_y_scale requires a value}"
      shift 2
      ;;
    --default_y_scale=*|--default-y-scale=*)
      default_y_scale="${1#*=}"
      shift
      ;;
    --default_z_scale|--default-z-scale)
      default_z_scale="${2:?--default_z_scale requires a value}"
      shift 2
      ;;
    --default_z_scale=*|--default-z-scale=*)
      default_z_scale="${1#*=}"
      shift
      ;;
    --scale_unit|--scale-unit)
      scale_unit="${2:?--scale_unit requires a value}"
      shift 2
      ;;
    --scale_unit=*|--scale-unit=*)
      scale_unit="${1#*=}"
      shift
      ;;
    --persistent_metadata_dir|--persistent-metadata-dir)
      persistent_metadata_dir="${2:?--persistent_metadata_dir requires a path}"
      shift 2
      ;;
    --persistent_metadata_dir=*|--persistent-metadata-dir=*)
      persistent_metadata_dir="${1#*=}"
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

input_table="${input_table:-${main_dir}/plastic_images.tsv}"
outdir="${outdir:-${main_dir}/processed}"
logdir="${logdir:-${main_dir}/logs/wfPLASTIC_${timestamp}}"
persistent_metadata_dir="${persistent_metadata_dir:-${main_dir}/metadata}"

mkdir -p "$logdir" "$outdir" "$work_dir" "$persistent_metadata_dir"
cd "$main_dir"

nextflow_args=(
  run "${script_dir}/wfPLASTIC.nf"
  -c "${script_dir}/nextflow.config"
  -work-dir "$work_dir"
  --script_dir "$script_dir"
  --logdir "$logdir"
  --outdir "$outdir"
  --input_table "$input_table"
  --sheet_mode "$sheet_mode"
  --sheet_url "$sheet_url"
  --sheet_name "$sheet_name"
  --google_key "$google_key"
  --collection_table_url "$collection_table_url"
  --collection_table_sheet "$collection_table_sheet"
  --workflow_stage "$workflow_stage"
  --dryrun "$dryrun"
  --dryrun_n "$dryrun_n"
  --s3_bucket "$s3_bucket"
  --zarr_format "$zarr_format"
  --eubi_extra_args "$eubi_extra_args"
  --default_x_scale "$default_x_scale"
  --default_y_scale "$default_y_scale"
  --default_z_scale "$default_z_scale"
  --scale_unit "$scale_unit"
  --persistent_metadata_dir "$persistent_metadata_dir"
  -profile "$profile"
)

if [ "$resume" = "TRUE" ]; then
  nextflow_args+=("-resume")
fi

nextflow "${nextflow_args[@]}"
