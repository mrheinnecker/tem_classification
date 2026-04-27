# library(tidyverse)
# 
# opt <- tibble(
#   rawdir="/g/schwab/tem_screen/raw",
#   pngdir="/g/schwab/tem_screen/pngs"
# )
# 
# #print(opt$dryrun)
# 
# raw_dir <- opt$rawdir
#png_dir <- opt$pngdir

make_main_statistic_of_sample_number <- function(raw_dir){
  
  all_sites <- c("TAL","KRI","BIL","POR","BAR","NAP","ATH") #%>% c(., "VIG")
  all_files_raw <- 
    tibble(file=list.files(raw_dir, pattern="c\\d+.mrc$", recursive = T, full.names=T) %>%
             .[which(!str_detect(.,"canc_"))]) %>%
    
    mutate(
      site=str_extract(file, "ATH|BAR|KRI|TAL|NAP|BIL|POR"),
      cell_id=str_extract(file, "c0\\d+.mrc$") %>% str_remove(".mrc"),
      sampling_time=str_extract(file, "_AM_|_PM_|_MID_|_TARA_") %>% str_remove_all("_"),
      size_frac=str_extract(file, "_\\d+to\\d+_") %>% str_remove_all("_"),
      shortname=str_extract(basename(dirname(file)), "^.*Cut\\d+") %>% paste(cell_id, sep="_")
    )%>%
    mutate(site=factor(site, levels=all_sites),
           size_frac=factor(size_frac),
           sampling_time=factor(sampling_time))
  
  
  cnts <- all_files_raw  %>%
    group_by(site, .drop=F)  %>%
    tally() %>%
    mutate(frac=n/200,
           fac="left") 
  
  
  
  block_counts <- all_files_raw %>%
    rowwise() %>%
    mutate(
      to_rem=str_remove(shortname, "_c\\d+$"),
      cut_event=str_extract(shortname, "Cut\\d"),
      block=basename(dirname(file)) %>% str_remove(., to_rem)
    )
  
  cut_events <- 
    block_counts %>%
    group_by(site, block, cut_event) %>%
    tally()
  
  per_block <- 
    block_counts %>%
    group_by(site, block) %>%
    tally()
  
  
  
  col_high <- "#0C7BDC"
  col_low <- "#FFC20A"
  
  
  barplot <- 
    ggplot(cnts,
                    aes(x=site, y=n))+
    geom_col(
      aes(fill=frac)
             )+
      
    geom_col(data=per_block, aes(color=block), color="white", position="stack", alpha=0)+ 
      
    #facet_grid("1"~fac, scales="free", space="free")+
    geom_text(aes(label=n, y=n), vjust=0, color="black")+
    
    scale_fill_gradientn(
      colors = c("grey", col_low, col_high),
      values = scales::rescale(c(0, 0.01, 1)),
      limits = c(0, 1),
      breaks = seq(0, 1, 0.25),
      labels = 200 * seq(0, 1, 0.25),
      name = "progress"
    )+
    
    # scale_fill_gradientn(colors=c("grey",col_low,col_low,  col_high,col_high), limits=c(0,1), 
    #                      breaks=seq(0,1,0.25), labels=200*seq(0,1,0.25),
    #                      name="progress")+
    
    
    geom_label(data=tibble(x=ifelse("VIG" %in% all_sites, "ATH", "NAP"), y=150, label=paste0("total: ", as.character(sum(cnts$n)))),
              aes(x=x, y=y, label=label), inherit.aes=F)+
    scale_y_continuous(expand = c(0.01, 0.5, 0.1, 0.1))+
    theme_bw()+
    ylab("cells imaged")
  
  
  sizefrac_plot <-all_files_raw %>%
    group_by(site, size_frac, .drop=F) %>%
    tally() %>%
    ggplot(data=., aes(x=site, y=size_frac, fill=n))+
    geom_tile()+
    geom_text(aes(label=n), color="white")+
    scale_fill_gradientn(
      colors = c("grey", col_low, col_high),
      values = scales::rescale(c(0, 0.01, 1)),
      limits = c(0, 200),
      breaks = seq(0, 1, 0.25),
      #labels = 200 * seq(0, 1, 0.25),
      name = "progress"
    )+
    theme_bw()+
    ylab("size fraction")
  
  
  
  sampling_time_plot <-all_files_raw %>%
    group_by(site, sampling_time, .drop=F) %>%
    tally() %>%
    ggplot(data=., aes(x=site, y=sampling_time, fill=n))+
    geom_tile()+
    geom_text(aes(label=n), color="white")+
    scale_fill_gradientn(
      colors = c("grey", col_low, col_high),
      values = scales::rescale(c(0, 0.01, 1)),
      limits = c(0, 200),
      breaks = seq(0, 1, 0.25),
      #labels = 200 * seq(0, 1, 0.25),
      name = "progress"
    )+
    theme_bw()+
    ylab("daytime")
  

  
  comb_plot <- 
    cowplot::plot_grid(
      plotlist=c(barplot+theme(axis.title.x = element_blank(), 
                               axis.text.x = element_blank(), 
                               axis.ticks.x = element_blank(),
                              # legend.position="none"
                               ), 
                 sampling_time_plot+theme(axis.title.x = element_blank(), axis.text.x = element_blank(), axis.ticks.x = element_blank(),
                                          legend.position="none"
                                          ), 
                 sizefrac_plot+theme(
                   legend.position="none"
                   )), 
      nrow=3,
      align="v",
      rel_heights = c(2,1, 0.9)
    )
  
  
}










