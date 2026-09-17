UVS ?= /home/xylan/local/uvs/bin/uvs
RTL_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
UVS_ROOT ?= $(RTL_DIR)/uvs_dir
TEST_NAME ?= hnf
TOP_TB ?= tb_hnf
RUN_DIR ?= $(UVS_ROOT)/$(TEST_NAME)
FILE_LIST_TB := $(RUN_DIR)/file_list_tb.f
SIMV ?= uvsim
SIM_LOG ?= uvs_run.log
UVS_OPTS ?= -sv +incdir+$(RTL_DIR)/include+$(RTL_DIR)/misc+$(RTL_DIR)/src+$(RTL_DIR)/tb -usdbon

.PHONY: all prepare com sim run_hnf run_rni run_snf run_hni run_all clean

all: com sim

prepare:
	@mkdir -p "$(RUN_DIR)"
	@sed 's|^\./|$(RTL_DIR)/|' "$(RTL_DIR)/file_list_tb.f" > "$(FILE_LIST_TB)"
	@if [ "$(TEST_NAME)" = "hnf" ] && [ ! -e "$(RUN_DIR)/case" ]; then \
		ln -s "$(RTL_DIR)/case" "$(RUN_DIR)/case"; \
	fi

com: prepare
	cd "$(RUN_DIR)" && $(UVS) $(UVS_OPTS) -f "$(notdir $(FILE_LIST_TB))" -top $(TOP_TB) -o $(SIMV)

sim: prepare
	cd "$(RUN_DIR)" && ./$(SIMV) -logfile $(SIM_LOG) -usdb=all

run_hnf:
	$(MAKE) TEST_NAME=hnf TOP_TB=tb_hnf SIMV=uvsim_hnf SIM_LOG=uvs_hnf_run.log all

run_rni:
	$(MAKE) TEST_NAME=rni TOP_TB=tb_rni SIMV=uvsim_rni SIM_LOG=uvs_rni_run.log all

run_snf:
	$(MAKE) TEST_NAME=snf TOP_TB=tb_snf_top SIMV=uvsim_snf SIM_LOG=uvs_snf_run.log all

run_hni:
	$(MAKE) TEST_NAME=hni TOP_TB=tb_hni_top SIMV=uvsim_hni SIM_LOG=uvs_hni_run.log all

run_all: run_hnf run_rni run_snf run_hni

clean:
	$(RM) -rf "$(UVS_ROOT)"
