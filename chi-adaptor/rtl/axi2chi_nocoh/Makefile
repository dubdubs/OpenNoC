SHELL := /bin/bash
.DEFAULT_GOAL := list

SIM ?= uvs
SEED ?= 1
TEST ?=
RESULTS_RUN_ID ?=
export SIM SEED TEST RESULTS_RUN_ID

.PHONY: list test regression negative coverage clean
list:
	@./scripts/list_tests.sh

test:
	@./scripts/run_test.sh

regression:
	@./scripts/run_suite.sh positive

negative:
	@./scripts/run_suite.sh negative

coverage:
	@./scripts/run_coverage.sh

clean:
	@./scripts/clean.sh
