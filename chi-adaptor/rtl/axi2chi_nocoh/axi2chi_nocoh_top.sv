// AXI-to-CHI non-coherent bridge top-level skeleton.
// This module intentionally declares no functional logic or child instances.

`default_nettype none

module axi2chi_nocoh_top #(
  parameter int unsigned AxiAddrWidth = 64,
  parameter int unsigned AxiDataWidth = 128,
  parameter int unsigned AxiIdWidth = 4,
  parameter int unsigned AxlenWidth = 8,
  parameter int unsigned AxsizeWidth = 3,
  parameter int unsigned ChiNidWidth = 7,
  parameter int unsigned ChiTxnidWidth = 12,
  parameter int unsigned ChiDbidWidth = 12,
  parameter int unsigned ChiDataWidth = 256,
  parameter int unsigned CacheLineBytes = 64,
  parameter int unsigned ParentEntries = 16,
  parameter int unsigned ChildEntries = 16,
  parameter int unsigned ReqFlitWidth = 131,
  parameter int unsigned RspFlitWidth = 73,
  parameter int unsigned DatFlitWidth = 406
) (
  input  logic                         clk,
  input  logic                         aresetn,

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

  output logic                         chi_txreq_flitv_o,
  output logic [ReqFlitWidth-1:0]      chi_txreq_flit_o,
  input  logic                         chi_txreq_lcrdv_i,
  output logic                         chi_txdat_flitv_o,
  output logic [DatFlitWidth-1:0]      chi_txdat_flit_o,
  input  logic                         chi_txdat_lcrdv_i,
  output logic                         chi_txrsp_flitv_o,
  output logic [RspFlitWidth-1:0]      chi_txrsp_flit_o,
  input  logic                         chi_txrsp_lcrdv_i,
  input  logic                         chi_rxrsp_flitv_i,
  input  logic [RspFlitWidth-1:0]      chi_rxrsp_flit_i,
  output logic                         chi_rxrsp_lcrdv_o,
  input  logic                         chi_rxdat_flitv_i,
  input  logic [DatFlitWidth-1:0]      chi_rxdat_flit_i,
  output logic                         chi_rxdat_lcrdv_o,
  output logic                         chi_txlinkactivereq_o,
  input  logic                         chi_txlinkactiveack_i,
  input  logic                         chi_rxlinkactivereq_i,
  output logic                         chi_rxlinkactiveack_o
);

  localparam int unsigned AxiStrbWidth = AxiDataWidth / 8;
  localparam int unsigned ChiBeWidth = ChiDataWidth / 8;
  localparam int unsigned ParentIndexWidth = $clog2(ParentEntries);
  localparam int unsigned ChildIndexWidth = $clog2(ChildEntries);

  // Canonical internal boundaries are declared here for the later integration step.
  logic rst;
  logic core_txreq_valid;
  logic [ReqFlitWidth-1:0] core_txreq_payload;
  logic core_txreq_ready;
  logic core_txdat_valid;
  logic [DatFlitWidth-1:0] core_txdat_payload;
  logic core_txdat_ready;
  logic core_rxrsp_valid;
  logic [RspFlitWidth-1:0] core_rxrsp_payload;
  logic core_rxrsp_ready;
  logic core_rxdat_valid;
  logic [DatFlitWidth-1:0] core_rxdat_payload;
  logic core_rxdat_ready;

  // Child instances are added only after each boundary is verified in Step 4.

endmodule

`default_nettype wire
