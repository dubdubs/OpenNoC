// Profile-specific canonical CHI codec skeleton.

`default_nettype none

module axi2chi_nocoh_chi_codec #(
  parameter int unsigned ChiNidWidth = 7,
  parameter int unsigned ChiTxnidWidth = 12,
  parameter int unsigned ChiDbidWidth = 12,
  parameter int unsigned ChiDataWidth = 256,
  parameter int unsigned ReqFlitWidth = 131,
  parameter int unsigned RspFlitWidth = 73,
  parameter int unsigned DatFlitWidth = 406
) (
  input logic read_req_valid_i,
  input logic [ChiNidWidth-1:0] read_target_id_i,
  input logic [ChiTxnidWidth-1:0] read_txnid_i,
  input logic [43:0] read_addr_i,
  input logic [2:0] read_size_i,
  output logic [ReqFlitWidth-1:0] read_req_flit_o,
  input logic write_req_valid_i,
  input logic write_req_full_i,
  input logic [ChiNidWidth-1:0] write_target_id_i,
  input logic [ChiTxnidWidth-1:0] write_txnid_i,
  input logic [43:0] write_addr_i,
  input logic [2:0] write_size_i,
  output logic [ReqFlitWidth-1:0] write_req_flit_o,
  input logic [RspFlitWidth-1:0] rxrsp_flit_i,
  output logic [ChiTxnidWidth-1:0] rxrsp_txnid_o,
  output logic [ChiDbidWidth-1:0] rxrsp_dbid_o,
  output logic [1:0] rxrsp_resp_err_o,
  output logic rxrsp_is_dbidresp_o,
  output logic rxrsp_is_compdbidresp_o,
  output logic rxrsp_is_comp_o,
  input logic [DatFlitWidth-1:0] rxdat_flit_i,
  output logic [ChiTxnidWidth-1:0] rxdat_txnid_o,
  output logic [1:0] rxdat_dataid_o,
  output logic [1:0] rxdat_resp_err_o,
  output logic [ChiDataWidth-1:0] rxdat_data_o,
  output logic [ChiDataWidth / 8-1:0] rxdat_be_o,
  input logic [ChiTxnidWidth-1:0] txdat_txnid_i,
  input logic [ChiDbidWidth-1:0] txdat_dbid_i,
  input logic [1:0] txdat_dataid_i,
  input logic [ChiDataWidth-1:0] txdat_data_i,
  input logic [ChiDataWidth / 8-1:0] txdat_be_i,
  output logic [DatFlitWidth-1:0] txdat_flit_o
);

  localparam logic [6:0] kReqOpcodeReadNoSnp = 7'h04;
  localparam logic [6:0] kReqOpcodeWriteNoSnpPtl = 7'h18;
  localparam logic [6:0] kReqOpcodeWriteNoSnpFull = 7'h19;
  localparam logic [3:0] kRspOpcodeDbidResp = 4'h1;
  localparam logic [3:0] kRspOpcodeCompDbidResp = 4'h2;
  localparam logic [3:0] kRspOpcodeComp = 4'h3;

  always_comb begin
    read_req_flit_o = '0;
    read_req_flit_o[6:0] = kReqOpcodeReadNoSnp;
    read_req_flit_o[8 +: ChiNidWidth] = read_target_id_i;
    read_req_flit_o[16 +: ChiTxnidWidth] = read_txnid_i;
    read_req_flit_o[32 +: 44] = read_addr_i;
    read_req_flit_o[76 +: 3] = read_size_i;
    read_req_flit_o[ReqFlitWidth-1] = read_req_valid_i;

    write_req_flit_o = '0;
    write_req_flit_o[6:0] =
        write_req_full_i ? kReqOpcodeWriteNoSnpFull : kReqOpcodeWriteNoSnpPtl;
    write_req_flit_o[8 +: ChiNidWidth] = write_target_id_i;
    write_req_flit_o[16 +: ChiTxnidWidth] = write_txnid_i;
    write_req_flit_o[32 +: 44] = write_addr_i;
    write_req_flit_o[76 +: 3] = write_size_i;
    write_req_flit_o[ReqFlitWidth-1] = write_req_valid_i;

    rxrsp_txnid_o = rxrsp_flit_i[8 +: ChiTxnidWidth];
    rxrsp_dbid_o = rxrsp_flit_i[24 +: ChiDbidWidth];
    rxrsp_resp_err_o = rxrsp_flit_i[36 +: 2];
    rxrsp_is_dbidresp_o = rxrsp_flit_i[3:0] == kRspOpcodeDbidResp;
    rxrsp_is_compdbidresp_o = rxrsp_flit_i[3:0] == kRspOpcodeCompDbidResp;
    rxrsp_is_comp_o = rxrsp_flit_i[3:0] == kRspOpcodeComp ||
        rxrsp_is_compdbidresp_o;

    rxdat_txnid_o = rxdat_flit_i[8 +: ChiTxnidWidth];
    rxdat_dataid_o = rxdat_flit_i[24 +: 2];
    rxdat_resp_err_o = rxdat_flit_i[26 +: 2];
    rxdat_be_o = rxdat_flit_i[32 +: (ChiDataWidth / 8)];
    rxdat_data_o = rxdat_flit_i[64 +: ChiDataWidth];

    txdat_flit_o = '0;
    txdat_flit_o[8 +: ChiTxnidWidth] = txdat_txnid_i;
    txdat_flit_o[24 +: ChiDbidWidth] = txdat_dbid_i;
    txdat_flit_o[36 +: 2] = txdat_dataid_i;
    txdat_flit_o[64 +: (ChiDataWidth / 8)] = txdat_be_i;
    txdat_flit_o[128 +: ChiDataWidth] = txdat_data_i;
  end

endmodule

`default_nettype wire
