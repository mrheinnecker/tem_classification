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

If IMOD, EUBI, and the segmentation Python container/tools are available locally but you do not want S3 upload, use:

```bash
WORKFLOW_STAGE=process DRYRUN=FALSE ./main.sh local
```

This produces the corrected image, the overview PNG with scale bar, a coarse-mask QC PNG, and a `*_coarse_mask.ome.zarr` label image for MoBIE overlay testing.

## Local full run

If all external tools, including MinIO/S3 access, are available locally, use:

```bash
WORKFLOW_STAGE=all DRYRUN=FALSE ./main.sh local
```

## Cluster run

```bash
./main.sh cluster
```

Cluster mode loads Nextflow, uses the `cluster` profile, enables Singularity, writes to Google Sheets, uploads both image OME-Zarrs and coarse-mask OME-Zarrs, and runs the full workflow.

## Interactive cluster debugging

After allocating an interactive cluster node, run:

```bash
./main.sh interactive
```

Interactive mode uses the cluster paths and containers, but runs Nextflow tasks with the local executor inside the allocated node instead of submitting each task as a Slurm batch job. By default it uses `SHEET_MODE=local`, `WORKFLOW_STAGE=process`, and `DRYRUN=TRUE`, so it avoids Google/S3 while debugging.

## Useful overrides

All paths can be changed without editing code:

```bash
TEM_SCREEN_DIR=/some/other/tem_screen ./main.sh local
RAWDIR=/path/to/raw PNGDIR=/path/to/pngs OUTDIR=/path/to/processed ./main.sh local
SHEET_MODE=local WORKFLOW_STAGE=discover DRYRUN=TRUE ./main.sh cluster
DRYRUN=FALSE WORKFLOW_STAGE=process ./main.sh interactive
```
