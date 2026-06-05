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
  metadata <- fromJSON(path, simplifyVector=FALSE)
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
    channels=list(metadata$channels %||% list())
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
    s3_prefix=str_match(s3_raw, "^([^/]+(?:\\.zarr)?)/(?:\\.zattrs|\\.zgroup|Z_zset\\.zarr/(?:\\.zattrs|\\.zgroup))$")[, 2],
    name=str_remove(s3_prefix, "\\.zarr$")
  ) %>%
  filter(!is.na(name), name != "") %>%
  distinct(name, .keep_all=TRUE) %>%
  mutate(
    uri=file.path(s3_public_prefix(s3_bucket), s3_prefix, "/")
  ) %>%
  select(uri, name, s3_prefix, s3_raw)

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
preferred_channel_order <- c("GFP", "PE", "ChloA", "TL", "DAPI")

color_for_display <- function(display, fallback) {
  compact <- str_replace_all(tolower(display %||% ""), "[^a-z0-9]+", "")
  case_when(
    str_detect(compact, "gfp") ~ "green",
    str_detect(compact, "tl") ~ "white",
    str_detect(compact, "chloa") | str_detect(compact, "chlorophyll") ~ "red",
    str_detect(compact, "pe") ~ "yellow",
    TRUE ~ fallback
  )
}

sanitize_channel_display <- function(value, index) {
  value <- value %||% paste0("channel_", index)
  value <- str_replace_all(as.character(value), "[^A-Za-z0-9]+", "_") %>%
    str_replace_all("^_|_$", "")
  ifelse(value == "", paste0("channel_", index), value)
}

normalize_channels <- function(channels, size_c=NA_integer_) {
  if (is.null(channels) || length(channels) == 0) {
    return(list(list(index=0L, label="channel_0", display="channel_0", color=default_channel_colors[[1]])))
  }

  normalized <- map(seq_along(channels), function(i) {
    channel <- channels[[i]]
    index <- as.integer(channel$index %||% (i - 1L))
    label <- channel$label %||% paste0("channel_", index)
    display <- channel$display %||% sanitize_channel_display(label, index)
    color <- channel$color %||% default_channel_colors[[(index %% length(default_channel_colors)) + 1]]
    contrast_limits <- channel$contrast_limits %||% ""
    display <- sanitize_channel_display(display, index)
    list(
      index=index,
      label=as.character(label),
      display=display,
      color=as.character(color_for_display(display, color)),
      contrast_limits=as.character(contrast_limits)
    )
  })

  normalized <- normalized[!duplicated(map_chr(normalized, ~tolower(.x$display)))]
  if (length(normalized) > length(preferred_channel_order)) {
    preferred <- list()
    for (term in preferred_channel_order) {
      matches <- keep(
        normalized,
        ~str_detect(tolower(.x$display), fixed(tolower(term))) ||
          str_detect(tolower(.x$label), fixed(tolower(term)))
      )
      if (length(matches) > 0) {
        match <- matches[[1]]
        match$display <- term
        match$label <- term
        match$color <- color_for_display(term, match$color)
        preferred[[length(preferred) + 1L]] <- match
      }
    }
    if (length(preferred) > 0) {
      normalized <- preferred
    }
  }
  if (!is.na(size_c) && size_c > 0) {
    normalized <- normalized[seq_len(min(length(normalized), size_c))]
  }
  normalized <- imap(normalized, function(channel, index) {
    channel$index <- index - 1L
    channel
  })
  normalized
}

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
    site=str_extract(source_name, "^[A-Za-z]+"),
    view=coalesce(site, "cryo"),
    grid=coalesce(site, "cryo"),
    grid_index=row_number() - 1L,
    grid_position=paste0("(", grid_index %% 5L, ",", grid_index %/% 5L, ")"),
    channels=map2(channels, size_c, normalize_channels),
    exclusive=FALSE,
    blend="sum",
    format="OmeZarr",
    type="intensities"
  )

col_table <- base_table %>%
  unnest_longer(channels) %>%
  mutate(
    channel=map_int(channels, "index"),
    channel_label=map_chr(channels, "label"),
    display=map_chr(channels, "display"),
    color=map_chr(channels, "color"),
    contrast_limits=map_chr(channels, "contrast_limits"),
    name=paste0(source_name, "_c", channel, "_", display)
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
    format
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
