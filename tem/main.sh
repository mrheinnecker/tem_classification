#!/usr/bin/env bash
set -euo pipefail

PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
timestamp="$(date +%Y-%m-%d_%H-%M)"

usage() {
  cat <<EOF
Usage:
  bash main.sh [profile] [options]
  bash main.sh --profile cluster --resume TRUE --sheet_mode google

Profiles:
  local        Local Windows/test-data defaults; no containers, discovery by default.
  interactive Cluster node interactive session; local executor with containers.
  cluster      EMBL Slurm submission profile.
  devel        Cluster profile with dryrun enabled.

Options:
  --profile, --mode VALUE          Runtime profile: local, interactive, cluster, devel.
  --resume TRUE|FALSE              Add Nextflow -resume when TRUE.
  --dryrun TRUE|FALSE              Forwarded to the workflow.
  --dryrun_n N                     Number of images to process during dryrun.
  --sheet_mode VALUE               local or google.
  --sheet_url URL                  Image log Google Sheet URL.
  --google_key PATH                Google service-account JSON key.
  --collection_table_url URL       Collection-table Google Sheet URL.
  --collection_table_sheet VALUE   Output sheet name for the collection table.
  --workflow_stage VALUE           discover, process, or all.
  --main_dir PATH                  Base TEM screen directory.
  --rawdir PATH                    Raw image directory.
  --pngdir PATH                    PNG output directory.
  --outdir PATH                    Processed output directory.
  --logdir PATH                    Workflow log directory.
  --work_dir PATH                  Nextflow work directory.
  --local_log PATH                 Local image log TSV.
  --s3_bucket VALUE                Target S3 bucket/path for OME-Zarr upload.
  --gradient_chunk_rows VALUE      Row chunk size for gradient correction.
  --gradient_downsample VALUE      Downsample factor for gradient detection.
  --help                           Show this message.

Environment overrides are still supported for compatibility:
  RESUME, DRYRUN, SHEET_MODE, WORKFLOW_STAGE, TEM_SCREEN_DIR, RAWDIR,
  PNGDIR, OUTDIR, LOGDIR, WORK_DIR, LOCAL_LOG, S3_BUCKET, SHEET_URL,
  GOOGLE_KEY, COLLECTION_TABLE_URL, COLLECTION_TABLE_SHEET, DRYRUN_N,
  GRADIENT_CHUNK_ROWS, GRADIENT_DOWNSAMPLE.
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

mode="${MODE:-local}"

# Keep the old positional style working: bash main.sh cluster -resume
if [[ $# -gt 0 && "${1:-}" != --* && "${1:-}" != "-resume" ]]; then
  mode="$1"
  shift
fi

# Allow --profile/--mode anywhere, so defaults are selected before option overrides.
scan_args=("$@")
for ((i = 0; i < ${#scan_args[@]}; i++)); do
  case "${scan_args[$i]}" in
    --profile|--mode)
      if (( i + 1 >= ${#scan_args[@]} )); then
        echo "${scan_args[$i]} requires a value" >&2
        exit 1
      fi
      mode="${scan_args[$((i + 1))]}"
      ;;
    --profile=*|--mode=*)
      mode="${scan_args[$i]#*=}"
      ;;
  esac
done

case "$mode" in
  local)
    main_dir="${TEM_SCREEN_DIR:-C:/projects/tem_screen}"
    default_work_dir="${WORK_DIR:-${main_dir}/work}"
    profile="local"
    default_sheet_mode="local"
    default_workflow_stage="discover"
    default_dryrun="TRUE"
    ;;
  cluster)
    main_dir="${TEM_SCREEN_DIR:-/g/schwab/tem_screen}"
    default_work_dir="${WORK_DIR:-/scratch/rheinnec/tem_screen/work}"
    profile="cluster"
    default_sheet_mode="google"
    default_workflow_stage="all"
    default_dryrun="FALSE"
    if command -v module >/dev/null 2>&1; then
      module load Nextflow/24.10.4
    fi
    ;;
  interactive)
    main_dir="${TEM_SCREEN_DIR:-/scratch/rheinnec/tem_screen}"
    default_work_dir="${WORK_DIR:-/scratch/rheinnec/tem_screen/work}"
    profile="interactive"
    default_sheet_mode="local"
    default_workflow_stage="process"
    default_dryrun="TRUE"
    if command -v module >/dev/null 2>&1; then
      module load Nextflow/24.10.4
    fi
    ;;
  devel)
    main_dir="${TEM_SCREEN_DIR:-/g/schwab/tem_screen}"
    default_work_dir="${WORK_DIR:-/scratch/rheinnec/tem_screen/work}"
    profile="cluster"
    default_sheet_mode="google"
    default_workflow_stage="all"
    default_dryrun="TRUE"
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

resume="$(to_upper_bool "${RESUME:-TRUE}")"
sheet_mode="${SHEET_MODE:-$default_sheet_mode}"
workflow_stage="${WORKFLOW_STAGE:-$default_workflow_stage}"
dryrun="$(to_upper_bool "${DRYRUN:-$default_dryrun}")"
dryrun_n="${DRYRUN_N:-10}"

rawdir="${RAWDIR:-}"
pngdir="${PNGDIR:-}"
outdir="${OUTDIR:-}"
logdir="${LOGDIR:-}"
work_dir="${WORK_DIR:-$default_work_dir}"
local_log="${LOCAL_LOG:-}"
s3_bucket="${S3_BUCKET:-s3embl/temscreen}"
sheet_url="${SHEET_URL:-https://docs.google.com/spreadsheets/d/143uVeeJ72SQE5eK01lzWYCEiT7pJUF3lX7hJl3R9s9I/edit?gid=258669282#gid=258669282}"
google_key="${GOOGLE_KEY:-${script_dir}/trec-tem-screen-e98a2e03f58b.json}"
collection_table_url="${COLLECTION_TABLE_URL:-https://docs.google.com/spreadsheets/d/15WNNnse7OvlfiJwFOFYbQA4zIp-5nKc0icRZYfJS--o/edit?gid=1643802951#gid=1643802951}"
collection_table_sheet="${COLLECTION_TABLE_SHEET:-collection_table}"
gradient_chunk_rows="${GRADIENT_CHUNK_ROWS:-}"
gradient_downsample="${GRADIENT_DOWNSAMPLE:-}"

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
    --sheet_mode|--sheet-mode|--sheete_mode)
      sheet_mode="${2:?--sheet_mode requires a value}"
      shift 2
      ;;
    --sheet_mode=*|--sheet-mode=*|--sheete_mode=*)
      sheet_mode="${1#*=}"
      shift
      ;;
    --sheet_url|--sheet-url)
      sheet_url="${2:?--sheet_url requires a value}"
      shift 2
      ;;
    --sheet_url=*|--sheet-url=*)
      sheet_url="${1#*=}"
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
      collection_table_url="${2:?--collection_table_url requires a value}"
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
    --workflow_stage|--workflow-stage)
      workflow_stage="${2:?--workflow_stage requires a value}"
      shift 2
      ;;
    --workflow_stage=*|--workflow-stage=*)
      workflow_stage="${1#*=}"
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
    --rawdir)
      rawdir="${2:?--rawdir requires a path}"
      shift 2
      ;;
    --rawdir=*)
      rawdir="${1#*=}"
      shift
      ;;
    --pngdir)
      pngdir="${2:?--pngdir requires a path}"
      shift 2
      ;;
    --pngdir=*)
      pngdir="${1#*=}"
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
    --local_log|--local-log)
      local_log="${2:?--local_log requires a path}"
      shift 2
      ;;
    --local_log=*|--local-log=*)
      local_log="${1#*=}"
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
    --gradient_chunk_rows|--gradient-chunk-rows)
      gradient_chunk_rows="${2:?--gradient_chunk_rows requires a value}"
      shift 2
      ;;
    --gradient_chunk_rows=*|--gradient-chunk-rows=*)
      gradient_chunk_rows="${1#*=}"
      shift
      ;;
    --gradient_downsample|--gradient-downsample)
      gradient_downsample="${2:?--gradient_downsample requires a value}"
      shift 2
      ;;
    --gradient_downsample=*|--gradient-downsample=*)
      gradient_downsample="${1#*=}"
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

