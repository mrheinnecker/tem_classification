# nf-core/ampliseq setup for the mixed-domain SSU dataset

This setup targets nf-core/ampliseq 2.18.0 with paired Illumina reads that
contain both primer orientations. It does not assume that the amplicons are
exclusively bacterial 16S; the experiment is expected to recover prokaryotic
16S and eukaryotic 18S SSU sequences.

## Required information

Before running, supply:

1. Exact forward and reverse biological primer sequences, 5' to 3'. Exclude
   adapters, indices, pads, linkers, heterogeneity spacers, and barcodes.
2. Cluster-visible absolute paths for FASTQs, output, work, and the Apptainer
   cache.
3. Any required Slurm account, partition, or QoS.
4. Experimental metadata and biological sample names, if available. The
   supplied `sampleinfo.tsv` identifies six paired negative-control samples;
   ENA run accessions are used as sample IDs until better metadata is supplied.

## Why the custom config is required

In a 100,000-pair check of ERR16149169, 45.55% of pairs had the forward primer
in read 1 and 47.72% had it in read 2. The stock ampliseq paired-Illumina
Cutadapt command accepts only the first orientation and discards the other.
`ampliseq_orientation.config` adds Cutadapt 5.2's `--revcomp` option, which
normalizes paired orientation by swapping mates when appropriate.

## Pilot procedure

Edit the single command in `launcher.sh`. All changing inputs are listed there,
including paths, sample counts, primers, pipeline version, resource ceilings,
container profile, and optional Slurm allocation fields. Then run:

```bash
./launcher.sh
```

`main.sh` validates those values, gzip-tests and selects the requested samples,
creates the samplesheet and parameter file, prepares scratch directories, and
submits the Nextflow controller job. Use `all` for either sample count to
include every available sample of that type.

The pilot deliberately sets `skip_taxonomy: true`. First inspect Cutadapt read
retention, DADA2 filtering/merging, ASV lengths, FastQC, and MultiQC. Taxonomic
classification should then be configured with a reference that represents both
prokaryotic 16S and eukaryotic 18S; the pipeline's built-in DADA2 SILVA dataset
is documented as unsuitable for Eukaryotes, while PR2 targets 18S.
