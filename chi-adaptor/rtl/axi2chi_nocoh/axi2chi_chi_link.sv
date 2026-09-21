// Profile-neutral CHI transport owner skeleton.

`default_nettype none

module axi2chi_chi_link #(
  parameter int unsigned ReqFlitWidth = 131,
  parameter int unsigned RspFlitWidth = 73,
  parameter int unsigned DatFlitWidth = 406,
  parameter int unsigned ReqRxDepth = 2,
  parameter int unsigned RspRxDepth = 2,
  parameter int unsigned DatRxDepth = 2
) (
  input logic clk,
  input logic rst,
  input logic core_txreq_valid_i,
  input logic [ReqFlitWidth-1:0] core_txreq_flit_i,
  output logic core_txreq_ready_o,
  input logic core_txdat_valid_i,
  input logic [DatFlitWidth-1:0] core_txdat_flit_i,
  output logic core_txdat_ready_o,
  output logic core_rxrsp_valid_o,
  output logic [RspFlitWidth-1:0] core_rxrsp_flit_o,
  input logic core_rxrsp_ready_i,
  output logic core_rxdat_valid_o,
  output logic [DatFlitWidth-1:0] core_rxdat_flit_o,
  input logic core_rxdat_ready_i,
  output logic chi_txreq_flitv_o,
  output logic [ReqFlitWidth-1:0] chi_txreq_flit_o,
  input logic chi_txreq_lcrdv_i,
  output logic chi_txdat_flitv_o,
  output logic [DatFlitWidth-1:0] chi_txdat_flit_o,
  input logic chi_txdat_lcrdv_i,
  output logic chi_txrsp_flitv_o,
  output logic [RspFlitWidth-1:0] chi_txrsp_flit_o,
  input logic chi_txrsp_lcrdv_i,
  input logic chi_rxrsp_flitv_i,
  input logic [RspFlitWidth-1:0] chi_rxrsp_flit_i,
  output logic chi_rxrsp_lcrdv_o,
  input logic chi_rxdat_flitv_i,
  input logic [DatFlitWidth-1:0] chi_rxdat_flit_i,
  output logic chi_rxdat_lcrdv_o,
  output logic chi_txlinkactivereq_o,
  input logic chi_txlinkactiveack_i,
  input logic chi_rxlinkactivereq_i,
  output logic chi_rxlinkactiveack_o
);

  typedef enum logic [1:0] {
    kLinkReset,
    kLinkActivate,
    kLinkRun,
    kLinkDrain
  } link_state_t;

  link_state_t link_state_q;
  logic tx_link_active_req_q;
  logic rx_link_active_ack_q;
  logic [$clog2(ReqRxDepth + 1)-1:0] txreq_credit_q;
  logic [$clog2(DatRxDepth + 1)-1:0] txdat_credit_q;
  logic [$clog2(RspRxDepth + 1)-1:0] txrsp_credit_q;

  // Child transport modules are connected in a later incremental implementation.

endmodule

`default_nettype wire
