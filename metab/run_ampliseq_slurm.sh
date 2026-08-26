#!/usr/bin/env bash
#SBATCH --job-name=ampliseq-pilot
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=7-00:00:00
#SBATCH --output=slurm-ampliseq-%j.out
#SBATCH --error=slurm-ampliseq-%j.err

# This long-lived controller job launches nf-core/ampliseq tasks through Slurm.
# Add site-specific #SBATCH --account/--partition directives if required.

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PARAMS_FILE="${PARAMS_FILE:-${SCRIPT_DIR}/ampliseq_params.yaml}"
readonly CONFIG_FILE="${CONFIG_FILE:-${SCRIPT_DIR}/ampliseq_orientation.config}"
readonly WORK_DIR="${WORK_DIR:-${SCRIPT_DIR}/work}"
readonly APPTAINER_CACHE="${NXF_APPTAINER_CACHEDIR:-${SCRIPT_DIR}/apptainer_cache}"

if [[ ! -r "${PARAMS_FILE}" ]]; then
    echo "Error: parameter file not found: ${PARAMS_FILE}" >&2
    echo "Copy ampliseq_params.example.yaml to ampliseq_params.yaml and edit it." >&2
    exit 2
fi

if grep -q 'REPLACE_ME' "${PARAMS_FILE}"; then
    echo "Error: ${PARAMS_FILE} still contains REPLACE_ME placeholders." >&2
    exit 2
fi

if ! command -v nextflow >/dev/null 2>&1; then
    echo "Error: Nextflow is not available. Load the appropriate cluster module." >&2
    exit 2
fi

if ! command -v apptainer >/dev/null 2>&1 && ! command -v singularity >/dev/null 2>&1; then
    echo "Error: neither Apptainer nor Singularity is available." >&2
    exit 2
fi

mkdir -p -- "${WORK_DIR}" "${APPTAINER_CACHE}"
export NXF_APPTAINER_CACHEDIR="${APPTAINER_CACHE}"
export NXF_OPTS="${NXF_OPTS:--Xms1g -Xmx4g}"

echo "Starting nf-core/ampliseq 2.18.0"
echo "Parameters:      ${PARAMS_FILE}"
echo "Custom config:  ${CONFIG_FILE}"
echo "Work directory: ${WORK_DIR}"
echo "Container cache:${NXF_APPTAINER_CACHEDIR}"

nextflow run nf-core/ampliseq \
    -r 2.18.0 \
    -profile apptainer \
    -params-file "${PARAMS_FILE}" \
    -c "${CONFIG_FILE}" \
    -work-dir "${WORK_DIR}" \
    -resume
