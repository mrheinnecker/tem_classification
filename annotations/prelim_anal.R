
library(cowplot)
library(tidyverse)

save_plot <- function(p, name, width, height) {
  for (ext in c("pdf", "png")) {
    ggsave(file.path(plot_dir, paste0(name, ".", ext)), p, width = width, height = height,
           dpi = 300, bg = "white", limitsize = FALSE)
  }
}
plot_dir <- "C:/projects/tem_classification/plots"



all_annotations <- read_tsv("C:/projects/tem_classification/all_annotations_2026-10-15.tsv")




ov_annotations <- all_annotations  %>%
  mutate(
    filename=basename(file)
  ) %>%
  select(name, run, filename) %>%
  pivot_wider(names_from = "run", values_from = "filename")

## run columns are YYYYMMDD_HHMMSS timestamps -> sort them chronologically
## (pivot_wider orders them by appearance, not by time)
run_cols <- sort(setdiff(names(ov_annotations), "name"))

## for every cell: the earliest run column in which it has an annotation
first_run <- ov_annotations %>%
  pivot_longer(all_of(run_cols), names_to = "run", values_to = "filename") %>%
  filter(!is.na(filename)) %>%
  group_by(name) %>%
  summarise(run = min(run), n_runs = n(), .groups = "drop")

## keep only the first annotation of each cell, drop the later duplicates
annotations_first <- all_annotations %>%
  semi_join(first_run, by = c("name", "run"))


group_lookup <- tibble(
  code  = as.character(1:8),
  group = c("Dinoflagellates", "Diatoms", "Ciliates", "Flagellates",
            "Coccolithophores", "Dictyocha", "Others", "Haptophytes")
)


tot_cells_per_site <- annotations_first %>%
  group_by(site) %>%
  tally()


p_ov_site_major_group <- annotations_first %>%
  #filter(major_group %in% seq(1,8)) %>%
  left_join(group_lookup, by=c("major_group"="code")) %>%
  group_by(
    site, group
  ) %>%
  tally() %>%
  ggplot(
    aes(x=site, y=n, fill=group)
  )+geom_col()+
  geom_text(data=tot_cells_per_site, inherit.aes=F, aes(x=site, y=n, label = n), vjust=0)+
  theme_bw()


save_plot(p_ov_site_major_group, "ov_site_major_group", 5, 3)






## undescribed: messy comma separated numbers ("16, 18?", "9,17,", "7or8", "many 7, 18")
## -> extract every number, one 0/1 column per number (undescribed_<n>)
## "0" means nothing undescribed, NA stays NA in all columns
## uncertain entries ("17?") are counted as present

annotations_first <- annotations_first %>% filter(major_group==1)


undescribed_wide <- annotations_first %>%
  select(name, undescribed) %>%
  mutate(nr = str_extract_all(undescribed, "\\d+")) %>%
  unnest(nr, keep_empty = TRUE) %>%
  mutate(nr = as.integer(nr)) %>%
  filter(is.na(nr) | nr != 0) %>%
  distinct(name, nr) %>%
  mutate(present = 1L) %>%
  pivot_wider(names_from = nr, values_from = present, values_fill = 0L,
              names_prefix = "undescribed_", names_sort = TRUE) %>%
  select(-any_of("undescribed_NA"))

annotations_first <- annotations_first %>%
  left_join(undescribed_wide, by = "name") %>%
  mutate(across(starts_with("undescribed_"), ~ if_else(is.na(undescribed), NA_integer_, replace_na(.x, 0L))))

udo_cols <- setdiff(names(undescribed_wide), "name")

## ---- features across sampling sites, with site tests ----
## site_feature_plot(): heatmap of the cells with each 0/1 feature per site + p-values of three site tests
## NAs dropped per feature, BH correction over the features (per test)
## KW:   Kruskal-Wallis on the 0/1 values; for 0/1 data it is the chi-squared test of the
##       site x present table (H = (N-1)/N * X^2), so KW and chi2 give almost the same p
## chi2: chi-squared test of the site x present table
##       both treat every cell as independent -> optimistic p-values
## GLMM: binomial mixed model present ~ site + (1 | sample), likelihood-ratio test against
##       present ~ 1 + (1 | sample); the sample (barcode) takes up the cells of one sample being alike,
##       so site is tested against the sample-to-sample variation
## outlines: for features with a significant GLMM site test, one model per site,
##       present ~ this site vs. all others + (1 | sample), Wald test of the site term
##       p < 0.05 -> that site has clearly more (solid) / fewer (dashed) cells with the feature
library(lme4)
library(patchwork)

