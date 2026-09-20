// AXI-to-CHI RNI integration skeleton.
//
// This top-level declares the immutable integration boundary only. It does
// not instantiate or connect its children until the P0 canonical flit packing
// and each child interface are verified in their own implementation step.

`default_nettype none

module rni_axi_chi_top #(
  parameter int unsigned AxiAddrWidth = 64,
  parameter int unsigned AxiDataWidth = 32,
  parameter int unsigned AxiIdWidth = 4,
  parameter int unsigned AxlenWidth = 8,
  parameter int unsigned AxsizeWidth = 3,
  parameter int unsigned RegionEntries = 32,
  parameter int unsigned ChieNidWidth = 7,
  parameter int unsigned ReqFlitWidth = 131,
  parameter int unsigned RspFlitWidth = 73,
  parameter int unsigned DatFlitWidth = 406,
  parameter logic [AxiAddrWidth-1:0] PolicyCsrBase =
      64'h0000_0020_0000_0000,
  parameter logic [AxiAddrWidth-1:0] PolicyCsrSize =
      64'h0000_0000_0000_1000
) (
  input  logic                         aclk,
  input  logic                         aresetn,

  // AXI4 slave interface: connected by final system integration to the BFM.
  input  logic [AxiIdWidth-1:0]        s_axi_awid,
  input  logic [AxiAddrWidth-1:0]      s_axi_awaddr,
  input  logic [AxlenWidth-1:0]        s_axi_awlen,
  input  logic [AxsizeWidth-1:0]       s_axi_awsize,
  input  logic [1:0]                   s_axi_awburst,
  input  logic                         s_axi_awvalid,
  output logic                         s_axi_awready,
  input  logic [AxiDataWidth-1:0]      s_axi_wdata,
  input  logic [AxiDataWidth / 8-1:0]  s_axi_wstrb,
  input  logic                         s_axi_wlast,
  input  logic                         s_axi_wvalid,
  output logic                         s_axi_wready,
  output logic [AxiIdWidth-1:0]        s_axi_bid,
  output logic [1:0]                   s_axi_bresp,
  output logic                         s_axi_bvalid,
  input  logic                         s_axi_bready,
  input  logic [AxiIdWidth-1:0]        s_axi_arid,
  input  logic [AxiAddrWidth-1:0]      s_axi_araddr,
  input  logic [AxlenWidth-1:0]        s_axi_arlen,
  input  logic [AxsizeWidth-1:0]       s_axi_arsize,
  input  logic [1:0]                   s_axi_arburst,
  input  logic                         s_axi_arvalid,
  output logic                         s_axi_arready,
  output logic [AxiIdWidth-1:0]        s_axi_rid,
  output logic [AxiDataWidth-1:0]      s_axi_rdata,
  output logic [1:0]                   s_axi_rresp,
  output logic                         s_axi_rlast,
  output logic                         s_axi_rvalid,
  input  logic                         s_axi_rready,

  // Raw P0 CHI local-link boundary. rni_xp_p0_link_ctl is the eventual sole
  // owner of these signals; top-level contains no raw-link behavior.
  output logic                         xp_rxreq_flitv_o,
  output logic [ReqFlitWidth-1:0]      xp_rxreq_flit_o,
  input  logic                         xp_rxreq_lcrdv_i,
  output logic                         xp_rxrsp_flitv_o,
  output logic [RspFlitWidth-1:0]      xp_rxrsp_flit_o,
  input  logic                         xp_rxrsp_lcrdv_i,
  output logic                         xp_rxdat_flitv_o,
  output logic [DatFlitWidth-1:0]      xp_rxdat_flit_o,
  input  logic                         xp_rxdat_lcrdv_i,
  input  logic                         xp_txreq_flitv_i,
  input  logic [ReqFlitWidth-1:0]      xp_txreq_flit_i,
  output logic                         xp_txreq_lcrdv_o,
  input  logic                         xp_txrsp_flitv_i,
  input  logic [RspFlitWidth-1:0]      xp_txrsp_flit_i,
  output logic                         xp_txrsp_lcrdv_o,
  input  logic                         xp_txdat_flitv_i,
  input  logic [DatFlitWidth-1:0]      xp_txdat_flit_i,
  output logic                         xp_txdat_lcrdv_o,
  output logic                         txlinkactivereq_o,
  input  logic                         txlinkactiveack_i,
  input  logic                         rxlinkactivereq_i,
  output logic                         rxlinkactiveack_o
);

  // Future instances: rni_axi_ingress, rni_core, policy_csr_chi_slave and
  // rni_xp_p0_link_ctl. No assign/always block is legal in this skeleton;
  // an undriven output must not be mistaken for a defined reset behavior.

endmodule

`default_nettype wire
