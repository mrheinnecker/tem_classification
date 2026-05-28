library(tidyverse)
library(getopt)
library(jsonlite)

spec <- matrix(c(
  "all_s3", "d", 1, "character",
  "metadata_dir", "x", 1, "character",
  "sheet_mode", "m", 1, "character",
  "google_key", "k", 1, "character",
  "collection_table_url", "u", 1, "character",
  "local_collection_table", "l", 1, "character",
  "image_log_url", "i", 1, "character",
  "local_image_log", "a", 1, "character"
), ncol=4, byrow=TRUE)
opt <- getopt(spec)

sheet_mode <- opt$sheet_mode
if (is.null(sheet_mode) || is.na(sheet_mode)) {
  sheet_mode <- "local"
}

local_collection_table <- opt$local_collection_table
if (is.null(local_collection_table) || is.na(local_collection_table)) {
  local_collection_table <- "sem_collection_table.tsv"
}

metadata_dir <- opt$metadata_dir
if (is.null(metadata_dir) || is.na(metadata_dir)) {
  metadata_dir <- "."
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
    basename() %>%
    str_remove("_omezarr$")
}

read_metadata_table <- function() {
  metadata_files <- list.files(
    metadata_dir,
    pattern="_metadata\\.json$",
    recursive=TRUE,
    full.names=TRUE
  )

  if (length(metadata_files) == 0) {
    return(tibble(name=character()))
  }

  map_dfr(metadata_files, function(file) {
    metadata <- read_json(file, simplifyVector=TRUE)
    scalar <- function(x) {
      if (is.null(x) || length(x) == 0) {
        NA_character_
      } else {
        as.character(x[[1]])
      }
    }

    tibble(
      name=basename(file) %>% str_remove("_metadata\\.json$"),
      pixel_size_x_nm=scalar(metadata$pixel_size$x_nm),
      pixel_size_y_nm=scalar(metadata$pixel_size$y_nm),
      pixel_size_source=scalar(metadata$pixel_size$source),
      width_px=scalar(metadata$image$width_px),
      height_px=scalar(metadata$image$height_px),
      instrument=scalar(metadata$sem$instrument$value),
      detector=scalar(metadata$sem$detector$value),
      magnification=scalar(metadata$sem$magnification$value)
    )
  })
}

read_image_log <- function() {
  local_image_log <- opt$local_image_log
  if (is.null(local_image_log) || is.na(local_image_log)) {
    local_image_log <- "sem_image_log_local.tsv"
  }

  if (sheet_mode == "google") {
    library(googlesheets4)
    json_key <- opt$google_key
    if (is.null(json_key) || is.na(json_key)) {
      stop("--google_key is required when --sheet_mode google")
    }
    gs4_auth(path=json_key)
    read_sheet(opt$image_log_url, sheet="sem_image_log", col_types="c")
  } else if (file.exists(local_image_log)) {
    read_tsv(local_image_log, col_types=cols(.default=col_character()))
  } else {
    tibble(shortname=character())
  }
}

col_table <-
  read_lines(opt$all_s3) %>%
  as_tibble() %>%
  mutate(
    s3_raw=parse_mc_ls_path(value),
    name=source_name_from_s3(s3_raw),
    uri=file.path("https://s3.embl.de/semscreen", s3_raw),
    view=name,
    grid="SEM",
    site=str_extract(name, "ATH|BAR|KRI|TAL|NAP|BIL|POR"),
    sem_date=str_extract(name, "20[0-9]{6}"),
    sampling_time=str_extract(name, "_(AM|PM|MID|TARA)_") %>% str_remove_all("_"),
    size_frac=str_extract(name, "\\d+to\\d+")
  ) %>%
  filter(!is.na(s3_raw), str_detect(s3_raw, "_omezarr/?$")) %>%
  distinct(uri, .keep_all=TRUE) %>%
  select(uri, name, view, grid, site, sem_date, sampling_time, size_frac, s3_raw)

if (nrow(col_table) == 0) {
  stop("No SEM OME-Zarr datasets found in S3 listing.")
}

metadata_table <- read_metadata_table()
if (nrow(metadata_table) > 0) {
  col_table <- col_table %>%
    left_join(metadata_table, by="name")
}

image_log <- read_image_log()
if (nrow(image_log) > 0 && "shortname" %in% names(image_log)) {
  col_table <- col_table %>%
    left_join(
      image_log %>% distinct(shortname, .keep_all=TRUE),
      by=c("name"="shortname")
    )
}

if (sheet_mode == "google") {
  library(googlesheets4)
  library(googledrive)
  json_key <- opt$google_key
  if (is.null(json_key) || is.na(json_key)) {
    stop("--google_key is required when --sheet_mode google")
  }
  gs4_auth(path=json_key)
  drive_auth(path=json_key)
  write_sheet(col_table, ss=opt$collection_table_url, sheet="sem_collection_table")
} else {
  write_tsv(col_table, file=local_collection_table)
}

write_tsv(tibble(done="done"), file="done.tsv")
