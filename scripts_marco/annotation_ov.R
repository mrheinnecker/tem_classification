


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





df_trec_tem_current_state <- read_sheet(trec_tem_googledoc, sheet="image_log", col_types="c") 


annotated <- df_trec_tem_current_state %>%
  filter(!is.na(user), dinoflagellate==0) 

all_sites <- c("TAL","KRI","BIL","POR","BAR","NAP","ATH") #%>% c(., "VIG")

df <- annotated %>%
  select(1:12) %>%
  select(-cell_count, -life_status) %>%
  pivot_longer(cols=names(.) %>% .[which(!. %in% c("shortname", "site"))]) %>%
  mutate(
    val_tf=ifelse(value==0|is.na(value), 0, 1),
    site=factor(site, levels = all_sites),
    name=factor(name)
  )

cell_count <- annotated %>% mutate(site=factor(site, levels = all_sites)) %>% group_by(site, .drop=F) %>% tally() %>% select(site, total_cells=n)

plot_data <- 
  df %>%
  filter(val_tf!=0) %>% 
  group_by(site, name, .drop=F) %>%
  tally() %>%
  left_join(
    cell_count
  ) %>%
  mutate(
    frac=n/total_cells
  )
  
  
  

hm <- ggplot(plot_data, aes(x=site, fill=frac, y=name))+
  geom_tile()+
  geom_text(aes(label=n), color="white")+
  scale_fill_gradientn(colors=c("#FFC20A","#0C7BDC"), name="fraction")+
  theme_bw()



bp <- ggplot(cell_count, aes(x=site, y=total_cells))+
  geom_col()+
  geom_text(aes(label=total_cells, y=total_cells-1), color="white", vjust=1)+
  theme_bw()


comb_plot <- cowplot::plot_grid(
  bp+theme(axis.title.x = element_blank(), axis.ticks.x = element_blank(), axis.text.x = element_blank()), 
  hm,
  align="v",
  rel_heights=c(1,3),
  nrow=2
)


plot_name <- "TEM_screen_artifact_count.pdf"

pdf(file=plot_name, width=5.5, height=4.5)
comb_plot
dev.off()













