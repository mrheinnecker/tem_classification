

library(tidyverse)

ov_dir <- "C:/projects/tem_classification/ov"

## set TRUE to export the sheets again (needs Google auth), otherwise the exported TSVs are used
refresh_from_sheets <- TRUE

if (refresh_from_sheets) {
  sampling_events <- googlesheets4::read_sheet("https://docs.google.com/spreadsheets/d/1jcpyMkSR4npSxST3D5cFzkAIi9UPmwbPvzAdr2ws55U/edit?gid=193823038#gid=193823038", sheet="Event", col_types = "c", skip=1)

  
  cryo_sheet <- "https://docs.google.com/spreadsheets/d/1Ln2YVfxMtQNc-eSh69RA0tpc5UhsMNFXizfCVAR4iZI/edit?gid=0#gid=0"
  cryo_pf <- googlesheets4::read_sheet(cryo_sheet, sheet="pf", col_types="c")
  cryo_wm <- googlesheets4::read_sheet(cryo_sheet, sheet="wm", col_types="c")
  hpf <- googlesheets4::read_sheet(cryo_sheet, sheet="hpf", col_types="c")
  
  write_tsv(sampling_events, file=file.path(ov_dir, "sampling_events.tsv"))
  write_tsv(hpf, file=file.path(ov_dir, "hpf.tsv"))
  write_tsv(cryo_pf, file=file.path(ov_dir, "cryo_pf.tsv"))
  write_tsv(cryo_wm, file=file.path(ov_dir, "cryo_wm.tsv"))
  
  
 # hpf <- googlesheets4::read_sheet("https://docs.google.com/spreadsheets/d/1jcpyMkSR4npSxST3D5cFzkAIi9UPmwbPvzAdr2ws55U/edit?gid=193823038#gid=193823038", sheet="HPF", col_types = "c")

  write_tsv(sampling_events, file=file.path(ov_dir, "sampling_events.tsv"))
  write_tsv(hpf, file=file.path(ov_dir, "hpf.tsv"))


  ## metabarcoding samples (same sheet as Event / HPF)
  metab <- googlesheets4::read_sheet("https://docs.google.com/spreadsheets/d/1jcpyMkSR4npSxST3D5cFzkAIi9UPmwbPvzAdr2ws55U/edit?gid=804034428#gid=804034428", sheet="MetaB", col_types="c")
  write_tsv(metab, file=file.path(ov_dir, "metab.tsv"))

  ## chemically fixed samples (same sheet as Event / HPF)
  chemfix <- googlesheets4::read_sheet("https://docs.google.com/spreadsheets/d/1jcpyMkSR4npSxST3D5cFzkAIi9UPmwbPvzAdr2ws55U/edit?gid=193823038#gid=193823038", sheet="Chem fixation", col_types="c")
  write_tsv(chemfix, file=file.path(ov_dir, "chemfix.tsv"))
}

sampling_events <- read_tsv(file.path(ov_dir, "sampling_events.tsv"), col_types=cols(.default=col_character()))
hpf <- read_tsv(file.path(ov_dir, "hpf.tsv"), col_types=cols(.default=col_character()))
cryo_pf <- read_tsv(file.path(ov_dir, "cryo_pf.tsv"), col_types=cols(.default=col_character()))
cryo_wm <- read_tsv(file.path(ov_dir, "cryo_wm.tsv"), col_types=cols(.default=col_character()))
metab <- read_tsv(file.path(ov_dir, "metab.tsv"), col_types=cols(.default=col_character()))
chemfix <- read_tsv(file.path(ov_dir, "chemfix.tsv"), col_types=cols(.default=col_character()))


## ---- samples -> sampling events -----------------------------------------------------------------
## no shared ID column: matched by site (sample "Site" = event "Country") and date,
## on days with several events additionally by the sample time of day (AM / MID / PM).
##
## match_quality:
##   date          only one event at the site on that day
##   date_ampm     several events, exactly one in the same half day (MID: 10-14h)
##   untimed_event several events, none in the same half day, exactly one without collection time
##   nearest_time  still ambiguous: the event closest to AM 09:00 / MID 12:00 / PM 15:00 (check these)
##   no_sample_time several events but the sample has no time of day: not assigned, see candidate_events
##   no_event      no event at the site on that day (or no valid date)

events <- sampling_events %>%
  transmute(
    event_id=`Event ID`,
    event_site_id=`Site ID`,
    site=Country,
    date=mdy(`Collection date`),
    event_time=na_if(`Collection time`, "NA"),
    event_hour=as.numeric(str_sub(event_time, 1, 2)) + as.numeric(str_sub(event_time, 4, 5)) / 60,
    latitude=as.numeric(Latitude),
    longitude=as.numeric(Longitude)
  )

