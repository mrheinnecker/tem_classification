#!/usr/bin/env bash
set -euo pipefail

PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
timestamp="$(date +%Y-%m-%d_%H-%M)"
resume="${RESUME:-TRUE}"
mode="${MODE:-interactive}"

if [[ $# -gt 0 && "${1:-}" != --* && "${1:-}" != "-resume" ]]; then
  mode="$1"
  shift
fi

scan_args=("$@")
for ((i = 0; i < ${#scan_args[@]}; i++)); do
  case "${scan_args[$i]}" in
    --profile|--mode)
      if (( i + 1 >= ${#scan_args[@]} )); then
        echo "${scan_args[$i]} requires a value"
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
  cluster)
    main_dir="${SEM_SCREEN_DIR:-/g/schwab/sem_screen}"
    default_work_dir="${WORK_DIR:-/scratch/rheinnec/sem_screen/work}"
    profile="cluster"
    default_sheet_mode="google"
    default_workflow_stage="all"
    default_dryrun="FALSE"
    if command -v module >/dev/null 2>&1; then
      module load Nextflow/24.10.4
    fi
    ;;
  interactive)
    main_dir="${SEM_SCREEN_DIR:-/g/schwab/sem_screen}"
    default_work_dir="${WORK_DIR:-/scratch/rheinnec/sem_screen/work}"
    profile="interactive"
    default_sheet_mode="google"
    default_workflow_stage="all"
    default_dryrun="FALSE"
    if command -v module >/dev/null 2>&1; then
      module load Nextflow/24.10.4
    fi
    ;;
  local)
    main_dir="${SEM_SCREEN_DIR:-C:/projects/sem_screen}"
    default_work_dir="${WORK_DIR:-${main_dir}/work}"
    profile="local"
    default_sheet_mode="local"
    default_workflow_stage="discover"
    default_dryrun="TRUE"
    ;;
  *)
    echo "Usage: $0 [local|interactive|cluster]"
    exit 1
    ;;
esac

sheet_mode="${SHEET_MODE:-$default_sheet_mode}"
workflow_stage="${WORKFLOW_STAGE:-$default_workflow_stage}"
dryrun="${DRYRUN:-$default_dryrun}"

rawdir="${RAWDIR:-}"
outdir="${OUTDIR:-}"
logdir="${LOGDIR:-}"
work_dir="${WORK_DIR:-$default_work_dir}"
local_log="${LOCAL_LOG:-}"
s3_bucket="${S3_BUCKET:-s3embl/semscreen}"
sheet_url="${SHEET_URL:-https://docs.google.com/spreadsheets/d/1jcpyMkSR4npSxST3D5cFzkAIi9UPmwbPvzAdr2ws55U/edit?gid=2132397683#gid=2132397683}"
collection_table_url="${COLLECTION_TABLE_URL:-https://docs.google.com/spreadsheets/d/15WNNnse7OvlfiJwFOFYbQA4zIp-5nKc0icRZYfJS--o/edit?gid=1643802951#gid=1643802951}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile|--mode)
      mode="${2:?--profile requires a value}"
      shift 2
      ;;
    --profile=*|--mode=*)
      mode="${1#*=}"
      shift
      ;;
    --resume)
      resume="${2:?--resume requires TRUE or FALSE}"
      shift 2
      ;;
    --resume=*)
      resume="${1#*=}"
      shift
      ;;
    -resume)
      resume="TRUE"
      shift
      ;;
    --dryrun)
      dryrun="${2:?--dryrun requires TRUE or FALSE}"
      shift 2
      ;;
    --dryrun=*)
      dryrun="${1#*=}"
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
    --work_dir|--work-dir)
      work_dir="${2:?--work_dir requires a path}"
      shift 2
      ;;
    --work_dir=*|--work-dir=*)
      work_dir="${1#*=}"
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
    --help|-h)
      echo "Usage: $0 [local|interactive|cluster] [--main_dir PATH] [--work_dir PATH] [--resume TRUE|FALSE]"
      exit 0
      ;;
    local|interactive|cluster)
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

rawdir="${rawdir:-/g/schwab/Chandni/SEM/IMATREC SEM}"
outdir="${outdir:-${main_dir}/processed}"
logdir="${logdir:-${main_dir}/logs/wfSEM_${timestamp}}"
local_log="${local_log:-${main_dir}/sem_image_log_local.tsv}"

mkdir -p "$logdir" "$outdir" "$work_dir"
cd "$main_dir"

nextflow_args=(
  run "${script_dir}/wfSEM.nf"
  -c "${script_dir}/nextflow.config"
  -work-dir "$work_dir"
  --script_dir "$script_dir"
  --logdir "$logdir"
  --rawdir "$rawdir"
  --outdir "$outdir"
  --local_log "$local_log"
  --sheet_mode "$sheet_mode"
  --sheet_url "$sheet_url"
  --collection_table_url "$collection_table_url"
  --workflow_stage "$workflow_stage"
  --dryrun "$dryrun"
  --s3_bucket "$s3_bucket"
  -profile "$profile"
)

case "$resume" in
  TRUE|true|1|yes|YES)
    nextflow_args+=("-resume")
    ;;
  FALSE|false|0|no|NO)
    ;;
  *)
    echo "RESUME must be TRUE or FALSE"
    exit 1
    ;;
esac

nextflow "${nextflow_args[@]}"
