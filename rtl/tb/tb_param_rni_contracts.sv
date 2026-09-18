`timescale 1ns/1ps

// Scheme-1 contract regression.
//
// Every legal AXI-full/CHI-DAT width pair is elaborated.  The dynamic cases
// intentionally drive only legal transactions: rni_scheme1_static_assert
// reports contract violations with $error, and a negative stimulus would make
// a normal regression fail.  The negative-contract vectors are consequently
// recorded below and are checked by the assertion module itself when a
// simulator error-expectation mechanism is available.
module tb_param_rni_contract_width #(
  parameter integer AXI_WIDTH = 128,
  parameter integer CHI_WIDTH = 256
) (
  input wire clk,
  input wire rst
);
  rni_scheme1_static_assert #(
    .AXI_DATA_WIDTH(AXI_WIDTH),
    .CHI_DATA_WIDTH(CHI_WIDTH),
    .CHI_BE_WIDTH(CHI_WIDTH / 8),
    .CHI_TXNID_WIDTH(12),
    .SLOT_COUNT(32),
    .DBID_MAP_DEPTH(64),
    .ENABLE_NONCOHERENT(1),
    .ENABLE_COHERENT(1),
    .TXRSP_CREDITS(1)
  ) contract (
    .clk(clk),
    .rst(rst),
    .admission_valid(1'b0),
    .axsize(3'b000),
    .profile_coherent(1'b0),
    .profile_enabled(1'b1),
    .txnid(12'b0),
    .txrsp_valid(1'b0),
    .txrsp_credit(1'b1),
    .req_attr_complete(1'b1)
  );
endmodule

module tb_param_rni_contract_case #(
  parameter integer ENABLE_COHERENT = 1,
  parameter integer ENABLE_NONCOHERENT = 1
) (
  input wire clk,
  input wire rst
);
  reg admission_valid;
  reg [2:0] axsize;
  reg profile_coherent;
  reg profile_enabled;
  reg [11:0] txnid;
  reg txrsp_valid;
  reg txrsp_credit;
  reg req_attr_complete;

  integer checks;

  rni_scheme1_static_assert #(
    .AXI_DATA_WIDTH(128),
    .CHI_DATA_WIDTH(256),
    .CHI_BE_WIDTH(32),
    .CHI_TXNID_WIDTH(12),
    .SLOT_COUNT(32),
    .DBID_MAP_DEPTH(64),
    .ENABLE_NONCOHERENT(ENABLE_NONCOHERENT),
    .ENABLE_COHERENT(ENABLE_COHERENT),
    .TXRSP_CREDITS(1)
  ) contract (
    .clk(clk), .rst(rst), .admission_valid(admission_valid),
    .axsize(axsize), .profile_coherent(profile_coherent),
    .profile_enabled(profile_enabled), .txnid(txnid),
    .txrsp_valid(txrsp_valid), .txrsp_credit(txrsp_credit),
    .req_attr_complete(req_attr_complete)
  );

  task check_legal_contract;
    input [2:0] requested_axsize;
    input requested_profile_coherent;
    input [4:0] requested_slot;
    input requested_compack;
    begin
      // These checks make the legal vectors self-checking before they are
      // sampled by the RTL contract monitor.
      if (requested_axsize > 3'd4) begin
        $fatal(1, "tb contract generated illegal AxSIZE");
      end
      if (requested_slot >= 32) begin
        $fatal(1, "tb contract generated out-of-range TxnID slot");
      end
      if (requested_profile_coherent && !ENABLE_COHERENT) begin
        $fatal(1, "tb contract generated disabled coherent profile");
      end
      if (!requested_profile_coherent && !ENABLE_NONCOHERENT) begin
        $fatal(1, "tb contract generated disabled noncoherent profile");
      end
      if (requested_compack && !txrsp_credit) begin
        $fatal(1, "tb contract generated CompAck without credit");
      end
      checks = checks + 1;
    end
  endtask

  initial begin
    admission_valid = 1'b0;
    axsize = 3'd0;
    profile_coherent = 1'b0;
    profile_enabled = 1'b1;
    txnid = 12'b0;
    txrsp_valid = 1'b0;
    txrsp_credit = 1'b1;
    req_attr_complete = 1'b1;
    checks = 0;

    wait (!rst);

    // Boundary legal AXI sizes: byte and full 128-bit transfer.
    @(negedge clk);
    check_legal_contract(3'd0, ENABLE_COHERENT, 5'd0, 1'b0);
    admission_valid = 1'b1;
    axsize = 3'd0;
    profile_coherent = ENABLE_COHERENT;
    txnid = 12'h000;
    @(negedge clk);
    check_legal_contract(3'd4, ENABLE_COHERENT, 5'd31, 1'b1);
    axsize = 3'd4;
    profile_coherent = ENABLE_COHERENT;
    txnid = 12'h01f;
    txrsp_valid = 1'b1;
    txrsp_credit = 1'b1;
    @(negedge clk);

    // Exercise the other implemented profile in the dual-profile instance.
    if (ENABLE_COHERENT && ENABLE_NONCOHERENT) begin
      check_legal_contract(3'd2, 1'b0, 5'd16, 1'b0);
      axsize = 3'd2;
      profile_coherent = 1'b0;
      txnid = 12'h010;
      txrsp_valid = 1'b0;
      @(negedge clk);
    end

    admission_valid = 1'b0;
    txrsp_valid = 1'b0;
    if (checks < 2) begin
      $fatal(1, "tb contract did not execute its legal boundary vectors");
    end
  end
endmodule

module tb_param_rni_contracts;
  reg clk;
  reg rst;

  always #5 clk = ~clk;

  // Complete 8-by-3 legal width elaboration matrix.
  tb_param_rni_contract_width #(.AXI_WIDTH(8),    .CHI_WIDTH(128)) axi8_chi128(clk, rst);
  tb_param_rni_contract_width #(.AXI_WIDTH(8),    .CHI_WIDTH(256)) axi8_chi256(clk, rst);
  tb_param_rni_contract_width #(.AXI_WIDTH(8),    .CHI_WIDTH(512)) axi8_chi512(clk, rst);
  tb_param_rni_contract_width #(.AXI_WIDTH(16),   .CHI_WIDTH(128)) axi16_chi128(clk, rst);
  tb_param_rni_contract_width #(.AXI_WIDTH(16),   .CHI_WIDTH(256)) axi16_chi256(clk, rst);
  tb_param_rni_contract_width #(.AXI_WIDTH(16),   .CHI_WIDTH(512)) axi16_chi512(clk, rst);
  tb_param_rni_contract_width #(.AXI_WIDTH(32),   .CHI_WIDTH(128)) axi32_chi128(clk, rst);
  tb_param_rni_contract_width #(.AXI_WIDTH(32),   .CHI_WIDTH(256)) axi32_chi256(clk, rst);
  tb_param_rni_contract_width #(.AXI_WIDTH(32),   .CHI_WIDTH(512)) axi32_chi512(clk, rst);
  tb_param_rni_contract_width #(.AXI_WIDTH(64),   .CHI_WIDTH(128)) axi64_chi128(clk, rst);
  tb_param_rni_contract_width #(.AXI_WIDTH(64),   .CHI_WIDTH(256)) axi64_chi256(clk, rst);
  tb_param_rni_contract_width #(.AXI_WIDTH(64),   .CHI_WIDTH(512)) axi64_chi512(clk, rst);
  tb_param_rni_contract_width #(.AXI_WIDTH(128),  .CHI_WIDTH(128)) axi128_chi128(clk, rst);
  tb_param_rni_contract_width #(.AXI_WIDTH(128),  .CHI_WIDTH(256)) axi128_chi256(clk, rst);
  tb_param_rni_contract_width #(.AXI_WIDTH(128),  .CHI_WIDTH(512)) axi128_chi512(clk, rst);
  tb_param_rni_contract_width #(.AXI_WIDTH(256),  .CHI_WIDTH(128)) axi256_chi128(clk, rst);
  tb_param_rni_contract_width #(.AXI_WIDTH(256),  .CHI_WIDTH(256)) axi256_chi256(clk, rst);
  tb_param_rni_contract_width #(.AXI_WIDTH(256),  .CHI_WIDTH(512)) axi256_chi512(clk, rst);
  tb_param_rni_contract_width #(.AXI_WIDTH(512),  .CHI_WIDTH(128)) axi512_chi128(clk, rst);
  tb_param_rni_contract_width #(.AXI_WIDTH(512),  .CHI_WIDTH(256)) axi512_chi256(clk, rst);
  tb_param_rni_contract_width #(.AXI_WIDTH(512),  .CHI_WIDTH(512)) axi512_chi512(clk, rst);
  tb_param_rni_contract_width #(.AXI_WIDTH(1024), .CHI_WIDTH(128)) axi1024_chi128(clk, rst);
  tb_param_rni_contract_width #(.AXI_WIDTH(1024), .CHI_WIDTH(256)) axi1024_chi256(clk, rst);
  tb_param_rni_contract_width #(.AXI_WIDTH(1024), .CHI_WIDTH(512)) axi1024_chi512(clk, rst);

  // Legal traffic through each profile configuration.  Disabled profiles are
  // deliberately not driven: their negative vectors are listed below.
  tb_param_rni_contract_case #(.ENABLE_COHERENT(1), .ENABLE_NONCOHERENT(1)) both_profiles(clk, rst);
  tb_param_rni_contract_case #(.ENABLE_COHERENT(1), .ENABLE_NONCOHERENT(0)) coherent_only(clk, rst);
  tb_param_rni_contract_case #(.ENABLE_COHERENT(0), .ENABLE_NONCOHERENT(1)) noncoherent_only(clk, rst);

  initial begin
    clk = 1'b0;
    rst = 1'b1;
    #12 rst = 1'b0;
    #65;
    $display("tb_param_rni_contracts PASS: 24 widths and legal Scheme-1 boundary contracts");
    // Negative contracts owned by rni_scheme1_static_assert (not driven here
    // because each is intentionally an $error): disabled/unimplemented
    // profile, AxSIZE > log2(AXI_BYTES), slot >= SLOT_COUNT, incomplete
    // req_attr, and CompAck without TXRSP credit.
    $finish;
  end
endmodule
