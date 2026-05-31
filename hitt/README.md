# HITT table-driven workflow

This workflow converts a Google Sheet or local table of large image directories into OME-Zarr and optionally uploads the outputs to S3.

The input table must contain a `tmp_copy_path` column. By default, interactive and cluster runs read this Google Sheet:

```text
https://docs.google.com/spreadsheets/d/1ePRpa56mmMvCeRTLXmwOywOLy5_I3AFrxJepSUYGR1s/edit?gid=0#gid=0
```

Local table input is still supported for development:

```text
tmp_copy_path
/scratch/rheinnec/tmp_hitt/TES_10to40_20231003_PM_01_epo_03
/scratch/rheinnec/tmp_hitt/TES_10to40_20231003_PM_01_epo_04
```

For each row, the workflow expects the image input below that directory at:

```text
recon_111_1/tomo
```

and writes OME-Zarr output to:

```text
omezarr
```

Before conversion, the workflow stages a renamed copy of `slice_*.tif` / `slice_*.tiff` files in the Nextflow work directory so the stack starts at `Z0001.tif` and increments by one. The original `tomo` directory is left untouched. Previously normalized `Z*.tif` stacks are also accepted for development recovery.

By default, staged images are converted from `float32` to `uint16` using stack-wide `0.1` and `99.9` percentiles. Disable this when original reconstructed values are needed:

```bash
bash hitt_main.sh interactive --convert_uint16 FALSE
```

Per-image renaming and intensity-conversion TSV logs are written under the workflow logs.

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
  --x_scale 100 \
  --y_scale 100 \
  --s3_bucket s3embl/hitttest
```

`workflow_stage` supports:

- `discover`: parse the table and write `images_to_process.csv` / `all_datasets.tsv`.
- `process`: renumber slice files and convert listed images to OME-Zarr.
- `all`: renumber slice files, convert, upload to S3, collect the S3 listing, and write `hitt_collection_table`.

Uploads copy the contents of each local `omezarr` directory into an S3 prefix named after the original image folder, for example:

```text
s3embl/hitttest/TES_10to40_20231003_PM_01_epo_03/
```

During development, conversion always removes and rebuilds the local `omezarr` folder.

The collection table is written to the `hitt_collection_table` sheet in:

```text
https://docs.google.com/spreadsheets/d/1ePRpa56mmMvCeRTLXmwOywOLy5_I3AFrxJepSUYGR1s/edit?gid=1582290308#gid=1582290308
```
