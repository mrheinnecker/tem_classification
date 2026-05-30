library(tidyverse)
library(getopt)

spec <- matrix(c(
  "input_table", "i", 1, "character",
  "dryrun", "d", 1, "character",
  "dryrun_n", "n", 1, "integer"
), ncol=4, byrow=TRUE)
opt <- getopt(spec)

input_table <- opt$input_table
if (is.null(input_table) || is.na(input_table)) {
  stop("--input_table is required")
}

dryrun <- opt$dryrun
if (is.null(dryrun) || is.na(dryrun)) {
  dryrun <- "FALSE"
}

dryrun_n <- opt$dryrun_n
if (is.null(dryrun_n) || is.na(dryrun_n)) {
  dryrun_n <- 2L
}

sanitize_name <- function(x) {
  x %>%
    basename() %>%
    str_replace_all("[^A-Za-z0-9]+", "_") %>%
    str_replace_all("^_|_$", "")
}

read_input_table <- function(path) {
  if (str_detect(path, "\\.[Cc][Ss][Vv]$")) {
    read_csv(path, col_types=cols(.default=col_character()))
  } else {
    read_tsv(path, col_types=cols(.default=col_character()))
  }
}

images <- read_input_table(input_table) %>%
  mutate(across(everything(), ~na_if(.x, "")))

if (!"tmp_copy_path" %in% names(images)) {
  stop("Input table must contain a tmp_copy_path column")
}

all_images <- images %>%
  filter(!is.na(tmp_copy_path)) %>%
  mutate(
    tmp_copy_path=str_remove(tmp_copy_path, "/$"),
    filename=sanitize_name(tmp_copy_path),
    shortname=filename,
    tomo_path=file.path(tmp_copy_path, "recon_111_1", "tomo"),
    omezarr_path=file.path(tmp_copy_path, "omezarr"),
    req_mem=32
  ) %>%
  distinct(tmp_copy_path, .keep_all=TRUE) %>%
  select(filename, shortname, tmp_copy_path, tomo_path, omezarr_path, req_mem, everything())

to_run <- all_images
if (as.logical(dryrun)) {
  to_run <- head(to_run, dryrun_n)
}

write_csv(to_run, file="images_to_process.csv")
write_tsv(all_images, file="all_datasets.tsv")
