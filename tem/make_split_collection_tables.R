library(tidyverse)
library(getopt)

spec <- matrix(c(
  "processed_dir", "p", 1, "character",
  "collection_table_url", "u", 1, "character",
  "source_collection_table_url", "c", 1, "character",
  "source_collection_sheet", "t", 1, "character",
  "local_source_collection_table", "f", 1, "character",
  "google_key", "k", 1, "character",
  "sheet_mode", "m", 1, "character",
  "local_outdir", "o", 1, "character",
  "annotation_log_dir", "a", 1, "character",
  "annotations_sheet", "n", 1, "character",
  "assignees", "g", 1, "character",
  "s3_base_url", "b", 1, "character",
  "image_stats_dir", "x", 1, "character",
  "local_annotations_log", "l", 1, "character"
), ncol=4, byrow=TRUE)
opt <- getopt(spec)

# Debug helper:
# Uncomment this block when running interactively in R/RStudio and you want to
# bypass command-line parsing. Keep values as character strings to match getopt.
#
# opt <- list(
#   processed_dir = "/g/schwab/tem_screen/processed",
#   collection_table_url = "https://docs.google.com/spreadsheets/d/143uVeeJ72SQE5eK01lzWYCEiT7pJUF3lX7hJl3R9s9I/edit?gid=1426216525#gid=1426216525",
#   source_collection_table_url = "https://docs.google.com/spreadsheets/d/15WNNnse7OvlfiJwFOFYbQA4zIp-5nKc0icRZYfJS--o/edit?gid=1643802951#gid=1643802951",
#   source_collection_sheet = "tem_collection_table",
#   local_source_collection_table = "tem_collection_table.tsv",
#   google_key = "/g/schwab/marco/repos/tem_classification/tem/trec-tem-screen-e98a2e03f58b.json",
#   sheet_mode = "google",
#   local_outdir = "split_collection_tables",
#   annotation_log_dir = "/g/schwab/tem_screen/annotations/log",
#   annotations_sheet = "annotations_log",
#   assignees = "marco,chandni,yannick,karel,viktoria",
#   s3_base_url = "https://s3.embl.de/temscreen",
#   image_stats_dir = "/g/schwab/tem_screen/processed",
#   local_annotations_log = "split_collection_tables/annotations_log.tsv"
# )

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

source_collection_table_url <- opt$source_collection_table_url
if (is.null(source_collection_table_url) || is.na(source_collection_table_url)) {
  source_collection_table_url <- "https://docs.google.com/spreadsheets/d/15WNNnse7OvlfiJwFOFYbQA4zIp-5nKc0icRZYfJS--o/edit?gid=1643802951#gid=1643802951"
}

source_collection_sheet <- opt$source_collection_sheet
if (is.null(source_collection_sheet) || is.na(source_collection_sheet)) {
  source_collection_sheet <- "tem_collection_table"
}

