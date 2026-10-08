`timescale 1ns/1ps
`default_nettype none
`define CHECK(c) if (!(c)) $fatal(1, "CHECK failed: %s", `"c`")
module tb_axi2chi_nocoh_top_write_128x256 #(
  parameter int unsigned AxiDataWidth = 128,
  parameter int unsigned ChiDataWidth = 256
);
  localparam int unsigned AxiAddrWidth=32, AxiIdWidth=2;
  localparam int unsigned ChiTxnidWidth=8, ChiDbidWidth=8;
  localparam int unsigned ReqFlitWidth=128, RspFlitWidth=64, DatFlitWidth=384;
  localparam int unsigned ParentEntries=4, ChildEntries=4;
  logic clk=0, aresetn=0;
  logic [AxiIdWidth-1:0] s_axi_awid,s_axi_bid,s_axi_arid,s_axi_rid;
  logic [AxiAddrWidth-1:0] s_axi_awaddr,s_axi_araddr;
  logic [7:0] s_axi_awlen,s_axi_arlen; logic [2:0] s_axi_awsize,s_axi_arsize;
  logic [1:0] s_axi_awburst,s_axi_arburst; logic s_axi_awvalid,s_axi_awready;
  logic [AxiDataWidth-1:0] s_axi_wdata,s_axi_rdata;
  logic [AxiDataWidth/8-1:0] s_axi_wstrb;
  logic s_axi_wlast,s_axi_wvalid,s_axi_wready; logic [1:0] s_axi_bresp,s_axi_rresp;
  logic s_axi_bvalid,s_axi_bready,s_axi_arvalid,s_axi_arready,s_axi_rlast,s_axi_rvalid,s_axi_rready;
  logic chi_txreq_flitv_o,chi_txreq_lcrdv_i; logic [ReqFlitWidth-1:0] chi_txreq_flit_o;
  logic chi_txdat_flitv_o,chi_txdat_lcrdv_i; logic [DatFlitWidth-1:0] chi_txdat_flit_o;
  logic chi_txrsp_flitv_o,chi_txrsp_lcrdv_i; logic [RspFlitWidth-1:0] chi_txrsp_flit_o;
  logic chi_rxrsp_flitv_i,chi_rxrsp_lcrdv_o; logic [RspFlitWidth-1:0] chi_rxrsp_flit_i;
  logic chi_rxdat_flitv_i,chi_rxdat_lcrdv_o; logic [DatFlitWidth-1:0] chi_rxdat_flit_i;
  logic chi_txlinkactivereq_o,chi_txlinkactiveack_i,chi_rxlinkactivereq_i,chi_rxlinkactiveack_o;
  logic [RspFlitWidth-1:0] rsp;
  axi2chi_nocoh_top #(.AxiAddrWidth(AxiAddrWidth),.AxiDataWidth(AxiDataWidth),.AxiIdWidth(AxiIdWidth),.ChiTxnidWidth(ChiTxnidWidth),.ChiDbidWidth(ChiDbidWidth),.ChiDataWidth(ChiDataWidth),.ParentEntries(ParentEntries),.ChildEntries(ChildEntries),.ReqFlitWidth(ReqFlitWidth),.RspFlitWidth(RspFlitWidth),.DatFlitWidth(DatFlitWidth)) dut (.*);
  always #5 clk=~clk;
  task automatic send_rsp(input logic [RspFlitWidth-1:0] p);
    begin chi_rxrsp_flit_i=p; chi_rxrsp_flitv_i=1; #1; `CHECK(chi_rxrsp_lcrdv_o); @(posedge clk); @(negedge clk); chi_rxrsp_flitv_i=0; end
  endtask
  initial begin
    s_axi_awid=2'd1;s_axi_awaddr=32'h2000;s_axi_awlen=0;s_axi_awsize=$clog2(AxiDataWidth/8);s_axi_awburst=2'b01;s_axi_awvalid=0;
    s_axi_wdata=128'h1122_3344_5566_7788_99aa_bbcc_ddee_ff00;s_axi_wstrb=(1<<(AxiDataWidth/8))-1;s_axi_wlast=1;s_axi_wvalid=0;s_axi_bready=0;
    s_axi_arid=0;s_axi_araddr=0;s_axi_arlen=0;s_axi_arsize=0;s_axi_arburst=0;s_axi_arvalid=0;s_axi_rready=1;
    chi_txreq_lcrdv_i=0;chi_txdat_lcrdv_i=0;chi_txrsp_lcrdv_i=0;chi_rxrsp_flitv_i=0;chi_rxrsp_flit_i=0;chi_rxdat_flitv_i=0;chi_rxdat_flit_i=0;chi_txlinkactiveack_i=0;chi_rxlinkactivereq_i=1;
    @(negedge clk);aresetn=1;@(posedge clk);@(negedge clk);chi_txlinkactiveack_i=1;@(posedge clk);@(negedge clk);
    s_axi_awvalid=1;#1;`CHECK(s_axi_awready);@(posedge clk);@(negedge clk);s_axi_awvalid=0;
    repeat(4) begin if(!chi_txreq_flitv_o) begin @(posedge clk);@(negedge clk);end end
    #1;`CHECK(chi_txreq_flitv_o && chi_txreq_flit_o[32+:AxiAddrWidth]==32'h2000);chi_txreq_lcrdv_i=1;@(posedge clk);@(negedge clk);chi_txreq_lcrdv_i=0;
    rsp=0;rsp[3:0]=4'h1;rsp[24+:ChiDbidWidth]=8'ha5;send_rsp(rsp);
    s_axi_wvalid=1;repeat(4) begin if(!s_axi_wready) begin @(posedge clk);@(negedge clk);end end
    #1;`CHECK(s_axi_wready);@(posedge clk);@(negedge clk);s_axi_wvalid=0;
    repeat(4) begin if(!chi_txdat_flitv_o) begin @(posedge clk);@(negedge clk);end end
    #1;`CHECK(chi_txdat_flit_o[24+:ChiDbidWidth]==8'ha5);`CHECK(chi_txdat_flit_o[64+:(ChiDataWidth/8)]==(1<<(AxiDataWidth/8))-1);`CHECK(chi_txdat_flit_o[128+:AxiDataWidth]==s_axi_wdata);
    chi_txdat_lcrdv_i=1;@(posedge clk);@(negedge clk);chi_txdat_lcrdv_i=0;rsp=0;rsp[3:0]=4'h3;send_rsp(rsp);
    repeat(4) begin if(!s_axi_bvalid) begin @(posedge clk);@(negedge clk);end end
    #1;`CHECK(s_axi_bvalid&&s_axi_bid==2'd1&&s_axi_bresp==2'b00);s_axi_bready=1;@(posedge clk);
    $display("PASS: top write AXI=%0db CHI=%0db smoke", AxiDataWidth, ChiDataWidth);$finish;
  end
endmodule
`default_nettype wire
`undef CHECK