target_hour <- c(AM=9, MID=12, PM=15)

in_half_day <- function(hour, time_of_day) {
  case_when(
    is.na(hour) | is.na(time_of_day) ~ NA,
    time_of_day == "AM" ~ hour < 12,
    time_of_day == "PM" ~ hour >= 12,
    time_of_day == "MID" ~ hour >= 10 & hour <= 14,
    TRUE ~ NA
  )
}

## samples: a table with site, date (Date), time_of_day; returns it with the matched event columns
map_to_events <- function(samples, events) {
  ## one row per time slot (site, date, time of day) and candidate event
  slot_event <- samples %>%
    distinct(site, date, time_of_day) %>%
    filter(!is.na(date)) %>%
    inner_join(events, by=c("site", "date"), relationship="many-to-many") %>%
    group_by(site, date, time_of_day) %>%
    mutate(
      n_events=n(),
      same_half=in_half_day(event_hour, time_of_day),
      n_same_half=sum(same_half %in% TRUE),
      n_untimed=sum(is.na(event_hour)),
      time_distance=abs(event_hour - target_hour[time_of_day]),
      candidate_events=paste0(event_site_id, " (", coalesce(str_sub(event_time, 1, 5), "no time"), ")", collapse="; "),
      match_quality=case_when(
        n_events == 1 ~ "date",
        is.na(time_of_day) ~ "no_sample_time",
        n_same_half == 1 ~ "date_ampm",
        n_same_half == 0 & n_untimed == 1 ~ "untimed_event",
        TRUE ~ "nearest_time"
      ),
      keep=case_when(
        match_quality == "date" ~ TRUE,
        match_quality == "date_ampm" ~ same_half %in% TRUE,
        match_quality == "untimed_event" ~ is.na(event_hour),
        match_quality == "no_sample_time" ~ row_number() == 1,
        ## several in the same half day: the closest of those, else the closest overall (untimed last)
        n_same_half > 1 ~ same_half %in% TRUE & time_distance == suppressWarnings(min(time_distance[same_half %in% TRUE])),
        TRUE ~ !is.na(time_distance) & time_distance == suppressWarnings(min(time_distance, na.rm=TRUE))
      )
    ) %>%
    filter(keep) %>%
    slice(1) %>%
    ungroup() %>%
    mutate(across(c(event_id, event_site_id, event_time), ~if_else(match_quality == "no_sample_time", NA, .x))) %>%
    mutate(across(c(latitude, longitude), ~if_else(match_quality == "no_sample_time", NA_real_, .x))) %>%
    select(site, date, time_of_day, event_id, event_site_id, event_time, latitude, longitude, n_events, candidate_events, match_quality)

  samples %>%
    left_join(slot_event, by=c("site", "date", "time_of_day")) %>%
    mutate(match_quality=coalesce(match_quality, "no_event"))
}

## overview of a mapping; the flagged slots should be checked by hand
report_mapping <- function(mapped, label) {
  message("---- ", label)
  print(count(mapped, match_quality))
  mapped %>%
    filter(match_quality %in% c("untimed_event", "nearest_time", "no_sample_time", "no_event")) %>%
    count(site, date_raw, time_of_day, event_time, event_site_id, candidate_events, match_quality) %>%
    print(n=Inf)
  invisible(mapped)
}

sample_base <- function(tab) {
  tab %>%
    mutate(
      barcode=Barcode,
      site=Site,
      date=suppressWarnings(ymd(Date)),
      date_raw=Date,
      time_of_day=na_if(Time, "NA"),
      tara=TARA
    )
}


## ---- HPF ----
hpf_samples <- hpf %>%
  ## the column was renamed in the sheet
  rename(any_of(c(block_name_if_produced="Block name (if produced)"))) %>%
  sample_base() %>%
  transmute(
    barcode, site, date, date_raw, time_of_day, tara,
    parent_barcode=na_if(`Parent HPF barcode (if at all)`, "NA"),
    block_name=na_if(block_name_if_produced, "NA"),
    cryo_name=na_if(`Cryo name (automatically generated FP)`, "NA"),
    used=na_if(Used, "NA"),
    imaged=Imaged,
    post_processed=`Post Processed`,
    freezing_quality=na_if(eye_test_freezing_quality, "NA"),
    amount_of_signal=na_if(amount_of_signal, "NA")
  )

