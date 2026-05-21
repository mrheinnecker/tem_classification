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
    uri=file.path("https://s3.embl.de/temscreen", s3_raw),
    name=sub("^(.*?_c[0-9]{3}).*$", "\\1", s3_raw)
  ) %>%
  select(uri, name)


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


