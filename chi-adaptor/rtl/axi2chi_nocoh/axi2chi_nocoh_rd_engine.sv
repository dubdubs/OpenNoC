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
  input logic rd_issue_valid_i,
  output logic rd_issue_ready_o,
  input logic [$clog2(ParentEntries)-1:0] rd_issue_parent_idx_i,
  input logic [AxiAddrWidth-1:0] rd_issue_addr_i,
  input logic [7:0] rd_issue_axi_beat_i,
  output logic child_alloc_valid_o,
  input logic child_alloc_ready_i,
  output logic [$clog2(ParentEntries)-1:0] child_alloc_parent_idx_o,
  output logic [AxiAddrWidth-1:0] child_alloc_addr_o,
  output logic [7:0] child_alloc_axi_beat_o,
  input logic [$clog2(ChildEntries)-1:0] child_alloc_idx_i,
  input logic [ChiTxnidWidth-1:0] child_alloc_txnid_i,
  output logic child_event_valid_o,
  output logic [$clog2(ChildEntries)-1:0] child_event_idx_o,
  output logic [2:0] child_event_type_o,
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

  localparam int unsigned ChildIndexWidth = $clog2(ChildEntries);

  typedef enum logic [2:0] {
    kRdIdle,
    kRdAlloc,
    kRdIssueReq,
    kRdWaitDat,
    kRdCommitData,
    kRdWaitRetire
  } rd_state_t;

  rd_state_t state_q [ChildEntries];
  logic [$clog2(ParentEntries)-1:0] parent_q [ChildEntries];
  logic [$clog2(ChildEntries)-1:0] child_q [ChildEntries];
  logic [ChiTxnidWidth-1:0] txnid_q [ChildEntries];
  logic [AxiAddrWidth-1:0] addr_q [ChildEntries];
  logic [7:0] axi_beat_q [ChildEntries];
  logic [DatFlitWidth-1:0] rxdat_payload_q [ChildEntries];
  logic [$clog2(ChildEntries)-1:0] issue_lane_idx;
  logic issue_lane_found;
  logic [$clog2(ChildEntries)-1:0] alloc_lane_idx;
  logic alloc_lane_found;
  logic [$clog2(ChildEntries)-1:0] txreq_lane_idx;
  logic txreq_lane_found;
  logic [$clog2(ChildEntries)-1:0] rxdat_lane_idx;
  logic rxdat_lane_found;
  logic [$clog2(ChildEntries)-1:0] fragment_lane_idx;
  logic fragment_lane_found;
  logic [$clog2(ChildEntries)-1:0] event_lane_idx;
  logic event_lane_found;
  logic [ChiTxnidWidth-1:0] rxdat_txnid;
  logic issue_fire;
  logic alloc_fire;
  logic txreq_fire;
  logic rxdat_fire;
  logic fragment_fire;

  always_comb begin
    issue_lane_idx = '0;
    issue_lane_found = 1'b0;
    alloc_lane_idx = '0;
    alloc_lane_found = 1'b0;
    txreq_lane_idx = '0;
    txreq_lane_found = 1'b0;
    rxdat_lane_idx = '0;
    rxdat_lane_found = 1'b0;
    fragment_lane_idx = '0;
    fragment_lane_found = 1'b0;
    event_lane_idx = '0;
    event_lane_found = 1'b0;
    rxdat_txnid = rxdat_payload_i[8 +: ChiTxnidWidth];
    for (int unsigned idx = 0; idx < ChildEntries; idx++) begin
      if (state_q[idx] == kRdIdle && !issue_lane_found) begin
        issue_lane_idx = ChildIndexWidth'(idx);
        issue_lane_found = 1'b1;
      end
      if (state_q[idx] == kRdAlloc && !alloc_lane_found) begin
        alloc_lane_idx = ChildIndexWidth'(idx);
        alloc_lane_found = 1'b1;
      end
      if (state_q[idx] == kRdIssueReq && !txreq_lane_found) begin
        txreq_lane_idx = ChildIndexWidth'(idx);
        txreq_lane_found = 1'b1;
      end
      if (state_q[idx] == kRdWaitDat && txnid_q[idx] == rxdat_txnid &&
          !rxdat_lane_found) begin
        rxdat_lane_idx = ChildIndexWidth'(idx);
        rxdat_lane_found = 1'b1;
      end
      if (state_q[idx] == kRdCommitData && !fragment_lane_found) begin
        fragment_lane_idx = ChildIndexWidth'(idx);
        fragment_lane_found = 1'b1;
      end
      if (state_q[idx] == kRdWaitRetire && !event_lane_found) begin
        event_lane_idx = ChildIndexWidth'(idx);
        event_lane_found = 1'b1;
      end
    end

    rd_issue_ready_o = 1'b0;
    child_alloc_valid_o = 1'b0;
    child_alloc_parent_idx_o = parent_q[alloc_lane_idx];
    child_alloc_addr_o = addr_q[alloc_lane_idx];
    child_alloc_axi_beat_o = axi_beat_q[alloc_lane_idx];
    child_event_valid_o = 1'b0;
    child_event_idx_o = child_q[event_lane_idx];
    child_event_type_o = 3'd0;
    txreq_valid_o = 1'b0;
    txreq_payload_o = '0;
    rxdat_ready_o = 1'b0;
    rxrsp_ready_o = 1'b0;
    rd_fragment_valid_o = 1'b0;
    rd_fragment_child_idx_o = child_q[fragment_lane_idx];
    rd_fragment_payload_o = rxdat_payload_q[fragment_lane_idx];

    if (!rst) begin
      rd_issue_ready_o = issue_lane_found;
      child_alloc_valid_o = alloc_lane_found;
      if (txreq_lane_found) begin
        txreq_valid_o = 1'b1;
        txreq_payload_o[6:0] = 7'h04;
        txreq_payload_o[16 +: ChiTxnidWidth] = txnid_q[txreq_lane_idx];
        txreq_payload_o[32 +: AxiAddrWidth] = addr_q[txreq_lane_idx];
      end
      rxdat_ready_o = rxdat_lane_found;
      rd_fragment_valid_o = fragment_lane_found;
      child_event_valid_o = event_lane_found;
      child_event_type_o = 3'd4;
    end

    issue_fire = rd_issue_valid_i && rd_issue_ready_o;
    alloc_fire = child_alloc_valid_o && child_alloc_ready_i;
    txreq_fire = txreq_valid_o && txreq_ready_i;
    rxdat_fire = rxdat_valid_i && rxdat_ready_o;
    fragment_fire = rd_fragment_valid_o && rd_fragment_ready_i;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      for (int unsigned idx = 0; idx < ChildEntries; idx++) begin
        state_q[idx] <= kRdIdle;
        parent_q[idx] <= '0;
        child_q[idx] <= '0;
        txnid_q[idx] <= '0;
        addr_q[idx] <= '0;
        axi_beat_q[idx] <= '0;
        rxdat_payload_q[idx] <= '0;
      end
    end else begin
      if (issue_fire) begin
        parent_q[issue_lane_idx] <= rd_issue_parent_idx_i;
        addr_q[issue_lane_idx] <= rd_issue_addr_i;
        axi_beat_q[issue_lane_idx] <= rd_issue_axi_beat_i;
        state_q[issue_lane_idx] <= kRdAlloc;
      end

      if (alloc_fire) begin
        child_q[alloc_lane_idx] <= child_alloc_idx_i;
        txnid_q[alloc_lane_idx] <= child_alloc_txnid_i;
        state_q[alloc_lane_idx] <= kRdIssueReq;
      end

      if (txreq_fire) begin
        state_q[txreq_lane_idx] <= kRdWaitDat;
      end

      if (rxdat_fire) begin
        rxdat_payload_q[rxdat_lane_idx] <= rxdat_payload_i;
        state_q[rxdat_lane_idx] <= kRdCommitData;
      end

      if (fragment_fire) begin
        state_q[fragment_lane_idx] <= kRdWaitRetire;
      end

      if (child_event_valid_o) begin
        state_q[event_lane_idx] <= kRdIdle;
      end
    end
  end

endmodule

`default_nettype wire
