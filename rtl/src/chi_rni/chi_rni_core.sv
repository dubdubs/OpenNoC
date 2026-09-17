// Copyright 2026
//
// chi_rni_core: synthesizable transaction engine for the Scheme-1
// (non-coherent AXI-to-CHI) adaptor.  It owns AXI-parent / CHI-child
// bookkeeping, child segmentation, completion aggregation and AXI
// response generation.  Packing CHI flits and managing link credits
// deliberately belongs in a profile shim, not here: this module exposes a
// decoded, ready/valid CHI channel interface.
//
// BURST_BEAT_COALESCING selects per-beat (0) or exact, naturally-aligned
// 1B..64B Normal-INCR segmentation across AXI beat boundaries (1).  Device
// and FIXED accesses never coalesce.

`include "chi_rni_defines.svh"

module chi_rni_core #(
    parameter int unsigned ADDR_WIDTH         = 44,
    parameter int unsigned AXI_DATA_WIDTH     = 128,
    parameter int unsigned AXI_ID_WIDTH       = 8,
    parameter int unsigned CHI_DATA_WIDTH     = 256,
    parameter int unsigned CHI_TXNID_WIDTH    = 12,
    parameter int unsigned CHI_DBID_WIDTH     = 12,
    parameter int unsigned CHI_DATAID_WIDTH   = 2,
    parameter int unsigned DATAID_LAYOUT      = `CHI_RNI_DATAID_LAYOUT_IHI0050E,
    parameter int unsigned ORDER_POLICY       = `CHI_RNI_ORDER_POLICY_PERMISSIVE,
    parameter bit          BURST_BEAT_COALESCING = 1'b0,
    parameter int unsigned PARENT_ENTRIES     = 32,
    parameter int unsigned MAX_AXI_BEATS      = 256,
    parameter int unsigned MAX_WRITE_PARENT_BYTES = MAX_AXI_BEATS * (AXI_DATA_WIDTH / 8),
    parameter int unsigned MAX_CHILD_PER_PARENT = MAX_AXI_BEATS * (AXI_DATA_WIDTH / 8),
    parameter bit          ACCESS_DEVICE      = 1'b0,
    parameter bit          FORCE_NONSECURE    = 1'b1,
    parameter logic [1:0]  ORDER_VALUE        = 2'b00,
    parameter logic [3:0]  QOS_VALUE          = 4'b0000,
    parameter bit          ENABLE_WRITE_NO_SNP_FULL = 1'b0,
    parameter logic [2:0]  FULL_LINE_SIZE_LOG2 = `CHI_RNI_MAX_CHILD_LOG2,
    parameter logic [6:0]  READ_NO_SNP_OPCODE      = `CHI_RNI_OPCODE_READNOSNP,
    parameter logic [6:0]  WRITE_NO_SNP_PTL_OPCODE = `CHI_RNI_OPCODE_WRITENOSNPPTL
)(
    input  logic clk,
    input  logic rst_n,
    input  logic link_active,

    // AXI read address / read data
    input  logic [AXI_ID_WIDTH-1:0] s_axi_arid,
    input  logic [ADDR_WIDTH-1:0]   s_axi_araddr,
    input  logic [7:0]              s_axi_arlen,
    input  logic [2:0]              s_axi_arsize,
    input  logic [1:0]              s_axi_arburst,
    input  logic [2:0]              s_axi_arprot,
    input  logic                    s_axi_arlock,
    input  logic                    s_axi_arvalid,
    output logic                    s_axi_arready,
    output logic [AXI_ID_WIDTH-1:0] s_axi_rid,
    output logic [AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output logic [1:0]              s_axi_rresp,
    output logic                    s_axi_rlast,
    output logic                    s_axi_rvalid,
    input  logic                    s_axi_rready,

    // AXI write address / write data / write response
    input  logic [AXI_ID_WIDTH-1:0] s_axi_awid,
    input  logic [ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  logic [7:0]              s_axi_awlen,
    input  logic [2:0]              s_axi_awsize,
    input  logic [1:0]              s_axi_awburst,
    input  logic [2:0]              s_axi_awprot,
    input  logic                    s_axi_awlock,
    input  logic                    s_axi_awvalid,
    output logic                    s_axi_awready,
    input  logic [AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  logic [AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  logic                    s_axi_wlast,
    input  logic                    s_axi_wvalid,
    output logic                    s_axi_wready,
    output logic [AXI_ID_WIDTH-1:0] s_axi_bid,
    output logic [1:0]              s_axi_bresp,
    output logic                    s_axi_bvalid,
    input  logic                    s_axi_bready,

    // CHI TX request (decoded)
    output logic                    chi_txreq_valid,
    input  logic                    chi_txreq_ready,
    output logic [6:0]              chi_txreq_opcode,
    output logic [ADDR_WIDTH-1:0]   chi_txreq_addr,
    output logic [2:0]              chi_txreq_size,
    output logic [CHI_TXNID_WIDTH-1:0] chi_txreq_txnid,
    output logic                    chi_txreq_device,
    output logic                    chi_txreq_ns,
    output logic [1:0]              chi_txreq_order,
    output logic [3:0]              chi_txreq_qos,
    output logic                    chi_txreq_allow_retry,

    // CHI RX response (decoded)
    input  logic                    chi_rxrsp_valid,
    output logic                    chi_rxrsp_ready,
    input  logic [CHI_TXNID_WIDTH-1:0] chi_rxrsp_txnid,
    input  logic [1:0]              chi_rxrsp_kind,
    input  logic [CHI_DBID_WIDTH-1:0]  chi_rxrsp_dbid,
    input  logic [1:0]              chi_rxrsp_resp_err,

    // CHI RX data (decoded)
    input  logic                    chi_rxdat_valid,
    output logic                    chi_rxdat_ready,
    input  logic [CHI_TXNID_WIDTH-1:0] chi_rxdat_txnid,
    input  logic [CHI_DATAID_WIDTH-1:0] chi_rxdat_data_id,
    input  logic [CHI_DATA_WIDTH-1:0] chi_rxdat_data,
    input  logic [1:0]              chi_rxdat_resp_err,

    // CHI TX data (decoded)
    output logic                    chi_txdat_valid,
    input  logic                    chi_txdat_ready,
    output logic [CHI_TXNID_WIDTH-1:0] chi_txdat_txnid,
    output logic [CHI_DBID_WIDTH-1:0]  chi_txdat_dbid,
    output logic [CHI_DATA_WIDTH-1:0]  chi_txdat_data,
    output logic [CHI_DATA_WIDTH/8-1:0] chi_txdat_be,
    output logic [CHI_DATAID_WIDTH-1:0] chi_txdat_data_id,
    output logic                    chi_txdat_last,

    output logic                    protocol_error
);

  localparam int unsigned AXI_BYTES      = AXI_DATA_WIDTH / 8;
  localparam int unsigned CHI_BYTES      = CHI_DATA_WIDTH / 8;
  localparam int unsigned AXI_BYTES_LOG2 = $clog2(AXI_BYTES);
  localparam int unsigned CHI_BYTES_LOG2 = $clog2(CHI_BYTES);
  localparam int unsigned PARENT_BITS    = $clog2(PARENT_ENTRIES);
  localparam int unsigned BEAT_BITS      = $clog2(MAX_AXI_BEATS);
  localparam int unsigned MAX_CHI_DAT_BEATS =
      ((`CHI_RNI_MAX_CHILD_BYTES + CHI_BYTES - 1) / CHI_BYTES);
  localparam int unsigned DAT_ORDINAL_BITS =
      (MAX_CHI_DAT_BEATS <= 1) ? 1 : $clog2(MAX_CHI_DAT_BEATS);

  typedef enum logic [2:0] {P_FREE, P_WCOLLECT, P_ACTIVE, P_RREADY, P_BREADY}
      parent_state_t;
  typedef enum logic [2:0] {C_FREE, C_REQ, C_RDATA, C_WDBID, C_WDATA, C_WCOMP}
      child_state_t;

  parent_state_t parent_state [0:PARENT_ENTRIES-1];
  child_state_t  child_state  [0:PARENT_ENTRIES-1];

  logic parent_write [0:PARENT_ENTRIES-1];
  logic [AXI_ID_WIDTH-1:0] parent_id   [0:PARENT_ENTRIES-1];
  logic [ADDR_WIDTH-1:0]   parent_addr [0:PARENT_ENTRIES-1];
  logic [7:0]  parent_len   [0:PARENT_ENTRIES-1];
  logic [2:0]  parent_size  [0:PARENT_ENTRIES-1];
  logic [1:0]  parent_burst [0:PARENT_ENTRIES-1];
  logic [BEAT_BITS-1:0] parent_beat   [0:PARENT_ENTRIES-1];
  logic [7:0]  parent_beat_pos        [0:PARENT_ENTRIES-1];
  logic [8:0]  parent_wcount          [0:PARENT_ENTRIES-1];
  logic [1:0]  parent_error           [0:PARENT_ENTRIES-1];
  logic [BEAT_BITS:0] parent_ready_until [0:PARENT_ENTRIES-1];
  logic [AXI_DATA_WIDTH-1:0] parent_rdata [0:PARENT_ENTRIES-1][0:MAX_AXI_BEATS-1];
  logic [AXI_DATA_WIDTH-1:0] parent_wdata [0:PARENT_ENTRIES-1][0:MAX_AXI_BEATS-1];
  logic [AXI_BYTES-1:0]      parent_wstrb [0:PARENT_ENTRIES-1][0:MAX_AXI_BEATS-1];

  logic [ADDR_WIDTH-1:0]   child_addr  [0:PARENT_ENTRIES-1];
  logic [2:0]              child_size  [0:PARENT_ENTRIES-1];
  logic [CHI_TXNID_WIDTH-1:0] child_txnid [0:PARENT_ENTRIES-1];
  logic [CHI_DBID_WIDTH-1:0]  child_dbid  [0:PARENT_ENTRIES-1];
  logic child_comp_included [0:PARENT_ENTRIES-1];
  logic child_completion_seen [0:PARENT_ENTRIES-1];
  logic child_write_full [0:PARENT_ENTRIES-1];
  logic [MAX_CHI_DAT_BEATS-1:0] child_dat_seen [0:PARENT_ENTRIES-1];
  logic [DAT_ORDINAL_BITS:0] child_dat_needed [0:PARENT_ENTRIES-1];
  logic [DAT_ORDINAL_BITS:0] child_wdat_ordinal [0:PARENT_ENTRIES-1];

  logic axi_id_busy [0:(1 << AXI_ID_WIDTH)-1];
  logic [PARENT_BITS-1:0] w_collect_parent;
  logic w_collect_valid;
  logic parent_free;

  logic [PARENT_BITS-1:0] req_child, r_select, b_select;
  logic req_found, r_found, b_found;
  logic [PARENT_BITS-1:0] dat_child, rsp_child, dat_tx_child;
  logic dat_match, rsp_match;

  // Combinational temporaries for the channel/DAT block (module scope so
  // every path through the combinational block has a default assignment).
  logic [ADDR_WIDTH-1:0] abs_addr_c;
  integer src_beat_c, chi_lane_c, axi_lane_c;

  initial begin
    if (DATAID_LAYOUT != `CHI_RNI_DATAID_LAYOUT_IHI0050E)
      $fatal(1, "chi_rni_core: unsupported DataID revision/profile");
    if (CHI_DATA_WIDTH != 128 && CHI_DATA_WIDTH != 256 && CHI_DATA_WIDTH != 512)
      $fatal(1, "chi_rni_core: IHI0050E requires 128/256/512-bit DAT width");
  end

  // ---------------------------------------------------------------------
  // Admission / helpers
  // ---------------------------------------------------------------------
  function automatic logic RequestLegal(
      input logic [ADDR_WIDTH-1:0] address,
      input integer len,
      input integer size,
      input logic [1:0] burst,
      input logic prot_ns,
      input logic lock);
    logic [ADDR_WIDTH:0] final_addr;
    logic aligned;
    begin
      final_addr = {1'b0, address} + ((len + 1) << size) - 1'b1;
      aligned = ((address % (1 << size)) == 0);
      RequestLegal = link_active && !lock && (prot_ns == FORCE_NONSECURE) &&
          (burst == `CHI_RNI_AXI_BURST_INCR || burst == `CHI_RNI_AXI_BURST_FIXED) &&
          (size <= AXI_BYTES_LOG2) && (size <= `CHI_RNI_MAX_CHILD_LOG2) &&
          ((len + 1) <= MAX_AXI_BEATS) &&
          (((len + 1) << size) <= MAX_CHILD_PER_PARENT) &&
          (burst != `CHI_RNI_AXI_BURST_INCR ||
              address[ADDR_WIDTH-1:12] == final_addr[ADDR_WIDTH-1:12]) &&
          (aligned || (burst == `CHI_RNI_AXI_BURST_INCR && !ACCESS_DEVICE));
    end
  endfunction

  function automatic logic WriteRequestLegal(
      input logic [ADDR_WIDTH-1:0] address,
      input integer len,
      input integer size,
      input logic [1:0] burst,
      input logic prot_ns,
      input logic lock);
    begin
      WriteRequestLegal = RequestLegal(address, len, size, burst, prot_ns,
                                       lock) &&
          (((len + 1) << size) <= MAX_WRITE_PARENT_BYTES);
    end
  endfunction

  // True if every byte in [start_lane, start_lane+count) of `strobe` is 0.
  function automatic logic StrobeZero(
      input logic [AXI_BYTES-1:0] strobe,
      input integer start_lane,
      input integer count);
    integer n;
    begin
      StrobeZero = 1'b1;
      for (n = 0; n < count; n = n + 1)
        if (strobe[(start_lane + n) % AXI_BYTES]) StrobeZero = 1'b0;
    end
  endfunction

  function automatic logic CoalescingEnabled(input integer p);
    begin
      CoalescingEnabled = BURST_BEAT_COALESCING && !ACCESS_DEVICE &&
          (parent_burst[p] == `CHI_RNI_AXI_BURST_INCR);
    end
  endfunction

  function automatic logic StrobeZeroChild(
      input integer p, input logic [ADDR_WIDTH-1:0] caddr, input integer count);
    integer n, src_beat, lane;
    logic [ADDR_WIDTH-1:0] byte_addr;
    begin
      StrobeZeroChild = 1'b1;
      for (n = 0; n < count; n = n + 1) begin
        byte_addr = caddr + n;
        src_beat = (parent_burst[p] == `CHI_RNI_AXI_BURST_FIXED) ?
            parent_beat[p] : ((byte_addr - parent_addr[p]) >> parent_size[p]);
        lane = byte_addr[AXI_BYTES_LOG2-1:0];
        if (parent_wstrb[p][src_beat][lane]) StrobeZeroChild = 1'b0;
      end
    end
  endfunction

  function automatic logic ChildFullyWritten(
      input integer p, input logic [ADDR_WIDTH-1:0] caddr, input integer count);
    integer n, src_beat, lane;
    logic [ADDR_WIDTH-1:0] byte_addr;
    begin
      ChildFullyWritten = 1'b1;
      for (n = 0; n < count; n = n + 1) begin
        byte_addr = caddr + n;
        src_beat = (parent_burst[p] == `CHI_RNI_AXI_BURST_FIXED) ?
            parent_beat[p] : ((byte_addr - parent_addr[p]) >> parent_size[p]);
        lane = byte_addr[AXI_BYTES_LOG2-1:0];
        if (!parent_wstrb[p][src_beat][lane]) ChildFullyWritten = 1'b0;
      end
    end
  endfunction

  // Allocate the child slot for parent p (child table is 1:1 with parent
  // table).  TxnID is the zero-extended parent index: at most one child per
  // parent is live, so this is always unique among outstanding requests and
  // makes RSP/DAT correlation a constant-time index.
  task automatic StartChild(input integer p,
                            input logic [ADDR_WIDTH-1:0] caddr,
                            input logic [2:0] csize);
    integer dbc;
    begin
      dbc = chi_rni_data_beat_count(csize, CHI_BYTES_LOG2);
      child_state[p]        = C_REQ;
      child_addr[p]         = caddr;
      child_size[p]         = csize;
      child_txnid[p]        = {{(CHI_TXNID_WIDTH - PARENT_BITS){1'b0}},
                                p[PARENT_BITS-1:0]};
      child_dat_needed[p]   = dbc;
      child_dat_seen[p]     = '0;
      child_wdat_ordinal[p] = '0;
      child_comp_included[p] = 1'b0;
      child_completion_seen[p] = 1'b0;
      child_write_full[p] = ENABLE_WRITE_NO_SNP_FULL && !ACCESS_DEVICE &&
          (csize == FULL_LINE_SIZE_LOG2) &&
          ChildFullyWritten(p, caddr, 1 << csize);
    end
  endtask

  // Issue the next child of a READ parent (one aligned power-of-two chunk
  // of the current beat).
  task automatic ServiceRead(input integer p);
    integer beat_bytes;
    logic [ADDR_WIDTH-1:0] caddr;
    begin
      beat_bytes = 1 << parent_size[p];
      if (parent_beat_pos[p] < beat_bytes) begin
        caddr = (parent_burst[p] == `CHI_RNI_AXI_BURST_FIXED) ? parent_addr[p]
              : parent_addr[p] + ((parent_beat[p] << parent_size[p])
                                  + parent_beat_pos[p]);
        StartChild(p, caddr,
                   chi_rni_next_child_size_log2(caddr[11:0],
                       CoalescingEnabled(p) ?
                           ((((parent_len[p] + 1) << parent_size[p]) -
                             ((parent_beat[p] << parent_size[p]) +
                              parent_beat_pos[p])) > `CHI_RNI_MAX_CHILD_BYTES ?
                               `CHI_RNI_MAX_CHILD_BYTES :
                               (((parent_len[p] + 1) << parent_size[p]) -
                                ((parent_beat[p] << parent_size[p]) +
                                 parent_beat_pos[p]))) :
                           (beat_bytes - parent_beat_pos[p]),
                       CoalescingEnabled(p) ? `CHI_RNI_MAX_CHILD_LOG2 : parent_size[p]));
      end
    end
  endtask

  // Issue the next non-zero-strobe child of a WRITE parent, skipping
  // all-zero sub-children (Scheme 6.5: WSTRB=0 bytes are never written).
  // Advances the beat when the remainder of the beat is all zero.
  task automatic ServiceWrite(input integer p);
    integer beat_bytes, skip_acc, cand_bytes, src_beat, start_lane, n;
    logic [ADDR_WIDTH-1:0] caddr;
    logic [2:0] csize;
    logic issued;
    begin
      beat_bytes = 1 << parent_size[p];
      if (parent_beat_pos[p] >= beat_bytes) begin
        if (parent_beat[p] == parent_len[p])
          parent_state[p] = P_BREADY;
        else begin
          parent_beat[p]     = parent_beat[p] + 1'b1;
          parent_beat_pos[p] = '0;
        end
      end else begin
        skip_acc = 0;
        issued   = 1'b0;
        for (n = 0; n < beat_bytes; n = n + 1) begin
          if (!issued && (parent_beat_pos[p] + skip_acc) < beat_bytes) begin
            caddr = (parent_burst[p] == `CHI_RNI_AXI_BURST_FIXED)
                  ? parent_addr[p]
                  : parent_addr[p] + ((parent_beat[p] << parent_size[p])
                                      + parent_beat_pos[p] + skip_acc);
            csize = chi_rni_next_child_size_log2(caddr[11:0],
                        CoalescingEnabled(p) ?
                            ((((parent_len[p] + 1) << parent_size[p]) -
                              ((parent_beat[p] << parent_size[p]) +
                               parent_beat_pos[p] + skip_acc)) >
                             `CHI_RNI_MAX_CHILD_BYTES ? `CHI_RNI_MAX_CHILD_BYTES :
                             (((parent_len[p] + 1) << parent_size[p]) -
                              ((parent_beat[p] << parent_size[p]) +
                               parent_beat_pos[p] + skip_acc))) :
                            (beat_bytes - parent_beat_pos[p] - skip_acc),
                        CoalescingEnabled(p) ? `CHI_RNI_MAX_CHILD_LOG2 : parent_size[p]);
            cand_bytes = 1 << csize;
            src_beat = (parent_burst[p] == `CHI_RNI_AXI_BURST_FIXED)
                     ? parent_beat[p]
                     : ((caddr - parent_addr[p]) >> parent_size[p]);
            start_lane = caddr[AXI_BYTES_LOG2-1:0];
            if (StrobeZeroChild(p, caddr, cand_bytes)) begin
              skip_acc = skip_acc + cand_bytes;
            end else begin
              parent_beat_pos[p] = parent_beat_pos[p] + skip_acc;
              StartChild(p, caddr, csize);
              issued = 1'b1;
            end
          end
        end
        if (!issued) parent_beat_pos[p] = beat_bytes;
      end
    end
  endtask

  // Complete a READ child: accumulate bytes into the current AXI beat and
  // move to R-drain when the beat is full.
  task automatic CompleteReadChild(input integer cp);
    begin
      child_state[cp] = C_FREE;
      if ((parent_beat_pos[cp] + (1 << child_size[cp])) >=
          (1 << parent_size[cp])) begin
        parent_beat_pos[cp] = '0;
        if (parent_burst[cp] == `CHI_RNI_AXI_BURST_FIXED)
          parent_ready_until[cp] = parent_beat[cp] + 1'b1;
        else
          parent_ready_until[cp] =
              ((child_addr[cp] - parent_addr[cp]) + (1 << child_size[cp]) +
               (1 << parent_size[cp]) - 1) >> parent_size[cp];
        parent_state[cp]     = P_RREADY;
      end else begin
        parent_beat_pos[cp] = parent_beat_pos[cp] + (1 << child_size[cp]);
      end
    end
  endtask

  // Complete a WRITE child: accumulate bytes into the current AXI beat and
  // advance to the next beat (or B-response) when the beat is full.
  task automatic CompleteWriteChild(input integer cp);
    begin
      child_state[cp] = C_FREE;
      if ((parent_beat_pos[cp] + (1 << child_size[cp])) >=
          (1 << parent_size[cp])) begin
        parent_beat_pos[cp] = '0;
        if (parent_beat[cp] +
            ((parent_beat_pos[cp] + (1 << child_size[cp])) >> parent_size[cp]) >
            parent_len[cp])
          parent_state[cp] = P_BREADY;
        else
          parent_beat[cp] = parent_beat[cp] +
              ((parent_beat_pos[cp] + (1 << child_size[cp])) >> parent_size[cp]);
      end else begin
        parent_beat_pos[cp] = parent_beat_pos[cp] + (1 << child_size[cp]);
      end
    end
  endtask

  // ---------------------------------------------------------------------
  // Channel / combinational logic
  // ---------------------------------------------------------------------
  always_comb begin
    integer i, j;
    abs_addr_c = '0; src_beat_c = 0; chi_lane_c = 0; axi_lane_c = 0;
    req_found = 1'b0; req_child = '0;
    r_found = 1'b0;   r_select = '0;
    b_found = 1'b0;   b_select = '0;
    parent_free = 1'b0;
    for (i = 0; i < PARENT_ENTRIES; i = i + 1) begin
      if (parent_state[i] == P_FREE) parent_free = 1'b1;
      if (!req_found && child_state[i] == C_REQ) begin
        req_found = 1'b1; req_child = i[PARENT_BITS-1:0];
      end
      if (!r_found && parent_state[i] == P_RREADY) begin
        r_found = 1'b1; r_select = i[PARENT_BITS-1:0];
      end
      if (!b_found && parent_state[i] == P_BREADY) begin
        b_found = 1'b1; b_select = i[PARENT_BITS-1:0];
      end
    end

    // AXI ready: backpressure also when the parent table is full, so a
    // transaction is never silently dropped (Scheme 7.2).
    s_axi_arready = rst_n && link_active && parent_free && !axi_id_busy[s_axi_arid];
    s_axi_awready = rst_n && link_active && parent_free && !w_collect_valid &&
                    !axi_id_busy[s_axi_awid] && !s_axi_arvalid;
    s_axi_wready  = rst_n && w_collect_valid;

    s_axi_rvalid = rst_n && r_found;
    s_axi_rid    = r_found ? parent_id[r_select] : '0;
    s_axi_rdata  = '0;
    if (r_found) s_axi_rdata = parent_rdata[r_select][parent_beat[r_select]];
    s_axi_rresp  = r_found ? parent_error[r_select] : `CHI_RNI_AXI_OKAY;
    s_axi_rlast  = r_found && (parent_beat[r_select] == parent_len[r_select]);

    s_axi_bvalid = rst_n && b_found;
    s_axi_bid    = b_found ? parent_id[b_select] : '0;
    s_axi_bresp  = b_found ? parent_error[b_select] : `CHI_RNI_AXI_OKAY;

    // REQ channel
    chi_txreq_valid = link_active && req_found;
    chi_txreq_opcode = (req_found && parent_write[req_child])
                     ? (child_write_full[req_child]
                        ? `CHI_RNI_OPCODE_WRITENOSNPFULL
                        : WRITE_NO_SNP_PTL_OPCODE)
                     : READ_NO_SNP_OPCODE;
    chi_txreq_addr  = req_found ? child_addr[req_child] : '0;
    chi_txreq_size  = req_found ? child_size[req_child] : '0;
    chi_txreq_txnid = req_found ? child_txnid[req_child] : '0;
    chi_txreq_device = ACCESS_DEVICE;
    chi_txreq_ns     = FORCE_NONSECURE;
    chi_txreq_order  = ORDER_VALUE;
    chi_txreq_qos    = QOS_VALUE;
    chi_txreq_allow_retry = 1'b0;

    // DAT channel (write data), selected independently from REQ so a
    // REQ scheduler never blocks a child that already owns a DBID.
    chi_txdat_valid = 1'b0;
    chi_txdat_txnid = '0; chi_txdat_dbid = '0; chi_txdat_data = '0;
    chi_txdat_be    = '0; chi_txdat_data_id = '0; chi_txdat_last = 1'b0;
    dat_tx_child = '0;
    for (i = 0; i < PARENT_ENTRIES; i = i + 1) begin
      if (!chi_txdat_valid && child_state[i] == C_WDATA && link_active) begin
        chi_txdat_valid = 1'b1;
        chi_txdat_txnid = child_txnid[i];
        chi_txdat_dbid  = child_dbid[i];
        chi_txdat_data_id = chi_rni_expected_dataid(DATAID_LAYOUT,
            child_addr[i], child_size[i], child_wdat_ordinal[i], CHI_BYTES_LOG2);
        chi_txdat_last =
            (child_wdat_ordinal[i] + 1 >= child_dat_needed[i]);
        dat_tx_child = i[PARENT_BITS-1:0];
        for (j = 0; j < CHI_BYTES; j = j + 1) begin
          if ((child_wdat_ordinal[i] * CHI_BYTES + j) <
              (1 << child_size[i])) begin
            // Address-aligned CHI byte lane (Scheme 6.1.1).
            abs_addr_c = child_addr[i] +
                         (child_wdat_ordinal[i] * CHI_BYTES) + j;
            chi_lane_c = abs_addr_c[CHI_BYTES_LOG2-1:0];
            axi_lane_c = abs_addr_c[AXI_BYTES_LOG2-1:0];
            src_beat_c = (parent_burst[i] == `CHI_RNI_AXI_BURST_FIXED)
                       ? parent_beat[i]
                       : ((abs_addr_c - parent_addr[i]) >> parent_size[i]);
            // CHI spec: a deasserted BE lane must carry zero data.
            chi_txdat_be[chi_lane_c] =
                parent_wstrb[i][src_beat_c][axi_lane_c];
            chi_txdat_data[8*chi_lane_c +: 8] =
                parent_wstrb[i][src_beat_c][axi_lane_c]
                    ? parent_wdata[i][src_beat_c][8*axi_lane_c +: 8]
                    : 8'b0;
          end
        end
      end
    end

    // RSP/DAT correlation.  TxnID is the parent index, so the decode is
    // constant time; the full-width compare rejects spurious TxnIDs.
    dat_child = chi_rxdat_txnid[PARENT_BITS-1:0];
    rsp_child = chi_rxrsp_txnid[PARENT_BITS-1:0];
    dat_match = (child_txnid[dat_child] == chi_rxdat_txnid);
    rsp_match = (child_txnid[rsp_child] == chi_rxrsp_txnid);

    // Always drain RX channels and flag unexpected flits as protocol
    // errors; never deadlock on a spurious TxnID.
    chi_rxdat_ready = link_active;
    chi_rxrsp_ready = link_active;
  end

  // ---------------------------------------------------------------------
  // Sequential logic
  // ---------------------------------------------------------------------
  // State-transition helper tasks assign these registers.  A plain edge-triggered
  // process is used so simulators that enforce always_ff single-writer checks
  // across task boundaries (including UVS) preserve the intended transitions.
  always @(posedge clk or negedge rst_n) begin
    integer i, j;
    integer cp, src_beat, chi_lane, axi_lane, ordinal;
    logic [ADDR_WIDTH-1:0] abs_addr;
    logic [MAX_CHI_DAT_BEATS-1:0] need_mask, seen_int;

    if (!rst_n || !link_active) begin
      for (i = 0; i < PARENT_ENTRIES; i = i + 1) begin
        parent_state[i] <= P_FREE;
        parent_error[i] <= `CHI_RNI_AXI_OKAY;
        child_state[i]  <= C_FREE;
      end
      for (i = 0; i < (1 << AXI_ID_WIDTH); i = i + 1)
        axi_id_busy[i] <= 1'b0;
      w_collect_valid  <= 1'b0;
      w_collect_parent <= '0;
      protocol_error   <= 1'b0;
    end else begin

      // ---- service: issue the next child of every eligible parent -----
      for (i = 0; i < PARENT_ENTRIES; i = i + 1) begin
        if (parent_state[i] == P_ACTIVE && child_state[i] == C_FREE) begin
          if (parent_write[i]) ServiceWrite(i);
          else ServiceRead(i);
        end
      end

      // ---- AXI AR accept ----------------------------------------------
      if (s_axi_arvalid && s_axi_arready) begin
        for (i = 0; i < PARENT_ENTRIES; i = i + 1) begin
          if (parent_state[i] == P_FREE && !axi_id_busy[s_axi_arid]) begin
            // Use the current combinational legality result.  Reading the
            // just-scheduled parent_error here used its previous value and
            // could issue a child for a rejected AR.
            parent_state[i]    <= RequestLegal(s_axi_araddr, s_axi_arlen,
                                  s_axi_arsize, s_axi_arburst,
                                  s_axi_arprot[1], s_axi_arlock)
                                ? P_ACTIVE : P_RREADY;
            parent_write[i]    <= 1'b0;
            parent_id[i]       <= s_axi_arid;
            parent_addr[i]     <= s_axi_araddr;
            parent_len[i]      <= s_axi_arlen;
            parent_size[i]     <= s_axi_arsize;
            parent_burst[i]    <= s_axi_arburst;
            parent_beat[i]     <= '0;
            parent_beat_pos[i] <= '0;
            parent_error[i]    <= RequestLegal(s_axi_araddr, s_axi_arlen,
                                  s_axi_arsize, s_axi_arburst,
                                  s_axi_arprot[1], s_axi_arlock)
                                  ? `CHI_RNI_AXI_OKAY : `CHI_RNI_AXI_DECERR;
            axi_id_busy[s_axi_arid] <= 1'b1;
          end
        end
      end

      // ---- AXI AW accept ----------------------------------------------
      if (s_axi_awvalid && s_axi_awready) begin
        for (i = 0; i < PARENT_ENTRIES; i = i + 1) begin
          if (parent_state[i] == P_FREE && !w_collect_valid &&
              !axi_id_busy[s_axi_awid]) begin
            parent_state[i]    <= P_WCOLLECT;
            parent_write[i]    <= 1'b1;
            parent_id[i]       <= s_axi_awid;
            parent_addr[i]     <= s_axi_awaddr;
            parent_len[i]      <= s_axi_awlen;
            parent_size[i]     <= s_axi_awsize;
            parent_burst[i]    <= s_axi_awburst;
            parent_wcount[i]   <= '0;
            parent_beat[i]     <= '0;
            parent_beat_pos[i] <= '0;
            parent_error[i]    <= WriteRequestLegal(s_axi_awaddr, s_axi_awlen,
                                  s_axi_awsize, s_axi_awburst,
                                  s_axi_awprot[1], s_axi_awlock)
                                  ? `CHI_RNI_AXI_OKAY : `CHI_RNI_AXI_DECERR;
            axi_id_busy[s_axi_awid] <= 1'b1;
            w_collect_valid  <= 1'b1;
            w_collect_parent <= i[PARENT_BITS-1:0];
          end
        end
      end

      // ---- AXI W collect ----------------------------------------------
      if (s_axi_wvalid && s_axi_wready) begin
        $display("CHI_RNI_CORE_TRACE: accept W last=%0b count=%0d len=%0d", 
                 s_axi_wlast, parent_wcount[w_collect_parent],
                 parent_len[w_collect_parent]);
        cp = w_collect_parent;
        parent_wdata[cp][parent_wcount[cp]] <= s_axi_wdata;
        parent_wstrb[cp][parent_wcount[cp]] <= s_axi_wstrb;
        if (s_axi_wlast != (parent_wcount[cp] == parent_len[cp])) begin
          protocol_error        <= 1'b1;
          parent_error[cp]      <= `CHI_RNI_AXI_SLVERR;
        end
        if (s_axi_wlast || parent_wcount[cp] == parent_len[cp]) begin
          w_collect_valid <= 1'b0;
          // WLAST can arrive long after AW, but do not use the registered
          // error as the admission decision.  Re-evaluate the descriptor.
          if (WriteRequestLegal(parent_addr[cp], parent_len[cp],
                                parent_size[cp], parent_burst[cp],
                                FORCE_NONSECURE, 1'b0) &&
              (s_axi_wlast == (parent_wcount[cp] == parent_len[cp])))
            parent_state[cp] <= P_ACTIVE;   // service loop issues first child
          else
            parent_state[cp] <= P_BREADY;
          $display("CHI_RNI_CORE_TRACE: complete W legal=%0b addr=0x%0h size=%0d burst=%0b -> state=%0d",
                   WriteRequestLegal(parent_addr[cp], parent_len[cp],
                                     parent_size[cp], parent_burst[cp],
                                     FORCE_NONSECURE, 1'b0), parent_addr[cp],
                   parent_size[cp], parent_burst[cp],
                   WriteRequestLegal(parent_addr[cp], parent_len[cp],
                                     parent_size[cp], parent_burst[cp],
                                     FORCE_NONSECURE, 1'b0) ? P_ACTIVE : P_BREADY);
        end else begin
          parent_wcount[cp] <= parent_wcount[cp] + 1'b1;
        end
      end

      // ---- CHI REQ handshake ------------------------------------------
      if (chi_txreq_valid && chi_txreq_ready) begin
        if (parent_write[req_child]) child_state[req_child] <= C_WDBID;
        else                          child_state[req_child] <= C_RDATA;
      end

      // ---- CHI RX data (read return) ----------------------------------
      if (chi_rxdat_valid && chi_rxdat_ready) begin
        if (!dat_match || child_state[dat_child] != C_RDATA) begin
          protocol_error <= 1'b1;
        end else begin
          cp      = dat_child;
          ordinal = -1;
          for (j = 0; j < MAX_CHI_DAT_BEATS; j = j + 1) begin
            if (j < child_dat_needed[cp] &&
                chi_rxdat_data_id == chi_rni_expected_dataid(DATAID_LAYOUT,
                    child_addr[cp], child_size[cp], j, CHI_BYTES_LOG2))
              ordinal = j;
          end
          if (ordinal < 0 || ordinal >= child_dat_needed[cp]) begin
            protocol_error   <= 1'b1;
            parent_error[cp] <= `CHI_RNI_AXI_SLVERR;
            // A failed child must not expose a partially valid AXI beat.
            for (j = 0; j < MAX_AXI_BEATS; j = j + 1)
              parent_rdata[cp][j] <= '0;
            // Drain and complete it.
            for (j = 0; j < (1 << child_size[cp]); j = j + 1) begin
              abs_addr = child_addr[cp] + j;
              axi_lane = abs_addr[AXI_BYTES_LOG2-1:0];
              src_beat = (parent_burst[cp] == `CHI_RNI_AXI_BURST_FIXED)
                       ? parent_beat[cp]
                       : ((abs_addr - parent_addr[cp]) >> parent_size[cp]);
              parent_rdata[cp][src_beat][8*axi_lane +: 8] <= '0;
            end
            CompleteReadChild(cp);
          end else if (child_dat_seen[cp][ordinal] ||
              (ORDER_POLICY == `CHI_RNI_ORDER_POLICY_IN_ORDER &&
               ordinal != $countones(child_dat_seen[cp]))) begin
            protocol_error <= 1'b1;   // duplicate or out-of-order DataID
          end else begin
            if (chi_rxdat_resp_err != 2'b00) begin
              parent_error[cp] <= `CHI_RNI_AXI_SLVERR;
              for (j = 0; j < MAX_AXI_BEATS; j = j + 1)
                parent_rdata[cp][j] <= '0;
              for (j = 0; j < (1 << child_size[cp]); j = j + 1) begin
                abs_addr = child_addr[cp] + j;
                axi_lane = abs_addr[AXI_BYTES_LOG2-1:0];
                src_beat = (parent_burst[cp] == `CHI_RNI_AXI_BURST_FIXED)
                         ? parent_beat[cp]
                         : ((abs_addr - parent_addr[cp]) >> parent_size[cp]);
                parent_rdata[cp][src_beat][8*axi_lane +: 8] <= '0;
              end
            end else begin
              for (j = 0; j < CHI_BYTES; j = j + 1) begin
                if ((ordinal * CHI_BYTES + j) < (1 << child_size[cp])) begin
                  abs_addr = child_addr[cp] + (ordinal * CHI_BYTES) + j;
                  chi_lane = abs_addr[CHI_BYTES_LOG2-1:0];
                  axi_lane = abs_addr[AXI_BYTES_LOG2-1:0];
                  src_beat = (parent_burst[cp] == `CHI_RNI_AXI_BURST_FIXED)
                           ? parent_beat[cp]
                           : ((abs_addr - parent_addr[cp]) >> parent_size[cp]);
                  parent_rdata[cp][src_beat][8*axi_lane +: 8] <=
                      chi_rxdat_data[8*chi_lane +: 8];
                end
              end
            end
            seen_int = child_dat_seen[cp] |
                ({{(MAX_CHI_DAT_BEATS-1){1'b0}}, 1'b1} << ordinal);
            child_dat_seen[cp] <= seen_int;
            need_mask = ({{(MAX_CHI_DAT_BEATS-1){1'b0}}, 1'b1}
                         << child_dat_needed[cp]) - 1'b1;
            if (seen_int == need_mask) CompleteReadChild(cp);
          end
        end
      end

      // ---- CHI RX response (write completion) -------------------------
      if (chi_rxrsp_valid && chi_rxrsp_ready) begin
        if (!rsp_match) begin
          protocol_error <= 1'b1;
        end else begin
          cp = rsp_child;
          if (chi_rxrsp_resp_err != 2'b00)
            parent_error[cp] <= `CHI_RNI_AXI_SLVERR;
          case (child_state[cp])
            C_WDBID: begin
              if (chi_rxrsp_kind == `CHI_RNI_RSP_DBIDRESP ||
                  chi_rxrsp_kind == `CHI_RNI_RSP_COMPDBIDRESP) begin
                if (chi_rxrsp_resp_err != 2'b00) begin
                  // Scheme 6.5: non-OK DBIDResp -> SLVERR, no DAT.
                  CompleteWriteChild(cp);
                end else begin
                  child_dbid[cp] <= chi_rxrsp_dbid;
                  child_comp_included[cp] <=
                      (chi_rxrsp_kind == `CHI_RNI_RSP_COMPDBIDRESP);
                  child_completion_seen[cp] <=
                      (chi_rxrsp_kind == `CHI_RNI_RSP_COMPDBIDRESP);
                  child_state[cp] <= C_WDATA;
                end
              end else begin
                // bare Comp before DBID: protocol error (Scheme 6.5).
                protocol_error   <= 1'b1;
                parent_error[cp] <= `CHI_RNI_AXI_SLVERR;
                CompleteWriteChild(cp);
              end
            end
            C_WCOMP: begin
              if (chi_rxrsp_kind == `CHI_RNI_RSP_COMP)
                CompleteWriteChild(cp);
              else begin
                protocol_error   <= 1'b1;
                parent_error[cp] <= `CHI_RNI_AXI_SLVERR;
                CompleteWriteChild(cp);
              end
            end
            C_WDATA: begin
              if (chi_rxrsp_kind == `CHI_RNI_RSP_COMP &&
                  !child_completion_seen[cp]) begin
                // A bare Comp may arrive after DBIDResp but before the last
                // write DAT.  Latch it and finish when all DAT packets send.
                child_completion_seen[cp] <= 1'b1;
              end else begin
                protocol_error   <= 1'b1;
                parent_error[cp] <= `CHI_RNI_AXI_SLVERR;
              end
            end
            default: protocol_error <= 1'b1;
          endcase
        end
      end

      // ---- CHI TX data (write data beat) ------------------------------
      if (chi_txdat_valid && chi_txdat_ready) begin
        cp = dat_tx_child;
        if (child_wdat_ordinal[cp] + 1 < child_dat_needed[cp])
          child_wdat_ordinal[cp] <= child_wdat_ordinal[cp] + 1'b1;
        else if (child_completion_seen[cp])
          CompleteWriteChild(cp);           // CompDBIDResp: last DAT -> done
        else
          child_state[cp] <= C_WCOMP;        // wait for final Comp
      end

      // ---- AXI R drain ------------------------------------------------
      if (s_axi_rvalid && s_axi_rready) begin
        if (s_axi_rlast) begin
          axi_id_busy[parent_id[r_select]] <= 1'b0;
          parent_state[r_select] <= P_FREE;
        end else if (parent_error[r_select] == `CHI_RNI_AXI_DECERR) begin
          // Rejected read: keep draining error beats, issue no children.
          parent_beat[r_select]     <= parent_beat[r_select] + 1'b1;
          parent_beat_pos[r_select] <= '0;
        end else if (parent_beat[r_select] + 1 < parent_ready_until[r_select]) begin
          parent_beat[r_select] <= parent_beat[r_select] + 1'b1;
          parent_beat_pos[r_select] <= '0;
        end else begin
          parent_beat[r_select]     <= parent_beat[r_select] + 1'b1;
          parent_beat_pos[r_select] <= '0;
          parent_state[r_select]    <= P_ACTIVE;
        end
      end

      // ---- AXI B drain ------------------------------------------------
      if (s_axi_bvalid && s_axi_bready) begin
        axi_id_busy[parent_id[b_select]] <= 1'b0;
        parent_state[b_select] <= P_FREE;
      end

    end
  end

endmodule
