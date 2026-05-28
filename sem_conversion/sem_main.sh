#!/usr/bin/env bash
set -euo pipefail

mode="${1:-interactive}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
timestamp="$(date +%Y-%m-%d_%H-%M)"
resume="${RESUME:-TRUE}"

case "$mode" in
  cluster)
    main_dir="${SEM_SCREEN_DIR:-/scratch/rheinnec/sem_screen}"
    profile="cluster"
    default_sheet_mode="google"
    default_workflow_stage="all"
    default_dryrun="FALSE"
    module load Nextflow/24.10.4
    ;;
  interactive)
    main_dir="${SEM_SCREEN_DIR:-/scratch/rheinnec/sem_screen}"
    profile="interactive"
    default_sheet_mode="local"
    default_workflow_stage="process"
    default_dryrun="TRUE"
    module load Nextflow/24.10.4
    ;;
  local)
    main_dir="${SEM_SCREEN_DIR:-C:/projects/sem_screen}"
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

rawdir="${RAWDIR:-/g/schwab/Chandni/SEM/IMATREC SEM}"
outdir="${OUTDIR:-${main_dir}/processed}"
logdir="${LOGDIR:-${main_dir}/logs/wfSEM_${timestamp}}"
local_log="${LOCAL_LOG:-${main_dir}/sem_image_log_local.tsv}"
s3_bucket="${S3_BUCKET:-s3embl/semscreen}"

mkdir -p "$logdir" "$outdir"
cd "$main_dir"

nextflow_args=(
  run "${script_dir}/wfSEM.nf"
  -c "${script_dir}/nextflow.config"
  --script_dir "$script_dir"
  --logdir "$logdir"
  --rawdir "$rawdir"
  --outdir "$outdir"
  --local_log "$local_log"
  --sheet_mode "$sheet_mode"
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
