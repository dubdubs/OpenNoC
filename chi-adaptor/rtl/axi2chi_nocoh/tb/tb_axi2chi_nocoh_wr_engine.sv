`timescale 1ns/1ps
`default_nettype none

`define CHECK(condition) \
  if (!(condition)) begin \
    $fatal(1, "CHECK failed: %s", `"condition`"); \
  end

module tb_axi2chi_nocoh_wr_engine;
  localparam int unsigned AxiAddrWidth = 64;
  localparam int unsigned ChiTxnidWidth = 4;
  localparam int unsigned ChiDbidWidth = 4;
  localparam int unsigned ReqFlitWidth = 96;
  localparam int unsigned RspFlitWidth = 64;
  localparam int unsigned DatFlitWidth = 128;
  localparam int unsigned ParentEntries = 4;
  localparam int unsigned ChildEntries = 4;

  logic clk = 1'b0;
  logic rst = 1'b1;
  logic wr_issue_valid_i;
  logic wr_issue_ready_o;
  logic [$clog2(ParentEntries)-1:0] wr_issue_parent_idx_i;
  logic [AxiAddrWidth-1:0] wr_issue_addr_i;
  logic [7:0] wr_issue_axi_beat_i;
  logic [1:0] wr_issue_frag_idx_i;
  logic wr_issue_full_candidate_i;
  logic [ParentEntries-1:0] wr_beat_present_vec_i;
  logic [ParentEntries-1:0] wr_beat_full_vec_i;
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
  logic [ChiDbidWidth-1:0] child_event_dbid_o;
  logic [1:0] child_event_resp_o;
  logic txreq_valid_o;
  logic [ReqFlitWidth-1:0] txreq_payload_o;
  logic txreq_ready_i;
  logic txdat_valid_o;
  logic [DatFlitWidth-1:0] txdat_payload_o;
  logic txdat_ready_i;
  logic rxrsp_valid_i;
  logic [RspFlitWidth-1:0] rxrsp_payload_i;
  logic rxrsp_ready_o;
  logic wr_fragment_valid_i;
  logic [$clog2(ChildEntries)-1:0] wr_fragment_child_idx_i;
  logic [DatFlitWidth-1:0] wr_fragment_payload_i;
  logic wr_fragment_last_i;
  logic wr_fragment_error_i;
  logic wr_fragment_ready_o;
  logic [ChildEntries-1:0] wr_wait_child_vec_o;

  axi2chi_nocoh_wr_engine #(
    .AxiAddrWidth(AxiAddrWidth),
    .ChiTxnidWidth(ChiTxnidWidth),
    .ChiDbidWidth(ChiDbidWidth),
    .ReqFlitWidth(ReqFlitWidth),
    .RspFlitWidth(RspFlitWidth),
    .DatFlitWidth(DatFlitWidth),
    .ParentEntries(ParentEntries),
    .ChildEntries(ChildEntries),
    .EnableWriteNoSnpFull(1'b1)
  ) dut (.*);

  always #5 clk = ~clk;

  initial begin
    wr_issue_valid_i = 1'b0;
    wr_issue_parent_idx_i = '0;
    wr_issue_addr_i = '0;
    wr_issue_axi_beat_i = '0;
    wr_issue_frag_idx_i = '0;
    wr_issue_full_candidate_i = 1'b0;
    wr_beat_present_vec_i = '0;
    wr_beat_full_vec_i = '0;
    child_alloc_ready_i = 1'b0;
    child_alloc_idx_i = '0;
    child_alloc_txnid_i = '0;
    txreq_ready_i = 1'b0;
    txdat_ready_i = 1'b0;
    rxrsp_valid_i = 1'b0;
    rxrsp_payload_i = '0;
    wr_fragment_valid_i = 1'b0;
    wr_fragment_child_idx_i = '0;
    wr_fragment_payload_i = '0;
    wr_fragment_last_i = 1'b1;
    wr_fragment_error_i = 1'b0;

    #1;
    `CHECK(!wr_issue_ready_o);

    @(negedge clk);
    rst = 1'b0;
    wr_issue_parent_idx_i = 2'd1;
    wr_issue_addr_i = 64'hcc00_0010;
    wr_issue_valid_i = 1'b1;
    #1;
    `CHECK(wr_issue_ready_o);
    @(posedge clk);

    @(negedge clk);
    wr_issue_valid_i = 1'b0;
    #1;
    `CHECK(child_alloc_valid_o);
    `CHECK(child_alloc_parent_idx_o == 2'd1);
    `CHECK(child_alloc_addr_o == 64'hcc00_0010);
    child_alloc_idx_i = 2'd2;
    child_alloc_txnid_i = 4'h7;
    child_alloc_ready_i = 1'b1;
    @(posedge clk);

    @(negedge clk);
    child_alloc_ready_i = 1'b0;
    #1;
    `CHECK(txreq_valid_o);
    `CHECK(txreq_payload_o[6:0] == 7'h18);
    `CHECK(txreq_payload_o[16 +: ChiTxnidWidth] == 4'h7);
    `CHECK(txreq_payload_o[32 +: AxiAddrWidth] == 64'hcc00_0010);
    txreq_ready_i = 1'b1;
    @(posedge clk);

    @(negedge clk);
    txreq_ready_i = 1'b0;
    rxrsp_payload_i[3:0] = 4'h1;
    rxrsp_payload_i[8 +: ChiTxnidWidth] = 4'h7;
    #1;
    `CHECK(rxrsp_ready_o);
    rxrsp_payload_i[24 +: ChiDbidWidth] = 4'hc;
    rxrsp_payload_i[36 +: 2] = 2'b00;
    rxrsp_valid_i = 1'b1;
    @(posedge clk);

    @(negedge clk);
    rxrsp_valid_i = 1'b0;
    wr_fragment_child_idx_i = 2'd2;
    #1;
    `CHECK(wr_fragment_ready_o);
    wr_fragment_payload_i = 128'h0123_4567_89ab_cdef_feed_face_cafe_beef;
    wr_fragment_valid_i = 1'b1;
    @(posedge clk);

    @(negedge clk);
    wr_fragment_valid_i = 1'b0;
    #1;
    `CHECK(txdat_valid_o);
    `CHECK(txdat_payload_o[24 +: ChiDbidWidth] == 4'hc);
    txdat_ready_i = 1'b1;
    @(posedge clk);

    @(negedge clk);
    txdat_ready_i = 1'b0;
    rxrsp_payload_i = '0;
    rxrsp_payload_i[3:0] = 4'h3;
    rxrsp_payload_i[8 +: ChiTxnidWidth] = 4'h7;
    #1;
    `CHECK(rxrsp_ready_o);
    rxrsp_payload_i[36 +: 2] = 2'b00;
    rxrsp_valid_i = 1'b1;
    @(posedge clk);

    @(negedge clk);
    rxrsp_valid_i = 1'b0;
    #1;
    `CHECK(child_event_valid_o);
    `CHECK(child_event_idx_o == 2'd2);
    `CHECK(child_event_type_o == 3'd3);
    `CHECK(child_event_dbid_o == 4'hc);
    `CHECK(child_event_resp_o == 2'b00);
    @(posedge clk);

    @(negedge clk);
    #1;
    `CHECK(wr_issue_ready_o);

    // CompDBIDResp permits the data transfer and already carries completion.
    wr_issue_parent_idx_i = 2'd0;
    wr_issue_addr_i = 64'hcc00_0020;
    wr_issue_full_candidate_i = 1'b1;
    wr_beat_present_vec_i[0] = 1'b1;
    wr_beat_full_vec_i[0] = 1'b1;
    wr_issue_valid_i = 1'b1;
    @(posedge clk);

    @(negedge clk);
    wr_issue_valid_i = 1'b0;
    child_alloc_idx_i = 2'd1;
    child_alloc_txnid_i = 4'h8;
    child_alloc_ready_i = 1'b1;
    #1;
    `CHECK(child_alloc_valid_o);
    @(posedge clk);

    @(negedge clk);
    child_alloc_ready_i = 1'b0;
    txreq_ready_i = 1'b1;
    #1;
    `CHECK(txreq_valid_o);
    `CHECK(txreq_payload_o[6:0] == 7'h19);
    @(posedge clk);

    @(negedge clk);
    txreq_ready_i = 1'b0;
    rxrsp_payload_i = '0;
    rxrsp_payload_i[3:0] = 4'h2;
    rxrsp_payload_i[8 +: ChiTxnidWidth] = 4'h8;
    rxrsp_payload_i[24 +: ChiDbidWidth] = 4'hd;
    rxrsp_valid_i = 1'b1;
    #1;
    `CHECK(rxrsp_ready_o);
    @(posedge clk);

    @(negedge clk);
    rxrsp_valid_i = 1'b0;
    wr_fragment_child_idx_i = 2'd1;
    wr_fragment_payload_i = 128'h0bad_f00d_cafe_babe_0123_4567_89ab_cdef;
    wr_fragment_valid_i = 1'b1;
    #1;
    `CHECK(wr_fragment_ready_o);
    @(posedge clk);

    @(negedge clk);
    wr_fragment_valid_i = 1'b0;
    txdat_ready_i = 1'b1;
    #1;
    `CHECK(txdat_valid_o);
    `CHECK(txdat_payload_o[24 +: ChiDbidWidth] == 4'hd);
    @(posedge clk);

    @(negedge clk);
    txdat_ready_i = 1'b0;
    #1;
    `CHECK(child_event_valid_o);
    `CHECK(child_event_idx_o == 2'd1);
    `CHECK(child_event_type_o == 3'd5);
    `CHECK(child_event_dbid_o == 4'hd);
    $display("PASS: write engine DBIDResp and CompDBIDResp flows");
    $finish;
  end
endmodule

`default_nettype wire

`undef CHECK
