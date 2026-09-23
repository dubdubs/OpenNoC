// AXI W beat storage and CHI DAT fragment byte-lane mapping.

`default_nettype none

module axi2chi_nocoh_wr_data #(
  parameter int unsigned AxiDataWidth = 128,
  parameter int unsigned ChiDataWidth = 256,
  parameter int unsigned CacheLineBytes = 64,
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
  input logic child_bind_last_fragment_i,
  input logic [$clog2(AxiDataWidth / 8 + 1)-1:0] child_bind_axi_byte_offset_i,
  input logic [$clog2(CacheLineBytes)-1:0] child_bind_line_byte_offset_i,
  input logic [$clog2(AxiDataWidth / 8 + 1)-1:0] child_bind_fragment_byte_count_i,
  output logic txdat_fragment_valid_o,
  input logic txdat_fragment_ready_i,
  output logic [$clog2(ChildEntries)-1:0] txdat_fragment_child_idx_o,
  output logic [ChiDataWidth-1:0] txdat_fragment_data_o,
  output logic [ChiDataWidth / 8-1:0] txdat_fragment_be_o
);

  logic beat_valid_q;
  logic [$clog2(ParentEntries)-1:0] beat_parent_idx_q;
  logic [AxiDataWidth-1:0] beat_data_q;
  logic [AxiDataWidth / 8-1:0] beat_strb_q;
  logic beat_last_q;
  logic bind_valid_q;
  logic [$clog2(ChildEntries)-1:0] bind_child_idx_q;
  logic bind_last_fragment_q;
  logic [$clog2(AxiDataWidth / 8 + 1)-1:0] bind_axi_byte_offset_q;
  logic [$clog2(CacheLineBytes)-1:0] bind_line_byte_offset_q;
  logic [$clog2(AxiDataWidth / 8 + 1)-1:0] bind_fragment_byte_count_q;
  logic [ChiDataWidth-1:0] mapped_data;
  logic [ChiDataWidth / 8-1:0] mapped_be;
  logic wr_capture_fire;
  logic bind_capture_fire;
  logic fragment_fire;

  axi2chi_nocoh_wr_byte_map #(
    .AxiDataWidth(AxiDataWidth),
    .ChiDataWidth(ChiDataWidth),
    .CacheLineBytes(CacheLineBytes)
  ) wr_byte_map (
    .axi_data_i(beat_data_q),
    .axi_strb_i(beat_strb_q),
    .axi_byte_offset_i(bind_axi_byte_offset_q),
    .fragment_byte_count_i(bind_fragment_byte_count_q),
    .line_byte_offset_i(bind_line_byte_offset_q),
    .chi_data_o(mapped_data),
    .chi_be_o(mapped_be)
  );

  always_comb begin
    wr_beat_ready_o = !beat_valid_q && bind_valid_q;
    txdat_fragment_valid_o = beat_valid_q && bind_valid_q;
    txdat_fragment_child_idx_o = bind_child_idx_q;
    txdat_fragment_data_o = mapped_data;
    txdat_fragment_be_o = mapped_be;
    wr_capture_fire = wr_beat_valid_i && wr_beat_ready_o;
    bind_capture_fire = child_bind_valid_i && !bind_valid_q;
    fragment_fire = txdat_fragment_valid_o && txdat_fragment_ready_i;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      beat_valid_q <= 1'b0;
      beat_parent_idx_q <= '0;
      beat_data_q <= '0;
      beat_strb_q <= '0;
      beat_last_q <= 1'b0;
      bind_valid_q <= 1'b0;
      bind_child_idx_q <= '0;
      bind_last_fragment_q <= 1'b0;
      bind_axi_byte_offset_q <= '0;
      bind_line_byte_offset_q <= '0;
      bind_fragment_byte_count_q <= '0;
    end else begin
      if (bind_capture_fire) begin
        bind_valid_q <= 1'b1;
        bind_child_idx_q <= child_bind_idx_i;
        bind_last_fragment_q <= child_bind_last_fragment_i;
        bind_axi_byte_offset_q <= child_bind_axi_byte_offset_i;
        bind_line_byte_offset_q <= child_bind_line_byte_offset_i;
        bind_fragment_byte_count_q <= child_bind_fragment_byte_count_i;
      end

      if (wr_capture_fire) begin
        beat_valid_q <= 1'b1;
        beat_parent_idx_q <= wr_beat_parent_idx_i;
        beat_data_q <= wr_beat_data_i;
        beat_strb_q <= wr_beat_strb_i;
        beat_last_q <= wr_beat_last_i;
      end

      if (fragment_fire) begin
        bind_valid_q <= 1'b0;
        if (bind_last_fragment_q) begin
          beat_valid_q <= 1'b0;
        end
      end
    end
  end

endmodule

`default_nettype wire
