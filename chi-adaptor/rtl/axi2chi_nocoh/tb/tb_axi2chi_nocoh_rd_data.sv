`timescale 1ns/1ps
`default_nettype none

`define CHECK(condition) \
  if (!(condition)) begin \
    $fatal(1, "CHECK failed: %s", `"condition`"); \
  end

module tb_axi2chi_nocoh_rd_data;
  localparam int unsigned AxiDataWidth = 64;
  localparam int unsigned AxiIdWidth = 3;
  localparam int unsigned ChiDataWidth = 128;
  localparam int unsigned ParentEntries = 8;
  localparam int unsigned ChildEntries = 8;

  logic clk = 1'b0;
  logic rst = 1'b1;
  logic fragment_valid_i;
  logic fragment_ready_o;
  logic [$clog2(ChildEntries)-1:0] fragment_child_idx_i;
  logic [$clog2(ParentEntries)-1:0] fragment_parent_idx_i;
  logic fragment_lookup_valid_i;
  logic [AxiIdWidth-1:0] fragment_axi_id_i;
  logic [ChiDataWidth-1:0] fragment_data_i;
  logic [ChiDataWidth / 8-1:0] fragment_be_i;
  logic [1:0] fragment_resp_i;
  logic fragment_last_i;
  logic rd_rsp_parent_valid_o;
  logic [$clog2(ParentEntries)-1:0] rd_rsp_parent_idx_o;
  logic rd_rsp_valid_o;
  logic rd_rsp_ready_i;
  logic [AxiIdWidth-1:0] rd_rsp_id_o;
  logic [AxiDataWidth-1:0] rd_rsp_data_o;
  logic [1:0] rd_rsp_resp_o;
  logic rd_rsp_last_o;

  axi2chi_nocoh_rd_data #(
    .AxiDataWidth(AxiDataWidth),
    .AxiIdWidth(AxiIdWidth),
    .ChiDataWidth(ChiDataWidth),
    .ParentEntries(ParentEntries),
    .ChildEntries(ChildEntries)
  ) dut (.*);

  always #5 clk = ~clk;

  initial begin
    fragment_valid_i = 1'b0;
    fragment_child_idx_i = '0;
    fragment_parent_idx_i = '0;
    fragment_lookup_valid_i = 1'b1;
    fragment_axi_id_i = '0;
    fragment_data_i = '0;
    fragment_be_i = '0;
    fragment_resp_i = '0;
    fragment_last_i = 1'b1;
    rd_rsp_ready_i = 1'b0;

    @(negedge clk);
    rst = 1'b0;
    #1;
    `CHECK(fragment_ready_o);
    `CHECK(!rd_rsp_valid_o);

    fragment_valid_i = 1'b1;
    fragment_child_idx_i = 3'd5;
    fragment_parent_idx_i = 3'd4;
    fragment_axi_id_i = 3'd6;
    fragment_data_i = 128'hffff_eeee_dddd_cccc_0123_4567_89ab_cdef;
    fragment_be_i = 16'h00ff;
    fragment_resp_i = 2'b00;
    @(posedge clk);

    @(negedge clk);
    fragment_valid_i = 1'b0;
    #1;
    `CHECK(rd_rsp_valid_o);
    `CHECK(!fragment_ready_o);
    `CHECK(rd_rsp_parent_valid_o);
    `CHECK(rd_rsp_parent_idx_o == 3'd4);
    `CHECK(rd_rsp_id_o == 3'd6);
    `CHECK(rd_rsp_data_o == 64'h0123_4567_89ab_cdef);
    `CHECK(rd_rsp_resp_o == 2'b00);
    `CHECK(rd_rsp_last_o);

    rd_rsp_ready_i = 1'b1;
    @(posedge clk);
    @(negedge clk);
    rd_rsp_ready_i = 1'b0;
    #1;
    `CHECK(!rd_rsp_valid_o);
    `CHECK(fragment_ready_o);

    fragment_valid_i = 1'b1;
    fragment_child_idx_i = 3'd2;
    fragment_parent_idx_i = 3'd1;
    fragment_axi_id_i = 3'd3;
    fragment_data_i = 128'h0;
    fragment_resp_i = 2'b10;
    @(posedge clk);
    @(negedge clk);
    fragment_valid_i = 1'b0;
    #1;
    `CHECK(rd_rsp_valid_o);
    `CHECK(rd_rsp_parent_idx_o == 3'd1);
    `CHECK(rd_rsp_id_o == 3'd3);
    `CHECK(rd_rsp_resp_o == 2'b10);

    $display("PASS: read data fragment to AXI R response");
    $finish;
  end
endmodule

`default_nettype wire

`undef CHECK
