# chi_rni build/test with UVS.
UVS ?= /home/xylan/local/uvs/bin/uvs
SRC_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

.PHONY: seg core shim lint clean

# Segmenter unit test (Scheme 6.4 example: 0x38/len7/size4 -> 8/64/32/16/8)
seg:
	cd $(SRC_DIR) && $(UVS) -sv -debug -f files_seg.f \
		-top tb_chi_rni_segburst -o simv_seg -logfile uvs_seg_compile.log
	cd $(SRC_DIR) && ./simv_seg -logfile uvs_seg_run.log

# Core smoke test (aligned read + aligned write)
core:
	cd $(SRC_DIR) && $(UVS) -sv -debug -f files_core.f \
		-top tb_chi_rni_core -o simv_core -logfile uvs_core_compile.log
	cd $(SRC_DIR) && ./simv_core -logfile uvs_core_run.log

# OpenNoC raw-flit/profile boundary.  The shim has no standalone traffic
# generator; compile it as a syntax/elaboration check.
shim:
	cd $(SRC_DIR) && $(UVS) -sv +incdir+$(SRC_DIR) -f files_shim.f \
		-top chi_rni_opennoc_profile_shim -o simv_shim \
		-logfile uvs_shim_compile.log


clean:
	rm -rf $(SRC_DIR)simv_seg* $(SRC_DIR)simv_core* $(SRC_DIR)simv_shim* $(SRC_DIR)uvs_*.log \
	       $(SRC_DIR)uvs_seg.db $(SRC_DIR)uvs_core.db
