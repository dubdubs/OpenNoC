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
  localparam int unsigned DataIdWidth = $clog2(64 / (ChiDataWidth / 8));

  logic clk = 1'b0;
  logic rst = 1'b1;
  logic fragment_valid_i;
  logic fragment_ready_o;
  logic [$clog2(ChildEntries)-1:0] fragment_child_idx_i;
  logic [$clog2(ParentEntries)-1:0] fragment_parent_idx_i;
  logic fragment_lookup_valid_i;
  logic [AxiIdWidth-1:0] fragment_axi_id_i;
  logic [7:0] fragment_axi_beat_i;
  logic [ChiDataWidth-1:0] fragment_data_i;
  logic [ChiDataWidth / 8-1:0] fragment_be_i;
  logic [DataIdWidth-1:0] fragment_dataid_i;
  logic [1:0] fragment_resp_i;
  logic fragment_last_i;
  logic fragment_last_fragment_i;
  logic [1:0] fragment_idx_i;
  logic [$clog2(AxiDataWidth / 8 + 1)-1:0] fragment_axi_byte_offset_i;
  logic [$clog2(64)-1:0] fragment_line_byte_offset_i;
  logic [$clog2(AxiDataWidth / 8 + 1)-1:0] fragment_byte_count_i;
  logic rd_rsp_parent_valid_o;
  logic [$clog2(ParentEntries)-1:0] rd_rsp_parent_idx_o;
  logic [$clog2(ChildEntries)-1:0] rd_rsp_child_idx_o;
  logic [7:0] rd_rsp_axi_beat_o;
  logic [ParentEntries-1:0] rd_rsp_retire_permit_vec_i;
  logic rd_rsp_valid_o;
  logic rd_rsp_ready_i;
  logic [AxiIdWidth-1:0] rd_rsp_id_o;
  logic [AxiDataWidth-1:0] rd_rsp_data_o;
  logic [1:0] rd_rsp_resp_o;
  logic rd_rsp_last_o;
  logic child_complete_valid_o;
  logic [$clog2(ChildEntries)-1:0] child_complete_idx_o;
  logic [1:0] child_complete_resp_o;

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
    rd_rsp_retire_permit_vec_i = '1;
    fragment_child_idx_i = '0;
    fragment_parent_idx_i = '0;
    fragment_lookup_valid_i = 1'b1;
    fragment_axi_id_i = '0;
    fragment_axi_beat_i = '0;
    fragment_data_i = '0;
    fragment_be_i = '0;
    fragment_dataid_i = '0;
    fragment_resp_i = '0;
    fragment_last_i = 1'b1;
    fragment_last_fragment_i = 1'b1;
    fragment_idx_i = '0;
    fragment_axi_byte_offset_i = '0;
    fragment_line_byte_offset_i = '0;
    fragment_byte_count_i = AxiDataWidth / 8;
    rd_rsp_ready_i = 1'b0;

    @(negedge clk);
    rst = 1'b0;
    #1;
    `CHECK(fragment_ready_o);
    `CHECK(!rd_rsp_valid_o);

    repeat (8) begin
      if (!fragment_ready_o) begin
        @(posedge clk);
        @(negedge clk);
      end
    end
    `CHECK(fragment_ready_o);
    fragment_valid_i = 1'b1;
    fragment_child_idx_i = 3'd5;
    fragment_parent_idx_i = 3'd4;
    fragment_axi_id_i = 3'd6;
    fragment_data_i = 128'hffff_eeee_dddd_cccc_0123_4567_89ab_cdef;
    fragment_be_i = 16'h00fe;
    fragment_resp_i = 2'b00;
    @(posedge clk);

    @(negedge clk);
    fragment_valid_i = 1'b0;
    repeat (4) begin
      if (!rd_rsp_valid_o) begin
        @(posedge clk);
        @(negedge clk);
      end
    end
    #1;
    `CHECK(rd_rsp_valid_o);
    `CHECK(!fragment_ready_o);
    `CHECK(rd_rsp_parent_valid_o);
    `CHECK(rd_rsp_parent_idx_o == 3'd4);
    `CHECK(rd_rsp_id_o == 3'd6);
    `CHECK(rd_rsp_data_o == 64'h0123_4567_89ab_cdef);
    `CHECK(rd_rsp_resp_o == 2'b10);
    `CHECK(rd_rsp_last_o);

    rd_rsp_ready_i = 1'b1;
    @(posedge clk);
    @(negedge clk);
    rd_rsp_ready_i = 1'b0;
    #1;
    `CHECK(!rd_rsp_valid_o);
    `CHECK(fragment_ready_o);

    fragment_valid_i = 1'b1;
    fragment_child_idx_i = 3'd0;
    fragment_parent_idx_i = 3'd2;
    fragment_axi_id_i = 3'd1;
    fragment_data_i = 128'h0000_0000_0000_0000_0000_0000_bbaa_9988;
    fragment_be_i = 16'h000e;
    fragment_resp_i = 2'b00;
    fragment_last_i = 1'b1;
    fragment_axi_byte_offset_i = '0;
    fragment_line_byte_offset_i = '0;
    fragment_byte_count_i = 4'd4;
    fragment_last_fragment_i = 1'b0;
    fragment_idx_i = '0;
    @(posedge clk);
    @(negedge clk);
    fragment_valid_i = 1'b0;
    #1;
    `CHECK(!rd_rsp_valid_o);

    while (!fragment_ready_o) begin
      @(posedge clk);
      @(negedge clk);
    end

    fragment_valid_i = 1'b1;
    fragment_child_idx_i = 3'd1;
    fragment_dataid_i = '0;
    fragment_data_i = 128'h0000_0000_0000_0000_0000_0000_ffee_ddcc;
    fragment_be_i = 16'h000f;
    fragment_axi_byte_offset_i = 4'd4;
    fragment_line_byte_offset_i = '0;
    fragment_byte_count_i = 4'd4;
    fragment_last_fragment_i = 1'b1;
    fragment_idx_i = 2'd1;
    @(posedge clk);
    @(negedge clk);
    fragment_valid_i = 1'b0;
    repeat (8) begin
      if (!rd_rsp_valid_o) begin
        @(posedge clk);
        @(negedge clk);
      end
    end
    #1;
    `CHECK(rd_rsp_valid_o && rd_rsp_parent_idx_o == 3'd2);
    `CHECK(rd_rsp_id_o == 3'd1);
    `CHECK(rd_rsp_data_o == 64'hffee_ddcc_bbaa_9988);
    `CHECK(rd_rsp_resp_o == 2'b10);
    rd_rsp_ready_i = 1'b1;
    @(posedge clk);
    @(negedge clk);
    rd_rsp_ready_i = 1'b0;

    fragment_valid_i = 1'b1;
    fragment_child_idx_i = 3'd2;
    fragment_dataid_i = '0;
    fragment_parent_idx_i = 3'd1;
    fragment_axi_id_i = 3'd3;
    fragment_data_i = 128'h0000_0000_0000_0000_0000_0000_4433_2211;
    fragment_be_i = 16'h000f;
    fragment_axi_byte_offset_i = 4'd4;
    fragment_line_byte_offset_i = '0;
    fragment_byte_count_i = 4'd4;
    fragment_resp_i = 2'b10;
    fragment_last_fragment_i = 1'b1;
    fragment_idx_i = '0;
    @(posedge clk);
    @(negedge clk);
    fragment_valid_i = 1'b0;
    #1;
    `CHECK(rd_rsp_valid_o);
    `CHECK(rd_rsp_parent_idx_o == 3'd1);
    `CHECK(rd_rsp_id_o == 3'd3);
    `CHECK(rd_rsp_data_o == 64'h4433_2211_0000_0000);
    `CHECK(rd_rsp_resp_o == 2'b10);

    $display("PASS: read data fragment to AXI R response");
    $finish;
  end
endmodule

`default_nettype wire

`undef CHECK
