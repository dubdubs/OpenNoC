// Core transaction-state skeleton for the AXI-to-CHI RNI.
//
// This module will own parent/child lifetime, immutable policy snapshots,
// line hazards and canonical 64-byte data contexts. It deliberately has no
// AXI-to-CHI behavior in this skeleton stage.

`default_nettype none

module rni_core #(
  parameter int unsigned AxiAddrWidth = 64,
  parameter int unsigned AxiDataWidth = 32,
  parameter int unsigned AxiIdWidth = 4,
  parameter int unsigned AxlenWidth = 8,
  parameter int unsigned AxsizeWidth = 3,
  parameter int unsigned ParentEntries = 32,
  parameter int unsigned ChildEntries = ParentEntries,
  parameter int unsigned LineContextEntries = ParentEntries,
  parameter int unsigned LineHazardEntries = 64,
  parameter int unsigned PolicyEpochWidth = 8,
  parameter int unsigned ChieNidWidth = 7,
  parameter int unsigned ChieReqAddrWidth = 44,
  parameter logic [ChieNidWidth-1:0] RniNid = 7'd6,
  parameter int unsigned ChieTxnidWidth = 12,
  parameter int unsigned ChieDbidWidth = 12,
  parameter int unsigned ChieDataidWidth = 2,
  parameter int unsigned ReqFlitWidth = 131,
  parameter int unsigned RspFlitWidth = 73,
  parameter int unsigned DatFlitWidth = 406,
  parameter logic [AxiAddrWidth-1:0] PolicyCsrBase =
      64'h0000_0020_0000_0000,
  parameter logic [AxiAddrWidth-1:0] PolicyCsrSize =
      64'h0000_0000_0000_1000
) (
  input  logic                         clk,
  input  logic                         rst,

  // Internal AXI ingress command and write-data interfaces.
  input  logic                         write_cmd_valid_i,
  input  logic [AxiIdWidth-1:0]        write_cmd_id_i,
  input  logic [AxiAddrWidth-1:0]      write_cmd_addr_i,
  input  logic [AxlenWidth-1:0]        write_cmd_len_i,
  input  logic [AxsizeWidth-1:0]       write_cmd_size_i,
  input  logic [1:0]                   write_cmd_burst_i,
  output logic                         write_cmd_ready_o,
  input  logic                         write_data_valid_i,
  input  logic [AxiDataWidth-1:0]      write_data_i,
  input  logic [AxiDataWidth / 8-1:0]  write_strb_i,
  input  logic                         write_last_i,
  output logic                         write_data_ready_o,

  input  logic                         read_cmd_valid_i,
  input  logic [AxiIdWidth-1:0]        read_cmd_id_i,
  input  logic [AxiAddrWidth-1:0]      read_cmd_addr_i,
  input  logic [AxlenWidth-1:0]        read_cmd_len_i,
  input  logic [AxsizeWidth-1:0]       read_cmd_size_i,
  input  logic [1:0]                   read_cmd_burst_i,
  output logic                         read_cmd_ready_o,

  // Internal AXI response interfaces back to rni_axi_ingress.
  output logic                         write_rsp_valid_o,
  output logic [AxiIdWidth-1:0]        write_rsp_id_o,
  output logic [1:0]                   write_rsp_code_o,
  input  logic                         write_rsp_ready_i,
  output logic                         read_rsp_valid_o,
  output logic [AxiIdWidth-1:0]        read_rsp_id_o,
  output logic [AxiDataWidth-1:0]      read_rsp_data_o,
  output logic [1:0]                   read_rsp_code_o,
  output logic                         read_rsp_last_o,
  input  logic                         read_rsp_ready_i,

  // Address-only policy lookup and commit drain interfaces.
  output logic                         policy_lookup_valid_o,
  output logic [AxiAddrWidth-1:0]      policy_lookup_addr_o,
  input  logic                         policy_lookup_hit_i,
  input  logic [1:0]                   policy_region_type_i,
  input  logic [ChieNidWidth-1:0]      policy_target_nid_i,
  input  logic                         policy_ns_i,
  input  logic [1:0]                   policy_order_i,
  input  logic [3:0]                   policy_memattr_i,
  input  logic [PolicyEpochWidth-1:0]  policy_epoch_i,
  input  logic                         policy_quiesce_req_i,
  output logic                         policy_drain_done_o,

  // Decoded core-to-link requests. rni_xp_p0_link_ctl is the only raw-link
  // owner; core only uses ready/valid payload boundaries.
  output logic                         txreq_valid_o,
  output logic [ReqFlitWidth-1:0]      txreq_payload_o,
  input  logic                         txreq_ready_i,
  output logic                         txdat_valid_o,
  output logic [DatFlitWidth-1:0]      txdat_payload_o,
  input  logic                         txdat_ready_i,
  output logic                         txrsp_valid_o,
  output logic [RspFlitWidth-1:0]      txrsp_payload_o,
  input  logic                         txrsp_ready_i,
  input  logic                         rxrsp_valid_i,
  input  logic [RspFlitWidth-1:0]      rxrsp_payload_i,
  output logic                         rxrsp_ready_o,
  input  logic                         rxdat_valid_i,
  input  logic [DatFlitWidth-1:0]      rxdat_payload_i,
  output logic                         rxdat_ready_o
);

  localparam int unsigned ParentIndexWidth = $clog2(ParentEntries);
  localparam int unsigned ChildIndexWidth = $clog2(ChildEntries);
  localparam int unsigned LineContextIndexWidth = $clog2(LineContextEntries);
  localparam int unsigned LineHazardIndexWidth = $clog2(LineHazardEntries);
  localparam int unsigned LineAddrWidth = AxiAddrWidth - 6;
  localparam int unsigned MaxDatPerLine = 4;

  typedef enum logic [1:0] {
    kProfileNoncoherent,
    kProfileCoherent,
    kProfileInvalid
  } txn_profile_t;

  typedef enum logic [2:0] {
    kReadChildIdle,
    kReadChildSegment,
    kReadChildIssueReq,
    kReadChildWaitDat,
    kReadChildWaitPcrd,
    kReadChildPresentR,
    kReadChildErrorDrain
  } read_child_state_t;

  typedef enum logic [3:0] {
    kWriteChildIdle,
    kWriteChildCollect,
    kWriteChildFinalize,
    kWriteChildIssueReq,
    kWriteChildWaitDbid,
    kWriteChildSendDat,
    kWriteChildWaitComp,
    kWriteChildPresentB,
    kWriteChildErrorDrain
  } write_child_state_t;

  typedef struct packed {
    logic                               valid;
    logic                               is_write;
    logic [AxiIdWidth-1:0]              axi_id;
    logic [AxiAddrWidth-1:0]            start_addr;
    logic [AxlenWidth-1:0]              burst_len;
    logic [AxsizeWidth-1:0]             burst_size;
    logic [1:0]                         burst_type;
    txn_profile_t                       profile;
    logic [1:0]                         region_type;
    logic [ChieNidWidth-1:0]            target_nid;
    logic                               ns;
    logic [1:0]                         order;
    logic [3:0]                         memattr;
    logic [PolicyEpochWidth-1:0]        policy_epoch;
    logic [ChildIndexWidth-1:0]         child_index;
    logic [LineContextIndexWidth-1:0]   line_context_index;
    logic                               error_seen;
  } parent_context_t;

  typedef struct packed {
    logic                               valid;
    logic                               is_write;
    logic [ParentIndexWidth-1:0]        parent_index;
    logic [ChieTxnidWidth-1:0]           txnid;
    logic [ChieDbidWidth-1:0]            dbid;
    logic [ChieNidWidth-1:0]             responder_nid;
    logic                               dbid_valid;
    logic [MaxDatPerLine-1:0]            required_dat_mask;
    logic [MaxDatPerLine-1:0]            sent_dat_mask;
    logic [MaxDatPerLine-1:0]            received_dat_mask;
    logic                               retry_pending;
    logic                               comp_seen;
    logic                               error_seen;
  } child_context_t;

  typedef struct packed {
    logic                               valid;
    logic [LineAddrWidth-1:0]           line_addr;
    logic [511:0]                       data;
    logic [63:0]                        valid_byte_mask;
    logic [63:0]                        required_byte_mask;
    logic [63:0]                        dirty_byte_mask;
    logic [63:0]                        error_byte_mask;
  } line_context_t;

  typedef struct packed {
    logic                               valid;
    logic [LineAddrWidth-1:0]           line_addr;
    logic [ParentIndexWidth-1:0]        parent_index;
    txn_profile_t                       profile;
  } line_hazard_t;

  typedef struct packed {
    logic                               valid;
    logic                               is_policy_csr;
    logic                               policy_hit;
    logic [AxiIdWidth-1:0]              axi_id;
    logic [AxiAddrWidth-1:0]            addr;
    logic [AxlenWidth-1:0]              len;
    logic [AxsizeWidth-1:0]             size;
    logic [1:0]                         burst;
    logic [1:0]                         region_type;
    logic [ChieNidWidth-1:0]            target_nid;
    logic                               ns;
    logic [1:0]                         order;
    logic [3:0]                         memattr;
    logic [PolicyEpochWidth-1:0]        policy_epoch;
  } read_admission_snapshot_t;

  typedef struct packed {
    logic                               valid;
    logic                               is_policy_csr;
    logic                               policy_hit;
    logic [AxiIdWidth-1:0]              axi_id;
    logic [AxiAddrWidth-1:0]            addr;
    logic [AxlenWidth-1:0]              len;
    logic [AxsizeWidth-1:0]             size;
    logic [1:0]                         burst;
    logic [AxiDataWidth-1:0]            data;
    logic [AxiDataWidth / 8-1:0]        strb;
    logic                               last;
    logic [1:0]                         region_type;
    logic [ChieNidWidth-1:0]            target_nid;
    logic                               ns;
    logic [1:0]                         order;
    logic [3:0]                         memattr;
    logic [PolicyEpochWidth-1:0]        policy_epoch;
  } write_admission_snapshot_t;

  // Sequential ownership tables. Allocation happens only after admission has
  // reserved all required resources; release is deferred until final AXI R/B
  // handshake. No table update logic is implemented in this skeleton.
  parent_context_t parent_context_q [ParentEntries];
  child_context_t child_context_q [ChildEntries];
  line_context_t line_context_q [LineContextEntries];
  line_hazard_t line_hazard_q [LineHazardEntries];
  read_child_state_t read_child_state_q [ChildEntries];
  write_child_state_t write_child_state_q [ChildEntries];

  // Sequential allocation and policy-snapshot placeholders.
  logic [ParentEntries-1:0] parent_free_q;
  logic [ChildEntries-1:0] child_free_q;
  logic [LineContextEntries-1:0] line_context_free_q;
  logic [LineHazardEntries-1:0] line_hazard_free_q;

  // One-entry read admission snapshot. It is intentionally separate from the
  // parent table: no parent/child allocation is safe until a later increment
  // supplies a response/drain lifecycle.
  read_admission_snapshot_t read_snapshot_q;
  write_admission_snapshot_t write_snapshot_q;
  logic csr_window_hit;
  logic write_csr_window_hit;
  logic read_admit_eligible;
  logic write_admit_eligible;
  logic read_admit_fire;
  logic write_admit_fire;
  logic parent_alloc_ready;
  logic [ParentIndexWidth-1:0] parent_alloc_index;
  logic child_alloc_ready;
  logic [ChildIndexWidth-1:0] child_alloc_index;
  logic line_alloc_ready;
  logic [LineContextIndexWidth-1:0] line_alloc_index;
  logic txn_alloc_ready;
  logic [ChieTxnidWidth-1:0] txn_alloc_id;
  logic parent_free_valid;
  logic [ParentIndexWidth-1:0] parent_free_index;
  logic child_free_valid;
  logic [ChildIndexWidth-1:0] child_free_index;
  logic line_free_valid;
  logic [LineContextIndexWidth-1:0] line_free_index;
  logic txn_free_valid;
  logic [ChieTxnidWidth-1:0] txn_free_id;
  logic [ChieTxnidWidth-1:0] txn_lookup_id;
  logic txn_map_hit;
  logic [ChildIndexWidth-1:0] txn_map_child;
  logic normal_read_alloc_fire;
  logic normal_write_alloc_fire;
  logic issue_child_found;
  logic [ChildIndexWidth-1:0] issue_child_index;
  logic issue_child_is_write;
  logic present_child_found;
  logic [ChildIndexWidth-1:0] present_child_index;
  logic present_child_parent_valid;
  logic [ParentIndexWidth-1:0] present_parent_index;
  logic [LineContextIndexWidth-1:0] present_line_index;
  logic [511:0] present_line_data;
  logic [5:0] present_byte_offset;
  logic [AxiDataWidth-1:0] present_read_data;
  logic read_rsp_load;
  logic read_rsp_fire;
  logic read_rsp_valid_q;
  logic [AxiIdWidth-1:0] read_rsp_id_q;
  logic [AxiDataWidth-1:0] read_rsp_data_q;
  logic [1:0] read_rsp_code_q;
  logic read_rsp_last_q;
  logic write_rsp_fire;
  logic write_rsp_valid_q;
  logic [AxiIdWidth-1:0] write_rsp_id_q;
  logic [1:0] write_rsp_code_q;
  logic [ChildIndexWidth-1:0] write_rsp_child_index_q;
  logic [ParentIndexWidth-1:0] write_rsp_parent_index_q;
  logic [LineContextIndexWidth-1:0] write_rsp_line_index_q;
  logic [ReqFlitWidth-1:0] readnosnp_flit;
  logic [ReqFlitWidth-1:0] writenosnpptl_flit;
  logic [DatFlitWidth-1:0] noncopyback_wrdata_flit;
  logic [6:0] codec_opcode_unused;
  logic [ChieNidWidth-1:0] codec_nid_unused;
  logic [ChieNidWidth-1:0] codec_return_nid_unused;
  logic [ChieTxnidWidth-1:0] codec_txnid_unused;
  logic [ChieTxnidWidth-1:0] codec_return_txnid_unused;
  logic [ChieReqAddrWidth-1:0] codec_addr_unused;
  logic [2:0] codec_size_unused;
  logic codec_read_unused;
  logic [DatFlitWidth-1:0] codec_dat_unused;
  logic [4:0] rxrsp_opcode;
  logic [ChieNidWidth-1:0] rxrsp_src_id;
  logic [ChieTxnidWidth-1:0] rxrsp_txnid;
  logic [ChieDbidWidth-1:0] rxrsp_dbid;
  logic [1:0] rxrsp_resperr;
  logic rxrsp_is_dbidresp;
  logic rxrsp_is_compdbidresp;
  logic rxrsp_is_comp;
  logic [3:0] rxdat_opcode;
  logic [ChieTxnidWidth-1:0] rxdat_txnid;
  logic [1:0] rxdat_dataid;
  logic [1:0] rxdat_resperr;
  logic [31:0] rxdat_be;
  logic [255:0] rxdat_data;
  logic rxdat_legal_dataid;
  logic rxdat_accept;
  logic [MaxDatPerLine-1:0] rxdat_next_received_mask;
  logic rxdat_protocol_error_q;
  logic [31:0] write_dat_be;
  logic [255:0] write_dat_data;
  logic rxrsp_accept;

  rni_chi_codec #(.NidWidth(ChieNidWidth), .TxnidWidth(ChieTxnidWidth),
      .ReqAddrWidth(ChieReqAddrWidth), .ReqFlitWidth(ReqFlitWidth)) read_codec (
      .req_flit_i('0), .req_opcode_o(codec_opcode_unused), .req_src_id_o(codec_nid_unused), .req_return_nid_o(codec_return_nid_unused),
      .req_txnid_o(codec_txnid_unused), .req_return_txnid_o(codec_return_txnid_unused), .req_addr_o(codec_addr_unused), .req_size_o(codec_size_unused),
      .req_is_readnosnp_o(codec_read_unused),
      .read_tgt_id_i(parent_context_q[issue_child_index].target_nid),
      .read_src_id_i(RniNid), .read_txnid_i(child_context_q[issue_child_index].txnid),
      .read_return_nid_i(RniNid),
      .read_return_txnid_i({{(ChieTxnidWidth-AxiIdWidth){1'b0}}, parent_context_q[issue_child_index].axi_id}),
      .read_addr_i(parent_context_q[issue_child_index].start_addr[ChieReqAddrWidth-1:0]),
      .read_size_i(parent_context_q[issue_child_index].burst_size),
      .read_ns_i(parent_context_q[issue_child_index].ns),
      .read_order_i(parent_context_q[issue_child_index].order),
      .read_memattr_i(parent_context_q[issue_child_index].memattr),
      .readnosnp_flit_o(readnosnp_flit),
      .write_tgt_id_i(parent_context_q[issue_child_index].target_nid),
      .write_src_id_i(RniNid),
      .write_txnid_i(child_context_q[issue_child_index].txnid),
      .write_return_nid_i(RniNid),
      .write_return_txnid_i(child_context_q[issue_child_index].txnid),
      .write_addr_i(parent_context_q[issue_child_index].start_addr[ChieReqAddrWidth-1:0]),
      .write_size_i(parent_context_q[issue_child_index].burst_size),
      .write_ns_i(parent_context_q[issue_child_index].ns),
      .write_order_i(parent_context_q[issue_child_index].order),
      .write_memattr_i(parent_context_q[issue_child_index].memattr),
      .writenosnpptl_flit_o(writenosnpptl_flit),
      .rsp_flit_i(rxrsp_payload_i), .rsp_opcode_o(rxrsp_opcode),
      .rsp_src_id_o(rxrsp_src_id), .rsp_txnid_o(rxrsp_txnid),
      .rsp_dbid_o(rxrsp_dbid), .rsp_resperr_o(rxrsp_resperr),
      .rsp_is_dbidresp_o(rxrsp_is_dbidresp),
      .rsp_is_compdbidresp_o(rxrsp_is_compdbidresp),
      .rsp_is_comp_o(rxrsp_is_comp),
      .comp_tgt_id_i('0), .comp_src_id_i('0),
      .comp_home_nid_i('0), .comp_txnid_i('0), .comp_dbid_i('0), .comp_data_i('0),
      .compdata_flit_o(codec_dat_unused), .dat_flit_i(rxdat_payload_i),
      .dat_opcode_o(rxdat_opcode), .dat_txnid_o(rxdat_txnid),
      .dat_dataid_o(rxdat_dataid), .dat_resperr_o(rxdat_resperr),
      .dat_be_o(rxdat_be), .dat_data_o(rxdat_data),
      .wrdat_tgt_id_i(child_context_q[issue_child_index].responder_nid),
      .wrdat_src_id_i(RniNid),
      .wrdat_home_nid_i(RniNid),
      .wrdat_txnid_i(child_context_q[issue_child_index].dbid),
      .wrdat_dbid_i(child_context_q[issue_child_index].txnid),
      .wrdat_dataid_i(2'b00), .wrdat_be_i(write_dat_be),
      .wrdat_data_i(write_dat_data),
      .noncopyback_wrdata_flit_o(noncopyback_wrdata_flit));

  rni_parent_allocator #(.Entries(ParentEntries)) parent_allocator (
      .clk(clk), .rst(rst),
      .alloc_valid_i(normal_read_alloc_fire || normal_write_alloc_fire),
      .alloc_ready_o(parent_alloc_ready), .alloc_index_o(parent_alloc_index),
      .free_valid_i(parent_free_valid), .free_index_i(parent_free_index));
  rni_parent_allocator #(.Entries(ChildEntries)) child_allocator (
      .clk(clk), .rst(rst),
      .alloc_valid_i(normal_read_alloc_fire || normal_write_alloc_fire),
      .alloc_ready_o(child_alloc_ready), .alloc_index_o(child_alloc_index),
      .free_valid_i(child_free_valid), .free_index_i(child_free_index));
  rni_parent_allocator #(.Entries(LineContextEntries)) line_allocator (
      .clk(clk), .rst(rst),
      .alloc_valid_i(normal_read_alloc_fire || normal_write_alloc_fire),
      .alloc_ready_o(line_alloc_ready), .alloc_index_o(line_alloc_index),
      .free_valid_i(line_free_valid), .free_index_i(line_free_index));
  rni_txnid_allocator #(.TxnidWidth(ChieTxnidWidth), .Entries(ChildEntries))
      txnid_allocator (.clk(clk), .rst(rst),
      .alloc_valid_i(normal_read_alloc_fire || normal_write_alloc_fire),
      .alloc_ready_o(txn_alloc_ready), .alloc_txnid_o(txn_alloc_id),
      .free_valid_i(txn_free_valid), .free_txnid_i(txn_free_id));
  rni_txn_child_map #(.TxnidWidth(ChieTxnidWidth),
      .TxnidEntries(ChildEntries), .ChildEntries(ChildEntries)) txn_child_map (
      .clk(clk), .rst(rst),
      .alloc_valid_i(normal_read_alloc_fire || normal_write_alloc_fire),
      .alloc_txnid_i(txn_alloc_id),
      .alloc_child_i(child_alloc_index), .free_valid_i(txn_free_valid),
      .free_txnid_i(txn_free_id),
      .lookup_txnid_i(txn_lookup_id), .lookup_hit_o(txn_map_hit),
      .lookup_child_o(txn_map_child));

  // This predicate uses BASE plus SIZE semantics for the half-open bootstrap
  // CSR range. Subtracting only after the lower-bound check avoids treating an
  // address below BASE as a wrapped, in-range offset.
  always_comb begin
    issue_child_found = 1'b0;
    issue_child_index = '0;
    issue_child_is_write = 1'b0;
    for (int i = 0; i < ChildEntries; i++) begin
      if (!issue_child_found && child_context_q[i].valid &&
          !child_context_q[i].is_write &&
          (read_child_state_q[i] == kReadChildIssueReq)) begin
        issue_child_found = 1'b1;
        issue_child_index = ChildIndexWidth'(i);
      end
      if (!issue_child_found && child_context_q[i].valid &&
          child_context_q[i].is_write &&
          ((write_child_state_q[i] == kWriteChildIssueReq) ||
           (write_child_state_q[i] == kWriteChildSendDat))) begin
        issue_child_found = 1'b1;
        issue_child_index = ChildIndexWidth'(i);
        issue_child_is_write = 1'b1;
      end
    end
    txn_lookup_id = rxrsp_valid_i ? rxrsp_txnid : rxdat_txnid;
    present_child_found = 1'b0;
    present_child_index = '0;
    for (int i = 0; i < ChildEntries; i++) begin
      if (!present_child_found && child_context_q[i].valid &&
          !child_context_q[i].is_write &&
          (read_child_state_q[i] == kReadChildPresentR)) begin
        present_child_found = 1'b1;
        present_child_index = ChildIndexWidth'(i);
      end
    end
    present_parent_index = child_context_q[present_child_index].parent_index;
    present_child_parent_valid = present_child_found &&
        parent_context_q[present_parent_index].valid;
    present_line_index = parent_context_q[present_parent_index].line_context_index;
    present_line_data = line_context_q[present_line_index].data;
    present_byte_offset = parent_context_q[present_parent_index].start_addr[5:0];
    present_read_data =
        present_line_data[present_byte_offset * 8 +: AxiDataWidth];
    read_rsp_load = present_child_parent_valid && !read_rsp_valid_q;
    read_rsp_fire = read_rsp_valid_q && read_rsp_ready_i;
    write_rsp_fire = write_rsp_valid_q && write_rsp_ready_i;
    parent_free_valid = read_rsp_fire || write_rsp_fire;
    parent_free_index = read_rsp_fire ? present_parent_index :
                                      write_rsp_parent_index_q;
    child_free_valid = read_rsp_fire || write_rsp_fire;
    child_free_index = read_rsp_fire ? present_child_index :
                                    write_rsp_child_index_q;
    line_free_valid = read_rsp_fire || write_rsp_fire;
    line_free_index = read_rsp_fire ? present_line_index :
                                    write_rsp_line_index_q;
    txn_free_valid = read_rsp_fire || write_rsp_fire;
    txn_free_id = read_rsp_fire ? child_context_q[present_child_index].txnid :
                                  child_context_q[write_rsp_child_index_q].txnid;
    csr_window_hit = (read_cmd_addr_i >= PolicyCsrBase) &&
                     ((read_cmd_addr_i - PolicyCsrBase) < PolicyCsrSize);
    write_csr_window_hit = (write_cmd_addr_i >= PolicyCsrBase) &&
                           ((write_cmd_addr_i - PolicyCsrBase) < PolicyCsrSize);
    read_admit_eligible = !policy_quiesce_req_i && !read_snapshot_q.valid &&
                           (csr_window_hit || !policy_lookup_hit_i ||
                            (parent_alloc_ready && child_alloc_ready && line_alloc_ready && txn_alloc_ready));
    read_admit_fire = read_cmd_valid_i && read_admit_eligible;
    normal_read_alloc_fire = read_admit_fire && !csr_window_hit && policy_lookup_hit_i &&
                             parent_alloc_ready && child_alloc_ready && line_alloc_ready && txn_alloc_ready;
    // One combinational policy lookup port is shared. A viable read takes
    // priority; write admission waits only for that competing lookup cycle.
    write_admit_eligible = !policy_quiesce_req_i && !write_snapshot_q.valid &&
                            !read_admit_fire;
    write_admit_fire = write_cmd_valid_i && write_data_valid_i &&
                       write_admit_eligible;
    normal_write_alloc_fire = write_admit_fire && !write_csr_window_hit &&
                              policy_lookup_hit_i && parent_alloc_ready &&
                              child_alloc_ready && line_alloc_ready &&
                              txn_alloc_ready;

    write_cmd_ready_o = write_admit_eligible && write_data_valid_i;
    write_data_ready_o = write_admit_eligible && write_cmd_valid_i;
    read_cmd_ready_o = read_admit_eligible;
    write_rsp_valid_o = write_rsp_valid_q;
    write_rsp_id_o = write_rsp_id_q;
    write_rsp_code_o = write_rsp_code_q;
    read_rsp_valid_o = read_rsp_valid_q;
    read_rsp_id_o = read_rsp_id_q;
    read_rsp_data_o = read_rsp_data_q;
    read_rsp_code_o = read_rsp_code_q;
    read_rsp_last_o = read_rsp_last_q;
    policy_lookup_valid_o = (read_admit_fire && !csr_window_hit) ||
                            (write_admit_fire && !write_csr_window_hit);
    policy_lookup_addr_o = read_admit_fire ? read_cmd_addr_i : write_cmd_addr_i;
    policy_drain_done_o = 1'b0;
    txreq_valid_o = issue_child_found &&
                    (!issue_child_is_write ||
                     (write_child_state_q[issue_child_index] ==
                      kWriteChildIssueReq));
    txreq_payload_o = issue_child_is_write ? writenosnpptl_flit :
                                           readnosnp_flit;
    write_dat_be = '0;
    write_dat_be[AxiDataWidth / 8-1:0] =
        line_context_q[parent_context_q[child_context_q[issue_child_index].parent_index]
            .line_context_index].dirty_byte_mask[AxiDataWidth / 8-1:0];
    write_dat_data = '0;
    write_dat_data[AxiDataWidth-1:0] =
        line_context_q[parent_context_q[child_context_q[issue_child_index].parent_index]
            .line_context_index].data[AxiDataWidth-1:0];
    txdat_valid_o = issue_child_found && issue_child_is_write &&
                    (write_child_state_q[issue_child_index] ==
                     kWriteChildSendDat);
    txdat_payload_o = noncopyback_wrdata_flit;
    txrsp_valid_o = 1'b0;
    txrsp_payload_o = '0;
    rxrsp_accept = rxrsp_valid_i && txn_map_hit &&
                   child_context_q[txn_map_child].is_write &&
                   (((write_child_state_q[txn_map_child] ==
                      kWriteChildWaitDbid) &&
                     (rxrsp_is_dbidresp || rxrsp_is_compdbidresp)) ||
                    ((write_child_state_q[txn_map_child] ==
                      kWriteChildWaitComp) && rxrsp_is_comp));
    rxrsp_ready_o = 1'b1;
    rxdat_legal_dataid = (rxdat_dataid == 2'b00) || (rxdat_dataid == 2'b10);
    rxdat_accept = rxdat_valid_i && (rxdat_opcode == 4'h4) && txn_map_hit &&
                   !child_context_q[txn_map_child].is_write &&
                   (read_child_state_q[txn_map_child] == kReadChildWaitDat) &&
                   rxdat_legal_dataid &&
                   !child_context_q[txn_map_child].received_dat_mask[rxdat_dataid[1]];
    rxdat_next_received_mask =
        child_context_q[txn_map_child].received_dat_mask |
        (4'b0001 << rxdat_dataid[1]);
    // Consume every received DAT into this core boundary. Invalid DAT is
    // retained as protocol-error state rather than blocking the P0 forever.
    rxdat_ready_o = 1'b1;
  end

  // The snapshot register updates only on the external read-command
  // handshake. The policy inputs are therefore captured at admission and
  // cannot be reinterpreted by a later CSR policy-table update.
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      read_snapshot_q <= '0;
      write_snapshot_q <= '0;
      rxdat_protocol_error_q <= 1'b0;
      read_rsp_valid_q <= 1'b0;
      read_rsp_id_q <= '0;
      read_rsp_data_q <= '0;
      read_rsp_code_q <= '0;
      read_rsp_last_q <= 1'b0;
      write_rsp_valid_q <= 1'b0;
      write_rsp_id_q <= '0;
      write_rsp_code_q <= '0;
      write_rsp_child_index_q <= '0;
      write_rsp_parent_index_q <= '0;
      write_rsp_line_index_q <= '0;
      for (int i = 0; i < ParentEntries; i++) begin
        parent_context_q[i] <= '0;
      end
      for (int i = 0; i < ChildEntries; i++) begin
        child_context_q[i] <= '0;
        read_child_state_q[i] <= kReadChildIdle;
        write_child_state_q[i] <= kWriteChildIdle;
      end
      for (int i = 0; i < LineContextEntries; i++) begin
        line_context_q[i] <= '0;
      end
      for (int i = 0; i < LineHazardEntries; i++) begin
        line_hazard_q[i] <= '0;
      end
    end else begin
      if (read_rsp_fire) begin
        read_rsp_valid_q <= 1'b0;
        read_snapshot_q.valid <= 1'b0;
        parent_context_q[present_parent_index].valid <= 1'b0;
        child_context_q[present_child_index].valid <= 1'b0;
        line_context_q[present_line_index].valid <= 1'b0;
        read_child_state_q[present_child_index] <= kReadChildIdle;
      end
      if (write_rsp_fire) begin
        write_rsp_valid_q <= 1'b0;
        write_snapshot_q.valid <= 1'b0;
        parent_context_q[write_rsp_parent_index_q].valid <= 1'b0;
        child_context_q[write_rsp_child_index_q].valid <= 1'b0;
        line_context_q[write_rsp_line_index_q].valid <= 1'b0;
        write_child_state_q[write_rsp_child_index_q] <= kWriteChildIdle;
      end
      if (read_rsp_load) begin
        read_rsp_valid_q <= 1'b1;
        read_rsp_id_q <= parent_context_q[present_parent_index].axi_id;
        read_rsp_data_q <= present_read_data;
        read_rsp_code_q <= child_context_q[present_child_index].error_seen ?
                           2'b10 : 2'b00;
        read_rsp_last_q <= 1'b1;
      end
      if (txreq_valid_o && txreq_ready_i) begin
        if (issue_child_is_write) begin
          write_child_state_q[issue_child_index] <= kWriteChildWaitDbid;
        end else begin
          read_child_state_q[issue_child_index] <= kReadChildWaitDat;
        end
      end
      if (txdat_valid_o && txdat_ready_i) begin
        child_context_q[issue_child_index].sent_dat_mask[0] <= 1'b1;
        if (child_context_q[issue_child_index].comp_seen) begin
          write_rsp_valid_q <= 1'b1;
          write_rsp_id_q <= parent_context_q[
              child_context_q[issue_child_index].parent_index].axi_id;
          write_rsp_code_q <= child_context_q[issue_child_index].error_seen ?
                              2'b10 : 2'b00;
          write_rsp_child_index_q <= issue_child_index;
          write_rsp_parent_index_q <=
              child_context_q[issue_child_index].parent_index;
          write_rsp_line_index_q <= parent_context_q[
              child_context_q[issue_child_index].parent_index]
              .line_context_index;
          write_child_state_q[issue_child_index] <= kWriteChildPresentB;
        end else begin
          write_child_state_q[issue_child_index] <= kWriteChildWaitComp;
        end
      end
      if (rxrsp_valid_i && rxrsp_ready_o) begin
        if (rxrsp_accept) begin
          if (rxrsp_is_dbidresp || rxrsp_is_compdbidresp) begin
            child_context_q[txn_map_child].dbid <= rxrsp_dbid;
            child_context_q[txn_map_child].responder_nid <= rxrsp_src_id;
            child_context_q[txn_map_child].dbid_valid <= 1'b1;
            child_context_q[txn_map_child].error_seen <=
                child_context_q[txn_map_child].error_seen ||
                (rxrsp_resperr != 2'b00);
            write_child_state_q[txn_map_child] <= kWriteChildSendDat;
          end
          if (rxrsp_is_comp || rxrsp_is_compdbidresp) begin
            child_context_q[txn_map_child].comp_seen <= 1'b1;
            if (write_child_state_q[txn_map_child] ==
                kWriteChildWaitComp) begin
              write_rsp_valid_q <= 1'b1;
              write_rsp_id_q <= parent_context_q[
                  child_context_q[txn_map_child].parent_index].axi_id;
              write_rsp_code_q <=
                  (child_context_q[txn_map_child].error_seen ||
                   (rxrsp_resperr != 2'b00)) ? 2'b10 : 2'b00;
              write_rsp_child_index_q <= txn_map_child;
              write_rsp_parent_index_q <=
                  child_context_q[txn_map_child].parent_index;
              write_rsp_line_index_q <= parent_context_q[
                  child_context_q[txn_map_child].parent_index]
                  .line_context_index;
              write_child_state_q[txn_map_child] <= kWriteChildPresentB;
            end
          end
        end else begin
          rxdat_protocol_error_q <= 1'b1;
        end
      end
      if (rxdat_valid_i && rxdat_ready_o) begin
        if (rxdat_accept) begin
          line_context_q[parent_context_q[child_context_q[txn_map_child].parent_index].line_context_index]
              .data[rxdat_dataid[1] * 256 +: 256] <= rxdat_data;
          line_context_q[parent_context_q[child_context_q[txn_map_child].parent_index].line_context_index]
              .valid_byte_mask[rxdat_dataid[1] * 32 +: 32] <= rxdat_be;
          child_context_q[txn_map_child].received_dat_mask[rxdat_dataid[1]] <= 1'b1;
          if (rxdat_next_received_mask[1:0] == 2'b11) begin
            read_child_state_q[txn_map_child] <= kReadChildPresentR;
          end
          if (rxdat_resperr != 2'b00) begin
            child_context_q[txn_map_child].error_seen <= 1'b1;
          end
        end else begin
          rxdat_protocol_error_q <= 1'b1;
        end
      end
      if (read_cmd_valid_i && read_cmd_ready_o) begin
      read_snapshot_q.valid <= 1'b1;
      read_snapshot_q.is_policy_csr <= csr_window_hit;
      read_snapshot_q.policy_hit <= csr_window_hit || policy_lookup_hit_i;
      read_snapshot_q.axi_id <= read_cmd_id_i;
      read_snapshot_q.addr <= read_cmd_addr_i;
      read_snapshot_q.len <= read_cmd_len_i;
      read_snapshot_q.size <= read_cmd_size_i;
      read_snapshot_q.burst <= read_cmd_burst_i;
      read_snapshot_q.region_type <= policy_region_type_i;
      read_snapshot_q.target_nid <= policy_target_nid_i;
      read_snapshot_q.ns <= policy_ns_i;
      read_snapshot_q.order <= policy_order_i;
      read_snapshot_q.memattr <= policy_memattr_i;
      read_snapshot_q.policy_epoch <= policy_epoch_i;
      if (normal_read_alloc_fire) begin
        parent_context_q[parent_alloc_index].valid <= 1'b1;
        parent_context_q[parent_alloc_index].is_write <= 1'b0;
        parent_context_q[parent_alloc_index].axi_id <= read_cmd_id_i;
        parent_context_q[parent_alloc_index].start_addr <= read_cmd_addr_i;
        parent_context_q[parent_alloc_index].burst_len <= read_cmd_len_i;
        parent_context_q[parent_alloc_index].burst_size <= read_cmd_size_i;
        parent_context_q[parent_alloc_index].burst_type <= read_cmd_burst_i;
        parent_context_q[parent_alloc_index].profile <= kProfileNoncoherent;
        parent_context_q[parent_alloc_index].region_type <= policy_region_type_i;
        parent_context_q[parent_alloc_index].target_nid <= policy_target_nid_i;
        parent_context_q[parent_alloc_index].ns <= policy_ns_i;
        parent_context_q[parent_alloc_index].order <= policy_order_i;
        parent_context_q[parent_alloc_index].memattr <= policy_memattr_i;
        parent_context_q[parent_alloc_index].policy_epoch <= policy_epoch_i;
        parent_context_q[parent_alloc_index].child_index <= child_alloc_index;
        parent_context_q[parent_alloc_index].line_context_index <= line_alloc_index;
        parent_context_q[parent_alloc_index].error_seen <= 1'b0;
        child_context_q[child_alloc_index].valid <= 1'b1;
        child_context_q[child_alloc_index].is_write <= 1'b0;
        child_context_q[child_alloc_index].parent_index <= parent_alloc_index;
        child_context_q[child_alloc_index].txnid <= txn_alloc_id;
        child_context_q[child_alloc_index].dbid <= '0;
        child_context_q[child_alloc_index].dbid_valid <= 1'b0;
        child_context_q[child_alloc_index].required_dat_mask <= 4'b0011;
        child_context_q[child_alloc_index].sent_dat_mask <= '0;
        child_context_q[child_alloc_index].received_dat_mask <= '0;
        child_context_q[child_alloc_index].retry_pending <= 1'b0;
        child_context_q[child_alloc_index].comp_seen <= 1'b0;
        child_context_q[child_alloc_index].error_seen <= 1'b0;
        line_context_q[line_alloc_index].valid <= 1'b1;
        line_context_q[line_alloc_index].line_addr <= read_cmd_addr_i[AxiAddrWidth-1:6];
        line_context_q[line_alloc_index].data <= '0;
        line_context_q[line_alloc_index].valid_byte_mask <= '0;
        line_context_q[line_alloc_index].required_byte_mask <= '0;
        line_context_q[line_alloc_index].dirty_byte_mask <= '0;
        line_context_q[line_alloc_index].error_byte_mask <= '0;
        read_child_state_q[child_alloc_index] <= kReadChildIssueReq;
      end
      end else if (write_admit_fire) begin
      write_snapshot_q.valid <= 1'b1;
      write_snapshot_q.is_policy_csr <= write_csr_window_hit;
      write_snapshot_q.policy_hit <= write_csr_window_hit || policy_lookup_hit_i;
      write_snapshot_q.axi_id <= write_cmd_id_i;
      write_snapshot_q.addr <= write_cmd_addr_i;
      write_snapshot_q.len <= write_cmd_len_i;
      write_snapshot_q.size <= write_cmd_size_i;
      write_snapshot_q.burst <= write_cmd_burst_i;
      write_snapshot_q.data <= write_data_i;
      write_snapshot_q.strb <= write_strb_i;
      write_snapshot_q.last <= write_last_i;
      write_snapshot_q.region_type <= policy_region_type_i;
      write_snapshot_q.target_nid <= policy_target_nid_i;
      write_snapshot_q.ns <= policy_ns_i;
      write_snapshot_q.order <= policy_order_i;
      write_snapshot_q.memattr <= policy_memattr_i;
      write_snapshot_q.policy_epoch <= policy_epoch_i;
      if (normal_write_alloc_fire) begin
        parent_context_q[parent_alloc_index].valid <= 1'b1;
        parent_context_q[parent_alloc_index].is_write <= 1'b1;
        parent_context_q[parent_alloc_index].axi_id <= write_cmd_id_i;
        parent_context_q[parent_alloc_index].start_addr <= write_cmd_addr_i;
        parent_context_q[parent_alloc_index].burst_len <= write_cmd_len_i;
        parent_context_q[parent_alloc_index].burst_size <= write_cmd_size_i;
        parent_context_q[parent_alloc_index].burst_type <= write_cmd_burst_i;
        parent_context_q[parent_alloc_index].profile <= kProfileNoncoherent;
        parent_context_q[parent_alloc_index].region_type <= policy_region_type_i;
        parent_context_q[parent_alloc_index].target_nid <= policy_target_nid_i;
        parent_context_q[parent_alloc_index].ns <= policy_ns_i;
        parent_context_q[parent_alloc_index].order <= policy_order_i;
        parent_context_q[parent_alloc_index].memattr <= policy_memattr_i;
        parent_context_q[parent_alloc_index].policy_epoch <= policy_epoch_i;
        parent_context_q[parent_alloc_index].child_index <= child_alloc_index;
        parent_context_q[parent_alloc_index].line_context_index <= line_alloc_index;
        parent_context_q[parent_alloc_index].error_seen <= 1'b0;
        child_context_q[child_alloc_index].valid <= 1'b1;
        child_context_q[child_alloc_index].is_write <= 1'b1;
        child_context_q[child_alloc_index].parent_index <= parent_alloc_index;
        child_context_q[child_alloc_index].txnid <= txn_alloc_id;
        child_context_q[child_alloc_index].dbid <= '0;
        child_context_q[child_alloc_index].responder_nid <= '0;
        child_context_q[child_alloc_index].dbid_valid <= 1'b0;
        child_context_q[child_alloc_index].required_dat_mask <= 4'b0001;
        child_context_q[child_alloc_index].sent_dat_mask <= '0;
        child_context_q[child_alloc_index].received_dat_mask <= '0;
        child_context_q[child_alloc_index].retry_pending <= 1'b0;
        child_context_q[child_alloc_index].comp_seen <= 1'b0;
        child_context_q[child_alloc_index].error_seen <= 1'b0;
        line_context_q[line_alloc_index].valid <= 1'b1;
        line_context_q[line_alloc_index].line_addr <= write_cmd_addr_i[AxiAddrWidth-1:6];
        line_context_q[line_alloc_index].data <= '0;
        line_context_q[line_alloc_index].data[AxiDataWidth-1:0] <= write_data_i;
        line_context_q[line_alloc_index].valid_byte_mask <= '0;
        line_context_q[line_alloc_index].required_byte_mask <= '0;
        line_context_q[line_alloc_index].dirty_byte_mask <= '0;
        line_context_q[line_alloc_index].dirty_byte_mask[AxiDataWidth / 8-1:0] <=
            write_strb_i;
        line_context_q[line_alloc_index].error_byte_mask <= '0;
        write_child_state_q[child_alloc_index] <= kWriteChildIssueReq;
      end
      end
    end
  end

  // Write admission, snapshot dequeue, parent/child allocation, fragment
  // calculation, CHI pack/unpack, response routing and all other transitions
  // are deferred to later increments.

endmodule

`default_nettype wire
