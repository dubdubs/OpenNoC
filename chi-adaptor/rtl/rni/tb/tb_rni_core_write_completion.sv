`timescale 1ns / 1ps

module tb_rni_core_write_completion;

  localparam int unsigned NidWidth = 7;
  localparam int unsigned TxnidWidth = 12;
  localparam int unsigned RspFlitWidth = 73;
  localparam int unsigned DatFlitWidth = 406;
  localparam int unsigned RspSrcIdLsb = NidWidth + 4;
  localparam int unsigned RspTxnidLsb = 2 * NidWidth + 4;
  localparam int unsigned RspOpcodeLsb = 2 * NidWidth + 16;
  localparam int unsigned RspRespErrLsb = 2 * NidWidth + 21;
  localparam int unsigned RspDbidLsb = 2 * NidWidth + 32;
  localparam int unsigned DatTxnidLsb = 2 * NidWidth + 4;
  localparam int unsigned DatOpcodeLsb = 3 * NidWidth + 16;
  localparam int unsigned DatDbidLsb = 3 * NidWidth + 32;
  localparam int unsigned DatBeLsb = 3 * NidWidth + 256 / 32 +
                                     256 / 128 + 51;
  localparam int unsigned DatDataLsb = DatBeLsb + 32;

  logic clk;
  logic rst;
  logic write_cmd_valid;
  logic [3:0] write_cmd_id;
  logic [63:0] write_cmd_addr;
  logic [7:0] write_cmd_len;
  logic [2:0] write_cmd_size;
  logic [1:0] write_cmd_burst;
  logic write_cmd_ready;
  logic write_data_valid;
  logic [31:0] write_data;
  logic [3:0] write_strb;
  logic write_last;
  logic write_data_ready;
  logic write_rsp_valid;
  logic [3:0] write_rsp_id;
  logic [1:0] write_rsp_code;
  logic write_rsp_ready;
  logic txreq_valid;
  logic [130:0] txreq_payload;
  logic txreq_ready;
  logic txdat_valid;
  logic [DatFlitWidth-1:0] txdat_payload;
  logic txdat_ready;
  logic rxrsp_valid;
  logic [RspFlitWidth-1:0] rxrsp_payload;
  logic rxrsp_ready;

  rni_core dut (
      .clk(clk), .rst(rst),
      .write_cmd_valid_i(write_cmd_valid), .write_cmd_id_i(write_cmd_id),
      .write_cmd_addr_i(write_cmd_addr), .write_cmd_len_i(write_cmd_len),
      .write_cmd_size_i(write_cmd_size), .write_cmd_burst_i(write_cmd_burst),
      .write_cmd_ready_o(write_cmd_ready),
      .write_data_valid_i(write_data_valid), .write_data_i(write_data),
      .write_strb_i(write_strb), .write_last_i(write_last),
      .write_data_ready_o(write_data_ready),
      .read_cmd_valid_i(1'b0), .read_cmd_id_i('0), .read_cmd_addr_i('0),
      .read_cmd_len_i('0), .read_cmd_size_i('0), .read_cmd_burst_i('0),
      .read_cmd_ready_o(), .write_rsp_valid_o(write_rsp_valid),
      .write_rsp_id_o(write_rsp_id), .write_rsp_code_o(write_rsp_code),
      .write_rsp_ready_i(write_rsp_ready), .read_rsp_valid_o(),
      .read_rsp_id_o(), .read_rsp_data_o(), .read_rsp_code_o(),
      .read_rsp_last_o(), .read_rsp_ready_i(1'b1),
      .policy_lookup_valid_o(), .policy_lookup_addr_o(),
      .policy_lookup_hit_i(1'b1), .policy_region_type_i(2'b01),
      .policy_target_nid_i(7'h2), .policy_ns_i(1'b1),
      .policy_order_i(2'b10), .policy_memattr_i(4'h9),
      .policy_epoch_i(8'h33), .policy_quiesce_req_i(1'b0),
      .policy_drain_done_o(), .txreq_valid_o(txreq_valid),
      .txreq_payload_o(txreq_payload), .txreq_ready_i(txreq_ready),
      .txdat_valid_o(txdat_valid), .txdat_payload_o(txdat_payload),
      .txdat_ready_i(txdat_ready), .txrsp_valid_o(), .txrsp_payload_o(),
      .txrsp_ready_i(1'b1), .rxrsp_valid_i(rxrsp_valid),
      .rxrsp_payload_i(rxrsp_payload), .rxrsp_ready_o(rxrsp_ready),
      .rxdat_valid_i(1'b0), .rxdat_payload_i('0), .rxdat_ready_o()
  );

  always #5 clk = ~clk;

  task automatic Check(input logic condition, input string message);
    if (condition !== 1'b1) begin
      $fatal(1, "CHECK FAILED: %s", message);
    end
  endtask

  task automatic DriveRsp(
      input logic [4:0] opcode,
      input logic [11:0] txnid,
      input logic [11:0] dbid
  );
    rxrsp_payload = '0;
    rxrsp_payload[RspSrcIdLsb +: NidWidth] = 7'h2;
    rxrsp_payload[RspTxnidLsb +: TxnidWidth] = txnid;
    rxrsp_payload[RspOpcodeLsb +: 5] = opcode;
    rxrsp_payload[RspRespErrLsb +: 2] = 2'b00;
    rxrsp_payload[RspDbidLsb +: TxnidWidth] = dbid;
    rxrsp_valid = 1'b1;
    #1;
    Check(rxrsp_ready, "core must consume write RXRSP at boundary");
    @(posedge clk);
    rxrsp_valid = 1'b0;
    rxrsp_payload = '0;
    #1;
  endtask

  initial begin
    clk = 1'b0;
    rst = 1'b1;
    write_cmd_valid = 1'b0;
    write_cmd_id = '0;
    write_cmd_addr = '0;
    write_cmd_len = '0;
    write_cmd_size = '0;
    write_cmd_burst = '0;
    write_data_valid = 1'b0;
    write_data = '0;
    write_strb = '0;
    write_last = 1'b0;
    write_rsp_ready = 1'b0;
    txreq_ready = 1'b0;
    txdat_ready = 1'b0;
    rxrsp_valid = 1'b0;
    rxrsp_payload = '0;

    repeat (2) @(posedge clk);
    rst = 1'b0;
    @(negedge clk);

    write_cmd_valid = 1'b1;
    write_data_valid = 1'b1;
    write_cmd_id = 4'hc;
    write_cmd_addr = 64'h0000_0000_9000_0000;
    write_cmd_len = 8'h00;
    write_cmd_size = 3'd2;
    write_cmd_burst = 2'b01;
    write_data = 32'hfeed_cafe;
    write_strb = 4'b1111;
    write_last = 1'b1;
    #1;
    Check(write_cmd_ready && write_data_ready,
          "write command/data must be admitted atomically");
    @(posedge clk);
    write_cmd_valid = 1'b0;
    write_data_valid = 1'b0;
    #1;

    Check(txreq_valid, "write child must present TXREQ");
    Check(txreq_payload[50 +: 7] == 7'h1c,
          "TXREQ must be WriteNoSnpPtl");
    txreq_ready = 1'b1;
    @(posedge clk);
    txreq_ready = 1'b0;
    #1;
    Check(!txreq_valid, "write TXREQ must drop after handshake");

    DriveRsp(5'h06, 12'h000, 12'h055);
    Check(txdat_valid, "DBIDResp must enable write DAT");
    Check(txdat_payload[DatOpcodeLsb +: 4] == 4'h3,
          "TXDAT must be NonCopyBackWrData");
    Check(txdat_payload[DatTxnidLsb +: TxnidWidth] == 12'h055,
          "TXDAT TxnID must use DBID");
    Check(txdat_payload[DatDbidLsb +: TxnidWidth] == 12'h000,
          "TXDAT DBID route must carry original TxnID");
    Check(txdat_payload[DatBeLsb +: 4] == 4'hf,
          "TXDAT BE mismatch");
    Check(txdat_payload[DatDataLsb +: 32] == 32'hfeed_cafe,
          "TXDAT DATA mismatch");
    txdat_ready = 1'b1;
    @(posedge clk);
    txdat_ready = 1'b0;
    #1;
    Check(!write_rsp_valid, "B must wait for final Comp");

    DriveRsp(5'h04, 12'h000, 12'h000);
    Check(write_rsp_valid, "Comp must produce AXI B");
    Check(write_rsp_id == 4'hc, "BID mismatch");
    Check(write_rsp_code == 2'b00, "BRESP must be OKAY");
    repeat (2) @(posedge clk);
    #1;
    Check(write_rsp_valid && write_rsp_id == 4'hc,
          "B payload must hold under backpressure");
    write_rsp_ready = 1'b1;
    @(posedge clk);
    write_rsp_ready = 1'b0;
    #1;
    Check(!write_rsp_valid, "B handshake must release holding register");

    $display("PASS: rni_core WriteNoSnpPtl DBID/DAT/Comp/B completion");
    $finish;
  end

endmodule