local_source_collection_table <- opt$local_source_collection_table
if (is.null(local_source_collection_table) || is.na(local_source_collection_table)) {
  local_source_collection_table <- "tem_collection_table.tsv"
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

annotation_log_dir <- opt$annotation_log_dir
if (is.null(annotation_log_dir) || is.na(annotation_log_dir)) {
  annotation_log_dir <- "/g/schwab/tem_screen/annotations/log"
}

annotations_sheet <- opt$annotations_sheet
if (is.null(annotations_sheet) || is.na(annotations_sheet)) {
  annotations_sheet <- "annotations_log"
}

assignees <- opt$assignees
if (is.null(assignees) || is.na(assignees)) {
  assignees <- "marco,chandni,yannick,karel,viktoria"
}
people <- str_split(assignees, ",")[[1]] %>%
  str_trim() %>%
  str_to_lower() %>%
  discard(~.x == "")

if (length(people) == 0) {
  stop("--assignees must contain at least one sheet/person name.")
}

s3_base_url <- opt$s3_base_url
if (is.null(s3_base_url) || is.na(s3_base_url)) {
  s3_base_url <- "https://s3.embl.de/temscreen"
}

image_stats_dir <- opt$image_stats_dir
if (is.null(image_stats_dir) || is.na(image_stats_dir)) {
  image_stats_dir <- processed_dir
}

local_annotations_log <- opt$local_annotations_log
if (is.null(local_annotations_log) || is.na(local_annotations_log)) {
  local_annotations_log <- file.path(local_outdir, paste0(annotations_sheet, ".tsv"))
}

is_blank <- function(x) {
  is.na(x) | str_trim(as.character(x)) == ""
}

freeze_first_column <- function(ss, sheet_name) {
  spreadsheet_id <- as.character(googlesheets4::as_sheets_id(ss))
  sheet_id <- googlesheets4::sheet_properties(ss) %>%
    filter(name == sheet_name) %>%
    pull(id)

  if (length(sheet_id) != 1) {
    warning("Could not freeze first column for sheet: ", sheet_name)
    return(invisible(NULL))
  }

  response <- httr::POST(
    url=sprintf(
      "https://sheets.googleapis.com/v4/spreadsheets/%s:batchUpdate",
      spreadsheet_id
    ),
    config=googlesheets4::gs4_token(),
    body=list(
      requests=list(
        list(
          updateSheetProperties=list(
            properties=list(
              sheetId=sheet_id,
              gridProperties=list(frozenColumnCount=1)
            ),
            fields="gridProperties.frozenColumnCount"
          )
        )
      )
    ),
    encode="json"
  )

  httr::stop_for_status(response)
  invisible(NULL)
}

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
    arrange(site, name) %>%
    select(
      name, uri, view, grid,
      site, cell_id, size_frac, sampling_time, source_name, exclusive
    )
}

standardize_collection_table <- function(col_table) {
  if (!"name" %in% names(col_table)) {
    stop("The source collection table needs a name column.")
  }

  if (!"source_name" %in% names(col_table)) {
    if ("uri" %in% names(col_table)) {
      col_table$source_name <- basename(str_remove(as.character(col_table$uri), "/$"))
    } else {
      col_table$source_name <- col_table$name
    }
  }

  if (!"site" %in% names(col_table)) {
    col_table$site <- str_extract(col_table$source_name, "ATH|BAR|KRI|TAL|NAP|BIL|POR")
  }
  if (!"cell_id" %in% names(col_table)) {
    col_table$cell_id <- str_extract(col_table$source_name, "c0\\d+")
  }
  if (!"size_frac" %in% names(col_table)) {
    col_table$size_frac <- str_extract(col_table$source_name, "\\d+to\\d+")
  }
  if (!"sampling_time" %in% names(col_table)) {
    col_table$sampling_time <- str_extract(col_table$source_name, "_(AM|PM|MID|TARA)_") %>%
      str_remove_all("_")
  }
  if (!"exclusive" %in% names(col_table)) {
    col_table$exclusive <- TRUE
  }

  preferred_cols <- c(
    "name", "uri", "view", "grid", "site", "cell_id", "size_frac",
    "sampling_time", "source_name", "exclusive"
  )
  col_table %>%
    distinct(name, .keep_all=TRUE) %>%
    arrange(site, name) %>%
    select(any_of(preferred_cols), everything())
}

