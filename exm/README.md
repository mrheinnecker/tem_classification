# EXM table-driven workflow

Expansion microscopy (EXM) workflow. Same structure as the CRYO workflow (it was started as a copy of it):
it reads listed Nikon `.nd2` files, extracts pixel-size metadata, prepares each raw file for conversion,
converts it to OME-Zarr (zarr format 3 by default) with EuBI-Bridge, uploads completed datasets to S3, and writes a collection table.

```text
CHECKEXISTINGEXMS3FILES -> SELECTEXMIMAGES -> EXTRACTEXMMETADATA -> PREPAREEXMINPUT
  -> EUBIEXMCONVERSION -> PATCHEXMOMEZARRMETADATA -> S3UPLOADEXM -> COLLECTEXMS3FILES -> MAKEEXMCOLLECTIONTABLE
```

Before selecting datasets, the workflow lists the top level of the configured S3 bucket with `mc ls`.
A dataset only counts as present when its root metadata (`zarr.json` or `.zattrs`) is on S3; the upload copies the root metadata last,
so incomplete uploads are listed in `incomplete_s3_entries.txt` and processed again.

## Input data

Nikon spinning-disk (CSU-W1 SoRa) z-stacks saved as `.nd2`, one file per channel:

```text
Img0098_ChannelDAPI (Single EM)_Seq0071.nd2
Img0098_ChannelFITC (Single EM)_Seq0070.nd2
Img0098_ChannelTRITC (Single EM)_Seq0069.nd2
Img0098_ChannelCy5 (Single EM)_Seq0068.nd2
```

All files with the same folder and image prefix (`Img0098`) form one dataset. The channels are merged into one
multi-channel OME-Zarr, ordered by excitation wavelength (DAPI, FITC, TRITC, Cy5); names and colors come from the `.nd2` metadata.

## Input table

Google Sheet (tab `exm_input_table`) or local TSV/CSV with one path column (`FilePath`, `raw_path`, `file_path`, `filepath`, `file`, `source_path` or `path`).
A row can be a single `.nd2` file or a folder (all `.nd2` files in it are used); duplicates are dropped.

The dataset name (S3 and collection table) is taken from, in this order: a `dataset_name` column, the `shortname` column
(e.g. `BAR_Img0093`), or `<folder name>_<image prefix>`. Use the same value on all channel rows of an image; the workflow stops if
names are not unique. A `filename` column (raw file names) is ignored. The letters at the start of the name (e.g. `BAR`) are used as
view/grid in the collection table.

Optional columns: `dataset_name`, `shortname`, `convert` (`0`/`FALSE`/`no` skips an image), `req_mem`, and pixel-size overrides
`x_scale`, `y_scale`, `z_scale`, `scale_unit` (`nm`, `um`, `mm`); non-numeric values are ignored with a warning.

Note: the pixel size written to the OME-Zarr is the one stored in the `.nd2` (42.14 nm x 42.14 nm x 400 nm for the example data),
i.e. of the expanded sample. If the pre-expansion size is wanted, provide corrected values via the overrides.

## Processing steps

- `extract_metadata.py`: reads all channel files of a dataset (`nd2` package), checks that Z/Y/X shape and pixel size agree,
  writes `<name>_metadata.json`, `<name>_pixel_size.tsv` and the full per-file metadata `<name>_nd2_metadata.json`.
- `prepare_input.py`: merges the channels into one CZYX OME-TIFF in the work directory (one channel in memory at a time)
  and adds per-channel contrast limits (0.1 / 99.9 percentiles).
- EuBI-Bridge converts the OME-TIFF to OME-Zarr.
- `patch_omezarr_metadata.py`: writes `omero.channels` and an `exm_metadata` block into the root attributes
  (`zarr.json` for zarr v3, `.zattrs` for v2) and copies the raw metadata to `nd2_metadata/nd2_metadata.json`.

## Run

Edit and submit `launch_wfEXM.sh` in the repo root, or run directly:

```bash
bash exm/exm_main.sh interactive \
  --sheet_mode google \
  --sheet_url "https://docs.google.com/spreadsheets/d/..." \
  --sheet_name "exm_input_table" \
  --workflow_stage all \
  --dryrun TRUE --dryrun_n 2
```

Stages: `discover` (selection only), `process` (convert, no upload), `all` (convert, upload, collection table),
`collection` (rebuild the collection table from S3 and the persisted metadata).

## Outputs

- S3: `<s3_bucket>/<dataset_name>.ome.zarr/`, default bucket `s3test/imatrec/central_data_processing/exm`
  (public URL `https://schwab.buckets.embl.de/imatrec/central_data_processing/exm/...`)
- Logs, Nextflow trace/report/timeline/dag and metadata: `/g/schwab/biobank_logs/exm/wfEXM_<timestamp>`
- Collection table: Google Sheet tab `exm_collection_table`

## Containers

- `nd2_to_tiff.sif` (metadata, preparation, patching), build from `container/nd2_to_tiff.def`:
  `singularity build /g/schwab/marco/container_devel/nd2_to_tiff.sif container/nd2_to_tiff.def`
- `eubibridge.sif`, `mc_client.sif`, `probeDesign_rtool.sif` as in the other workflows.
