

## important: Temporyry for now... until all old annotations are adapted.... be carefull when executing right now


apptainer shell -B /home -B /scratch -B /g /g/schwab/marco/container_legacy/tidyverse_latest.sif

cd /g/schwab/marco/repos/tem_classification




Rscript tem/make_split_collection_tables.R \
  --sheet_mode google \
  --google_key /g/schwab/marco/repos/tem_classification/trec-tem-screen-e98a2e03f58b.json \
  --collection_table_url "https://docs.google.com/spreadsheets/d/1NDyVERdrl7nXJrQRWBbwHjyHCMNEZhj1RQnBKUObwuU/edit?gid=0#gid=0" \
  --annotations_sheet "main" \
  --source_collection_table_url "https://docs.google.com/spreadsheets/d/1NDyVERdrl7nXJrQRWBbwHjyHCMNEZhj1RQnBKUObwuU/edit?gid=0#gid=0" \
  --source_collection_sheet "main" \
  --annotation_log_dir /g/schwab/tem_screen/annotations/log \
  --assignees "marco,chandni,yannick,karel,viktoria" \
  --max_rows_per_person 20

