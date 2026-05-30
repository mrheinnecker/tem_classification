# HITT table-driven workflow

This workflow converts a table of large image directories into OME-Zarr and optionally uploads the outputs to S3.

The input table must contain a `tmp_copy_path` column:

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
  --input_table /scratch/rheinnec/tmp_hitt/hitt_images.tsv \
  --workflow_stage process
```

Run conversion and upload:

```bash
cd hitt
bash hitt_main.sh cluster \
  --input_table /scratch/rheinnec/tmp_hitt/hitt_images.tsv \
  --workflow_stage all
```

Useful overrides:

```bash
bash hitt_main.sh interactive \
  --input_table /scratch/rheinnec/tmp_hitt/hitt_images.tsv \
  --x_scale 100 \
  --y_scale 100 \
  --s3_bucket s3embl/hitttest \
  --overwrite FALSE
```

`workflow_stage` supports:

- `discover`: parse the table and write `images_to_process.csv` / `all_datasets.tsv`.
- `process`: convert listed images to OME-Zarr.
- `all`: convert, upload to S3, and collect the S3 listing.

The MoBIE collection table step is intentionally left as a TODO in `wfHITT.nf` until the target table schema is finalized.
