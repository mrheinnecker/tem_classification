#!/usr/bin/env bash

# Prepare and submit an nf-core/ampliseq pilot. User-editable values belong in
# launcher.sh; this script implements and validates them.

set -euo pipefail

usage() {
    echo "Usage: main.sh --raw-dir PATH --sampleinfo FILE --run-dir PATH --work-dir PATH" >&2
    echo "               --results-dir PATH --apptainer-cache PATH --apptainer-tmp PATH" >&2
    echo "               --environmental-samples N|all --control-samples N|all" >&2
    echo "               --fw-primer DNA --rv-primer DNA [options]" >&2
}

RAW_DIR=""
SAMPLEINFO=""
RUN_DIR=""
WORK_DIR=""
RESULTS_DIR=""
APPTAINER_CACHE=""
APPTAINER_TMP=""
ENVIRONMENTAL_SAMPLES=""
CONTROL_SAMPLES=""
FW_PRIMER=""
RV_PRIMER=""
PIPELINE_VERSION="2.18.0"
CONTAINER_PROFILE="apptainer"
BINNED_QUALITY="2,11,25,37"
MAX_CPUS="16"
MAX_MEMORY="64.GB"
MAX_TIME="48.h"
SKIP_TAXONOMY="true"
SKIP_INCOMPLETE="1"
CHECK_GZIP="1"
SBATCH_ACCOUNT=""
SBATCH_PARTITION=""
SBATCH_QOS=""

while (( $# > 0 )); do
    case "$1" in
        --raw-dir)                RAW_DIR="$2"; shift 2 ;;
        --sampleinfo)             SAMPLEINFO="$2"; shift 2 ;;
        --run-dir)                RUN_DIR="$2"; shift 2 ;;
        --work-dir)               WORK_DIR="$2"; shift 2 ;;
        --results-dir)            RESULTS_DIR="$2"; shift 2 ;;
        --apptainer-cache)        APPTAINER_CACHE="$2"; shift 2 ;;
        --apptainer-tmp)          APPTAINER_TMP="$2"; shift 2 ;;
        --environmental-samples) ENVIRONMENTAL_SAMPLES="$2"; shift 2 ;;
        --control-samples)       CONTROL_SAMPLES="$2"; shift 2 ;;
        --fw-primer)              FW_PRIMER="$2"; shift 2 ;;
        --rv-primer)              RV_PRIMER="$2"; shift 2 ;;
        --pipeline-version)       PIPELINE_VERSION="$2"; shift 2 ;;
        --container-profile)      CONTAINER_PROFILE="$2"; shift 2 ;;
        --binned-quality)         BINNED_QUALITY="$2"; shift 2 ;;
        --max-cpus)               MAX_CPUS="$2"; shift 2 ;;
        --max-memory)             MAX_MEMORY="$2"; shift 2 ;;
        --max-time)               MAX_TIME="$2"; shift 2 ;;
        --skip-taxonomy)          SKIP_TAXONOMY="$2"; shift 2 ;;
        --skip-incomplete)        SKIP_INCOMPLETE="$2"; shift 2 ;;
        --check-gzip)             CHECK_GZIP="$2"; shift 2 ;;
        --account)                SBATCH_ACCOUNT="$2"; shift 2 ;;
        --partition)              SBATCH_PARTITION="$2"; shift 2 ;;
        --qos)                    SBATCH_QOS="$2"; shift 2 ;;
        -h|--help)                usage; exit 0 ;;
        *) echo "Error: unknown argument: $1" >&2; usage; exit 2 ;;
    esac
done

for required_value in \
    RAW_DIR SAMPLEINFO RUN_DIR WORK_DIR RESULTS_DIR APPTAINER_CACHE APPTAINER_TMP \
    ENVIRONMENTAL_SAMPLES CONTROL_SAMPLES FW_PRIMER RV_PRIMER; do
    if [[ -z "${!required_value}" ]]; then
        echo "Error: required parameter ${required_value} is empty." >&2
        usage
        exit 2
    fi
done

for count in "${ENVIRONMENTAL_SAMPLES}" "${CONTROL_SAMPLES}"; do
    if [[ ! "${count}" =~ ^(all|[0-9]+)$ ]]; then
        echo "Error: sample counts must be non-negative integers or 'all': ${count}" >&2
        exit 2
    fi
done

for boolean_value in "${SKIP_TAXONOMY}"; do
    if [[ ! "${boolean_value}" =~ ^(true|false)$ ]]; then
        echo "Error: boolean values must be 'true' or 'false': ${boolean_value}" >&2
        exit 2
    fi
done

for binary_value in "${SKIP_INCOMPLETE}" "${CHECK_GZIP}"; do
    if [[ ! "${binary_value}" =~ ^[01]$ ]]; then
        echo "Error: --skip-incomplete and --check-gzip must be 0 or 1." >&2
        exit 2
    fi
