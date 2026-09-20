`timescale 1ns / 1ps
module tb_rni_txnid_allocator;
  logic clk=0,rst=1,av,ar,fv; logic [3:0] aid,fid;
  rni_txnid_allocator #(.TxnidWidth(4),.Entries(4)) dut(.clk(clk),.rst(rst),.alloc_valid_i(av),.alloc_ready_o(ar),.alloc_txnid_o(aid),.free_valid_i(fv),.free_txnid_i(fid));
  always #5 clk=~clk;
  task automatic ck(input logic x,input string s);if(x!==1'b1)$fatal(1,"%s",s);endtask
  initial begin
    av=0;fv=0;fid=0; repeat(2)@(posedge clk);rst=0;
    for(int i=0;i<4;i++) begin #1;ck(ar&&aid==i,"allocation order");av=1;@(posedge clk);av=0;end
    #1;ck(!ar,"full backpressure");
    fid=4'd1;fv=1;@(posedge clk);fv=0;#1;ck(ar&&aid==1,"out-of-order reuse");
    av=1;@(posedge clk);av=0;#1;ck(!ar,"reused ID occupied");
    fid=0;fv=1;@(posedge clk);fv=0;#1;ck(ar&&aid==0,"second reuse");
    $display("PASS: txnid allocator");$finish;
  end
endmodule
