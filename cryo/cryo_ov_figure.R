

library(tidyverse)
library(ggalluvial)

frido_tab <- "https://docs.google.com/spreadsheets/d/1Ln2YVfxMtQNc-eSh69RA0tpc5UhsMNFXizfCVAR4iZI/edit?gid=0#gid=0"


raw_df <- read_sheet(frido_tab,
                   col_types="c")




df <- raw_df %>%
  filter(is.na(block_name_if_produced))%>%
  mutate(imaged=ifelse(is.na(Imaged), F, Imaged)) %>%
  select(Site, eye_test_freezing_quality, 
         #imaged, 
         amount_of_signal) %>%
  rownames_to_column("id") %>%
  pivot_longer(cols=names(.)[which(names(.)!="id")], names_to = "survey", values_to = "response") 


survey_count <- df %>%
  filter(!is.na(response)) %>%
  group_by(survey) %>%
  tally()

max_in_figure <- max(survey_count$n)

pd <- df %>%
  left_join(survey_count) %>%
  rowwise() %>%
  mutate(
    h=max_in_figure/n
  ) %>%
  filter(!is.na(response)) %>%
  left_join(
    filter(.,survey=="Site") %>%
      select(id, fillcol=response)
  )



library(ggplot2)
library(ggalluvial)

ggplot(
  pd,
  aes(
    x=survey,
    y=h,
    alluvium=id,
    stratum=response
  )
) +
  geom_flow(alpha = 0.7, 
            aes(fill=fillcol)
            ) +
  geom_stratum(width = 0.25, fill = "grey90", color = "grey40") +
  ## text on ribbons
  geom_text(
    stat = "stratum",
    aes(label = after_stat(stratum)),
    size = 3
  ) +
  # total count per ribbon
  geom_text(
    data=survey_count,
    inherit.aes=F,
    aes(x=survey, y=max_in_figure, label=n),
    vjust=0
  )+
  theme_minimal() +
  theme(
    panel.grid.major = element_blank(),
    panel.grid.minor = element_blank(),
    axis.title = element_blank(),
    axis.text.y = element_blank()
  )



  scale_x_discrete(
    limits = c(
      "Site",
      "Freezing quality",
      "Imaged",
      "Amount of signal"
    ),
    expand = c(0.05, 0.05)
  ) +
  labs(
    x = NULL,
    y = "Number of samples",
    fill = "Site"
  ) +
  theme_minimal() +
  theme(
    panel.grid.major.x = element_blank(),
    panel.grid.minor = element_blank()
  )

