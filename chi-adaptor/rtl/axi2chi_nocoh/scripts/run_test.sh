#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly MANIFEST="${ROOT_DIR}/tests.tsv"
readonly TEST_NAME="${TEST:-}"
readonly SIM="${SIM:-uvs}"
readonly SEED="${SEED:-1}"
readonly COVERAGE="${COVERAGE:-0}"
readonly RESULTS_RUN_ID="${RESULTS_RUN_ID:-$(date -u +%Y%m%dT%H%M%S)-$$}"

is_component() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ && "$1" != "." && "$1" != ".." ]]
}

is_component "${TEST_NAME}" || { echo "Unsafe or missing TEST=${TEST_NAME}" >&2; exit 2; }
is_component "${SIM}" || { echo "Unsafe SIM=${SIM}" >&2; exit 2; }
is_component "${RESULTS_RUN_ID}" || {
  echo "Unsafe RESULTS_RUN_ID=${RESULTS_RUN_ID}" >&2
  exit 2
}
[[ "${SIM}" =~ ^(uvs|vcs|questa)$ ]] || { echo "Unsupported SIM=${SIM}" >&2; exit 2; }
[[ "${SEED}" =~ ^[0-9]+$ ]] || { echo "SEED must contain decimal digits only: ${SEED}" >&2; exit 2; }
[[ "${COVERAGE}" =~ ^[01]$ ]] || { echo "COVERAGE must be 0 or 1" >&2; exit 2; }
if [[ "${COVERAGE}" == 1 ]]; then
  readonly RUN_ID="${COVERAGE_RUN_ID:?COVERAGE_RUN_ID is required for coverage}"
  is_component "${RUN_ID}" || { echo "Unsafe COVERAGE_RUN_ID=${RUN_ID}" >&2; exit 2; }
fi

