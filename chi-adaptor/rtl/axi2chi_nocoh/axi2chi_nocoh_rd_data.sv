// RXDAT-to-AXI read data assembly skeleton.

`default_nettype none

module axi2chi_nocoh_rd_data #(
  parameter int unsigned AxiDataWidth = 128,
  parameter int unsigned AxiIdWidth = 4,
  parameter int unsigned ChiDataWidth = 256,
  parameter int unsigned ParentEntries = 16,
  parameter int unsigned ChildEntries = 16
) (
  input logic clk,
  input logic rst,
  input logic fragment_valid_i,
  output logic fragment_ready_o,
  input logic [$clog2(ChildEntries)-1:0] fragment_child_idx_i,
  input logic [ChiDataWidth-1:0] fragment_data_i,
  input logic [ChiDataWidth / 8-1:0] fragment_be_i,
  input logic [1:0] fragment_resp_i,
  output logic rd_rsp_valid_o,
  input logic rd_rsp_ready_i,
  output logic [AxiIdWidth-1:0] rd_rsp_id_o,
  output logic [AxiDataWidth-1:0] rd_rsp_data_o,
  output logic [1:0] rd_rsp_resp_o,
  output logic rd_rsp_last_o
);

  typedef struct packed {
    logic valid;
    logic [AxiDataWidth-1:0] data;
    logic [AxiDataWidth / 8-1:0] valid_byte_mask;
    logic [AxiDataWidth / 8-1:0] error_byte_mask;
    logic [1:0] resp;
  } read_assembly_t;

  read_assembly_t assembly_q [ChildEntries];
  logic rsp_hold_valid_q;
  logic [AxiIdWidth-1:0] rsp_hold_id_q;
  logic [AxiDataWidth-1:0] rsp_hold_data_q;
  logic [1:0] rsp_hold_resp_q;
  logic rsp_hold_last_q;

  // Byte-lane extraction and AXI response assembly are deferred.

endmodule

`default_nettype wire
