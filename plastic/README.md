# PLASTIC table-driven workflow

This workflow reads listed Leica `.lif` light-microscopy files, extracts pixel-size metadata, converts each raw file directly to OME-Zarr with EuBI-Bridge, uploads completed datasets to S3, and writes a MoBIE collection table.

Before selecting datasets, the workflow lists the top level of the configured S3 bucket with `mc ls`. Any dataset with an uploaded `<dataset_name>.ome.zarr/` or legacy `<dataset_name>.zarr/` prefix is excluded from `images_to_process.csv`, independently of the Nextflow `-resume` cache.

## Input Table

The input table can be a Google Sheet or local TSV/CSV. It should contain one raw-file column. Accepted names are:

```text
raw_path
file_path
filepath
file
source_path
path
```

If a `convert` column is present, values such as `0`, `FALSE`, or `no` keep the row in `all_datasets.tsv` but skip processing. If `convert` is absent, rows are processed by default unless already present in S3.

Dataset names are derived from the raw filename unless a `filename` column is present.

## Metadata

`extract_metadata.py` uses BioImage with the LIF reader to extract:

- physical X/Y/Z pixel sizes, converted to nanometers
- scene names/count where exposed by the reader
- image axes/shape where exposed by the reader
- channel names where exposed by the reader

You can override or provide missing values in the table with:

```text
x_scale
y_scale
z_scale
scale_unit
```

Aliases such as `x_pixel_size_nm`, `y_pixel_size_nm`, and `z_spacing_nm` are also accepted. `scale_unit` supports `nm`, `um`, and `mm`.

## Conversion

PLASTIC does not run an intermediate OME-TIFF preparation step. It sends the raw `.lif` path directly to EuBI-Bridge:

```text
raw .lif -> eubi to_zarr -> <dataset>.ome.zarr
```

If EuBI needs a specific LIF/stitched-file flag, pass it with:

```bash
--eubi_extra_args "--your-flag value"
```

The launcher includes an empty `--eubi_extra_args ""` placeholder for this.

## Run Examples

Discover selected rows without conversion:

```bash
cd plastic
bash plastic_main.sh local \
  --sheet_mode local \
  --input_table /path/to/plastic_images.tsv \
  --workflow_stage discover
```

Run conversion without upload:

```bash
cd plastic
bash plastic_main.sh interactive \
  --sheet_mode google \
  --sheet_url "https://docs.google.com/spreadsheets/d/..." \
  --sheet_name "plastic_input_table" \
  --workflow_stage process
```

Run conversion, upload, and write the collection table:

```bash
cd plastic
bash plastic_main.sh cluster \
  --sheet_mode google \
  --sheet_url "https://docs.google.com/spreadsheets/d/..." \
  --sheet_name "plastic_input_table" \
  --collection_table_url "https://docs.google.com/spreadsheets/d/..." \
  --collection_table_sheet "plastic_collection_table" \
  --s3_bucket "s3embl/imatrec/central_data_processing/plastic" \
  --workflow_stage all
```

Rebuild only the collection table from S3 and persisted metadata:

```bash
bash plastic_main.sh cluster --workflow_stage collection
```

## Outputs

Uploaded datasets are written to S3 as:

```text
<s3_bucket>/<dataset_name>.ome.zarr/
```

The collection table keeps `name` as `<dataset_name>` but points `uri` to the `.ome.zarr` prefix. Existing legacy `.zarr` uploads are still recognized.

For multi-channel data, the collection table is expanded to one row per channel. Channels from the same image share the same `grid_position`.

## Containers

The PLASTIC workflow uses separate containers:

- LIF metadata extraction: `/g/schwab/marco/container_devel/lif_metadata.sif`
- EuBI-Bridge conversion: `/g/schwab/marco/container_devel/eubibridge.sif`
- S3 access and R/table steps use the same containers as the other workflows.

Build the LIF metadata container from:

```text
container/lif_metadata.def
```

For example:

```bash
singularity build /g/schwab/marco/container_devel/lif_metadata.sif container/lif_metadata.def
```
