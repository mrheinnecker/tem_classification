#!/usr/bin/env bash

# Cluster run of nf-core/ampliseq. Run on a Slurm login node (not via sbatch):
#
#   bash launch_ampliseq_cluster.sh
#
# Builds the samplesheet and params file in RUN_DIR, then submits the
# controller job (run_ampliseq_slurm.sh) through main.sh. When it is done, run
# the taxonomy step: sbatch taxonomy/run_taxonomy_slurm.sh (its default
# AMPLISEQ_RESULTS matches RESULTS_DIR below).

set -euo pipefail

## -- edit these ------------------------------------------------------------
RAW_DIR="/g/schwab/marco/projects/trec_metab/datahub_downloads"
ENVIRONMENTAL_SAMPLES="all"        # number or "all"
CONTROL_SAMPLES="all"              # number or "all"
FW_PRIMER="GTGYCAGCMGCCGCGGTAA"
RV_PRIMER="CCGYCAATTYMTTTRAGTTT"
BINNED_QUALITY="2,11,25,37"
PIPELINE_VERSION="2.18.0"
MAX_CPUS="16"
MAX_MEMORY="64.GB"
MAX_TIME="48.h"

SCRATCH_ROOT="/scratch/rheinnec"
RUN_DIR="${SCRATCH_ROOT}/ampliseq_run"
RESULTS_DIR="${RUN_DIR}/results"
WORK_DIR="${RUN_DIR}/work"
APPTAINER_CACHE="${SCRATCH_ROOT}/apptainer_cache"
APPTAINER_TMP="${SCRATCH_ROOT}/apptainer_tmp"

# Optional Slurm settings; leave empty if your cluster does not need them.
SBATCH_ACCOUNT=""
SBATCH_PARTITION=""
SBATCH_QOS=""
## ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/main.sh" \
    --raw-dir "${RAW_DIR}" \
    --sampleinfo "${SCRIPT_DIR}/sampleinfo.tsv" \
    --run-dir "${RUN_DIR}" \
    --work-dir "${WORK_DIR}" \
    --results-dir "${RESULTS_DIR}" \
    --apptainer-cache "${APPTAINER_CACHE}" \
    --apptainer-tmp "${APPTAINER_TMP}" \
    --environmental-samples "${ENVIRONMENTAL_SAMPLES}" \
    --control-samples "${CONTROL_SAMPLES}" \
    --fw-primer "${FW_PRIMER}" \
    --rv-primer "${RV_PRIMER}" \
    --binned-quality "${BINNED_QUALITY}" \
    --pipeline-version "${PIPELINE_VERSION}" \
    --max-cpus "${MAX_CPUS}" \
    --max-memory "${MAX_MEMORY}" \
    --max-time "${MAX_TIME}" \
    --skip-taxonomy true \
    --skip-incomplete 1 \
    --check-gzip 1 \
    --account "${SBATCH_ACCOUNT}" \
    --partition "${SBATCH_PARTITION}" \
    --qos "${SBATCH_QOS}"
