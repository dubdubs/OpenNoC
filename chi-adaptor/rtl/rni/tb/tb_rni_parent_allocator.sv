`timescale 1ns/1ps
module tb_rni_parent_allocator;
 logic clk=0,rst=1,av,ar,fv;logic[1:0] ai,fi;
 rni_parent_allocator #(.Entries(4)) dut(.clk(clk),.rst(rst),.alloc_valid_i(av),.alloc_ready_o(ar),.alloc_index_o(ai),.free_valid_i(fv),.free_index_i(fi));
 always #5 clk=~clk;task automatic ck(input logic x,input string s);if(x!==1)$fatal(1,"%s",s);endtask
 initial begin av=0;fv=0;fi=0;repeat(2)@(posedge clk);rst=0;for(int i=0;i<4;i++)begin #1;ck(ar&&ai==i,"parent allocation order");av=1;@(posedge clk);av=0;end #1;ck(!ar,"parent full");fi=2;fv=1;@(posedge clk);fv=0;#1;ck(ar&&ai==2,"parent reuse");$display("PASS: parent allocator");$finish;end
endmodule
