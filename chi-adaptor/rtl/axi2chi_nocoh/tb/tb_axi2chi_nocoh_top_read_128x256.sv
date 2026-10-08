`timescale 1ns/1ps
`default_nettype none

`define CHECK(condition) if (!(condition)) $fatal(1, "CHECK failed: %s", `"condition`")

module tb_axi2chi_nocoh_top_read_128x256 #(
  parameter int unsigned CacheLineBytes = 64,
  parameter int unsigned AxiDataWidth = 128,
  parameter int unsigned ChiDataWidth = 256
);
  localparam int unsigned AxiAddrWidth = 32;
  localparam int unsigned AxiIdWidth = 2;
  localparam int unsigned ChiTxnidWidth = 8;
  localparam int unsigned ChiDbidWidth = 8;
  localparam int unsigned ReqFlitWidth = 128;
  localparam int unsigned RspFlitWidth = 64;
  localparam int unsigned DatFlitWidth = 384;
  localparam int unsigned ParentEntries = 4;
  localparam int unsigned ChildEntries = 4;
  localparam int unsigned DataIdWidth =
      ((CacheLineBytes / (ChiDataWidth / 8)) > 1) ?
          $clog2(CacheLineBytes / (ChiDataWidth / 8)) : 1;

  logic clk = 1'b0;
  logic aresetn = 1'b0;
  logic [AxiIdWidth-1:0] s_axi_awid, s_axi_bid, s_axi_arid, s_axi_rid;
  logic [AxiAddrWidth-1:0] s_axi_awaddr, s_axi_araddr;
  logic [7:0] s_axi_awlen, s_axi_arlen;
  logic [2:0] s_axi_awsize, s_axi_arsize;
  logic [1:0] s_axi_awburst, s_axi_arburst;
  logic s_axi_awvalid, s_axi_awready, s_axi_wlast, s_axi_wvalid, s_axi_wready;
  logic [AxiDataWidth-1:0] s_axi_wdata, s_axi_rdata;
  logic [AxiDataWidth / 8-1:0] s_axi_wstrb;
  logic [1:0] s_axi_bresp, s_axi_rresp;
  logic s_axi_bvalid, s_axi_bready, s_axi_arvalid, s_axi_arready;
  logic s_axi_rlast, s_axi_rvalid, s_axi_rready;
  logic chi_txreq_flitv_o, chi_txreq_lcrdv_i;
  logic [ReqFlitWidth-1:0] chi_txreq_flit_o;
  logic chi_txdat_flitv_o, chi_txdat_lcrdv_i;
  logic [DatFlitWidth-1:0] chi_txdat_flit_o;
  logic chi_txrsp_flitv_o, chi_txrsp_lcrdv_i;
  logic [RspFlitWidth-1:0] chi_txrsp_flit_o;
  logic chi_rxrsp_flitv_i, chi_rxrsp_lcrdv_o;
  logic [RspFlitWidth-1:0] chi_rxrsp_flit_i;
  logic chi_rxdat_flitv_i, chi_rxdat_lcrdv_o;
  logic [DatFlitWidth-1:0] chi_rxdat_flit_i;
  logic chi_txlinkactivereq_o, chi_txlinkactiveack_i;
  logic chi_rxlinkactivereq_i, chi_rxlinkactiveack_o;
  logic [ChiTxnidWidth-1:0] txnid;
  logic [AxiDataWidth-1:0] expected_rdata;

  axi2chi_nocoh_top #(
    .AxiAddrWidth(AxiAddrWidth), .AxiDataWidth(AxiDataWidth),
    .AxiIdWidth(AxiIdWidth), .ChiTxnidWidth(ChiTxnidWidth),
    .ChiDbidWidth(ChiDbidWidth), .ChiDataWidth(ChiDataWidth),
    .ParentEntries(ParentEntries), .ChildEntries(ChildEntries),
    .ReqFlitWidth(ReqFlitWidth), .RspFlitWidth(RspFlitWidth),
    .DatFlitWidth(DatFlitWidth), .CacheLineBytes(CacheLineBytes)
  ) dut (.*);

  always #5 clk = ~clk;

  initial begin
    s_axi_awid = '0; s_axi_awaddr = '0; s_axi_awlen = '0; s_axi_awsize = '0;
    expected_rdata = 128'h1122_3344_5566_7788_99aa_bbcc_ddee_ff00;
    s_axi_awburst = '0; s_axi_awvalid = 1'b0; s_axi_wdata = '0; s_axi_wstrb = '0;
    s_axi_wlast = 1'b0; s_axi_wvalid = 1'b0; s_axi_bready = 1'b1;
    s_axi_arid = 2'd1; s_axi_araddr = 32'h0000_1000; s_axi_arlen = '0;
    s_axi_arsize = $clog2(AxiDataWidth / 8); s_axi_arburst = 2'b01; s_axi_arvalid = 1'b0;
    s_axi_rready = 1'b0; chi_txreq_lcrdv_i = 1'b0; chi_txdat_lcrdv_i = 1'b0;
    chi_txrsp_lcrdv_i = 1'b0; chi_rxrsp_flitv_i = 1'b0; chi_rxrsp_flit_i = '0;
    chi_rxdat_flitv_i = 1'b0; chi_rxdat_flit_i = '0; chi_txlinkactiveack_i = 1'b0;
    chi_rxlinkactivereq_i = 1'b1;

    @(negedge clk); aresetn = 1'b1;
    @(posedge clk); @(negedge clk); chi_txlinkactiveack_i = 1'b1;
    @(posedge clk); @(negedge clk);
    s_axi_arvalid = 1'b1; #1; `CHECK(s_axi_arready);
    @(posedge clk); @(negedge clk); s_axi_arvalid = 1'b0;
    repeat (4) begin if (!chi_txreq_flitv_o) begin @(posedge clk); @(negedge clk); end end
    #1; `CHECK(chi_txreq_flitv_o);
    `CHECK(chi_txreq_flit_o[32 +: AxiAddrWidth] == 32'h0000_1000);
    txnid = chi_txreq_flit_o[16 +: ChiTxnidWidth];
    chi_txreq_lcrdv_i = 1'b1; @(posedge clk); @(negedge clk); chi_txreq_lcrdv_i = 1'b0;
    chi_rxdat_flit_i = '0;
    chi_rxdat_flit_i[8 +: ChiTxnidWidth] = txnid;
    chi_rxdat_flit_i[24 +: DataIdWidth] = '0;
    chi_rxdat_flit_i[27 +: 2] = 2'b00;
    chi_rxdat_flit_i[32 +: (ChiDataWidth / 8)] =
        (1 << (AxiDataWidth / 8)) - 1;
    chi_rxdat_flit_i[64 +: ChiDataWidth] =
        256'h0000_0000_0000_0000_0000_0000_0000_0000_1122_3344_5566_7788_99aa_bbcc_ddee_ff00;
    chi_rxdat_flitv_i = 1'b1; #1; `CHECK(chi_rxdat_lcrdv_o);
    @(posedge clk); @(negedge clk); chi_rxdat_flitv_i = 1'b0;
    repeat (5) begin if (!s_axi_rvalid) begin @(posedge clk); @(negedge clk); end end
    #1;
    `CHECK(s_axi_rvalid && s_axi_rid == 2'd1 && s_axi_rresp == 2'b00 && s_axi_rlast);
    `CHECK(s_axi_rdata == expected_rdata);
    s_axi_rready = 1'b1; @(posedge clk);
    $display("PASS: top read AXI=%0db CHI=%0db, line=%0dB", AxiDataWidth,
             ChiDataWidth, CacheLineBytes);
    $finish;
  end
endmodule

`default_nettype wire
`undef CHECK
