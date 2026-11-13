#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly SIM="${SIM:-uvs}"
[[ "${SIM}" =~ ^(uvs|vcs|questa)$ ]] || { echo "Unsupported SIM=${SIM}" >&2; exit 2; }
readonly RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"

ensure_child_directory() {
  local parent="$1"
  local name="$2"
  local child="${parent}/${name}"
  [[ -d "${parent}" && ! -L "${parent}" &&
      "$(realpath -e -- "${parent}")" == "${parent}" ]] || {
    echo "Unsafe coverage parent: ${parent}" >&2
    return 2
  }
  if [[ -e "${child}" || -L "${child}" ]]; then
    [[ -d "${child}" && ! -L "${child}" &&
        "$(realpath -e -- "${child}")" == "${child}" ]] || {
      echo "Unsafe coverage directory: ${child}" >&2
      return 2
    }
  else
    mkdir -- "${child}"
    [[ ! -L "${child}" && "$(realpath -e -- "${child}")" == "${child}" ]] || {
      echo "Unsafe newly-created coverage directory: ${child}" >&2
      return 2
    }
  fi
}

ensure_child_directory "${ROOT_DIR}" out
readonly OUT_DIR="${ROOT_DIR}/out"
ensure_child_directory "${OUT_DIR}" "${SIM}"
readonly SIM_OUT_DIR="${OUT_DIR}/${SIM}"
ensure_child_directory "${SIM_OUT_DIR}" coverage-runs
readonly COVERAGE_BASE="${SIM_OUT_DIR}/coverage-runs"
readonly RUN_DIR="${COVERAGE_BASE}/${RUN_ID}"
mkdir "${RUN_DIR}" || { echo "Coverage run already exists: ${RUN_DIR}" >&2; exit 3; }
COVERAGE=1 COVERAGE_RUN_ID="${RUN_ID}" \
  "${ROOT_DIR}/scripts/run_suite.sh" positive
COVERAGE_RUN_ID="${RUN_ID}" \
  "${ROOT_DIR}/scripts/merge_coverage.sh"
