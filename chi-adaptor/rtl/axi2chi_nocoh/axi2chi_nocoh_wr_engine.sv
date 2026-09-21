// WriteNoSnpPtl/WriteNoSnpFull child scheduler and control-state skeleton.

`default_nettype none

module axi2chi_nocoh_wr_engine #(
  parameter int unsigned AxiAddrWidth = 64,
  parameter int unsigned ChiTxnidWidth = 12,
  parameter int unsigned ChiDbidWidth = 12,
  parameter int unsigned ReqFlitWidth = 131,
  parameter int unsigned RspFlitWidth = 73,
  parameter int unsigned DatFlitWidth = 406,
  parameter int unsigned ParentEntries = 16,
  parameter int unsigned ChildEntries = 16,
  parameter bit EnableWriteNoSnpFull = 1'b1
) (
  input logic clk,
  input logic rst,
  output logic child_alloc_valid_o,
  input logic child_alloc_ready_i,
  output logic [$clog2(ParentEntries)-1:0] child_alloc_parent_idx_o,
  output logic [AxiAddrWidth-1:0] child_alloc_addr_o,
  input logic [$clog2(ChildEntries)-1:0] child_alloc_idx_i,
  input logic [ChiTxnidWidth-1:0] child_alloc_txnid_i,
  output logic txreq_valid_o,
  output logic [ReqFlitWidth-1:0] txreq_payload_o,
  input logic txreq_ready_i,
  output logic txdat_valid_o,
  output logic [DatFlitWidth-1:0] txdat_payload_o,
  input logic txdat_ready_i,
  input logic rxrsp_valid_i,
  input logic [RspFlitWidth-1:0] rxrsp_payload_i,
  output logic rxrsp_ready_o,
  input logic wr_fragment_valid_i,
  input logic [DatFlitWidth-1:0] wr_fragment_payload_i,
  output logic wr_fragment_ready_o
);

  typedef enum logic [3:0] {
    kWrIdle,
    kWrWaitW,
    kWrAlloc,
    kWrIssueReq,
    kWrWaitDbid,
    kWrIssueDat,
    kWrWaitComp,
    kWrComplete
  } wr_state_t;

  wr_state_t state_q [ChildEntries];
  logic [$clog2(ParentEntries)-1:0] sched_parent_q;
  logic [$clog2(ChildEntries)-1:0] active_child_q;
  logic [ChiTxnidWidth-1:0] active_txnid_q;
  logic [ChiDbidWidth-1:0] active_dbid_q;
  logic active_is_full_q;

  // DBID, DAT, Comp, and protocol-error transitions are deferred.

endmodule

`default_nettype wire
