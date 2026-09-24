// One CHI channel credit counter.

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
  logic [$clog2(MaxCredits + 1)-1:0] credit_count_d;

  always_comb begin
    credit_count_d = credit_count_q;
    if (credit_return_i && !send_fire_i && credit_count_q < MaxCredits) begin
      credit_count_d = credit_count_q + 1'b1;
    end else if (!credit_return_i && send_fire_i && credit_count_q != '0) begin
      credit_count_d = credit_count_q - 1'b1;
    end

    credit_available_o = credit_count_q != '0;
    credit_count_o = credit_count_q;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      credit_count_q <= MaxCredits[$clog2(MaxCredits + 1)-1:0];
    end else begin
      credit_count_q <= credit_count_d;
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (!rst) begin
      assert (credit_count_q <= MaxCredits)
      else $fatal(1, "CHI credit count overflow");
      assert (!(send_fire_i && !credit_available_o))
      else $fatal(1, "CHI send without available credit");
    end
  end
`endif

endmodule

`default_nettype wire
