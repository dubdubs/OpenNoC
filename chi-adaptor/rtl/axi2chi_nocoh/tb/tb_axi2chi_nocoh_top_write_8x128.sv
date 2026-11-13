`timescale 1ns/1ps
`default_nettype none

// Elaboration and smoke coverage for the one-byte AXI data-bus profile.  In
// particular, this configuration exercises the slave's zero lane-offset case.
module tb_axi2chi_nocoh_top_write_8x128;
  tb_axi2chi_nocoh_top_write_128x256 #(
    .AxiDataWidth(8),
    .ChiDataWidth(128)
  ) smoke ();
endmodule

`default_nettype wire
