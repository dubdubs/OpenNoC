`timescale 1ns/1ps
`default_nettype none

`define CHECK(condition) \
  if (!(condition)) $fatal(1, "CHECK failed: %s", `"condition`");

module tb_axi2chi_nocoh_rd_byte_map;
  logic [511:0] chi_data_i;
  logic [63:0] chi_be_i;
  logic [3:0] axi_byte_offset_i;
  logic [3:0] fragment_byte_count_i;
  logic [5:0] line_byte_offset_i;
  logic [6:0] chi_byte_offset_i;
  logic [63:0] axi_data_o;
  logic [7:0] axi_valid_be_o;

  axi2chi_nocoh_rd_byte_map #(
    .AxiDataWidth(64), .ChiDataWidth(512), .CacheLineBytes(64)
  ) dut (.*);

  initial begin
    chi_data_i = '0;
    chi_be_i = '0;
    chi_data_i[31:0] = 32'h0706_0504;
    chi_be_i[3:0] = 4'b1011;
    axi_byte_offset_i = 4'd4;
    fragment_byte_count_i = 4'd4;
    line_byte_offset_i = 6'd0;
    chi_byte_offset_i = '0;
    #1;
    `CHECK(axi_data_o == 64'h0706_0504_0000_0000);
    `CHECK(axi_valid_be_o == 8'b1011_0000);
    $display("PASS: read fragment byte-lane mapping");
    $finish;
  end
endmodule

`default_nettype wire

`undef CHECK
