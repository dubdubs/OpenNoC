#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
awk -F '\t' 'BEGIN {printf "%-9s %-28s %s\n", "KIND", "TEST", "TOP"}
  !/^#/ && NF {printf "%-9s %-28s %s\n", $1, $2, $3}' "${ROOT_DIR}/tests.tsv"
