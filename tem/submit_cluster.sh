#!/usr/bin/env bash
#SBATCH --job-name=wfTEM
#SBATCH --output=wfTEM_%j.out
#SBATCH --error=wfTEM_%j.err
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --time=4:00:00

set -euo pipefail

PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "${script_dir}/main.sh" \
  --profile cluster \
  --resume "${RESUME:-TRUE}" \
  --dryrun "${DRYRUN:-FALSE}" \
  --sheet_mode "${SHEET_MODE:-google}" \
  --workflow_stage "${WORKFLOW_STAGE:-all}" \
  --main_dir "${TEM_SCREEN_DIR:-/scratch/rheinnec/tem_screen}" \
  --gradient_chunk_rows "${GRADIENT_CHUNK_ROWS:-512}" \
  --gradient_downsample "${GRADIENT_DOWNSAMPLE:-16}"
