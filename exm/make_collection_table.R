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
collection_table_sheet <- value_or_default(opt$collection_table_sheet, "exm_collection_table")
local_collection_table <- value_or_default(opt$local_collection_table, "exm_collection_table.tsv")
metadata_dir <- value_or_default(opt$metadata_dir, ".")
s3_bucket <- value_or_default(opt$s3_bucket, "s3test/imatrec/central_data_processing/exm")

parse_mc_ls_path <- function(line) {
  parsed <- str_match(line, "^\\[.*?\\]\\s+\\S+\\s+(?:STANDARD\\s+)?(.+)$")[, 2]
  ifelse(
    is.na(parsed),
    ## plain names (listing of the mounted S3 share) are used as they are
    coalesce(str_match(line, "^\\S+\\s+(?:STANDARD\\s+)?(.+)$")[, 2], line),
    parsed
  )
}

## the mc alias (e.g. s3test) is dropped, the rest of the path is served by the public endpoint
s3_public_prefix <- function(bucket) {
  bucket_path <- bucket %>%
    str_remove("^[^/]+/") %>%
    str_remove("/$")
  file.path("https://schwab.buckets.embl.de", bucket_path)
}

metadata_row <- function(path) {
  metadata <- fromJSON(path, simplifyVector=FALSE)
  channels <- metadata$channels %||% list()
  channel_stats <- metadata$channel_stats %||% list()
  if (length(channels) > 0 && length(channel_stats) > 0) {
    stats_by_index <- set_names(channel_stats, map_chr(channel_stats, ~as.character(.x$index %||% "")))
    channels <- map(channels, function(channel) {
      stats <- stats_by_index[[as.character(channel$index %||% "")]]
      if (!is.null(stats)) {
        channel$min <- channel$min %||% stats$min
        channel$max <- channel$max %||% stats$max
        channel$contrast_limits <- channel$contrast_limits %||% stats$contrast_limits
      }
      channel
    })
  }
  tibble(
    name=metadata$name,
    metadata_raw_path=metadata$raw_path %||% "",
    x_scale_nm=metadata$x_scale_nm %||% NA_real_,
    y_scale_nm=metadata$y_scale_nm %||% NA_real_,
    z_scale_nm=metadata$z_scale_nm %||% NA_real_,
    shape=if (!is.null(metadata$shape)) paste(metadata$shape, collapse="x") else "",
    axes=metadata$axes %||% "",
    page_count=metadata$page_count %||% NA_integer_,
    source_suffix=metadata$source_suffix %||% "",
    size_c=metadata$size_c %||% NA_integer_,
    channels=list(channels)
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
    s3_prefix=str_match(s3_raw, "^([^/]+(?:\\.ome\\.zarr|\\.zarr))$")[, 2],
    name=s3_prefix %>%
      str_remove("\\.ome\\.zarr$") %>%
      str_remove("\\.zarr$")
  ) %>%
  filter(!is.na(name), name != "") %>%
  distinct(name, .keep_all=TRUE) %>%
  mutate(
    ## paste0, not file.path(..., "/"): on Linux that gives ".ome.zarr//", which the Fiji OME-Zarr reader cannot open
    uri=paste0(s3_public_prefix(s3_bucket), "/", s3_prefix, "/")
  ) %>%
  select(uri, name, s3_prefix, s3_raw)

## only datasets that are (still) in the input table; others on S3 (old test runs, removed rows) are left out
not_in_input <- setdiff(s3_root_markers$name, all_datasets$filename)
if (length(not_in_input) > 0) {
  message(
    "Leaving out ", length(not_in_input), " S3 dataset(s) that are not in the input table: ",
    paste(not_in_input, collapse=", ")
  )
}
s3_root_markers <- s3_root_markers %>%
  filter(name %in% all_datasets$filename)

if (nrow(s3_root_markers) == 0) {
  stop("No EXM OME-Zarr datasets found in S3 listing that are in the input table.")
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
  source_suffix=character(),
  size_c=integer(),
  channels=list()
)
if (length(metadata_files) > 0) {
  metadata_table <- metadata_files %>%
    map_dfr(metadata_row) %>%
    distinct(name, .keep_all=TRUE)
} else {
  warning("No *_metadata.json files found; collection table will use sheet metadata only.")
}

default_channel_colors <- c("red", "green", "yellow", "blue", "magenta", "cyan", "white")

near_square_columns <- function(n) {
  if (n <= 1) {
    return(1L)
  }
  as.integer(ceiling(sqrt(n)))
}

sanitize_channel_display <- function(value, index) {
  value <- value %||% paste0("channel_", index)
  value <- str_replace_all(as.character(value), "[^A-Za-z0-9]+", "_") %>%
    str_replace_all("^_|_$", "") %>%
    ## zoom suffix of some acquisitions: "Cy5 4x (Single EM)1" -> Cy5_4x_1 -> Cy5
    str_remove("_\\d+x(_.*)?$")
  ifelse(value == "", paste0("channel_", index), value)
}

## colors in MoBIE by channel; channels not listed keep the color from the .nd2 metadata
## (white = grey scale)
channel_colors <- c(DAPI="blue", FITC="green", TRITC="magenta", Cy5="white")

## EXM: channel names (DAPI, FITC, TRITC, Cy5) and colors come from the .nd2 metadata
## (extract_metadata.py), contrast limits from prepare_input.py
normalize_channels <- function(channels, size_c=NA_integer_) {
  if (is.null(channels) || length(channels) == 0) {
    return(list(list(index=0L, label="channel_0", display="channel_0", color=default_channel_colors[[1]], contrast_limits="")))
  }

  imap(channels, function(channel, i) {
    index <- as.integer(channel$index %||% (i - 1L))
    label <- channel$label %||% paste0("channel_", index)
    display <- sanitize_channel_display(channel$display %||% label, index)
    list(
      index=index,
      label=as.character(label),
      display=display,
      color=unname(coalesce(
        channel_colors[display],
        as.character(channel$color %||% default_channel_colors[[(index %% length(default_channel_colors)) + 1]])
      )),
      contrast_limits=as.character(channel$contrast_limits %||% "")
    )
  })
}

site_pattern <- "ATH|BAR|KRI|TAL|NAP|BIL|POR"

base_table <- s3_root_markers %>%
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
        sheet_z_scale=z_scale
      ),
    by="name"
  ) %>%
  left_join(metadata_table, by="name") %>%
  mutate(
    x_scale_nm=coalesce(as.character(x_scale_nm), sheet_x_scale),
    y_scale_nm=coalesce(as.character(y_scale_nm), sheet_y_scale),
    z_scale_nm=coalesce(as.character(z_scale_nm), sheet_z_scale),
    source_name=name,
    ## sampling site as in the other data layers: from the dataset name (BAR_Img0093),
    ## else from the raw path (.../ExM_TREC/BAR/...)
    site=coalesce(
      str_extract(source_name, site_pattern),
      str_extract(coalesce(raw_path, metadata_raw_path), paste0("(?<=/)(", site_pattern, ")(?=/)"))
    ),
    view=coalesce(site, "exm"),
    grid=coalesce(site, "exm"),
    channels=map2(channels, size_c, normalize_channels),
    exclusive=FALSE,
    blend="sum",
    format="OmeZarr",
    type="intensities"
  ) %>%
  group_by(grid) %>%
  mutate(
    ## position within the site's grid
    grid_index=row_number() - 1L,
    grid_columns=near_square_columns(n()),
    grid_position=paste0("(", grid_index %% grid_columns, ",", grid_index %/% grid_columns, ")")
  ) %>%
  ungroup() %>%
  select(-grid_columns)

col_table <- base_table %>%
  unnest_longer(channels) %>%
  mutate(
    channel=map_int(channels, "index"),
    channel_label=map_chr(channels, "label"),
    display=map_chr(channels, "display"),
    color=map_chr(channels, "color"),
    contrast_limits=map_chr(channels, "contrast_limits"),
    name=paste0(source_name, "_c", channel, "_", display),
    exclusive=T
  ) %>%
  select(-channels) %>%
  select(
    uri,
    name,
    view,
    grid,
    grid_position,
    channel,
    display,
    color,
    contrast_limits,
    blend,
    format,
    exclusive
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
