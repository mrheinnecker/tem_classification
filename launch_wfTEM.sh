#!/usr/bin/env bash
#SBATCH --job-name=wfTEM
#SBATCH --output=/scratch/rheinnec/tem_screen/wfTEM_%j.out
#SBATCH --error=/scratch/rheinnec/tem_screen/wfTEM_%j.err
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --time=24:00:00
set -euo pipefail

# Edit this file to define a complete TEM screening run.
# The profile only selects where Nextflow jobs run:
#   interactive = current cluster node
#   cluster     = submit jobs through Slurm

timestamp="$(date +%Y-%m-%d_%H-%M)"

repo_dir="/g/schwab/marco/repos/tem_classification"
scratch_dir="/scratch/rheinnec/tem_screen"

mkdir -p "${scratch_dir}"
cd "${scratch_dir}"

bash "${repo_dir}/tem/main.sh" interactive \
  --sheet_mode google \
  --sheet_url "https://docs.google.com/spreadsheets/d/143uVeeJ72SQE5eK01lzWYCEiT7pJUF3lX7hJl3R9s9I/edit?gid=258669282#gid=258669282" \
  --google_key "${repo_dir}/trec-tem-screen-e98a2e03f58b.json" \
  --collection_table_url "https://docs.google.com/spreadsheets/d/15WNNnse7OvlfiJwFOFYbQA4zIp-5nKc0icRZYfJS--o/edit?gid=1643802951#gid=1643802951" \
  --collection_table_sheet "tem_collection_table" \
  --main_dir "/g/schwab/tem_screen" \
  --rawdir "/g/schwab/tem_screen/raw" \
  --pngdir "/g/schwab/tem_screen/pngs" \
  --outdir "/g/schwab/tem_screen/processed" \
  --logdir "/g/schwab/tem_screen/logs/wfTEM_${timestamp}" \
  --work_dir "${scratch_dir}/work" \
  --local_log "/g/schwab/tem_screen/image_log_local.tsv" \
  --workflow_stage all \
  --dryrun FALSE \
  --dryrun_n 10 \
  --s3_bucket "s3embl/temscreen" \
  --gradient_chunk_rows 512 \
  --gradient_downsample 16 \
  --resume TRUE
