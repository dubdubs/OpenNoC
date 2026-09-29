`timescale 1ns/1ps
`default_nettype none
`define C(x) if(!(x)) $fatal(1,"check failed: %s",`"x`")
module tb_axi2chi_nocoh_rd_data_256x128;
  localparam int P=4,CN=4; logic clk=0,rst=1;
  logic fragment_valid_i,fragment_ready_o,fragment_lookup_valid_i,fragment_last_i,fragment_last_fragment_i;
  logic [$clog2(CN)-1:0] fragment_child_idx_i; logic [$clog2(P)-1:0] fragment_parent_idx_i;
  logic [1:0] fragment_axi_id_i; logic [7:0] fragment_axi_beat_i;
  logic [127:0] fragment_data_i; logic [15:0] fragment_be_i; logic [1:0] fragment_dataid_i; logic [1:0] fragment_resp_i; logic [1:0] fragment_idx_i;
  logic [$clog2(256/8+1)-1:0] fragment_axi_byte_offset_i,fragment_byte_count_i;
  logic [$clog2(64)-1:0] fragment_line_byte_offset_i;
  logic rd_rsp_parent_valid_o; logic [$clog2(P)-1:0] rd_rsp_parent_idx_o; logic [$clog2(CN)-1:0] rd_rsp_child_idx_o; logic [7:0] rd_rsp_axi_beat_o; logic [P-1:0] rd_rsp_retire_permit_vec_i;
  logic rd_rsp_valid_o,rd_rsp_ready_i; logic [1:0] rd_rsp_id_o; logic [255:0] rd_rsp_data_o; logic [1:0] rd_rsp_resp_o; logic rd_rsp_last_o;
  logic child_complete_valid_o; logic [$clog2(CN)-1:0] child_complete_idx_o; logic [1:0] child_complete_resp_o;
  axi2chi_nocoh_rd_data #(.AxiDataWidth(256),.AxiIdWidth(2),.ChiDataWidth(128),.ParentEntries(P),.ChildEntries(CN)) dut(.*);
  always #5 clk=~clk;
  task automatic send(input logic [1:0] did,input logic [127:0] d);
    begin fragment_dataid_i=did;fragment_data_i=d;fragment_valid_i=1;@(posedge clk);@(negedge clk);fragment_valid_i=0;end
  endtask
  initial begin
    fragment_valid_i=0;fragment_child_idx_i=2;fragment_parent_idx_i=1;fragment_lookup_valid_i=1;fragment_axi_id_i=2;fragment_axi_beat_i=0;fragment_data_i=0;fragment_be_i='1;fragment_dataid_i=0;fragment_resp_i=0;fragment_last_i=1;fragment_last_fragment_i=1;fragment_idx_i=0;fragment_axi_byte_offset_i=0;fragment_line_byte_offset_i=0;fragment_byte_count_i=32;rd_rsp_retire_permit_vec_i='1;rd_rsp_ready_i=0;
    @(negedge clk);rst=0;send(0,128'h00112233445566778899aabbccddeeff);#1;`C(!rd_rsp_valid_o);send(1,128'hffeeddccbbaa99887766554433221100);
    repeat(4) begin if(!rd_rsp_valid_o) begin @(posedge clk);@(negedge clk);end end
    #1;`C(rd_rsp_valid_o&&rd_rsp_id_o==2&&rd_rsp_last_o&&rd_rsp_resp_o==0);`C(rd_rsp_data_o==256'hffeeddccbbaa99887766554433221100_00112233445566778899aabbccddeeff);rd_rsp_ready_i=1;@(posedge clk);
    $display("PASS: rd_data 256b AXI assembly from two 128b DataIDs");$finish;
  end
endmodule
`default_nettype wire
`undef C
