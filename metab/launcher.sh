#!/usr/bin/env bash

# Prepare and submit a four-environmental-sample nf-core/ampliseq pilot.
# Run this script from any directory on the cluster:
#
#   ./launcher.sh
#
# Optional Slurm settings can be supplied as environment variables:
#
#   SBATCH_ACCOUNT=my_account SBATCH_PARTITION=my_partition ./launcher.sh

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly RAW_DIR="/g/schwab/marco/projects/trec_metab/datahub_downloads"
readonly SAMPLEINFO="${SCRIPT_DIR}/sampleinfo.tsv"

readonly SCRATCH_ROOT="/scratch/rheinnec"
readonly RUN_DIR="${SCRATCH_ROOT}/ampliseq_4env_test"
readonly WORK_DIR="${RUN_DIR}/work"
readonly RESULTS_DIR="${RUN_DIR}/ampliseq_pilot_results"
readonly APPTAINER_CACHE="${SCRATCH_ROOT}/apptainer_cache"
readonly APPTAINER_TMP="${SCRATCH_ROOT}/apptainer_tmp"

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

if ! command -v sbatch >/dev/null 2>&1; then
    echo "Error: sbatch is not available. Run this launcher on a Slurm cluster login node." >&2
    exit 2
fi

mkdir -p -- \
    "${RUN_DIR}" \
    "${WORK_DIR}" \
    "${APPTAINER_CACHE}" \
    "${APPTAINER_TMP}"

# Select exactly four complete environmental pairs and zero controls. Candidate
# FASTQs are gzip-tested; partial downloads are skipped.
SKIP_INCOMPLETE=1 "${SAMPLESHEET_BUILDER}" \
    "${RAW_DIR}" \
    "${SAMPLESHEET}" \
    "${SAMPLEINFO}" \
    4 \
    0

cp -- "${PARAMS_TEMPLATE}" "${PARAMS_FILE}"
sed -i "s|REPLACE_ME_WITH_ABSOLUTE_PATH|${RUN_DIR}|g" "${PARAMS_FILE}"

# Keep this check explicit so an accidental template change cannot submit a
# workflow with unresolved paths or primer values.
if grep -q 'REPLACE_ME' "${PARAMS_FILE}"; then
    echo "Error: unresolved REPLACE_ME placeholder in ${PARAMS_FILE}." >&2
    exit 2
fi

SBATCH_OPTIONS=()
[[ -n "${SBATCH_ACCOUNT:-}" ]] && SBATCH_OPTIONS+=("--account=${SBATCH_ACCOUNT}")
[[ -n "${SBATCH_PARTITION:-}" ]] && SBATCH_OPTIONS+=("--partition=${SBATCH_PARTITION}")
[[ -n "${SBATCH_QOS:-}" ]] && SBATCH_OPTIONS+=("--qos=${SBATCH_QOS}")

echo "Submitting nf-core/ampliseq 2.18.0 four-sample pilot"
echo "Raw FASTQs:     ${RAW_DIR}"
echo "Samplesheet:    ${SAMPLESHEET}"
echo "Results:        ${RESULTS_DIR}"
echo "Nextflow work:  ${WORK_DIR}"
echo "Apptainer cache:${APPTAINER_CACHE}"
echo "Apptainer temp: ${APPTAINER_TMP}"

sbatch \
    "${SBATCH_OPTIONS[@]}" \
    --export="ALL,PARAMS_FILE=${PARAMS_FILE},WORK_DIR=${WORK_DIR},NXF_APPTAINER_CACHEDIR=${APPTAINER_CACHE},APPTAINER_TMPDIR=${APPTAINER_TMP}" \
    "${SLURM_RUNNER}"
