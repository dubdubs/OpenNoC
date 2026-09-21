// Single owner of AXI parent, CHI child, TxnID, DBID, and retire state.

`default_nettype none

module axi2chi_nocoh_txn_ctx #(
  parameter int unsigned AxiAddrWidth = 64,
  parameter int unsigned AxiIdWidth = 4,
  parameter int unsigned AxlenWidth = 8,
  parameter int unsigned AxsizeWidth = 3,
  parameter int unsigned ChiTxnidWidth = 12,
  parameter int unsigned ChiDbidWidth = 12,
  parameter int unsigned ParentEntries = 16,
  parameter int unsigned ChildEntries = 16,
  parameter int unsigned MaxAxiBeats = 256
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
  output logic [$clog2(ParentEntries)-1:0] wr_admit_parent_idx_o,
  input logic child_alloc_valid_i,
  output logic child_alloc_ready_o,
  input logic [$clog2(ParentEntries)-1:0] child_alloc_parent_idx_i,
  input logic child_alloc_is_write_i,
  input logic [AxlenWidth-1:0] child_alloc_axi_beat_i,
  input logic [AxiAddrWidth-1:0] child_alloc_addr_i,
  input logic [1:0] child_alloc_frag_idx_i,
  output logic [$clog2(ChildEntries)-1:0] child_alloc_idx_o,
  output logic [ChiTxnidWidth-1:0] child_alloc_txnid_o,
  input logic child_event_valid_i,
  input logic [$clog2(ChildEntries)-1:0] child_event_idx_i,
  input logic [2:0] child_event_type_i,
  input logic [ChiDbidWidth-1:0] child_event_dbid_i,
  input logic [1:0] child_event_resp_i,
  input logic parent_retire_valid_i,
  input logic [$clog2(ParentEntries)-1:0] parent_retire_idx_i,
  output logic parent_retire_ready_o
);

  localparam int unsigned ParentIndexWidth = $clog2(ParentEntries);
  localparam int unsigned ChildIndexWidth = $clog2(ChildEntries);
  localparam int unsigned BeatIndexWidth = $clog2(MaxAxiBeats);

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
    logic [BeatIndexWidth-1:0] next_retire_beat;
    logic [BeatIndexWidth-1:0] completed_beat_count;
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
  logic [(1 << ChiTxnidWidth)-1:0] txnid_valid_q;
  logic [ChildIndexWidth-1:0] txnid_child_q [1 << ChiTxnidWidth];

  // Context RAM write arbitration and all allocation/release updates are deferred.

endmodule

`default_nettype wire
