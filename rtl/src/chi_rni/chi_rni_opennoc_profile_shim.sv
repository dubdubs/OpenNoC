// Copyright 2026
//
// OpenNoC wire-profile shim for chi_rni.  This module is deliberately the
// only place that knows the OpenNoC CHI-E bit layout.  chi_rni itself stays a
// decoded-channel transaction engine and can therefore be reused with a
// different link profile.

`include "chi_rni_defines.svh"

module chi_rni_opennoc_profile_shim #(
    // OpenNoC RNI profile constants.  The elaboration checks below make an
    // accidental connection to a different CHI profile fail deterministically.
    parameter int unsigned NID_WIDTH        = 11,
    parameter int unsigned ADDR_WIDTH       = 44,
    parameter int unsigned DATA_WIDTH       = 256,
    parameter int unsigned TXNID_WIDTH      = 12,
    parameter int unsigned DBID_WIDTH       = 12,
    parameter int unsigned DATAID_WIDTH     = 2,
    parameter int unsigned TX_REQ_CREDITS   = 4,
    parameter int unsigned TX_DAT_CREDITS   = 4,
    parameter int unsigned RX_RSP_CREDITS   = 4,
    parameter int unsigned RX_DAT_CREDITS   = 4,
    parameter logic [NID_WIDTH-1:0] RNI_NODE_ID = '0,
    parameter logic [NID_WIDTH-1:0] DEFAULT_HN_NODE_ID = '0,
    parameter logic [NID_WIDTH-1:0] RETURN_NODE_ID = '0,
    parameter int unsigned RAW_REQ_WIDTH = ADDR_WIDTH + 3 * NID_WIDTH + 66,
    parameter int unsigned RAW_RSP_WIDTH = 2 * NID_WIDTH + 51,
    parameter int unsigned RAW_DAT_WIDTH = 3 * NID_WIDTH + DATA_WIDTH +
                                             DATA_WIDTH / 8 + DATA_WIDTH / 32 +
                                             DATA_WIDTH / 128 + 51
) (
    input  logic clk,
    input  logic rst_n,

    // OpenNoC LinkActive handshake.
    output logic tx_linkactive_req,
    input  logic tx_linkactive_ack,
    input  logic rx_linkactive_req,
    output logic rx_linkactive_ack,
    output logic core_link_active,
    output logic link_epoch,

    // OpenNoC raw REQ and DAT transmit channels plus returned L-credits.
    output logic                     txreq_flitv,
    output logic                     txreq_flitpend,
    output logic [RAW_REQ_WIDTH-1:0] txreq_flit,
    input  logic                     txreq_lcrdv,
    output logic                     txdat_flitv,
    output logic                     txdat_flitpend,
    output logic [RAW_DAT_WIDTH-1:0] txdat_flit,
    input  logic                     txdat_lcrdv,

    // OpenNoC raw RSP and DAT receive channels plus L-credit returns.
    input  logic                     rxrsp_flitv,
    input  logic                     rxrsp_flitpend,
    input  logic [RAW_RSP_WIDTH-1:0] rxrsp_flit,
    output logic                     rxrsp_lcrdv,
    input  logic                     rxdat_flitv,
    input  logic                     rxdat_flitpend,
    input  logic [RAW_DAT_WIDTH-1:0] rxdat_flit,
    output logic                     rxdat_lcrdv,

    // Decoded core REQ channel.
    input  logic                    core_txreq_valid,
    output logic                    core_txreq_ready,
    input  logic [6:0]              core_txreq_opcode,
    input  logic [ADDR_WIDTH-1:0]   core_txreq_addr,
    input  logic [2:0]              core_txreq_size,
    input  logic [TXNID_WIDTH-1:0]  core_txreq_txnid,
    input  logic                    core_txreq_device,
    input  logic                    core_txreq_ns,
    input  logic [1:0]              core_txreq_order,
    input  logic [3:0]              core_txreq_qos,
    input  logic                    core_txreq_allow_retry,

    // Decoded core RSP receive channel.
    output logic                    core_rxrsp_valid,
    input  logic                    core_rxrsp_ready,
    output logic [TXNID_WIDTH-1:0]  core_rxrsp_txnid,
    output logic [1:0]              core_rxrsp_kind,
    output logic [DBID_WIDTH-1:0]   core_rxrsp_dbid,
    output logic [1:0]              core_rxrsp_resp_err,

    // Decoded core DAT receive channel.
    output logic                    core_rxdat_valid,
    input  logic                    core_rxdat_ready,
    output logic [TXNID_WIDTH-1:0]  core_rxdat_txnid,
    output logic [DATAID_WIDTH-1:0] core_rxdat_data_id,
    output logic [DATA_WIDTH-1:0]   core_rxdat_data,
    output logic [1:0]              core_rxdat_resp_err,

    // Decoded core DAT transmit channel.
    input  logic                    core_txdat_valid,
    output logic                    core_txdat_ready,
    input  logic [TXNID_WIDTH-1:0]  core_txdat_txnid,
    input  logic [DBID_WIDTH-1:0]   core_txdat_dbid,
    input  logic [DATA_WIDTH-1:0]   core_txdat_data,
    input  logic [DATA_WIDTH/8-1:0] core_txdat_be,
    input  logic [DATAID_WIDTH-1:0] core_txdat_data_id,
    input  logic                    core_txdat_last,

    output logic protocol_error
);

  localparam int unsigned MAX_CREDITS_0 =
      (TX_REQ_CREDITS > TX_DAT_CREDITS) ? TX_REQ_CREDITS : TX_DAT_CREDITS;
  localparam int unsigned MAX_CREDITS =
      (RX_RSP_CREDITS > RX_DAT_CREDITS)
          ? ((RX_RSP_CREDITS > MAX_CREDITS_0) ? RX_RSP_CREDITS : MAX_CREDITS_0)
          : ((RX_DAT_CREDITS > MAX_CREDITS_0) ? RX_DAT_CREDITS : MAX_CREDITS_0);
  localparam int unsigned CREDIT_WIDTH = $clog2(MAX_CREDITS + 1);
  localparam int unsigned RSP_PTR_WIDTH =
      (RX_RSP_CREDITS <= 1) ? 1 : $clog2(RX_RSP_CREDITS);
  localparam int unsigned DAT_PTR_WIDTH =
      (RX_DAT_CREDITS <= 1) ? 1 : $clog2(RX_DAT_CREDITS);

  // OpenNoC CHI-E field positions.  Keeping these local avoids importing
  // macro-controlled widths from legacy OpenNoC RTL.
  localparam int unsigned REQ_TGTID_LSB = 4;
  localparam int unsigned REQ_SRCID_LSB = NID_WIDTH + 4;
  localparam int unsigned REQ_TXNID_LSB = 2 * NID_WIDTH + 4;
  localparam int unsigned REQ_RET_NID_LSB = 2 * NID_WIDTH + 16;
  localparam int unsigned REQ_RET_TXNID_LSB = 3 * NID_WIDTH + 17;
  localparam int unsigned REQ_OPCODE_LSB = 3 * NID_WIDTH + 29;
  localparam int unsigned REQ_SIZE_LSB = 3 * NID_WIDTH + 36;
  localparam int unsigned REQ_ADDR_LSB = 3 * NID_WIDTH + 39;
  localparam int unsigned REQ_NS_LSB = REQ_ADDR_LSB + ADDR_WIDTH;
  localparam int unsigned REQ_ALLOW_RETRY_LSB = REQ_NS_LSB + 2;
  localparam int unsigned REQ_ORDER_LSB = REQ_NS_LSB + 3;
  localparam int unsigned REQ_MEMATTR_LSB = REQ_NS_LSB + 9;

  localparam int unsigned RSP_TXNID_LSB = 2 * NID_WIDTH + 4;
  localparam int unsigned RSP_SRCID_LSB = NID_WIDTH + 4;
  localparam int unsigned RSP_OPCODE_LSB = 2 * NID_WIDTH + 16;
  localparam int unsigned RSP_RESPERR_LSB = 2 * NID_WIDTH + 21;
  localparam int unsigned RSP_DBID_LSB = 2 * NID_WIDTH + 32;

  localparam int unsigned DAT_TXNID_LSB = 2 * NID_WIDTH + 4;
  localparam int unsigned DAT_TGTID_LSB = 4;
  localparam int unsigned DAT_SRCID_LSB = NID_WIDTH + 4;
  localparam int unsigned DAT_HOMENID_LSB = 2 * NID_WIDTH + 16;
  localparam int unsigned DAT_OPCODE_LSB = 3 * NID_WIDTH + 16;
  localparam int unsigned DAT_RESPERR_LSB = 3 * NID_WIDTH + 20;
  localparam int unsigned DAT_DBID_LSB = 3 * NID_WIDTH + 32;
  localparam int unsigned DAT_DATAID_LSB = 3 * NID_WIDTH + 46;
  localparam int unsigned DAT_BE_LSB = 3 * NID_WIDTH + DATA_WIDTH / 32 +
                                        DATA_WIDTH / 128 + 51;
  localparam int unsigned DAT_DATA_LSB = DAT_BE_LSB + DATA_WIDTH / 8;

  localparam logic [4:0] RSP_RETRYACK = 5'h03;
  localparam logic [4:0] RSP_COMP = 5'h04;
  localparam logic [4:0] RSP_COMPDBIDRESP = 5'h05;
  localparam logic [4:0] RSP_DBIDRESP = 5'h06;
  localparam logic [4:0] RSP_PCRDGRANT = 5'h07;
  localparam logic [3:0] DAT_COMPDATA = 4'h4;

  logic [CREDIT_WIDTH-1:0] req_credit_count;
  logic [CREDIT_WIDTH-1:0] dat_credit_count;
  logic [CREDIT_WIDTH-1:0] rxrsp_credit_pending;
  logic [CREDIT_WIDTH-1:0] rxdat_credit_pending;
  logic link_active_q;
  logic rsp_supported;
  logic rsp_forbidden;
  logic dat_supported;
  logic dat_forbidden;
  logic rsp_enqueue;
  logic dat_enqueue;
  logic rsp_push_supported;
  logic dat_push_supported;
  logic rsp_pop;
  logic dat_pop;
  logic [RSP_PTR_WIDTH-1:0] rsp_write_ptr;
  logic [RSP_PTR_WIDTH-1:0] rsp_read_ptr;
  logic [DAT_PTR_WIDTH-1:0] dat_write_ptr;
  logic [DAT_PTR_WIDTH-1:0] dat_read_ptr;
  logic [CREDIT_WIDTH-1:0] rsp_fifo_count;
  logic [CREDIT_WIDTH-1:0] dat_fifo_count;
  logic [TXNID_WIDTH-1:0] rsp_txnid_fifo [0:RX_RSP_CREDITS-1];
  logic [1:0] rsp_kind_fifo [0:RX_RSP_CREDITS-1];
  logic [DBID_WIDTH-1:0] rsp_dbid_fifo [0:RX_RSP_CREDITS-1];
  logic [1:0] rsp_resp_err_fifo [0:RX_RSP_CREDITS-1];
  logic [TXNID_WIDTH-1:0] dat_txnid_fifo [0:RX_DAT_CREDITS-1];
  logic [DATAID_WIDTH-1:0] dat_data_id_fifo [0:RX_DAT_CREDITS-1];
  logic [DATA_WIDTH-1:0] dat_data_fifo [0:RX_DAT_CREDITS-1];
  logic [1:0] dat_resp_err_fifo [0:RX_DAT_CREDITS-1];
  logic [NID_WIDTH-1:0] completer_node_id [0:(1 << TXNID_WIDTH)-1];
  logic completer_node_valid [0:(1 << TXNID_WIDTH)-1];
  integer route_slot;

  // Static profile checks: a raw flit must be exactly the width implied by
  // OpenNoC's CHI-E layout, not silently truncated or zero-extended.
  initial begin
    if (NID_WIDTH != 11 || ADDR_WIDTH != 44 || DATA_WIDTH != 256 ||
        TXNID_WIDTH != 12 || DBID_WIDTH != 12 || DATAID_WIDTH != 2 ||
        RAW_REQ_WIDTH != 143 || RAW_RSP_WIDTH != 73 || RAW_DAT_WIDTH != 382)
      $fatal(1, "chi_rni_opennoc_profile_shim: unsupported OpenNoC profile");
    if (TX_REQ_CREDITS == 0 || TX_REQ_CREDITS > 15 ||
        TX_DAT_CREDITS == 0 || TX_DAT_CREDITS > 15 ||
        RX_RSP_CREDITS == 0 || RX_RSP_CREDITS > 15 ||
        RX_DAT_CREDITS == 0 || RX_DAT_CREDITS > 15)
      $fatal(1, "chi_rni_opennoc_profile_shim: credits must be in 1..15");
  end

  assign tx_linkactive_req = rst_n;
  assign rx_linkactive_ack = rx_linkactive_req;
  assign core_link_active = link_active_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      link_active_q <= 1'b0;
      link_epoch <= 1'b0;
      req_credit_count <= '0;
      dat_credit_count <= '0;
      rxrsp_credit_pending <= '0;
      rxdat_credit_pending <= '0;
      rsp_write_ptr <= '0;
      rsp_read_ptr <= '0;
      dat_write_ptr <= '0;
      dat_read_ptr <= '0;
      rsp_fifo_count <= '0;
      dat_fifo_count <= '0;
      protocol_error <= 1'b0;
      for (route_slot = 0; route_slot < (1 << TXNID_WIDTH); route_slot = route_slot + 1)
        completer_node_valid[route_slot] <= 1'b0;
    end else begin
      link_active_q <= tx_linkactive_ack && rx_linkactive_req;
      if (link_active_q != (tx_linkactive_ack && rx_linkactive_req)) begin
        link_epoch <= ~link_epoch;
        // TX credit belongs to the remote receiver.  It starts at zero and
        // becomes available only when that receiver returns/grants credit.
        req_credit_count <= '0;
        dat_credit_count <= '0;
        rxrsp_credit_pending <= (tx_linkactive_ack && rx_linkactive_req)
                                ? RX_RSP_CREDITS[CREDIT_WIDTH-1:0] : '0;
        rxdat_credit_pending <= (tx_linkactive_ack && rx_linkactive_req)
                                ? RX_DAT_CREDITS[CREDIT_WIDTH-1:0] : '0;
        rsp_write_ptr <= '0;
        rsp_read_ptr <= '0;
        dat_write_ptr <= '0;
        dat_read_ptr <= '0;
        rsp_fifo_count <= '0;
        dat_fifo_count <= '0;
        for (route_slot = 0; route_slot < (1 << TXNID_WIDTH); route_slot = route_slot + 1)
          completer_node_valid[route_slot] <= 1'b0;
      end else if (link_active_q) begin
        case ({txreq_lcrdv, core_txreq_valid && core_txreq_ready})
          2'b10: if (req_credit_count < TX_REQ_CREDITS) req_credit_count <= req_credit_count + 1'b1;
          2'b01: if (req_credit_count != '0) req_credit_count <= req_credit_count - 1'b1;
          default: req_credit_count <= req_credit_count;
        endcase
        case ({txdat_lcrdv, core_txdat_valid && core_txdat_ready})
          2'b10: if (dat_credit_count < TX_DAT_CREDITS) dat_credit_count <= dat_credit_count + 1'b1;
          2'b01: if (dat_credit_count != '0) dat_credit_count <= dat_credit_count - 1'b1;
          default: dat_credit_count <= dat_credit_count;
        endcase
        case ({rxrsp_lcrdv, rsp_enqueue})
          2'b10: rxrsp_credit_pending <= rxrsp_credit_pending - 1'b1;
          2'b01: if (rxrsp_credit_pending < RX_RSP_CREDITS)
                   rxrsp_credit_pending <= rxrsp_credit_pending + 1'b1;
          default: rxrsp_credit_pending <= rxrsp_credit_pending;
        endcase
        case ({rxdat_lcrdv, dat_enqueue})
          2'b10: rxdat_credit_pending <= rxdat_credit_pending - 1'b1;
          2'b01: if (rxdat_credit_pending < RX_DAT_CREDITS)
                   rxdat_credit_pending <= rxdat_credit_pending + 1'b1;
          default: rxdat_credit_pending <= rxdat_credit_pending;
        endcase
      end

      if ((core_txreq_valid && core_txreq_allow_retry) ||
          (rxrsp_flitv && rxrsp_flitpend && rsp_forbidden) ||
          (rxdat_flitv && rxdat_flitpend && dat_forbidden) ||
          (rxrsp_flitv && rxrsp_flitpend && !rsp_enqueue) ||
          (rxdat_flitv && rxdat_flitpend && !dat_enqueue))
        protocol_error <= 1'b1;

      if (rsp_enqueue && rsp_supported &&
          ((rxrsp_flit[RSP_OPCODE_LSB +: 5] == RSP_DBIDRESP) ||
           (rxrsp_flit[RSP_OPCODE_LSB +: 5] == RSP_COMPDBIDRESP))) begin
        completer_node_id[rxrsp_flit[RSP_TXNID_LSB +: TXNID_WIDTH]] <=
            rxrsp_flit[RSP_SRCID_LSB +: NID_WIDTH];
        completer_node_valid[rxrsp_flit[RSP_TXNID_LSB +: TXNID_WIDTH]] <= 1'b1;
      end

      if (core_txdat_valid && core_txdat_ready && core_txdat_last)
        completer_node_valid[core_txdat_txnid] <= 1'b0;

      if (rsp_push_supported) begin
        rsp_txnid_fifo[rsp_write_ptr] <=
            rxrsp_flit[RSP_TXNID_LSB +: TXNID_WIDTH];
        rsp_dbid_fifo[rsp_write_ptr] <= rxrsp_flit[RSP_DBID_LSB +: DBID_WIDTH];
        rsp_resp_err_fifo[rsp_write_ptr] <= rxrsp_flit[RSP_RESPERR_LSB +: 2];
        case (rxrsp_flit[RSP_OPCODE_LSB +: 5])
          RSP_DBIDRESP: rsp_kind_fifo[rsp_write_ptr] <= `CHI_RNI_RSP_DBIDRESP;
          RSP_COMPDBIDRESP: rsp_kind_fifo[rsp_write_ptr] <= `CHI_RNI_RSP_COMPDBIDRESP;
          default: rsp_kind_fifo[rsp_write_ptr] <= `CHI_RNI_RSP_COMP;
        endcase
        if (rsp_write_ptr == RX_RSP_CREDITS - 1)
          rsp_write_ptr <= '0;
        else
          rsp_write_ptr <= rsp_write_ptr + 1'b1;
      end
      if (rsp_pop) begin
        if (rsp_read_ptr == RX_RSP_CREDITS - 1)
          rsp_read_ptr <= '0;
        else
          rsp_read_ptr <= rsp_read_ptr + 1'b1;
      end
      case ({rsp_push_supported, rsp_pop})
        2'b10: rsp_fifo_count <= rsp_fifo_count + 1'b1;
        2'b01: rsp_fifo_count <= rsp_fifo_count - 1'b1;
        default: rsp_fifo_count <= rsp_fifo_count;
      endcase

      if (dat_push_supported) begin
        dat_txnid_fifo[dat_write_ptr] <=
            rxdat_flit[DAT_TXNID_LSB +: TXNID_WIDTH];
        dat_data_id_fifo[dat_write_ptr] <=
            rxdat_flit[DAT_DATAID_LSB +: DATAID_WIDTH];
        dat_data_fifo[dat_write_ptr] <= rxdat_flit[DAT_DATA_LSB +: DATA_WIDTH];
        dat_resp_err_fifo[dat_write_ptr] <= rxdat_flit[DAT_RESPERR_LSB +: 2];
        if (dat_write_ptr == RX_DAT_CREDITS - 1)
          dat_write_ptr <= '0;
        else
          dat_write_ptr <= dat_write_ptr + 1'b1;
      end
      if (dat_pop) begin
        if (dat_read_ptr == RX_DAT_CREDITS - 1)
          dat_read_ptr <= '0;
        else
          dat_read_ptr <= dat_read_ptr + 1'b1;
      end
      case ({dat_push_supported, dat_pop})
        2'b10: dat_fifo_count <= dat_fifo_count + 1'b1;
        2'b01: dat_fifo_count <= dat_fifo_count - 1'b1;
        default: dat_fifo_count <= dat_fifo_count;
      endcase
    end
  end

  always_comb begin
    txreq_flit = '0;
    txreq_flit[3:0] = core_txreq_qos;
    txreq_flit[REQ_TGTID_LSB +: NID_WIDTH] = DEFAULT_HN_NODE_ID;
    txreq_flit[REQ_SRCID_LSB +: NID_WIDTH] = RNI_NODE_ID;
    txreq_flit[REQ_TXNID_LSB +: TXNID_WIDTH] = core_txreq_txnid;
    txreq_flit[REQ_RET_NID_LSB +: NID_WIDTH] = RETURN_NODE_ID;
    txreq_flit[REQ_RET_TXNID_LSB +: TXNID_WIDTH] = core_txreq_txnid;
    txreq_flit[REQ_OPCODE_LSB +: 7] = core_txreq_opcode;
    txreq_flit[REQ_SIZE_LSB +: 3] = core_txreq_size;
    txreq_flit[REQ_ADDR_LSB +: ADDR_WIDTH] = core_txreq_addr;
    txreq_flit[REQ_NS_LSB] = core_txreq_ns;
    txreq_flit[REQ_ORDER_LSB +: 2] = core_txreq_order;
    // MemAttr[1]=Device; normal accesses are cacheable but never allocate.
    txreq_flit[REQ_MEMATTR_LSB +: 4] = {1'b0, !core_txreq_device,
                                        core_txreq_device, 1'b0};
    // PCrdType, Endian and reserved/profile-unsupported fields are fixed by
    // V1.  Route identity is always explicitly packed from integration config.

    txreq_flitv = core_txreq_valid && core_txreq_ready;
    txreq_flitpend = core_txreq_valid && core_txreq_ready;
    core_txreq_ready = link_active_q && (req_credit_count != '0) &&
                       !core_txreq_allow_retry;

    txdat_flit = '0;
    txdat_flit[DAT_TGTID_LSB +: NID_WIDTH] =
        completer_node_id[core_txdat_txnid];
    txdat_flit[DAT_SRCID_LSB +: NID_WIDTH] = RNI_NODE_ID;
    txdat_flit[DAT_HOMENID_LSB +: NID_WIDTH] = RETURN_NODE_ID;
    txdat_flit[DAT_TXNID_LSB +: TXNID_WIDTH] = core_txdat_txnid;
    txdat_flit[DAT_DBID_LSB +: DBID_WIDTH] = core_txdat_dbid;
    txdat_flit[DAT_OPCODE_LSB +: 4] = 4'h3;  // NonCopyBackWrData
    txdat_flit[DAT_DATAID_LSB +: DATAID_WIDTH] = core_txdat_data_id;
    txdat_flit[DAT_BE_LSB +: DATA_WIDTH/8] = core_txdat_be;
    txdat_flit[DAT_DATA_LSB +: DATA_WIDTH] = core_txdat_data;
    txdat_flitv = core_txdat_valid && core_txdat_ready;
    txdat_flitpend = core_txdat_valid && core_txdat_ready;
    core_txdat_ready = link_active_q && (dat_credit_count != '0) &&
                       completer_node_valid[core_txdat_txnid];

    rsp_supported = (rxrsp_flit[RSP_OPCODE_LSB +: 5] == RSP_DBIDRESP) ||
                    (rxrsp_flit[RSP_OPCODE_LSB +: 5] == RSP_COMPDBIDRESP) ||
                    (rxrsp_flit[RSP_OPCODE_LSB +: 5] == RSP_COMP);
    rsp_forbidden = !rsp_supported;
    rsp_enqueue = link_active_q && rxrsp_flitv && rxrsp_flitpend &&
                  (rsp_fifo_count < RX_RSP_CREDITS);
    rsp_push_supported = rsp_enqueue && rsp_supported;
    core_rxrsp_valid = link_active_q && (rsp_fifo_count != '0);
    core_rxrsp_txnid = rsp_txnid_fifo[rsp_read_ptr];
    core_rxrsp_kind = rsp_kind_fifo[rsp_read_ptr];
    core_rxrsp_dbid = rsp_dbid_fifo[rsp_read_ptr];
    core_rxrsp_resp_err = rsp_resp_err_fifo[rsp_read_ptr];
    rsp_pop = core_rxrsp_valid && core_rxrsp_ready;
    // A pending receive credit is emitted independently of flit traffic.
    // This produces the initial OpenNoC L-credit grants after each epoch and
    // returns one credit after every flit the shim drains.
    rxrsp_lcrdv = link_active_q && (rxrsp_credit_pending != '0);

    dat_supported = (rxdat_flit[DAT_OPCODE_LSB +: 4] == DAT_COMPDATA);
    dat_forbidden = !dat_supported;
    dat_enqueue = link_active_q && rxdat_flitv && rxdat_flitpend &&
                  (dat_fifo_count < RX_DAT_CREDITS);
    dat_push_supported = dat_enqueue && dat_supported;
    core_rxdat_valid = link_active_q && (dat_fifo_count != '0);
    core_rxdat_txnid = dat_txnid_fifo[dat_read_ptr];
    core_rxdat_data_id = dat_data_id_fifo[dat_read_ptr];
    core_rxdat_data = dat_data_fifo[dat_read_ptr];
    core_rxdat_resp_err = dat_resp_err_fifo[dat_read_ptr];
    dat_pop = core_rxdat_valid && core_rxdat_ready;
    rxdat_lcrdv = link_active_q && (rxdat_credit_pending != '0);
  end

endmodule
