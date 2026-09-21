// TXREQ/TXDAT queue and arbitration skeleton.

`default_nettype none

module axi2chi_chi_txflit #(
  parameter int unsigned FlitWidth = 406,
  parameter int unsigned Depth = 2
) (
  input logic clk,
  input logic rst,
  input logic producer_valid_i,
  input logic [FlitWidth-1:0] producer_flit_i,
  output logic producer_ready_o,
  input logic credit_available_i,
  output logic chi_flitv_o,
  output logic [FlitWidth-1:0] chi_flit_o,
  output logic send_fire_o
);

  localparam int unsigned PtrWidth = $clog2(Depth);
  logic [FlitWidth-1:0] fifo_q [Depth];
  logic [PtrWidth-1:0] wr_ptr_q;
  logic [PtrWidth-1:0] rd_ptr_q;
  logic [$clog2(Depth + 1)-1:0] occupancy_q;

  // Queue admission, arbitration, and payload-hold logic are deferred.

endmodule

`default_nettype wire
