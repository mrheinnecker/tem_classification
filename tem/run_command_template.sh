#!/usr/bin/env bash

# This file is a run template only.
# Copy one command block into your terminal, edit the values there, and execute it.
echo "Template only: copy one command block from this file and run it manually."
exit 0

# Full cluster production run.
bash /g/schwab/marco/repos/tem_classification/tem/main.sh \
  --profile cluster \
  --resume TRUE \
  --dryrun FALSE \
  --sheet_mode google \
  --workflow_stage all \
  --main_dir /scratch/rheinnec/tem_screen \
  --rawdir /scratch/rheinnec/tem_screen/raw \
  --pngdir /scratch/rheinnec/tem_screen/pngs \
  --outdir /scratch/rheinnec/tem_screen/processed \
  --local_log /scratch/rheinnec/tem_screen/image_log_local.tsv \
  --gradient_chunk_rows 512 \
  --gradient_downsample 16

# Interactive cluster debugging after allocating a node.
bash /g/schwab/marco/repos/tem_classification/tem/main.sh \
  --profile interactive \
  --resume TRUE \
  --dryrun TRUE \
  --sheet_mode local \
  --workflow_stage process \
  --main_dir /scratch/rheinnec/tem_screen \
  --rawdir /scratch/rheinnec/tem_screen/raw \
  --pngdir /scratch/rheinnec/tem_screen/pngs \
  --outdir /scratch/rheinnec/tem_screen/processed \
  --local_log /scratch/rheinnec/tem_screen/image_log_local.tsv \
  --gradient_chunk_rows 512 \
  --gradient_downsample 16

# Local Windows discovery run with copied test files.
bash C:/repos/tem_classification/tem/main.sh \
  --profile local \
  --resume TRUE \
  --dryrun TRUE \
  --sheet_mode local \
  --workflow_stage discover \
  --main_dir C:/projects/tem_screen \
  --rawdir C:/projects/tem_screen/raw \
  --pngdir C:/projects/tem_screen/pngs \
  --outdir C:/projects/tem_screen/processed \
  --local_log C:/projects/tem_screen/image_log_local.tsv
