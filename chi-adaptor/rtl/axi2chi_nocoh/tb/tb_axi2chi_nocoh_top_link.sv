`timescale 1ns/1ps
`default_nettype none

`define CHECK(condition) \
  if (!(condition)) begin \
    $fatal(1, "CHECK failed: %s", `"condition`"); \
  end

module tb_axi2chi_nocoh_top_link;
  localparam int unsigned AxiAddrWidth = 32;
  localparam int unsigned AxiDataWidth = 64;
  localparam int unsigned AxiIdWidth = 2;
  localparam int unsigned ReqFlitWidth = 32;
  localparam int unsigned RspFlitWidth = 16;
  localparam int unsigned DatFlitWidth = 64;

  logic clk = 1'b0;
  logic aresetn = 1'b0;
  logic [AxiIdWidth-1:0] s_axi_awid;
  logic [AxiAddrWidth-1:0] s_axi_awaddr;
  logic [7:0] s_axi_awlen;
  logic [2:0] s_axi_awsize;
  logic [1:0] s_axi_awburst;
  logic s_axi_awvalid;
  logic s_axi_awready;
  logic [AxiDataWidth-1:0] s_axi_wdata;
  logic [AxiDataWidth / 8-1:0] s_axi_wstrb;
  logic s_axi_wlast;
  logic s_axi_wvalid;
  logic s_axi_wready;
  logic [AxiIdWidth-1:0] s_axi_bid;
  logic [1:0] s_axi_bresp;
  logic s_axi_bvalid;
  logic s_axi_bready;
  logic [AxiIdWidth-1:0] s_axi_arid;
  logic [AxiAddrWidth-1:0] s_axi_araddr;
  logic [7:0] s_axi_arlen;
  logic [2:0] s_axi_arsize;
  logic [1:0] s_axi_arburst;
  logic s_axi_arvalid;
  logic s_axi_arready;
  logic [AxiIdWidth-1:0] s_axi_rid;
  logic [AxiDataWidth-1:0] s_axi_rdata;
  logic [1:0] s_axi_rresp;
  logic s_axi_rlast;
  logic s_axi_rvalid;
  logic s_axi_rready;
  logic chi_txreq_flitv_o;
  logic [ReqFlitWidth-1:0] chi_txreq_flit_o;
  logic chi_txreq_lcrdv_i;
  logic chi_txdat_flitv_o;
  logic [DatFlitWidth-1:0] chi_txdat_flit_o;
  logic chi_txdat_lcrdv_i;
  logic chi_txrsp_flitv_o;
  logic [RspFlitWidth-1:0] chi_txrsp_flit_o;
  logic chi_txrsp_lcrdv_i;
  logic chi_rxrsp_flitv_i;
  logic [RspFlitWidth-1:0] chi_rxrsp_flit_i;
  logic chi_rxrsp_lcrdv_o;
  logic chi_rxdat_flitv_i;
  logic [DatFlitWidth-1:0] chi_rxdat_flit_i;
  logic chi_rxdat_lcrdv_o;
  logic chi_txlinkactivereq_o;
  logic chi_txlinkactiveack_i;
  logic chi_rxlinkactivereq_i;
  logic chi_rxlinkactiveack_o;

  axi2chi_nocoh_top #(
    .AxiAddrWidth(AxiAddrWidth),
    .AxiDataWidth(AxiDataWidth),
    .AxiIdWidth(AxiIdWidth),
    .ReqFlitWidth(ReqFlitWidth),
    .RspFlitWidth(RspFlitWidth),
    .DatFlitWidth(DatFlitWidth)
  ) dut (.*);

  always #5 clk = ~clk;

  initial begin
    s_axi_awid = '0;
    s_axi_awaddr = '0;
    s_axi_awlen = '0;
    s_axi_awsize = '0;
    s_axi_awburst = '0;
    s_axi_awvalid = 1'b1;
    s_axi_wdata = '0;
    s_axi_wstrb = '0;
    s_axi_wlast = 1'b0;
    s_axi_wvalid = 1'b1;
    s_axi_bready = 1'b1;
    s_axi_arid = '0;
    s_axi_araddr = '0;
    s_axi_arlen = '0;
    s_axi_arsize = '0;
    s_axi_arburst = '0;
    s_axi_arvalid = 1'b1;
    s_axi_rready = 1'b1;
    chi_txreq_lcrdv_i = 1'b0;
    chi_txdat_lcrdv_i = 1'b0;
    chi_txrsp_lcrdv_i = 1'b0;
    chi_rxrsp_flitv_i = 1'b0;
    chi_rxrsp_flit_i = '0;
    chi_rxdat_flitv_i = 1'b0;
    chi_rxdat_flit_i = '0;
    chi_txlinkactiveack_i = 1'b0;
    chi_rxlinkactivereq_i = 1'b0;

    #1;
    `CHECK(!s_axi_awready);
    `CHECK(!s_axi_wready);
    `CHECK(!s_axi_arready);
    `CHECK(!s_axi_bvalid);
    `CHECK(!s_axi_rvalid);
    `CHECK(!chi_txlinkactivereq_o);

    @(negedge clk);
    aresetn = 1'b1;
    @(posedge clk);
    @(negedge clk);
    #1;
    `CHECK(chi_txlinkactivereq_o);
    `CHECK(!chi_txreq_flitv_o);
    `CHECK(!chi_txdat_flitv_o);
    `CHECK(!chi_txrsp_flitv_o);
    `CHECK(chi_txrsp_flit_o == '0);
    `CHECK(!s_axi_awready);
    `CHECK(!s_axi_arready);

    chi_txlinkactiveack_i = 1'b1;
    chi_rxlinkactivereq_i = 1'b1;
    @(posedge clk);
    @(negedge clk);
    #1;
    `CHECK(chi_rxlinkactiveack_o);
    `CHECK(chi_rxrsp_lcrdv_o);
    `CHECK(chi_rxdat_lcrdv_o);
    `CHECK(!chi_txreq_flitv_o);
    `CHECK(!chi_txdat_flitv_o);

    chi_rxrsp_flit_i = 16'hcafe;
    chi_rxrsp_flitv_i = 1'b1;
    @(posedge clk);
    @(negedge clk);
    chi_rxrsp_flitv_i = 1'b0;
    #1;
    `CHECK(chi_rxrsp_lcrdv_o);

    $display("PASS: top-level CHI link integration shell");
    $finish;
  end
endmodule

`default_nettype wire

`undef CHECK
