# TEM/SEM Screening Workflows

This repository contains workflow code for preparing, processing, converting, and publishing microscopy screening data. The main active areas are:

- `tem/`: Transmission electron microscopy (TEM) discovery, preprocessing, QC, OME-Zarr conversion, S3 upload, and collection-table generation.
- `sem/`: Scanning electron microscopy (SEM) TIFF discovery, metadata extraction, OME-Zarr conversion, S3 upload, and collection-table generation.
- `container/`: Singularity/Apptainer definition files for the tool environments used by the workflows.

The `microsam/` folder is currently treated as a separate area and is not covered by this README.

## Repository Layout

```text
.
+-- container/
|   +-- eubibridge.def
|   +-- imod.def
|   +-- py_mrcfile.def
|   +-- segmentation.def
+-- sem/
|   +-- wfSEM.nf
|   +-- sem_main.sh
|   +-- nextflow.config
|   +-- select_images.R
|   +-- extract_metadata.py
|   +-- make_collection_table.R
+-- tem/
    +-- wfTEM.nf
    +-- main.sh
    +-- nextflow.config
    +-- imaging_ov.R
    +-- process_images.py
    +-- correct_gradient.py
    +-- extract_image_stats.py
    +-- make_collection_table.R
    +-- figures/
```

## TEM Workflow

The TEM workflow is defined in `tem/wfTEM.nf`, configured by `tem/nextflow.config`, and usually launched through `tem/main.sh`.

At a high level it:

1. Scans a raw TEM directory for `.mrc` files and matching `.mdoc` files.
2. Maintains an image log in either a local TSV file or a Google Sheet.
3. Generates a progress/count overview plot for imaged samples.
4. Renames/copies raw inputs into workflow output folders.
5. Runs IMOD tools such as `justblend` and `blendmont`.
6. Detects and optionally corrects broad low-frequency grayscale gradients.
7. Generates overview PNGs and QC images.
8. Extracts simple intensity statistics for contrast limits.
9. Converts processed MRC images to OME-Zarr using EuBI-Bridge.
10. In full mode, uploads OME-Zarr datasets to EMBL S3 and writes a collection table.

Useful entry points:

```bash
cd tem
./main.sh local
./main.sh interactive
./main.sh cluster
```

The main runtime controls can be overridden with environment variables:

```bash
WORKFLOW_STAGE=discover DRYRUN=TRUE ./main.sh local
WORKFLOW_STAGE=process DRYRUN=FALSE ./main.sh interactive
WORKFLOW_STAGE=all DRYRUN=FALSE ./main.sh cluster
RESUME=FALSE ./main.sh interactive
```

`WORKFLOW_STAGE` supports the following practical modes:

- `discover`: only discover images and update/write logs.
- `process`: process and convert images, but skip final S3/collection-table steps.
- `all`: run the full workflow including S3 upload and collection-table generation.

See `tem/README.md` for more detailed TEM-specific usage notes.

## SEM Workflow

The SEM workflow is defined in `sem/wfSEM.nf`, configured by `sem/nextflow.config`, and usually launched through `sem/sem_main.sh`.

At a high level it:

1. Scans a raw SEM directory for `.tif`/`.tiff` files.
2. Builds a local or Google-backed image log.
3. Extracts TIFF/Zeiss SEM metadata, including pixel-size information.
4. Converts SEM TIFF files to OME-Zarr using EuBI-Bridge.
5. In full mode, uploads OME-Zarr datasets to EMBL S3.
6. Builds a SEM collection table, optionally joined with metadata and taxonomy/annotation information.

Useful entry points:

```bash
cd sem
bash ./sem_main.sh --profile local
bash ./sem_main.sh --profile interactive
bash ./sem_main.sh --profile cluster
```

As with the TEM workflow, the SEM launcher separates persistent data paths from Nextflow's working directory:

```bash
bash ./sem_main.sh \
  --profile cluster \
  --main_dir /g/schwab/sem_screen \
  --work_dir /scratch/rheinnec/sem_screen/work \
  --workflow_stage all \
  --dryrun FALSE
```

For cluster and interactive runs, `/g/schwab/sem_screen` is the default output/log base and `/scratch/rheinnec/sem_screen/work` is the default Nextflow work directory. You can still override the same values with `SEM_SCREEN_DIR`, `WORK_DIR`, `OUTDIR`, `LOGDIR`, and `RAWDIR`.

## Run Modes

Both workflows use Nextflow profiles to separate local testing from cluster execution.

- `local`: intended for lightweight discovery/debugging on local paths.
- `interactive`: intended for debugging on an allocated cluster node with local task execution.
- `cluster`: intended for production runs with Slurm, Singularity containers, Google Sheets integration, and S3 upload.

The configured paths in `nextflow.config` are specific to the current EMBL/project environment. Override paths with environment variables such as:

```bash
RAWDIR=/path/to/raw OUTDIR=/path/to/output LOGDIR=/path/to/logs ./main.sh interactive
```

or, for SEM:

```bash
bash ./sem_main.sh \
  --profile interactive \
  --rawdir /path/to/sem/raw \
  --outdir /path/to/output \
  --logdir /path/to/logs \
  --work_dir /scratch/rheinnec/other_sem_work
```

## External Dependencies

The workflows expect several tools and services depending on the run mode:

- Nextflow
- Slurm, for cluster runs
- Singularity/Apptainer, for containerized cluster runs
- R with tidyverse-style packages for discovery, logging, and table generation
- Python image-processing libraries such as `mrcfile`, `numpy`, `scipy`, `scikit-image`, `pandas`, `matplotlib`, and `tifffile`
- IMOD for TEM blending/correction steps
- EuBI-Bridge for OME-Zarr conversion
- MinIO client (`mc`) for S3 upload/listing
- Google Sheets/Drive credentials when using `sheet_mode=google`

Container definition files for the main environments are stored in `container/`.

## Outputs

Typical TEM outputs include:

- `images_to_process.csv`
- `all_datasets.tsv`
- local or Google image log
- blended/corrected MRC files
- gradient QC PNGs and metrics TSVs
- overview PNGs
- image intensity statistics
- OME-Zarr datasets
- S3 collection table

Typical SEM outputs include:

- `images_to_process.csv`
- `all_datasets.tsv`
- local or Google image log
- metadata JSON files
- pixel-size TSV files
- OME-Zarr datasets
- S3 collection table

## Notes and Caveats

- Several paths, bucket names, and Google Sheet URLs are project-specific and currently encoded in workflow configs or scripts.
- Google-backed modes require a service-account key JSON file configured through `google_key`.
- `DRYRUN=TRUE` limits processing candidates and is useful for discovery/debugging.
- `RESUME=TRUE` enables Nextflow cache reuse where supported by the launcher scripts.
- `tem/crop_omezarr_by_mask.py` appears to be experimental or stale: it contains OME-Zarr cropping helpers, but the current main function reads an MRC input and is not wired into the active TEM workflow.

## Development Notes

Before changing workflow behavior, check:

- The relevant `*.nf` process definitions.
- The matching `nextflow.config` profile and container assignments.
- Whether the script is used by the workflow or is a downstream/manual analysis helper.
- Whether the change affects local, interactive, and cluster modes differently.
