`timescale 1ns / 1ps
module tb_rni_axi_core_admission_bridge;
  logic clk=0, rst=1, wv, wr, cwcr, cwdr, rv, rr, crcr;
  logic [3:0] wid=4'ha, rid=4'h3, cwid, crid;
  logic [63:0] wa=64'h1234, ra=64'h5678, cwa, cra;
  logic [7:0] wl=0, rl=0, cwl, crl;
  logic [2:0] ws=3'd2, rs=3'd2, cws, crs;
  logic [1:0] wb=2'b01, rb=2'b01, cwb, crb;
  logic [31:0] wd=32'hface_cafe, cwd;
  logic [3:0] wstrb=4'hf, cwstrb;
  logic cwdv, cwd_valid, cwlast, crv;
  rni_axi_core_admission_bridge dut(
    .clk(clk),.rst(rst),.write_bundle_valid_i(wv),.write_bundle_id_i(wid),.write_bundle_addr_i(wa),.write_bundle_len_i(wl),.write_bundle_size_i(ws),.write_bundle_burst_i(wb),.write_bundle_data_i(wd),.write_bundle_strb_i(wstrb),.write_bundle_ready_o(wr),.core_write_cmd_valid_o(cwdv),.core_write_cmd_id_o(cwid),.core_write_cmd_addr_o(cwa),.core_write_cmd_len_o(cwl),.core_write_cmd_size_o(cws),.core_write_cmd_burst_o(cwb),.core_write_cmd_ready_i(cwcr),.core_write_data_valid_o(cwd_valid),.core_write_data_o(cwd),.core_write_strb_o(cwstrb),.core_write_last_o(cwlast),.core_write_data_ready_i(cwdr),.read_bundle_valid_i(rv),.read_bundle_id_i(rid),.read_bundle_addr_i(ra),.read_bundle_len_i(rl),.read_bundle_size_i(rs),.read_bundle_burst_i(rb),.read_bundle_ready_o(rr),.core_read_cmd_valid_o(crv),.core_read_cmd_id_o(crid),.core_read_cmd_addr_o(cra),.core_read_cmd_len_o(crl),.core_read_cmd_size_o(crs),.core_read_cmd_burst_o(crb),.core_read_cmd_ready_i(crcr));
  always #5 clk=~clk;
  task automatic ck(input logic x,input string s); if(x!==1'b1)$fatal(1,"%s",s); endtask
  initial begin
    wv=0;rv=0;cwcr=0;cwdr=0;crcr=0; repeat(2)@(posedge clk); rst=0;
    wv=1;rv=1; #1; ck(cwdv&&crv,"valid mapping"); ck(!wr&&!rr,"stall mapping"); ck(cwa==wa&&cwd==wd&&cwstrb==wstrb&&cwlast,"write payload mapping");
    crcr=1; #1; ck(rr&&crid==rid&&cra==ra,"read mapping");
    cwcr=1;cwdr=1; #1; ck(wr,"atomic write ready");
    $display("PASS: admission bridge mapping and backpressure"); $finish;
  end
endmodule
