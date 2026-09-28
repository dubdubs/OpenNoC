`timescale 1ns/1ps
`default_nettype none

module tb_axi2chi_nocoh_top_read_64x256;
  tb_axi2chi_nocoh_top_read_128x256 #(
    .AxiDataWidth(64),
    .CacheLineBytes(64)
  ) smoke ();
endmodule

`default_nettype wire
