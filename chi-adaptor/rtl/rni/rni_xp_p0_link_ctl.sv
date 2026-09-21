// RNI P0 local-link controller skeleton.
//
// This module is the sole RNI-side owner of raw CHI P0 link state, including
// LinkActive and per-channel L-credit accounting. Transaction behavior and
// flit packing are intentionally deferred to later incremental RTL steps.

`default_nettype none

module rni_xp_p0_link_ctl #(
  parameter int unsigned ChieNidWidth = 7,
  parameter int unsigned ReqFlitWidth = 131,
  parameter int unsigned RspFlitWidth = 73,
  parameter int unsigned DatFlitWidth = 406,
  parameter int unsigned XpP0ReqRxDepth = 2,
  parameter int unsigned XpP0RspRxDepth = 2,
  parameter int unsigned XpP0DatRxDepth = 2,
  parameter bit LinkFlitpendEnable = 1'b0,
  parameter bit EnableExpCompack = 1'b0
) (
  input  logic                    clk,
  input  logic                    rst,

  // Core-to-link canonical CHI payloads. The link controller will own the
  // later conversion from these payloads to external XP flits.
  input  logic                    core_txreq_valid_i,
  input  logic [ReqFlitWidth-1:0] core_txreq_payload_i,
  output logic                    core_txreq_ready_o,
  input  logic                    core_txdat_valid_i,
  input  logic [DatFlitWidth-1:0] core_txdat_payload_i,
  output logic                    core_txdat_ready_o,
  input  logic                    core_txrsp_valid_i,
  input  logic [RspFlitWidth-1:0] core_txrsp_payload_i,
  output logic                    core_txrsp_ready_o,

  // Link-to-core canonical receive payloads.
  output logic                    core_rxrsp_valid_o,
  output logic [RspFlitWidth-1:0] core_rxrsp_payload_o,
  input  logic                    core_rxrsp_ready_i,
  output logic                    core_rxdat_valid_o,
  output logic [DatFlitWidth-1:0] core_rxdat_payload_o,
  input  logic                    core_rxdat_ready_i,

  // CSR-slave canonical boundary. Incoming REQ is accepted only by the
  // policy CSR slave in the first release. The controller will later decode
  // the fixed CSR address window before asserting csr_rxreq_valid_o.
  output logic                    csr_rxreq_valid_o,
  output logic [ReqFlitWidth-1:0] csr_rxreq_payload_o,
  input  logic                    csr_rxreq_ready_i,
  output logic                    csr_rxdat_valid_o,
  output logic [DatFlitWidth-1:0] csr_rxdat_payload_o,
  input  logic                    csr_rxdat_ready_i,
  input  logic                    csr_txrsp_valid_i,
  input  logic [RspFlitWidth-1:0] csr_txrsp_payload_i,
  output logic                    csr_txrsp_ready_o,
  input  logic                    csr_txdat_valid_i,
  input  logic [DatFlitWidth-1:0] csr_txdat_payload_i,
  output logic                    csr_txdat_ready_o,

  // RNI-to-XP P0 CHI REQ channel.
  output logic                    xp_rxreq_flitv_o,
  output logic [ReqFlitWidth-1:0] xp_rxreq_flit_o,
  input  logic                    xp_rxreq_lcrdv_i,

  // RNI-to-XP P0 CHI DAT channel.
  output logic                    xp_rxdat_flitv_o,
  output logic [DatFlitWidth-1:0] xp_rxdat_flit_o,
  input  logic                    xp_rxdat_lcrdv_i,

  // RNI-to-XP P0 CHI RSP channel. It remains idle while EnableExpCompack is
  // zero, but the physical channel is declared for the future CompAck step.
  output logic                    xp_rxrsp_flitv_o,
  output logic [RspFlitWidth-1:0] xp_rxrsp_flit_o,
  input  logic                    xp_rxrsp_lcrdv_i,

  // XP P0-to-RNI channels. The RXREQ path is reserved for the independent
  // CHI Device CSR slave; requester responses arrive on RSP/DAT.
  input  logic                    xp_txreq_flitv_i,
  input  logic [ReqFlitWidth-1:0] xp_txreq_flit_i,
  output logic                    xp_txreq_lcrdv_o,
  input  logic                    xp_txrsp_flitv_i,
  input  logic [RspFlitWidth-1:0] xp_txrsp_flit_i,
  output logic                    xp_txrsp_lcrdv_o,
  input  logic                    xp_txdat_flitv_i,
  input  logic [DatFlitWidth-1:0] xp_txdat_flit_i,
  output logic                    xp_txdat_lcrdv_o,

  // Bidirectional LinkActive handshake for the P0 local link.
  output logic                    rni_txlinkactivereq_o,
  input  logic                    rni_txlinkactiveack_i,
  input  logic                    rni_rxlinkactivereq_i,
  output logic                    rni_rxlinkactiveack_o
);

  localparam int unsigned ReqCreditWidth = $clog2(XpP0ReqRxDepth + 1);
  localparam int unsigned RspCreditWidth = $clog2(XpP0RspRxDepth + 1);
  localparam int unsigned DatCreditWidth = $clog2(XpP0DatRxDepth + 1);

  typedef enum logic [1:0] {
    kLinkReset,
    kLinkWaitPeerRequest,
    kLinkWaitPeerAcknowledge,
    kLinkRun
  } link_state_t;

  // Sequential state: reset asynchronously asserts these registers; their
  // release and all later updates occur synchronously on clk.
  link_state_t link_state_q;
  logic        link_run_q;
  logic        txlinkactivereq_q;
  logic        rxlinkactiveack_q;

  // Sequential outbound-credit state. Each counter increments only on an XP
  // L-credit pulse and decrements only when its matching external flit sends.
  logic [ReqCreditWidth-1:0] txreq_credit_q;
  logic [DatCreditWidth-1:0] txdat_credit_q;
  logic [RspCreditWidth-1:0] txrsp_credit_q;

  // Sequential receive ownership placeholders. Exact FIFO depth and payload
  // storage are implemented only after the REQ/RSP/DAT credit substeps begin.
  logic csr_rxreq_buffer_valid_q;
  logic [ReqFlitWidth-1:0] csr_rxreq_buffer_q;
  logic csr_rxdat_buffer_valid_q;
  logic [DatFlitWidth-1:0] csr_rxdat_buffer_q;
  logic rxrsp_buffer_valid_q;
  logic [RspFlitWidth-1:0] rxrsp_buffer_q;
  logic rxdat_buffer_valid_q;
  logic [DatFlitWidth-1:0] rxdat_buffer_q;
  logic req_send_fire;
  logic dat_send_fire;
  logic rsp_send_fire;
  logic csr_txrsp_selected;
  logic csr_txdat_selected;
  logic rxreq_accept;
  logic rxrsp_accept;
  logic rxdat_accept;

  always_comb begin
    csr_txrsp_selected = csr_txrsp_valid_i;
    csr_txdat_selected = csr_txdat_valid_i;

    xp_rxreq_flitv_o = link_run_q && core_txreq_valid_i &&
                       (txreq_credit_q != '0);
    xp_rxreq_flit_o = core_txreq_payload_i;
    core_txreq_ready_o = xp_rxreq_flitv_o;
    req_send_fire = xp_rxreq_flitv_o;

    xp_rxdat_flitv_o = link_run_q &&
                       (csr_txdat_valid_i || core_txdat_valid_i) &&
                       (txdat_credit_q != '0);
    xp_rxdat_flit_o = csr_txdat_selected ? csr_txdat_payload_i :
                                           core_txdat_payload_i;
    csr_txdat_ready_o = xp_rxdat_flitv_o && csr_txdat_selected;
    core_txdat_ready_o = xp_rxdat_flitv_o && !csr_txdat_selected;
    dat_send_fire = xp_rxdat_flitv_o;

    xp_rxrsp_flitv_o = link_run_q &&
                       (csr_txrsp_valid_i ||
                        (EnableExpCompack && core_txrsp_valid_i)) &&
                       (txrsp_credit_q != '0);
    xp_rxrsp_flit_o = csr_txrsp_selected ? csr_txrsp_payload_i :
                                           core_txrsp_payload_i;
    csr_txrsp_ready_o = xp_rxrsp_flitv_o && csr_txrsp_selected;
    core_txrsp_ready_o = xp_rxrsp_flitv_o && !csr_txrsp_selected;
    rsp_send_fire = xp_rxrsp_flitv_o;

    csr_rxreq_valid_o = csr_rxreq_buffer_valid_q;
    csr_rxreq_payload_o = csr_rxreq_buffer_q;
    rxreq_accept = link_run_q && xp_txreq_flitv_i &&
                   (!csr_rxreq_buffer_valid_q || csr_rxreq_ready_i);
    xp_txreq_lcrdv_o = rxreq_accept;

    core_rxrsp_valid_o = rxrsp_buffer_valid_q;
    core_rxrsp_payload_o = rxrsp_buffer_q;
    rxrsp_accept = link_run_q && xp_txrsp_flitv_i &&
                   (!rxrsp_buffer_valid_q || core_rxrsp_ready_i);
    xp_txrsp_lcrdv_o = rxrsp_accept;

    core_rxdat_valid_o = rxdat_buffer_valid_q;
    core_rxdat_payload_o = rxdat_buffer_q;
    csr_rxdat_valid_o = csr_rxdat_buffer_valid_q;
    csr_rxdat_payload_o = csr_rxdat_buffer_q;
    rxdat_accept = link_run_q && xp_txdat_flitv_i &&
                   (!rxdat_buffer_valid_q || core_rxdat_ready_i);
    xp_txdat_lcrdv_o = rxdat_accept;

    rni_txlinkactivereq_o = txlinkactivereq_q;
    rni_rxlinkactiveack_o = rxlinkactiveack_q;
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      link_state_q <= kLinkReset;
      link_run_q <= 1'b0;
      txlinkactivereq_q <= 1'b0;
      rxlinkactiveack_q <= 1'b0;
      txreq_credit_q <= '0;
      txdat_credit_q <= '0;
      txrsp_credit_q <= '0;
      csr_rxreq_buffer_valid_q <= 1'b0;
      csr_rxreq_buffer_q <= '0;
      csr_rxdat_buffer_valid_q <= 1'b0;
      csr_rxdat_buffer_q <= '0;
      rxrsp_buffer_valid_q <= 1'b0;
      rxrsp_buffer_q <= '0;
      rxdat_buffer_valid_q <= 1'b0;
      rxdat_buffer_q <= '0;
    end else begin
      unique case (link_state_q)
        kLinkReset: begin
          txlinkactivereq_q <= 1'b1;
          rxlinkactiveack_q <= rni_rxlinkactivereq_i;
          link_run_q <= 1'b0;
          link_state_q <= kLinkWaitPeerRequest;
        end
        kLinkWaitPeerRequest: begin
          rxlinkactiveack_q <= rni_rxlinkactivereq_i;
          if (rni_rxlinkactivereq_i) begin
            link_state_q <= kLinkWaitPeerAcknowledge;
          end
        end
        kLinkWaitPeerAcknowledge: begin
          rxlinkactiveack_q <= rni_rxlinkactivereq_i;
          if (rni_txlinkactiveack_i) begin
            link_state_q <= kLinkRun;
            link_run_q <= 1'b1;
          end
        end
        kLinkRun: begin
          if (!rni_rxlinkactivereq_i || !rni_txlinkactiveack_i) begin
            link_state_q <= kLinkWaitPeerRequest;
            link_run_q <= 1'b0;
            rxlinkactiveack_q <= rni_rxlinkactivereq_i;
          end
        end
        default: begin
          link_state_q <= kLinkReset;
          link_run_q <= 1'b0;
        end
      endcase

      if (xp_rxreq_lcrdv_i && !req_send_fire &&
          (txreq_credit_q != XpP0ReqRxDepth[ReqCreditWidth-1:0])) begin
        txreq_credit_q <= txreq_credit_q + 1'b1;
      end else if (!xp_rxreq_lcrdv_i && req_send_fire) begin
        txreq_credit_q <= txreq_credit_q - 1'b1;
      end

      if (xp_rxdat_lcrdv_i && !dat_send_fire &&
          (txdat_credit_q != XpP0DatRxDepth[DatCreditWidth-1:0])) begin
        txdat_credit_q <= txdat_credit_q + 1'b1;
      end else if (!xp_rxdat_lcrdv_i && dat_send_fire) begin
        txdat_credit_q <= txdat_credit_q - 1'b1;
      end

      if (xp_rxrsp_lcrdv_i && !rsp_send_fire &&
          (txrsp_credit_q != XpP0RspRxDepth[RspCreditWidth-1:0])) begin
        txrsp_credit_q <= txrsp_credit_q + 1'b1;
      end else if (!xp_rxrsp_lcrdv_i && rsp_send_fire) begin
        txrsp_credit_q <= txrsp_credit_q - 1'b1;
      end

      if (csr_rxreq_valid_o && csr_rxreq_ready_i) begin
        csr_rxreq_buffer_valid_q <= 1'b0;
      end
      if (rxreq_accept) begin
        csr_rxreq_buffer_valid_q <= 1'b1;
        csr_rxreq_buffer_q <= xp_txreq_flit_i;
      end

      if (core_rxrsp_valid_o && core_rxrsp_ready_i) begin
        rxrsp_buffer_valid_q <= 1'b0;
      end
      if (rxrsp_accept) begin
        rxrsp_buffer_valid_q <= 1'b1;
        rxrsp_buffer_q <= xp_txrsp_flit_i;
      end

      if (core_rxdat_valid_o && core_rxdat_ready_i) begin
        rxdat_buffer_valid_q <= 1'b0;
      end
      if (rxdat_accept) begin
        rxdat_buffer_valid_q <= 1'b1;
        rxdat_buffer_q <= xp_txdat_flit_i;
      end

      if (csr_rxdat_valid_o && csr_rxdat_ready_i) begin
        csr_rxdat_buffer_valid_q <= 1'b0;
      end
    end
  end

endmodule

`default_nettype wire
