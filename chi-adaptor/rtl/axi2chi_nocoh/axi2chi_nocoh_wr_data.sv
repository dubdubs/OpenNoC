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
  logic hold_valid_q;
  logic [$clog2(ChildEntries)-1:0] hold_child_idx_q;
  logic [ChiDataWidth-1:0] hold_data_q;
  logic [ChiDataWidth / 8-1:0] hold_be_q;
  logic bind_valid_q;
  logic [$clog2(ChildEntries)-1:0] bind_child_idx_q;
  logic wr_capture_fire;
  logic fragment_fire;

  always_comb begin
    wr_beat_ready_o = !hold_valid_q && (bind_valid_q || child_bind_valid_i);
    txdat_fragment_valid_o = hold_valid_q;
    txdat_fragment_child_idx_o = hold_child_idx_q;
    txdat_fragment_data_o = hold_data_q;
    txdat_fragment_be_o = hold_be_q;
    wr_capture_fire = wr_beat_valid_i && wr_beat_ready_o;
    fragment_fire = txdat_fragment_valid_o && txdat_fragment_ready_i;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      active_parent_q <= '0;
      active_strb_q <= '0;
      active_wlast_q <= 1'b0;
      hold_valid_q <= 1'b0;
      hold_child_idx_q <= '0;
      hold_data_q <= '0;
      hold_be_q <= '0;
      bind_valid_q <= 1'b0;
      bind_child_idx_q <= '0;
      for (int unsigned idx = 0; idx < ChildEntries; idx++) begin
        fragment_q[idx] <= '0;
      end
    end else begin
      if (wr_capture_fire) begin
        active_parent_q <= wr_beat_parent_idx_i;
        active_strb_q <= wr_beat_strb_i;
        active_wlast_q <= wr_beat_last_i;
        hold_valid_q <= 1'b1;
        hold_child_idx_q <= bind_valid_q ? bind_child_idx_q : child_bind_idx_i;
        hold_data_q <= {{(ChiDataWidth - AxiDataWidth) {1'b0}}, wr_beat_data_i};
        hold_be_q <= {{((ChiDataWidth / 8) - (AxiDataWidth / 8)) {1'b0}},
            wr_beat_strb_i};
        bind_valid_q <= 1'b0;
      end else if (fragment_fire) begin
        hold_valid_q <= 1'b0;
      end

      if (child_bind_valid_i && !wr_capture_fire) begin
        bind_valid_q <= 1'b1;
        bind_child_idx_q <= child_bind_idx_i;
      end
    end
  end

endmodule

`default_nettype wire
