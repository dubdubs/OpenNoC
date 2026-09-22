`timescale 1ns/1ps
`default_nettype none

`define CHECK(condition) \
  if (!(condition)) begin \
    $fatal(1, "CHECK failed: %s", `"condition`"); \
  end

module tb_axi2chi_chi_transport_leaf;
  localparam int unsigned FlitWidth = 16;
  localparam int unsigned Depth = 2;
  localparam int unsigned MaxCredits = 2;

  logic clk = 1'b0;
  logic rst = 1'b1;

  logic credit_return_i;
  logic send_fire_i;
  logic credit_available_o;
  logic [$clog2(MaxCredits + 1)-1:0] credit_count_o;

  logic producer_valid_i;
  logic [FlitWidth-1:0] producer_flit_i;
  logic producer_ready_o;
  logic tx_credit_available_i;
  logic chi_flitv_o;
  logic [FlitWidth-1:0] chi_flit_o;
  logic tx_send_fire_o;

  logic chi_flitv_i;
  logic [FlitWidth-1:0] chi_flit_i;
  logic chi_lcrdv_o;
  logic core_valid_o;
  logic [FlitWidth-1:0] core_flit_o;
  logic core_ready_i;

  axi2chi_chi_credit #(
    .MaxCredits(MaxCredits)
  ) credit_dut (
    .clk(clk),
    .rst(rst),
    .credit_return_i(credit_return_i),
    .send_fire_i(send_fire_i),
    .credit_available_o(credit_available_o),
    .credit_count_o(credit_count_o)
  );

  axi2chi_chi_txflit #(
    .FlitWidth(FlitWidth),
    .Depth(Depth)
  ) tx_dut (
    .clk(clk),
    .rst(rst),
    .producer_valid_i(producer_valid_i),
    .producer_flit_i(producer_flit_i),
    .producer_ready_o(producer_ready_o),
    .credit_available_i(tx_credit_available_i),
    .chi_flitv_o(chi_flitv_o),
    .chi_flit_o(chi_flit_o),
    .send_fire_o(tx_send_fire_o)
  );

  axi2chi_chi_rxflit #(
    .FlitWidth(FlitWidth),
    .Depth(Depth)
  ) rx_dut (
    .clk(clk),
    .rst(rst),
    .chi_flitv_i(chi_flitv_i),
    .chi_flit_i(chi_flit_i),
    .chi_lcrdv_o(chi_lcrdv_o),
    .core_valid_o(core_valid_o),
    .core_flit_o(core_flit_o),
    .core_ready_i(core_ready_i)
  );

  always #5 clk = ~clk;

  initial begin
    credit_return_i = 1'b0;
    send_fire_i = 1'b0;
    producer_valid_i = 1'b0;
    producer_flit_i = '0;
    tx_credit_available_i = 1'b0;
    chi_flitv_i = 1'b0;
    chi_flit_i = '0;
    core_ready_i = 1'b0;

    @(negedge clk);
    rst = 1'b0;
    #1;
    `CHECK(credit_available_o);
    `CHECK(credit_count_o == 2);
    `CHECK(producer_ready_o);
    `CHECK(!chi_flitv_o);
    `CHECK(chi_lcrdv_o);
    `CHECK(!core_valid_o);

    send_fire_i = 1'b1;
    @(posedge clk);
    @(negedge clk);
    send_fire_i = 1'b0;
    #1;
    `CHECK(credit_count_o == 1);
    credit_return_i = 1'b1;
    @(posedge clk);
    @(negedge clk);
    credit_return_i = 1'b0;
    #1;
    `CHECK(credit_count_o == 2);

    producer_valid_i = 1'b1;
    producer_flit_i = 16'ha001;
    tx_credit_available_i = 1'b0;
    @(posedge clk);
    @(negedge clk);
    producer_flit_i = 16'ha002;
    @(posedge clk);
    @(negedge clk);
    #1;
    `CHECK(!producer_ready_o);
    `CHECK(!chi_flitv_o);

    producer_valid_i = 1'b0;
    tx_credit_available_i = 1'b1;
    #1;
    `CHECK(chi_flitv_o);
    `CHECK(chi_flit_o == 16'ha001);
    @(posedge clk);
    @(negedge clk);
    #1;
    `CHECK(chi_flitv_o);
    `CHECK(chi_flit_o == 16'ha002);
    @(posedge clk);
    @(negedge clk);
    #1;
    `CHECK(!chi_flitv_o);

    chi_flitv_i = 1'b1;
    chi_flit_i = 16'hb001;
    @(posedge clk);
    @(negedge clk);
    chi_flit_i = 16'hb002;
    @(posedge clk);
    @(negedge clk);
    #1;
    `CHECK(!chi_lcrdv_o);
    `CHECK(core_valid_o);
    `CHECK(core_flit_o == 16'hb001);

    chi_flitv_i = 1'b0;
    core_ready_i = 1'b1;
    @(posedge clk);
    @(negedge clk);
    #1;
    `CHECK(core_valid_o);
    `CHECK(core_flit_o == 16'hb002);
    @(posedge clk);
    @(negedge clk);
    core_ready_i = 1'b0;
    #1;
    `CHECK(!core_valid_o);
    `CHECK(chi_lcrdv_o);

    $display("PASS: CHI transport leaf credit and FIFO flow");
    $finish;
  end
endmodule

`default_nettype wire

`undef CHECK
