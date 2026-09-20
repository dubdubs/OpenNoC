`timescale 1ns / 1ps

module tb_rni_axi_ingress_ar;

  logic aclk;
  logic aresetn;
  logic [3:0] s_axi_awid;
  logic [63:0] s_axi_awaddr;
  logic [7:0] s_axi_awlen;
  logic [2:0] s_axi_awsize;
  logic [1:0] s_axi_awburst;
  logic s_axi_awvalid;
  logic s_axi_awready;
  logic [31:0] s_axi_wdata;
  logic [3:0] s_axi_wstrb;
  logic s_axi_wlast;
  logic s_axi_wvalid;
  logic s_axi_wready;
  logic [3:0] s_axi_bid;
  logic [1:0] s_axi_bresp;
  logic s_axi_buser;
  logic s_axi_bvalid;
  logic s_axi_bready;
  logic [3:0] s_axi_arid;
  logic [63:0] s_axi_araddr;
  logic [7:0] s_axi_arlen;
  logic [2:0] s_axi_arsize;
  logic [1:0] s_axi_arburst;
  logic s_axi_arvalid;
  logic s_axi_arready;
  logic [3:0] s_axi_rid;
  logic [31:0] s_axi_rdata;
  logic [1:0] s_axi_rresp;
  logic s_axi_ruser;
  logic s_axi_rlast;
  logic s_axi_rvalid;
  logic s_axi_rready;
  logic write_bundle_valid;
  logic [3:0] write_bundle_id;
  logic [63:0] write_bundle_addr;
  logic [7:0] write_bundle_len;
  logic [2:0] write_bundle_size;
  logic [1:0] write_bundle_burst;
  logic [31:0] write_bundle_data;
  logic [3:0] write_bundle_strb;
  logic write_bundle_ready;
  logic read_bundle_valid;
  logic [3:0] read_bundle_id;
  logic [63:0] read_bundle_addr;
  logic [7:0] read_bundle_len;
  logic [2:0] read_bundle_size;
  logic [1:0] read_bundle_burst;
  logic read_bundle_ready;

  rni_axi_ingress dut (
      .aclk(aclk),
      .aresetn(aresetn),
      .s_axi_awid(s_axi_awid),
      .s_axi_awaddr(s_axi_awaddr),
      .s_axi_awlen(s_axi_awlen),
      .s_axi_awsize(s_axi_awsize),
      .s_axi_awburst(s_axi_awburst),
      .s_axi_awuser(1'b0),
      .s_axi_awvalid(s_axi_awvalid),
      .s_axi_awready(s_axi_awready),
      .s_axi_wdata(s_axi_wdata),
      .s_axi_wstrb(s_axi_wstrb),
      .s_axi_wuser(1'b0),
      .s_axi_wlast(s_axi_wlast),
      .s_axi_wvalid(s_axi_wvalid),
      .s_axi_wready(s_axi_wready),
      .s_axi_bid(s_axi_bid),
      .s_axi_bresp(s_axi_bresp),
      .s_axi_buser(s_axi_buser),
      .s_axi_bvalid(s_axi_bvalid),
      .s_axi_bready(s_axi_bready),
      .s_axi_arid(s_axi_arid),
      .s_axi_araddr(s_axi_araddr),
      .s_axi_arlen(s_axi_arlen),
      .s_axi_arsize(s_axi_arsize),
      .s_axi_arburst(s_axi_arburst),
      .s_axi_aruser(1'b0),
      .s_axi_arvalid(s_axi_arvalid),
      .s_axi_arready(s_axi_arready),
      .s_axi_rid(s_axi_rid),
      .s_axi_rdata(s_axi_rdata),
      .s_axi_rresp(s_axi_rresp),
      .s_axi_ruser(s_axi_ruser),
      .s_axi_rlast(s_axi_rlast),
      .s_axi_rvalid(s_axi_rvalid),
      .s_axi_rready(s_axi_rready),
      .write_bundle_valid_o(write_bundle_valid),
      .write_bundle_id_o(write_bundle_id),
      .write_bundle_addr_o(write_bundle_addr),
      .write_bundle_len_o(write_bundle_len),
      .write_bundle_size_o(write_bundle_size),
      .write_bundle_burst_o(write_bundle_burst),
      .write_bundle_data_o(write_bundle_data),
      .write_bundle_strb_o(write_bundle_strb),
      .write_bundle_ready_i(write_bundle_ready),
      .read_bundle_valid_o(read_bundle_valid),
      .read_bundle_id_o(read_bundle_id),
      .read_bundle_addr_o(read_bundle_addr),
      .read_bundle_len_o(read_bundle_len),
      .read_bundle_size_o(read_bundle_size),
      .read_bundle_burst_o(read_bundle_burst),
      .read_bundle_ready_i(read_bundle_ready)
  );

  always #5 aclk = ~aclk;

  task automatic Check(input logic condition, input string message);
    if (condition !== 1'b1) begin
      $fatal(1, "CHECK FAILED: %s", message);
    end
  endtask

  property ArHandshakeFillsSingleEntry;
    @(posedge aclk) disable iff (!aresetn)
        (s_axi_arvalid && s_axi_arready) |=>
            (dut.ar_capture_valid_q && !s_axi_arready);
  endproperty

  assert property (ArHandshakeFillsSingleEntry)
      else $fatal(1, "AR handshake did not fill the single-entry buffer");

  property AwHandshakeFillsSingleEntry;
    @(posedge aclk) disable iff (!aresetn)
        (s_axi_awvalid && s_axi_awready) |=>
            (dut.aw_capture_valid_q && !s_axi_awready);
  endproperty

  assert property (AwHandshakeFillsSingleEntry)
      else $fatal(1, "AW handshake did not fill the single-entry buffer");

  property WhandshakeFillsSingleEntry;
    @(posedge aclk) disable iff (!aresetn)
        (s_axi_wvalid && s_axi_wready) |=>
            (dut.w_capture_valid_q && !s_axi_wready);
  endproperty

  assert property (WhandshakeFillsSingleEntry)
      else $fatal(1, "W handshake did not fill the single-entry buffer");

  property WriteBundleHandshakeReleasesPair;
    @(posedge aclk) disable iff (!aresetn)
        (write_bundle_valid && write_bundle_ready) |=>
            (!dut.aw_capture_valid_q && !dut.w_capture_valid_q);
  endproperty

  assert property (WriteBundleHandshakeReleasesPair)
      else $fatal(1, "write bundle handshake did not release both captures");

  property ReadBundleHandshakeReleasesAr;
    @(posedge aclk) disable iff (!aresetn)
        (read_bundle_valid && read_bundle_ready) |=> !dut.ar_capture_valid_q;
  endproperty

  assert property (ReadBundleHandshakeReleasesAr)
      else $fatal(1, "read bundle handshake did not release AR capture");

  initial begin
    aclk = 1'b0;
    aresetn = 1'b0;
    s_axi_awid = '0;
    s_axi_awaddr = '0;
    s_axi_awlen = '0;
    s_axi_awsize = '0;
    s_axi_awburst = '0;
    s_axi_awvalid = 1'b0;
    s_axi_wdata = '0;
    s_axi_wstrb = '0;
    s_axi_wlast = 1'b0;
    s_axi_wvalid = 1'b0;
    s_axi_bready = 1'b0;
    s_axi_arid = '0;
    s_axi_araddr = '0;
    s_axi_arlen = '0;
    s_axi_arsize = '0;
    s_axi_arburst = '0;
    s_axi_arvalid = 1'b0;
    s_axi_rready = 1'b0;
    write_bundle_ready = 1'b0;
    read_bundle_ready = 1'b0;

    repeat (2) @(posedge aclk);
    #1;
    Check(!s_axi_arready, "ARREADY must remain low during reset");

    @(negedge aclk);
    aresetn = 1'b1;
    #1;
    Check(s_axi_arready, "empty AR buffer must accept a request");
    Check(s_axi_awready, "empty AW buffer must accept a request");
    Check(!s_axi_wready, "W must remain stalled before the W increment");

    // WVALID arrives before AW. WREADY must remain low until the AW register
    // has been written on a prior edge.
    s_axi_wdata = 32'hbad0_0001;
    s_axi_wstrb = 4'b1111;
    s_axi_wlast = 1'b0;
    s_axi_wvalid = 1'b1;
    s_axi_awid = 4'h5;
    s_axi_awaddr = 64'h0000_0000_2468_ace0;
    s_axi_awlen = 8'h00;
    s_axi_awsize = 3'd2;
    s_axi_awburst = 2'b01;
    s_axi_awvalid = 1'b1;
    s_axi_arid = 4'h3;
    s_axi_araddr = 64'h0000_0000_1234_5600;
    s_axi_arlen = 8'h00;
    s_axi_arsize = 3'd2;
    s_axi_arburst = 2'b01;
    s_axi_arvalid = 1'b1;
    @(posedge aclk);
    #1;
    Check(!s_axi_arready, "filled AR buffer must apply backpressure");
    Check(!s_axi_awready, "filled AW buffer must apply backpressure");
    Check(dut.ar_capture_valid_q, "accepted AR must set valid bit");
    Check(dut.aw_capture_valid_q, "accepted AW must set valid bit");
    Check(dut.ar_capture_q.id == 4'h3, "captured ARID mismatch");
    Check(dut.ar_capture_q.addr == 64'h0000_0000_1234_5600,
          "captured ARADDR mismatch");
    Check(dut.ar_capture_q.len == 8'h00, "captured ARLEN mismatch");
    Check(dut.ar_capture_q.size == 3'd2, "captured ARSIZE mismatch");
    Check(dut.ar_capture_q.burst == 2'b01, "captured ARBURST mismatch");
    Check(dut.aw_capture_q.id == 4'h5, "captured AWID mismatch");
    Check(dut.aw_capture_q.addr == 64'h0000_0000_2468_ace0,
          "captured AWADDR mismatch");
    Check(dut.aw_capture_q.len == 8'h00, "captured AWLEN mismatch");
    Check(dut.aw_capture_q.size == 3'd2, "captured AWSIZE mismatch");
    Check(dut.aw_capture_q.burst == 2'b01, "captured AWBURST mismatch");
    Check(s_axi_wready, "single-beat AW must enable the first W handshake");
    Check(!dut.w_capture_valid_q, "W must not capture on AW handshake edge");

    // Invalid WLAST is captured but recorded as a protocol error, preventing
    // a silent interpretation of a non-final beat as a complete write.
    @(posedge aclk);
    #1;
    Check(dut.w_capture_valid_q, "W handshake must set valid bit");
    Check(dut.w_protocol_error_q, "single-beat WLAST=0 must set error");
    Check(dut.w_capture_q.data == 32'hbad0_0001, "captured WDATA mismatch");
    Check(!s_axi_wready, "filled W buffer must apply backpressure");
    Check(!write_bundle_valid, "WLAST error must not issue a write bundle");
    Check(read_bundle_valid, "captured AR must issue a read bundle");
    Check(read_bundle_id == 4'h3, "read bundle ID mismatch");
    Check(read_bundle_addr == 64'h0000_0000_1234_5600,
          "read bundle address mismatch");
    Check(read_bundle_len == 8'h00, "read bundle length mismatch");
    Check(read_bundle_size == 3'd2, "read bundle size mismatch");
    Check(read_bundle_burst == 2'b01, "read bundle burst mismatch");

    // Keep downstream stalled for a full cycle, then consume AR exactly once.
    @(posedge aclk);
    #1;
    Check(read_bundle_valid, "read bundle must persist during downstream stall");
    Check(read_bundle_addr == 64'h0000_0000_1234_5600,
          "stalled read bundle address changed");
    @(negedge aclk);
    read_bundle_ready = 1'b1;
    @(posedge aclk);
    #1;
    Check(!read_bundle_valid, "accepted read bundle must clear valid");
    Check(!dut.ar_capture_valid_q, "read bundle handshake must release AR");
    read_bundle_ready = 1'b0;

    // Reset clears the malformed write context before the independent valid
    // WLAST path is exercised.
    s_axi_awvalid = 1'b0;
    s_axi_arvalid = 1'b0;
    s_axi_wvalid = 1'b0;
    @(negedge aclk);
    aresetn = 1'b0;
    @(posedge aclk);
    #1;
    Check(!dut.w_capture_valid_q, "reset must clear W capture valid");
    Check(!dut.w_protocol_error_q, "reset must clear W protocol error");

    @(negedge aclk);
    aresetn = 1'b1;
    s_axi_awid = 4'h7;
    s_axi_awaddr = 64'h0000_0000_1122_3344;
    s_axi_awlen = 8'h00;
    s_axi_awvalid = 1'b1;
    s_axi_wdata = 32'hface_cafe;
    s_axi_wstrb = 4'b0011;
    s_axi_wlast = 1'b1;
    s_axi_wvalid = 1'b1;
    @(posedge aclk);
    #1;
    Check(s_axi_wready, "captured single-beat AW must release W stall");
    Check(!dut.w_capture_valid_q, "W may not capture before its own edge");
    s_axi_awvalid = 1'b0;
    @(posedge aclk);
    #1;
    Check(dut.w_capture_valid_q, "valid W must set capture valid");
    Check(!dut.w_protocol_error_q, "WLAST=1 must not set protocol error");
    Check(dut.w_capture_q.data == 32'hface_cafe, "valid WDATA mismatch");
    Check(dut.w_capture_q.strb == 4'b0011, "valid WSTRB mismatch");
    Check(dut.w_capture_q.last, "valid single-beat W must retain WLAST");
    Check(write_bundle_valid, "legal AW+W pair must issue a write bundle");
    Check(write_bundle_id == 4'h7, "write bundle ID mismatch");
    Check(write_bundle_addr == 64'h0000_0000_1122_3344,
          "write bundle address mismatch");
    Check(write_bundle_data == 32'hface_cafe, "write bundle data mismatch");
    Check(write_bundle_strb == 4'b0011, "write bundle strobe mismatch");

    // Consumer backpressure must preserve the entire atomic pair.
    @(posedge aclk);
    #1;
    Check(write_bundle_valid, "bundle valid must persist during downstream stall");
    Check(write_bundle_addr == 64'h0000_0000_1122_3344,
          "stalled bundle address changed");
    Check(write_bundle_data == 32'hface_cafe, "stalled bundle data changed");

    @(negedge aclk);
    write_bundle_ready = 1'b1;
    @(posedge aclk);
    #1;
    Check(!write_bundle_valid, "accepted bundle must clear valid");
    Check(!dut.aw_capture_valid_q, "bundle handshake must release AW capture");
    Check(!dut.w_capture_valid_q, "bundle handshake must release W capture");

    s_axi_wvalid = 1'b0;
    $display("PASS: rni_axi_ingress AR/AW/W capture and write bundle handoff");
    $finish;
  end

endmodule
