library(tidyverse)
library(getopt)

spec <- matrix(c(
  "processed_dir", "p", 1, "character",
  "collection_table_url", "u", 1, "character",
  "google_key", "k", 1, "character",
  "sheet_mode", "m", 1, "character",
  "local_outdir", "o", 1, "character",
  "s3_base_url", "b", 1, "character",
  "image_stats_dir", "x", 1, "character",
  "image_log_url", "i", 1, "character",
  "image_log_sheet", "s", 1, "character",
  "local_image_log", "l", 1, "character"
), ncol=4, byrow=TRUE)
opt <- getopt(spec)

arg_file <- commandArgs(FALSE) %>%
  .[str_detect(., "^--file=")] %>%
  str_remove("^--file=") %>%
  .[1]

script_dir <- if (!is.na(arg_file)) {
  dirname(normalizePath(arg_file))
} else {
  getwd()
}

processed_dir <- opt$processed_dir
if (is.null(processed_dir) || is.na(processed_dir)) {
  processed_dir <- "/g/schwab/tem_screen/processed"
}

collection_table_url <- opt$collection_table_url
if (is.null(collection_table_url) || is.na(collection_table_url)) {
  collection_table_url <- "https://docs.google.com/spreadsheets/d/143uVeeJ72SQE5eK01lzWYCEiT7pJUF3lX7hJl3R9s9I/edit?gid=1426216525#gid=1426216525"
}

google_key <- opt$google_key
if (is.null(google_key) || is.na(google_key)) {
  google_key <- file.path(script_dir, "trec-tem-screen-e98a2e03f58b.json")
}

sheet_mode <- opt$sheet_mode
if (is.null(sheet_mode) || is.na(sheet_mode)) {
  sheet_mode <- "google"
}

local_outdir <- opt$local_outdir
if (is.null(local_outdir) || is.na(local_outdir)) {
  local_outdir <- "split_collection_tables"
}

s3_base_url <- opt$s3_base_url
if (is.null(s3_base_url) || is.na(s3_base_url)) {
  s3_base_url <- "https://s3.embl.de/temscreen"
}

image_stats_dir <- opt$image_stats_dir
if (is.null(image_stats_dir) || is.na(image_stats_dir)) {
  image_stats_dir <- processed_dir
}

image_log_url <- opt$image_log_url
if (is.null(image_log_url) || is.na(image_log_url)) {
  image_log_url <- "https://docs.google.com/spreadsheets/d/143uVeeJ72SQE5eK01lzWYCEiT7pJUF3lX7hJl3R9s9I/edit?gid=258669282#gid=258669282"
}

image_log_sheet <- opt$image_log_sheet
if (is.null(image_log_sheet) || is.na(image_log_sheet)) {
  image_log_sheet <- "image_log"
}

local_image_log <- opt$local_image_log
if (is.null(local_image_log) || is.na(local_image_log)) {
  local_image_log <- file.path(dirname(processed_dir), "image_log_local.tsv")
}

people <- c("marco", "chandni", "karel", "yannick")

find_omezarrs <- function(path) {
  if (!dir.exists(path)) {
    stop("Processed directory does not exist: ", path)
  }

  list.dirs(path, recursive=FALSE, full.names=TRUE) %>%
    #keep(~str_detect(basename(.x), "")) %>%
    tibble(local_path=.) %>%
    mutate(source_name=basename(local_path)) %>%
    distinct(source_name, .keep_all=TRUE)
}

make_collection_rows <- function(omezarrs) {
  omezarrs %>%
    mutate(
      site=str_extract(source_name, "ATH|BAR|KRI|TAL|NAP|BIL|POR"),
      cell_id=str_extract(source_name, "c0\\d+"),
      size_frac=str_extract(source_name, "\\d+to\\d+"),
      sampling_time=str_extract(source_name, "_(AM|PM|MID|TARA)_") %>%
        str_remove_all("_"),
      uri=file.path(s3_base_url, source_name),
      name=if_else(
        !is.na(cell_id),
        paste0(str_split(source_name, cell_id) %>% map_chr(1), cell_id),
        str_remove(source_name, "_omezarr$")
      ),
      view=site,
      grid=site,
      exclusive=TRUE
    ) %>%
    arrange(site, source_name) %>%
    select(
      uri, name, view, grid,
      site, cell_id, size_frac, sampling_time, source_name, exclusive
    )
}

add_image_stats <- function(col_table) {
  image_stats_files <- list.files(
    image_stats_dir,
    pattern="_image_stats\\.tsv$",
    recursive=FALSE,
    full.names=TRUE
  )

  if (length(image_stats_files) == 0) {
    warning("No *_image_stats.tsv files found; tables will not include contrast limits.")
    return(col_table)
  }

  image_stats <- image_stats_files %>%
    map_dfr(~read_tsv(.x, col_types=cols(.default=col_character()))) %>%
    distinct(name, .keep_all=TRUE)

  col_table %>%
    left_join(
      image_stats %>% select(name, min_gray, max_gray, contrast_limits),
      by="name"
    )
}

read_image_log <- function() {
  if (sheet_mode == "google") {
    library(googlesheets4)
    if (is.null(google_key) || is.na(google_key) || !file.exists(google_key)) {
      stop("--google_key is required and must exist when --sheet_mode google")
    }
    gs4_auth(path=google_key)
    read_sheet(image_log_url, sheet=image_log_sheet, col_types="c")
  } else if (file.exists(local_image_log)) {
    read_tsv(local_image_log, col_types=cols(.default=col_character()))
  } else {
    tibble(shortname=character(), site=character())
  }
}

add_image_log <- function(col_table) {
  image_log <- read_image_log()

  if (nrow(image_log) == 0 || !all(c("shortname", "site") %in% names(image_log))) {
    warning("Image log has no rows or is missing shortname/site columns; tables will not include annotations.")
    return(col_table)
  }

  col_table %>%
    left_join(
      image_log %>% distinct(shortname, site, .keep_all=TRUE),
      by=c("name"="shortname", "site"="site")
    )
}

write_split_tables <- function(col_table) {
  split_tables <- col_table %>%
    mutate(split_sheet=people[((row_number() - 1) %% length(people)) + 1]) %>%
    group_split(split_sheet)

  names(split_tables) <- map_chr(split_tables, ~unique(.x$split_sheet))
  split_tables <- map(split_tables, ~select(.x, -split_sheet))

  if (sheet_mode == "google") {
    library(googlesheets4)
    library(googledrive)
    gs4_auth(path=google_key)
    drive_auth(path=google_key)
    walk2(split_tables, names(split_tables), ~write_sheet(.x, ss=collection_table_url, sheet=.y))
  } else {
    dir.create(local_outdir, recursive=TRUE, showWarnings=FALSE)
    walk2(
      split_tables,
      names(split_tables),
      ~write_tsv(.x, file.path(local_outdir, paste0(.y, ".tsv")))
    )
  }

  tibble(sheet=names(split_tables), n_images=map_int(split_tables, nrow))
}

omezarrs <- find_omezarrs(processed_dir)
if (nrow(omezarrs) == 0) {
  stop("No *_omezarr directories found under: ", processed_dir)
}

col_table <- omezarrs %>%
  make_collection_rows() %>%
  add_image_stats() %>%
  add_image_log()

summary <- write_split_tables(col_table)
print(summary)
