# HITT table-driven workflow

This workflow copies remote HITT image stacks into scratch, converts them into OME-Zarr, and optionally uploads the outputs to S3.

The input table should contain a `source_path` column with the remote dataset path or remote `tomo` directory. For compatibility, `remote_path` and `tmp_copy_path` are also accepted as column names. By default, interactive and cluster runs read this Google Sheet:

```text
https://docs.google.com/spreadsheets/d/1ePRpa56mmMvCeRTLXmwOywOLy5_I3AFrxJepSUYGR1s/edit?gid=0#gid=0
```

Example:

```text
source_path
/mnt/ximg/2024/p3l-yschwab/RECON/20240414/RAW_DATA/BIL_10to40_20231003_PM_01_epo_03/recon_111_1/tomo
```

Before running the workflow, export the SSH password in the launch shell:

```bash
export SSHPASS='PASSWORD'
```

For each row, `rsync` copies the stack incrementally into:

```text
/scratch/rheinnec/tmp_hitt/<dataset_name>/recon_111_1/tomo
```

Use `--copy_data FALSE` to process data that is already present in scratch without contacting the remote server.

Before conversion, the workflow stages a renamed copy of `slice_*.tif` / `slice_*.tiff` files in the Nextflow work directory so the stack starts at `Z0001.tif` and increments by one. The scratch `tomo` directory is left untouched. Previously normalized `Z*.tif` stacks are also accepted for development recovery.

By default, staged images are converted from `float32` to `uint16` using stack-wide `0.1` and `99.9` percentiles. Disable this when original reconstructed values are needed:

```bash
bash hitt_main.sh interactive --convert_uint16 FALSE
```

Per-image renaming and intensity-conversion TSV logs are written under the workflow logs.

The workflow also calculates stack-wide `min_gray`, `max_gray`, and `contrast_limits` values from the staged TIFF slices. In `all` mode these display values are added to `hitt_collection_table`; individual TSV files are written under `logs/.../image_stats`.

## Run examples

```bash
cd hitt
bash hitt_main.sh interactive \
  --sheet_mode google \
  --workflow_stage process
```

Run conversion, upload, and write the collection table:

```bash
cd hitt
bash hitt_main.sh cluster \
  --sheet_mode google \
  --workflow_stage all
```

Useful overrides:

```bash
bash hitt_main.sh interactive \
  --sheet_mode google \
  --x_scale 650 \
  --y_scale 650 \
  --z_scale 650 \
  --s3_bucket s3embl/hitttest
```

`workflow_stage` supports:

- `discover`: parse the table and write `images_to_process.csv` / `all_datasets.tsv`.
- `process`: copy remote stacks, renumber staged slice files, and convert listed images to OME-Zarr.
- `all`: copy remote stacks, renumber staged slice files, convert, upload to S3, collect the S3 listing, and write `hitt_collection_table`.

Uploads copy the contents of each local `omezarr` directory into an S3 prefix named after the original image folder, for example:

```text
s3embl/hitttest/TES_10to40_20231003_PM_01_epo_03/
```

During development, conversion always removes and rebuilds the local `omezarr` folder.

The collection table is written to the `hitt_collection_table` sheet in:

```text
https://docs.google.com/spreadsheets/d/1ePRpa56mmMvCeRTLXmwOywOLy5_I3AFrxJepSUYGR1s/edit?gid=1582290308#gid=1582290308
```
