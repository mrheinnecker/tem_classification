library(tidyverse)
library(getopt)


spec <- matrix(c(
  # long option                  short  arg  type
  "rawdir",                   "r",   1,   "character",
  "pngdir",        "p",   1,   "character"
),
ncol = 4,
byrow = TRUE)
opt <- getopt(spec)


# opt <- tibble(
#   rawdir="/g/schwab/tem_screen/",
#   pngdir="/g/schwab/marco/wfTEM_pngs/"
# )

raw_dir <- opt$rawdir
png_dir <- opt$pngdir

all_files <- 
  tibble(file=list.files(raw_dir, pattern="c0\\d+.mrc$", recursive = T, full.names=T) %>%
  .[which(!str_detect(.,"canc_"))]) %>%
 # .[63,] %>%
  #rowwise() %>%
  mutate(
    site=str_extract(file, "ATH|BAR|KRI|TAL"),
    cell_id=str_extract(file, "c0\\d+.mrc$") %>% str_remove(".mrc"),
    
    shortname=str_extract(basename(dirname(file)), "^.*Cut\\d+") %>% paste(cell_id, sep="_"),
    
    filename=str_split(basename(dirname(file)), "Cut\\d*_") %>% map_chr(.,2) %>% paste(shortname,., sep="_"),
    justblend_file=file.path(png_dir, paste0(filename, "_blend.png")),
    correctionblend_file=file.path(png_dir, paste0(filename, "_correctionblend.png")),
    
    #grid=
  ) %>%
  rowwise() %>%
  mutate(
    filesize=file.info(file)$size,
    req_mem=min(max(16, round(20*filesize/10^9)), 128)
  ) %>%
  select(filename, file, shortname, req_mem, justblend_file, correctionblend_file, filesize) #%>%

to_run <- all_files %>%
  filter(!(file.exists(correctionblend_file)&file.exists(justblend_file)))


write_csv(to_run, file="images_to_process.csv")

write_tsv(all_files, file="all_datasets.tsv")

