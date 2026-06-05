# CRYO table-driven workflow

This workflow reads listed light-microscopy Z-stack files, extracts pixel-size metadata, prepares each raw file for conversion, converts it to OME-Zarr with EuBI-Bridge, uploads completed datasets to S3, and writes a collection table.

Before selecting datasets, the workflow lists the configured S3 bucket with `mc ls --recursive`. Any dataset whose uploaded `<dataset_name>.zarr/` prefix contains a root `.zattrs` or `.zgroup` marker is excluded from `images_to_process.csv`, independently of the Nextflow `-resume` cache. The complete input table is still written to `all_datasets.tsv` with `s3_omezarr_present` and `needs_processing` columns.

For a non-dry-run `all` or `collection` run, the workflow stops if S3 cannot be listed. This avoids accidentally reprocessing every dataset or writing an incomplete collection table when S3 is unavailable.

## Input table

The input table can be a Google Sheet or local TSV/CSV. It should contain one raw-file column. Accepted names are:

```text
raw_path
file_path
filepath
file
source_path
path
```

Example:

```text
raw_path
/g/example/light_microscopy/sample_001.ome.tif
```

If a `convert` column is present, values such as `0`, `FALSE`, or `no` keep the row in `all_datasets.tsv` but skip processing. If `convert` is absent, rows are processed by default unless already present in S3.

Dataset names are derived from the raw filename unless a `filename` column is present.

## Pixel-size metadata

The workflow needs X pixel size, Y pixel size, and Z spacing in nanometers for EuBI-Bridge conversion.

For CZI inputs, `extract_metadata.py` reads Zeiss scaling metadata from the CZI XML and converts meter-scale values to nanometers.

For TIFF/OME-TIFF inputs, `extract_metadata.py` tries to read:

- OME `PhysicalSizeX`, `PhysicalSizeY`, and `PhysicalSizeZ`
- ImageJ `spacing`
- TIFF resolution tags for X/Y when available

You can override or provide missing values in the table with:

```text
x_scale
y_scale
z_scale
scale_unit
```

Aliases such as `x_pixel_size_nm`, `y_pixel_size_nm`, and `z_spacing_nm` are also accepted. `scale_unit` supports `nm`, `um`, and `mm`; the workflow converts values to nanometers before calling EuBI-Bridge.

Launcher defaults are also available:

```bash
bash cryo_main.sh interactive \
  --default_x_scale 250 \
  --default_y_scale 250 \
  --default_z_scale 1000 \
  --scale_unit nm
```

## CZI preparation

Zeiss `.czi` files are not sent directly to EuBI-Bridge. The workflow first runs `prepare_input.py`, which converts each CZI into an intermediate OME-TIFF inside the Nextflow work directory. EuBI-Bridge then converts that OME-TIFF to OME-Zarr.

Non-CZI inputs are linked or copied into the same prepared-input directory and then passed to EuBI-Bridge unchanged. The original raw files are not modified.

## Run examples

Discover selected rows without conversion:

```bash
cd cryo
bash cryo_main.sh local \
  --sheet_mode local \
  --input_table /path/to/cryo_images.tsv \
  --workflow_stage discover
```

Run conversion without upload:

```bash
cd cryo
bash cryo_main.sh interactive \
  --sheet_mode google \
  --sheet_url "https://docs.google.com/spreadsheets/d/..." \
  --sheet_name "cryo_input_table" \
  --workflow_stage process
```

Run conversion, upload, and write the collection table:

```bash
cd cryo
bash cryo_main.sh cluster \
  --sheet_mode google \
  --sheet_url "https://docs.google.com/spreadsheets/d/..." \
  --sheet_name "cryo_input_table" \
  --collection_table_url "https://docs.google.com/spreadsheets/d/..." \
  --collection_table_sheet "cryo_collection_table" \
  --s3_bucket "s3embl/imatrec/central_data_processing/cryo" \
  --workflow_stage all
```

Rebuild only the collection table from S3 and persisted metadata:

```bash
bash cryo_main.sh cluster --workflow_stage collection
```

## Workflow stages

- `discover`: parse the table and write `images_to_process.csv` / `all_datasets.tsv`.
- `process`: extract metadata, prepare inputs, and convert listed raw files to OME-Zarr.
- `all`: extract metadata, prepare inputs, convert, upload to S3, and write the collection table.
- `collection`: query S3 and rebuild the collection table from the input table plus persisted metadata.

Metadata JSON and pixel-size TSV files are persisted under `--persistent_metadata_dir`, defaulting to `<main_dir>/metadata` from the launcher or the profile-specific central-data path on the cluster.

Uploaded datasets are written to S3 as:

```text
<s3_bucket>/<dataset_name>.zarr/
```

The collection table keeps `name` as `<dataset_name>` but points `uri` to the `.zarr` prefix.

For multi-channel CZI data, the collection table is expanded to one row per channel. The original dataset name is kept in `source_name`, while `name` becomes channel-specific, for example:

```text
sample_c0_DAPI
sample_c1_GFP
```

The table also writes `channel`, `channel_label`, `display`, `color`, `blend=sum`, `format=OmeZarr`, `grid`, and `grid_position`. Channels from the same image share the same `grid_position`, and `display` is channel-specific so MoBIE keeps independent display controls for DAPI/GFP/etc.

## Containers

The CRYO workflow uses two separate containers:

- CZI metadata/preparation: `/g/schwab/marco/container_devel/czi_to_tiff.sif`
- EuBI-Bridge conversion: `/g/schwab/marco/container_devel/eubibridge.sif`

Build the CZI preparation container from:

```text
container/czi_to_tiff.def
```

For example:

```bash
singularity build /g/schwab/marco/container_devel/czi_to_tiff.sif container/czi_to_tiff.def
```

This keeps the existing EuBI-Bridge container unchanged and only adds the Zeiss CZI dependencies where they are needed.
