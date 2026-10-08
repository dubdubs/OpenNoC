`timescale 1ns/1ps
`default_nettype none
module tb_axi2chi_nocoh_top_write_32x128;
  tb_axi2chi_nocoh_top_write_128x256 #(
    .AxiDataWidth(32), .ChiDataWidth(128)
  ) smoke ();
endmodule
`default_nettype wire
