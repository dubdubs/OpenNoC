`timescale 1ns/1ps

// Self-checking unit test for the Scheme-1 policy CSR.  Keeping this test at
// the policy boundary makes commit and admission behavior observable without
// requiring CHI response traffic to drain an RNI transaction.
module tb_param_rni_policy;
  localparam integer ADDR_WIDTH = 16;
  localparam integer REQUESTER_WIDTH = 8;
  localparam integer REGION_COUNT = 4;

  reg clk;
  reg rst;
  reg outstanding_empty;
  reg csr_secure;
  reg csr_write;
  reg [1:0] csr_index;
  reg [ADDR_WIDTH-1:0] csr_base;
  reg [ADDR_WIDTH-1:0] csr_limit;
  reg [REQUESTER_WIDTH-1:0] csr_requester_value;
  reg [REQUESTER_WIDTH-1:0] csr_requester_mask;
  reg [1:0] csr_allowed_profiles;
  reg csr_default_coherent;
  reg csr_allow_intent;
  reg csr_ns_only;
  reg csr_lock;
  reg csr_commit;
  reg csr_security_event_clear;
  wire csr_locked;
  wire csr_commit_busy;
  wire csr_commit_error;
  wire security_event;
  wire admission_block;
  wire [7:0] policy_epoch;

  reg ar_query_valid;
  reg [ADDR_WIDTH-1:0] ar_addr;
  reg [REQUESTER_WIDTH-1:0] ar_requester;
  reg ar_nonsecure;
  reg ar_intent_valid;
  reg ar_coherent_intent;
  wire ar_allow;
  wire ar_profile_coherent;
  reg aw_query_valid;
  reg [ADDR_WIDTH-1:0] aw_addr;
  reg [REQUESTER_WIDTH-1:0] aw_requester;
  reg aw_nonsecure;
  reg aw_intent_valid;
  reg aw_coherent_intent;
  wire aw_allow;
  wire aw_profile_coherent;
  integer failure_count;
  wire capability_done;

  tb_param_rni_policy_capability capability_check (
      .clk(clk), .rst(rst), .done(capability_done)
  );

  rni_policy_csr #(
      .ADDR_WIDTH(ADDR_WIDTH),
      .REGION_COUNT(REGION_COUNT),
      .REQUESTER_WIDTH(REQUESTER_WIDTH),
      .ENABLE_POLICY_CSR(1),
      .ENABLE_NONCOHERENT(1),
      .ENABLE_COHERENT_REQ(1),
      .DEFAULT_COHERENT(0)
  ) dut (
      .clk_i(clk), .rst_i(rst), .outstanding_empty_i(outstanding_empty),
      .csr_secure_i(csr_secure), .csr_write_i(csr_write),
      .csr_index_i(csr_index), .csr_base_i(csr_base),
      .csr_limit_i(csr_limit),
      .csr_requester_value_i(csr_requester_value),
      .csr_requester_mask_i(csr_requester_mask),
      .csr_allowed_profiles_i(csr_allowed_profiles),
      .csr_default_coherent_i(csr_default_coherent),
      .csr_allow_intent_i(csr_allow_intent), .csr_ns_only_i(csr_ns_only),
      .csr_lock_i(csr_lock), .csr_commit_i(csr_commit),
      .csr_security_event_clear_i(csr_security_event_clear),
      .csr_locked_o(csr_locked), .csr_commit_busy_o(csr_commit_busy),
      .csr_commit_error_o(csr_commit_error), .security_event_o(security_event),
      .admission_block_o(admission_block), .policy_epoch_o(policy_epoch),
      .ar_query_valid_i(ar_query_valid), .ar_addr_i(ar_addr),
      .ar_requester_i(ar_requester), .ar_nonsecure_i(ar_nonsecure),
      .ar_intent_valid_i(ar_intent_valid),
      .ar_coherent_intent_i(ar_coherent_intent), .ar_allow_o(ar_allow),
      .ar_profile_coherent_o(ar_profile_coherent),
      .aw_query_valid_i(aw_query_valid), .aw_addr_i(aw_addr),
      .aw_requester_i(aw_requester), .aw_nonsecure_i(aw_nonsecure),
      .aw_intent_valid_i(aw_intent_valid),
      .aw_coherent_intent_i(aw_coherent_intent), .aw_allow_o(aw_allow),
      .aw_profile_coherent_o(aw_profile_coherent)
  );

  always #5 clk = ~clk;

  task automatic expect_bit;
    input actual;
    input expected;
    input [8*64-1:0] description;
    begin
      if (actual !== expected) begin
        $error("%0s: expected %b, got %b", description, expected, actual);
        failure_count = failure_count + 1;
      end
    end
  endtask

  task automatic expect_epoch;
    input [7:0] expected;
    begin
      if (policy_epoch !== expected) begin
        $error("policy epoch: expected %0d, got %0d", expected, policy_epoch);
        failure_count = failure_count + 1;
      end
    end
  endtask

  task automatic program_region;
    input [1:0] index;
    input [ADDR_WIDTH-1:0] base;
    input [ADDR_WIDTH-1:0] limit;
    input [REQUESTER_WIDTH-1:0] requester_value;
    input [REQUESTER_WIDTH-1:0] requester_mask;
    input [1:0] allowed_profiles;
    input default_coherent;
    input allow_intent;
    input ns_only;
    begin
      @(negedge clk);
      csr_index = index;
      csr_base = base;
      csr_limit = limit;
      csr_requester_value = requester_value;
      csr_requester_mask = requester_mask;
      csr_allowed_profiles = allowed_profiles;
      csr_default_coherent = default_coherent;
      csr_allow_intent = allow_intent;
      csr_ns_only = ns_only;
      csr_write = 1'b1;
      @(negedge clk);
      csr_write = 1'b0;
    end
  endtask

  task automatic request_commit;
    begin
      @(negedge clk);
      csr_commit = 1'b1;
      @(negedge clk);
      csr_commit = 1'b0;
    end
  endtask

  task automatic clear_security_event;
    begin
      @(negedge clk);
      csr_security_event_clear = 1'b1;
      @(negedge clk);
      csr_security_event_clear = 1'b0;
    end
  endtask

  task automatic check_query;
    input [ADDR_WIDTH-1:0] address;
    input [REQUESTER_WIDTH-1:0] requester;
    input nonsecure;
    input intent_valid;
    input coherent_intent;
    input expected_allow;
    input expected_coherent;
    input [8*64-1:0] description;
    begin
      ar_addr = address;
      ar_requester = requester;
      ar_nonsecure = nonsecure;
      ar_intent_valid = intent_valid;
      ar_coherent_intent = coherent_intent;
      ar_query_valid = 1'b1;
      aw_addr = address;
      aw_requester = requester;
      aw_nonsecure = nonsecure;
      aw_intent_valid = intent_valid;
      aw_coherent_intent = coherent_intent;
      aw_query_valid = 1'b1;
      // Hold the query over a clock edge so denied accesses also exercise the
      // policy audit event, which is synchronous in the RTL.
      @(posedge clk);
      #1;
      expect_bit(ar_allow, expected_allow, description);
      expect_bit(aw_allow, expected_allow, description);
      expect_bit(ar_profile_coherent, expected_coherent, description);
      expect_bit(aw_profile_coherent, expected_coherent, description);
      ar_query_valid = 1'b0;
      aw_query_valid = 1'b0;
    end
  endtask

  initial begin
    clk = 1'b0;
    rst = 1'b1;
    outstanding_empty = 1'b1;
    csr_secure = 1'b1;
    csr_write = 1'b0;
    csr_index = '0;
    csr_base = '0;
    csr_limit = '0;
    csr_requester_value = '0;
    csr_requester_mask = '0;
    csr_allowed_profiles = '0;
    csr_default_coherent = 1'b0;
    csr_allow_intent = 1'b0;
    csr_ns_only = 1'b0;
    csr_lock = 1'b0;
    csr_commit = 1'b0;
    csr_security_event_clear = 1'b0;
    ar_query_valid = 1'b0;
    ar_addr = '0;
    ar_requester = '0;
    ar_nonsecure = 1'b0;
    ar_intent_valid = 1'b0;
    ar_coherent_intent = 1'b0;
    aw_query_valid = 1'b0;
    aw_addr = '0;
    aw_requester = '0;
    aw_nonsecure = 1'b0;
    aw_intent_valid = 1'b0;
    aw_coherent_intent = 1'b0;
    failure_count = 0;

    repeat (3) @(posedge clk);
    rst = 1'b0;

    // Untrusted CSR accesses must not alter shadow state and must be audited.
    csr_secure = 1'b0;
    program_region(2'd0, 16'h1000, 16'h2000, 8'h2a, 8'hff, 2'b11,
                   1'b0, 1'b1, 1'b1);
    @(posedge clk); #1;
    expect_bit(security_event, 1'b1, "non-secure CSR write raises event");
    csr_secure = 1'b1;
    clear_security_event();
    @(posedge clk); #1;
    expect_bit(security_event, 1'b0, "secure event clear");

    // A commit holds admission closed until the externally tracked work drains.
    program_region(2'd0, 16'h1000, 16'h2000, 8'h2a, 8'hff, 2'b11,
                   1'b0, 1'b1, 1'b1);
    outstanding_empty = 1'b0;
    request_commit();
    #1;
    expect_bit(csr_commit_busy, 1'b1, "commit reports busy while work remains");
    expect_bit(admission_block, 1'b1, "commit blocks new admissions");
    expect_epoch(8'd0);
    repeat (2) begin
      @(posedge clk); #1;
      expect_bit(csr_commit_busy, 1'b1,
                 "commit busy must remain asserted until drain");
    end
    program_region(2'd0, 16'h4000, 16'h5000, 8'h00, 8'h00, 2'b01,
                   1'b0, 1'b0, 1'b0);
    #1;
    expect_bit(csr_commit_error, 1'b1,
               "pending commit must reject shadow writes");
    check_query(16'h1000, 8'h2a, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
                "blocked query while commit is pending");
    outstanding_empty = 1'b1;
    @(posedge clk); #1;
    expect_bit(admission_block, 1'b0, "commit unblocks after drain");
    expect_bit(csr_commit_busy, 1'b0, "busy clears after drain");
    expect_epoch(8'd1);

    // Region range, requester, nonsecure and intent selection apply to AR/AW.
    check_query(16'h1000, 8'h2a, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0,
                "default noncoherent profile");
    check_query(16'h1fff, 8'h2a, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1,
                "coherent intent profile");
    check_query(16'h1000, 8'h2b, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
                "requester mismatch is denied");
    check_query(16'h1000, 8'h2a, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
                "secure request rejected by nonsecure-only region");
    check_query(16'h2000, 8'h2a, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
                "region limit is exclusive");
    @(posedge clk); #1;
    expect_bit(security_event, 1'b1, "denied request raises event");
    clear_security_event();

    // Invalid and overlapping shadow maps are rejected without an epoch change.
    program_region(2'd1, 16'h3000, 16'h3000, 8'h00, 8'h00, 2'b01,
                   1'b0, 1'b0, 1'b0);
    request_commit();
    #1;
    expect_bit(csr_commit_error, 1'b1, "empty region is rejected");
    expect_epoch(8'd1);
    program_region(2'd1, 16'h1800, 16'h2800, 8'h00, 8'h00, 2'b01,
                   1'b0, 1'b0, 1'b0);
    request_commit();
    #1;
    expect_bit(csr_commit_error, 1'b1, "overlapping regions are rejected");
    expect_epoch(8'd1);
    program_region(2'd1, 16'h0000, 16'h0000, 8'h00, 8'h00, 2'b00,
                   1'b0, 1'b0, 1'b0);
    request_commit();
    @(posedge clk); #1;
    expect_epoch(8'd2);

    // Lock freezes the policy table: later secure writes and commits are ignored.
    @(negedge clk);
    csr_lock = 1'b1;
    @(negedge clk);
    csr_lock = 1'b0;
    #1;
    expect_bit(csr_locked, 1'b1, "secure lock engages");
    program_region(2'd0, 16'h1000, 16'h2000, 8'h2a, 8'hff, 2'b01,
                   1'b1, 1'b0, 1'b0);
    request_commit();
    @(posedge clk); #1;
    expect_epoch(8'd2);
    check_query(16'h1000, 8'h2a, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1,
                "locked table retains committed coherent-intent policy");

    wait (capability_done);

    if (failure_count != 0) begin
      $fatal(1, "tb_param_rni_policy failed with %0d mismatches", failure_count);
    end
    $display("tb_param_rni_policy PASS: security, commit, region and lock policy");
    $finish;
  end

  initial begin
    #10000;
    $fatal(1, "tb_param_rni_policy timeout");
  end
endmodule

module tb_param_rni_policy_capability (
    input wire clk,
    input wire rst,
    output reg done
);
  reg csr_write;
  reg csr_commit;
  wire commit_error;

  rni_policy_csr #(
      .ADDR_WIDTH(16), .REGION_COUNT(1), .REQUESTER_WIDTH(8),
      .ENABLE_POLICY_CSR(1), .ENABLE_NONCOHERENT(1),
      .ENABLE_COHERENT_REQ(0), .DEFAULT_COHERENT(0)
  ) dut (
      .clk_i(clk), .rst_i(rst), .outstanding_empty_i(1'b1),
      .csr_secure_i(1'b1), .csr_write_i(csr_write), .csr_index_i(1'b0),
      .csr_base_i(16'h0000), .csr_limit_i(16'h1000),
      .csr_requester_value_i(8'h00), .csr_requester_mask_i(8'h00),
      .csr_allowed_profiles_i(2'b10), .csr_default_coherent_i(1'b1),
      .csr_allow_intent_i(1'b0), .csr_ns_only_i(1'b0),
      .csr_lock_i(1'b0), .csr_commit_i(csr_commit),
      .csr_security_event_clear_i(1'b0), .csr_locked_o(),
      .csr_commit_busy_o(), .csr_commit_error_o(commit_error),
      .security_event_o(), .admission_block_o(), .policy_epoch_o(),
      .ar_query_valid_i(1'b0), .ar_addr_i(16'h0),
      .ar_requester_i(8'h0), .ar_nonsecure_i(1'b0),
      .ar_intent_valid_i(1'b0), .ar_coherent_intent_i(1'b0),
      .ar_allow_o(), .ar_profile_coherent_o(), .aw_query_valid_i(1'b0),
      .aw_addr_i(16'h0), .aw_requester_i(8'h0), .aw_nonsecure_i(1'b0),
      .aw_intent_valid_i(1'b0), .aw_coherent_intent_i(1'b0),
      .aw_allow_o(), .aw_profile_coherent_o()
  );

  initial begin
    done = 1'b0;
    csr_write = 1'b0;
    csr_commit = 1'b0;
    wait (!rst);
    @(negedge clk);
    csr_write = 1'b1;
    @(negedge clk);
    csr_write = 1'b0;
    csr_commit = 1'b1;
    @(posedge clk); #1;
    if (!commit_error)
      $fatal(1, "policy accepted a disabled coherent profile");
    @(negedge clk);
    csr_commit = 1'b0;
    done = 1'b1;
  end
endmodule
