# HITT table-driven workflow

This workflow copies remote HITT image stacks into scratch, converts them into OME-Zarr, and optionally uploads the outputs to S3.

Before selecting datasets, the workflow lists only the top level of the configured S3 bucket with `mc ls`. Any dataset with an uploaded `<dataset_name>/` prefix is excluded from `images_to_process.csv`, independently of the Nextflow `-resume` cache. The complete input table is still written to `all_datasets.tsv` with `s3_omezarr_present` and `needs_processing` columns.

For a non-dry-run `all` or `collection` run, the workflow stops if S3 cannot be listed. This avoids accidentally reprocessing every dataset or writing an incomplete collection table when the S3 client or connection is unavailable. Discovery, process-only, and dry-run modes can continue with an empty S3 listing.

The input table should contain a `source_path` column with the remote dataset path or remote `tomo` directory. For compatibility, `remote_path` and `tmp_copy_path` are also accepted as column names. By default, interactive and cluster runs read this Google Sheet:

```text
https://docs.google.com/spreadsheets/d/1ePRpa56mmMvCeRTLXmwOywOLy5_I3AFrxJepSUYGR1s/edit?gid=0#gid=0
```

Example:

```text
source_path
/mnt/ximg/2024/p3l-yschwab/RECON/20240414/RAW_DATA/BIL_10to40_20231003_PM_01_epo_03/recon_111_1/tomo
```

Only rows with `convert=1` are included in `images_to_process.csv`. Rows with `convert=0`, blank values, or a missing `convert` column remain visible in `all_datasets.tsv` but are not copied, cropped, converted, or uploaded. This allows datasets awaiting manual review to stay in the input table.

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

Remote copying is limited to ten concurrent `COPYHITTDATA` tasks by default to avoid overloading the external server. Adjust only this process limit with:

```bash
bash hitt_main.sh cluster --copy_max_forks 10
```

Copy failures are retried up to two times. Failures in later per-dataset steps are ignored so one problematic dataset does not stop the remaining batch. Global coordination steps, such as S3 listing and collection-table generation, still fail loudly.

After copying, the workflow samples every TIFF slice and detects a conservative sample-bearing Z range before conversion. By default, a bright-voxel threshold is calculated from the stack-wide `99.0` percentile. A slice is considered sample-bearing when at least `0.5%` of its sampled pixels meet that threshold. Short gaps are bridged, the largest detected run is selected, and ten padding slices are retained on each side.

The scratch `tomo` directory is never cropped or deleted. The selected range is only applied when preparing the temporary staged stack for conversion. Per-slice decisions, a crop summary, and a combined boundary QC PNG are written under `logs/.../crop_analysis`. The PNG shows the last excluded slice on the low-Z side on the left and the first excluded slice on the high-Z side on the right. If only one boundary has excluded slices, the PNG contains that available boundary image. If no reliable sample-bearing run is detected, the workflow keeps the full stack.

Crop parameters can be set per dataset with columns in the input table:

```text
crop_stack
crop_bright_threshold
crop_auto_percentile
crop_min_bright_fraction
crop_padding_low_slices
crop_padding_high_slices
crop_start
crop_end
```

Blank or missing values fall back to the launcher defaults. During migration, a legacy `crop_padding_slices` table column is also accepted and is applied to both edges unless an edge-specific value is present.

If both `crop_start` and `crop_end` are set for a dataset, they override automatic crop detection. The range is 1-based and inclusive: `crop_start=500` and `crop_end=1500` keeps slices 500 through 1500 and removes everything outside that range. If `crop_end` is larger than the stack length, the workflow uses the last available slice.

Useful crop overrides:

```bash
bash hitt_main.sh interactive \
  --crop_stack TRUE \
  --crop_bright_threshold auto \
  --crop_auto_percentile 99.0 \
  --crop_min_bright_fraction 0.005 \
  --crop_padding_low_slices 10 \
  --crop_padding_high_slices 10
```

Use a numeric `--crop_bright_threshold` when a stable reconstructed gray-value cutoff is known. Use `--crop_stack FALSE` to retain the complete Z-stack while still writing crop-analysis logs.

Before conversion, the workflow stages a renamed copy of `slice_*.tif` / `slice_*.tiff` files in the Nextflow work directory so the stack starts at `Z0001.tif` and increments by one. The scratch `tomo` directory is left untouched. Previously normalized `Z*.tif` stacks are also accepted for development recovery.

By default, staged images are converted from `float32` to `uint16` using stack-wide `0.1` and `99.9` percentiles. Disable this when original reconstructed values are needed:

```bash
bash hitt_main.sh interactive --convert_uint16 FALSE
```

Per-image renaming and intensity-conversion TSV logs are written under the workflow logs.

If TIFF slices at the outer start or end of a stack have a different XY shape, the staging step drops those slices before conversion. Each decision is recorded in `<image_name>_shape_crop.tsv`. A shape mismatch inside the retained stack still stops the workflow because automatically removing an internal slice would be unsafe.

The workflow also calculates stack-wide `min_gray`, `max_gray`, and `contrast_limits` values from the staged TIFF slices. In `all` mode these display values are added to `hitt_collection_table`; individual TSV files are written under `logs/.../image_stats`.

Dataset names starting with `Vigo_` are mapped to site code `VIG` in the collection table. Existing three-letter prefixes such as `ROS`, `ATH`, `BIL`, and `POR` are kept as uppercase site codes.

Image-statistics TSV files are also persisted under:

```text
/g/schwab/marco/central_data_processing/hitt/image_stats
```

This allows the collection table to be rebuilt without repeating image processing:

```bash
bash hitt_main.sh cluster --workflow_stage collection
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
  --x_scale 650 \
  --y_scale 650 \
  --z_scale 650 \
  --s3_bucket s3embl/hitttest
```

`workflow_stage` supports:

- `discover`: parse the table and write `images_to_process.csv` / `all_datasets.tsv`.
- `process`: copy remote stacks, detect a conservative Z crop, renumber staged slice files, and convert listed images to OME-Zarr.
- `all`: copy remote stacks, detect a conservative Z crop, renumber staged slice files, convert, upload to S3, collect the S3 listing, and write `hitt_collection_table`.
- `collection`: query S3 and rebuild `hitt_collection_table` from the input table and persistent image statistics without processing images.

Uploads copy the contents of each local `omezarr` directory into an S3 prefix named after the original image folder, for example:

```text
s3embl/hitttest/TES_10to40_20231003_PM_01_epo_03/
```

During development, conversion always removes and rebuilds the local `omezarr` folder.

The collection table is written to the `hitt_collection_table` sheet in:

```text
https://docs.google.com/spreadsheets/d/1ePRpa56mmMvCeRTLXmwOywOLy5_I3AFrxJepSUYGR1s/edit?gid=1582290308#gid=1582290308
```
