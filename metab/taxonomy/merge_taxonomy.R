#!/usr/bin/env Rscript
# Combine the SILVA (16S) and PR2 (18S) assignments into one ASV taxonomy and
# one abundance table with taxonomy. ASVs without a barrnap hit were classified
# with both references; the one with the higher bootstrap at the second rank
# is kept (ties go to SILVA). All per-reference columns are kept with a
# silva_/pr2_ prefix, so nothing is lost when the choice is wrong.
#
# Usage: merge_taxonomy.R asv_domains.tsv tax_16S_silva.tsv tax_18S_pr2.tsv \
#            ASV_table.tsv ASV_seqs.fasta MIN_BOOT

suppressPackageStartupMessages(library(Biostrings))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 6) stop("Usage: merge_taxonomy.R domains silva pr2 asv_table asv_fasta min_boot")
read_tsv <- function(f) read.delim(f, check.names = FALSE, stringsAsFactors = FALSE, na.strings = "")

domains <- read_tsv(args[1])
silva <- read_tsv(args[2])
pr2 <- read_tsv(args[3])
counts <- read_tsv(args[4])
seqs <- readDNAStringSet(args[5])
min_boot <- as.integer(args[6])

rank_cols <- function(tax) setdiff(names(tax)[!startsWith(names(tax), "boot_")], "ASV_ID")

# Lineage string, lowest assigned rank and its bootstrap for one reference.
summarise_ref <- function(tax, ref) {
  ranks <- rank_cols(tax)
  out <- lapply(seq_len(nrow(tax)), function(i) {
    assigned <- ranks[!is.na(unlist(tax[i, ranks]))]
    lowest <- if (length(assigned)) tail(assigned, 1) else NA_character_
    data.frame(
      ASV_ID = tax$ASV_ID[i], reference = ref,
      taxonomy = paste(unlist(tax[i, assigned]), collapse = ";"),
      lowest_rank = lowest,
      lowest_taxon = if (is.na(lowest)) NA_character_ else tax[i, lowest],
      lowest_boot = if (is.na(lowest)) NA_integer_ else tax[i, paste0("boot_", lowest)],
      second_boot = tax[i, paste0("boot_", ranks[2])],
      stringsAsFactors = FALSE)
  })
  do.call(rbind, out)
}

sum_silva <- summarise_ref(silva, "SILVA")
sum_pr2 <- summarise_ref(pr2, "PR2")

pick <- function(id, ssu) {
  s <- sum_silva[sum_silva$ASV_ID == id, ]
  p <- sum_pr2[sum_pr2$ASV_ID == id, ]
  if (ssu == "16S") return(s)
  if (ssu == "18S") return(p)
  if (nrow(p) && nrow(s) && p$second_boot > s$second_boot) p else s
}
chosen <- do.call(rbind, mapply(pick, domains$ASV_ID, domains$ssu, SIMPLIFY = FALSE))
chosen$second_boot <- NULL

taxonomy <- merge(domains, chosen, by = "ASV_ID", all.x = TRUE, sort = FALSE)

# Organelle SSU: plastid and mitochondrial 16S are classified by SILVA.
silva_order <- silva$Order[match(taxonomy$ASV_ID, silva$ASV_ID)]
silva_family <- silva$Family[match(taxonomy$ASV_ID, silva$ASV_ID)]
taxonomy$category <- ifelse(taxonomy$reference == "PR2", "eukaryote_nuclear",
                     ifelse(taxonomy$barrnap_kingdom == "mito" | silva_family %in% "Mitochondria", "mitochondrion",
                     ifelse(silva_order %in% "Chloroplast", "plastid",
                     ifelse(is.na(taxonomy$lowest_rank), "unassigned", "prokaryote"))))

prefixed <- function(tax, prefix) { names(tax)[-1] <- paste0(prefix, names(tax)[-1]); tax }
taxonomy <- merge(taxonomy, prefixed(silva, "silva_"), by = "ASV_ID", all.x = TRUE, sort = FALSE)
taxonomy <- merge(taxonomy, prefixed(pr2, "pr2_"), by = "ASV_ID", all.x = TRUE, sort = FALSE)
taxonomy$sequence <- as.character(seqs)[taxonomy$ASV_ID]

taxonomy$total_reads <- rowSums(counts[match(taxonomy$ASV_ID, counts$ASV_ID), -1, drop = FALSE])
taxonomy <- taxonomy[order(-taxonomy$total_reads), ]
write.table(taxonomy, "asv_taxonomy.tsv", sep = "\t", row.names = FALSE, quote = FALSE, na = "")

table_tax <- merge(taxonomy[, c("ASV_ID", "ssu", "category", "reference", "taxonomy", "lowest_taxon")],
                   counts, by = "ASV_ID", sort = FALSE)
table_tax <- table_tax[order(-rowSums(table_tax[, names(counts)[-1], drop = FALSE])), ]
write.table(table_tax, "asv_table_taxonomy.tsv", sep = "\t", row.names = FALSE, quote = FALSE, na = "")

# Short overview for the log: ASVs and reads per category.
overview <- aggregate(total_reads ~ category, taxonomy, function(x) c(asvs = length(x), reads = sum(x)))
overview <- data.frame(category = overview$category, overview$total_reads)
overview$read_percent <- round(100 * overview$reads / sum(overview$reads), 1)
write.table(overview, "taxonomy_overview.tsv", sep = "\t", row.names = FALSE, quote = FALSE)
print(overview)
cat("minBoot used for assignment:", min_boot, "\n")
