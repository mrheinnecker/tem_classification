library(tidyverse)
library(getopt)
library(googlesheets4)
library(googledrive)
library(cowplot)
#email = "marco.rheinnecker@embl.de"

json_key <- "/g/schwab/marco/repos/tem_classification/scripts_marco/trec-tem-screen-e98a2e03f58b.json"
gs4_auth(path=json_key)
drive_auth(path = json_key)
trec_tem_googledoc <- "https://docs.google.com/spreadsheets/d/143uVeeJ72SQE5eK01lzWYCEiT7pJUF3lX7hJl3R9s9I/edit?gid=258669282#gid=258669282"



spec <- matrix(c(
  # long option                  short  arg  type
  "rawdir",                   "r",   1,   "character",
  "pngdir",        "p",   1,   "character",
  "dryrun", "d",   1,   "character"
),
ncol = 4,
byrow = TRUE)
opt <- getopt(spec)


# opt <- tibble(
#   rawdir="/g/schwab/tem_screen/raw",
#   pngdir="/g/schwab/tem_screen/pngs"
# )

#print(opt$dryrun)

raw_dir <- opt$rawdir
png_dir <- opt$pngdir

all_files_raw <- 
  tibble(file=list.files(raw_dir, pattern="c\\d+.mrc$", recursive = T, full.names=T) %>%
  .[which(!str_detect(.,"canc_"))]) %>%
 # .[63,] %>%
  # filter(
  #   ## duplicated with id c015 from same block
  #   !2474646_76273
  # ) %>%
  #rowwise() %>%
  mutate(
    mdoc_file=str_replace(file, ".mrc$", ".mrc.mdoc"),
    site=str_extract(file, "ATH|BAR|KRI|TAL|NAP|BIL|POR"),
    cell_id=str_extract(file, "c0\\d+.mrc$") %>% str_remove(".mrc"),
    
    shortname=str_extract(basename(dirname(file)), "^.*Cut\\d+") %>% paste(cell_id, sep="_"),
    
    filename=str_split(basename(dirname(file)), "Cut\\d*_") %>% map_chr(.,2) %>% paste(shortname,., sep="_"),
    justblend_file=file.path(png_dir, site, paste0(filename, "_blend.png")),
    correctionblend_file=file.path(png_dir, site, paste0(filename, "_correctionblend.png")),
    
    #grid=
  ) %>%
  rowwise() %>%
  mutate(
    filesize=file.info(file)$size,
    req_mem=min(max(16, round(20*filesize/10^9)), 128)
  ) 

all_files <- all_files_raw %>%
  select(filename, file, mdoc_file, shortname, req_mem, justblend_file, correctionblend_file, filesize) #%>%

if(as.logical(opt$dryrun)){
  to_run <- all_files[1:5,]
} else {
  to_run <- all_files %>%
    filter(!(file.exists(correctionblend_file)))  
}


## make statistics figure

source("/g/schwab/marco/repos/tem_classification/scripts_marco/count_stats.R")

comb_plot <- make_main_statistic_of_sample_number(raw_dir)

plot_name <- "TEM_screen_image_count.pdf"

pdf(file=plot_name, width=4.5, height=4.5)
comb_plot
dev.off()


# 
# 
# cache_dir <- "/g/schwab/marco/repos/tem_classification/scripts_marco/gargle_cache"
# 
# 
# 
# options(gargle_oauth_cache = cache_dir,
#         gargle_oauth_email = "marco.rheinnecker@embl.de")
# 
# print(gargle::gargle_oauth_cache())
# print(list.files(cache_dir, recursive = TRUE))
# 
# 
# 
# googledrive::drive_auth(
#   email = "marco.rheinnecker@embl.de",
#   cache = cache_dir,
#   scopes = "https://www.googleapis.com/auth/drive"
# )
# 
# folder <- drive_get(as_id("https://drive.google.com/drive/folders/11T1ozEQ66wFDgfWjJnCW3jpfHTHwpJsW"))
# 
# 
# 
# drive_upload(
#   media = plot_name,
#   path  = folder,
#   name  = plot_name,
#   overwrite=TRUE
# )
# 



df_trec_tem_current_state <- read_sheet(trec_tem_googledoc, sheet="image_log", col_types="c") 
write_tsv(df_trec_tem_current_state, file="manually_filled_log.tsv")


new <- all_files_raw %>%
  select(shortname, site) %>%
  left_join(df_trec_tem_current_state, by=c("shortname", "site"))

#, "site"

write_sheet(new, ss = trec_tem_googledoc, sheet="image_log")

write_csv(to_run, file="images_to_process.csv")

write_tsv(all_files, file="all_datasets.tsv")






