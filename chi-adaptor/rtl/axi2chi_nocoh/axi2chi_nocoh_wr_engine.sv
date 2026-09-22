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
  input logic wr_issue_valid_i,
  output logic wr_issue_ready_o,
  input logic [$clog2(ParentEntries)-1:0] wr_issue_parent_idx_i,
  input logic [AxiAddrWidth-1:0] wr_issue_addr_i,
  input logic [7:0] wr_issue_axi_beat_i,
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
  output logic [ChiDbidWidth-1:0] child_event_dbid_o,
  output logic [1:0] child_event_resp_o,
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
  input logic [$clog2(ChildEntries)-1:0] wr_fragment_child_idx_i,
  input logic [DatFlitWidth-1:0] wr_fragment_payload_i,
  output logic wr_fragment_ready_o
);

  localparam int unsigned ChildIndexWidth = $clog2(ChildEntries);

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
  logic [$clog2(ParentEntries)-1:0] parent_q [ChildEntries];
  logic [$clog2(ChildEntries)-1:0] child_q [ChildEntries];
  logic [ChiTxnidWidth-1:0] txnid_q [ChildEntries];
  logic [ChiDbidWidth-1:0] dbid_q [ChildEntries];
  logic is_full_q [ChildEntries];
  logic [AxiAddrWidth-1:0] addr_q [ChildEntries];
  logic [7:0] axi_beat_q [ChildEntries];
  logic [DatFlitWidth-1:0] dat_payload_q [ChildEntries];
  logic [1:0] resp_q [ChildEntries];
  logic completion_seen_q [ChildEntries];
  logic [$clog2(ChildEntries)-1:0] issue_lane_idx;
  logic issue_lane_found;
  logic [$clog2(ChildEntries)-1:0] alloc_lane_idx;
  logic alloc_lane_found;
  logic [$clog2(ChildEntries)-1:0] txreq_lane_idx;
  logic txreq_lane_found;
  logic [$clog2(ChildEntries)-1:0] dbid_lane_idx;
  logic dbid_lane_found;
  logic [$clog2(ChildEntries)-1:0] w_lane_idx;
  logic w_lane_found;
  logic [$clog2(ChildEntries)-1:0] txdat_lane_idx;
  logic txdat_lane_found;
  logic [$clog2(ChildEntries)-1:0] comp_lane_idx;
  logic comp_lane_found;
  logic [$clog2(ChildEntries)-1:0] event_lane_idx;
  logic event_lane_found;
  logic [ChiTxnidWidth-1:0] rxrsp_txnid;
  logic [3:0] rxrsp_opcode;
  logic issue_fire;
  logic alloc_fire;
  logic txreq_fire;
  logic dbid_fire;
  logic wr_fragment_fire;
  logic txdat_fire;
  logic comp_fire;

  always_comb begin
    issue_lane_idx = '0;
    issue_lane_found = 1'b0;
    alloc_lane_idx = '0;
    alloc_lane_found = 1'b0;
    txreq_lane_idx = '0;
    txreq_lane_found = 1'b0;
    dbid_lane_idx = '0;
    dbid_lane_found = 1'b0;
    w_lane_idx = '0;
    w_lane_found = 1'b0;
    txdat_lane_idx = '0;
    txdat_lane_found = 1'b0;
    comp_lane_idx = '0;
    comp_lane_found = 1'b0;
    event_lane_idx = '0;
    event_lane_found = 1'b0;
    rxrsp_txnid = rxrsp_payload_i[8 +: ChiTxnidWidth];
    rxrsp_opcode = rxrsp_payload_i[3:0];
    for (int unsigned idx = 0; idx < ChildEntries; idx++) begin
      if (state_q[idx] == kWrIdle && !issue_lane_found) begin
        issue_lane_idx = ChildIndexWidth'(idx);
        issue_lane_found = 1'b1;
      end
      if (state_q[idx] == kWrAlloc && !alloc_lane_found) begin
        alloc_lane_idx = ChildIndexWidth'(idx);
        alloc_lane_found = 1'b1;
      end
      if (state_q[idx] == kWrIssueReq && !txreq_lane_found) begin
        txreq_lane_idx = ChildIndexWidth'(idx);
        txreq_lane_found = 1'b1;
      end
      if (state_q[idx] == kWrWaitDbid && txnid_q[idx] == rxrsp_txnid &&
          (rxrsp_opcode == 4'h1 || rxrsp_opcode == 4'h2) &&
          !dbid_lane_found) begin
        dbid_lane_idx = ChildIndexWidth'(idx);
        dbid_lane_found = 1'b1;
      end
      if (state_q[idx] == kWrWaitW && child_q[idx] == wr_fragment_child_idx_i &&
          !w_lane_found) begin
        w_lane_idx = ChildIndexWidth'(idx);
        w_lane_found = 1'b1;
      end
      if (state_q[idx] == kWrIssueDat && !txdat_lane_found) begin
        txdat_lane_idx = ChildIndexWidth'(idx);
        txdat_lane_found = 1'b1;
      end
      if (state_q[idx] == kWrWaitComp && txnid_q[idx] == rxrsp_txnid &&
          rxrsp_opcode == 4'h3 &&
          !comp_lane_found) begin
        comp_lane_idx = ChildIndexWidth'(idx);
        comp_lane_found = 1'b1;
      end
      if (state_q[idx] == kWrComplete && !event_lane_found) begin
        event_lane_idx = ChildIndexWidth'(idx);
        event_lane_found = 1'b1;
      end
    end

    wr_issue_ready_o = 1'b0;
    child_alloc_valid_o = 1'b0;
    child_alloc_parent_idx_o = parent_q[alloc_lane_idx];
    child_alloc_addr_o = addr_q[alloc_lane_idx];
    child_alloc_axi_beat_o = axi_beat_q[alloc_lane_idx];
    child_event_valid_o = 1'b0;
    child_event_idx_o = child_q[event_lane_idx];
    child_event_type_o = 3'd0;
    child_event_dbid_o = dbid_q[event_lane_idx];
    child_event_resp_o = resp_q[event_lane_idx];
    txreq_valid_o = 1'b0;
    txreq_payload_o = '0;
    txdat_valid_o = 1'b0;
    txdat_payload_o = dat_payload_q[txdat_lane_idx];
    rxrsp_ready_o = 1'b0;
    wr_fragment_ready_o = 1'b0;

    if (!rst) begin
      wr_issue_ready_o = issue_lane_found;
      child_alloc_valid_o = alloc_lane_found;
      if (txreq_lane_found) begin
        txreq_valid_o = 1'b1;
        txreq_payload_o[6:0] = is_full_q[txreq_lane_idx] ? 7'h19 : 7'h18;
        txreq_payload_o[16 +: ChiTxnidWidth] = txnid_q[txreq_lane_idx];
        txreq_payload_o[32 +: AxiAddrWidth] = addr_q[txreq_lane_idx];
      end
      rxrsp_ready_o = dbid_lane_found || comp_lane_found;
      wr_fragment_ready_o = w_lane_found;
      if (txdat_lane_found) begin
        txdat_valid_o = 1'b1;
        txdat_payload_o[8 +: ChiTxnidWidth] = txnid_q[txdat_lane_idx];
        txdat_payload_o[24 +: ChiDbidWidth] = dbid_q[txdat_lane_idx];
      end
      child_event_valid_o = event_lane_found;
      child_event_type_o = resp_q[event_lane_idx][1] ? 3'd5 : 3'd3;
    end

    issue_fire = wr_issue_valid_i && wr_issue_ready_o;
    alloc_fire = child_alloc_valid_o && child_alloc_ready_i;
    txreq_fire = txreq_valid_o && txreq_ready_i;
    dbid_fire = rxrsp_valid_i && dbid_lane_found;
    wr_fragment_fire = wr_fragment_valid_i && wr_fragment_ready_o;
    txdat_fire = txdat_valid_o && txdat_ready_i;
    comp_fire = rxrsp_valid_i && comp_lane_found;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      for (int unsigned idx = 0; idx < ChildEntries; idx++) begin
        state_q[idx] <= kWrIdle;
        parent_q[idx] <= '0;
        child_q[idx] <= '0;
        txnid_q[idx] <= '0;
        dbid_q[idx] <= '0;
        is_full_q[idx] <= EnableWriteNoSnpFull;
        addr_q[idx] <= '0;
        axi_beat_q[idx] <= '0;
        dat_payload_q[idx] <= '0;
        resp_q[idx] <= '0;
        completion_seen_q[idx] <= 1'b0;
      end
    end else begin
      if (issue_fire) begin
        parent_q[issue_lane_idx] <= wr_issue_parent_idx_i;
        addr_q[issue_lane_idx] <= wr_issue_addr_i;
        axi_beat_q[issue_lane_idx] <= wr_issue_axi_beat_i;
        is_full_q[issue_lane_idx] <= EnableWriteNoSnpFull;
        completion_seen_q[issue_lane_idx] <= 1'b0;
        state_q[issue_lane_idx] <= kWrAlloc;
      end

      if (alloc_fire) begin
        child_q[alloc_lane_idx] <= child_alloc_idx_i;
        txnid_q[alloc_lane_idx] <= child_alloc_txnid_i;
        state_q[alloc_lane_idx] <= kWrIssueReq;
      end

      if (txreq_fire) begin
        state_q[txreq_lane_idx] <= kWrWaitDbid;
      end

      if (dbid_fire) begin
        dbid_q[dbid_lane_idx] <= rxrsp_payload_i[24 +: ChiDbidWidth];
        resp_q[dbid_lane_idx] <= rxrsp_payload_i[36 +: 2];
        completion_seen_q[dbid_lane_idx] <= rxrsp_opcode == 4'h2;
        state_q[dbid_lane_idx] <= kWrWaitW;
      end

      if (wr_fragment_fire) begin
        dat_payload_q[w_lane_idx] <= wr_fragment_payload_i;
        state_q[w_lane_idx] <= kWrIssueDat;
      end

      if (txdat_fire) begin
        if (completion_seen_q[txdat_lane_idx]) begin
          state_q[txdat_lane_idx] <= kWrComplete;
        end else begin
          state_q[txdat_lane_idx] <= kWrWaitComp;
        end
      end

      if (comp_fire) begin
        resp_q[comp_lane_idx] <= resp_q[comp_lane_idx] | rxrsp_payload_i[36 +: 2];
        completion_seen_q[comp_lane_idx] <= 1'b1;
        state_q[comp_lane_idx] <= kWrComplete;
      end

      if (child_event_valid_o) begin
        state_q[event_lane_idx] <= kWrIdle;
      end
    end
  end

endmodule

`default_nettype wire
