#!/usr/bin/env bash
set -euo pipefail

readonly EXECUTABLE="${1:?UVS simulation executable is required}"
readonly SEED="${2:?seed is required}"
shift 2
readonly CAPTURE="$(mktemp)"
trap 'rm -f -- "${CAPTURE}"' EXIT

set +e
"${EXECUTABLE}" -fixed_seed "${SEED}" "$@" 2>&1 | tee "${CAPTURE}"
simulator_rc="${PIPESTATUS[0]}"
set -e
if ((simulator_rc != 0)); then
  exit "${simulator_rc}"
fi
# UVS 2025.12 returns zero after SystemVerilog $fatal. Normalize that runtime
# behavior to the conventional non-zero process status used by all backends.
if grep -Fq '* [FATAL]' "${CAPTURE}"; then
  exit 1
fi
