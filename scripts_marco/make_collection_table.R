library(tidyverse)
library(getopt)
library(googlesheets4)
library(googledrive)
#library(cowplot)
#email = "marco.rheinnecker@embl.de"

json_key <- "/g/schwab/marco/repos/tem_classification/scripts_marco/trec-tem-screen-e98a2e03f58b.json"
gs4_auth(path=json_key)
drive_auth(path = json_key)
#trec_tem_googledoc <- "https://docs.google.com/spreadsheets/d/143uVeeJ72SQE5eK01lzWYCEiT7pJUF3lX7hJl3R9s9I/edit?gid=258669282#gid=258669282"
collection_table="https://docs.google.com/spreadsheets/d/15WNNnse7OvlfiJwFOFYbQA4zIp-5nKc0icRZYfJS--o/edit?gid=1643802951#gid=1643802951"


spec <- matrix(c(
  # long option                  short  arg  type
  "all_s3", "d",   1,   "character"
),
ncol = 4,
byrow = TRUE)
opt <- getopt(spec)



opt <- tibble(
  # rawdir="/g/schwab/tem_screen/raw",
  # pngdir="/g/schwab/tem_screen/pngs",
  all_s3="/scratch/rheinnec/tem_screen/work/a4/39875e44d4c1c4603c6380a3aca160/all_s3_entries.txt" 
)

col_table <- read_lines(opt$all_s3) %>%
  as_tibble() %>%
  mutate(
    s3_raw=str_split(value, "0B ") %>% map_chr(.,2),
    uri=file.path("https://s3.embl.de/temscreen", s3_raw),
    name=sub("^(.*?_c[0-9]{3}).*$", "\\1", s3_raw)
  ) %>%
  select(uri, name)



write_sheet(col_table, ss = collection_table, sheet="collection_table")

write_tsv(tibble(done="done jonge"), file="done.tsv")


