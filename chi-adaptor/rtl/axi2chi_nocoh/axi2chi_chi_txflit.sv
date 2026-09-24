// TXREQ/TXDAT queue and arbitration.

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
  logic producer_fire;
  logic pop_fire;

  always_comb begin
    producer_ready_o = occupancy_q < Depth;
    chi_flitv_o = occupancy_q != '0 && credit_available_i;
    chi_flit_o = fifo_q[rd_ptr_q];
    send_fire_o = chi_flitv_o;
    producer_fire = producer_valid_i && producer_ready_o;
    pop_fire = chi_flitv_o;
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
      if (producer_fire) begin
        fifo_q[wr_ptr_q] <= producer_flit_i;
        wr_ptr_q <= wr_ptr_q == PtrWidth'(Depth - 1) ? '0 : wr_ptr_q + 1'b1;
      end

      if (pop_fire) begin
        rd_ptr_q <= rd_ptr_q == PtrWidth'(Depth - 1) ? '0 : rd_ptr_q + 1'b1;
      end

      unique case ({producer_fire, pop_fire})
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
      else $fatal(1, "TX flit FIFO occupancy overflow");
      assert (!(producer_valid_i && !producer_ready_o && occupancy_q < Depth))
      else $fatal(1, "TX producer backpressured while space is available");
      assert (!(chi_flitv_o && !credit_available_i))
      else $fatal(1, "TX flit sent without credit");
      assert (!(pop_fire && occupancy_q == '0))
      else $fatal(1, "TX flit FIFO underflow");
    end
  end
`endif

endmodule

`default_nettype wire
