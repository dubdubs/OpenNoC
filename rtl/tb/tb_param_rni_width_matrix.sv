`timescale 1ns/1ps

// Elaborates every AXI4-full width and every supported CHI DAT width through
// the Scheme-1 Gate-0 contract.  This is deliberately a static test: a width
// is not advertised as data-plane verified until a matching traffic test is
// added for rni_wr_buffer/rni_rd_buffer.
module tb_param_rni_width_case #(
  parameter integer AXI_WIDTH = 128,
  parameter integer CHI_WIDTH = 256
) (
  input wire clk,
  input wire rst
);
  rni_scheme1_static_assert #(
    .AXI_DATA_WIDTH(AXI_WIDTH),
    .CHI_DATA_WIDTH(CHI_WIDTH),
    .CHI_BE_WIDTH(CHI_WIDTH / 8),
    .CHI_TXNID_WIDTH(12),
    .SLOT_COUNT(32),
    .DBID_MAP_DEPTH(64),
    .ENABLE_NONCOHERENT(1),
    .ENABLE_COHERENT(1),
    .TXRSP_CREDITS(4)
  ) dut (
    .clk(clk), .rst(rst), .admission_valid(1'b0), .axsize(3'b000),
    .profile_coherent(1'b1), .profile_enabled(1'b1), .txnid(12'b0),
    .txrsp_valid(1'b0), .txrsp_credit(1'b1), .req_attr_complete(1'b1)
  );
endmodule

module tb_param_rni_width_matrix;
  reg clk;
  reg rst;

  always #5 clk = ~clk;

  // AXI legal-width matrix at the default CHI DAT width.
  tb_param_rni_width_case #(.AXI_WIDTH(8), .CHI_WIDTH(256)) axi8_chi256(clk, rst);
  tb_param_rni_width_case #(.AXI_WIDTH(16), .CHI_WIDTH(256)) axi16_chi256(clk, rst);
  tb_param_rni_width_case #(.AXI_WIDTH(32), .CHI_WIDTH(256)) axi32_chi256(clk, rst);
  tb_param_rni_width_case #(.AXI_WIDTH(64), .CHI_WIDTH(256)) axi64_chi256(clk, rst);
  tb_param_rni_width_case #(.AXI_WIDTH(128), .CHI_WIDTH(256)) axi128_chi256(clk, rst);
  tb_param_rni_width_case #(.AXI_WIDTH(256), .CHI_WIDTH(256)) axi256_chi256(clk, rst);
  tb_param_rni_width_case #(.AXI_WIDTH(512), .CHI_WIDTH(256)) axi512_chi256(clk, rst);
  tb_param_rni_width_case #(.AXI_WIDTH(1024), .CHI_WIDTH(256)) axi1024_chi256(clk, rst);

  // Remaining CHI DAT choices at the baseline AXI width.
  tb_param_rni_width_case #(.AXI_WIDTH(128), .CHI_WIDTH(128)) axi128_chi128(clk, rst);
  tb_param_rni_width_case #(.AXI_WIDTH(128), .CHI_WIDTH(512)) axi128_chi512(clk, rst);

  initial begin
    clk = 1'b0;
    rst = 1'b1;
    #12 rst = 1'b0;
    #20;
    $display("tb_param_rni_width_matrix PASS: AXI=8..1024, CHI DAT=128/256/512 static Gate-0 matrix");
    $finish;
  end
endmodule
