


#install.packages("ggalluvial")


library(tidyverse)
library(ggalluvial)
library(googlesheets4)


response_colors = tribble(
  ~response,          ~col,   ~lab,
  
  # Baltic / North Sea — cool
  "Kristineberg",     "#332288", "Kristineberg", # deep indigo   
  "Tallinn",          "#4477AA",  "Tallinn",   # blue
  "Roscoff",          "#66CCEE",   "Roscoff", # cyan
  "Bilbao",           "#228833",  "Bilbao",   # green
  "Porto",            "#AA9933",   "Porto",  # ochre
  "Barcelona",        "#EE7733",   "Barcelona",# orange
  "Naples",           "#CC6677",  "Naples",   # coral / rose
  "Athens",           "#AA3377",   "Athens",    # magenta
  
  # Other categories
 
  "fully covered",    "grey10",   "fully\ncovered",
  "partly covered",   "grey40",  "partly\ncovered",  
  "empty planchette", "grey70", "empty\nplanchette",

  "very high",        "grey10"  ,  "very high",   
  "high",             "grey25",   "high",     
  "medium",           "grey40",   "medium",  
  "low",              "grey55", "low",  
  "very low",         "grey70",  "very low",  

 
)

survey_colors=tibble(
  survey=c("Site", "eye_test_freezing_quality", "amount_of_signal" ),
  lab=c("Site", "Freezing quality", "Signal intensity"),
  top_lab_raw=c("cryo HPF samples", "visually inspected", "imaged")
)


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
  tally() %>%
  left_join(survey_colors) %>%
  mutate(top_lab=paste(n, top_lab_raw, sep="\n"))

max_in_figure <- max(survey_count$n)

response_count <- df %>%
  filter(!is.na(response)) %>%
  group_by(survey, response) %>%
  tally() %>%
  mutate(
    angle=ifelse(survey=="Site", 90, 270),
    hjust=ifelse(survey=="Site", -2, 5),
    response=factor(response, levels=response_colors$response)
  ) %>%
  arrange(response)



pd <- df %>%
  left_join(survey_count %>% select(survey, n)) %>%
  rowwise() %>%
  mutate(
    h=max_in_figure/n
  ) %>%
  filter(!is.na(response)) %>%
  left_join(
    filter(.,survey=="Site") %>%
      select(id, fillcol=response)
  ) %>%
  ## reorder response + survey
  mutate(
    survey=factor(survey, levels = survey_colors$survey),
    response=factor(response, levels=response_colors$response)
  ) 

## left to right 
## add info at top number
## make correct order of barplots

response_labels <- setNames(
  response_colors$lab,
  response_colors$response
)

response_count_labels <- setNames(
  response_count$n,
  response_count$response
)

response_count_angles <- setNames(
  response_count$angle,
  response_count$response
)

response_count_hjust <- setNames(
  response_count$hjust,
  response_count$response
)

p <- ggplot(
  pd,
  aes(
    x=survey,
    y=h,
    alluvium=id,
    stratum=response
  )
) +
  scale_x_discrete(breaks=survey_colors$survey, labels=survey_colors$lab)+
  scale_y_continuous(expand = c(0,0,0.1,0))+
  geom_flow(alpha = 0.7, 
            aes(fill=fillcol)
            ) +
  geom_stratum(
    aes(fill=response, color=response),
    show.legend=F,
    #width = 0.3,
    #fill = "grey90", color = "grey40"
    ) +
  scale_fill_manual(breaks = response_colors$response,
                    values=response_colors$col)+
  scale_color_manual(breaks = response_colors$response,
                    values=response_colors$col)+
  ## text on ribbons
  geom_text(
    stat = "stratum",
    color="white",
    
    #aes(label = after_stat(stratum)),
    aes(label = response_labels[after_stat(stratum)]),
    size = 3
  ) +
  # total count per ribbon
  geom_text(
    data=survey_count,
    inherit.aes=F,
    aes(x=survey, y=max_in_figure+20, label=top_lab),
    vjust=0
  )+
  ## count per tile (on the side)
  geom_text(
    stat = "stratum",
   # data=response_count %>% mutate(h=n, id=n),
    #inherit.aes=F,
   vjust=(-3.5),
    aes(
      label=response_count_labels[after_stat(stratum)],
      angle=response_count_angles[after_stat(stratum)],
      #vjust=response_count_hjust[after_stat(stratum)],
    )
  )+
  theme_minimal() +
  theme(
    panel.grid.major = element_blank(),
    panel.grid.minor = element_blank(),
    axis.title = element_blank(),
    axis.text.y = element_blank(),
    legend.position = "none"
  )

png(
  filename = "my_figure.png",
  width = 2100,
  height = 1400,
  res = 300
)
p
dev.off()

