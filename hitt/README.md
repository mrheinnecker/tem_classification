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
  --s3_bucket s3embl/hitttest \
  --overwrite FALSE
```

`workflow_stage` supports:

- `discover`: parse the table and write `images_to_process.csv` / `all_datasets.tsv`.
- `process`: convert listed images to OME-Zarr.
- `all`: convert, upload to S3, collect the S3 listing, and write `hitt_collection_table`.

The collection table is written to the `hitt_collection_table` sheet in:

```text
https://docs.google.com/spreadsheets/d/1ePRpa56mmMvCeRTLXmwOywOLy5_I3AFrxJepSUYGR1s/edit?gid=1582290308#gid=1582290308
```