mapfile -t matching_records < <(awk -F '\t' -v test="${TEST_NAME}" '$2 == test {print}' "${MANIFEST}")
if ((${#matching_records[@]} != 1)); then
  echo "TEST=${TEST_NAME} must match exactly one manifest record; found ${#matching_records[@]}" >&2
  exit 2
fi
readonly record="${matching_records[0]}"
IFS=$'\t' read -r kind name top tb_csv sentinel extra_csv <<< "${record}"
case "${kind}" in
  positive|negative) ;;
  *) echo "Invalid test kind '${kind}' for ${name}" >&2; exit 2 ;;
esac

ensure_child_directory() {
  local parent="$1"
  local name="$2"
  local child="${parent}/${name}"
  [[ -d "${parent}" && ! -L "${parent}" &&
      "$(realpath -e -- "${parent}")" == "${parent}" ]] || {
    echo "Unsafe output parent: ${parent}" >&2
    return 2
  }
  if [[ -e "${child}" || -L "${child}" ]]; then
    [[ -d "${child}" && ! -L "${child}" &&
        "$(realpath -e -- "${child}")" == "${child}" ]] || {
      echo "Unsafe output directory: ${child}" >&2
      return 2
    }
  else
    mkdir -- "${child}"
    [[ ! -L "${child}" && "$(realpath -e -- "${child}")" == "${child}" ]] || {
      echo "Unsafe newly-created output directory: ${child}" >&2
      return 2
    }
  fi
}

ensure_child_directory "${ROOT_DIR}" out
readonly OUT_BASE="${ROOT_DIR}/out"
ensure_child_directory "${OUT_BASE}" runs
readonly RUNS_BASE="${OUT_BASE}/runs"
ensure_child_directory "${RUNS_BASE}" "${RESULTS_RUN_ID}"
readonly RESULTS_RUN_DIR="${RUNS_BASE}/${RESULTS_RUN_ID}"
ensure_child_directory "${RESULTS_RUN_DIR}" "${SIM}"
readonly SIM_RESULTS_DIR="${RESULTS_RUN_DIR}/${SIM}"
ensure_child_directory "${SIM_RESULTS_DIR}" "${TEST_NAME}"
readonly TEST_RESULTS_DIR="${SIM_RESULTS_DIR}/${TEST_NAME}"
if [[ "${COVERAGE}" == 1 ]]; then
  readonly COVERAGE_BASE="${OUT_BASE}/${SIM}/coverage-runs"
  readonly COVERAGE_RUN_DIR="${COVERAGE_BASE}/${RUN_ID}"
  [[ -d "${COVERAGE_BASE}" && ! -L "${COVERAGE_BASE}" &&
      "$(realpath -e -- "${COVERAGE_BASE}")" == "${COVERAGE_BASE}" ]] || {
    echo "Unsafe coverage base: ${COVERAGE_BASE}" >&2
    exit 2
  }
  [[ -d "${COVERAGE_RUN_DIR}" && ! -L "${COVERAGE_RUN_DIR}" &&
      "$(realpath -e -- "${COVERAGE_RUN_DIR}")" == "${COVERAGE_RUN_DIR}" ]] || {
    echo "Unsafe or missing coverage run directory: ${COVERAGE_RUN_DIR}" >&2
    exit 2
  }
fi
readonly OUT_DIR="${TEST_RESULTS_DIR}/seed-${SEED}"
readonly CANONICAL_OUT="$(realpath -m -- "${OUT_DIR}")"
case "${CANONICAL_OUT}" in
  "${RESULTS_RUN_DIR}"/*) ;;
  *) echo "Output path escapes ${RESULTS_RUN_DIR}: ${CANONICAL_OUT}" >&2; exit 2 ;;
esac
if ! mkdir "${CANONICAL_OUT}" 2>/dev/null; then
  echo "Result directory already exists; refusing to overwrite: ${CANONICAL_OUT}" >&2
  exit 3
fi
readonly COMPILE_LOG="${CANONICAL_OUT}/compile.log"
readonly RUN_LOG="${CANONICAL_OUT}/run.log"
readonly GIT_COMMIT="$(cd "${ROOT_DIR}" && git rev-parse HEAD 2>/dev/null || printf 'UNKNOWN')"
readonly MANIFEST_SHA256="$(sha256sum "${MANIFEST}" | awk '{print $1}')"
printf '%s\n' "${record}" > "${CANONICAL_OUT}/manifest-record.tsv"

compile_rc=NOT_STARTED
run_rc=NOT_RUN
status_written=0
write_status() {
  local result="$1"
  printf 'result=%s\nkind=%s\nsimulator=%s\ntest=%s\ntop=%s\nseed=%s\nresults_run_id=%s\ngit_commit=%s\ntests_tsv_sha256=%s\ncompile_rc=%s\nrun_rc=%s\nsentinel=%s\n' \
    "${result}" "${kind}" "${SIM}" "${name}" "${top}" "${SEED}" \
    "${RESULTS_RUN_ID}" "${GIT_COMMIT}" "${MANIFEST_SHA256}" \
    "${compile_rc}" "${run_rc}" "${sentinel}" > "${CANONICAL_OUT}/status.txt"
  status_written=1
}
cleanup() {
  local exit_rc="$?"
  if ((status_written == 0)); then write_status FAIL; fi
  return "${exit_rc}"
}
trap cleanup EXIT

declare -a sources=()
while IFS= read -r rtl_source; do
  [[ -n "${rtl_source}" ]] && sources+=("${ROOT_DIR}/${rtl_source}")
done < "${ROOT_DIR}/files.f"
IFS=',' read -ra tb_sources <<< "${tb_csv}"
for source in "${tb_sources[@]}"; do sources+=("${ROOT_DIR}/${source}"); done
if [[ "${extra_csv}" != "-" ]]; then
  IFS=',' read -ra extra_sources <<< "${extra_csv}"
  for source in "${extra_sources[@]}"; do sources+=("${ROOT_DIR}/${source}"); done
fi

quote_command() { printf '%q ' "$@"; printf '\n'; }
declare -a compile_cmd run_cmd
coverage_database=""
case "${SIM}" in
  uvs)
    readonly UVS="${UVS:-/home/xylan/local/uvs/bin/uvs}"
    [[ -x "${UVS}" ]] || { echo "UVS executable not found: ${UVS}" >&2; exit 127; }
    compile_cmd=("${UVS}" -sv -top "${top}" -o "${CANONICAL_OUT}/simv" "${sources[@]}")
    run_cmd=("${ROOT_DIR}/scripts/run_uvs.sh" "${CANONICAL_OUT}/simv" "${SEED}")
    if [[ "${COVERAGE}" == 1 ]]; then
      coverage_database="${CANONICAL_OUT}/coverage.cdb"
      compile_cmd+=(-cov stmt,cond,tgl,fsm -covdir "${CANONICAL_OUT}/coverage")
      run_cmd+=(-cov stmt,cond,tgl,fsm -covdir "${CANONICAL_OUT}/coverage" -covtest "${name}-seed-${SEED}")
    fi
    ;;
  vcs)
    readonly VCS="${VCS:-vcs}"
    command -v "${VCS}" >/dev/null || { echo "VCS executable not found: ${VCS}" >&2; exit 127; }
    compile_cmd=("${VCS}" -full64 -sverilog -top "${top}" -o "${CANONICAL_OUT}/simv" "${sources[@]}")
    run_cmd=("${CANONICAL_OUT}/simv" "+ntb_random_seed=${SEED}")
    if [[ "${COVERAGE}" == 1 ]]; then
      coverage_database="${CANONICAL_OUT}/coverage.vdb"
      compile_cmd+=(-cm line+cond+tgl+fsm -cm_dir "${coverage_database}")
      run_cmd+=(-cm line+cond+tgl+fsm -cm_dir "${coverage_database}")
    fi
    ;;
  questa)
    readonly VLIB="${VLIB:-vlib}"
    readonly VLOG="${VLOG:-vlog}"
    readonly VSIM="${VSIM:-vsim}"
    command -v "${VLIB}" >/dev/null || { echo "Questa vlib not found: ${VLIB}" >&2; exit 127; }
    command -v "${VLOG}" >/dev/null || { echo "Questa vlog not found: ${VLOG}" >&2; exit 127; }
    command -v "${VSIM}" >/dev/null || { echo "Questa vsim not found: ${VSIM}" >&2; exit 127; }
    "${VLIB}" "${CANONICAL_OUT}/work" > "${CANONICAL_OUT}/vlib.log" 2>&1
    compile_cmd=("${VLOG}" -sv -work "${CANONICAL_OUT}/work" "${sources[@]}")
    run_cmd=("${VSIM}" -c -lib "${CANONICAL_OUT}/work" "${top}" -sv_seed "${SEED}" -do 'run -all; quit -code [coverage attribute -name TESTSTATUS -concise]')
    if [[ "${COVERAGE}" == 1 ]]; then
      coverage_database="${CANONICAL_OUT}/coverage.ucdb"
      compile_cmd+=(+cover=bcesft)
      run_cmd=("${VSIM}" -coverage -c -lib "${CANONICAL_OUT}/work" "${top}" -sv_seed "${SEED}" -do "coverage save -onexit ${coverage_database}; run -all; quit -code [coverage attribute -name TESTSTATUS -concise]")
    fi
    ;;
esac

quote_command "${compile_cmd[@]}" > "${CANONICAL_OUT}/compile.cmd"
set +e
(cd "${CANONICAL_OUT}" && "${compile_cmd[@]}") > "${COMPILE_LOG}" 2>&1
compile_rc=$?
set -e
if ((compile_rc != 0)); then
  write_status FAIL
  echo "FAIL ${name}: compilation failed (see ${COMPILE_LOG})" >&2
  exit 1
fi

quote_command "${run_cmd[@]}" > "${CANONICAL_OUT}/run.cmd"
set +e
(cd "${CANONICAL_OUT}" && "${run_cmd[@]}") > "${RUN_LOG}" 2>&1
run_rc=$?
set -e
passed=0
case "${kind}" in
  positive)
    if ((run_rc == 0)) && grep -Fq -- "${sentinel}" "${RUN_LOG}"; then passed=1; fi
    ;;
  negative)
    if ((run_rc != 0)) && grep -Fq -- "${sentinel}" "${RUN_LOG}"; then passed=1; fi
    ;;
esac
if ((passed == 0)); then
  write_status FAIL
  echo "FAIL ${name}: exit/sentinel policy not satisfied (see ${RUN_LOG})" >&2
  exit 1
fi
if [[ "${COVERAGE}" == 1 ]]; then
  readonly DB_LIST="${COVERAGE_RUN_DIR}/databases.list"
  readonly DATABASES_DIR="${COVERAGE_RUN_DIR}/databases"
  readonly IMMUTABLE_DB_DIR="${DATABASES_DIR}/${TEST_NAME}"
  readonly IMMUTABLE_DATABASE="${IMMUTABLE_DB_DIR}/$(basename "${coverage_database}")"
  [[ -e "${coverage_database}" ]] || { echo "Coverage database missing: ${coverage_database}" >&2; exit 1; }
  [[ ! -e "${DB_LIST}" || (! -L "${DB_LIST}" && "$(realpath -e -- "${DB_LIST}")" == "${DB_LIST}") ]] || {
    echo "Unsafe coverage database list: ${DB_LIST}" >&2
    exit 2
  }
  mkdir -p "${DATABASES_DIR}"
  [[ ! -L "${DATABASES_DIR}" && "$(realpath -e -- "${DATABASES_DIR}")" == "${DATABASES_DIR}" ]] || {
    echo "Unsafe coverage databases directory: ${DATABASES_DIR}" >&2
    exit 2
  }
  mkdir -p "${IMMUTABLE_DB_DIR}"
  [[ ! -L "${IMMUTABLE_DB_DIR}" && "$(realpath -e -- "${IMMUTABLE_DB_DIR}")" == "${IMMUTABLE_DB_DIR}" ]] || {
    echo "Unsafe test coverage directory: ${IMMUTABLE_DB_DIR}" >&2
    exit 2
  }
  [[ ! -e "${IMMUTABLE_DATABASE}" ]] || {
    echo "Coverage database already exists for run ${RUN_ID}, test ${TEST_NAME}" >&2
    exit 3
  }
  mv -- "${coverage_database}" "${IMMUTABLE_DATABASE}"
  printf '%s\n' "${IMMUTABLE_DATABASE}" >> "${DB_LIST}"
fi
write_status PASS
if [[ "${kind}" == negative ]]; then
  echo "PASS ${name} (expected failure rc=${run_rc})"
else
  echo "PASS ${name}"
fi
