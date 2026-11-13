#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly KIND="${1:?suite kind is required}"
readonly RESULTS_RUN_ID="${RESULTS_RUN_ID:-$(date -u +%Y%m%dT%H%M%S)-$$}"
[[ "${RESULTS_RUN_ID}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ &&
    "${RESULTS_RUN_ID}" != "." && "${RESULTS_RUN_ID}" != ".." ]] || {
  echo "Unsafe RESULTS_RUN_ID=${RESULTS_RUN_ID}" >&2
  exit 2
}
export RESULTS_RUN_ID

status=0
while IFS=$'\t' read -r kind name _; do
  [[ "${kind}" == "${KIND}" ]] || continue
  if ! TEST="${name}" "${ROOT_DIR}/scripts/run_test.sh"; then status=1; fi
done < <(grep -v '^#' "${ROOT_DIR}/tests.tsv")
exit "${status}"