glmm_site_p <- function(d) {
  ctrl <- glmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 1e5))
  tryCatch({
    m1 <- suppressMessages(suppressWarnings(glmer(value ~ site + (1 | sample), data = d, family = binomial, control = ctrl)))
    m0 <- suppressMessages(suppressWarnings(glmer(value ~ 1 + (1 | sample), data = d, family = binomial, control = ctrl)))
    anova(m0, m1)$`Pr(>Chisq)`[2]
  }, error = function(e) NA_real_)
}

## feat_groups: named list group -> features, top to bottom; features not listed go into "specific"
## (numeric order). One group only (e.g. undescribed) -> no group labels
site_feature_plot <- function(annot, feature_cols, feat_groups = list()) {
  tot_cells_per_site <- annot %>%
    group_by(site) %>%
    tally()

  feat_long <- annot %>%
    mutate(sample = str_extract(source_name, "(?<=_)\\d{9}(?=_[A-Z]{3}_)")) %>%
    select(site, sample, all_of(feature_cols)) %>%
    pivot_longer(cols = all_of(feature_cols)) %>%
    filter(!is.na(value))
  ## row order + group of every feature, the same in all panels
  ## numbers in the names sorted numerically (undescribed_2 before undescribed_11)
  feat_groups <- map(feat_groups, ~ intersect(.x, feature_cols))
  feat_groups$specific <- str_sort(setdiff(feature_cols, unlist(feat_groups)), numeric = TRUE)
  feat_groups <- compact(feat_groups)
  feat_info <- enframe(feat_groups, name = "group", value = "name") %>% unnest(name)
  add_feat_info <- function(d) {
    d %>%
      mutate(name = as.character(name)) %>%
      left_join(feat_info, by = "name") %>%
      mutate(name  = factor(name, rev(feat_info$name)),  # first feature on top
             group = factor(group, names(feat_groups)))
  }
  ## one block per group, the group name only on the right panel
  group_facets <- facet_grid(group ~ ., scales = "free_y", space = "free_y")
  no_strip <- theme(strip.text.y = element_blank(), strip.background = element_blank())
  if (length(feat_groups) == 1) group_facets <- NULL

  across_sites <- feat_long %>%
    group_by(site, name) %>%
    summarize(n_abs = sum(value), .groups = "drop") %>%
    left_join(tot_cells_per_site, by = "site") %>%
    mutate(frac = n_abs / n)

  site_tests <- feat_long %>%
    group_by(name) %>%
    filter(n_distinct(value) > 1) %>%
    summarise(
      KW   = kruskal.test(value ~ factor(site))$p.value,
      chi2 = suppressWarnings(chisq.test(table(value, site))$p.value),
      GLMM = glmm_site_p(cur_data()),
      .groups = "drop"
    ) %>%
    pivot_longer(c(KW, chi2, GLMM), names_to = "test", values_to = "p") %>%
    group_by(test) %>%
    mutate(p_adj = p.adjust(p, method = "BH")) %>%
    ungroup() %>%
    mutate(test = factor(test, levels = c("KW", "chi2", "GLMM")),
           p_class = cut(p_adj, c(0, 0.001, 0.01, 0.05, 1), include.lowest = TRUE,
                         labels = c("< 0.001", "< 0.01", "< 0.05", "n.s."))) %>%
    ## features without a test (never present) keep an empty row
    complete(name = feature_cols, test)

  glmm_sign <- site_tests %>% filter(test == "GLMM", p_adj < 0.05) %>% pull(name)

  glmm_site_effects <- feat_long %>%
    filter(name %in% glmm_sign) %>%
    group_by(name) %>%
    group_modify(~ {
      d <- .x
      map_dfr(sort(unique(d$site)), function(s) {
        d$this_site <- as.integer(d$site == s)
        tryCatch({
          m <- suppressMessages(suppressWarnings(glmer(value ~ this_site + (1 | sample), data = d, family = binomial,
                                                       control = glmerControl(optimizer = "bobyqa"))))
          co <- summary(m)$coefficients["this_site", ]
          tibble(site = s, glmm_est = co[["Estimate"]], glmm_p = co[["Pr(>|z|)"]])
        }, error = function(e) tibble(site = s, glmm_est = NA_real_, glmm_p = NA_real_))
      })
    }) %>%
    ungroup()
  if (nrow(glmm_site_effects) == 0) {
    glmm_site_effects <- tibble(name = character(), site = character(), glmm_est = numeric(), glmm_p = numeric())
  }
  glmm_site_effects <- glmm_site_effects %>%
    mutate(glmm_mark = case_when(glmm_p < 0.05 & glmm_est > 0 ~ "more",
                                 glmm_p < 0.05 & glmm_est < 0 ~ "fewer"))

  across_sites <- across_sites %>%
    left_join(glmm_site_effects %>% select(name, site, glmm_mark), by = c("name", "site"))

  across_sites <- add_feat_info(across_sites)

  p_feat <- ggplot(across_sites, aes(x = site, y = name, fill = frac)) +
    geom_tile() +
    geom_tile(data = filter(across_sites, !is.na(glmm_mark)),
              aes(linetype = glmm_mark), fill = NA, colour = "#00E5FF", linewidth = 0.8,
              width = 0.92, height = 0.88) +
    ## black text on the bright end of the colour scale (relative to the max of this plot)
    geom_text(aes(label = n_abs, colour = ifelse(frac > 0.75 * max(frac), "black", "white"))) +
    scale_fill_viridis_c(option = "inferno") +
    scale_colour_identity() +
    scale_linetype_manual(values = c(more = "solid", fewer = "22"), drop = FALSE,
                          limits = c("more", "fewer"), name = "site effect (GLMM sign.)") +
    group_facets + no_strip

  ## p-values of the three site tests, BH-adjusted, colour = significance class
  p_pval <- ggplot(add_feat_info(site_tests), aes(x = test, y = name, fill = p_class)) +
    geom_tile(colour = "white") +
    geom_text(aes(label = case_when(is.na(p_adj) ~ "",
                                    p_adj < 0.001 ~ sprintf("%.0e", p_adj),
                                    TRUE ~ formatC(p_adj, digits = 1, format = "g")),
                  colour = ifelse(p_class %in% c("< 0.001", "< 0.01"), "white", "black")), size = 2.1) +
    scale_colour_identity() +
    scale_fill_manual(values = c(`< 0.001` = "#08519C", `< 0.01` = "#4292C6", `< 0.05` = "#9ECAE1", n.s. = "grey92"),
                      drop = FALSE, na.translate = FALSE, name = "site test\n(BH-adj. p)") +
    labs(x = NULL) +
    group_facets + no_strip +
    theme(
      axis.title.y = element_blank(),
      axis.text.y  = element_blank(),
      axis.ticks.y = element_blank()
    )

  tot_per_feature <- across_sites %>%
    group_by(name) %>%
    summarize(n_tot = sum(n_abs)) %>%
    add_feat_info()

  p_bar <- ggplot(tot_cells_per_site, aes(y = n, x = site)) +
    geom_col() +
    geom_text(aes(label = n), vjust = -0.3, size = 3) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
    theme(
      axis.title.x = element_blank(),
      axis.text.x  = element_blank(),
      axis.ticks.x = element_blank()
    )

  p_side <- ggplot(tot_per_feature, aes(x = n_tot, y = name)) +
    geom_col() +
    geom_text(aes(label = n_tot), hjust = -0.2, size = 3) +
    scale_x_continuous(expand = expansion(mult = c(0, 0.35))) +
    group_facets +
    theme(
      axis.title.y = element_blank(),
      axis.text.y  = element_blank(),
      axis.ticks.y = element_blank()
    )

  p_comb <- p_bar + plot_spacer() + plot_spacer() + p_feat + p_pval + p_side +
    plot_layout(ncol = 3, widths = c(3, 1.1, 1), heights = c(0.5, 2), guides = "collect")

  list(plot = p_comb, across_sites = across_sites, site_tests = site_tests, glmm_site_effects = glmm_site_effects)
}

