library(tidyverse)
library(getopt)

spec <- matrix(c(
  "all_s3", "d", 1, "character",
  "all_datasets", "a", 1, "character",
  "image_stats_dir", "x", 1, "character",
  "sheet_mode", "m", 1, "character",
  "google_key", "k", 1, "character",
  "collection_table_url", "u", 1, "character",
  "collection_table_sheet", "s", 1, "character",
  "local_collection_table", "l", 1, "character"
), ncol=4, byrow=TRUE)
opt <- getopt(spec)

sheet_mode <- opt$sheet_mode
if (is.null(sheet_mode) || is.na(sheet_mode)) {
  sheet_mode <- "google"
}

collection_table_url <- opt$collection_table_url
if (is.null(collection_table_url) || is.na(collection_table_url)) {
  collection_table_url <- "https://docs.google.com/spreadsheets/d/1ePRpa56mmMvCeRTLXmwOywOLy5_I3AFrxJepSUYGR1s/edit?gid=1582290308#gid=1582290308"
}

collection_table_sheet <- opt$collection_table_sheet
if (is.null(collection_table_sheet) || is.na(collection_table_sheet)) {
  collection_table_sheet <- "hitt_collection_table"
}

local_collection_table <- opt$local_collection_table
if (is.null(local_collection_table) || is.na(local_collection_table)) {
  local_collection_table <- "hitt_collection_table.tsv"
}

image_stats_dir <- opt$image_stats_dir
if (is.null(image_stats_dir) || is.na(image_stats_dir)) {
  image_stats_dir <- "."
}

parse_mc_ls_path <- function(line) {
  parsed <- str_match(line, "^\\[.*?\\]\\s+\\S+\\s+(?:STANDARD\\s+)?(.+)$")[, 2]
  ifelse(
    is.na(parsed),
    str_match(line, "^\\S+\\s+(?:STANDARD\\s+)?(.+)$")[, 2],
    parsed
  )
}

source_name_from_s3 <- function(path) {
  path %>%
    str_remove("/$") %>%
    basename()
}

all_datasets <- read_tsv(opt$all_datasets, col_types=cols(.default=col_character())) %>%
  distinct(filename, .keep_all=TRUE)

col_table <-
  read_lines(opt$all_s3) %>%
  as_tibble() %>%
  mutate(
    s3_raw=parse_mc_ls_path(value),
    name=source_name_from_s3(s3_raw),
    uri=file.path("https://s3.embl.de/imatrec/central_data_processing/hitt", str_remove(s3_raw, "/$"), "Z_zset.zarr/"),
    site=str_extract(name, "^[A-Za-z]+"),
    hitt_date=str_extract(name, "20[0-9]{6}"),
    sampling_time=str_extract(name, "_(AM|PM|MID|TARA)_") %>% str_remove_all("_"),
    size_frac=str_extract(name, "\\d+to\\d+"),
    epoch=str_extract(name, "epo_[0-9]+$"),
    grid=site,
    view=site
  ) %>%
  filter(!is.na(s3_raw), s3_raw != "") %>%
  distinct(uri, .keep_all=TRUE) %>%
  select(uri, name, view, grid, site, hitt_date, sampling_time, size_frac, epoch, s3_raw)

if (nrow(col_table) == 0) {
  stop("No HITT OME-Zarr datasets found in S3 listing.")
}

col_table <- col_table %>%
  left_join(
    all_datasets %>%
      select(
        name=filename,
        shortname,
        tmp_copy_path,
        tomo_path,
        omezarr_path,
        everything()
      ),
    by="name"
  )

image_stats_files <- list.files(
  image_stats_dir,
  pattern="_image_stats\\.tsv$",
  full.names=TRUE
)

if (length(image_stats_files) > 0) {
  image_stats <- image_stats_files %>%
    map_dfr(~read_tsv(.x, col_types=cols(.default=col_character()))) %>%
    distinct(name, .keep_all=TRUE)

  col_table <- col_table %>%
    left_join(
      image_stats %>%
        select(name, min_gray, max_gray, contrast_limits),
      by="name"
    )
} else {
  warning("No *_image_stats.tsv files found; collection table was written without contrast limits.")
}

write_tsv(col_table, file=local_collection_table)

if (sheet_mode == "google") {
  library(googlesheets4)
  library(googledrive)
  json_key <- opt$google_key
  if (is.null(json_key) || is.na(json_key)) {
    stop("--google_key is required when --sheet_mode google")
  }
  gs4_auth(path=json_key)
  drive_auth(path=json_key)
  write_sheet(col_table, ss=collection_table_url, sheet=collection_table_sheet)
}

write_tsv(tibble(done="done"), file="done.tsv")
