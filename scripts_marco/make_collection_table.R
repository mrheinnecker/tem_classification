library(tidyverse)
library(getopt)

spec <- matrix(c(
  # long option                  short  arg  type
  "all_s3", "d",   1,   "character",
  "sheet_mode", "m", 1, "character",
  "google_key", "k", 1, "character",
  "collection_table_url", "u", 1, "character",
  "local_collection_table", "l", 1, "character"
),
ncol = 4,
byrow = TRUE)
opt <- getopt(spec)

sheet_mode <- opt$sheet_mode
if (is.null(sheet_mode) || is.na(sheet_mode)) {
  sheet_mode <- "local"
}

collection_table <- opt$collection_table_url
if (is.null(collection_table) || is.na(collection_table)) {
  collection_table <- "https://docs.google.com/spreadsheets/d/15WNNnse7OvlfiJwFOFYbQA4zIp-5nKc0icRZYfJS--o/edit?gid=1643802951#gid=1643802951"
}

local_collection_table <- opt$local_collection_table
if (is.null(local_collection_table) || is.na(local_collection_table)) {
  local_collection_table <- "collection_table.tsv"
}

col_table <- read_lines(opt$all_s3) %>%
  as_tibble() %>%
  mutate(
    s3_raw=str_split(value, "0B ") %>% map_chr(.,2),
    s3_raw=str_remove(s3_raw, "/$"),
    object_name=basename(s3_raw),
    source_name=case_when(
      str_detect(object_name, "_coarse_mask\\.ome\\.zarr$") ~ str_remove(object_name, "_coarse_mask\\.ome\\.zarr$"),
      str_detect(object_name, "_omezarr$") ~ str_remove(object_name, "_omezarr$"),
      TRUE ~ object_name
    ),
    is_mask=str_detect(object_name, "_coarse_mask\\.ome\\.zarr$"),
    uri=file.path("https://s3.embl.de/temscreen", s3_raw),
    name=if_else(is_mask, paste0(source_name, " coarse mask"), source_name),
    type=if_else(is_mask, "labels", "intensities"),
    view=source_name,
    display=if_else(is_mask, "coarse cell mask", "TEM image"),
    blend=if_else(is_mask, "alpha", "sum"),
    color=if_else(is_mask, "magenta", "white"),
    format="OmeZarr",
    site=str_extract(source_name, "ATH|BAR|KRI|TAL|NAP|BIL|POR"),
    cell_id=str_extract(source_name, "c0\\d+"),
    size_frac=str_extract(source_name, "\\d+to\\d+"),
    sampling_time=str_extract(source_name, "_(AM|PM|MID|TARA)_") %>% str_remove_all("_"),
    group=site
  ) %>%
  arrange(source_name, is_mask) %>%
  select(
    uri, name, type, view, display, blend, color, format, group,
    site, cell_id, size_frac, sampling_time, source_name
  )


if (sheet_mode == "google") {
  library(googlesheets4)
  library(googledrive)

  json_key <- opt$google_key
  if (is.null(json_key) || is.na(json_key)) {
    stop("--google_key is required when --sheet_mode google")
  }

  gs4_auth(path=json_key)
  drive_auth(path = json_key)
  write_sheet(col_table, ss = collection_table, sheet="collection_table")
} else {
  write_tsv(col_table, file=local_collection_table)
}

write_tsv(tibble(done="done"), file="done.tsv")


