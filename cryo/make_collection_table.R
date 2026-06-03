library(tidyverse)
library(getopt)
library(jsonlite)

spec <- matrix(c(
  "all_s3", "d", 1, "character",
  "all_datasets", "a", 1, "character",
  "metadata_dir", "x", 1, "character",
  "s3_bucket", "b", 1, "character",
  "sheet_mode", "m", 1, "character",
  "google_key", "k", 1, "character",
  "collection_table_url", "u", 1, "character",
  "collection_table_sheet", "s", 1, "character",
  "local_collection_table", "l", 1, "character"
), ncol=4, byrow=TRUE)
opt <- getopt(spec)

value_or_default <- function(value, default) {
  if (is.null(value) || is.na(value) || value == "") default else value
}

sheet_mode <- value_or_default(opt$sheet_mode, "google")
collection_table_url <- value_or_default(opt$collection_table_url, "")
collection_table_sheet <- value_or_default(opt$collection_table_sheet, "cryo_collection_table")
local_collection_table <- value_or_default(opt$local_collection_table, "cryo_collection_table.tsv")
metadata_dir <- value_or_default(opt$metadata_dir, ".")
s3_bucket <- value_or_default(opt$s3_bucket, "s3embl/cryotest")

parse_mc_ls_path <- function(line) {
  parsed <- str_match(line, "^\\[.*?\\]\\s+\\S+\\s+(?:STANDARD\\s+)?(.+)$")[, 2]
  ifelse(
    is.na(parsed),
    str_match(line, "^\\S+\\s+(?:STANDARD\\s+)?(.+)$")[, 2],
    parsed
  )
}

s3_public_prefix <- function(bucket) {
  bucket_path <- bucket %>%
    str_remove("^s3embl/") %>%
    str_remove("/$")
  file.path("https://s3.embl.de", bucket_path)
}

metadata_row <- function(path) {
  metadata <- fromJSON(path)
  tibble(
    name=metadata$name,
    metadata_raw_path=metadata$raw_path %||% "",
    x_scale_nm=metadata$x_scale_nm %||% NA_real_,
    y_scale_nm=metadata$y_scale_nm %||% NA_real_,
    z_scale_nm=metadata$z_scale_nm %||% NA_real_,
    shape=if (!is.null(metadata$shape)) paste(metadata$shape, collapse="x") else "",
    axes=metadata$axes %||% "",
    page_count=metadata$page_count %||% NA_integer_,
    source_suffix=metadata$source_suffix %||% ""
  )
}

`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

all_datasets <- read_tsv(opt$all_datasets, col_types=cols(.default=col_character())) %>%
  distinct(filename, .keep_all=TRUE)

s3_root_markers <- read_lines(opt$all_s3) %>%
  as_tibble() %>%
  mutate(
    s3_raw=parse_mc_ls_path(value),
    s3_raw=str_remove(s3_raw, "/$"),
    name=str_match(s3_raw, "^([^/]+)/(?:\\.zattrs|\\.zgroup|Z_zset\\.zarr/(?:\\.zattrs|\\.zgroup))$")[, 2]
  ) %>%
  filter(!is.na(name), name != "") %>%
  distinct(name, .keep_all=TRUE) %>%
  mutate(
    uri=file.path(s3_public_prefix(s3_bucket), name, "/")
  ) %>%
  select(uri, name, s3_raw)

if (nrow(s3_root_markers) == 0) {
  stop("No CRYO OME-Zarr datasets found in S3 listing.")
}

metadata_files <- list.files(
  metadata_dir,
  pattern="_metadata\\.json$",
  full.names=TRUE
)

metadata_table <- tibble(
  name=character(),
  metadata_raw_path=character(),
  x_scale_nm=double(),
  y_scale_nm=double(),
  z_scale_nm=double(),
  shape=character(),
  axes=character(),
  page_count=integer(),
  source_suffix=character()
)
if (length(metadata_files) > 0) {
  metadata_table <- metadata_files %>%
    map_dfr(metadata_row) %>%
    distinct(name, .keep_all=TRUE)
} else {
  warning("No *_metadata.json files found; collection table will use sheet metadata only.")
}

col_table <- s3_root_markers %>%
  left_join(
    all_datasets %>%
      select(
        name=filename,
        shortname,
        raw_path,
        output_path,
        req_mem,
        sheet_x_scale=x_scale,
        sheet_y_scale=y_scale,
        sheet_z_scale=z_scale,
        sheet_scale_unit=scale_unit,
        everything()
      ),
    by="name"
  ) %>%
  left_join(metadata_table, by="name") %>%
  mutate(
    x_scale_nm=coalesce(as.character(x_scale_nm), sheet_x_scale),
    y_scale_nm=coalesce(as.character(y_scale_nm), sheet_y_scale),
    z_scale_nm=coalesce(as.character(z_scale_nm), sheet_z_scale),
    view=name,
    grid=name,
    exclusive=TRUE
  ) %>%
  select(
    uri,
    name,
    view,
    grid,
    raw_path,
    x_scale_nm,
    y_scale_nm,
    z_scale_nm,
    shape,
    axes,
    page_count,
    source_suffix,
    exclusive,
    everything()
  )

write_tsv(col_table, file=local_collection_table)

if (sheet_mode == "google") {
  if (collection_table_url == "") {
    stop("--collection_table_url is required when --sheet_mode google")
  }
  json_key <- opt$google_key
  if (is.null(json_key) || is.na(json_key)) {
    stop("--google_key is required when --sheet_mode google")
  }

  library(googlesheets4)
  library(googledrive)
  gs4_auth(path=json_key)
  drive_auth(path=json_key)
  write_sheet(col_table, ss=collection_table_url, sheet=collection_table_sheet)
}

write_tsv(tibble(done="done"), file="done.tsv")
