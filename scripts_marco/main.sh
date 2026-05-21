#!/usr/bin/env bash
set -euo pipefail

mode="${1:-local}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
timestamp="$(date +%Y-%m-%d_%H-%M)"
resume="${RESUME:-TRUE}"

case "$mode" in
  local)
    main_dir="${TEM_SCREEN_DIR:-C:/projects/tem_screen}"
    profile="local"
    default_sheet_mode="local"
    default_workflow_stage="discover"
    default_dryrun="TRUE"
    ;;
  interactive)
    main_dir="${TEM_SCREEN_DIR:-/scratch/rheinnec/tem_screen}"
    profile="interactive"
    default_sheet_mode="local"
    default_workflow_stage="process"
    default_dryrun="TRUE"
    module load Nextflow/24.10.4
    ;;
  cluster)
    main_dir="${TEM_SCREEN_DIR:-/scratch/rheinnec/tem_screen}"
    profile="cluster"
    default_sheet_mode="google"
    default_workflow_stage="all"
    default_dryrun="TRUE"
    module load Nextflow/24.10.4
    ;;
  *)
    echo "Usage: $0 [local|interactive|cluster]"
    exit 1
    ;;
esac

sheet_mode="${SHEET_MODE:-$default_sheet_mode}"
workflow_stage="${WORKFLOW_STAGE:-$default_workflow_stage}"
dryrun="${DRYRUN:-$default_dryrun}"

rawdir="${RAWDIR:-${main_dir}/raw}"
pngdir="${PNGDIR:-${main_dir}/pngs}"
outdir="${OUTDIR:-${main_dir}/processed}"
logdir="${LOGDIR:-${main_dir}/logs/wfTEM_${timestamp}}"
local_log="${LOCAL_LOG:-${main_dir}/image_log_local.tsv}"

mkdir -p "$logdir" "$pngdir" "$outdir"
cd "$main_dir"

nextflow_args=(
  run "${script_dir}/wfTEM.nf"
  --script_dir "$script_dir"
  --logdir "$logdir"
  --pngdir "$pngdir"
  --rawdir "$rawdir"
  --outdir "$outdir"
  --local_log "$local_log"
  --sheet_mode "$sheet_mode"
  --workflow_stage "$workflow_stage"
  --dryrun "$dryrun"
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
