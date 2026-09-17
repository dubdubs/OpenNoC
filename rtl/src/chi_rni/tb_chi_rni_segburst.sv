// Deterministic testbench for chi_rni_segburst.
// Drives inputs and samples outputs at negedge so no posedge race exists.
`include "chi_rni_defines.svh"

module tb_chi_rni_segburst;
  logic clk = 0;
  logic rst_n = 0;
  logic start_valid = 0;
  logic start_ready;
  logic [43:0] start_addr = '0;
  logic [7:0]  start_len  = '0;
  logic [2:0]  start_size = '0;
  logic [1:0]  start_burst = '0;
  logic coalesce = 1'b0;
  logic device   = 1'b0;
  logic child_valid;
  logic child_ready = 1'b1;
  logic [43:0] child_addr;
  logic [2:0]  child_size;
  logic [6:0]  child_bytes;
  logic child_last;

  chi_rni_segburst #(.ADDR_WIDTH(44)) dut(
    .clk(clk), .rst_n(rst_n),
    .start_valid(start_valid), .start_ready(start_ready),
    .start_addr(start_addr), .start_len(start_len),
    .start_size(start_size), .start_burst(start_burst),
    .coalesce(coalesce), .device(device),
    .child_valid(child_valid), .child_ready(child_ready),
    .child_addr(child_addr), .child_size(child_size),
    .child_bytes(child_bytes), .child_last(child_last)
  );

  always #5 clk = ~clk;

  int errors = 0;
  int n;

  // Sample the CURRENT negedge (no leading wait): the caller owns timing.
  task automatic check(input logic [43:0] exp_addr,
                       input logic [6:0]  exp_bytes,
                       input logic        exp_last);
    begin
      if (!child_valid) begin
        $display("FAIL child[%0d]: child_valid=0 at %0t", n, $time);
        errors = errors + 1;
      end else if (child_addr !== exp_addr || child_bytes !== exp_bytes ||
                   child_last !== exp_last) begin
        $display("FAIL child[%0d]: addr=0x%h size=%0d bytes=%0d last=%0b (exp 0x%h/%0d/%0b)",
                 n, child_addr, child_size, child_bytes, child_last,
                 exp_addr, exp_bytes, exp_last);
        errors = errors + 1;
      end else begin
        $display("PASS child[%0d]: addr=0x%h bytes=%0d last=%0b",
                 n, child_addr, child_bytes, child_last);
      end
      n = n + 1;
    end
  endtask

  initial begin
    #20 rst_n = 1'b1;
    #20;
    // Scheme 6.4 example: 0x38, len 7, size 4 (16B), INCR, coalesce.
    @(negedge clk);            // t=50
    start_addr  = 44'h38;
    start_len   = 8'd7;
    start_size  = 3'd4;
    start_burst = `CHI_RNI_AXI_BURST_INCR;
    coalesce    = 1'b1;
    device      = 1'b0;
    start_valid = 1'b1;
    @(negedge clk);            // t=60: start accepted at t=55, child[0] live
    start_valid = 1'b0;

    n = 0;
    check(44'h38, 8,  1'b0);
    @(negedge clk); check(44'h40, 64, 1'b0);
    @(negedge clk); check(44'h80, 32, 1'b0);
    @(negedge clk); check(44'hA0, 16, 1'b0);
    @(negedge clk); check(44'hB0, 8,  1'b1);

    #20;
    if (errors == 0) $display("TB_SEGBURST: PASS");
    else             $display("TB_SEGBURST: FAIL (%0d errors)", errors);
    $finish;
  end
endmodule
