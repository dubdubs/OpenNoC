`default_nettype none
module rni_txn_child_map #(
  parameter int unsigned TxnidWidth=12, parameter int unsigned TxnidEntries=32,
  parameter int unsigned ChildEntries=32
) (
  input logic clk,input logic rst,input logic alloc_valid_i,
  input logic [TxnidWidth-1:0] alloc_txnid_i,
  input logic [$clog2(ChildEntries)-1:0] alloc_child_i,
  input logic free_valid_i,input logic [TxnidWidth-1:0] free_txnid_i,
  input logic [TxnidWidth-1:0] lookup_txnid_i,output logic lookup_hit_o,
  output logic [$clog2(ChildEntries)-1:0] lookup_child_o
);
  logic [TxnidEntries-1:0] live_q;
  logic [$clog2(ChildEntries)-1:0] child_q [TxnidEntries];
  always_comb begin
    lookup_hit_o=(lookup_txnid_i<TxnidEntries)&&live_q[lookup_txnid_i];
    lookup_child_o='0;
    if(lookup_hit_o) lookup_child_o=child_q[lookup_txnid_i];
  end
  always_ff @(posedge clk or posedge rst) begin
    if(rst) live_q<='0;
    else begin
      if(alloc_valid_i && alloc_txnid_i<TxnidEntries) begin live_q[alloc_txnid_i]<=1'b1; child_q[alloc_txnid_i]<=alloc_child_i; end
      if(free_valid_i && free_txnid_i<TxnidEntries && !(alloc_valid_i&&alloc_txnid_i==free_txnid_i)) live_q[free_txnid_i]<=1'b0;
    end
  end
endmodule
`default_nettype wire
