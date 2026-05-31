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
  bash hitt_main.sh [local|interactive|cluster] [options]

Options:
  --profile, --mode VALUE          Runtime profile: local, interactive, cluster.
  --input_table PATH               TSV/CSV table with a tmp_copy_path column.
  --sheet_mode VALUE               local or google, default depends on profile.
  --sheet_url URL                  Google Sheet URL for table input.
  --sheet_name VALUE               Google Sheet tab name. Empty/default reads the first tab.
  --google_key PATH                Google service-account JSON key.
  --collection_table_url URL       Google Sheet URL for collection table output.
  --collection_table_sheet VALUE   Output sheet name, default hitt_collection_table.
  --main_dir PATH                  Base HITT workflow directory.
  --logdir PATH                    Workflow log directory.
  --work_dir PATH                  Nextflow work directory.
  --workflow_stage VALUE           discover, process, or all.
  --dryrun TRUE|FALSE              Limit to --dryrun_n rows when TRUE.
  --dryrun_n N                     Number of rows to process during dryrun.
  --s3_bucket VALUE                S3 bucket/prefix, default s3embl/hitttest.
  --x_scale VALUE                  X pixel scale in nm, default 100.
  --y_scale VALUE                  Y pixel scale in nm, default 100.
  --input_suffix PATH              Path below tmp_copy_path, default recon_111_1/tomo.
  --output_name NAME               Output folder below tmp_copy_path, default omezarr.
  --overwrite TRUE|FALSE           Kept for compatibility; conversion currently always rebuilds output.
  --convert_uint16 TRUE|FALSE      Stage uint16 TIFFs when TRUE; preserve original dtype when FALSE.
  --uint16_lower_percentile VALUE  Lower stack-wide clipping percentile, default 0.1.
  --uint16_upper_percentile VALUE  Upper stack-wide clipping percentile, default 99.9.
  --uint16_sample_values N         Approximate sampled pixels per stack, default 2000000.
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
    main_dir="${HITT_SCREEN_DIR:-C:/projects/hitt_screen}"
    default_work_dir="${WORK_DIR:-${main_dir}/work}"
    profile="local"
    default_workflow_stage="discover"
    default_sheet_mode="local"
    default_dryrun="TRUE"
    ;;
  interactive)
    main_dir="${HITT_SCREEN_DIR:-/scratch/rheinnec/hitt_screen}"
    default_work_dir="${WORK_DIR:-/scratch/rheinnec/hitt_screen/work}"
    profile="interactive"
    default_workflow_stage="process"
    default_sheet_mode="google"
    default_dryrun="FALSE"
    if command -v module >/dev/null 2>&1; then
      module load Nextflow/24.10.4
    fi
    ;;
  cluster)
    main_dir="${HITT_SCREEN_DIR:-/scratch/rheinnec/hitt_screen}"
    default_work_dir="${WORK_DIR:-/scratch/rheinnec/hitt_screen/work}"
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
sheet_url="${SHEET_URL:-https://docs.google.com/spreadsheets/d/1ePRpa56mmMvCeRTLXmwOywOLy5_I3AFrxJepSUYGR1s/edit?gid=0#gid=0}"
sheet_name="${SHEET_NAME:-all_hitt}"
google_key="${GOOGLE_KEY:-${script_dir}/trec-tem-screen-e98a2e03f58b.json}"
collection_table_url="${COLLECTION_TABLE_URL:-https://docs.google.com/spreadsheets/d/1ePRpa56mmMvCeRTLXmwOywOLy5_I3AFrxJepSUYGR1s/edit?gid=1582290308#gid=1582290308}"
collection_table_sheet="${COLLECTION_TABLE_SHEET:-hitt_collection_table}"
logdir="${LOGDIR:-}"
work_dir="${WORK_DIR:-$default_work_dir}"
s3_bucket="${S3_BUCKET:-s3embl/hitttest}"
x_scale="${X_SCALE:-650}"
y_scale="${Y_SCALE:-650}"
z_scale="${Z_SCALE:-650}"
input_suffix="${INPUT_SUFFIX:-recon_111_1/tomo}"
output_name="${OUTPUT_NAME:-omezarr}"
overwrite="$(to_upper_bool "${OVERWRITE:-TRUE}")"
convert_uint16="$(to_upper_bool "${CONVERT_UINT16:-TRUE}")"
uint16_lower_percentile="${UINT16_LOWER_PERCENTILE:-0.1}"
uint16_upper_percentile="${UINT16_UPPER_PERCENTILE:-99.9}"
uint16_sample_values="${UINT16_SAMPLE_VALUES:-2000000}"

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
    --x_scale|--x-scale)
      x_scale="${2:?--x_scale requires a value}"
      shift 2
      ;;
    --x_scale=*|--x-scale=*)
      x_scale="${1#*=}"
      shift
      ;;
    --y_scale|--y-scale)
      y_scale="${2:?--y_scale requires a value}"
      shift 2
      ;;
    --y_scale=*|--y-scale=*)
      y_scale="${1#*=}"
      shift
      ;;
    --z_scale|--z-scale)
      z_scale="${2:?--z_scale requires a value}"
      shift 2
      ;;
    --z_scale=*|--z-scale=*)
      z_scale="${1#*=}"
      shift
      ;;
    --input_suffix|--input-suffix)
      input_suffix="${2:?--input_suffix requires a value}"
      shift 2
      ;;
    --input_suffix=*|--input-suffix=*)
      input_suffix="${1#*=}"
      shift
      ;;
    --output_name|--output-name)
      output_name="${2:?--output_name requires a value}"
      shift 2
      ;;
    --output_name=*|--output-name=*)
      output_name="${1#*=}"
      shift
      ;;
    --overwrite)
      overwrite="$(to_upper_bool "${2:?--overwrite requires TRUE or FALSE}")"
      shift 2
      ;;
    --overwrite=*)
      overwrite="$(to_upper_bool "${1#*=}")"
      shift
      ;;
    --convert_uint16|--convert-uint16)
      convert_uint16="$(to_upper_bool "${2:?--convert_uint16 requires TRUE or FALSE}")"
      shift 2
      ;;
    --convert_uint16=*|--convert-uint16=*)
      convert_uint16="$(to_upper_bool "${1#*=}")"
      shift
      ;;
    --uint16_lower_percentile|--uint16-lower-percentile)
      uint16_lower_percentile="${2:?--uint16_lower_percentile requires a value}"
      shift 2
      ;;
    --uint16_lower_percentile=*|--uint16-lower-percentile=*)
      uint16_lower_percentile="${1#*=}"
      shift
      ;;
    --uint16_upper_percentile|--uint16-upper-percentile)
      uint16_upper_percentile="${2:?--uint16_upper_percentile requires a value}"
      shift 2
      ;;
    --uint16_upper_percentile=*|--uint16-upper-percentile=*)
      uint16_upper_percentile="${1#*=}"
      shift
      ;;
    --uint16_sample_values|--uint16-sample-values)
      uint16_sample_values="${2:?--uint16_sample_values requires a value}"
      shift 2
      ;;
    --uint16_sample_values=*|--uint16-sample-values=*)
      uint16_sample_values="${1#*=}"
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

input_table="${input_table:-${main_dir}/hitt_images.tsv}"
logdir="${logdir:-${main_dir}/logs/wfHITT_${timestamp}}"

mkdir -p "$logdir" "$work_dir"
cd "$main_dir"

nextflow_args=(
  run "${script_dir}/wfHITT.nf"
  -c "${script_dir}/nextflow.config"
  -work-dir "$work_dir"
  --script_dir "$script_dir"
  --logdir "$logdir"
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
  --x_scale "$x_scale"
  --y_scale "$y_scale"
  --z_scale "$z_scale"
  --input_suffix "$input_suffix"
  --output_name "$output_name"
  --overwrite "$overwrite"
  --convert_uint16 "$convert_uint16"
  --uint16_lower_percentile "$uint16_lower_percentile"
  --uint16_upper_percentile "$uint16_upper_percentile"
  --uint16_sample_values "$uint16_sample_values"
  -profile "$profile"
)

if [ "$resume" = "TRUE" ]; then
  nextflow_args+=("-resume")
fi

nextflow "${nextflow_args[@]}"
