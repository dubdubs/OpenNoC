`default_nettype none
module rni_parent_allocator #(parameter int unsigned Entries=32)(
 input logic clk,input logic rst,input logic alloc_valid_i,output logic alloc_ready_o,
 output logic [$clog2(Entries)-1:0] alloc_index_o,input logic free_valid_i,
 input logic [$clog2(Entries)-1:0] free_index_i);
 logic [Entries-1:0] used_q; logic found;
 always_comb begin found=0;alloc_index_o='0;for(int i=0;i<Entries;i++)if(!found&&!used_q[i])begin found=1;alloc_index_o=$clog2(Entries)'(i);end alloc_ready_o=found;end
 always_ff @(posedge clk or posedge rst) begin
  if(rst)used_q<='0; else begin
   if(alloc_valid_i&&alloc_ready_o)used_q[alloc_index_o]<=1;
   if(free_valid_i&&!(alloc_valid_i&&alloc_ready_o&&alloc_index_o==free_index_i))used_q[free_index_i]<=0;
  end
 end
endmodule
`default_nettype wire