## organelles
## same groups as the association map below: chloroplast related, common organelles, the rest specific
org_res <- site_feature_plot(annotations_first, names(annotations_first)[18:45],
                             feat_groups = list(chloroplast = c("chloropl", "plastoglob", "pyrenoid"),
                                                common = c("mito", "ER", "golgi", "nucleus", "nucleolus", "lysosome", "lipid_drop")))
save_plot(org_res$plot, "orgs_per_site", 9, 9)

## undescribed organelles
udo_res <- site_feature_plot(annotations_first, udo_cols)
save_plot(udo_res$plot, "udos_per_site", 9, 3 + 0.25 * length(udo_cols))


to_do_correlation_analysis <- annotations_first %>%
  select(5,7,8, 15:ncol(annotations_first)) %>%
  select(-comments, -annotated_by, -validated_by, -taxo_class, -undescribed, -file, -run, -done_by)




















## ---- pairwise association analysis ----
## nominal columns (some coded as numbers, but without order) -> treat as categorical
nominal_cols <- c("site", "size_frac", "sampling_time", "life_status", "major_group")

cor_data <- to_do_correlation_analysis %>%
  mutate(major_group = na_if(as.character(major_group), "?"),
         across(any_of(nominal_cols), as.character))

is_binary <- function(x) is.numeric(x) && all(na.omit(x) %in% c(0, 1))

