#pragma once

#include "svdpi.h"

extern "C" {
void h2s_axi_master_init(int id, int addr_width, int data_width, int awid_width,
                         int arid_width, int axlen_width, int axsize_width,
                         int user_req_width, int user_data_width, int user_resp_width);
void h2s_axi_master_init_v2(int id, int addr_width, int data_width,
                            int awid_width, int bid_width, int arid_width,
                            int rid_width, int axlen_width, int axsize_width,
                            int user_req_width, int user_data_width,
                            int user_resp_width, int cmd_fifo_depth,
                            int wbeat_fifo_depth, int rsp_fifo_depth,
                            int initial_poll_interval);
void h2s_axi_master_init_v3(int runtime_id, int id, int addr_width,
                            int data_width, int awid_width, int bid_width,
                            int arid_width, int rid_width, int axlen_width,
                            int axsize_width, int user_req_width,
                            int user_data_width, int user_resp_width,
                            int cmd_fifo_depth, int wbeat_fifo_depth,
                            int rsp_fifo_depth, int initial_poll_interval);
void h2s_axi_master_poll(int id);
void h2s_axi_master_bresp(int id, const svBitVecVal* bid, const svBitVecVal* bresp,
                          const svBitVecVal* buser);
void h2s_axi_master_rbeat(int id, const svBitVecVal* rid, const svBitVecVal* rdata,
                          const svBitVecVal* rresp, const svBitVecVal* ruser,
                          unsigned char rlast);
void h2s_axi_master_credit(int id, int write_begin_credit, int read_credit,
                           int write_beat_credit);
void h2s_axi_master_reset_notify(int id);
}
