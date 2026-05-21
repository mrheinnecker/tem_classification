#!/usr/bin/env bash
set -euo pipefail

mode="${1:-local}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
timestamp="$(date +%Y-%m-%d_%H-%M)"

case "$mode" in
  local)
    main_dir="${TEM_SCREEN_DIR:-C:/projects/tem_screen}"
    profile="local"
    sheet_mode="${SHEET_MODE:-local}"
    workflow_stage="${WORKFLOW_STAGE:-discover}"
    dryrun="${DRYRUN:-TRUE}"
    ;;
  cluster)
    main_dir="${TEM_SCREEN_DIR:-/scratch/rheinnec/tem_screen}"
    profile="cluster"
    sheet_mode="${SHEET_MODE:-google}"
    workflow_stage="${WORKFLOW_STAGE:-all}"
    dryrun="${DRYRUN:-FALSE}"
    module load Nextflow/24.10.4
    ;;
  *)
    echo "Usage: $0 [local|cluster]"
    exit 1
    ;;
esac

rawdir="${RAWDIR:-${main_dir}/raw}"
pngdir="${PNGDIR:-${main_dir}/pngs}"
outdir="${OUTDIR:-${main_dir}/processed}"
logdir="${LOGDIR:-${main_dir}/logs/wfTEM_${timestamp}}"
local_log="${LOCAL_LOG:-${main_dir}/image_log_local.tsv}"

mkdir -p "$logdir" "$pngdir" "$outdir"
cd "$main_dir"

nextflow run "${script_dir}/wfTEM.nf" \
  --script_dir "$script_dir" \
  --logdir "$logdir" \
  --pngdir "$pngdir" \
  --rawdir "$rawdir" \
  --outdir "$outdir" \
  --local_log "$local_log" \
  --sheet_mode "$sheet_mode" \
  --workflow_stage "$workflow_stage" \
  --dryrun "$dryrun" \
  -profile "$profile" \
  -resume
