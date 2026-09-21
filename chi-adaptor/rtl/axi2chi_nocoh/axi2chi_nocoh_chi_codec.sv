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

  // CHI opcode values, field slicing, and flit packing are deferred to the
  // codec increment. In particular, no unverified WriteNoSnpFull encoding is
  // represented in this Step 3 skeleton.

endmodule

`default_nettype wire
