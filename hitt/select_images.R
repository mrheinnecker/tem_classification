library(tidyverse)
library(getopt)

spec <- matrix(c(
  "input_table", "i", 1, "character",
  "sheet_mode", "m", 1, "character",
  "sheet_url", "u", 1, "character",
  "sheet_name", "s", 1, "character",
  "google_key", "k", 1, "character",
  "copy_dest_root", "c", 1, "character",
  "dryrun", "d", 1, "character",
  "dryrun_n", "n", 1, "integer"
), ncol=4, byrow=TRUE)
opt <- getopt(spec)

sheet_mode <- opt$sheet_mode
if (is.null(sheet_mode) || is.na(sheet_mode)) {
  sheet_mode <- "local"
}

sheet_url <- opt$sheet_url
sheet_name <- opt$sheet_name
if (is.null(sheet_name) || is.na(sheet_name)) {
  sheet_name <- ""
}

dryrun <- opt$dryrun
if (is.null(dryrun) || is.na(dryrun)) {
  dryrun <- "FALSE"
}

dryrun_n <- opt$dryrun_n
if (is.null(dryrun_n) || is.na(dryrun_n)) {
  dryrun_n <- 2L
}

copy_dest_root <- opt$copy_dest_root
if (is.null(copy_dest_root) || is.na(copy_dest_root)) {
  copy_dest_root <- "/scratch/rheinnec/tmp_hitt"
}

sanitize_name <- function(x) {
  x %>%
    basename() %>%
    str_replace_all("[^A-Za-z0-9]+", "_") %>%
    str_replace_all("^_|_$", "")
}

dataset_name_from_path <- function(x) {
  path <- x %>%
    str_remove("^[^:]+:") %>%
    str_remove("/+$")

  dataset_root <- str_remove(path, "/recon_111_1/tomo$")
  sanitize_name(dataset_root)
}

remote_tomo_path_from_source <- function(x) {
  path <- str_remove(x, "/+$")
  if_else(
    str_detect(path, "/recon_111_1/tomo$"),
    path,
    file.path(path, "recon_111_1", "tomo")
  )
}

read_local_table <- function(path) {
  if (is.null(path) || is.na(path)) {
    stop("--input_table is required when --sheet_mode local")
  }
  if (str_detect(path, "\\.[Cc][Ss][Vv]$")) {
    read_csv(path, col_types=cols(.default=col_character()))
  } else {
    read_tsv(path, col_types=cols(.default=col_character()))
  }
}

read_google_table <- function(url, sheet) {
  if (is.null(url) || is.na(url)) {
    stop("--sheet_url is required when --sheet_mode google")
  }
  json_key <- opt$google_key
  if (is.null(json_key) || is.na(json_key)) {
    stop("--google_key is required when --sheet_mode google")
  }

  library(googlesheets4)
  gs4_auth(path=json_key)
  if (is.null(sheet) || is.na(sheet) || sheet == "") {
    read_sheet(url, col_types="c")
  } else {
    read_sheet(url, sheet=sheet, col_types="c")
  }
}

images <- if (sheet_mode == "google") {
  read_google_table(sheet_url, sheet_name)
} else {
  read_local_table(opt$input_table)
}

images <- images %>%
  mutate(across(everything(), ~na_if(.x, "")))

path_column <- intersect(c("source_path", "remote_path", "tmp_copy_path"), names(images))
if (length(path_column) == 0) {
  stop("Input table must contain a source_path, remote_path, or tmp_copy_path column")
}
path_column <- path_column[[1]]

all_images <- images %>%
  mutate(source_path=.data[[path_column]]) %>%
  filter(!is.na(source_path)) %>%
  mutate(
    source_path=str_remove(source_path, "/+$"),
    remote_tomo_path=remote_tomo_path_from_source(source_path),
    filename=dataset_name_from_path(remote_tomo_path),
    shortname=filename,
    tmp_copy_path=file.path(copy_dest_root, filename),
    tomo_path=file.path(tmp_copy_path, "recon_111_1", "tomo"),
    omezarr_path=file.path(tmp_copy_path, filename),
    req_mem=32
  ) %>%
  distinct(remote_tomo_path, .keep_all=TRUE) %>%
  select(filename, shortname, source_path, remote_tomo_path, tmp_copy_path, tomo_path, omezarr_path, req_mem, everything())

to_run <- all_images
if (as.logical(dryrun)) {
  to_run <- head(to_run, dryrun_n)
}

write_csv(to_run, file="images_to_process.csv")
write_tsv(all_images, file="all_datasets.tsv")
