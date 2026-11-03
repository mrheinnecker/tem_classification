#!/usr/bin/env Rscript
# Split ampliseq ASVs into 16S and 18S sets by barrnap's best hit.
# The kingdom with the lowest e-value wins: bac/arc/mito -> 16S, euk -> 18S.
# ASVs without any barrnap hit go into both sets, the merge step decides later.
#
# Usage: split_asvs.R ASV_seqs.fasta barrnap_summary.tsv

suppressPackageStartupMessages(library(Biostrings))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2) stop("Usage: split_asvs.R ASV_seqs.fasta barrnap_summary.tsv")

seqs <- readDNAStringSet(args[1])
barrnap <- read.delim(args[2], na.strings = c("NA", ""), check.names = FALSE)

kingdoms <- c(arc = "arc_eval", bac = "bac_eval", euk = "euk_eval", mito = "mito_eval")
evals <- as.matrix(barrnap[, kingdoms])
best <- apply(evals, 1, function(e) if (all(is.na(e))) NA_character_ else names(kingdoms)[which.min(e)])

domains <- data.frame(ASV_ID = names(seqs), stringsAsFactors = FALSE)
domains$barrnap_kingdom <- best[match(domains$ASV_ID, barrnap$ASV_ID)]
domains$barrnap_kingdom[is.na(domains$barrnap_kingdom)] <- "none"
domains$ssu <- ifelse(domains$barrnap_kingdom == "euk", "18S",
               ifelse(domains$barrnap_kingdom == "none", "unknown", "16S"))
domains$length <- width(seqs)

in_16S <- domains$ssu %in% c("16S", "unknown")
in_18S <- domains$ssu %in% c("18S", "unknown")
writeXStringSet(seqs[in_16S], "asv_16S.fasta")
writeXStringSet(seqs[in_18S], "asv_18S.fasta")
write.table(domains, "asv_domains.tsv", sep = "\t", row.names = FALSE, quote = FALSE)

print(table(domains$ssu, domains$barrnap_kingdom))
