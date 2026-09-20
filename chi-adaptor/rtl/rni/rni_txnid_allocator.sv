`default_nettype none
module rni_txnid_allocator #(
  parameter int unsigned TxnidWidth = 12,
  parameter int unsigned Entries = 32
) (
  input logic clk, input logic rst,
  input logic alloc_valid_i, output logic alloc_ready_o,
  output logic [TxnidWidth-1:0] alloc_txnid_o,
  input logic free_valid_i, input logic [TxnidWidth-1:0] free_txnid_i
);
  logic [Entries-1:0] used_q;
  logic found_free;
  always_comb begin
    found_free = 1'b0;
    alloc_txnid_o = '0;
    for (int i = 0; i < Entries; i++) begin
      if (!found_free && !used_q[i]) begin found_free = 1'b1; alloc_txnid_o = TxnidWidth'(i); end
    end
    alloc_ready_o = found_free;
  end
  always_ff @(posedge clk or posedge rst) begin
    if (rst) used_q <= '0;
    else begin
      if (alloc_valid_i && alloc_ready_o) used_q[alloc_txnid_o] <= 1'b1;
      if (free_valid_i && (free_txnid_i < Entries) &&
          !(alloc_valid_i && alloc_ready_o && (alloc_txnid_o == free_txnid_i)))
        used_q[free_txnid_i] <= 1'b0;
    end
  end
endmodule
`default_nettype wire