## picks the test by column type, NAs are dropped per pair
test_pair <- function(var1, var2) {
  d <- cor_data %>% select(x = all_of(var1), y = all_of(var2)) %>% drop_na()
  out <- tibble(var1, var2, n = nrow(d), 
                n1=nrow(d %>% filter(x==1)),
                n2=nrow(d %>% filter(y==1)),
                test = NA_character_, estimate = NA_real_,
                var1_present = NA_character_, var1_absent = NA_character_,
                odds_ratio = NA_real_, or_ci_low = NA_real_, or_ci_high = NA_real_, p_value = NA_real_)
  if (n_distinct(d$x) < 2 || n_distinct(d$y) < 2) return(out)

  if (is_binary(d$x) && is_binary(d$y)) {
   # rawn <- d %>% group_by(x,y) %>% tally() %>% drop_na() %>% mutate(cat=paste0("x", x, "y", y)) %>% ungroup() %>% select(cat, n) %>% pivot_wider(names_from = "cat", values_from = "n")
    
    ## 0/1 vs 0/1: exact test on the 2x2 table, effect = phi coefficient (-1..1)
    ## + conditional MLE odds ratio with 95% CI (only defined for 2x2)
    ## counts behind the OR as "var2 present / var2 absent", split by var1 present / absent
    ## OR ~ (a/b) / (c/d)
    tab <- table(factor(d$x, levels = 0:1), factor(d$y, levels = 0:1))
    res <- fisher.test(tab)
    out %>% mutate(test = "fisher 2x2", estimate = cor(d$x, d$y),
                   var1_present = paste0(tab["1", "1"], "/", tab["0", "0"]),
                   var1_absent  = paste0(tab["0", "1"], "/", tab["1", "0"]),
                   x1y1=tab["1", "1"],x0y0=tab["0", "0"],x0y1=tab["0", "1"],x1y0=tab["1", "0"],
                   odds_ratio = unname(res$estimate), or_ci_low = res$conf.int[1], or_ci_high = res$conf.int[2],
                   p_value = res$p.value) #%>%
    #  bind_cols(rawn)
  } else if (is.numeric(d$x) && is.numeric(d$y)) {
    ## ordinal (beauty) vs numeric: rank correlation (-1..1)
    res <- cor.test(d$x, d$y, method = "spearman", exact = FALSE)
    out %>% mutate(test = "spearman", estimate = unname(res$estimate), p_value = res$p.value)
  } else {
    ## at least one categorical: fisher with simulated p, effect = Cramer's V (0..1)
    tab <- table(d$x, d$y)
    res <- fisher.test(tab, simulate.p.value = TRUE, B = 1e4)
    chi2 <- suppressWarnings(chisq.test(tab, correct = FALSE)$statistic)
    out %>% mutate(test = "fisher RxC", estimate = unname(sqrt(chi2 / (sum(tab) * (min(dim(tab)) - 1)))),
                   p_value = res$p.value)
  }
}

set.seed(42)
cor_results <- combn(names(cor_data), 2, simplify = FALSE) %>%
  map_dfr(~ test_pair(.x[1], .x[2])) %>%
  mutate(p_adj = p.adjust(p_value, method = "bonferroni")) %>%
  arrange(p_adj) #%>%