read_source_collection_table <- function() {
  if (sheet_mode == "google") {
    library(googlesheets4)
    if (is.null(google_key) || is.na(google_key) || !file.exists(google_key)) {
      stop("--google_key is required and must exist when --sheet_mode google")
    }
    gs4_auth(path=google_key)
    read_sheet(source_collection_table_url, sheet=source_collection_sheet, col_types="c")
  } else if (file.exists(local_source_collection_table)) {
    read_tsv(local_source_collection_table, col_types=cols(.default=col_character()))
  } else {
    stop("Local source collection table does not exist: ", local_source_collection_table)
  }
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

empty_annotations <- function() {
  tibble(name=character(), source_name=character())
}

sheet_exists <- function(ss, sheet_name) {
  googlesheets4::sheet_properties(ss) %>%
    pull(name) %>%
    `%in%`(sheet_name) %>%
    any()
}

read_google_sheet_if_exists <- function(ss, sheet_name) {
  if (!sheet_exists(ss, sheet_name)) {
    warning("Sheet does not exist yet, treating as empty: ", sheet_name)
    return(tibble())
  }
  googlesheets4::read_sheet(ss, sheet=sheet_name, col_types="c")
}

standardize_annotation_table <- function(df) {
  if (nrow(df) == 0 && ncol(df) == 0) {
    return(empty_annotations())
  }
  if (!"name" %in% names(df)) {
    df$name <- df$source_name
  }
  if (!"source_name" %in% names(df)) {
    df$source_name <- df$name
  }
  if (!"annotated_by" %in% names(df)) {
    df$annotated_by <- NA_character_
  }
  if (!"validated_by" %in% names(df)) {
    df$validated_by <- NA_character_
  }
  df
}

last_non_blank <- function(x) {
  x <- as.character(x)
  keep <- !is_blank(x)
  if (any(keep)) {
    tail(x[keep], 1)
  } else {
    NA_character_
  }
}

merge_annotation_rows <- function(df) {
  if (nrow(df) == 0) {
    return(empty_annotations())
  }

  df %>%
    arrange(.priority) %>%
    group_by(name) %>%
    summarise(
      across(
        -any_of(c(".priority", ".assignment_sheet")),
        last_non_blank
      ),
      .groups="drop"
    )
}

read_current_annotations <- function() {
  if (sheet_mode == "google") {
    library(googlesheets4)
    if (is.null(google_key) || is.na(google_key) || !file.exists(google_key)) {
      stop("--google_key is required and must exist when --sheet_mode google")
    }
    gs4_auth(path=google_key)
    existing_log <- read_google_sheet_if_exists(collection_table_url, annotations_sheet)
    split_logs <- map_dfr(people, function(person) {
      read_google_sheet_if_exists(collection_table_url, person) %>%
        mutate(.assignment_sheet=person)
    })
  } else {
    existing_log <- if (file.exists(local_annotations_log)) {
      read_tsv(local_annotations_log, col_types=cols(.default=col_character()))
    } else {
      tibble()
    }
    split_logs <- map_dfr(people, function(person) {
      file <- file.path(local_outdir, paste0(person, ".tsv"))
      if (file.exists(file)) {
        read_tsv(file, col_types=cols(.default=col_character())) %>%
          mutate(.assignment_sheet=person)
      } else {
        tibble()
      }
    })
  }

  bind_rows(
    standardize_annotation_table(existing_log) %>% mutate(.priority=1),
    standardize_annotation_table(split_logs) %>% mutate(.priority=2)
  ) %>%
    merge_annotation_rows()
}

backup_annotations <- function(annotations) {
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  dir.create(annotation_log_dir, recursive=TRUE, showWarnings=FALSE)
  backup_file <- file.path(annotation_log_dir, paste0(annotations_sheet, "_", timestamp, ".tsv"))
  write_tsv(annotations, backup_file)
  message("Backed up annotations to: ", backup_file)
  invisible(backup_file)
}

write_annotations_log <- function(annotations) {
  annotations <- annotations %>% arrange(site, name)
  if (sheet_mode == "google") {
    googlesheets4::write_sheet(annotations, ss=collection_table_url, sheet=annotations_sheet)
  } else {
    dir.create(dirname(local_annotations_log), recursive=TRUE, showWarnings=FALSE)
    write_tsv(annotations, local_annotations_log)
  }
  annotations
}

add_annotations <- function(col_table, annotations) {
  annotations <- standardize_annotation_table(annotations)
  annotation_cols <- setdiff(names(annotations), names(col_table))

  if (length(annotation_cols) == 0) {
    annotation_cols <- character()
  }

  joined <- col_table %>%
    left_join(
      annotations %>% select(name, all_of(annotation_cols)),
      by="name"
    )

  if (!"annotated_by" %in% names(joined)) {
    joined$annotated_by <- NA_character_
  }
  if (!"validated_by" %in% names(joined)) {
    joined$validated_by <- NA_character_
  }

  joined
}

empty_split_tables <- function(template) {
  set_names(
    replicate(length(people), template[0, ], simplify=FALSE),
    people
  )
}

split_contiguous <- function(rows, template) {
  split_tables <- empty_split_tables(template)
  if (nrow(rows) == 0) {
    return(split_tables)
  }

  chunk_size <- ceiling(nrow(rows) / length(people))
  rows <- rows %>%
    arrange(site, name) %>%
    mutate(
      split_index=pmin(ceiling(row_number() / chunk_size), length(people)),
      split_sheet=people[split_index]
    )

  rows %>%
    group_split(split_sheet) %>%
    walk(function(sheet_rows) {
      sheet_name <- unique(sheet_rows$split_sheet)
      split_tables[[sheet_name]] <<- sheet_rows %>%
        select(-split_index, -split_sheet)
    })

  split_tables
}

assign_annotated_elsewhere <- function(rows, split_tables) {
  if (nrow(rows) == 0) {
    return(split_tables)
  }

  rows <- rows %>% arrange(site, name)

  for (i in seq_len(nrow(rows))) {
    row <- rows[i, , drop=FALSE]
    previous_annotator <- str_to_lower(str_trim(as.character(row$annotated_by[[1]])))
    allowed_people <- if (previous_annotator %in% people) {
      setdiff(people, previous_annotator)
    } else {
      people
    }
    if (length(allowed_people) == 0) {
      allowed_people <- people
    }

    current_counts <- map_int(split_tables[allowed_people], nrow)
    target <- allowed_people[which.min(current_counts)]
    split_tables[[target]] <- bind_rows(split_tables[[target]], row)
  }

  split_tables
}

write_split_tables <- function(col_table) {
  col_table <- col_table %>% arrange(site, name)
  template <- col_table

  needs_first_annotation <- col_table %>%
    filter(is_blank(annotated_by) | !(str_to_lower(str_trim(annotated_by)) %in% people))

  needs_second_annotation <- col_table %>%
    filter(!is_blank(annotated_by), str_to_lower(str_trim(annotated_by)) %in% people)

  split_tables <- split_contiguous(needs_first_annotation, template)
  split_tables <- assign_annotated_elsewhere(needs_second_annotation, split_tables)
  split_tables <- imap(split_tables, function(table, sheet_name) {
    table %>%
      mutate(
        view=sheet_name,
        grid=sheet_name
      ) %>%
      arrange(site, name)
  })

  if (sheet_mode == "google") {
    library(googlesheets4)
    library(googledrive)
    gs4_auth(path=google_key)
    drive_auth(path=google_key)
    walk2(split_tables, names(split_tables), function(table, sheet_name) {
      write_sheet(table, ss=collection_table_url, sheet=sheet_name)
      freeze_first_column(collection_table_url, sheet_name)
    })
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

if (sheet_mode == "google") {
  library(googlesheets4)
  library(googledrive)
  gs4_auth(path=google_key)
  drive_auth(path=google_key)
}

current_annotations <- read_current_annotations()
backup_annotations(current_annotations)

source_collection_table <- read_source_collection_table() %>%
  standardize_collection_table()

if (nrow(source_collection_table) == 0) {
  stop("No rows found in source collection table: ", source_collection_sheet)
}

annotated_table <- source_collection_table %>%
  add_annotations(current_annotations) %>%
  arrange(site, name)

annotated_table <- write_annotations_log(annotated_table)

remaining_table <- annotated_table %>%
  filter(is_blank(validated_by))

summary <- write_split_tables(remaining_table)
print(summary)
