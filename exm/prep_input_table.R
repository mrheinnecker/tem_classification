

library(tidyverse)



df <- list.files("/g/dey/EmilyWollinger/TREC_2026/ExM_TREC", pattern=".nd2$", recursive=T, full.names=T) %>%
  tibble(
    path=.
  ) %>%
  mutate(
    filename=basename(path),
    shortname=basename(dirname(dirname(dirname(dirname(path))))) %>% paste(basename(path) %>% str_split("_") %>% map_chr(.,1), sep="_")
  ) %>%
  filter(
    shortname %in% c("KRI_Img0030", "KRI_Img0047", "TAL_Img0000")
  )


exm_input_table <- "https://docs.google.com/spreadsheets/d/1ePRpa56mmMvCeRTLXmwOywOLy5_I3AFrxJepSUYGR1s/edit?gid=1331814489#gid=1331814489"

write_sheet(df, exm_input_table, sheet="exm_input_table")











