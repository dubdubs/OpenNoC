`timescale 1ns / 1ps

module tb_rni_core_read_completion;

  localparam int unsigned NidWidth = 7;
  localparam int unsigned TxnidWidth = 12;
  localparam int unsigned DatFlitWidth = 406;
  localparam int unsigned DatTxnidLsb = 2 * NidWidth + 4;
  localparam int unsigned DatOpcodeLsb = 3 * NidWidth + 16;
  localparam int unsigned DatRespErrLsb = 3 * NidWidth + 20;
  localparam int unsigned DatDataidLsb = 3 * NidWidth + 46;
  localparam int unsigned DatBeLsb = 3 * NidWidth + 256 / 32 +
                                     256 / 128 + 51;
  localparam int unsigned DatDataLsb = DatBeLsb + 32;

  logic clk;
  logic rst;
  logic read_cmd_valid;
  logic [3:0] read_cmd_id;
  logic [63:0] read_cmd_addr;
  logic [7:0] read_cmd_len;
  logic [2:0] read_cmd_size;
  logic [1:0] read_cmd_burst;
  logic read_cmd_ready;
  logic read_rsp_valid;
  logic [3:0] read_rsp_id;
  logic [31:0] read_rsp_data;
  logic [1:0] read_rsp_code;
  logic read_rsp_last;
  logic read_rsp_ready;
  logic policy_lookup_valid;
  logic [63:0] policy_lookup_addr;
  logic txreq_valid;
  logic [130:0] txreq_payload;
  logic txreq_ready;
  logic rxdat_valid;
  logic [DatFlitWidth-1:0] rxdat_payload;
  logic rxdat_ready;

  rni_core dut (
      .clk(clk), .rst(rst),
      .write_cmd_valid_i(1'b0), .write_cmd_id_i('0), .write_cmd_addr_i('0),
      .write_cmd_len_i('0), .write_cmd_size_i('0), .write_cmd_burst_i('0),
      .write_cmd_ready_o(), .write_data_valid_i(1'b0), .write_data_i('0),
      .write_strb_i('0), .write_last_i(1'b0), .write_data_ready_o(),
      .read_cmd_valid_i(read_cmd_valid), .read_cmd_id_i(read_cmd_id),
      .read_cmd_addr_i(read_cmd_addr), .read_cmd_len_i(read_cmd_len),
      .read_cmd_size_i(read_cmd_size), .read_cmd_burst_i(read_cmd_burst),
      .read_cmd_ready_o(read_cmd_ready), .write_rsp_valid_o(),
      .write_rsp_id_o(), .write_rsp_code_o(), .write_rsp_ready_i(1'b1),
      .read_rsp_valid_o(read_rsp_valid), .read_rsp_id_o(read_rsp_id),
      .read_rsp_data_o(read_rsp_data), .read_rsp_code_o(read_rsp_code),
      .read_rsp_last_o(read_rsp_last), .read_rsp_ready_i(read_rsp_ready),
      .policy_lookup_valid_o(policy_lookup_valid),
      .policy_lookup_addr_o(policy_lookup_addr), .policy_lookup_hit_i(1'b1),
      .policy_region_type_i(2'b01), .policy_target_nid_i(7'h2),
      .policy_ns_i(1'b1), .policy_order_i(2'b10),
      .policy_memattr_i(4'h9), .policy_epoch_i(8'h22),
      .policy_quiesce_req_i(1'b0), .policy_drain_done_o(),
      .txreq_valid_o(txreq_valid), .txreq_payload_o(txreq_payload),
      .txreq_ready_i(txreq_ready), .txdat_valid_o(), .txdat_payload_o(),
      .txdat_ready_i(1'b1), .txrsp_valid_o(), .txrsp_payload_o(),
      .txrsp_ready_i(1'b1), .rxrsp_valid_i(1'b0), .rxrsp_payload_i('0),
      .rxrsp_ready_o(), .rxdat_valid_i(rxdat_valid),
      .rxdat_payload_i(rxdat_payload), .rxdat_ready_o(rxdat_ready)
  );

  always #5 clk = ~clk;

  task automatic Check(input logic condition, input string message);
    if (condition !== 1'b1) begin
      $fatal(1, "CHECK FAILED: %s", message);
    end
  endtask

  task automatic DriveCompData(
      input logic [1:0] dataid,
      input logic [31:0] first_word
  );
    rxdat_payload = '0;
    rxdat_payload[DatTxnidLsb +: TxnidWidth] = 12'h000;
    rxdat_payload[DatOpcodeLsb +: 4] = 4'h4;
    rxdat_payload[DatRespErrLsb +: 2] = 2'b00;
    rxdat_payload[DatDataidLsb +: 2] = dataid;
    rxdat_payload[DatBeLsb +: 32] = 32'hffff_ffff;
    rxdat_payload[DatDataLsb +: 32] = first_word;
    rxdat_valid = 1'b1;
    @(posedge clk);
    #1;
    Check(rxdat_ready, "core must consume RXDAT at its boundary");
    rxdat_valid = 1'b0;
    rxdat_payload = '0;
  endtask

  initial begin
    clk = 1'b0;
    rst = 1'b1;
    read_cmd_valid = 1'b0;
    read_cmd_id = '0;
    read_cmd_addr = '0;
    read_cmd_len = '0;
    read_cmd_size = '0;
    read_cmd_burst = '0;
    read_rsp_ready = 1'b0;
    txreq_ready = 1'b0;
    rxdat_valid = 1'b0;
    rxdat_payload = '0;

    repeat (2) @(posedge clk);
    rst = 1'b0;
    @(negedge clk);

    read_cmd_valid = 1'b1;
    read_cmd_id = 4'h9;
    read_cmd_addr = 64'h0000_0000_8000_0000;
    read_cmd_len = 8'h00;
    read_cmd_size = 3'd2;
    read_cmd_burst = 2'b01;
    #1;
    Check(read_cmd_ready, "first read must be admitted");
    Check(policy_lookup_valid, "ordinary read must request policy lookup");
    @(posedge clk);
    read_cmd_valid = 1'b0;
    #1;

    Check(txreq_valid, "allocated read child must present TXREQ");
    Check(txreq_payload[50 +: 7] == 7'h04, "TXREQ must be ReadNoSnp");
    txreq_ready = 1'b1;
    @(posedge clk);
    txreq_ready = 1'b0;
    #1;
    Check(!txreq_valid, "TXREQ must drop after ready handshake");

    DriveCompData(2'b00, 32'h1111_aaaa);
    #1;
    Check(!read_rsp_valid, "single DAT half must not produce AXI R");
    DriveCompData(2'b10, 32'h2222_bbbb);
    @(posedge clk);
    #1;
    Check(read_rsp_valid, "both DAT halves must produce AXI R");
    Check(read_rsp_id == 4'h9, "AXI RID mismatch");
    Check(read_rsp_data == 32'h1111_aaaa, "AXI RDATA mismatch");
    Check(read_rsp_code == 2'b00, "AXI RRESP must be OKAY");
    Check(read_rsp_last, "single-beat read must assert RLAST");

    repeat (2) @(posedge clk);
    #1;
    Check(read_rsp_valid && read_rsp_data == 32'h1111_aaaa,
          "R payload must remain stable under backpressure");
    read_rsp_ready = 1'b1;
    @(posedge clk);
    read_rsp_ready = 1'b0;
    #1;
    Check(!read_rsp_valid, "R handshake must release response holding register");

    read_cmd_valid = 1'b1;
    read_cmd_id = 4'ha;
    read_cmd_addr = 64'h0000_0000_8000_0040;
    #1;
    Check(read_cmd_ready, "resource release must allow a second read");

    $display("PASS: rni_core ReadNoSnp TXREQ/RXDAT/R response completion");
    $finish;
  end

endmodule
