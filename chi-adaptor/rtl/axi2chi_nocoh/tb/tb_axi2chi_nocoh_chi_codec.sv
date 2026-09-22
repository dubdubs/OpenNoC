`timescale 1ns/1ps
`default_nettype none

`define CHECK(condition) \
  if (!(condition)) begin \
    $fatal(1, "CHECK failed: %s", `"condition`"); \
  end

module tb_axi2chi_nocoh_chi_codec;
  localparam int unsigned ChiNidWidth = 7;
  localparam int unsigned ChiTxnidWidth = 8;
  localparam int unsigned ChiDbidWidth = 8;
  localparam int unsigned ChiDataWidth = 64;
  localparam int unsigned ReqFlitWidth = 96;
  localparam int unsigned RspFlitWidth = 64;
  localparam int unsigned DatFlitWidth = 256;

  logic read_req_valid_i;
  logic [ChiNidWidth-1:0] read_target_id_i;
  logic [ChiTxnidWidth-1:0] read_txnid_i;
  logic [43:0] read_addr_i;
  logic [2:0] read_size_i;
  logic [ReqFlitWidth-1:0] read_req_flit_o;
  logic write_req_valid_i;
  logic write_req_full_i;
  logic [ChiNidWidth-1:0] write_target_id_i;
  logic [ChiTxnidWidth-1:0] write_txnid_i;
  logic [43:0] write_addr_i;
  logic [2:0] write_size_i;
  logic [ReqFlitWidth-1:0] write_req_flit_o;
  logic [RspFlitWidth-1:0] rxrsp_flit_i;
  logic [ChiTxnidWidth-1:0] rxrsp_txnid_o;
  logic [ChiDbidWidth-1:0] rxrsp_dbid_o;
  logic [1:0] rxrsp_resp_err_o;
  logic rxrsp_is_dbidresp_o;
  logic rxrsp_is_compdbidresp_o;
  logic rxrsp_is_comp_o;
  logic [DatFlitWidth-1:0] rxdat_flit_i;
  logic [ChiTxnidWidth-1:0] rxdat_txnid_o;
  logic [1:0] rxdat_dataid_o;
  logic [1:0] rxdat_resp_err_o;
  logic [ChiDataWidth-1:0] rxdat_data_o;
  logic [ChiDataWidth / 8-1:0] rxdat_be_o;
  logic [ChiTxnidWidth-1:0] txdat_txnid_i;
  logic [ChiDbidWidth-1:0] txdat_dbid_i;
  logic [1:0] txdat_dataid_i;
  logic [ChiDataWidth-1:0] txdat_data_i;
  logic [ChiDataWidth / 8-1:0] txdat_be_i;
  logic [DatFlitWidth-1:0] txdat_flit_o;

  axi2chi_nocoh_chi_codec #(
    .ChiNidWidth(ChiNidWidth),
    .ChiTxnidWidth(ChiTxnidWidth),
    .ChiDbidWidth(ChiDbidWidth),
    .ChiDataWidth(ChiDataWidth),
    .ReqFlitWidth(ReqFlitWidth),
    .RspFlitWidth(RspFlitWidth),
    .DatFlitWidth(DatFlitWidth)
  ) dut (.*);

  initial begin
    read_req_valid_i = 1'b1;
    read_target_id_i = 7'h55;
    read_txnid_i = 8'ha1;
    read_addr_i = 44'h123_4567_89ab;
    read_size_i = 3'd4;
    write_req_valid_i = 1'b1;
    write_req_full_i = 1'b0;
    write_target_id_i = 7'h2a;
    write_txnid_i = 8'hb2;
    write_addr_i = 44'h321_7654_ba98;
    write_size_i = 3'd5;
    rxrsp_flit_i = '0;
    rxdat_flit_i = '0;
    txdat_txnid_i = 8'hc3;
    txdat_dbid_i = 8'hd4;
    txdat_dataid_i = 2'd2;
    txdat_data_i = 64'h0123_4567_89ab_cdef;
    txdat_be_i = 8'hf0;

    #1;
    `CHECK(read_req_flit_o[6:0] == 7'h04);
    `CHECK(read_req_flit_o[8 +: ChiNidWidth] == 7'h55);
    `CHECK(read_req_flit_o[16 +: ChiTxnidWidth] == 8'ha1);
    `CHECK(read_req_flit_o[32 +: 44] == 44'h123_4567_89ab);
    `CHECK(read_req_flit_o[76 +: 3] == 3'd4);
    `CHECK(read_req_flit_o[ReqFlitWidth-1]);

    `CHECK(write_req_flit_o[6:0] == 7'h18);
    `CHECK(write_req_flit_o[8 +: ChiNidWidth] == 7'h2a);
    `CHECK(write_req_flit_o[16 +: ChiTxnidWidth] == 8'hb2);
    `CHECK(write_req_flit_o[32 +: 44] == 44'h321_7654_ba98);
    write_req_full_i = 1'b1;
    #1;
    `CHECK(write_req_flit_o[6:0] == 7'h19);

    rxrsp_flit_i[3:0] = 4'h2;
    rxrsp_flit_i[8 +: ChiTxnidWidth] = 8'he5;
    rxrsp_flit_i[24 +: ChiDbidWidth] = 8'hf6;
    rxrsp_flit_i[36 +: 2] = 2'b10;
    #1;
    `CHECK(rxrsp_is_compdbidresp_o);
    `CHECK(rxrsp_is_comp_o);
    `CHECK(!rxrsp_is_dbidresp_o);
    `CHECK(rxrsp_txnid_o == 8'he5);
    `CHECK(rxrsp_dbid_o == 8'hf6);
    `CHECK(rxrsp_resp_err_o == 2'b10);

    rxdat_flit_i[8 +: ChiTxnidWidth] = 8'h11;
    rxdat_flit_i[24 +: 2] = 2'd1;
    rxdat_flit_i[26 +: 2] = 2'b01;
    rxdat_flit_i[32 +: 8] = 8'h3c;
    rxdat_flit_i[64 +: ChiDataWidth] = 64'hfeed_face_cafe_beef;
    #1;
    `CHECK(rxdat_txnid_o == 8'h11);
    `CHECK(rxdat_dataid_o == 2'd1);
    `CHECK(rxdat_resp_err_o == 2'b01);
    `CHECK(rxdat_be_o == 8'h3c);
    `CHECK(rxdat_data_o == 64'hfeed_face_cafe_beef);

    `CHECK(txdat_flit_o[8 +: ChiTxnidWidth] == 8'hc3);
    `CHECK(txdat_flit_o[24 +: ChiDbidWidth] == 8'hd4);
    `CHECK(txdat_flit_o[36 +: 2] == 2'd2);
    `CHECK(txdat_flit_o[64 +: 8] == 8'hf0);
    `CHECK(txdat_flit_o[128 +: ChiDataWidth] == 64'h0123_4567_89ab_cdef);

    $display("PASS: CHI codec field packing and unpacking");
    $finish;
  end
endmodule

`default_nettype wire

`undef CHECK