to_be_plotted <- cor_results %>%
  filter(p_adj<0.05) 


## ---- plots of the significant associations ----
plot_dir <- "C:/projects/tem_classification/plots"
dir.create(plot_dir, showWarnings = FALSE, recursive = TRUE)

stars <- function(p) case_when(p < 0.001 ~ "***", p < 0.01 ~ "**", p < 0.05 ~ "*", TRUE ~ "")

## 1) association map: every significant pair, features ordered by clustering
plot_pairs <- to_be_plotted %>% filter(!is.na(estimate))
feats <- unique(c(plot_pairs$var1, plot_pairs$var2))
m <- matrix(0, length(feats), length(feats), dimnames = list(feats, feats))
m[cbind(plot_pairs$var1, plot_pairs$var2)] <- plot_pairs$estimate
m <- m + t(m)
feat_clustered <- if (length(feats) > 2) feats[hclust(dist(m))$order] else feats

## manual order: chloroplast related, common organelles, specific ones (clustered),
## metadata, undescribed at the end
chloro_feats <- c("chloropl", "plastoglob", "pyrenoid")
common_feats <- c("mito", "ER", "golgi", "nucleus", "nucleolus", "lysosome", "lipid_drop")
meta_feats   <- c("site", "size_frac", "sampling_time", "life_status", "major_group", "beauty")
undesc_feats <- str_sort(str_subset(feats, "^undescribed_"), numeric = TRUE)
specific_feats <- setdiff(feat_clustered, c(chloro_feats, common_feats, meta_feats, undesc_feats))

feat_order <- c(intersect(feat_clustered, chloro_feats),
                intersect(common_feats, feats),
                specific_feats,
                intersect(meta_feats, feats),
                undesc_feats)

## feature group of every feature, used for the facets
feat_groups <- tibble(feature = feat_order) %>%
  mutate(group = case_when(feature %in% chloro_feats ~ "chloroplast",
                           feature %in% common_feats ~ "common",
                           feature %in% meta_feats   ~ "metadata",
                           feature %in% undesc_feats ~ "undescribed",
                           TRUE                      ~ "specific"),
         group = factor(group, c("chloroplast", "common", "specific", "metadata", "undescribed")))
group_of <- function(f) feat_groups$group[match(f, feat_groups$feature)]

## lower triangle only: orient every pair so the x feature comes before the y feature
heatmap_data <- plot_pairs %>%
  mutate(i1 = match(var1, feat_order), i2 = match(var2, feat_order),
         x = feat_order[pmin(i1, i2)], y = feat_order[pmax(i1, i2)],
         x_group = group_of(x), y_group = group_of(y),
         x = factor(x, feat_order[-length(feat_order)]),
         y = factor(y, rev(feat_order[-1])))

## total number of cells with the feature (0/1 columns) or annotated cells (other columns),
## shown on top / right of the heatmap
feat_counts <- map_int(cor_data, ~ if (is_binary(.x)) sum(.x == 1, na.rm = TRUE) else sum(!is.na(.x)))
## drawn as text outside the outer panels: x counts above the top facet row, y counts right of the last column
top_counts <- distinct(heatmap_data, x, x_group) %>%
  mutate(y_group = factor(levels(droplevels(heatmap_data$y_group))[1], levels(heatmap_data$y_group)),
         n = feat_counts[as.character(x)])
right_counts <- distinct(heatmap_data, y, y_group) %>%
  mutate(x_group = factor(last(levels(droplevels(heatmap_data$x_group))), levels(heatmap_data$x_group)),
         n = feat_counts[as.character(y)])

## light background only for the group blocks that contain pairs, empty blocks stay invisible
heatmap_blocks <- distinct(heatmap_data, x_group, y_group)

