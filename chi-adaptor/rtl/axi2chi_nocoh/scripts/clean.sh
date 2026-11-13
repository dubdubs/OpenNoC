#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly TARGET="${ROOT_DIR}/out"
readonly CANONICAL_TARGET="$(realpath -m -- "${TARGET}")"
[[ "${CANONICAL_TARGET}" == "${ROOT_DIR}/out" ]] || {
  echo "Refusing to clean unexpected path: ${CANONICAL_TARGET}" >&2
  exit 2
}
if [[ "${DRY_RUN:-0}" == 1 ]]; then
  printf 'Would remove %s\n' "${CANONICAL_TARGET}"
  exit 0
fi
[[ "${DRY_RUN:-0}" == 0 ]] || { echo "DRY_RUN must be 0 or 1" >&2; exit 2; }
rm -rf -- "${CANONICAL_TARGET}"
