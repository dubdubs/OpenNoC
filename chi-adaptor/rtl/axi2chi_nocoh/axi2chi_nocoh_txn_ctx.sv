// Single owner of AXI parent, CHI child, TxnID, DBID, and retire state.

`default_nettype none

module axi2chi_nocoh_txn_ctx #(
  parameter int unsigned AxiAddrWidth = 64,
  parameter int unsigned AxiDataWidth = 128,
  parameter int unsigned AxiIdWidth = 4,
  parameter int unsigned AxlenWidth = 8,
  parameter int unsigned AxsizeWidth = 3,
  parameter int unsigned ChiTxnidWidth = 12,
  parameter int unsigned ChiDbidWidth = 12,
  parameter int unsigned ParentEntries = 16,
  parameter int unsigned ChildEntries = 16,
  parameter int unsigned TxnidEntries = ChildEntries,
  parameter int unsigned MaxAxiBeats = 256,
  parameter int unsigned CacheLineBytes = 64
) (
  input logic clk,
  input logic rst,
  input logic rd_admit_valid_i,
  output logic rd_admit_ready_o,
  input logic [AxiIdWidth-1:0] rd_admit_id_i,
  input logic [AxiAddrWidth-1:0] rd_admit_addr_i,
  input logic [AxlenWidth-1:0] rd_admit_len_i,
  input logic [AxsizeWidth-1:0] rd_admit_size_i,
  input logic [1:0] rd_admit_burst_i,
  input logic wr_admit_valid_i,
  output logic wr_admit_ready_o,
  input logic [AxiIdWidth-1:0] wr_admit_id_i,
  input logic [AxiAddrWidth-1:0] wr_admit_addr_i,
  input logic [AxlenWidth-1:0] wr_admit_len_i,
  input logic [AxsizeWidth-1:0] wr_admit_size_i,
  input logic [1:0] wr_admit_burst_i,
  output logic [$clog2(ParentEntries)-1:0] rd_admit_parent_idx_o,
  output logic [$clog2(ParentEntries)-1:0] wr_admit_parent_idx_o,
  output logic rd_issue_valid_o,
  input logic rd_issue_ready_i,
  output logic [$clog2(ParentEntries)-1:0] rd_issue_parent_idx_o,
  output logic [AxiAddrWidth-1:0] rd_issue_addr_o,
  output logic [AxlenWidth-1:0] rd_issue_axi_beat_o,
  output logic [1:0] rd_issue_frag_idx_o,
  output logic wr_issue_valid_o,
  input logic wr_issue_ready_i,
  output logic [$clog2(ParentEntries)-1:0] wr_issue_parent_idx_o,
  output logic [AxiAddrWidth-1:0] wr_issue_addr_o,
  output logic [AxlenWidth-1:0] wr_issue_axi_beat_o,
  output logic [1:0] wr_issue_frag_idx_o,
  output logic wr_issue_full_candidate_o,
  input logic child_alloc_valid_i,
  output logic child_alloc_ready_o,
  input logic [$clog2(ParentEntries)-1:0] child_alloc_parent_idx_i,
  input logic child_alloc_is_write_i,
  input logic [AxlenWidth-1:0] child_alloc_axi_beat_i,
  input logic [AxiAddrWidth-1:0] child_alloc_addr_i,
  input logic [1:0] child_alloc_frag_idx_i,
  output logic [$clog2(ChildEntries)-1:0] child_alloc_idx_o,
  output logic [ChiTxnidWidth-1:0] child_alloc_txnid_o,
  output logic child_alloc_last_fragment_o,
  output logic [$clog2(AxiDataWidth / 8 + 1)-1:0] child_alloc_axi_byte_offset_o,
  output logic [$clog2(CacheLineBytes)-1:0] child_alloc_line_byte_offset_o,
  output logic [$clog2(AxiDataWidth / 8 + 1)-1:0] child_alloc_fragment_byte_count_o,
  input logic child_release_valid_i,
  output logic child_release_ready_o,
  input logic [$clog2(ChildEntries)-1:0] child_release_idx_i,
  // An AXI response handshake retires one read beat or an entire write
  // parent.  txn_ctx owns the resulting child/TxnID release sequence.
  input logic axi_beat_retire_valid_i,
  input logic [$clog2(ParentEntries)-1:0] axi_beat_retire_parent_idx_i,
  input logic [AxlenWidth-1:0] axi_beat_retire_beat_i,
  input logic axi_beat_retire_all_i,
  input logic child_event_valid_i,
  input logic [$clog2(ChildEntries)-1:0] child_event_idx_i,
  input logic [2:0] child_event_type_i,
  input logic [ChiDbidWidth-1:0] child_event_dbid_i,
  input logic [1:0] child_event_resp_i,
  output logic [$clog2(ParentEntries)-1:0] child_event_parent_idx_o,
  output logic child_event_parent_complete_o,
  output logic child_event_parent_error_o,
  input logic child_lookup_valid_i,
  input logic [$clog2(ChildEntries)-1:0] child_lookup_idx_i,
  output logic child_lookup_valid_o,
  output logic [$clog2(ParentEntries)-1:0] child_lookup_parent_idx_o,
  output logic [AxiIdWidth-1:0] child_lookup_axi_id_o,
  output logic child_lookup_is_write_o,
  output logic child_lookup_last_o,
  output logic [AxlenWidth-1:0] child_lookup_axi_beat_o,
  output logic [1:0] child_lookup_frag_idx_o,
  output logic child_lookup_last_fragment_o,
  output logic [$clog2(AxiDataWidth / 8 + 1)-1:0] child_lookup_axi_byte_offset_o,
  output logic [$clog2(CacheLineBytes)-1:0] child_lookup_line_byte_offset_o,
  output logic [$clog2(AxiDataWidth / 8 + 1)-1:0] child_lookup_fragment_byte_count_o,
  input logic parent_retire_valid_i,
  input logic [$clog2(ParentEntries)-1:0] parent_retire_idx_i,
  output logic parent_retire_ready_o,
  input logic parent_retire_query_valid_i,
  input logic [$clog2(ParentEntries)-1:0] parent_retire_query_idx_i,
  output logic parent_retire_query_permit_o,
  output logic [ParentEntries-1:0] parent_retire_permit_vec_o,
  input logic parent_lookup_valid_i,
  input logic [$clog2(ParentEntries)-1:0] parent_lookup_idx_i,
  output logic [AxiIdWidth-1:0] parent_lookup_axi_id_o
);

  localparam int unsigned ParentIndexWidth = $clog2(ParentEntries);
  localparam int unsigned ChildIndexWidth = $clog2(ChildEntries);
  localparam int unsigned BeatIndexWidth = $clog2(MaxAxiBeats);
  localparam int unsigned BeatCountWidth = $clog2(MaxAxiBeats + 1);
  localparam int unsigned AxiByteCountWidth = $clog2(AxiDataWidth / 8 + 1);
  localparam int unsigned LineOffsetWidth = $clog2(CacheLineBytes);
  localparam int unsigned AxiIdCount = 1 << AxiIdWidth;

  typedef enum logic [2:0] {
    kChildEventReqSent,
    kChildEventDbid,
    kChildEventDatSent,
    kChildEventComp,
    kChildEventRxdat,
    kChildEventError
  } child_event_t;

  typedef struct packed {
    logic valid;
    logic is_write;
    logic [AxiIdWidth-1:0] axi_id;
    logic [AxiAddrWidth-1:0] start_addr;
    logic [AxlenWidth-1:0] len;
    logic [AxsizeWidth-1:0] size;
    logic [1:0] burst;
    logic [BeatIndexWidth-1:0] next_issue_beat;
    logic [1:0] next_issue_frag;
    logic [BeatIndexWidth-1:0] next_retire_beat;
    logic [1:0] next_retire_frag;
    logic [BeatCountWidth-1:0] completed_beat_count;
    logic error_seen;
    logic all_children_issued;
    logic all_children_complete;
  } parent_t;

  typedef struct packed {
    logic valid;
    logic is_write;
    logic [ParentIndexWidth-1:0] parent_idx;
    logic [BeatIndexWidth-1:0] axi_beat_idx;
    logic [1:0] frag_idx;
    logic [AxiAddrWidth-1:0] addr;
    logic [AxiByteCountWidth-1:0] axi_byte_offset;
    logic [LineOffsetWidth-1:0] line_byte_offset;
    logic [AxiByteCountWidth-1:0] fragment_byte_count;
    logic [ChiTxnidWidth-1:0] txnid;
    logic [ChiDbidWidth-1:0] dbid;
    logic dbid_valid;
    logic req_sent;
    logic dat_sent;
    logic comp_seen;
    logic rxdat_seen;
    logic error_seen;
  } child_t;

  parent_t parent_q [ParentEntries];
  child_t child_q [ChildEntries];
  logic [ParentEntries-1:0] parent_free_q;
  logic [ChildEntries-1:0] child_free_q;
  logic [TxnidEntries-1:0] txnid_valid_q;
  logic [ChildEntries-1:0] child_release_pending_q;
  logic [ParentIndexWidth-1:0] id_retire_fifo_q [AxiIdCount][ParentEntries];
  logic [ParentIndexWidth-1:0] id_retire_wr_ptr_q [AxiIdCount];
  logic [ParentIndexWidth-1:0] id_retire_rd_ptr_q [AxiIdCount];
  logic [ParentIndexWidth:0] id_retire_count_q [AxiIdCount];
  logic [ChildIndexWidth-1:0] txnid_child_q [TxnidEntries];
  logic [ParentIndexWidth-1:0] parent_alloc_idx;
  logic parent_free_found;
  logic rd_id_blocked;
  logic wr_id_blocked;
  logic admit_prefer_read_q;
  logic rd_admit_fire;
  logic wr_admit_fire;
  logic parent_retire_fire;
  logic [ChildIndexWidth-1:0] child_alloc_idx;
  logic child_free_found;
  logic [ChiTxnidWidth-1:0] txnid_alloc_id;
  logic txnid_free_found;
  logic child_alloc_fire;
  logic child_release_fire;
  logic child_release_pending_found;
  logic [ChildIndexWidth-1:0] child_release_pending_idx;
  logic child_event_fire;
  logic child_event_completes;
  logic child_completion_new;
  logic child_beat_completion_new;
  logic rd_issue_fire;
  logic wr_issue_fire;
  logic [ParentIndexWidth-1:0] child_event_parent_idx;
  logic [BeatCountWidth-1:0] parent_completed_beat_next;
  logic [BeatCountWidth-1:0] parent_expected_beat_count;
  logic [AxiAddrWidth-1:0] child_alloc_beat_bytes;
  logic [AxiAddrWidth-1:0] child_alloc_beat_addr;
  logic [AxiAddrWidth-1:0] child_alloc_line_remaining;
  logic [AxiAddrWidth-1:0] child_alloc_fragment_bytes;
  logic rd_issue_crosses_line;
  logic child_event_crosses_line;

  // The frozen profile supports only FIXED and INCR.  Admission owns rejection
  // of unsupported burst encodings; an admitted command is therefore either
  // FIXED or INCR, and this datapath does not encode WRAP behavior.
  function automatic logic [AxiAddrWidth-1:0] axi_beat_addr(
      input logic [AxiAddrWidth-1:0] start_addr,
      input logic [AxsizeWidth-1:0] size,
      input logic [1:0] burst,
      input logic [BeatIndexWidth-1:0] beat_idx);
    logic [AxiAddrWidth-1:0] advanced_addr;
    begin
      advanced_addr = start_addr + (AxiAddrWidth'(beat_idx) << size);
      unique case (burst)
        2'b00: axi_beat_addr = start_addr;
        default: axi_beat_addr = advanced_addr;
      endcase
    end
  endfunction

  always_comb begin
    parent_alloc_idx = '0;
    parent_free_found = 1'b0;
    rd_id_blocked = 1'b0;
    wr_id_blocked = 1'b0;
    for (int unsigned idx = 0; idx < ParentEntries; idx++) begin
      if (parent_free_q[idx] && !parent_free_found) begin
        parent_alloc_idx = ParentIndexWidth'(idx);
        parent_free_found = 1'b1;
      end
    end
    rd_admit_ready_o = 1'b0;
    wr_admit_ready_o = 1'b0;
    rd_admit_parent_idx_o = parent_alloc_idx;
    wr_admit_parent_idx_o = parent_alloc_idx;
    rd_issue_valid_o = 1'b0;
    rd_issue_parent_idx_o = '0;
    rd_issue_addr_o = '0;
    rd_issue_axi_beat_o = '0;
    rd_issue_frag_idx_o = '0;
    wr_issue_valid_o = 1'b0;
    wr_issue_parent_idx_o = '0;
    wr_issue_addr_o = '0;
    wr_issue_axi_beat_o = '0;
    wr_issue_frag_idx_o = '0;
    wr_issue_full_candidate_o = 1'b0;
    for (int unsigned idx = 0; idx < ParentEntries; idx++) begin
      if (!rd_issue_valid_o && parent_q[idx].valid &&
          !parent_q[idx].is_write &&
          parent_q[idx].next_issue_beat <= parent_q[idx].len &&
          parent_q[idx].next_issue_beat == parent_q[idx].next_retire_beat &&
          parent_q[idx].next_issue_frag == parent_q[idx].next_retire_frag) begin
        rd_issue_valid_o = !rst;
        rd_issue_parent_idx_o = ParentIndexWidth'(idx);
        rd_issue_axi_beat_o = parent_q[idx].next_issue_beat;
        rd_issue_frag_idx_o = parent_q[idx].next_issue_frag;
        rd_issue_addr_o = axi_beat_addr(parent_q[idx].start_addr,
            parent_q[idx].size, parent_q[idx].burst,
            parent_q[idx].next_issue_beat);
        if (parent_q[idx].next_issue_frag != 0) begin
          rd_issue_addr_o = (rd_issue_addr_o &
              ~AxiAddrWidth'(CacheLineBytes - 1)) +
              AxiAddrWidth'(CacheLineBytes);
        end
      end
      if (!wr_issue_valid_o && parent_q[idx].valid &&
          parent_q[idx].is_write &&
          parent_q[idx].next_issue_beat <= parent_q[idx].len &&
          parent_q[idx].next_issue_beat == parent_q[idx].next_retire_beat &&
          parent_q[idx].next_issue_frag == parent_q[idx].next_retire_frag) begin
        wr_issue_valid_o = !rst;
        wr_issue_parent_idx_o = ParentIndexWidth'(idx);
        wr_issue_axi_beat_o = parent_q[idx].next_issue_beat;
        wr_issue_frag_idx_o = parent_q[idx].next_issue_frag;
        wr_issue_addr_o = axi_beat_addr(parent_q[idx].start_addr,
            parent_q[idx].size, parent_q[idx].burst,
            parent_q[idx].next_issue_beat);
        if (parent_q[idx].next_issue_frag != 0) begin
          wr_issue_addr_o = (wr_issue_addr_o &
              ~AxiAddrWidth'(CacheLineBytes - 1)) +
            AxiAddrWidth'(CacheLineBytes);
        end
        wr_issue_full_candidate_o = parent_q[idx].len == 0 &&
            parent_q[idx].size == $clog2(CacheLineBytes) &&
            (wr_issue_addr_o & AxiAddrWidth'(CacheLineBytes - 1)) == 0 &&
            AxiDataWidth / 8 == CacheLineBytes;
      end
    end
    rd_issue_crosses_line = (rd_issue_addr_o & AxiAddrWidth'(CacheLineBytes - 1)) +
        (AxiAddrWidth'(1) << parent_q[rd_issue_parent_idx_o].size) >
        AxiAddrWidth'(CacheLineBytes);
    child_alloc_idx = '0;
    child_free_found = 1'b0;
    for (int unsigned idx = 0; idx < ChildEntries; idx++) begin
      if (child_free_q[idx] && !child_free_found) begin
        child_alloc_idx = ChildIndexWidth'(idx);
        child_free_found = 1'b1;
      end
    end

    txnid_alloc_id = '0;
    txnid_free_found = 1'b0;
    for (int unsigned idx = 0; idx < TxnidEntries; idx++) begin
      if (!txnid_valid_q[idx] && !txnid_free_found) begin
        txnid_alloc_id = ChiTxnidWidth'(idx);
        txnid_free_found = 1'b1;
      end
    end

    child_alloc_ready_o = 1'b0;
    child_alloc_idx_o = child_alloc_idx;
    child_alloc_txnid_o = txnid_alloc_id;
    child_release_ready_o = 1'b0;
    parent_retire_ready_o = 1'b0;
    parent_retire_query_permit_o = 1'b0;
    parent_retire_permit_vec_o = '0;
    for (int unsigned idx = 0; idx < ParentEntries; idx++) begin
      if (parent_q[idx].valid &&
          id_retire_count_q[parent_q[idx].axi_id] != 0 &&
          id_retire_fifo_q[parent_q[idx].axi_id]
              [id_retire_rd_ptr_q[parent_q[idx].axi_id]] == ParentIndexWidth'(idx)) begin
        parent_retire_permit_vec_o[idx] = 1'b1;
      end
    end
    if (!rst && parent_retire_query_valid_i &&
        parent_q[parent_retire_query_idx_i].valid) begin
      parent_retire_query_permit_o = id_retire_count_q[
          parent_q[parent_retire_query_idx_i].axi_id] != 0 &&
          id_retire_fifo_q[parent_q[parent_retire_query_idx_i].axi_id]
              [id_retire_rd_ptr_q[parent_q[parent_retire_query_idx_i].axi_id]] ==
              parent_retire_query_idx_i;
    end

    if (!rst && parent_free_found) begin
      if (rd_admit_valid_i && id_retire_count_q[rd_admit_id_i] < ParentEntries &&
          wr_admit_valid_i && id_retire_count_q[wr_admit_id_i] < ParentEntries) begin
        if (admit_prefer_read_q) begin
          rd_admit_ready_o = 1'b1;
        end else begin
          wr_admit_ready_o = 1'b1;
        end
      end else if (rd_admit_valid_i && id_retire_count_q[rd_admit_id_i] < ParentEntries) begin
        rd_admit_ready_o = 1'b1;
      end else if (wr_admit_valid_i && id_retire_count_q[wr_admit_id_i] < ParentEntries) begin
        wr_admit_ready_o = 1'b1;
      end
    end

    if (!rst && parent_q[parent_retire_idx_i].valid &&
        id_retire_count_q[parent_q[parent_retire_idx_i].axi_id] != 0 &&
        id_retire_fifo_q[parent_q[parent_retire_idx_i].axi_id]
            [id_retire_rd_ptr_q[parent_q[parent_retire_idx_i].axi_id]] ==
            parent_retire_idx_i) begin
      parent_retire_ready_o = 1'b1;
    end

    if (!rst && child_free_found && txnid_free_found &&
        parent_q[child_alloc_parent_idx_i].valid) begin
      child_alloc_ready_o = 1'b1;
    end

    child_release_pending_found = 1'b0;
    child_release_pending_idx = '0;
    for (int unsigned idx = 0; idx < ChildEntries; idx++) begin
      if (child_release_pending_q[idx] && child_q[idx].valid &&
          !child_release_pending_found) begin
        child_release_pending_found = 1'b1;
        child_release_pending_idx = ChildIndexWidth'(idx);
      end
    end
    // Legacy external release inputs are intentionally no longer consumed.
    child_release_ready_o = child_release_pending_found;

    rd_admit_fire = rd_admit_valid_i && rd_admit_ready_o;
    wr_admit_fire = wr_admit_valid_i && wr_admit_ready_o;
    parent_retire_fire = parent_retire_valid_i && parent_retire_ready_o;
    child_alloc_fire = child_alloc_valid_i && child_alloc_ready_o;
    child_release_fire = child_release_pending_found;
    child_event_fire = child_event_valid_i && child_q[child_event_idx_i].valid;
    rd_issue_fire = rd_issue_valid_o && rd_issue_ready_i;
    wr_issue_fire = wr_issue_valid_o && wr_issue_ready_i;
    child_lookup_valid_o = 1'b0;
    child_lookup_parent_idx_o = '0;
    child_lookup_axi_id_o = '0;
    child_lookup_is_write_o = 1'b0;
    child_lookup_last_o = 1'b0;
    child_lookup_axi_beat_o = '0;
    child_lookup_frag_idx_o = '0;
    child_lookup_last_fragment_o = 1'b0;
    child_lookup_axi_byte_offset_o = '0;
    child_lookup_line_byte_offset_o = '0;
    child_lookup_fragment_byte_count_o = '0;
    parent_lookup_axi_id_o = '0;
    if (!rst && parent_lookup_valid_i && parent_q[parent_lookup_idx_i].valid) begin
      parent_lookup_axi_id_o = parent_q[parent_lookup_idx_i].axi_id;
    end
    if (!rst && child_lookup_valid_i && child_q[child_lookup_idx_i].valid &&
        parent_q[child_q[child_lookup_idx_i].parent_idx].valid) begin
      child_lookup_valid_o = 1'b1;
      child_lookup_parent_idx_o = child_q[child_lookup_idx_i].parent_idx;
      child_lookup_axi_id_o =
          parent_q[child_q[child_lookup_idx_i].parent_idx].axi_id;
      child_lookup_is_write_o = child_q[child_lookup_idx_i].is_write;
      child_lookup_last_o = child_q[child_lookup_idx_i].axi_beat_idx ==
          parent_q[child_q[child_lookup_idx_i].parent_idx].len;
      child_lookup_axi_beat_o = child_q[child_lookup_idx_i].axi_beat_idx;
      child_lookup_frag_idx_o = child_q[child_lookup_idx_i].frag_idx;
      child_lookup_last_fragment_o = child_q[child_lookup_idx_i].frag_idx != 0 ||
          ((child_q[child_lookup_idx_i].addr &
          AxiAddrWidth'(CacheLineBytes - 1)) +
          (AxiAddrWidth'(1) << parent_q[child_q[child_lookup_idx_i].parent_idx].size)
          <= AxiAddrWidth'(CacheLineBytes));
      child_lookup_axi_byte_offset_o =
          child_q[child_lookup_idx_i].axi_byte_offset;
      child_lookup_line_byte_offset_o =
          child_q[child_lookup_idx_i].line_byte_offset;
      child_lookup_fragment_byte_count_o =
          child_q[child_lookup_idx_i].fragment_byte_count;
    end
    child_event_parent_idx = child_q[child_event_idx_i].parent_idx;
    child_event_completes = 1'b0;
    if (child_event_type_i == kChildEventError) begin
      child_event_completes = 1'b1;
    end else if (child_q[child_event_idx_i].is_write) begin
      child_event_completes = child_event_type_i == kChildEventComp;
    end else begin
      child_event_completes = child_event_type_i == kChildEventRxdat;
    end
    child_completion_new = child_event_fire && child_event_completes &&
        !child_q[child_event_idx_i].comp_seen &&
        !child_q[child_event_idx_i].rxdat_seen &&
        !child_q[child_event_idx_i].error_seen;
    child_beat_completion_new = child_completion_new &&
        (child_q[child_event_idx_i].frag_idx != 0 ||
        !child_event_crosses_line);
    parent_completed_beat_next =
        parent_q[child_event_parent_idx].completed_beat_count + BeatCountWidth'(1);
    parent_expected_beat_count =
        BeatCountWidth'(parent_q[child_event_parent_idx].len) + BeatCountWidth'(1);
    child_alloc_beat_bytes = AxiAddrWidth'(1) <<
        parent_q[child_alloc_parent_idx_i].size;
    child_alloc_beat_addr = axi_beat_addr(
        parent_q[child_alloc_parent_idx_i].start_addr,
        parent_q[child_alloc_parent_idx_i].size,
        parent_q[child_alloc_parent_idx_i].burst,
        child_alloc_axi_beat_i);
    child_alloc_line_remaining = AxiAddrWidth'(CacheLineBytes) -
        (child_alloc_beat_addr & AxiAddrWidth'(CacheLineBytes - 1));
    if (child_alloc_frag_idx_i == 0) begin
      child_alloc_fragment_bytes = child_alloc_beat_bytes > child_alloc_line_remaining ?
          child_alloc_line_remaining : child_alloc_beat_bytes;
    end else begin
      child_alloc_fragment_bytes = child_alloc_beat_bytes - child_alloc_line_remaining;
    end
    child_alloc_last_fragment_o = child_alloc_frag_idx_i != 0 ||
        child_alloc_beat_bytes <= child_alloc_line_remaining;
    child_alloc_axi_byte_offset_o = child_alloc_frag_idx_i == 0 ? '0 :
        AxiByteCountWidth'(child_alloc_line_remaining);
    child_alloc_line_byte_offset_o = child_alloc_frag_idx_i == 0 ?
        child_alloc_beat_addr[LineOffsetWidth-1:0] : '0;
    child_alloc_fragment_byte_count_o =
        AxiByteCountWidth'(child_alloc_fragment_bytes);
    child_event_crosses_line =
        (child_q[child_event_idx_i].addr & AxiAddrWidth'(CacheLineBytes - 1)) +
        (AxiAddrWidth'(1) << parent_q[child_event_parent_idx].size) >
        AxiAddrWidth'(CacheLineBytes);
    child_event_parent_idx_o = child_event_parent_idx;
    child_event_parent_complete_o = child_beat_completion_new &&
        child_q[child_event_idx_i].is_write &&
        parent_completed_beat_next >= parent_expected_beat_count;
    child_event_parent_error_o = parent_q[child_event_parent_idx].error_seen ||
        child_event_type_i == kChildEventError || child_event_resp_i[1];
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      parent_free_q <= '1;
      child_free_q <= '1;
      txnid_valid_q <= '0;
      child_release_pending_q <= '0;
      admit_prefer_read_q <= 1'b1;
      for (int unsigned idx = 0; idx < ParentEntries; idx++) begin
        parent_q[idx] <= '0;
      end
      for (int unsigned idx = 0; idx < ChildEntries; idx++) begin
        child_q[idx] <= '0;
      end
      for (int unsigned idx = 0; idx < TxnidEntries; idx++) begin
        txnid_child_q[idx] <= '0;
      end
      for (int unsigned idx = 0; idx < AxiIdCount; idx++) begin
        id_retire_wr_ptr_q[idx] <= '0;
        id_retire_rd_ptr_q[idx] <= '0;
        id_retire_count_q[idx] <= '0;
      end
    end else begin
      if (rd_admit_fire || wr_admit_fire) begin
        id_retire_fifo_q[rd_admit_fire ? rd_admit_id_i : wr_admit_id_i]
            [id_retire_wr_ptr_q[rd_admit_fire ? rd_admit_id_i : wr_admit_id_i]] <=
            parent_alloc_idx;
        if (id_retire_wr_ptr_q[rd_admit_fire ? rd_admit_id_i : wr_admit_id_i] ==
            ParentEntries - 1) begin
          id_retire_wr_ptr_q[rd_admit_fire ? rd_admit_id_i : wr_admit_id_i] <= '0;
        end else begin
          id_retire_wr_ptr_q[rd_admit_fire ? rd_admit_id_i : wr_admit_id_i] <=
              id_retire_wr_ptr_q[rd_admit_fire ? rd_admit_id_i : wr_admit_id_i] + 1'b1;
        end
        if (!(parent_retire_fire &&
            parent_q[parent_retire_idx_i].axi_id ==
            (rd_admit_fire ? rd_admit_id_i : wr_admit_id_i))) begin
          id_retire_count_q[rd_admit_fire ? rd_admit_id_i : wr_admit_id_i] <=
              id_retire_count_q[rd_admit_fire ? rd_admit_id_i : wr_admit_id_i] + 1'b1;
        end
      end
      if (rd_admit_fire) begin
        parent_free_q[parent_alloc_idx] <= 1'b0;
        parent_q[parent_alloc_idx].valid <= 1'b1;
        parent_q[parent_alloc_idx].is_write <= 1'b0;
        parent_q[parent_alloc_idx].axi_id <= rd_admit_id_i;
        parent_q[parent_alloc_idx].start_addr <= rd_admit_addr_i;
        parent_q[parent_alloc_idx].len <= rd_admit_len_i;
        parent_q[parent_alloc_idx].size <= rd_admit_size_i;
        parent_q[parent_alloc_idx].burst <= rd_admit_burst_i;
        parent_q[parent_alloc_idx].next_issue_beat <= '0;
        parent_q[parent_alloc_idx].next_issue_frag <= '0;
        parent_q[parent_alloc_idx].next_retire_beat <= '0;
        parent_q[parent_alloc_idx].next_retire_frag <= '0;
        parent_q[parent_alloc_idx].completed_beat_count <= '0;
        parent_q[parent_alloc_idx].error_seen <= 1'b0;
        parent_q[parent_alloc_idx].all_children_issued <= 1'b0;
        parent_q[parent_alloc_idx].all_children_complete <= 1'b0;
        admit_prefer_read_q <= 1'b0;
      end else if (wr_admit_fire) begin
        parent_free_q[parent_alloc_idx] <= 1'b0;
        parent_q[parent_alloc_idx].valid <= 1'b1;
        parent_q[parent_alloc_idx].is_write <= 1'b1;
        parent_q[parent_alloc_idx].axi_id <= wr_admit_id_i;
        parent_q[parent_alloc_idx].start_addr <= wr_admit_addr_i;
        parent_q[parent_alloc_idx].len <= wr_admit_len_i;
        parent_q[parent_alloc_idx].size <= wr_admit_size_i;
        parent_q[parent_alloc_idx].burst <= wr_admit_burst_i;
        parent_q[parent_alloc_idx].next_issue_beat <= '0;
        parent_q[parent_alloc_idx].next_issue_frag <= '0;
        parent_q[parent_alloc_idx].next_retire_beat <= '0;
        parent_q[parent_alloc_idx].next_retire_frag <= '0;
        parent_q[parent_alloc_idx].completed_beat_count <= '0;
        parent_q[parent_alloc_idx].error_seen <= 1'b0;
        parent_q[parent_alloc_idx].all_children_issued <= 1'b0;
        parent_q[parent_alloc_idx].all_children_complete <= 1'b0;
        admit_prefer_read_q <= 1'b1;
      end

      if (parent_retire_fire) begin
        parent_q[parent_retire_idx_i].valid <= 1'b0;
        parent_free_q[parent_retire_idx_i] <= 1'b1;
        if (id_retire_rd_ptr_q[parent_q[parent_retire_idx_i].axi_id] ==
            ParentEntries - 1) begin
          id_retire_rd_ptr_q[parent_q[parent_retire_idx_i].axi_id] <= '0;
        end else begin
          id_retire_rd_ptr_q[parent_q[parent_retire_idx_i].axi_id] <=
              id_retire_rd_ptr_q[parent_q[parent_retire_idx_i].axi_id] + 1'b1;
        end
        if (!(rd_admit_fire || wr_admit_fire) ||
            parent_q[parent_retire_idx_i].axi_id !=
            (rd_admit_fire ? rd_admit_id_i : wr_admit_id_i)) begin
          id_retire_count_q[parent_q[parent_retire_idx_i].axi_id] <=
              id_retire_count_q[parent_q[parent_retire_idx_i].axi_id] - 1'b1;
        end
      end

      if (child_alloc_fire) begin
        child_free_q[child_alloc_idx] <= 1'b0;
        txnid_valid_q[txnid_alloc_id] <= 1'b1;
        txnid_child_q[txnid_alloc_id] <= child_alloc_idx;
        child_q[child_alloc_idx].valid <= 1'b1;
        child_q[child_alloc_idx].is_write <= child_alloc_is_write_i;
        child_q[child_alloc_idx].parent_idx <= child_alloc_parent_idx_i;
        child_q[child_alloc_idx].axi_beat_idx <= child_alloc_axi_beat_i;
        child_q[child_alloc_idx].frag_idx <= child_alloc_frag_idx_i;
        child_q[child_alloc_idx].addr <= child_alloc_addr_i;
        child_q[child_alloc_idx].axi_byte_offset <= child_alloc_frag_idx_i == 0 ?
            '0 : AxiByteCountWidth'(child_alloc_line_remaining);
        child_q[child_alloc_idx].line_byte_offset <= child_alloc_frag_idx_i == 0 ?
            child_alloc_addr_i[LineOffsetWidth-1:0] : '0;
        child_q[child_alloc_idx].fragment_byte_count <=
            AxiByteCountWidth'(child_alloc_fragment_bytes);
        child_q[child_alloc_idx].txnid <= txnid_alloc_id;
        child_q[child_alloc_idx].dbid <= '0;
        child_q[child_alloc_idx].dbid_valid <= 1'b0;
        child_q[child_alloc_idx].req_sent <= 1'b0;
        child_q[child_alloc_idx].dat_sent <= 1'b0;
        child_q[child_alloc_idx].comp_seen <= 1'b0;
        child_q[child_alloc_idx].rxdat_seen <= 1'b0;
        child_q[child_alloc_idx].error_seen <= 1'b0;
      end

      if (rd_issue_fire) begin
        if (rd_issue_crosses_line && rd_issue_frag_idx_o == 0) begin
          parent_q[rd_issue_parent_idx_o].next_issue_frag <= 2'd1;
        end else begin
          parent_q[rd_issue_parent_idx_o].next_issue_beat <=
              parent_q[rd_issue_parent_idx_o].next_issue_beat + 1'b1;
          parent_q[rd_issue_parent_idx_o].next_issue_frag <= '0;
        end
        parent_q[rd_issue_parent_idx_o].all_children_issued <=
            parent_q[rd_issue_parent_idx_o].next_issue_beat ==
            parent_q[rd_issue_parent_idx_o].len &&
            (!rd_issue_crosses_line || rd_issue_frag_idx_o == 2'd1);
      end

      if (wr_issue_fire) begin
        if ((wr_issue_addr_o & AxiAddrWidth'(CacheLineBytes - 1)) +
            (AxiAddrWidth'(1) << parent_q[wr_issue_parent_idx_o].size) >
            AxiAddrWidth'(CacheLineBytes) && wr_issue_frag_idx_o == 0) begin
          parent_q[wr_issue_parent_idx_o].next_issue_frag <= 2'd1;
        end else begin
          parent_q[wr_issue_parent_idx_o].next_issue_beat <=
              parent_q[wr_issue_parent_idx_o].next_issue_beat + 1'b1;
          parent_q[wr_issue_parent_idx_o].next_issue_frag <= '0;
        end
        parent_q[wr_issue_parent_idx_o].all_children_issued <=
            parent_q[wr_issue_parent_idx_o].next_issue_beat ==
            parent_q[wr_issue_parent_idx_o].len &&
            (!((wr_issue_addr_o & AxiAddrWidth'(CacheLineBytes - 1)) +
            (AxiAddrWidth'(1) << parent_q[wr_issue_parent_idx_o].size) >
            AxiAddrWidth'(CacheLineBytes)) || wr_issue_frag_idx_o != 0);
      end

      if (child_release_fire) begin
        child_free_q[child_release_pending_idx] <= 1'b1;
        txnid_valid_q[child_q[child_release_pending_idx].txnid] <= 1'b0;
        child_q[child_release_pending_idx].valid <= 1'b0;
        child_release_pending_q[child_release_pending_idx] <= 1'b0;
      end

      if (axi_beat_retire_valid_i) begin
        for (int unsigned idx = 0; idx < ChildEntries; idx++) begin
          if (child_q[idx].valid &&
              child_q[idx].parent_idx == axi_beat_retire_parent_idx_i &&
              (axi_beat_retire_all_i ||
               child_q[idx].axi_beat_idx == axi_beat_retire_beat_i)) begin
            child_release_pending_q[idx] <= 1'b1;
          end
        end
      end

      if (child_event_fire) begin
        unique case (child_event_type_i)
          kChildEventReqSent: begin
            child_q[child_event_idx_i].req_sent <= 1'b1;
          end
          kChildEventDbid: begin
            child_q[child_event_idx_i].dbid <= child_event_dbid_i;
            child_q[child_event_idx_i].dbid_valid <= 1'b1;
          end
          kChildEventDatSent: begin
            child_q[child_event_idx_i].dat_sent <= 1'b1;
          end
          kChildEventComp: begin
            child_q[child_event_idx_i].comp_seen <= 1'b1;
          end
          kChildEventRxdat: begin
            child_q[child_event_idx_i].rxdat_seen <= 1'b1;
          end
          kChildEventError: begin
            child_q[child_event_idx_i].error_seen <= 1'b1;
          end
          default: begin
            child_q[child_event_idx_i].error_seen <= 1'b1;
          end
        endcase

        if (child_event_resp_i[1]) begin
          child_q[child_event_idx_i].error_seen <= 1'b1;
        end

        if (child_beat_completion_new) begin
          parent_q[child_event_parent_idx].completed_beat_count <=
              parent_completed_beat_next;
          parent_q[child_event_parent_idx].all_children_complete <=
              parent_completed_beat_next >= parent_expected_beat_count;
        end

        if (child_completion_new) begin
          if (child_event_crosses_line && child_q[child_event_idx_i].frag_idx == 0) begin
            parent_q[child_event_parent_idx].next_retire_frag <= 2'd1;
          end else begin
            parent_q[child_event_parent_idx].next_retire_beat <=
                parent_q[child_event_parent_idx].next_retire_beat + 1'b1;
            parent_q[child_event_parent_idx].next_retire_frag <= '0;
          end
        end

        if (child_event_type_i == kChildEventError || child_event_resp_i[1]) begin
          parent_q[child_event_parent_idx].error_seen <= 1'b1;
        end
      end
    end
  end

  // Downstream engines consume the aggregated child state in later Step 4 stages.

endmodule

`default_nettype wire
