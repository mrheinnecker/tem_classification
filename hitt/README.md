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

Pass the SSH password when starting the workflow:

```bash
bash hitt_main.sh cluster --password 'PASSWORD' --workflow_stage all
```

The launcher keeps the password out of repository files and exports `SSHPASS` immediately before the `sshpass` copy command.

Because command-line values can be stored in shell history, you can alternatively keep the launch command clean:

```bash
export HITT_SSHPASS='PASSWORD'
bash hitt_main.sh cluster --workflow_stage all
```

For each row, `rsync` copies the stack incrementally into:

```text
/scratch/rheinnec/tmp_hitt/<dataset_name>/recon_111_1/tomo
```

Use `--copy_data FALSE` to process data that is already present in scratch without contacting the remote server.

After copying, the workflow samples every TIFF slice and detects a conservative sample-bearing Z range before conversion. By default, a bright-voxel threshold is calculated from the stack-wide `99.0` percentile. A slice is considered sample-bearing when at least `0.5%` of its sampled pixels meet that threshold. Short gaps are bridged, the largest detected run is selected, and ten padding slices are retained on each side.

The scratch `tomo` directory is never cropped or deleted. The selected range is only applied when preparing the temporary staged stack for conversion. Per-slice decisions and a crop summary are written under `logs/.../crop_analysis`. If no reliable sample-bearing run is detected, the workflow keeps the full stack.

Useful crop overrides:

```bash
bash hitt_main.sh interactive \
  --crop_stack TRUE \
  --crop_bright_threshold auto \
  --crop_auto_percentile 99.0 \
  --crop_min_bright_fraction 0.005 \
  --crop_padding_slices 10
```

Use a numeric `--crop_bright_threshold` when a stable reconstructed gray-value cutoff is known. Use `--crop_stack FALSE` to retain the complete Z-stack while still writing crop-analysis logs.

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
- `process`: copy remote stacks, detect a conservative Z crop, renumber staged slice files, and convert listed images to OME-Zarr.
- `all`: copy remote stacks, detect a conservative Z crop, renumber staged slice files, convert, upload to S3, collect the S3 listing, and write `hitt_collection_table`.

Uploads copy the contents of each local `omezarr` directory into an S3 prefix named after the original image folder, for example:

```text
s3embl/hitttest/TES_10to40_20231003_PM_01_epo_03/
```

During development, conversion always removes and rebuilds the local `omezarr` folder.

The collection table is written to the `hitt_collection_table` sheet in:

```text
https://docs.google.com/spreadsheets/d/1ePRpa56mmMvCeRTLXmwOywOLy5_I3AFrxJepSUYGR1s/edit?gid=1582290308#gid=1582290308
```
