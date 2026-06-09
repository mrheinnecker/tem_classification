library(tidyverse)
library(getopt)

spec <- matrix(c(
  "rawdir", "r", 1, "character",
  "outdir", "o", 1, "character",
  "dryrun", "d", 1, "character",
  "sheet_mode", "m", 1, "character",
  "sheet_url", "u", 1, "character",
  "google_key", "k", 1, "character",
  "local_log", "l", 1, "character"
), ncol=4, byrow=TRUE)
opt <- getopt(spec)

raw_dir <- opt$rawdir
if (is.null(raw_dir) || is.na(raw_dir)) {
  raw_dir <- "/g/schwab/Chandni/SEM/IMATREC SEM/"
}

out_dir <- opt$outdir
if (is.null(out_dir) || is.na(out_dir)) {
  out_dir <- getwd()
}

dryrun <- opt$dryrun
if (is.null(dryrun) || is.na(dryrun)) {
  dryrun <- "TRUE"
}

sheet_mode <- opt$sheet_mode
if (is.null(sheet_mode) || is.na(sheet_mode)) {
  sheet_mode <- "local"
}

local_log <- opt$local_log
if (is.null(local_log) || is.na(local_log)) {
  local_log <- file.path(out_dir, "sem_image_log_local.tsv")
}

sanitize_name <- function(x) {
  x %>%
    str_remove("\\.[Tt][Ii][Ff][Ff]?$") %>%
    str_replace_all("[^A-Za-z0-9]+", "_") %>%
    str_replace_all("^_|_$", "")
}

site_from_name <- function(name) {
  case_when(
    str_detect(str_to_lower(basename(name)), "^cellbloom(?:_|$)") ~ "VIG",
    TRUE ~ str_extract(name, "ATH|BAR|KRI|TAL|NAP|BIL|POR|ROS|VIG")
  )
}

all_files_raw <-
  tibble(file=list.files(
    raw_dir,
    pattern="\\.[Tt][Ii][Ff][Ff]?$",
    recursive=TRUE,
    full.names=TRUE
  )) %>%
  mutate(
    filename=sanitize_name(basename(file)),
    shortname=filename,
    site=site_from_name(file),
    sem_date=str_extract(file, "20[0-9]{6}"),
    sampling_time=str_extract(file, "_(AM|PM|MID|TARA)_") %>% str_remove_all("_"),
    size_frac=str_extract(file, "\\d+to\\d+"),
    omezarr_dir=file.path(out_dir, filename, paste0(filename, "_omezarr")),
    filesize=file.info(file)$size,
    req_mem=if_else(
      is.na(filesize),
      8,
      pmin(pmax(8, round(12 * filesize / 10^9)), 64)
    )
  )

all_files <- all_files_raw %>%
  select(
    filename, file, shortname, site, sem_date, sampling_time,
    size_frac, req_mem, filesize, omezarr_dir
  )

if (as.logical(dryrun)) {
  to_run <- head(all_files, 10)
} else {
  to_run <- all_files %>%
    filter(!file.exists(omezarr_dir))
}

read_image_log <- function() {
  if (sheet_mode == "google") {
    library(googlesheets4)
    json_key <- opt$google_key
    if (is.null(json_key) || is.na(json_key)) {
      stop("--google_key is required when --sheet_mode google")
    }
    gs4_auth(path=json_key)
    read_sheet(opt$sheet_url, sheet="sem_image_log", col_types="c")
  } else if (file.exists(local_log)) {
    read_tsv(local_log, col_types=cols(.default=col_character()))
  } else {
    tibble(
      shortname=character(),
      site=character(),
      sem_date=character(),
      sampling_time=character(),
      size_frac=character(),
      tara_overlap_fraction=character(),
      annotation=character()
    )
  }
}

#current_log <- read_image_log()
timestamp <- Sys.time() %>% as.character() %>% str_replace_all(" |:|\\.", "_")
#write_tsv(current_log, file=paste0("manually_filled_log_", timestamp, ".tsv"))

new_log <- all_files %>%
  select(shortname, site, sem_date, sampling_time, size_frac) #%>%
  # left_join(
  #   current_log,
  #   by=c("shortname", "site", "sem_date", "sampling_time", "size_frac")
  # )

# if (sheet_mode == "google") {
#   library(googlesheets4)
#   write_sheet(new_log, ss=opt$sheet_url, sheet="sem_image_log")
# } else {
write_tsv(new_log, file=local_log)
#}

write_csv(to_run, file="images_to_process.csv")
write_tsv(all_files, file="all_datasets.tsv")