p_heatmap <- ggplot(heatmap_data, aes(x, y, fill = estimate)) +
  geom_rect(data = heatmap_blocks, xmin = -Inf, xmax = Inf, ymin = -Inf, ymax = Inf,
            fill = "grey95", inherit.aes = FALSE) +
  geom_tile(colour = "white") +
  geom_text(aes(label = stars(p_adj)), size = 3, vjust = 0.75) +
  scale_fill_gradient2(low = "#2166ac", mid = "white", high = "#b2182b", limits = c(-1, 1),
                       name = "phi / rho /\nCramer's V") +
  geom_text(data = top_counts, aes(x = x, y = Inf, label = n), inherit.aes = FALSE,
            angle = 90, hjust = -0.2, size = 2.5, colour = "grey40") +
  geom_text(data = right_counts, aes(x = Inf, y = y, label = n), inherit.aes = FALSE,
            hjust = -0.3, size = 2.5, colour = "grey40") +
  facet_grid(y_group ~ x_group, scales = "free", space = "free", switch = "both") +
  coord_cartesian(clip = "off") +
  labs(x = NULL, y = NULL, title = "Significant associations",
       subtitle = "* p_adj < 0.05, ** < 0.01, *** < 0.001 | top / right: number of cells with the feature") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1), panel.grid = element_blank(),
        plot.margin = margin(10, 10, 5, 5), plot.subtitle = element_text(margin = margin(b = 30)),
        legend.box.spacing = unit(30, "pt"),
        panel.spacing = unit(4, "pt"), strip.placement = "outside",
        strip.text = element_text(face = "bold"), strip.text.y.left = element_text(angle = 0, hjust = 1))

## 2) 0/1 feature pairs: odds ratios + how var1 shifts the frequency of var2
or_cap <- 6   # log2 OR axis limit, OR = 0 / Inf are drawn at the cap
or_pairs <- to_be_plotted %>%
  filter(test == "fisher 2x2") %>%
  separate_wider_delim(var1_present, "/", names = c("a", "b"), cols_remove = FALSE) %>%
  separate_wider_delim(var1_absent, "/", names = c("c", "d"), cols_remove = FALSE) %>%
  mutate(across(c(a, b, c, d), as.numeric),
         prev_var1_present = a / (a + b),
         prev_var1_absent  = c / (c + d),
         pair = fct_reorder(paste(var1, "\u2192", var2), log2(odds_ratio)),
         direction = if_else(odds_ratio > 1, "co-occur", "exclude"),
         point = if_else(abs(log2(odds_ratio)) >= or_cap, "capped (OR 0 / Inf)", "estimate"),
         across(c(odds_ratio, or_ci_low, or_ci_high), ~ pmin(pmax(log2(.x), -or_cap), or_cap), .names = "l2_{.col}"))

p_forest <- ggplot(or_pairs, aes(l2_odds_ratio, pair, colour = direction)) +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "grey50") +
  geom_errorbar(aes(xmin = l2_or_ci_low, xmax = l2_or_ci_high), width = 0.3, orientation = "y") +
  geom_point(aes(shape = point), size = 2.5) +
  geom_text(aes(x = or_cap + 0.5, label = paste(var1_present, "vs", var1_absent)),
            hjust = 0, colour = "grey30", size = 3) +
  scale_colour_manual(values = c("co-occur" = "#b2182b", "exclude" = "#2166ac"), name = NULL) +
  scale_shape_manual(values = c("estimate" = 16, "capped (OR 0 / Inf)" = 4), name = NULL) +
  coord_cartesian(xlim = c(-or_cap, or_cap + 3), clip = "off") +
  labs(x = "log2 odds ratio (95% CI)", y = "var1 \u2192 var2", title = "Feature co-occurrence",
       subtitle = "text: var2 present/absent among cells with var1 vs without var1") +
  theme_minimal()

p_dumbbell <- ggplot(or_pairs, aes(y = pair)) +
  geom_segment(aes(x = prev_var1_absent, xend = prev_var1_present, yend = pair),
               colour = "grey70", linewidth = 1) +
  geom_point(aes(x = prev_var1_absent, colour = "without var1"), size = 2.5) +
  geom_point(aes(x = prev_var1_present, colour = "with var1"), size = 2.5) +
  scale_x_continuous(labels = scales::percent, limits = c(0, 1)) +
  scale_colour_manual(values = c("without var1" = "grey50", "with var1" = "#d95f02"), name = NULL) +
  labs(x = "cells with var2", y = "var1 \u2192 var2",
       title = "Frequency of var2 in cells with vs without var1") +
  theme_minimal()

