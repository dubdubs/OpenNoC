`timescale 1ns/1ps
`default_nettype none
`define C(x) if(!(x)) $fatal(1,"check failed: %s",`"x`")
module tb_axi2chi_nocoh_wr_data_256x128;
  localparam int P=4,CN=4; logic clk=0,rst=1;
  logic wr_beat_valid_i,wr_beat_ready_o,wr_beat_last_i,wr_beat_error_i;
  logic [$clog2(P)-1:0] wr_beat_parent_idx_i,child_bind_parent_idx_i;
  logic [255:0] wr_beat_data_i; logic [31:0] wr_beat_strb_i;
  logic child_bind_valid_i,child_bind_ready_o,child_bind_last_fragment_i;
  logic [CN-1:0] child_waiting_i; logic [$clog2(CN)-1:0] child_bind_idx_i;
  logic [$clog2(256/8+1)-1:0] child_bind_axi_byte_offset_i,child_bind_fragment_byte_count_i;
  logic [$clog2(64)-1:0] child_bind_line_byte_offset_i;
  logic txdat_fragment_valid_o,txdat_fragment_ready_i; logic [$clog2(CN)-1:0] txdat_fragment_child_idx_o; logic [1:0] txdat_fragment_dataid_o; logic txdat_fragment_last_o,txdat_fragment_error_o; logic [P-1:0] wr_beat_present_vec_o,wr_beat_full_vec_o; logic [127:0] txdat_fragment_data_o; logic [15:0] txdat_fragment_be_o;
  axi2chi_nocoh_wr_data #(.AxiDataWidth(256),.ChiDataWidth(128),.ParentEntries(P),.ChildEntries(CN)) dut(.*);
  always #5 clk=~clk;
  initial begin
    wr_beat_valid_i=0;wr_beat_parent_idx_i=1;wr_beat_data_i=256'hffeeddccbbaa99887766554433221100_00112233445566778899aabbccddeeff;wr_beat_strb_i='1;wr_beat_last_i=1;wr_beat_error_i=0;
    child_bind_valid_i=0;child_waiting_i='0;child_bind_parent_idx_i=1;child_bind_idx_i=2;child_bind_last_fragment_i=1;child_bind_axi_byte_offset_i=0;child_bind_line_byte_offset_i=0;child_bind_fragment_byte_count_i=32;txdat_fragment_ready_i=0;
    @(negedge clk);rst=0;wr_beat_valid_i=1;child_bind_valid_i=1;child_waiting_i[2]=1;#1;`C(wr_beat_ready_o&&child_bind_ready_o);@(posedge clk);@(negedge clk);wr_beat_valid_i=0;child_bind_valid_i=0;
    #1;`C(txdat_fragment_valid_o&&txdat_fragment_dataid_o==0&&!txdat_fragment_last_o);`C(txdat_fragment_data_o==128'h00112233445566778899aabbccddeeff&&txdat_fragment_be_o=='1);txdat_fragment_ready_i=1;@(posedge clk);@(negedge clk);txdat_fragment_ready_i=0;
    #1;`C(txdat_fragment_valid_o&&txdat_fragment_dataid_o==1&&txdat_fragment_last_o);`C(txdat_fragment_data_o==128'hffeeddccbbaa99887766554433221100&&txdat_fragment_be_o=='1);txdat_fragment_ready_i=1;@(posedge clk);@(negedge clk);txdat_fragment_ready_i=0;#1;`C(!txdat_fragment_valid_o&&wr_beat_ready_o);
    $display("PASS: wr_data 256b AXI to two 128b TXDAT DataIDs");$finish;
  end
endmodule
`default_nettype wire
`undef C
