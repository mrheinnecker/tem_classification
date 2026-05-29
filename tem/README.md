# TEM screen workflow

The workflow is configured by `nextflow.config` and can run in two modes:

- `local`: uses the copied test data in `C:/projects/tem_screen/raw`, writes local logs, and stops after image discovery by default.
- `cluster`: uses the EMBL/Slurm paths, containers, Google Sheets logging, S3 upload, and the full processing workflow.

## Local discovery run

```bash
bash ./main.sh --profile local
```

This creates:

- `C:/projects/tem_screen/logs/wfTEM_<timestamp>/images_to_process.csv`
- `C:/projects/tem_screen/logs/wfTEM_<timestamp>/all_datasets.tsv`
- `C:/projects/tem_screen/image_log_local.tsv`
- `C:/projects/tem_screen/logs/wfTEM_<timestamp>/TEM_screen_image_count.pdf`

By default local mode uses `DRYRUN=TRUE` and `WORKFLOW_STAGE=discover`, so it lists only the first five candidate images and does not require IMOD, EUBI, MinIO, Singularity, or Google credentials.

## Local processing run

If IMOD, EUBI, and the segmentation Python container/tools are available locally but you do not want S3 upload, use:

```bash
bash ./main.sh \
  --profile local \
  --workflow_stage process \
  --dryrun FALSE
```

This produces the corrected image, gradient QC/metrics, and the overview PNG with scale bar.

Gradient correction runs in `auto` mode by default. It estimates a broad low-frequency plane, writes `*_gradient_metrics.tsv` and `*_gradient_qc.png`, and only subtracts the plane when `gradient_score >= 0.18`. To report without changing pixels:

```bash
nextflow run /path/to/wfTEM.nf -profile interactive --gradient_mode detect_only
```

Memory for the larger image-processing steps is derived from the `req_mem` estimate written by `imaging_ov.R`, with process-specific floors and caps. `EXPORTOVPNG` also reads only a downsampled preview into memory.

## Local full run

If all external tools, including MinIO/S3 access, are available locally, use:

```bash
bash ./main.sh \
  --profile local \
  --workflow_stage all \
  --dryrun FALSE
```

## Cluster run

```bash
bash ./main.sh \
  --profile cluster \
  --resume TRUE \
  --dryrun FALSE \
  --sheet_mode google \
  --workflow_stage all \
  --main_dir /g/schwab/tem_screen \
  --work_dir /scratch/rheinnec/tem_screen/work
```

Cluster mode loads Nextflow, uses the `cluster` profile, enables Singularity, writes to Google Sheets, uploads both image OME-Zarrs and coarse-mask OME-Zarrs, and runs the full workflow. By default, data paths are under `/g/schwab/tem_screen`, while Nextflow's `work/` directory is under `/scratch/rheinnec/tem_screen/work`.

For repeatable runs, use `run_command_template.sh` as a copy/edit template. It is intentionally guarded so that running the file itself only prints a short message; copy one multiline command block from it into your terminal and execute that command.

To submit the whole Nextflow driver as one Slurm job:

```bash
sbatch ./submit_cluster.sh
```

You can still override the usual runtime flags:

```bash
RESUME=FALSE DRYRUN=TRUE WORKFLOW_STAGE=discover sbatch ./submit_cluster.sh
```

## Interactive cluster debugging

After allocating an interactive cluster node, run:

```bash
bash ./main.sh \
  --profile interactive \
  --resume TRUE \
  --dryrun TRUE \
  --sheet_mode local \
  --workflow_stage process
```

Interactive mode uses the cluster paths and containers, but runs Nextflow tasks with the local executor inside the allocated node instead of submitting each task as a Slurm batch job. By default it uses `SHEET_MODE=local`, `WORKFLOW_STAGE=process`, and `DRYRUN=TRUE`, so it avoids Google/S3 while debugging.

## Useful overrides

All paths can be changed without editing code:

```bash
bash ./main.sh --profile local --main_dir /some/other/tem_screen
bash ./main.sh --profile cluster --work_dir /scratch/rheinnec/other_tem_work
bash ./main.sh --profile local --rawdir /path/to/raw --pngdir /path/to/pngs --outdir /path/to/processed
bash ./main.sh --profile cluster --sheet_mode local --workflow_stage discover --dryrun TRUE
bash ./main.sh --profile interactive --dryrun FALSE --workflow_stage process
bash ./main.sh --profile interactive --resume FALSE
```

`RESUME=TRUE` is the default and adds Nextflow's `-resume` flag. Use `RESUME=FALSE` when you want a clean debug run and do not want Nextflow to reuse cached process outputs.
