#!/usr/bin/env bash

# Minimal nf-core/ampliseq test run. No pre-checks.
# Edit the variables at the top, then: bash launcher.sh

set -euo pipefail

## -- edit these ------------------------------------------------------------
RAW_DIR="/mnt/c/projects/biobank/metab"
SAMPLES="ERR16149169 ERR16149170 ERR16149171 ERR16149175"
FW_PRIMER="GTGYCAGCMGCCGCGGTAA"
RV_PRIMER="CCGYCAATTYMTTTRAGTTT"
BINNED_QUALITY="2,11,25,37"
PIPELINE_VERSION="2.18.0"
MAX_CPUS="16"
MAX_MEMORY="20.GB"
RUN_ROOT="/home/rheinnec/ampliseq_test"
## ---------------------------------------------------------------------------

read -r -a SAMPLES_ARR <<< "${SAMPLES}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${RUN_ROOT}/work"
RESULTS_DIR="${RUN_ROOT}/results"
SAMPLESHEET="${RUN_ROOT}/ampliseq_samplesheet.tsv"
PARAMS_FILE="${RUN_ROOT}/ampliseq_params.yaml"

mkdir -p -- "${WORK_DIR}" "${RESULTS_DIR}"

{
    printf 'sample\tfastq_1\tfastq_2\n'
    for sample in "${SAMPLES_ARR[@]}"; do
        printf '%s\t%s/%s_1.fastq.gz\t%s/%s_2.fastq.gz\n' \
            "${sample}" "${RAW_DIR}" "${sample}" "${RAW_DIR}" "${sample}"
    done
} > "${SAMPLESHEET}"

{
    printf 'input: "%s"\n' "${SAMPLESHEET}"
    printf 'outdir: "%s"\n' "${RESULTS_DIR}"
    printf 'FW_primer: "%s"\n' "${FW_PRIMER}"
    printf 'RV_primer: "%s"\n' "${RV_PRIMER}"
    printf 'binned_quality: "%s"\n' "${BINNED_QUALITY}"
    printf 'skip_taxonomy: true\n'
    printf 'max_cpus: %s\n' "${MAX_CPUS}"
    printf 'max_memory: "%s"\n' "${MAX_MEMORY}"
} > "${PARAMS_FILE}"

echo "Samples:     ${#SAMPLES_ARR[@]}"
echo "Samplesheet: ${SAMPLESHEET}"
echo "Params:      ${PARAMS_FILE}"
echo "Results:     ${RESULTS_DIR}"
echo "Work:        ${WORK_DIR}"
echo "Running nf-core/ampliseq ${PIPELINE_VERSION} in the foreground; logs below."

nextflow run nf-core/ampliseq \
    -r "${PIPELINE_VERSION}" \
    -profile apptainer \
    -params-file "${PARAMS_FILE}" \
    -c "${SCRIPT_DIR}/ampliseq_orientation.config" \
    -c "${SCRIPT_DIR}/nextflow.local.config" \
    -work-dir "${WORK_DIR}"