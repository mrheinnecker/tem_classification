#!/usr/bin/env Rscript
# DADA2 naive Bayesian classifier for one ASV set against one reference.
# Concatenated (non-overlapping) 18S ASVs contain a run of 10 N between the
# reads; k-mers spanning N are ignored by assignTaxonomy.
#
# Usage: assign_taxonomy.R ASVS.fasta REFERENCE.fa.gz TAXLEVELS(comma) MIN_BOOT CPUS OUT_PREFIX

suppressPackageStartupMessages(library(dada2))
set.seed(100)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 6) stop("Usage: assign_taxonomy.R ASVS.fasta REFERENCE TAXLEVELS MIN_BOOT CPUS OUT_PREFIX")
fasta <- args[1]; reference <- args[2]
taxlevels <- strsplit(args[3], ",")[[1]]
min_boot <- as.integer(args[4]); cpus <- as.integer(args[5]); prefix <- args[6]

seqs <- getSequences(fasta)
if (length(seqs) == 0) {
  empty <- data.frame(matrix(ncol = 2 * length(taxlevels) + 1, nrow = 0))
  names(empty) <- c("ASV_ID", taxlevels, paste0("boot_", taxlevels))
  write.table(empty, paste0(prefix, ".tsv"), sep = "\t", row.names = FALSE, quote = FALSE)
  quit(save = "no")
}

taxa <- assignTaxonomy(unname(seqs), reference, taxLevels = taxlevels, minBoot = min_boot,
                       outputBootstraps = TRUE, multithread = cpus, verbose = TRUE)

tax <- as.data.frame(taxa$tax, stringsAsFactors = FALSE)
boot <- as.data.frame(taxa$boot)
names(boot) <- paste0("boot_", names(boot))
out <- data.frame(ASV_ID = names(seqs), tax, boot, check.names = FALSE, row.names = NULL)

write.table(out, paste0(prefix, ".tsv"), sep = "\t", row.names = FALSE, quote = FALSE, na = "")
writeLines(c(paste("reference", reference), paste("taxlevels", args[3]), paste("minBoot", min_boot),
             paste("dada2", packageVersion("dada2"))), paste0(prefix, ".args.txt"))
