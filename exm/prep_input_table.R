

library(tidyverse)
library(googlesheets4)


df <- list.files("/g/dey/EmilyWollinger/TREC_2026/ExM_TREC", pattern=".nd2$", recursive=T, full.names=T) %>%
  tibble(
    path=.
  ) %>%
  mutate(
    filename=basename(path),
    shortname=basename(dirname(dirname(dirname(dirname(path))))) %>% paste(basename(path) %>% str_split("_") %>% map_chr(.,1), sep="_")
  ) %>%
  filter(
    !shortname %in% c("KRI_Img0030", "KRI_Img0047", "TAL_Img0000", "TAL_Img0081")
  )


exm_input_table <- "https://docs.google.com/spreadsheets/d/1ePRpa56mmMvCeRTLXmwOywOLy5_I3AFrxJepSUYGR1s/edit?gid=1331814489#gid=1331814489"

write_sheet(df, exm_input_table, sheet="exm_input_table")


## cryo PF + WM:


# run this on the cluster node if new stuff was registered on labID 
#/g/funcgen/bin/labid config refresh

#/g/funcgen/bin/labid export study --study "2f216b3b-db10-4513-8477-ee302f9c7833" --format biatable --odir . --filename /g/schwab/marco/study_table_plastic_20261022.tsv


cryo_labid_input <- "https://docs.google.com/spreadsheets/d/1ePRpa56mmMvCeRTLXmwOywOLy5_I3AFrxJepSUYGR1s/edit?gid=2141148955#gid=2141148955"

images_raw <- read_sheet(cryo_labid_input, sheet="cryo_lm")

cryo_WM_PF_images <- images_raw %>%
  #mutate(across(everything(), ~na_if(.x, ""))) %>%
  filter(str_detect(`File Name`, "_st_3D")) %>%
  filter(str_detect(FilePath, "CryoLM")) %>%
  select(path=FilePath)


## cryo hpf


frido_left_table <- "https://docs.google.com/spreadsheets/d/1Ln2YVfxMtQNc-eSh69RA0tpc5UhsMNFXizfCVAR4iZI/edit?gid=0#gid=0"

full_sheet <- read_sheet(frido_left_table, sheet="hpf")

df_cryo_hpf <- 
  list.files("/g/schwab/IMATREC/cryo_hpf/", pattern="10x", full.names=T, recursive=T) %>%
    .[which(str_detect(., ".czi$"))] %>%
  tibble(path=.) %>%
  mutate(
    name=basename(path) %>% str_split("_10x") %>% map_chr(.,1)
  )
relevant <- 
  full_sheet %>%
  filter(Imaged) %>%
  select(name=`Cryo name (automatically generated FP)`) %>%
    left_join(df_cryo_hpf) %>%
  filter(!is.na(path))

select_one <- relevant %>%
  group_by(name) %>%
  tally() %>%
  arrange(desc(n)) %>%
  filter(n>1)


final_cryo_hpf <- relevant %>%
  filter(name %in% select_one$name) %>%
  mutate(bn=basename(path)) %>%
  filter(
    bn %in% c(
      "TAL_10to40_20230617_AM_HPF_05_116114433_10x-01(3).czi",
      "TAL_10to40_20230617_PM_HPF_01_116114438_10x-01(2).czi",
      "KRI_10to40_20230803_MID_HPF_01_116114715_10x.czi",
      "KRI_10to40_20230804_AM_HPF_01_116114719_10x.czi",
      "ATH_20to200_20240706_MID_HPF_03_112488683_10x-01(1).czi",
      "ATH_20to200_20240706_MID_HPF_03_112488683_10x-02(1).czi"
    )
  ) %>%
  bind_rows(
    relevant %>%
      filter(!name %in% select_one$name)
  ) %>%
  select(path) %>%
  unique()



cryo_input_table <- bind_rows(cryo_WM_PF_images, final_cryo_hpf)

write_sheet(cryo_input_table, "https://docs.google.com/spreadsheets/d/1ePRpa56mmMvCeRTLXmwOywOLy5_I3AFrxJepSUYGR1s/edit?gid=2141148955#gid=2141148955", sheet="cryo_input_table")