done

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SAMPLESHEET="${RUN_DIR}/ampliseq_samplesheet.tsv"
readonly PARAMS_FILE="${RUN_DIR}/ampliseq_params.yaml"
readonly PARAMS_TEMPLATE="${SCRIPT_DIR}/ampliseq_params.example.yaml"
readonly SAMPLESHEET_BUILDER="${SCRIPT_DIR}/make_ampliseq_samplesheet.sh"
readonly SLURM_RUNNER="${SCRIPT_DIR}/run_ampliseq_slurm.sh"

for required_file in \
    "${SAMPLEINFO}" \
    "${PARAMS_TEMPLATE}" \
    "${SAMPLESHEET_BUILDER}" \
    "${SLURM_RUNNER}" \
    "${SCRIPT_DIR}/ampliseq_orientation.config"; do
    if [[ ! -r "${required_file}" ]]; then
        echo "Error: required file is not readable: ${required_file}" >&2
        exit 2
    fi
done

if [[ ! -d "${RAW_DIR}" ]]; then
    echo "Error: raw FASTQ directory does not exist: ${RAW_DIR}" >&2
    exit 2
fi

if ! command -v sbatch >/dev/null 2>&1; then
    echo "Error: sbatch is not available. Run launcher.sh on a Slurm login node." >&2
    exit 2
fi

mkdir -p -- "${RUN_DIR}" "${WORK_DIR}" "${RESULTS_DIR}" "${APPTAINER_CACHE}" "${APPTAINER_TMP}"

SKIP_INCOMPLETE="${SKIP_INCOMPLETE}" CHECK_GZIP="${CHECK_GZIP}" \
    "${SAMPLESHEET_BUILDER}" \
    "${RAW_DIR}" \
    "${SAMPLESHEET}" \
    "${SAMPLEINFO}" \
    "${ENVIRONMENTAL_SAMPLES}" \
    "${CONTROL_SAMPLES}"

cp -- "${PARAMS_TEMPLATE}" "${PARAMS_FILE}"
sed -i \
    -e "s|REPLACE_ME_INPUT|${SAMPLESHEET}|g" \
    -e "s|REPLACE_ME_OUTDIR|${RESULTS_DIR}|g" \
    -e "s|REPLACE_ME_FORWARD_PRIMER|${FW_PRIMER}|g" \
    -e "s|REPLACE_ME_REVERSE_PRIMER|${RV_PRIMER}|g" \
    -e "s|REPLACE_ME_BINNED_QUALITY|${BINNED_QUALITY}|g" \
    -e "s|REPLACE_ME_SKIP_TAXONOMY|${SKIP_TAXONOMY}|g" \
    -e "s|REPLACE_ME_MAX_CPUS|${MAX_CPUS}|g" \
    -e "s|REPLACE_ME_MAX_MEMORY|${MAX_MEMORY}|g" \
    -e "s|REPLACE_ME_MAX_TIME|${MAX_TIME}|g" \
    "${PARAMS_FILE}"

if grep -q 'REPLACE_ME' "${PARAMS_FILE}"; then
    echo "Error: unresolved REPLACE_ME placeholder in ${PARAMS_FILE}." >&2
    exit 2
fi

SBATCH_OPTIONS=()
[[ -n "${SBATCH_ACCOUNT}" ]] && SBATCH_OPTIONS+=("--account=${SBATCH_ACCOUNT}")
[[ -n "${SBATCH_PARTITION}" ]] && SBATCH_OPTIONS+=("--partition=${SBATCH_PARTITION}")
[[ -n "${SBATCH_QOS}" ]] && SBATCH_OPTIONS+=("--qos=${SBATCH_QOS}")

echo "Submitting nf-core/ampliseq ${PIPELINE_VERSION}"
echo "Raw FASTQs:      ${RAW_DIR}"
echo "Samplesheet:     ${SAMPLESHEET}"
echo "Results:         ${RESULTS_DIR}"
echo "Nextflow work:   ${WORK_DIR}"
echo "Apptainer cache: ${APPTAINER_CACHE}"
echo "Apptainer temp:  ${APPTAINER_TMP}"

sbatch \
    "${SBATCH_OPTIONS[@]}" \
    --export="ALL,PARAMS_FILE=${PARAMS_FILE},WORK_DIR=${WORK_DIR},NXF_APPTAINER_CACHEDIR=${APPTAINER_CACHE},APPTAINER_TMPDIR=${APPTAINER_TMP},PIPELINE_VERSION=${PIPELINE_VERSION},CONTAINER_PROFILE=${CONTAINER_PROFILE}" \
    "${SLURM_RUNNER}"