rawdir="${rawdir:-${main_dir}/raw}"
pngdir="${pngdir:-${main_dir}/pngs}"
outdir="${outdir:-${main_dir}/processed}"
logdir="${logdir:-${main_dir}/logs/wfTEM_${timestamp}}"
local_log="${local_log:-${main_dir}/image_log_local.tsv}"

mkdir -p "$logdir" "$pngdir" "$outdir" "$work_dir"
cd "$main_dir"

nextflow_args=(
  run "${script_dir}/wfTEM.nf"
  -c "${script_dir}/nextflow.config"
  -work-dir "$work_dir"
  --script_dir "$script_dir"
  --logdir "$logdir"
  --pngdir "$pngdir"
  --rawdir "$rawdir"
  --outdir "$outdir"
  --local_log "$local_log"
  --sheet_mode "$sheet_mode"
  --sheet_url "$sheet_url"
  --google_key "$google_key"
  --collection_table_url "$collection_table_url"
  --collection_table_sheet "$collection_table_sheet"
  --workflow_stage "$workflow_stage"
  --dryrun "$dryrun"
  --dryrun_n "$dryrun_n"
  --s3_bucket "$s3_bucket"
  -profile "$profile"
)

if [ -n "$gradient_chunk_rows" ]; then
  nextflow_args+=(--gradient_chunk_rows "$gradient_chunk_rows")
fi

if [ -n "$gradient_downsample" ]; then
  nextflow_args+=(--gradient_downsample "$gradient_downsample")
fi

if [ "$resume" = "TRUE" ]; then
  nextflow_args+=("-resume")
fi

nextflow "${nextflow_args[@]}"
