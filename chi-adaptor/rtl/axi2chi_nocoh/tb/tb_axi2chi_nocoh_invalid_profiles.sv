`timescale 1ns/1ps
`default_nettype none

// Each module is a negative elaboration test. The regression expects the
// simulator to terminate with the matching elaboration-time fatal message.
module tb_invalid_axi_geometry;
  axi2chi_nocoh_top #(.AxiDataWidth(96), .ChiDataWidth(128),
                      .CacheLineBytes(64)) dut ();
endmodule

module tb_invalid_chi_geometry;
  axi2chi_nocoh_top #(.AxiDataWidth(64), .ChiDataWidth(192),
                      .CacheLineBytes(64)) dut ();
endmodule

module tb_invalid_cache_line;
  axi2chi_nocoh_top #(.AxiDataWidth(32), .ChiDataWidth(128),
                      .CacheLineBytes(16)) dut ();
endmodule

module tb_invalid_line_divisibility;
  axi2chi_nocoh_top #(.AxiDataWidth(512), .ChiDataWidth(128),
                      .CacheLineBytes(32)) dut ();
endmodule

`default_nettype wire
