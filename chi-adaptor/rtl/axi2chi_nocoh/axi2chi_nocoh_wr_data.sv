// AXI W-to-CHI DAT byte-lane assembly skeleton.

`default_nettype none

module axi2chi_nocoh_wr_data #(
  parameter int unsigned AxiDataWidth = 128,
  parameter int unsigned ChiDataWidth = 256,
  parameter int unsigned ParentEntries = 16,
  parameter int unsigned ChildEntries = 16
) (
  input logic clk,
  input logic rst,
  input logic wr_beat_valid_i,
  output logic wr_beat_ready_o,
  input logic [$clog2(ParentEntries)-1:0] wr_beat_parent_idx_i,
  input logic [AxiDataWidth-1:0] wr_beat_data_i,
  input logic [AxiDataWidth / 8-1:0] wr_beat_strb_i,
  input logic wr_beat_last_i,
  input logic child_bind_valid_i,
  input logic [$clog2(ChildEntries)-1:0] child_bind_idx_i,
  output logic txdat_fragment_valid_o,
  input logic txdat_fragment_ready_i,
  output logic [$clog2(ChildEntries)-1:0] txdat_fragment_child_idx_o,
  output logic [ChiDataWidth-1:0] txdat_fragment_data_o,
  output logic [ChiDataWidth / 8-1:0] txdat_fragment_be_o
);

  typedef struct packed {
    logic valid;
    logic [ChiDataWidth-1:0] data;
    logic [ChiDataWidth / 8-1:0] byte_enable;
    logic complete;
  } write_fragment_t;

  write_fragment_t fragment_q [ChildEntries];
  logic [$clog2(ParentEntries)-1:0] active_parent_q;
  logic [AxiDataWidth / 8-1:0] active_strb_q;
  logic active_wlast_q;

  // WSTRB placement, cross-line splitting, and fragment release are deferred.

endmodule

`default_nettype wire
