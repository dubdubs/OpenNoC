// ReadNoSnp child scheduler and control-state skeleton.

`default_nettype none

module axi2chi_nocoh_rd_engine #(
  parameter int unsigned AxiAddrWidth = 64,
  parameter int unsigned AxiIdWidth = 4,
  parameter int unsigned ChiTxnidWidth = 12,
  parameter int unsigned ReqFlitWidth = 131,
  parameter int unsigned RspFlitWidth = 73,
  parameter int unsigned DatFlitWidth = 406,
  parameter int unsigned ParentEntries = 16,
  parameter int unsigned ChildEntries = 16
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
  input logic rxdat_valid_i,
  input logic [DatFlitWidth-1:0] rxdat_payload_i,
  output logic rxdat_ready_o,
  input logic rxrsp_valid_i,
  input logic [RspFlitWidth-1:0] rxrsp_payload_i,
  output logic rxrsp_ready_o,
  output logic rd_fragment_valid_o,
  output logic [$clog2(ChildEntries)-1:0] rd_fragment_child_idx_o,
  output logic [DatFlitWidth-1:0] rd_fragment_payload_o,
  input logic rd_fragment_ready_i
);

  typedef enum logic [2:0] {
    kRdIdle,
    kRdAlloc,
    kRdIssueReq,
    kRdWaitDat,
    kRdCommitData,
    kRdWaitRetire
  } rd_state_t;

  rd_state_t state_q [ChildEntries];
  logic [$clog2(ParentEntries)-1:0] sched_parent_q;
  logic [$clog2(ChildEntries)-1:0] active_child_q;
  logic [ChiTxnidWidth-1:0] active_txnid_q;
  logic [AxiAddrWidth-1:0] active_addr_q;

  // Child selection, CHI response decode, and state transitions are deferred.

endmodule

`default_nettype wire
