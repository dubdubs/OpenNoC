// Parent-indexed AXI W storage and CHI DAT fragment mapping.
`default_nettype none
module axi2chi_nocoh_wr_data #(
  parameter int unsigned AxiDataWidth = 128, parameter int unsigned ChiDataWidth = 256,
  parameter int unsigned CacheLineBytes = 64, parameter int unsigned ParentEntries = 16,
  parameter int unsigned ChildEntries = 16
) (
  input logic clk, input logic rst, input logic wr_beat_valid_i,
  output logic wr_beat_ready_o,
  input logic [$clog2(ParentEntries)-1:0] wr_beat_parent_idx_i,
  input logic [AxiDataWidth-1:0] wr_beat_data_i,
  input logic [AxiDataWidth / 8-1:0] wr_beat_strb_i, input logic wr_beat_last_i,
  input logic child_bind_valid_i,
  input logic [ChildEntries-1:0] child_waiting_i,
  output logic child_bind_ready_o,
  input logic [$clog2(ParentEntries)-1:0] child_bind_parent_idx_i,
  input logic [$clog2(ChildEntries)-1:0] child_bind_idx_i,
  input logic child_bind_last_fragment_i,
  input logic [$clog2(AxiDataWidth / 8 + 1)-1:0] child_bind_axi_byte_offset_i,
  input logic [$clog2(CacheLineBytes)-1:0] child_bind_line_byte_offset_i,
  input logic [$clog2(AxiDataWidth / 8 + 1)-1:0] child_bind_fragment_byte_count_i,
  output logic txdat_fragment_valid_o, input logic txdat_fragment_ready_i,
  output logic [$clog2(ChildEntries)-1:0] txdat_fragment_child_idx_o,
  output logic [ChiDataWidth-1:0] txdat_fragment_data_o,
  output logic [ChiDataWidth / 8-1:0] txdat_fragment_be_o
);
  localparam int unsigned ParentIndexWidth = $clog2(ParentEntries);
  logic [ParentEntries-1:0] beat_valid_q, bind_valid_q;
  logic [AxiDataWidth-1:0] beat_data_q [ParentEntries];
  logic [AxiDataWidth / 8-1:0] beat_strb_q [ParentEntries];
  logic [ChildEntries-1:0] bind_child_q [ParentEntries];
  logic bind_last_q [ParentEntries];
  logic [$clog2(AxiDataWidth / 8 + 1)-1:0] bind_axi_offset_q [ParentEntries];
  logic [$clog2(CacheLineBytes)-1:0] bind_line_offset_q [ParentEntries];
  logic [$clog2(AxiDataWidth / 8 + 1)-1:0] bind_count_q [ParentEntries];
  logic selected_found; logic [ParentIndexWidth-1:0] selected_idx;
  logic [ChiDataWidth-1:0] mapped_data; logic [ChiDataWidth / 8-1:0] mapped_be;
  logic wr_capture_fire, bind_capture_fire, fragment_fire;
  axi2chi_nocoh_wr_byte_map #(.AxiDataWidth(AxiDataWidth), .ChiDataWidth(ChiDataWidth), .CacheLineBytes(CacheLineBytes)) map (
    .axi_data_i(beat_data_q[selected_idx]), .axi_strb_i(beat_strb_q[selected_idx]),
    .axi_byte_offset_i(bind_axi_offset_q[selected_idx]), .fragment_byte_count_i(bind_count_q[selected_idx]),
    .line_byte_offset_i(bind_line_offset_q[selected_idx]), .chi_data_o(mapped_data), .chi_be_o(mapped_be));
  always_comb begin
    selected_found = 1'b0; selected_idx = '0;
    for (int unsigned idx = 0; idx < ParentEntries; idx++) begin
      if (beat_valid_q[idx] && bind_valid_q[idx] &&
          child_waiting_i[bind_child_q[idx]] && !selected_found) begin
        selected_found = 1'b1; selected_idx = ParentIndexWidth'(idx);
      end
    end
    // AXI W has no transaction ID.  The slave supplies its ordered parent
    // index, so retain the beat independently of when CHI child allocation
    // supplies the matching fragment binding.
    wr_beat_ready_o = !beat_valid_q[wr_beat_parent_idx_i];
    child_bind_ready_o = !bind_valid_q[child_bind_parent_idx_i];
    txdat_fragment_valid_o = selected_found;
    txdat_fragment_child_idx_o = bind_child_q[selected_idx];
    txdat_fragment_data_o = mapped_data; txdat_fragment_be_o = mapped_be;
    wr_capture_fire = wr_beat_valid_i && wr_beat_ready_o;
    bind_capture_fire = child_bind_valid_i && child_bind_ready_o;
    fragment_fire = txdat_fragment_valid_o && txdat_fragment_ready_i;
  end
  always_ff @(posedge clk) begin
    if (rst) begin
      beat_valid_q <= '0; bind_valid_q <= '0;
      for (int unsigned idx = 0; idx < ParentEntries; idx++) begin
        beat_data_q[idx] <= '0; beat_strb_q[idx] <= '0; bind_child_q[idx] <= '0;
        bind_last_q[idx] <= 1'b0; bind_axi_offset_q[idx] <= '0;
        bind_line_offset_q[idx] <= '0; bind_count_q[idx] <= '0;
      end
    end else begin
      if (bind_capture_fire) begin
        bind_valid_q[child_bind_parent_idx_i] <= 1'b1;
        bind_child_q[child_bind_parent_idx_i] <= child_bind_idx_i;
        bind_last_q[child_bind_parent_idx_i] <= child_bind_last_fragment_i;
        bind_axi_offset_q[child_bind_parent_idx_i] <= child_bind_axi_byte_offset_i;
        bind_line_offset_q[child_bind_parent_idx_i] <= child_bind_line_byte_offset_i;
        bind_count_q[child_bind_parent_idx_i] <= child_bind_fragment_byte_count_i;
      end
      if (wr_capture_fire) begin
        beat_valid_q[wr_beat_parent_idx_i] <= 1'b1;
        beat_data_q[wr_beat_parent_idx_i] <= wr_beat_data_i;
        beat_strb_q[wr_beat_parent_idx_i] <= wr_beat_strb_i;
      end
      if (fragment_fire) begin
        bind_valid_q[selected_idx] <= 1'b0;
        if (bind_last_q[selected_idx]) beat_valid_q[selected_idx] <= 1'b0;
      end
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (!rst && child_bind_valid_i) begin
      assert (child_bind_ready_o)
      else $fatal(1, "Write child bind was offered without an available slot");
    end
  end
`endif
endmodule
`default_nettype wire
