`timescale 1ns/1ps
`default_nettype none

`define CHECK(condition) \
  if (!(condition)) begin \
    $fatal(1, "CHECK failed: %s", `"condition`"); \
  end

module tb_axi2chi_nocoh_txn_ctx_child;
  localparam int unsigned AxiAddrWidth = 64;
  localparam int unsigned AxiIdWidth = 4;
  localparam int unsigned AxlenWidth = 8;
  localparam int unsigned AxsizeWidth = 3;
  localparam int unsigned ChiTxnidWidth = 3;
  localparam int unsigned ChiDbidWidth = 4;
  localparam int unsigned ParentEntries = 2;
  localparam int unsigned ChildEntries = 2;
  localparam int unsigned TxnidEntries = 2;

  logic clk = 1'b0;
  logic rst = 1'b1;
  logic rd_admit_valid_i;
  logic rd_admit_ready_o;
  logic [AxiIdWidth-1:0] rd_admit_id_i;
  logic [AxiAddrWidth-1:0] rd_admit_addr_i;
  logic [AxlenWidth-1:0] rd_admit_len_i;
  logic [AxsizeWidth-1:0] rd_admit_size_i;
  logic [1:0] rd_admit_burst_i;
  logic wr_admit_valid_i;
  logic wr_admit_ready_o;
  logic [AxiIdWidth-1:0] wr_admit_id_i;
  logic [AxiAddrWidth-1:0] wr_admit_addr_i;
  logic [AxlenWidth-1:0] wr_admit_len_i;
  logic [AxsizeWidth-1:0] wr_admit_size_i;
  logic [1:0] wr_admit_burst_i;
  logic [$clog2(ParentEntries)-1:0] rd_admit_parent_idx_o;
  logic [$clog2(ParentEntries)-1:0] wr_admit_parent_idx_o;
  logic rd_issue_valid_o;
  logic rd_issue_ready_i;
  logic [$clog2(ParentEntries)-1:0] rd_issue_parent_idx_o;
  logic [AxiAddrWidth-1:0] rd_issue_addr_o;
  logic [AxlenWidth-1:0] rd_issue_axi_beat_o;
  logic wr_issue_valid_o;
  logic wr_issue_ready_i;
  logic [$clog2(ParentEntries)-1:0] wr_issue_parent_idx_o;
  logic [AxiAddrWidth-1:0] wr_issue_addr_o;
  logic [AxlenWidth-1:0] wr_issue_axi_beat_o;
  logic child_alloc_valid_i;
  logic child_alloc_ready_o;
  logic [$clog2(ParentEntries)-1:0] child_alloc_parent_idx_i;
  logic child_alloc_is_write_i;
  logic [AxlenWidth-1:0] child_alloc_axi_beat_i;
  logic [AxiAddrWidth-1:0] child_alloc_addr_i;
  logic [1:0] child_alloc_frag_idx_i;
  logic [$clog2(ChildEntries)-1:0] child_alloc_idx_o;
  logic [ChiTxnidWidth-1:0] child_alloc_txnid_o;
  logic child_release_valid_i;
  logic child_release_ready_o;
  logic [$clog2(ChildEntries)-1:0] child_release_idx_i;
  logic child_event_valid_i;
  logic [$clog2(ChildEntries)-1:0] child_event_idx_i;
  logic [2:0] child_event_type_i;
  logic [ChiDbidWidth-1:0] child_event_dbid_i;
  logic [1:0] child_event_resp_i;
  logic [$clog2(ParentEntries)-1:0] child_event_parent_idx_o;
  logic child_event_parent_complete_o;
  logic child_event_parent_error_o;
  logic child_lookup_valid_i;
  logic [$clog2(ChildEntries)-1:0] child_lookup_idx_i;
  logic child_lookup_valid_o;
  logic [$clog2(ParentEntries)-1:0] child_lookup_parent_idx_o;
  logic [AxiIdWidth-1:0] child_lookup_axi_id_o;
  logic child_lookup_is_write_o;
  logic child_lookup_last_o;
  logic parent_retire_valid_i;
  logic [$clog2(ParentEntries)-1:0] parent_retire_idx_i;
  logic parent_retire_ready_o;

  axi2chi_nocoh_txn_ctx #(
    .AxiAddrWidth(AxiAddrWidth), .AxiIdWidth(AxiIdWidth),
    .AxlenWidth(AxlenWidth), .AxsizeWidth(AxsizeWidth),
    .ChiTxnidWidth(ChiTxnidWidth), .ChiDbidWidth(ChiDbidWidth),
    .ParentEntries(ParentEntries), .ChildEntries(ChildEntries),
    .TxnidEntries(TxnidEntries)
  ) dut (.*);

  always #5 clk = ~clk;

  initial begin
    rd_admit_valid_i = 1'b0;
    rd_admit_id_i = '0;
    rd_admit_addr_i = '0;
    rd_admit_len_i = '0;
    rd_admit_size_i = '0;
    rd_admit_burst_i = '0;
    wr_admit_valid_i = 1'b0;
    wr_admit_id_i = '0;
    wr_admit_addr_i = '0;
    wr_admit_len_i = '0;
    wr_admit_size_i = '0;
    wr_admit_burst_i = '0;
    child_alloc_valid_i = 1'b0;
    child_alloc_parent_idx_i = '0;
    child_alloc_is_write_i = 1'b0;
    child_alloc_axi_beat_i = '0;
    child_alloc_addr_i = '0;
    child_alloc_frag_idx_i = '0;
    child_release_valid_i = 1'b0;
    child_release_idx_i = '0;
    child_event_valid_i = 1'b0;
    child_event_idx_i = '0;
    child_event_type_i = '0;
    child_event_dbid_i = '0;
    child_event_resp_i = '0;
    child_lookup_valid_i = 1'b0;
    child_lookup_idx_i = '0;
    parent_retire_valid_i = 1'b0;
    parent_retire_idx_i = '0;
    rd_issue_ready_i = 1'b0;
    wr_issue_ready_i = 1'b0;

    @(negedge clk);
    rst = 1'b0;
    rd_admit_valid_i = 1'b1;
    #1;
    `CHECK(rd_admit_ready_o);
    @(posedge clk);
    @(negedge clk);
    rd_admit_valid_i = 1'b0;
    child_alloc_parent_idx_i = '0;
    child_alloc_addr_i = 64'h1000;
    child_alloc_valid_i = 1'b1;
    #1;
    `CHECK(child_alloc_ready_o && child_alloc_idx_o == 1'd0);
    `CHECK(child_alloc_txnid_o == 3'd0);
    @(posedge clk);
    @(negedge clk);
    child_alloc_addr_i = 64'h1010;
    child_alloc_axi_beat_i = 8'd1;
    #1;
    `CHECK(child_alloc_ready_o && child_alloc_idx_o == 1'd1);
    `CHECK(child_alloc_txnid_o == 3'd1);
    @(posedge clk);
    @(negedge clk);
    child_alloc_valid_i = 1'b0;
    #1;
    `CHECK(!child_alloc_ready_o);
    child_release_idx_i = 1'd0;
    child_release_valid_i = 1'b1;
    #1;
    `CHECK(child_release_ready_o);
    @(posedge clk);
    @(negedge clk);
    child_release_valid_i = 1'b0;
    child_alloc_valid_i = 1'b1;
    #1;
    `CHECK(child_alloc_ready_o && child_alloc_idx_o == 1'd0);
    `CHECK(child_alloc_txnid_o == 3'd0);
    $display("PASS: child context and TxnID allocation/release");
    $finish;
  end
endmodule

`default_nettype wire

`undef CHECK