## 3) pairs with a categorical variable (site, size_frac, major_group, ...): composition per category
plot_cat_pair <- function(var1, var2, p_adj, estimate) {
  d <- cor_data %>% select(x = all_of(var1), y = all_of(var2)) %>% drop_na() %>%
    mutate(across(c(x, y), as.factor))
  ## variable with more levels goes on the x axis
  if (nlevels(d$y) > nlevels(d$x)) {
    d <- rename(d, x = y, y = x)
    tmp <- var1; var1 <- var2; var2 <- tmp
  }
  ggplot(d, aes(x, fill = y)) +
    geom_bar(position = "fill") +
    geom_text(data = count(d, x), aes(x, y = 1.02, label = n), inherit.aes = FALSE, size = 3, vjust = 0) +
    scale_y_continuous(labels = scales::percent) +
    scale_fill_brewer(palette = "Set2", name = var2) +
    labs(x = var1, y = "fraction of cells", title = paste(var1, "vs", var2),
         subtitle = sprintf("Cramer's V = %.2f, p_adj = %.2g (n per bar on top)", estimate, p_adj)) +
    theme_minimal()
}

cat_plots <- to_be_plotted %>%
  filter(test == "fisher RxC") %>%
  select(var1, var2, p_adj, estimate) %>%
  pmap(plot_cat_pair)

## 4) lookup: contingency table of every significant pair, ordered by p_adj
est_names <- c("fisher 2x2" = "phi", "spearman" = "rho", "fisher RxC" = "Cramer's V")

ct_long <- to_be_plotted %>%
  select(var1, var2, test, estimate, p_adj) %>%
  pmap_dfr(function(var1, var2, test, estimate, p_adj) {
    cor_data %>%
      select(x = all_of(var1), y = all_of(var2)) %>%
      drop_na() %>%
      mutate(across(c(x, y), as.character)) %>%
      count(x, y) %>%
      complete(x, y, fill = list(n = 0L)) %>%
      mutate(frac_x = n / sum(n), .by = x) %>%
      mutate(pair = sprintf("x: %s | y: %s\n%s = %.2f, p_adj = %.1e", var1, var2, est_names[test], estimate, p_adj))
  }) %>%
  mutate(pair = factor(pair, unique(pair)))

n_col <- ceiling(sqrt(n_distinct(ct_long$pair)))
n_row <- ceiling(n_distinct(ct_long$pair) / n_col)

p_tables <- ggplot(ct_long, aes(x, y, fill = frac_x)) +
  geom_tile(colour = "white") +
  geom_text(aes(label = n), size = 3) +
  facet_wrap(~ pair, scales = "free", ncol = n_col) +
  scale_fill_gradient(low = "white", high = "#d95f02", limits = c(0, 1), labels = scales::percent,
                      name = "share within\nx category") +
  labs(x = NULL, y = NULL, title = "Contingency tables of all significant pairs",
       subtitle = "numbers = cell counts, colour = distribution of y within each x category (column)") +
  theme_minimal(base_size = 9) +
  theme(panel.grid = element_blank(), strip.text = element_text(size = 7, hjust = 0))

## show + save
p_heatmap; p_forest; p_dumbbell; walk(cat_plots, print); p_tables

## every plot as pdf + png (white background, theme_minimal is transparent otherwise)
save_plot <- function(p, name, width, height) {
  for (ext in c("pdf", "png")) {
    ggsave(file.path(plot_dir, paste0(name, ".", ext)), p, width = width, height = height,
           dpi = 300, bg = "white", limitsize = FALSE)
  }
}
#plot_dir <- "C:/projects/tem_classification/plots"
save_plot(p_heatmap, "assoc_heatmap", 10, 9)
save_plot(p_forest, "assoc_odds_ratios", 10, 2 + 0.25 * nrow(or_pairs))
save_plot(p_dumbbell, "assoc_frequency_shift", 8, 2 + 0.25 * nrow(or_pairs))
save_plot(p_tables, "assoc_contingency_tables", 3 * n_col, 2.6 * n_row + 1)

## categorical: all pairs in one multi-page pdf, one png per pair
if (length(cat_plots) > 0) {
  pdf(file.path(plot_dir, "assoc_categorical.pdf"), width = 7, height = 5)
  walk(cat_plots, print)
  dev.off()
  iwalk(cat_plots, ~ ggsave(file.path(plot_dir, sprintf("assoc_categorical_%02d.png", .y)), .x,
                            width = 7, height = 5, dpi = 300, bg = "white"))
}
