`timescale 1ns / 1ps
module tb_rni_chi_codec;
  logic [130:0] req; logic [6:0] op; logic [6:0] src, rn; logic [11:0] tx, rtx;
  logic [43:0] addr; logic [2:0] size; logic is_read; logic [405:0] dat;
  rni_chi_codec dut(.req_flit_i(req),.req_opcode_o(op),.req_src_id_o(src),.req_return_nid_o(rn),.req_txnid_o(tx),.req_return_txnid_o(rtx),.req_addr_o(addr),.req_size_o(size),.req_is_readnosnp_o(is_read),.read_tgt_id_i(7'h0),.read_src_id_i(7'h6),.read_txnid_i(12'h123),.read_return_nid_i(7'h6),.read_return_txnid_i(12'h005),.read_addr_i(44'h123_4567_890),.read_size_i(3'd2),.read_ns_i(1'b1),.read_order_i(2'b10),.read_memattr_i(4'h9),.readnosnp_flit_o(),.comp_tgt_id_i(7'h2),.comp_src_id_i(7'h6),.comp_home_nid_i(7'h6),.comp_txnid_i(12'h123),.comp_dbid_i(12'h456),.comp_data_i(32'hdead_beef),.compdata_flit_o(dat));
  task automatic ck(input logic x,input string s); if(x!==1'b1)$fatal(1,"%s",s); endtask
  initial begin
    req='0; req[11 +: 7]=7'h11; req[18 +: 12]=12'h321; req[30 +: 7]=7'h4; req[38 +: 12]=12'h765; req[50 +: 7]=7'h04; req[57 +: 3]=3'd2; req[60 +: 44]=44'h123_4567_890; #1;
    ck(op==7'h04&&is_read,"ReadNoSnp decode"); ck(src==7'h11&&tx==12'h321,"source/txnid decode"); ck(rn==7'h4&&rtx==12'h765,"return fields decode"); ck(size==3'd2&&addr==44'h123_4567_890,"address decode");
    ck(dut.readnosnp_flit_o[4 +:7]==7'h0 && dut.readnosnp_flit_o[11 +:7]==7'h6,"TXREQ node IDs"); ck(dut.readnosnp_flit_o[18 +:12]==12'h123 && dut.readnosnp_flit_o[30 +:7]==7'h6,"TXREQ transaction fields"); ck(dut.readnosnp_flit_o[50 +:7]==7'h04 && dut.readnosnp_flit_o[57 +:3]==3'd2 && dut.readnosnp_flit_o[60 +:44]==44'h123_4567_890,"TXREQ opcode/address"); ck(dut.readnosnp_flit_o[106]==1'b0 && dut.readnosnp_flit_o[107 +:2]==2'b10 && dut.readnosnp_flit_o[113 +:4]==4'h9,"TXREQ attributes/no-retry");
    ck(dat[4 +: 7]==7'h2&&dat[11 +: 7]==7'h6,"CompData IDs"); ck(dat[18 +: 12]==12'h123&&dat[30 +: 7]==7'h6,"CompData transaction fields"); ck(dat[37 +:4]==4'h4&&dat[43 +:3]==3'b010,"CompData opcode/resp"); ck(dat[53 +:12]==12'h456,"CompData DBID"); ck(dat[82 +:32]==32'hf&&dat[114 +:32]==32'hdead_beef,"CompData BE/data");
    $display("PASS: CHI codec OpenNoC default bundle"); $finish;
  end
endmodule
