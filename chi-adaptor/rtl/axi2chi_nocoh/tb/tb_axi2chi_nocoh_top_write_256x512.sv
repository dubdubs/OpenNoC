`timescale 1ns/1ps
`default_nettype none
module tb_axi2chi_nocoh_top_write_256x512;
  tb_axi2chi_nocoh_top_write_128x256 #(
    .AxiDataWidth(256), .ChiDataWidth(512)
  ) smoke ();
endmodule
`default_nettype wire
