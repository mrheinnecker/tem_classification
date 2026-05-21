# TEM screen workflow

The workflow is configured by `nextflow.config` and can run in two modes:

- `local`: uses the copied test data in `C:/projects/tem_screen/raw`, writes local logs, and stops after image discovery by default.
- `cluster`: uses the EMBL/Slurm paths, containers, Google Sheets logging, S3 upload, and the full processing workflow.

## Local discovery run

```bash
./main.sh local
```

This creates:

- `C:/projects/tem_screen/logs/wfTEM_<timestamp>/images_to_process.csv`
- `C:/projects/tem_screen/logs/wfTEM_<timestamp>/all_datasets.tsv`
- `C:/projects/tem_screen/image_log_local.tsv`
- `C:/projects/tem_screen/logs/wfTEM_<timestamp>/TEM_screen_image_count.pdf`

By default local mode uses `DRYRUN=TRUE` and `WORKFLOW_STAGE=discover`, so it lists only the first five candidate images and does not require IMOD, EUBI, MinIO, Singularity, or Google credentials.

## Local processing run

If IMOD and EUBI are available locally but you do not want S3 upload, use:

```bash
WORKFLOW_STAGE=process DRYRUN=FALSE ./main.sh local
```

## Local full run

If all external tools, including MinIO/S3 access, are available locally, use:

```bash
WORKFLOW_STAGE=all DRYRUN=FALSE ./main.sh local
```

## Cluster run

```bash
./main.sh cluster
```

Cluster mode loads Nextflow, uses the `cluster` profile, enables Singularity, writes to Google Sheets, and runs the full workflow.

## Useful overrides

All paths can be changed without editing code:

```bash
TEM_SCREEN_DIR=/some/other/tem_screen ./main.sh local
RAWDIR=/path/to/raw PNGDIR=/path/to/pngs OUTDIR=/path/to/processed ./main.sh local
SHEET_MODE=local WORKFLOW_STAGE=discover DRYRUN=TRUE ./main.sh cluster
```
