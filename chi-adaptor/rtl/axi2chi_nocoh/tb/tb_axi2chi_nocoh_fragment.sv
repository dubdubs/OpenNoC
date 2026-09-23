`timescale 1ns/1ps
`default_nettype none

`define CHECK(condition) \
  if (!(condition)) $fatal(1, "CHECK failed: %s", `"condition`");

module tb_axi2chi_nocoh_fragment;
  logic [31:0] axi_addr_i;
  logic [2:0] axi_size_i;
  logic fragment_two_valid_o;
  logic [31:0] fragment0_addr_o;
  logic [3:0] fragment0_axi_offset_o;
  logic [5:0] fragment0_line_offset_o;
  logic [3:0] fragment0_byte_count_o;
  logic [31:0] fragment1_addr_o;
  logic [3:0] fragment1_axi_offset_o;
  logic [5:0] fragment1_line_offset_o;
  logic [3:0] fragment1_byte_count_o;

  axi2chi_nocoh_fragment #(
    .AxiAddrWidth(32), .AxiDataWidth(64), .AxsizeWidth(3),
    .CacheLineBytes(64)
  ) dut (.*);

  initial begin
    axi_addr_i = 32'h0000_1021;
    axi_size_i = 3'd2;
    #1;
    `CHECK(!fragment_two_valid_o);
    `CHECK(fragment0_addr_o == 32'h0000_1021);
    `CHECK(fragment0_axi_offset_o == 0 && fragment0_line_offset_o == 6'h21);
    `CHECK(fragment0_byte_count_o == 4 && fragment1_byte_count_o == 0);

    axi_addr_i = 32'h0000_103c;
    axi_size_i = 3'd3;
    #1;
    `CHECK(fragment_two_valid_o);
    `CHECK(fragment0_addr_o == 32'h0000_103c);
    `CHECK(fragment0_axi_offset_o == 0 && fragment0_line_offset_o == 6'h3c);
    `CHECK(fragment0_byte_count_o == 4);
    `CHECK(fragment1_addr_o == 32'h0000_1040);
    `CHECK(fragment1_axi_offset_o == 4 && fragment1_line_offset_o == 0);
    `CHECK(fragment1_byte_count_o == 4);
    $display("PASS: AXI beat fragment geometry");
    $finish;
  end
endmodule

`default_nettype wire

`undef CHECK
