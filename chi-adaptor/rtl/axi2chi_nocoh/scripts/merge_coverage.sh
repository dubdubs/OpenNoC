#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly SIM="${SIM:-uvs}"
readonly RUN_ID="${COVERAGE_RUN_ID:?COVERAGE_RUN_ID is required}"
[[ "${SIM}" =~ ^(uvs|vcs|questa)$ ]] || { echo "Unsupported SIM=${SIM}" >&2; exit 2; }
[[ "${RUN_ID}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || { echo "Unsafe coverage run id" >&2; exit 2; }
readonly RUN_DIR="${ROOT_DIR}/out/${SIM}/coverage-runs/${RUN_ID}"
readonly DB_LIST="${RUN_DIR}/databases.list"
readonly REPORT_DIR="${RUN_DIR}/report"
readonly COVERAGE_BASE="${ROOT_DIR}/out/${SIM}/coverage-runs"
[[ -d "${COVERAGE_BASE}" && ! -L "${COVERAGE_BASE}" &&
    "$(realpath -e -- "${COVERAGE_BASE}")" == "${COVERAGE_BASE}" ]] || {
  echo "Unsafe coverage base: ${COVERAGE_BASE}" >&2
  exit 2
}
[[ -d "${RUN_DIR}" && ! -L "${RUN_DIR}" &&
    "$(realpath -e -- "${RUN_DIR}")" == "${RUN_DIR}" ]] || {
  echo "Unsafe coverage run directory: ${RUN_DIR}" >&2
  exit 2
}
[[ -f "${DB_LIST}" && ! -L "${DB_LIST}" &&
    "$(realpath -e -- "${DB_LIST}")" == "${DB_LIST}" ]] || {
  echo "Unsafe coverage database list: ${DB_LIST}" >&2
  exit 2
}
[[ ! -e "${REPORT_DIR}" || (! -L "${REPORT_DIR}" && "$(realpath -e -- "${REPORT_DIR}")" == "${REPORT_DIR}") ]] || {
  echo "Unsafe coverage report directory: ${REPORT_DIR}" >&2
  exit 2
}
mapfile -t databases < "${DB_LIST}"
((${#databases[@]})) || { echo "No databases listed in ${DB_LIST}" >&2; exit 1; }
for database in "${databases[@]}"; do
  canonical_database="$(realpath -m -- "${database}")"
  case "${canonical_database}" in
    "${RUN_DIR}/databases"/*) ;;
    *) echo "Coverage database escapes immutable run directory: ${database}" >&2; exit 2 ;;
  esac
  [[ -e "${database}" ]] || { echo "Coverage database not found: ${database}" >&2; exit 1; }
done
rm -rf -- "${REPORT_DIR}"
mkdir -p "${REPORT_DIR}"
case "${SIM}" in
  vcs)
    command -v "${URG:-urg}" >/dev/null || { echo "URG not found: ${URG:-urg}" >&2; exit 127; }
    "${URG:-urg}" -dir "${databases[@]}" -dbname "${REPORT_DIR}/merged.vdb" -report "${REPORT_DIR}/html"
    ;;
  questa)
    command -v "${VCOVER:-vcover}" >/dev/null || { echo "Questa vcover not found: ${VCOVER:-vcover}" >&2; exit 127; }
    "${VCOVER:-vcover}" merge "${REPORT_DIR}/merged.ucdb" "${databases[@]}"
    "${VCOVER:-vcover}" report -html -output "${REPORT_DIR}/html" "${REPORT_DIR}/merged.ucdb"
    ;;
  uvs)
    readonly UVS="${UVS:-/home/xylan/local/uvs/bin/uvs}"
    readonly UVCOV="${UVCOV:-$(dirname "${UVS}")/uvcov}"
    [[ -x "${UVCOV}" ]] || { echo "UVS uvcov not found: ${UVCOV}" >&2; exit 127; }
    "${UVCOV}" -db "${databases[@]}" -mdb "${REPORT_DIR}/merged" -reportdir "${REPORT_DIR}/html"
    ;;
esac
