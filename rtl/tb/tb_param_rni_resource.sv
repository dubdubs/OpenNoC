`timescale 1ns/1ps

// Unit regression for the serialization resource used by the parameterized
// RNI.  It exercises same-line cross-profile exclusion, release/reacquire,
// table-full backpressure, and reset recovery without relying on AXI timing.
module tb_param_rni_resource;
  logic clk;
  logic rst;
  logic acquire_valid;
  logic [43:0] acquire_addr;
  logic acquire_profile;
  logic [3:0] acquire_owner;
  wire acquire_ready;
  logic release_valid;
  logic [3:0] release_owner;
  wire empty;
  integer failures;

  rni_line_hazard #(
      .ADDR_WIDTH(44),
      .OWNER_WIDTH(4),
      .ENTRIES(2)
  ) dut (
      .clk_i(clk),
      .rst_i(rst),
      .acquire_valid_i(acquire_valid),
      .acquire_addr_i(acquire_addr),
      .acquire_profile_i(acquire_profile),
      .acquire_owner_i(acquire_owner),
      .acquire_ready_o(acquire_ready),
      .release_valid_i(release_valid),
      .release_owner_i(release_owner),
      .empty_o(empty)
  );

  always #5 clk = ~clk;

  task automatic check_value(input logic actual, input logic expected,
                             input string description);
    begin
      if (actual !== expected) begin
        $error("%s: expected %b, got %b", description, expected, actual);
        failures = failures + 1;
      end
    end
  endtask

  task automatic acquire(input logic [43:0] address, input logic profile,
                         input logic [3:0] owner);
    begin
      @(negedge clk);
      acquire_addr = address;
      acquire_profile = profile;
      acquire_owner = owner;
      acquire_valid = 1'b1;
      @(posedge clk);
      #1;
      @(negedge clk);
      acquire_valid = 1'b0;
    end
  endtask

  task automatic release_hazard(input logic [3:0] owner);
    begin
      @(negedge clk);
      release_owner = owner;
      release_valid = 1'b1;
      @(posedge clk);
      #1;
      @(negedge clk);
      release_valid = 1'b0;
    end
  endtask

  initial begin
    clk = 1'b0;
    rst = 1'b1;
    acquire_valid = 1'b0;
    acquire_addr = '0;
    acquire_profile = 1'b0;
    acquire_owner = '0;
    release_valid = 1'b0;
    release_owner = '0;
    failures = 0;

    repeat (2) @(posedge clk);
    rst = 1'b0;
    @(negedge clk);
    check_value(empty, 1'b1, "hazard table must be empty after reset");

    // Same profile may proceed; opposite profiles on the same 64-byte line
    // must wait for the owner to retire.
    check_value(acquire_ready, 1'b1, "first acquire must be accepted");
    acquire(44'h0000_0000_1008, 1'b0, 4'h1);
    @(negedge clk);
    check_value(empty, 1'b0, "first acquire must occupy the table");
    acquire_addr = 44'h0000_0000_103f;
    acquire_profile = 1'b1;
    acquire_owner = 4'h2;
    #1;
    check_value(acquire_ready, 1'b0, "opposite profile on same line must stall");
    acquire_addr = 44'h0000_0000_1080;
    #1;
    check_value(acquire_ready, 1'b1, "different line must not stall");
    acquire(44'h0000_0000_1080, 1'b1, 4'h2);
    @(negedge clk);
    check_value(acquire_ready, 1'b0, "full hazard table must backpressure");

    release_hazard(4'h1);
    @(negedge clk);
    acquire_addr = 44'h0000_0000_1020;
    acquire_profile = 1'b1;
    acquire_owner = 4'h3;
    #1;
    check_value(acquire_ready, 1'b1, "release must unblock opposite profile");
    acquire(44'h0000_0000_1020, 1'b1, 4'h3);
    release_hazard(4'h2);
    release_hazard(4'h3);
    @(negedge clk);
    check_value(empty, 1'b1, "all released owners must drain the table");

    acquire(44'h0000_0000_2000, 1'b0, 4'h4);
    rst = 1'b1;
    repeat (2) @(posedge clk);
    rst = 1'b0;
    @(negedge clk);
    check_value(empty, 1'b1, "reset must clear outstanding ownership");

    if (failures != 0) begin
      $fatal(1, "tb_param_rni_resource failed with %0d mismatches", failures);
    end
    $display("tb_param_rni_resource PASS: hazards, capacity, release, reset");
    $finish;
  end

  initial begin
    #5000;
    $fatal(1, "tb_param_rni_resource timeout");
  end
endmodule
