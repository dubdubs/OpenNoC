`timescale 1ns/1ps
module tb_rni_txn_child_map;
 logic clk=0,rst=1,av,fv,hit; logic[3:0] at,ft,lt; logic[1:0] ac,lc;
 rni_txn_child_map #(.TxnidWidth(4),.TxnidEntries(4),.ChildEntries(4)) dut(.clk(clk),.rst(rst),.alloc_valid_i(av),.alloc_txnid_i(at),.alloc_child_i(ac),.free_valid_i(fv),.free_txnid_i(ft),.lookup_txnid_i(lt),.lookup_hit_o(hit),.lookup_child_o(lc));
 always #5 clk=~clk; task automatic ck(input logic x,input string s);if(x!==1)$fatal(1,"%s",s);endtask
 initial begin av=0;fv=0;at=0;ft=0;lt=0;repeat(2)@(posedge clk);rst=0;at=2;ac=3;av=1;@(posedge clk);av=0;lt=2;#1;ck(hit&&lc==3,"map lookup");at=1;ac=0;av=1;@(posedge clk);av=0;lt=1;#1;ck(hit&&lc==0,"out of order map");fv=1;ft=2;@(posedge clk);fv=0;lt=2;#1;ck(!hit,"free invalidates");lt=4;#1;ck(!hit,"out of range miss");$display("PASS: txn child map");$finish;end
endmodule
