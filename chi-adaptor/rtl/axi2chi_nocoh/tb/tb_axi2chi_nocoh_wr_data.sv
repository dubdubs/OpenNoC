`timescale 1ns/1ps
`default_nettype none

`define CHECK(condition) \
  if (!(condition)) begin \
    $fatal(1, "CHECK failed: %s", `"condition`"); \
  end

module tb_axi2chi_nocoh_wr_data;
  localparam int unsigned AxiDataWidth = 64;
  localparam int unsigned ChiDataWidth = 128;
  localparam int unsigned ParentEntries = 4;
  localparam int unsigned ChildEntries = 4;

  logic clk = 1'b0;
  logic rst = 1'b1;
  logic wr_beat_valid_i;
  logic wr_beat_ready_o;
  logic [$clog2(ParentEntries)-1:0] wr_beat_parent_idx_i;
  logic [AxiDataWidth-1:0] wr_beat_data_i;
  logic [AxiDataWidth / 8-1:0] wr_beat_strb_i;
  logic wr_beat_last_i;
  logic child_bind_valid_i;
  logic [$clog2(ChildEntries)-1:0] child_bind_idx_i;
  logic txdat_fragment_valid_o;
  logic txdat_fragment_ready_i;
  logic [$clog2(ChildEntries)-1:0] txdat_fragment_child_idx_o;
  logic [ChiDataWidth-1:0] txdat_fragment_data_o;
  logic [ChiDataWidth / 8-1:0] txdat_fragment_be_o;

  axi2chi_nocoh_wr_data #(
    .AxiDataWidth(AxiDataWidth),
    .ChiDataWidth(ChiDataWidth),
    .ParentEntries(ParentEntries),
    .ChildEntries(ChildEntries)
  ) dut (.*);

  always #5 clk = ~clk;

  initial begin
    wr_beat_valid_i = 1'b0;
    wr_beat_parent_idx_i = '0;
    wr_beat_data_i = '0;
    wr_beat_strb_i = '0;
    wr_beat_last_i = 1'b0;
    child_bind_valid_i = 1'b0;
    child_bind_idx_i = '0;
    txdat_fragment_ready_i = 1'b0;

    @(negedge clk);
    rst = 1'b0;
    wr_beat_valid_i = 1'b1;
    wr_beat_data_i = 64'h0123_4567_89ab_cdef;
    wr_beat_strb_i = 8'hf3;
    #1;
    `CHECK(!wr_beat_ready_o);
    `CHECK(!txdat_fragment_valid_o);

    child_bind_valid_i = 1'b1;
    child_bind_idx_i = 2'd3;
    #1;
    `CHECK(wr_beat_ready_o);
    @(posedge clk);

    @(negedge clk);
    wr_beat_valid_i = 1'b0;
    child_bind_valid_i = 1'b0;
    #1;
    `CHECK(txdat_fragment_valid_o);
    `CHECK(!wr_beat_ready_o);
    `CHECK(txdat_fragment_child_idx_o == 2'd3);
    `CHECK(txdat_fragment_data_o == 128'h0000_0000_0000_0000_0123_4567_89ab_cdef);
    `CHECK(txdat_fragment_be_o == 16'h00f3);

    txdat_fragment_ready_i = 1'b1;
    @(posedge clk);
    @(negedge clk);
    txdat_fragment_ready_i = 1'b0;
    #1;
    `CHECK(!txdat_fragment_valid_o);

    $display("PASS: write data beat to TXDAT fragment");
    $finish;
  end
endmodule

`default_nettype wire

`undef CHECK
