#!/usr/bin/env bash

# Build a standardized nf-core/ampliseq samplesheet from paired ENA FASTQs.
# Usage:
#   make_ampliseq_samplesheet.sh FASTQ_DIR OUTPUT_TSV \
#       [SAMPLEINFO_TSV [MAX_ENVIRONMENTAL [MAX_CONTROLS]]]

set -euo pipefail

if (( $# < 2 || $# > 5 )); then
    echo "Usage: $0 FASTQ_DIR OUTPUT_TSV [SAMPLEINFO_TSV [MAX_ENVIRONMENTAL [MAX_CONTROLS]]]" >&2
    exit 2
fi

readonly FASTQ_DIR_INPUT="$1"
readonly OUTPUT_TSV="$2"
readonly SAMPLEINFO_TSV="${3:-}"
readonly MAX_ENVIRONMENTAL="${4:-all}"
readonly MAX_CONTROLS="${5:-all}"

if [[ ! -d "${FASTQ_DIR_INPUT}" ]]; then
    echo "Error: FASTQ directory does not exist: ${FASTQ_DIR_INPUT}" >&2
    exit 2
fi

if [[ ! "${MAX_ENVIRONMENTAL}" =~ ^(all|[0-9]+)$ || ! "${MAX_CONTROLS}" =~ ^(all|[0-9]+)$ ]]; then
    echo "Error: sample limits must be non-negative integers or 'all'." >&2
    exit 2
fi

if [[ -n "${SAMPLEINFO_TSV}" && ! -r "${SAMPLEINFO_TSV}" ]]; then
    echo "Error: cannot read sample information table: ${SAMPLEINFO_TSV}" >&2
    exit 2
fi

readonly FASTQ_DIR="$(cd -- "${FASTQ_DIR_INPUT}" && pwd)"
mkdir -p -- "$(dirname -- "${OUTPUT_TSV}")"

mapfile -t FORWARD_FILES < <(
    find "${FASTQ_DIR}" -maxdepth 1 -type f -name '*_1.fastq.gz' -printf '%f\n' | sort
)

if (( ${#FORWARD_FILES[@]} == 0 )); then
    echo "Error: no *_1.fastq.gz files found in ${FASTQ_DIR}." >&2
    exit 1
fi

readonly TEMP_OUTPUT="${OUTPUT_TSV}.tmp.$$"
trap 'rm -f -- "${TEMP_OUTPUT}"' EXIT

declare -A TYPE_BY_FILE=()
if [[ -n "${SAMPLEINFO_TSV}" ]]; then
    while IFS=$'\t' read -r name _url _size _md5 _description _comment _inserted _analyses _samples type; do
        [[ "${name}" == "Name" ]] && continue
        case "${type}" in
            environmental) TYPE_BY_FILE["${name}"]="sample" ;;
            control)       TYPE_BY_FILE["${name}"]="control" ;;
            *)
                echo "Error: unsupported type '${type}' for ${name}." >&2
                exit 1
                ;;
        esac
    done < "${SAMPLEINFO_TSV}"
    printf 'sample\tfastq_1\tfastq_2\tcontrol\n' > "${TEMP_OUTPUT}"
else
    printf 'sample\tfastq_1\tfastq_2\n' > "${TEMP_OUTPUT}"
fi

written=0
environmental_written=0
controls_written=0
for forward_name in "${FORWARD_FILES[@]}"; do
    sample="${forward_name%_1.fastq.gz}"
    reverse_name="${sample}_2.fastq.gz"
    forward_path="${FASTQ_DIR}/${forward_name}"
    reverse_path="${FASTQ_DIR}/${reverse_name}"

    if [[ ! "${sample}" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]]; then
        echo "Error: invalid ampliseq sample ID derived from ${forward_name}: ${sample}" >&2
        exit 1
    fi

    sample_type="sample"
    if [[ -n "${SAMPLEINFO_TSV}" ]]; then
        if [[ -z "${TYPE_BY_FILE[${forward_name}]:-}" || -z "${TYPE_BY_FILE[${reverse_name}]:-}" ]]; then
            echo "Error: sample information is missing for ${sample}." >&2
            exit 1
        fi
        if [[ "${TYPE_BY_FILE[${forward_name}]}" != "${TYPE_BY_FILE[${reverse_name}]}" ]]; then
            echo "Error: mate types disagree for ${sample}." >&2
            exit 1
        fi
        sample_type="${TYPE_BY_FILE[${forward_name}]}"
    fi

    if [[ "${sample_type}" == "control" ]]; then
        [[ "${MAX_CONTROLS}" != "all" ]] && (( controls_written >= MAX_CONTROLS )) && continue
    else
        [[ "${MAX_ENVIRONMENTAL}" != "all" ]] && (( environmental_written >= MAX_ENVIRONMENTAL )) && continue
    fi

    if [[ ! -f "${reverse_path}" ]]; then
        if [[ "${SKIP_INCOMPLETE:-0}" == "1" ]]; then
            echo "Warning: skipping ${sample}; reverse mate is missing." >&2
            continue
        else
            echo "Error: missing reverse mate for ${forward_name}: ${reverse_name}" >&2
            exit 1
        fi
    fi

    # The downloader writes directly to the final name, so a present file may
    # still be incomplete. Set CHECK_GZIP=0 to skip this potentially slow test.
    if [[ "${CHECK_GZIP:-1}" != "0" ]]; then
        if ! gzip -t -- "${forward_path}" "${reverse_path}"; then
            if [[ "${SKIP_INCOMPLETE:-0}" == "1" ]]; then
                echo "Warning: skipping incomplete or corrupt FASTQ pair ${sample}." >&2
                continue
            else
                echo "Error: incomplete or corrupt FASTQ pair for ${sample}." >&2
                exit 1
            fi
        fi
    fi

    if [[ -n "${SAMPLEINFO_TSV}" ]]; then
        printf '%s\t%s\t%s\t%s\n' \
            "${sample}" "${forward_path}" "${reverse_path}" "${sample_type}" >> "${TEMP_OUTPUT}"
    else
        printf '%s\t%s\t%s\n' \
            "${sample}" "${forward_path}" "${reverse_path}" >> "${TEMP_OUTPUT}"
    fi

    written=$((written + 1))
    if [[ "${sample_type}" == "control" ]]; then
        controls_written=$((controls_written + 1))
    else
        environmental_written=$((environmental_written + 1))
    fi

    if [[ "${MAX_ENVIRONMENTAL}" != "all" && "${MAX_CONTROLS}" != "all" ]] &&
       (( environmental_written >= MAX_ENVIRONMENTAL && controls_written >= MAX_CONTROLS )); then
        break
    fi
done

if [[ "${MAX_ENVIRONMENTAL}" != "all" ]] && (( environmental_written < MAX_ENVIRONMENTAL )); then
    echo "Error: requested ${MAX_ENVIRONMENTAL} environmental samples but found ${environmental_written} complete pairs." >&2
    exit 1
fi
if [[ "${MAX_CONTROLS}" != "all" ]] && (( controls_written < MAX_CONTROLS )); then
    echo "Error: requested ${MAX_CONTROLS} controls but found ${controls_written} complete pairs." >&2
    exit 1
fi

mv -- "${TEMP_OUTPUT}" "${OUTPUT_TSV}"
trap - EXIT
echo "Wrote ${written} paired samples (${environmental_written} environmental, ${controls_written} controls) to ${OUTPUT_TSV}."
