`timescale 1ns / 1ps

module tb_rni_xp_p0_link_ctl;

  logic clk;
  logic rst;
  logic core_txreq_valid;
  logic [130:0] core_txreq_payload;
  logic core_txreq_ready;
  logic core_rxdat_valid;
  logic [405:0] core_rxdat_payload;
  logic core_rxdat_ready;
  logic xp_rxreq_flitv;
  logic [130:0] xp_rxreq_flit;
  logic xp_rxreq_lcrdv;
  logic xp_txdat_flitv;
  logic [405:0] xp_txdat_flit;
  logic xp_txdat_lcrdv;
  logic txlinkactivereq;
  logic txlinkactiveack;
  logic rxlinkactivereq;
  logic rxlinkactiveack;

  rni_xp_p0_link_ctl dut (
      .clk(clk), .rst(rst),
      .core_txreq_valid_i(core_txreq_valid),
      .core_txreq_payload_i(core_txreq_payload),
      .core_txreq_ready_o(core_txreq_ready),
      .core_txdat_valid_i(1'b0), .core_txdat_payload_i('0),
      .core_txdat_ready_o(),
      .core_txrsp_valid_i(1'b0), .core_txrsp_payload_i('0),
      .core_txrsp_ready_o(),
      .core_rxrsp_valid_o(), .core_rxrsp_payload_o(),
      .core_rxrsp_ready_i(1'b1),
      .core_rxdat_valid_o(core_rxdat_valid),
      .core_rxdat_payload_o(core_rxdat_payload),
      .core_rxdat_ready_i(core_rxdat_ready),
      .csr_rxreq_valid_o(), .csr_rxreq_payload_o(),
      .csr_rxreq_ready_i(1'b1),
      .csr_rxdat_valid_o(), .csr_rxdat_payload_o(),
      .csr_rxdat_ready_i(1'b1),
      .csr_txrsp_valid_i(1'b0), .csr_txrsp_payload_i('0),
      .csr_txrsp_ready_o(),
      .csr_txdat_valid_i(1'b0), .csr_txdat_payload_i('0),
      .csr_txdat_ready_o(),
      .xp_rxreq_flitv_o(xp_rxreq_flitv),
      .xp_rxreq_flit_o(xp_rxreq_flit),
      .xp_rxreq_lcrdv_i(xp_rxreq_lcrdv),
      .xp_rxdat_flitv_o(), .xp_rxdat_flit_o(),
      .xp_rxdat_lcrdv_i(1'b0),
      .xp_rxrsp_flitv_o(), .xp_rxrsp_flit_o(),
      .xp_rxrsp_lcrdv_i(1'b0),
      .xp_txreq_flitv_i(1'b0), .xp_txreq_flit_i('0),
      .xp_txreq_lcrdv_o(),
      .xp_txrsp_flitv_i(1'b0), .xp_txrsp_flit_i('0),
      .xp_txrsp_lcrdv_o(),
      .xp_txdat_flitv_i(xp_txdat_flitv),
      .xp_txdat_flit_i(xp_txdat_flit),
      .xp_txdat_lcrdv_o(xp_txdat_lcrdv),
      .rni_txlinkactivereq_o(txlinkactivereq),
      .rni_txlinkactiveack_i(txlinkactiveack),
      .rni_rxlinkactivereq_i(rxlinkactivereq),
      .rni_rxlinkactiveack_o(rxlinkactiveack)
  );

  always #5 clk = ~clk;

  task automatic Check(input logic condition, input string message);
    if (condition !== 1'b1) begin
      $fatal(1, "CHECK FAILED: %s", message);
    end
  endtask

  initial begin
    clk = 1'b0;
    rst = 1'b1;
    core_txreq_valid = 1'b0;
    core_txreq_payload = '0;
    core_rxdat_ready = 1'b0;
    xp_rxreq_lcrdv = 1'b0;
    xp_txdat_flitv = 1'b0;
    xp_txdat_flit = '0;
    txlinkactiveack = 1'b0;
    rxlinkactivereq = 1'b0;

    repeat (2) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);
    #1;
    Check(txlinkactivereq, "RNI must request TX link activation");
    rxlinkactivereq = 1'b1;
    @(posedge clk);
    #1;
    Check(rxlinkactiveack, "RNI must acknowledge peer RX link request");
    txlinkactiveack = 1'b1;
    @(posedge clk);
    #1;

    core_txreq_valid = 1'b1;
    core_txreq_payload = 131'h1234;
    #1;
    Check(!core_txreq_ready && !xp_rxreq_flitv,
          "TXREQ must wait for returned L-credit");
    xp_rxreq_lcrdv = 1'b1;
    @(posedge clk);
    xp_rxreq_lcrdv = 1'b0;
    #1;
    Check(core_txreq_ready && xp_rxreq_flitv &&
          xp_rxreq_flit == 131'h1234,
          "TXREQ must send when link is active and credit is available");
    @(posedge clk);
    core_txreq_valid = 1'b0;
    #1;
    Check(!xp_rxreq_flitv, "TXREQ credit must be consumed by the send");

    xp_txdat_flit = 406'h55aa;
    xp_txdat_flitv = 1'b1;
    core_rxdat_ready = 1'b0;
    #1;
    Check(xp_txdat_lcrdv, "RXDAT must return L-credit on accept cycle");
    @(posedge clk);
    xp_txdat_flitv = 1'b0;
    #1;
    Check(core_rxdat_valid &&
          core_rxdat_payload == 406'h55aa,
          "RXDAT must capture into holding register");
    repeat (2) @(posedge clk);
    #1;
    Check(core_rxdat_valid && core_rxdat_payload == 406'h55aa,
          "RXDAT payload must hold under core backpressure");
    core_rxdat_ready = 1'b1;
    @(posedge clk);
    core_rxdat_ready = 1'b0;
    #1;
    Check(!core_rxdat_valid, "RXDAT holding register must release on ready");

    $display("PASS: rni_xp_p0_link_ctl LinkActive, credit, and RX holding");
    $finish;
  end

endmodule
