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
  --input_table PATH               TSV/CSV table with a source_path column.
  --sheet_mode VALUE               local or google, default depends on profile.
  --sheet_url URL                  Google Sheet URL for table input.
  --sheet_name VALUE               Google Sheet tab name. Empty/default reads the first tab.
  --google_key PATH                Google service-account JSON key.
  --collection_table_url URL       Google Sheet URL for collection table output.
  --collection_table_sheet VALUE   Output sheet name, default hitt_collection_table.
  --main_dir PATH                  Base HITT workflow directory.
  --logdir PATH                    Workflow log directory.
  --work_dir PATH                  Nextflow work directory.
  --workflow_stage VALUE           discover, process, all, or collection.
  --dryrun TRUE|FALSE              Limit to --dryrun_n rows when TRUE.
  --dryrun_n N                     Number of rows to process during dryrun.
  --s3_bucket VALUE                S3 bucket/prefix, default s3embl/hitttest.
  --x_scale VALUE                  X pixel scale in nm, default 650.
  --y_scale VALUE                  Y pixel scale in nm, default 650.
  --z_scale VALUE                  Z pixel scale in nm, default 650.
  --input_suffix PATH              Path below tmp_copy_path, default recon_111_1/tomo.
  --output_name NAME               Output folder below tmp_copy_path, default omezarr.
  --overwrite [TRUE|FALSE]         Reprocess convert=1 rows and replace matching S3 prefixes.
  --convert_uint16 TRUE|FALSE      Stage uint16 TIFFs when TRUE; preserve original dtype when FALSE.
  --uint16_lower_percentile VALUE  Lower stack-wide clipping percentile, default 0.1.
  --uint16_upper_percentile VALUE  Upper stack-wide clipping percentile, default 99.9.
  --uint16_sample_values N         Approximate sampled pixels per stack, default 2000000.
  --copy_data TRUE|FALSE           Copy remote tomo stacks into scratch before processing.
  --copy_dest_root PATH            Local scratch destination, default /scratch/rheinnec/tmp_hitt.
  --copy_max_forks N               Maximum concurrent remote copy jobs, default 10.
  --persistent_image_stats_dir PATH Persistent image-statistics directory.
  --crop_stack TRUE|FALSE          Detect and keep a conservative sample-bearing Z range.
  --crop_bright_threshold VALUE    Bright voxel threshold or auto, default auto.
  --crop_auto_percentile VALUE     Stack percentile used as auto threshold, default 99.
  --crop_min_bright_fraction VALUE Minimum bright sampled-pixel fraction per slice, default 0.005.
  --crop_padding_slices N          Compatibility shortcut: set padding on both edges.
  --crop_padding_low_slices N      Extra slices retained on the low-Z edge, default 10.
  --crop_padding_high_slices N     Extra slices retained on the high-Z edge, default 10.
  --crop_bridge_gap_slices N       Fill short detection gaps up to this size, default 3.
  --crop_min_run_slices N          Minimum detected run size, default 3.
  --crop_sample_values_per_slice N Approximate sampled pixels per slice, default 100000.
  --remote_user VALUE              SSH username, default p3l-yschwab.
  --remote_host VALUE              SSH host, default cerberus.embl-hamburg.de.
  --remote_port VALUE              SSH port, default 22443.
  --password VALUE                 SSH password passed through the workflow environment.
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
    default_workflow_stage="all"
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
overwrite="$(to_upper_bool "${OVERWRITE:-FALSE}")"
convert_uint16="$(to_upper_bool "${CONVERT_UINT16:-TRUE}")"
uint16_lower_percentile="${UINT16_LOWER_PERCENTILE:-0.1}"
uint16_upper_percentile="${UINT16_UPPER_PERCENTILE:-99.9}"
uint16_sample_values="${UINT16_SAMPLE_VALUES:-2000000}"
copy_data="$(to_upper_bool "${COPY_DATA:-TRUE}")"
copy_dest_root="${COPY_DEST_ROOT:-/scratch/rheinnec/tmp_hitt}"
copy_max_forks="${COPY_MAX_FORKS:-10}"
persistent_image_stats_dir="${PERSISTENT_IMAGE_STATS_DIR:-/g/schwab/marco/central_data_processing/hitt/image_stats}"
crop_stack="$(to_upper_bool "${CROP_STACK:-TRUE}")"
crop_bright_threshold="${CROP_BRIGHT_THRESHOLD:-auto}"
crop_auto_percentile="${CROP_AUTO_PERCENTILE:-99.0}"
crop_min_bright_fraction="${CROP_MIN_BRIGHT_FRACTION:-0.005}"
crop_padding_slices="${CROP_PADDING_SLICES:-10}"
crop_padding_low_slices="${CROP_PADDING_LOW_SLICES:-$crop_padding_slices}"
crop_padding_high_slices="${CROP_PADDING_HIGH_SLICES:-$crop_padding_slices}"
crop_bridge_gap_slices="${CROP_BRIDGE_GAP_SLICES:-3}"
crop_min_run_slices="${CROP_MIN_RUN_SLICES:-3}"
crop_sample_values_per_slice="${CROP_SAMPLE_VALUES_PER_SLICE:-100000}"
remote_user="${REMOTE_USER:-p3l-yschwab}"
remote_host="${REMOTE_HOST:-cerberus.embl-hamburg.de}"
remote_port="${REMOTE_PORT:-22443}"
password="${HITT_SSHPASS:-}"

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
      if [[ $# -gt 1 && "${2:-}" != --* ]]; then
        overwrite="$(to_upper_bool "$2")"
        shift 2
      else
        overwrite="TRUE"
        shift
      fi
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
    --copy_data|--copy-data)
      copy_data="$(to_upper_bool "${2:?--copy_data requires TRUE or FALSE}")"
      shift 2
      ;;
    --copy_data=*|--copy-data=*)
      copy_data="$(to_upper_bool "${1#*=}")"
      shift
      ;;
    --copy_dest_root|--copy-dest-root)
      copy_dest_root="${2:?--copy_dest_root requires a path}"
      shift 2
      ;;
    --copy_dest_root=*|--copy-dest-root=*)
      copy_dest_root="${1#*=}"
      shift
      ;;
    --copy_max_forks|--copy-max-forks)
      copy_max_forks="${2:?--copy_max_forks requires a value}"
      shift 2
      ;;
    --copy_max_forks=*|--copy-max-forks=*)
      copy_max_forks="${1#*=}"
      shift
      ;;
    --persistent_image_stats_dir|--persistent-image-stats-dir)
      persistent_image_stats_dir="${2:?--persistent_image_stats_dir requires a path}"
      shift 2
      ;;
    --persistent_image_stats_dir=*|--persistent-image-stats-dir=*)
      persistent_image_stats_dir="${1#*=}"
      shift
      ;;
    --crop_stack|--crop-stack)
      crop_stack="$(to_upper_bool "${2:?--crop_stack requires TRUE or FALSE}")"
      shift 2
      ;;
    --crop_stack=*|--crop-stack=*)
      crop_stack="$(to_upper_bool "${1#*=}")"
      shift
      ;;
    --crop_bright_threshold|--crop-bright-threshold)
      crop_bright_threshold="${2:?--crop_bright_threshold requires a value}"
      shift 2
      ;;
    --crop_bright_threshold=*|--crop-bright-threshold=*)
      crop_bright_threshold="${1#*=}"
      shift
      ;;
    --crop_auto_percentile|--crop-auto-percentile)
      crop_auto_percentile="${2:?--crop_auto_percentile requires a value}"
      shift 2
      ;;
    --crop_auto_percentile=*|--crop-auto-percentile=*)
      crop_auto_percentile="${1#*=}"
      shift
      ;;
    --crop_min_bright_fraction|--crop-min-bright-fraction)
      crop_min_bright_fraction="${2:?--crop_min_bright_fraction requires a value}"
      shift 2
      ;;
    --crop_min_bright_fraction=*|--crop-min-bright-fraction=*)
      crop_min_bright_fraction="${1#*=}"
      shift
      ;;
    --crop_padding_slices|--crop-padding-slices)
      crop_padding_slices="${2:?--crop_padding_slices requires a value}"
      crop_padding_low_slices="$crop_padding_slices"
      crop_padding_high_slices="$crop_padding_slices"
      shift 2
      ;;
    --crop_padding_slices=*|--crop-padding-slices=*)
      crop_padding_slices="${1#*=}"
      crop_padding_low_slices="$crop_padding_slices"
      crop_padding_high_slices="$crop_padding_slices"
      shift
      ;;
    --crop_padding_low_slices|--crop-padding-low-slices)
      crop_padding_low_slices="${2:?--crop_padding_low_slices requires a value}"
      shift 2
      ;;
    --crop_padding_low_slices=*|--crop-padding-low-slices=*)
      crop_padding_low_slices="${1#*=}"
      shift
      ;;
    --crop_padding_high_slices|--crop-padding-high-slices)
      crop_padding_high_slices="${2:?--crop_padding_high_slices requires a value}"
      shift 2
      ;;
    --crop_padding_high_slices=*|--crop-padding-high-slices=*)
      crop_padding_high_slices="${1#*=}"
      shift
      ;;
    --crop_bridge_gap_slices|--crop-bridge-gap-slices)
      crop_bridge_gap_slices="${2:?--crop_bridge_gap_slices requires a value}"
      shift 2
      ;;
    --crop_bridge_gap_slices=*|--crop-bridge-gap-slices=*)
      crop_bridge_gap_slices="${1#*=}"
      shift
      ;;
    --crop_min_run_slices|--crop-min-run-slices)
      crop_min_run_slices="${2:?--crop_min_run_slices requires a value}"
      shift 2
      ;;
    --crop_min_run_slices=*|--crop-min-run-slices=*)
      crop_min_run_slices="${1#*=}"
      shift
      ;;
    --crop_sample_values_per_slice|--crop-sample-values-per-slice)
      crop_sample_values_per_slice="${2:?--crop_sample_values_per_slice requires a value}"
      shift 2
      ;;
    --crop_sample_values_per_slice=*|--crop-sample-values-per-slice=*)
      crop_sample_values_per_slice="${1#*=}"
      shift
      ;;
    --remote_user|--remote-user)
      remote_user="${2:?--remote_user requires a value}"
      shift 2
      ;;
    --remote_user=*|--remote-user=*)
      remote_user="${1#*=}"
      shift
      ;;
    --remote_host|--remote-host)
      remote_host="${2:?--remote_host requires a value}"
      shift 2
      ;;
    --remote_host=*|--remote-host=*)
      remote_host="${1#*=}"
      shift
      ;;
    --remote_port|--remote-port)
      remote_port="${2:?--remote_port requires a value}"
      shift 2
      ;;
    --remote_port=*|--remote-port=*)
      remote_port="${1#*=}"
      shift
      ;;
    --password)
      password="${2:?--password requires a value}"
      shift 2
      ;;
    --password=*)
      password="${1#*=}"
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

export HITT_SSHPASS="$password"

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
  --copy_data "$copy_data"
  --copy_dest_root "$copy_dest_root"
  --copy_max_forks "$copy_max_forks"
  --persistent_image_stats_dir "$persistent_image_stats_dir"
  --crop_stack "$crop_stack"
  --crop_bright_threshold "$crop_bright_threshold"
  --crop_auto_percentile "$crop_auto_percentile"
  --crop_min_bright_fraction "$crop_min_bright_fraction"
  --crop_padding_slices "$crop_padding_slices"
  --crop_padding_low_slices "$crop_padding_low_slices"
  --crop_padding_high_slices "$crop_padding_high_slices"
  --crop_bridge_gap_slices "$crop_bridge_gap_slices"
  --crop_min_run_slices "$crop_min_run_slices"
  --crop_sample_values_per_slice "$crop_sample_values_per_slice"
  --remote_user "$remote_user"
  --remote_host "$remote_host"
  --remote_port "$remote_port"
  --password "$password"
  -profile "$profile"
)

if [ "$resume" = "TRUE" ]; then
  nextflow_args+=("-resume")
fi

nextflow "${nextflow_args[@]}"
