`timescale 1ns/1ps
`default_nettype none

module tb_axi2chi_nocoh_top_read_l32;
  tb_axi2chi_nocoh_top_read_128x256 #(.CacheLineBytes(32)) smoke ();
endmodule

module tb_axi2chi_nocoh_top_read_l128;
  tb_axi2chi_nocoh_top_read_128x256 #(.CacheLineBytes(128)) smoke ();
endmodule

module tb_axi2chi_nocoh_top_write_l32;
  tb_axi2chi_nocoh_top_write_128x256 #(.CacheLineBytes(32)) smoke ();
endmodule

module tb_axi2chi_nocoh_top_write_l128;
  tb_axi2chi_nocoh_top_write_128x256 #(.CacheLineBytes(128)) smoke ();
endmodule

`default_nettype wire
