`timescale 1ns / 1ps

module tb_rni_core_read_admission;

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
  logic read_cmd_valid;
  logic [3:0] read_cmd_id;
  logic [63:0] read_cmd_addr;
  logic [7:0] read_cmd_len;
  logic [2:0] read_cmd_size;
  logic [1:0] read_cmd_burst;
  logic read_cmd_ready;
  logic write_rsp_valid;
  logic [3:0] write_rsp_id;
  logic [1:0] write_rsp_code;
  logic write_rsp_ready;
  logic read_rsp_valid;
  logic [3:0] read_rsp_id;
  logic [31:0] read_rsp_data;
  logic [1:0] read_rsp_code;
  logic read_rsp_last;
  logic read_rsp_ready;
  logic policy_lookup_valid;
  logic [63:0] policy_lookup_addr;
  logic policy_lookup_hit;
  logic [1:0] policy_region_type;
  logic [6:0] policy_target_nid;
  logic policy_ns;
  logic [1:0] policy_order;
  logic [3:0] policy_memattr;
  logic [7:0] policy_epoch;
  logic policy_quiesce_req;
  logic policy_drain_done;
  logic txreq_valid;
  logic [130:0] txreq_payload;
  logic txreq_ready;
  logic txdat_valid;
  logic [405:0] txdat_payload;
  logic txdat_ready;
  logic txrsp_valid;
  logic [72:0] txrsp_payload;
  logic txrsp_ready;
  logic rxrsp_valid;
  logic [72:0] rxrsp_payload;
  logic rxrsp_ready;
  logic rxdat_valid;
  logic [405:0] rxdat_payload;
  logic rxdat_ready;

  rni_core dut (
      .clk(clk), .rst(rst),
      .write_cmd_valid_i(write_cmd_valid), .write_cmd_id_i(write_cmd_id),
      .write_cmd_addr_i(write_cmd_addr), .write_cmd_len_i(write_cmd_len),
      .write_cmd_size_i(write_cmd_size), .write_cmd_burst_i(write_cmd_burst),
      .write_cmd_ready_o(write_cmd_ready), .write_data_valid_i(write_data_valid),
      .write_data_i(write_data), .write_strb_i(write_strb),
      .write_last_i(write_last), .write_data_ready_o(write_data_ready),
      .read_cmd_valid_i(read_cmd_valid), .read_cmd_id_i(read_cmd_id),
      .read_cmd_addr_i(read_cmd_addr), .read_cmd_len_i(read_cmd_len),
      .read_cmd_size_i(read_cmd_size), .read_cmd_burst_i(read_cmd_burst),
      .read_cmd_ready_o(read_cmd_ready), .write_rsp_valid_o(write_rsp_valid),
      .write_rsp_id_o(write_rsp_id), .write_rsp_code_o(write_rsp_code),
      .write_rsp_ready_i(write_rsp_ready), .read_rsp_valid_o(read_rsp_valid),
      .read_rsp_id_o(read_rsp_id), .read_rsp_data_o(read_rsp_data),
      .read_rsp_code_o(read_rsp_code), .read_rsp_last_o(read_rsp_last),
      .read_rsp_ready_i(read_rsp_ready),
      .policy_lookup_valid_o(policy_lookup_valid),
      .policy_lookup_addr_o(policy_lookup_addr),
      .policy_lookup_hit_i(policy_lookup_hit),
      .policy_region_type_i(policy_region_type), .policy_epoch_i(policy_epoch),
      .policy_target_nid_i(policy_target_nid), .policy_ns_i(policy_ns),
      .policy_order_i(policy_order), .policy_memattr_i(policy_memattr),
      .policy_quiesce_req_i(policy_quiesce_req),
      .policy_drain_done_o(policy_drain_done), .txreq_valid_o(txreq_valid),
      .txreq_payload_o(txreq_payload), .txreq_ready_i(txreq_ready),
      .txdat_valid_o(txdat_valid), .txdat_payload_o(txdat_payload),
      .txdat_ready_i(txdat_ready), .txrsp_valid_o(txrsp_valid),
      .txrsp_payload_o(txrsp_payload), .txrsp_ready_i(txrsp_ready),
      .rxrsp_valid_i(rxrsp_valid), .rxrsp_payload_i(rxrsp_payload),
      .rxrsp_ready_o(rxrsp_ready), .rxdat_valid_i(rxdat_valid),
      .rxdat_payload_i(rxdat_payload), .rxdat_ready_o(rxdat_ready)
  );

  always #5 clk = ~clk;

  task automatic Check(input logic condition, input string message);
    if (condition !== 1'b1) begin
      $fatal(1, "CHECK FAILED: %s", message);
    end
  endtask

  task automatic ResetCore;
    rst = 1'b1;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    #1;
  endtask

  initial begin
    clk = 1'b0;
    rst = 1'b0;
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
    read_cmd_valid = 1'b0;
    read_cmd_id = '0;
    read_cmd_addr = '0;
    read_cmd_len = '0;
    read_cmd_size = '0;
    read_cmd_burst = '0;
    write_rsp_ready = 1'b0;
    read_rsp_ready = 1'b0;
    policy_lookup_hit = 1'b0;
    policy_region_type = '0;
    policy_target_nid = '0;
    policy_ns = 1'b0;
    policy_order = '0;
    policy_memattr = '0;
    policy_epoch = '0;
    policy_quiesce_req = 1'b0;
    txreq_ready = 1'b0;
    txdat_ready = 1'b0;
    txrsp_ready = 1'b0;
    rxrsp_valid = 1'b0;
    rxrsp_payload = '0;
    rxdat_valid = 1'b0;
    rxdat_payload = '0;

    ResetCore();
    Check(read_cmd_ready, "empty snapshot slot must accept a read");
    read_cmd_valid = 1'b1;
    read_cmd_id = 4'h2;
    read_cmd_addr = 64'h0000_0000_8000_0040;
    read_cmd_len = 8'h00;
    read_cmd_size = 3'd2;
    read_cmd_burst = 2'b01;
    policy_lookup_hit = 1'b1;
    policy_region_type = 2'b10;
    policy_epoch = 8'h31;
    policy_target_nid = 7'h0;
    policy_ns = 1'b1;
    policy_order = 2'b10;
    policy_memattr = 4'h9;
    #1;
    Check(policy_lookup_valid, "ordinary address must query dynamic policy");
    Check(policy_lookup_addr == 64'h0000_0000_8000_0040,
          "policy lookup address mismatch");
    @(posedge clk);
    #1;
    Check(dut.read_snapshot_q.valid, "ordinary read must fill snapshot");
    Check(!dut.read_snapshot_q.is_policy_csr, "ordinary read marked as CSR");
    Check(dut.read_snapshot_q.policy_hit, "policy hit was not captured");
    Check(dut.read_snapshot_q.region_type == 2'b10,
          "region type snapshot mismatch");
    Check(dut.read_snapshot_q.policy_epoch == 8'h31,
          "policy epoch snapshot mismatch");
    Check(dut.read_snapshot_q.target_nid == 7'h0 &&
          dut.read_snapshot_q.ns && dut.read_snapshot_q.order == 2'b10 &&
          dut.read_snapshot_q.memattr == 4'h9,
          "read request attributes were not snapshotted");
    Check(!read_cmd_ready, "full snapshot slot must backpressure reads");

    read_cmd_valid = 1'b0;
    ResetCore();
    read_cmd_valid = 1'b1;
    read_cmd_id = 4'h6;
    read_cmd_addr = 64'h0000_0020_0000_0020;
    policy_lookup_hit = 1'b0;
    policy_region_type = 2'b00;
    policy_epoch = 8'h44;
    #1;
    Check(!policy_lookup_valid, "CSR address must bypass dynamic policy");
    @(posedge clk);
    #1;
    Check(dut.read_snapshot_q.is_policy_csr, "CSR read was not classified");
    Check(dut.read_snapshot_q.policy_hit, "CSR read must be admitted locally");

    read_cmd_valid = 1'b0;
    ResetCore();
    read_cmd_valid = 1'b1;
    read_cmd_addr = 64'h0000_0020_0000_1000;
    policy_lookup_hit = 1'b1;
    #1;
    Check(policy_lookup_valid,
          "CSR base plus size must be outside the half-open CSR window");

    read_cmd_valid = 1'b0;
    ResetCore();
    policy_quiesce_req = 1'b1;
    read_cmd_valid = 1'b1;
    read_cmd_addr = 64'h0000_0000_8000_0080;
    #1;
    Check(!read_cmd_ready, "quiesce must block new read admission");
    Check(!policy_lookup_valid, "quiesce must suppress policy lookup");

    read_cmd_valid = 1'b0;
    policy_quiesce_req = 1'b0;
    ResetCore();
    write_cmd_valid = 1'b1;
    write_data_valid = 1'b1;
    write_cmd_id = 4'hb;
    write_cmd_addr = 64'h0000_0000_9000_0100;
    write_cmd_len = 8'h00;
    write_cmd_size = 3'd2;
    write_cmd_burst = 2'b01;
    write_data = 32'hca11_ab1e;
    write_strb = 4'b1100;
    write_last = 1'b1;
    policy_lookup_hit = 1'b1;
    policy_region_type = 2'b01;
    policy_epoch = 8'h55;
    #1;
    Check(write_cmd_ready && write_data_ready,
          "complete write pair must be admitted atomically");
    Check(policy_lookup_valid, "ordinary write must query dynamic policy");
    Check(policy_lookup_addr == 64'h0000_0000_9000_0100,
          "write policy lookup address mismatch");
    @(posedge clk);
    #1;
    Check(dut.write_snapshot_q.valid, "ordinary write must fill snapshot");
    Check(dut.write_snapshot_q.policy_hit, "write policy hit was not captured");
    Check(dut.write_snapshot_q.data == 32'hca11_ab1e,
          "write data snapshot mismatch");
    Check(dut.write_snapshot_q.strb == 4'b1100,
          "write strobe snapshot mismatch");
    Check(dut.write_snapshot_q.last, "write last snapshot mismatch");

    write_cmd_valid = 1'b0;
    write_data_valid = 1'b0;
    ResetCore();
    write_cmd_valid = 1'b1;
    write_data_valid = 1'b1;
    write_cmd_addr = 64'h0000_0020_0000_0030;
    write_data = 32'h1234_5678;
    write_last = 1'b1;
    policy_lookup_hit = 1'b0;
    #1;
    Check(!policy_lookup_valid, "CSR write must bypass dynamic policy");
    @(posedge clk);
    #1;
    Check(dut.write_snapshot_q.is_policy_csr,
          "CSR write was not classified locally");
    Check(dut.write_snapshot_q.policy_hit,
          "CSR write must be admitted locally");

    write_cmd_valid = 1'b0;
    write_data_valid = 1'b0;
    ResetCore();
    read_cmd_valid = 1'b1;
    read_cmd_addr = 64'h0000_0000_a000_0000;
    write_cmd_valid = 1'b1;
    write_data_valid = 1'b1;
    write_cmd_addr = 64'h0000_0000_b000_0000;
    #1;
    Check(read_cmd_ready, "read must win a same-cycle lookup conflict");
    Check(!write_cmd_ready && !write_data_ready,
          "write must wait for the read lookup conflict");

    $display("PASS: rni_core read/write admission snapshot and CSR bypass");
    $finish;
  end

endmodule
