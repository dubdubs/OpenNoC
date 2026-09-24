`timescale 1ns/1ps
`default_nettype none

`define CHECK(condition) \
  if (!(condition)) begin \
    $fatal(1, "CHECK failed: %s", `"condition`"); \
  end

module tb_axi2chi_nocoh_rd_engine;
  localparam int unsigned AxiAddrWidth = 64;
  localparam int unsigned ChiTxnidWidth = 4;
  localparam int unsigned ReqFlitWidth = 96;
  localparam int unsigned RspFlitWidth = 32;
  localparam int unsigned DatFlitWidth = 128;
  localparam int unsigned ParentEntries = 4;
  localparam int unsigned ChildEntries = 4;

  logic clk = 1'b0;
  logic rst = 1'b1;
  logic rd_issue_valid_i;
  logic rd_issue_ready_o;
  logic [$clog2(ParentEntries)-1:0] rd_issue_parent_idx_i;
  logic [AxiAddrWidth-1:0] rd_issue_addr_i;
  logic [7:0] rd_issue_axi_beat_i;
  logic [1:0] rd_issue_frag_idx_i;
  logic child_alloc_valid_o;
  logic child_alloc_ready_i;
  logic [$clog2(ParentEntries)-1:0] child_alloc_parent_idx_o;
  logic [AxiAddrWidth-1:0] child_alloc_addr_o;
  logic [7:0] child_alloc_axi_beat_o;
  logic [1:0] child_alloc_frag_idx_o;
  logic [$clog2(ChildEntries)-1:0] child_alloc_idx_i;
  logic [ChiTxnidWidth-1:0] child_alloc_txnid_i;
  logic child_event_valid_o;
  logic [$clog2(ChildEntries)-1:0] child_event_idx_o;
  logic [2:0] child_event_type_o;
  logic txreq_valid_o;
  logic [ReqFlitWidth-1:0] txreq_payload_o;
  logic txreq_ready_i;
  logic rxdat_valid_i;
  logic [DatFlitWidth-1:0] rxdat_payload_i;
  logic rxdat_ready_o;
  logic rxrsp_valid_i;
  logic [RspFlitWidth-1:0] rxrsp_payload_i;
  logic rxrsp_ready_o;
  logic rd_fragment_valid_o;
  logic [$clog2(ChildEntries)-1:0] rd_fragment_child_idx_o;
  logic [DatFlitWidth-1:0] rd_fragment_payload_o;
  logic rd_fragment_ready_i;
  logic rd_child_complete_valid_i;
  logic [$clog2(ChildEntries)-1:0] rd_child_complete_idx_i;
  logic unknown_rxdat_fire_o;

  axi2chi_nocoh_rd_engine #(
    .AxiAddrWidth(AxiAddrWidth),
    .ChiTxnidWidth(ChiTxnidWidth),
    .ReqFlitWidth(ReqFlitWidth),
    .RspFlitWidth(RspFlitWidth),
    .DatFlitWidth(DatFlitWidth),
    .ParentEntries(ParentEntries),
    .ChildEntries(ChildEntries)
  ) dut (.*);

  always #5 clk = ~clk;

  initial begin
    rd_issue_valid_i = 1'b0;
    rd_issue_parent_idx_i = '0;
    rd_issue_addr_i = '0;
    rd_issue_axi_beat_i = '0;
    rd_issue_frag_idx_i = '0;
    child_alloc_ready_i = 1'b0;
    child_alloc_idx_i = '0;
    child_alloc_txnid_i = '0;
    txreq_ready_i = 1'b0;
    rxdat_valid_i = 1'b0;
    rxdat_payload_i = '0;
    rxrsp_valid_i = 1'b0;
    rxrsp_payload_i = '0;
    rd_fragment_ready_i = 1'b0;
    rd_child_complete_valid_i = 1'b0;
    rd_child_complete_idx_i = '0;

    #1;
    `CHECK(!rd_issue_ready_o);

    @(negedge clk);
    rst = 1'b0;
    rd_issue_parent_idx_i = 2'd2;
    rd_issue_addr_i = 64'h1234_5678_9abc_def0;
    rd_issue_valid_i = 1'b1;
    #1;
    `CHECK(rd_issue_ready_o);
    @(posedge clk);

    @(negedge clk);
    rd_issue_valid_i = 1'b0;
    #1;
    `CHECK(child_alloc_valid_o);
    `CHECK(child_alloc_parent_idx_o == 2'd2);
    `CHECK(child_alloc_addr_o == 64'h1234_5678_9abc_def0);
    `CHECK(!txreq_valid_o);
    child_alloc_idx_i = 2'd3;
    child_alloc_txnid_i = 4'ha;
    child_alloc_ready_i = 1'b1;
    @(posedge clk);

    @(negedge clk);
    child_alloc_ready_i = 1'b0;
    #1;
    `CHECK(txreq_valid_o);
    `CHECK(txreq_payload_o[6:0] == 7'h04);
    `CHECK(txreq_payload_o[16 +: ChiTxnidWidth] == 4'ha);
    `CHECK(txreq_payload_o[32 +: AxiAddrWidth] ==
        64'h1234_5678_9abc_def0);
    txreq_ready_i = 1'b1;
    @(posedge clk);

    @(negedge clk);
    txreq_ready_i = 1'b0;
    rxdat_payload_i = 128'hfeed_face_cafe_beef_0123_4567_89ab_cdef;
    rxdat_payload_i[8 +: ChiTxnidWidth] = 4'ha;
    #1;
    `CHECK(rxdat_ready_o);
    rxdat_valid_i = 1'b1;
    @(posedge clk);

    @(negedge clk);
    rxdat_valid_i = 1'b0;
    #1;
    `CHECK(rd_fragment_valid_o);
    `CHECK(rd_fragment_child_idx_o == 2'd3);
    `CHECK(rd_fragment_payload_o[8 +: ChiTxnidWidth] == 4'ha);
    `CHECK(rd_fragment_payload_o[64 +: 64] == 64'hfeed_face_cafe_beef);
    rd_fragment_ready_i = 1'b1;
    @(posedge clk);

    @(negedge clk);
    rd_fragment_ready_i = 1'b0;
    #1;
    `CHECK(!child_event_valid_o);
    rd_child_complete_idx_i = 2'd3;
    rd_child_complete_valid_i = 1'b1;
    #1;
    `CHECK(!rxdat_ready_o);
    @(posedge clk);

    @(negedge clk);
    rd_child_complete_valid_i = 1'b0;
    #1;
    `CHECK(rd_issue_ready_o);
    `CHECK(!child_event_valid_o);
    $display("PASS: read engine single child flow");
    $finish;
  end
endmodule

`default_nettype wire

`undef CHECK
