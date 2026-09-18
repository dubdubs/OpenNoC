`timescale 1ns/1ps

// Credit-channel regression for CHI TX channels.  Exercises initial credit
// acquisition, credit exhaustion, simultaneous return/send, and reset.
module tb_param_rni_lcrd;
  logic clk;
  logic rst;
  logic credit_return;
  logic flit_send;
  wire credit_full;
  wire credit_available;
  integer failures;

  rni_lcrd_hdlr #(
      .LCRD_INIT_CNT_VAL(2),
      .LCRD_MAX_CNT_VAL(2)
  ) dut (
      .clk(clk),
      .rst(rst),
      .lcrd_inc(credit_return),
      .lcrd_dec(flit_send),
      .lcrd_full(credit_full),
      .lcrd_avail(credit_available)
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

  task automatic drive(input logic increment, input logic decrement);
    begin
      @(negedge clk);
      credit_return = increment;
      flit_send = decrement;
      @(posedge clk);
      @(negedge clk);
      credit_return = 1'b0;
      flit_send = 1'b0;
    end
  endtask

  initial begin
    clk = 1'b0;
    rst = 1'b1;
    credit_return = 1'b0;
    flit_send = 1'b0;
    failures = 0;

    repeat (2) @(posedge clk);
    rst = 1'b0;
    // The handler initializes on the first active clock after reset.
    repeat (2) @(posedge clk);
    @(negedge clk);
    check_value(credit_available, 1'b1, "initial credits must be available");
    check_value(credit_full, 1'b1, "initial credits must fill the channel");

    drive(1'b0, 1'b1);
    @(negedge clk);
    check_value(credit_available, 1'b1, "one remaining credit must be usable");
    check_value(credit_full, 1'b0, "send must consume a credit");
    drive(1'b0, 1'b1);
    @(negedge clk);
    check_value(credit_available, 1'b0, "zero credits must backpressure TX");

    // A returned credit permits a flit in the same cycle and preserves the
    // empty count, which models a pipelined credit return.
    drive(1'b1, 1'b1);
    @(negedge clk);
    check_value(credit_available, 1'b0,
                "simultaneous return/send must preserve empty count");
    drive(1'b1, 1'b0);
    @(negedge clk);
    check_value(credit_available, 1'b1, "returned credit must unblock TX");

    rst = 1'b1;
    @(posedge clk);
    @(negedge clk);
    check_value(credit_available, 1'b0, "reset/link-down must remove credits");
    rst = 1'b0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    check_value(credit_available, 1'b1, "reset recovery must restore credits");

    if (failures != 0) begin
      $fatal(1, "tb_param_rni_lcrd failed with %0d mismatches", failures);
    end
    $display("tb_param_rni_lcrd PASS: zero credit, return, reset");
    $finish;
  end

  initial begin
    #5000;
    $fatal(1, "tb_param_rni_lcrd timeout");
  end
endmodule
