#!/usr/bin/env bash
#SBATCH --job-name=wfTEM
#SBATCH --output=wfTEM_%j.out
#SBATCH --error=wfTEM_%j.err
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=24:00:00

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$script_dir/../.."

RESUME="${RESUME:-TRUE}" \
DRYRUN="${DRYRUN:-FALSE}" \
WORKFLOW_STAGE="${WORKFLOW_STAGE:-all}" \
"$script_dir/main.sh" cluster
