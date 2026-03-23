library(tidyverse)

main_dir <- "/g/schwab/tem_screen/"


tibble(file=list.files(main_dir, pattern="c0\\d+.mrc$", recursive = T) %>%
  .[which(!str_detect(.,"canc_"))]) %>%
  mutate(
    site=str_extract(file, "ATH|BAR|KRI|TAL"),
    cell_id=str_extract(file, "c0\\d+.mrc$") %>% str_remove(".mrc"),
    #grid=
  ) %>%
  select(-file) %>%
  group_by(site) %>%
  tally()



