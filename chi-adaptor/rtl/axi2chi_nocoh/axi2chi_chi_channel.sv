// Raw CHI channel register and LinkActive state skeleton.

`default_nettype none

module axi2chi_chi_channel #(
  parameter int unsigned FlitWidth = 131
) (
  input logic clk,
  input logic rst,
  input logic tx_valid_i,
  input logic [FlitWidth-1:0] tx_flit_i,
  output logic tx_ready_o,
  output logic chi_tx_flitv_o,
  output logic [FlitWidth-1:0] chi_tx_flit_o,
  input logic chi_tx_lcrdv_i,
  input logic chi_rx_flitv_i,
  input logic [FlitWidth-1:0] chi_rx_flit_i,
  output logic chi_rx_lcrdv_o,
  output logic rx_valid_o,
  output logic [FlitWidth-1:0] rx_flit_o,
  input logic rx_ready_i
);

  logic tx_hold_valid_q;
  logic [FlitWidth-1:0] tx_hold_flit_q;
  logic rx_hold_valid_q;
  logic [FlitWidth-1:0] rx_hold_flit_q;

  // Channel register behavior is deferred.

endmodule

`default_nettype wire
