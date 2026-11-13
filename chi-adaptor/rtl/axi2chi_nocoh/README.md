# AXI-to-CHI non-coherent regression

`files.f` is deliberately RTL-only. `tests.tsv` is the single machine-readable
test inventory: it defines all 32 verified positive and four negative tops,
testbench sources, wrapper dependencies, and expected messages. RV-BOSC tests
remain excluded until their integration regression passes.

## Commands

Run commands from this directory:

```sh
make list
make test TEST=fragment
make regression
make negative
make coverage
make clean
```

The default `SIM=uvs` uses `/home/xylan/local/uvs/bin/uvs`. Select another
backend with `SIM=vcs` or `SIM=questa`. `SEED=1` controls the seed. Executable
overrides are `UVS`, `UVCOV`, `VCS`, `VLIB`, `VLOG`, `VSIM`, `URG`, and `VCOVER`.
Missing tools produce an explicit diagnostic. UVS coverage uses the verified
UVS 2025.12 `-cov`, `-covdir`, and `-covtest` interface and `uvcov`; VCS uses a
per-test VDB plus `urg`; Questa uses a per-test UCDB plus `vcover`.
UVS 2025.12 reports `$fatal` but returns process status zero, so the checked-in
runtime shim normalizes a UVS `[FATAL]` record to status 1 before evaluation.

Every invocation belongs to an immutable result run. Set `RESULTS_RUN_ID`
explicitly when multiple suite commands must share one run; otherwise each
suite or direct test command generates one automatically:

```text
out/runs/<results-run-id>/<sim>/<test>/seed-<seed>/
  compile.cmd  compile.log  run.cmd  run.log  status.txt
  manifest-record.tsv
```

`RESULTS_RUN_ID`, `SIM`, `TEST`, and `SEED` are validated before a result
directory is created. An existing result tuple is never deleted or replaced;
reuse is rejected. `status.txt` records the run ID, Git commit, and
`tests.tsv` SHA-256, while `manifest-record.tsv` preserves the exact sentinel
and source record used by that run. An exit trap writes `FAIL` status for
interrupted or early-failing runs.

A positive test passes only when simulation exits zero and its test-specific
`PASS:` line is present. A negative test passes only after successful compile,
non-zero simulation exit, and its expected parameter-fatal text. Thus syntax,
compile, and unrelated runtime errors cannot be mistaken for expected failures.

Each `make coverage` creates a run ID and an explicit `databases.list`; merging
uses only databases produced by that invocation, never a scan of historical
output. Before releasing each tuple lock, its database is moved into the
immutable `coverage-runs/<run-id>/databases/<test>/` tree. Database-list paths
are derived internally and cannot be supplied by the caller. Reports are under
`out/<sim>/coverage-runs/<run-id>/report/`. CI should archive the complete
`out/` tree on both success and failure; `status.txt` is a small key/value
summary suitable for machine parsing, while command and log files retain exact
reproduction evidence.
