// RXRSP/RXDAT FIFO ownership and L-credit return skeleton.

`default_nettype none

module axi2chi_chi_rxflit #(
  parameter int unsigned FlitWidth = 406,
  parameter int unsigned Depth = 2
) (
  input logic clk,
  input logic rst,
  input logic chi_flitv_i,
  input logic [FlitWidth-1:0] chi_flit_i,
  output logic chi_lcrdv_o,
  output logic core_valid_o,
  output logic [FlitWidth-1:0] core_flit_o,
  input logic core_ready_i
);

  localparam int unsigned PtrWidth = $clog2(Depth);
  logic [FlitWidth-1:0] fifo_q [Depth];
  logic [PtrWidth-1:0] wr_ptr_q;
  logic [PtrWidth-1:0] rd_ptr_q;
  logic [$clog2(Depth + 1)-1:0] occupancy_q;

  // FIFO push/pop and credit-return timing are deferred.

endmodule

`default_nettype wire
