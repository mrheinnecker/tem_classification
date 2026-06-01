#!/usr/bin/env bash
set -euo pipefail

# Edit this file to define a complete screening run.
# Keep passwords outside the file, for example:
#   export HITT_SSHPASS='PASSWORD'
#
# The profile only selects where Nextflow jobs run:
#   interactive = current cluster node
#   cluster     = submit jobs through Slurm

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
timestamp="$(date +%Y-%m-%d_%H-%M)"

# HITT workflow
# To use a local table instead, replace the sheet options with:
#   --sheet_mode local \
#   --input_table "/path/to/hitt_images.tsv" \
bash "${repo_dir}/hitt/hitt_main.sh" cluster \
  --sheet_mode google \
  --sheet_url "https://docs.google.com/spreadsheets/d/1ePRpa56mmMvCeRTLXmwOywOLy5_I3AFrxJepSUYGR1s/edit?gid=0#gid=0" \
  --sheet_name "all_hitt" \
  --google_key "${repo_dir}/hitt/trec-tem-screen-e98a2e03f58b.json" \
  --collection_table_url "https://docs.google.com/spreadsheets/d/1ePRpa56mmMvCeRTLXmwOywOLy5_I3AFrxJepSUYGR1s/edit?gid=1582290308#gid=1582290308" \
  --collection_table_sheet "hitt_collection_table" \
  --main_dir "/scratch/rheinnec/hitt_screen" \
  --logdir "/scratch/rheinnec/hitt_screen/logs/wfHITT_${timestamp}" \
  --work_dir "/scratch/rheinnec/hitt_screen/work" \
  --workflow_stage all \
  --dryrun FALSE \
  --s3_bucket "s3embl/hitttest" \
  --x_scale 650 \
  --y_scale 650 \
  --z_scale 650 \
  --input_suffix "recon_111_1/tomo" \
  --output_name "omezarr" \
  --overwrite TRUE \
  --convert_uint16 TRUE \
  --uint16_lower_percentile 0.1 \
  --uint16_upper_percentile 99.9 \
  --uint16_sample_values 2000000 \
  --copy_data TRUE \
  --copy_dest_root "/scratch/rheinnec/tmp_hitt" \
  --remote_user "p3l-yschwab" \
  --remote_host "cerberus.embl-hamburg.de" \
  --remote_port 22443 \
  --resume TRUE

# Add other workflow launcher calls below when they are ready, for example:
#
# bash "${repo_dir}/tem/main.sh" cluster \
#   --workflow_stage all
#
# bash "${repo_dir}/sem/sem_main.sh" cluster \
#   --workflow_stage all
