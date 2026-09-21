// One CHI channel credit counter skeleton.

`default_nettype none

module axi2chi_chi_credit #(
  parameter int unsigned MaxCredits = 2
) (
  input logic clk,
  input logic rst,
  input logic credit_return_i,
  input logic send_fire_i,
  output logic credit_available_o,
  output logic [$clog2(MaxCredits + 1)-1:0] credit_count_o
);

  logic [$clog2(MaxCredits + 1)-1:0] credit_count_q;

  // Counter update and underflow/overflow assertions are deferred.

endmodule

`default_nettype wire
