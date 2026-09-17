// Smoke testbench for chi_rni (non-coherent AXI->CHI adaptor core).
// Verifies one aligned read (CompData) and one aligned partial-WSTRB write
// (DBIDResp -> DAT -> Comp) incl. the BE=0 => DATA=0 rule, end to end, with a
// hand-rolled CHI responder. Inputs are driven and outputs sampled at negedge
// to avoid posedge races.
`include "chi_rni_defines.svh"

module tb_chi_rni_core;
  logic clk = 0;
  logic rst_n = 0;
  logic link_active = 1'b1;

  // AXI
  logic [7:0]  s_axi_arid = '0;
  logic [43:0] s_axi_araddr = '0;
  logic [7:0]  s_axi_arlen = '0;
  logic [2:0]  s_axi_arsize = '0;
  logic [1:0]  s_axi_arburst = '0;
  logic [2:0]  s_axi_arprot = '0;
  logic        s_axi_arlock = 1'b0;
  logic        s_axi_arvalid = 1'b0;
  logic        s_axi_arready;
  logic [7:0]  s_axi_rid;
  logic [127:0] s_axi_rdata;
  logic [1:0]  s_axi_rresp;
  logic        s_axi_rlast;
  logic        s_axi_rvalid;
  logic        s_axi_rready = 1'b1;

  logic [7:0]  s_axi_awid = '0;
  logic [43:0] s_axi_awaddr = '0;
  logic [7:0]  s_axi_awlen = '0;
  logic [2:0]  s_axi_awsize = '0;
  logic [1:0]  s_axi_awburst = '0;
  logic [2:0]  s_axi_awprot = '0;
  logic        s_axi_awlock = 1'b0;
  logic        s_axi_awvalid = 1'b0;
  logic        s_axi_awready;
  logic [127:0] s_axi_wdata = '0;
  logic [15:0]  s_axi_wstrb = '0;
  logic        s_axi_wlast = 1'b0;
  logic        s_axi_wvalid = 1'b0;
  logic        s_axi_wready;
  logic [7:0]  s_axi_bid;
  logic [1:0]  s_axi_bresp;
  logic        s_axi_bvalid;
  logic        s_axi_bready = 1'b1;

  // CHI
  logic        chi_txreq_valid;
  logic        chi_txreq_ready = 1'b1;
  logic [6:0]  chi_txreq_opcode;
  logic [43:0] chi_txreq_addr;
  logic [2:0]  chi_txreq_size;
  logic [11:0] chi_txreq_txnid;
  logic        chi_txreq_device;
  logic        chi_txreq_ns;
  logic [1:0]  chi_txreq_order;
  logic [3:0]  chi_txreq_qos;
  logic        chi_txreq_allow_retry;

  logic        chi_rxrsp_valid = 1'b0;
  logic        chi_rxrsp_ready;
  logic [11:0] chi_rxrsp_txnid = '0;
  logic [1:0]  chi_rxrsp_kind = '0;
  logic [11:0] chi_rxrsp_dbid = '0;
  logic [1:0]  chi_rxrsp_resp_err = '0;

  logic        chi_rxdat_valid = 1'b0;
  logic        chi_rxdat_ready;
  logic [11:0] chi_rxdat_txnid = '0;
  logic [1:0]  chi_rxdat_data_id = '0;
  logic [255:0] chi_rxdat_data = '0;
  logic [1:0]  chi_rxdat_resp_err = '0;

  logic        chi_txdat_valid;
  logic        chi_txdat_ready = 1'b1;
  logic [11:0] chi_txdat_txnid;
  logic [11:0] chi_txdat_dbid;
  logic [255:0] chi_txdat_data;
  logic [31:0] chi_txdat_be;
  logic [1:0]  chi_txdat_data_id;
  logic        chi_txdat_last;

  logic protocol_error;

  chi_rni dut(
    .clk(clk), .rst_n(rst_n), .link_active(link_active),
    .s_axi_arid(s_axi_arid), .s_axi_araddr(s_axi_araddr),
    .s_axi_arlen(s_axi_arlen), .s_axi_arsize(s_axi_arsize),
    .s_axi_arburst(s_axi_arburst), .s_axi_arprot(s_axi_arprot),
    .s_axi_arlock(s_axi_arlock), .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready), .s_axi_rid(s_axi_rid),
    .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp),
    .s_axi_rlast(s_axi_rlast), .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rready(s_axi_rready),
    .s_axi_awid(s_axi_awid), .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awlen(s_axi_awlen), .s_axi_awsize(s_axi_awsize),
    .s_axi_awburst(s_axi_awburst), .s_axi_awprot(s_axi_awprot),
    .s_axi_awlock(s_axi_awlock), .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready), .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb), .s_axi_wlast(s_axi_wlast),
    .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
    .s_axi_bid(s_axi_bid), .s_axi_bresp(s_axi_bresp),
    .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
    .chi_txreq_valid(chi_txreq_valid), .chi_txreq_ready(chi_txreq_ready),
    .chi_txreq_opcode(chi_txreq_opcode), .chi_txreq_addr(chi_txreq_addr),
    .chi_txreq_size(chi_txreq_size), .chi_txreq_txnid(chi_txreq_txnid),
    .chi_txreq_device(chi_txreq_device), .chi_txreq_ns(chi_txreq_ns),
    .chi_txreq_order(chi_txreq_order), .chi_txreq_qos(chi_txreq_qos),
    .chi_txreq_allow_retry(chi_txreq_allow_retry),
    .chi_rxrsp_valid(chi_rxrsp_valid), .chi_rxrsp_ready(chi_rxrsp_ready),
    .chi_rxrsp_txnid(chi_rxrsp_txnid), .chi_rxrsp_kind(chi_rxrsp_kind),
    .chi_rxrsp_dbid(chi_rxrsp_dbid), .chi_rxrsp_resp_err(chi_rxrsp_resp_err),
    .chi_rxdat_valid(chi_rxdat_valid), .chi_rxdat_ready(chi_rxdat_ready),
    .chi_rxdat_txnid(chi_rxdat_txnid), .chi_rxdat_data_id(chi_rxdat_data_id),
    .chi_rxdat_data(chi_rxdat_data), .chi_rxdat_resp_err(chi_rxdat_resp_err),
    .chi_txdat_valid(chi_txdat_valid), .chi_txdat_ready(chi_txdat_ready),
    .chi_txdat_txnid(chi_txdat_txnid), .chi_txdat_dbid(chi_txdat_dbid),
    .chi_txdat_data(chi_txdat_data), .chi_txdat_be(chi_txdat_be),
    .chi_txdat_data_id(chi_txdat_data_id), .chi_txdat_last(chi_txdat_last),
    .protocol_error(protocol_error)
  );

  always #5 clk = ~clk;

  int errors = 0;

  // Captured while the REQ flit is still valid (before the handshake
  // consumes it), then reused to correlate the responder's RSP/DAT.
  logic [11:0] captured_txnid;

  task automatic send_rxdat(input logic [11:0] txnid,
                            input logic [255:0] data,
                            input logic [1:0]  resp_err);
    begin
      @(negedge clk);
      chi_rxdat_txnid    = txnid;
      chi_rxdat_data_id  = 2'd0;
      chi_rxdat_data     = data;
      chi_rxdat_resp_err = resp_err;
      chi_rxdat_valid    = 1'b1;
      @(negedge clk);
      chi_rxdat_valid    = 1'b0;
    end
  endtask

  task automatic send_rxrsp(input logic [11:0] txnid,
                            input logic [1:0]  kind,
                            input logic [11:0] dbid,
                            input logic [1:0]  resp_err);
    begin
      @(negedge clk);
      chi_rxrsp_txnid    = txnid;
      chi_rxrsp_kind     = kind;
      chi_rxrsp_dbid     = dbid;
      chi_rxrsp_resp_err = resp_err;
      chi_rxrsp_valid    = 1'b1;
      @(negedge clk);
      chi_rxrsp_valid    = 1'b0;
    end
  endtask

  initial begin
    #20 rst_n = 1'b1;
    #20;

    // ---------- READ: aligned 16B @ 0x40 ----------
    @(negedge clk);
    s_axi_arid    = 8'd0;
    s_axi_araddr  = 44'h40;
    s_axi_arlen   = 8'd0;
    s_axi_arsize  = 3'd4;   // 16B
    s_axi_arburst = `CHI_RNI_AXI_BURST_INCR;
    s_axi_arprot  = 3'b010; // non-secure (prot[1]=1)
    s_axi_arlock  = 1'b0;
    s_axi_arvalid = 1'b1;
    @(negedge clk);
    s_axi_arvalid = 1'b0;

    // Wait for the read REQ on CHI, then answer with CompData.
    fork
      begin
        // responder thread
        wait (chi_txreq_valid && chi_txreq_ready);
        @(negedge clk);
        captured_txnid = chi_txreq_txnid;
        $display("READ REQ: opcode=0x%h addr=0x%h size=%0d txnid=%0d",
                 chi_txreq_opcode, chi_txreq_addr, chi_txreq_size,
                 chi_txreq_txnid);
        if (chi_txreq_opcode != `CHI_RNI_OPCODE_READNOSNP) begin
          $display("FAIL: read opcode 0x%h", chi_txreq_opcode);
          errors = errors + 1;
        end
        repeat (2) @(negedge clk);
        send_rxdat(captured_txnid, 256'h0_8877665544332211_FFEEDDCCBBAA9988, 2'b00);
      end
    join_none

    // Wait for AXI R response.
    begin
      int timeout = 0;
      while (!s_axi_rvalid && timeout < 100) begin
        @(negedge clk);
        timeout = timeout + 1;
      end
      if (!s_axi_rvalid) begin
        $display("FAIL: read R never returned");
        errors = errors + 1;
      end else begin
        $display("READ R: rdata=0x%h rresp=%0b rlast=%0b",
                 s_axi_rdata, s_axi_rresp, s_axi_rlast);
        if (s_axi_rdata !== 128'h8877665544332211_FFEEDDCCBBAA9988) begin
          $display("FAIL: read data mismatch");
          errors = errors + 1;
        end
        if (s_axi_rresp !== `CHI_RNI_AXI_OKAY) begin
          $display("FAIL: read rresp %0b", s_axi_rresp);
          errors = errors + 1;
        end
        if (!s_axi_rlast) begin
          $display("FAIL: read rlast not set");
          errors = errors + 1;
        end
        @(negedge clk); // R handshake (rready=1)
      end
    end

    // ---------- WRITE: aligned 16B @ 0x80 ----------
    @(negedge clk);
    s_axi_awid    = 8'd1;
    s_axi_awaddr  = 44'h80;
    s_axi_awlen   = 8'd0;
    s_axi_awsize  = 3'd4;   // 16B
    s_axi_awburst = `CHI_RNI_AXI_BURST_INCR;
    s_axi_awprot  = 3'b010;
    s_axi_awlock  = 1'b0;
    s_axi_awvalid = 1'b1;
    @(negedge clk);
    s_axi_awvalid = 1'b0;

    @(negedge clk);
    // All 16 bytes carry distinct non-zero data; only the low 8 are enabled.
    s_axi_wdata = 128'h0F0E_0D0C_0B0A_0908_0706_0504_0302_0100;
    s_axi_wstrb = 16'h00FF;
    s_axi_wlast = 1'b1;
    s_axi_wvalid = 1'b1;
    @(negedge clk);
    s_axi_wvalid = 1'b0;
    s_axi_wlast  = 1'b0;

    fork
      begin
        // V1 permits completion before the write DAT sequence finishes.
        // The core must retain the completion and finish after the last DAT.
        wait (chi_txreq_valid && chi_txreq_ready);
        @(negedge clk);
        captured_txnid = chi_txreq_txnid;
        $display("WRITE REQ: opcode=0x%h addr=0x%h size=%0d txnid=%0d",
                 chi_txreq_opcode, chi_txreq_addr, chi_txreq_size,
                 chi_txreq_txnid);
        if (chi_txreq_opcode != `CHI_RNI_OPCODE_WRITENOSNPPTL) begin
          $display("FAIL: write opcode 0x%h", chi_txreq_opcode);
          errors = errors + 1;
        end
        repeat (2) @(negedge clk);
        send_rxrsp(captured_txnid, `CHI_RNI_RSP_DBIDRESP, 12'h5, 2'b00);
        send_rxrsp(captured_txnid, `CHI_RNI_RSP_COMP, 12'h0, 2'b00);
        // wait for DAT
        begin
          int t = 0;
          while (!chi_txdat_valid && t < 100) begin
            @(negedge clk);
            t = t + 1;
          end
          if (!chi_txdat_valid) begin
            $display("FAIL: write DAT never issued");
            errors = errors + 1;
          end else begin
            $display("WRITE DAT: dbid=%0d data=0x%h be=0x%h last=%0b",
                     chi_txdat_dbid, chi_txdat_data, chi_txdat_be,
                     chi_txdat_last);
            if (chi_txdat_dbid !== 12'h5) begin
              $display("FAIL: write dbid %0d", chi_txdat_dbid);
              errors = errors + 1;
            end
            // CHI spec: a deasserted BE lane must carry zero data.
            for (int k = 0; k < 32; k = k + 1) begin
              if (!chi_txdat_be[k] && chi_txdat_data[8*k +: 8] !== 8'h0) begin
                $display("FAIL: DAT lane %0d BE=0 but DATA=0x%h",
                         k, chi_txdat_data[8*k +: 8]);
                errors = errors + 1;
              end
            end
            @(negedge clk); // DAT handshake (txdat_ready=1)
          end
        end
      end
    join_none

    begin
      int timeout = 0;
      while (!s_axi_bvalid && timeout < 200) begin
        @(negedge clk);
        timeout = timeout + 1;
      end
      if (!s_axi_bvalid) begin
        $display("FAIL: write B never returned");
        errors = errors + 1;
      end else begin
        $display("WRITE B: bresp=%0b", s_axi_bresp);
        if (s_axi_bresp !== `CHI_RNI_AXI_OKAY) begin
          $display("FAIL: write bresp %0b", s_axi_bresp);
          errors = errors + 1;
        end
      end
    end

    if (protocol_error) begin
      $display("FAIL: protocol_error asserted");
      errors = errors + 1;
    end

    #40;
    if (errors == 0) $display("TB_CORE: PASS");
    else             $display("TB_CORE: FAIL (%0d errors)", errors);
    $finish;
  end
endmodule
