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
  logic push_fire;
  logic pop_fire;

  always_comb begin
    chi_lcrdv_o = occupancy_q < Depth;
    core_valid_o = occupancy_q != '0;
    core_flit_o = fifo_q[rd_ptr_q];
    push_fire = chi_flitv_i && chi_lcrdv_o;
    pop_fire = core_valid_o && core_ready_i;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      wr_ptr_q <= '0;
      rd_ptr_q <= '0;
      occupancy_q <= '0;
      for (int unsigned idx = 0; idx < Depth; idx++) begin
        fifo_q[idx] <= '0;
      end
    end else begin
      if (push_fire) begin
        fifo_q[wr_ptr_q] <= chi_flit_i;
        wr_ptr_q <= wr_ptr_q == PtrWidth'(Depth - 1) ? '0 : wr_ptr_q + 1'b1;
      end

      if (pop_fire) begin
        rd_ptr_q <= rd_ptr_q == PtrWidth'(Depth - 1) ? '0 : rd_ptr_q + 1'b1;
      end

      unique case ({push_fire, pop_fire})
        2'b10: occupancy_q <= occupancy_q + 1'b1;
        2'b01: occupancy_q <= occupancy_q - 1'b1;
        default: occupancy_q <= occupancy_q;
      endcase
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (!rst) begin
      assert (occupancy_q <= Depth)
      else $fatal(1, "RX flit FIFO occupancy overflow");
      assert (!(push_fire && occupancy_q == Depth && !pop_fire))
      else $fatal(1, "RX flit FIFO overflow");
      assert (!(pop_fire && occupancy_q == '0))
      else $fatal(1, "RX flit FIFO underflow");
      assert (!(chi_flitv_i && !chi_lcrdv_o && occupancy_q < Depth))
      else $fatal(1, "RX L-credit withheld while space is available");
    end
  end
`endif

endmodule

`default_nettype wire