hpf_events <- map_to_events(hpf_samples, events) %>%
  report_mapping("HPF")

write_tsv(hpf_events, file=file.path(ov_dir, "hpf_event_map.tsv"))


## ---- cryo plunge-frozen (pf) and wm ----
cryo_pf_samples <- cryo_pf %>%
  sample_base() %>%
  transmute(
    barcode, site, date, date_raw, time_of_day, tara,
    fraction=Fraction,
    name=`New name`,
    imaged=`Imaged with Linkam Stage`,
    post_processed=`Post Processed`,
    freezing_quality=na_if(Freezing_quality, "NA"),
    sample_quality=na_if(Sample_quality, "NA")
  )

cryo_wm_samples <- cryo_wm %>%
  sample_base() %>%
  transmute(
    barcode, site, date, date_raw, time_of_day, tara,
    fraction=Fraction,
    name=`New name`,
    imaged=`Imaged with Linkam Stage Cryo-WF`,
    comments=na_if(Comments, "NA"),
    post_processed=`Post Processed`,
    freezing_quality=na_if(Freezing_quality, "NA"),
    sample_quality=na_if(Sample_quality, "NA")
  )

cryo_pf_events <- map_to_events(cryo_pf_samples, events) %>%
  report_mapping("cryo PF")
cryo_wm_events <- map_to_events(cryo_wm_samples, events) %>%
  report_mapping("cryo WM")

write_tsv(cryo_pf_events, file=file.path(ov_dir, "cryo_pf_event_map.tsv"))
write_tsv(cryo_wm_events, file=file.path(ov_dir, "cryo_wm_event_map.tsv"))


## ---- metabarcoding ----
metab_samples <- metab %>%
  ## empty rows and note rows at the end of the sheet
  filter(!is.na(Site), Site != "NA") %>%
  rename(Barcode=`Barcode ID`) %>%
  sample_base() %>%
  transmute(
    barcode, site, date, date_raw, time_of_day, tara,
    lab_id=`LabID name`,
    ## "10-40" and "10to40" both occur
    fraction=str_replace(Fraction, "-", "to"),
    replicate=Replicate,
    depth_m=`Depth (m)`,
    sent_to_genoscope=`Sent to Genoscope`,
    notes=na_if(Notes, "NA")
  )

metab_events <- map_to_events(metab_samples, events) %>%
  report_mapping("MetaB")

write_tsv(metab_events, file=file.path(ov_dir, "metab_event_map.tsv"))


## ---- chemical fixation ----
## site as code in this sheet
site_codes <- c(
  ROS="Roscoff", TAL="Tallinn", KRI="Kristineberg", BIL="Bilbao",
  POR="Porto", BAR="Barcelona", NAP="Naples", ATH="Athens"
)

chemfix_samples <- chemfix %>%
  mutate(
    Site=unname(coalesce(site_codes[Site], Site)),
    Barcode=`TREC ID`,
    TARA=TARA_AML
  ) %>%
  sample_base() %>%
  transmute(
    barcode, site, date, date_raw, time_of_day, tara,
    name=`Sample name`,
    ## "20-200" and "20to200" both occur
    fraction=str_replace(`Size fraction`, "-", "to"),
    tube=`Tube number`,
    used=Used
  )

chemfix_events <- map_to_events(chemfix_samples, events) %>%
  report_mapping("Chem fixation")

write_tsv(chemfix_events, file=file.path(ov_dir, "chemfix_event_map.tsv"))


## ---- events without any sample of a layer ----
event_coverage <- events %>%
  select(event_id, site, date, event_time, event_site_id) %>%
  mutate(
    n_hpf=map_int(event_id, ~sum(hpf_events$event_id %in% .x)),
    n_cryo_pf=map_int(event_id, ~sum(cryo_pf_events$event_id %in% .x)),
    n_cryo_wm=map_int(event_id, ~sum(cryo_wm_events$event_id %in% .x)),
    n_metab=map_int(event_id, ~sum(metab_events$event_id %in% .x)),
    n_chemfix=map_int(event_id, ~sum(chemfix_events$event_id %in% .x))
  )
event_coverage %>%
  group_by(site) %>%
  summarise(events=n(), with_hpf=sum(n_hpf > 0), with_cryo_pf=sum(n_cryo_pf > 0), with_cryo_wm=sum(n_cryo_wm > 0), with_metab=sum(n_metab > 0), with_chemfix=sum(n_chemfix > 0))

write_tsv(event_coverage, file=file.path(ov_dir, "event_coverage.tsv"))
