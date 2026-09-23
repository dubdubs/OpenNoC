`timescale 1ns/1ps
`default_nettype none

`define CHECK(condition) \
  if (!(condition)) $fatal(1, "CHECK failed: %s", `"condition`");

module tb_axi2chi_nocoh_wr_byte_map;
  logic [63:0] axi_data_i;
  logic [7:0] axi_strb_i;
  logic [3:0] axi_byte_offset_i;
  logic [3:0] fragment_byte_count_i;
  logic [5:0] line_byte_offset_i;
  logic [511:0] chi_data_o;
  logic [63:0] chi_be_o;

  axi2chi_nocoh_wr_byte_map #(
    .AxiDataWidth(64), .ChiDataWidth(512), .CacheLineBytes(64)
  ) dut (.*);

  initial begin
    axi_data_i = 64'h0706_0504_0302_0100;
    axi_strb_i = 8'b1011_1101;
    axi_byte_offset_i = 4'd4;
    fragment_byte_count_i = 4'd4;
    line_byte_offset_i = 6'd0;
    #1;
    `CHECK(chi_data_o[31:0] == 32'h0706_0504);
    `CHECK(chi_be_o[3:0] == 4'b1011);
    `CHECK(chi_data_o[511:32] == '0 && chi_be_o[63:4] == '0);
    $display("PASS: write byte-lane fragment mapping");
    $finish;
  end
endmodule

`default_nettype wire

`undef CHECK
