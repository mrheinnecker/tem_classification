
library(googlesheets4)
library(googledrive)

google_key <- "/g/schwab/marco/repos/tem_classification/trec-tem-screen-e98a2e03f58b.json"
gs4_auth(path=google_key)
drive_auth(path=google_key)
tem_collection_table_url <- "https://docs.google.com/spreadsheets/d/15WNNnse7OvlfiJwFOFYbQA4zIp-5nKc0icRZYfJS--o/edit?gid=1643802951#gid=1643802951"

## load collection tbale: this one has all datasets that were correctly converted and are sitting on the s3
tem_collection_table <- read_sheet(tem_collection_table_url, sheet="tem_collection_table") %>%
  select(1:13)

## load old annotations from viktoria for now (until final adaptaion is done)
image_log_url <- "https://docs.google.com/spreadsheets/d/143uVeeJ72SQE5eK01lzWYCEiT7pJUF3lX7hJl3R9s9I/edit?gid=2107269356#gid=2107269356"

image_log <- read_sheet(image_log_url, sheet="image_log") 

## filter out some that we need to correct before annotations:
## These are either those that are at the moment done by Viktoria (here we need to adapt them to the final column naming conventions)

annotated_by_viktoria <- image_log %>%
  ## an annoatted column works here
  filter(!is.na(nucleus))

multiple_cells <- image_log %>%
  filter(cell_count>1)

remove_for_now <- c(annotated_by_viktoria$shortname, multiple_cells$shortname) %>% unique()


## now i create a dataframe to stash the removed ones until manula correczion is done

annotation_main <- tem_collection_table %>%
  filter(!name %in% remove_for_now)


annotation_columns <- tribble(
  ~full, ~short,
  "cell_count",  "n_cells",
  "life_status", "life_status",
  "major_group", "maj_group",
  "taxomomic_class", "taxo_class",
  "cell_covering", "cell_cover",
  "nucleus",  "nucleus",
  "nucleolus",  "nucleolus",
  "thrichocysts", "tricho",
  "large_light_core_vesicle", "core_vesic",
  "flagellar_apparatus", "flag_app",
  "symbiosis", "symbiosis",
  "chloroplasts", "chloropl", 
  "plastoglobuli", "plastoglob",
  "pyrenoid", "pyrenoid",
  "pusule", "pusule",
  "reticulated_net", "retic_net",
  "electron_dense_sheets", "electr_sheets",
  "tubular_net", "tubul_net", 
  "food_vacuole", "food_vac", 
  "starch", "starch",
  "crystal_rich_ret_net", "cryst_rich_RN",
  "eyespot", "eyespot",
  "rhabdosome", "rhabdo",
  "er", "er", 
  "mitochondria", "mito",
  "golgi","golgi",
  "lipid_droplets", "lipid_drop", 
  "fibrous_body", "fibr_body",
  "putative_cell_division", "division",
  "silica_deposition_vesicle", "SDV",
  "lysosome", "lysosome",
  "SER_whirls", "SER_whirls",
  "undescribed_organelles", "undescribed",
  "beauty",  "beauty", 
  "annotated_by", "annotated_by",
  "validated_by", "validated_by",
  "comments", "comments"
  
)  


all_cols_df <- tibble(
  !!!setNames(rep(list(NA), nrow(annotation_columns)),
              annotation_columns$short)
)




emtpy_full <- bind_cols(annotation_main, all_cols_df)


main_annotations_url <- "https://docs.google.com/spreadsheets/d/1NDyVERdrl7nXJrQRWBbwHjyHCMNEZhj1RQnBKUObwuU/edit?gid=0#gid=0"

write_sheet(emtpy_full, ss=main_annotations_url, sheet="main")












