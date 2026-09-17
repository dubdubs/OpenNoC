/*
 * Standalone UVS smoke test for the OpenNoC SNF RTL.
 * Exercises a 64-byte ReadNoSnp and WriteNoSnpFull transaction against a
 * behavioral AXI memory responder.
 */
`include "chie_defines.v"
`include "axi4_defines.v"
`include "snf_param.v"

module tb_snf_top `SNF_PARAM;
  localparam [43:0] kReadAddress = 44'h0000_0000_1000;
  localparam [43:0] kWriteAddress = 44'h0000_0000_2000;
  localparam [43:0] kPartialWriteAddress = 44'h0000_0000_3000;
  localparam [11:0] kReadTxnId = 12'h001;
  localparam [11:0] kWriteTxnId = 12'h012;
  localparam [11:0] kPartialWriteTxnId = 12'h023;
  localparam [6:0] kRequesterNid = 7'h01;
  localparam [6:0] kSnfNid = 7'h03;

  reg clk;
  reg rst;
  reg tx_link_active_ack;
  reg rx_link_active_req;
  reg rx_sactive;
  reg rx_req_flit_v;
  reg [`CHIE_REQ_FLIT_RANGE] rx_req_flit;
  reg rx_req_flit_pend;
  reg rx_dat_flit_v;
  reg [`CHIE_DAT_FLIT_RANGE] rx_dat_flit;
  reg rx_dat_flit_pend;
  wire tx_rsp_flit_pend;
  reg tx_rsp_lcrd_v;
  wire tx_dat_flit_pend;
  reg tx_dat_lcrd_v;

  wire tx_link_active_req;
  wire rx_link_active_ack;
  wire tx_sactive;
  wire rx_req_lcrd_v;
  wire rx_dat_lcrd_v;
  wire tx_rsp_flit_v;
  wire [`CHIE_RSP_FLIT_RANGE] tx_rsp_flit;
  wire tx_dat_flit_v;
  wire [`CHIE_DAT_FLIT_RANGE] tx_dat_flit;

  wire [`AXI4_ARID_RANGE] arid;
  wire [`AXI4_ARADDR_RANGE] araddr;
  wire [`AXI4_ARLEN_RANGE] arlen;
  wire [`AXI4_ARSIZE_RANGE] arsize;
  wire [`AXI4_ARBURST_RANGE] arburst;
  wire [`AXI4_ARLOCK_RANGE] arlock;
  wire [`AXI4_ARCACHE_RANGE] arcache;
  wire [`AXI4_ARPROT_RANGE] arprot;
  wire [`AXI4_ARQOS_RANGE] arqos;
  wire [`AXI4_ARREGION_RANGE] arregion;
  wire arvalid;
  reg arready;
  reg [`AXI4_RID_RANGE] rid;
  reg [`AXI4_RDATA_RANGE] rdata;
  reg [`AXI4_RRESP_RANGE] rresp;
  reg [`AXI4_RLAST_RANGE] rlast;
  reg rvalid;
  wire rready;
  wire [`AXI4_AWID_RANGE] awid;
  wire [`AXI4_AWADDR_RANGE] awaddr;
  wire [`AXI4_AWLEN_RANGE] awlen;
  wire [`AXI4_AWSIZE_RANGE] awsize;
  wire [`AXI4_AWBURST_RANGE] awburst;
  wire [`AXI4_AWLOCK_RANGE] awlock;
  wire [`AXI4_AWCACHE_RANGE] awcache;
  wire [`AXI4_AWPROT_RANGE] awprot;
  wire [`AXI4_AWQOS_RANGE] awqos;
  wire [`AXI4_AWREGION_RANGE] awregion;
  wire awvalid;
  reg awready;
  wire [`AXI4_WDATA_RANGE] wdata;
  wire [`AXI4_WSTRB_RANGE] wstrb;
  wire wlast;
  wire wvalid;
  reg wready;
  reg [`AXI4_BID_RANGE] bid;
  reg [`AXI4_BRESP_RANGE] bresp;
  reg bvalid;
  wire bready;

  assign tx_rsp_flit_pend = 1'b1;
  assign tx_dat_flit_pend = 1'b1;

  integer error_count;
  integer read_data_flits;
  integer write_data_beats;
  integer partial_write_data_beats;
  reg [11:0] write_dbid;
  reg saw_write_dbidresp;
  reg saw_write_comp;
  reg partial_write_phase;
  reg saw_partial_strobe;

  snf `SNF_PARAM_INST u_snf (
      .CLK(clk), .RST(rst),
      .TXLINKACTIVEREQ(tx_link_active_req),
      .TXLINKACTIVEACK(tx_link_active_ack),
      .RXLINKACTIVEREQ(rx_link_active_req),
      .RXLINKACTIVEACK(rx_link_active_ack), .TXSACTIVE(tx_sactive),
      .RXSACTIVE(rx_sactive), .RXREQFLITV(rx_req_flit_v),
      .RXREQFLIT(rx_req_flit), .RXREQFLITPEND(rx_req_flit_pend),
      .RXREQLCRDV(rx_req_lcrd_v), .RXDATFLITV(rx_dat_flit_v),
      .RXDATFLIT(rx_dat_flit), .RXDATFLITPEND(rx_dat_flit_pend),
      .RXDATLCRDV(rx_dat_lcrd_v), .TXRSPFLITV(tx_rsp_flit_v),
      .TXRSPFLIT(tx_rsp_flit), .TXRSPFLITPEND(tx_rsp_flit_pend),
      .TXRSPLCRDV(tx_rsp_lcrd_v), .TXDATFLITV(tx_dat_flit_v),
      .TXDATFLIT(tx_dat_flit), .TXDATFLITPEND(tx_dat_flit_pend),
      .TXDATLCRDV(tx_dat_lcrd_v), .ARID(arid), .ARADDR(araddr),
      .ARLEN(arlen), .ARSIZE(arsize), .ARBURST(arburst), .ARLOCK(arlock),
      .ARCACHE(arcache), .ARPROT(arprot), .ARQOS(arqos), .ARREGION(arregion),
      .ARVALID(arvalid), .ARREADY(arready), .RID(rid), .RDATA(rdata),
      .RRESP(rresp), .RLAST(rlast), .RVALID(rvalid), .RREADY(rready),
      .AWID(awid), .AWADDR(awaddr), .AWLEN(awlen), .AWSIZE(awsize),
      .AWBURST(awburst), .AWLOCK(awlock), .AWCACHE(awcache),
      .AWPROT(awprot), .AWQOS(awqos), .AWREGION(awregion), .AWVALID(awvalid),
      .AWREADY(awready), .WDATA(wdata), .WSTRB(wstrb), .WLAST(wlast),
      .WVALID(wvalid), .WREADY(wready), .BID(bid), .BRESP(bresp),
      .BVALID(bvalid), .BREADY(bready));

  always #5 clk = ~clk;

  task automatic fail(input [8*96-1:0] message);
    begin
      error_count = error_count + 1;
      $display("ERROR: %0s", message);
    end
  endtask

  task automatic send_request(
      input [`CHIE_REQ_FLIT_OPCODE_RANGE] opcode,
      input [11:0] txn_id,
      input [43:0] address);
    begin
      @(negedge clk);
      rx_req_flit = '0;
      rx_req_flit[`CHIE_REQ_FLIT_OPCODE_RANGE] = opcode;
      rx_req_flit[`CHIE_REQ_FLIT_TGTID_RANGE] = kSnfNid;
      rx_req_flit[`CHIE_REQ_FLIT_SRCID_RANGE] = kRequesterNid;
      rx_req_flit[`CHIE_REQ_FLIT_TXNID_RANGE] = txn_id;
      rx_req_flit[`CHIE_REQ_FLIT_RETURNNID_RANGE] = kRequesterNid;
      rx_req_flit[`CHIE_REQ_FLIT_RETURNTXNID_RANGE] = txn_id;
      rx_req_flit[`CHIE_REQ_FLIT_SIZE_RANGE] = 3'b110;
      rx_req_flit[`CHIE_REQ_FLIT_ADDR_RANGE] = address;
      rx_req_flit_v = 1'b1;
      @(negedge clk);
      rx_req_flit_v = 1'b0;
      rx_req_flit = '0;
    end
  endtask

  task automatic send_write_data(
      input [11:0] dbid,
      input [1:0] data_id,
      input [`CHIE_DAT_FLIT_BE_RANGE] byte_enable,
      input [`CHIE_DAT_FLIT_DATA_RANGE] data);
    begin
      @(negedge clk);
      rx_dat_flit = '0;
      rx_dat_flit[`CHIE_DAT_FLIT_OPCODE_RANGE] = `CHIE_NONCOPYBACKWRDATA;
      rx_dat_flit[`CHIE_DAT_FLIT_TXNID_RANGE] = dbid;
      rx_dat_flit[`CHIE_DAT_FLIT_DATAID_RANGE] = data_id;
      rx_dat_flit[`CHIE_DAT_FLIT_BE_RANGE] = byte_enable;
      rx_dat_flit[`CHIE_DAT_FLIT_DATA_RANGE] = data;
      rx_dat_flit_v = 1'b1;
      @(negedge clk);
      rx_dat_flit_v = 1'b0;
      rx_dat_flit = '0;
    end
  endtask

  task automatic send_axi_read_data;
    integer beat;
    begin
      for (beat = 0; beat < 4; beat = beat + 1) begin
        @(negedge clk);
        rvalid = 1'b1;
        rdata = {96'h0, 32'h1000_0000 + beat};
        rlast = (beat == 3);
        do @(posedge clk); while (!rready);
        @(negedge clk);
        rvalid = 1'b0;
        rlast = 1'b0;
      end
    end
  endtask

  always @(posedge clk) begin
    if (!rst && arvalid && arready) begin
      if (araddr != kReadAddress[31:0] || arlen != 8'd3 || arsize != 3'd4) begin
        fail("unexpected AXI read address transaction");
      end
      fork
        send_axi_read_data();
      join_none
    end
    if (!rst && awvalid && awready) begin
      if ((!partial_write_phase && awaddr != kWriteAddress[31:0]) ||
          (partial_write_phase && awaddr != kPartialWriteAddress[31:0]) ||
          awlen != 8'd3 || awsize != 3'd4) begin
        fail("unexpected AXI write address transaction");
      end
    end
    if (!rst && wvalid && wready) begin
      if (partial_write_phase) begin
        partial_write_data_beats = partial_write_data_beats + 1;
        if (wstrb != '1) saw_partial_strobe = 1'b1;
        if (wlast && partial_write_data_beats != 4) begin
          fail("partial AXI WLAST occurred on wrong beat");
        end
      end else begin
        write_data_beats = write_data_beats + 1;
        if (wstrb != '1) fail("AXI write strobe is not full width");
        if (wlast && write_data_beats != 4) fail("AXI WLAST occurred on wrong beat");
      end
    end
    if (!rst && tx_dat_flit_v) begin
      read_data_flits = read_data_flits + 1;
      if (tx_dat_flit[`CHIE_DAT_FLIT_OPCODE_RANGE] != `CHIE_COMPDATA) begin
        fail("ReadNoSnp did not return CompData");
      end
    end
    if (!rst && tx_rsp_flit_v) begin
      if (tx_rsp_flit[`CHIE_RSP_FLIT_OPCODE_RANGE] == `CHIE_DBIDRESP) begin
        saw_write_dbidresp = 1'b1;
        write_dbid = tx_rsp_flit[`CHIE_RSP_FLIT_DBID_RANGE];
      end else if (tx_rsp_flit[`CHIE_RSP_FLIT_OPCODE_RANGE] == `CHIE_COMP) begin
        saw_write_comp = 1'b1;
      end
    end
  end

  initial begin
    clk = 1'b0;
    rst = 1'b1;
    tx_link_active_ack = 1'b1;
    rx_link_active_req = 1'b0;
    rx_sactive = 1'b1;
    rx_req_flit_v = 1'b0;
    rx_req_flit = '0;
    rx_req_flit_pend = 1'b1;
    rx_dat_flit_v = 1'b0;
    rx_dat_flit = '0;
    rx_dat_flit_pend = 1'b1;
    tx_rsp_lcrd_v = 1'b1;
    tx_dat_lcrd_v = 1'b1;
    arready = 1'b1;
    rid = '0;
    rdata = '0;
    rresp = '0;
    rlast = 1'b0;
    rvalid = 1'b0;
    awready = 1'b1;
    wready = 1'b1;
    bid = '0;
    bresp = '0;
    bvalid = 1'b0;
    error_count = 0;
    read_data_flits = 0;
    write_data_beats = 0;
    partial_write_data_beats = 0;
    write_dbid = '0;
    saw_write_dbidresp = 1'b0;
    saw_write_comp = 1'b0;
    partial_write_phase = 1'b0;
    saw_partial_strobe = 1'b0;

    repeat (4) @(posedge clk);
    rst = 1'b0;
    rx_link_active_req = 1'b1;
    repeat (3) @(posedge clk);

    send_request(`CHIE_READNOSNP, kReadTxnId, kReadAddress);
    repeat (80) @(posedge clk);
    if (read_data_flits != 2) fail("ReadNoSnp did not return two CompData flits");

    send_request(`CHIE_WRITENOSNPFULL, kWriteTxnId, kWriteAddress);
    repeat (20) @(posedge clk);
    if (!saw_write_dbidresp) fail("WriteNoSnpFull did not return DBIDResp");
    send_write_data(write_dbid, 2'b00, '1, 256'h1111);
    send_write_data(write_dbid, 2'b10, '1, 256'h2222);
    repeat (40) @(posedge clk);
    if (write_data_beats != 4) fail("WriteNoSnpFull did not issue four AXI data beats");
    @(negedge clk);
    bid = write_dbid[10:0];
    bvalid = 1'b1;
    @(negedge clk);
    bvalid = 1'b0;
    repeat (20) @(posedge clk);
    if (!saw_write_comp) fail("WriteNoSnpFull did not return Comp");

    // WriteNoSnpPtl must follow the same DBID/DAT sequencing, while preserving
    // partial byte enables on the AXI write side.
    partial_write_phase = 1'b1;
    write_dbid = '0;
    saw_write_dbidresp = 1'b0;
    saw_write_comp = 1'b0;
    send_request(`CHIE_WRITENOSNPPTL, kPartialWriteTxnId, kPartialWriteAddress);
    repeat (20) @(posedge clk);
    if (!saw_write_dbidresp) fail("WriteNoSnpPtl did not return DBIDResp");
    send_write_data(write_dbid, 2'b00, 32'h0000_ffff, 256'h3333);
    send_write_data(write_dbid, 2'b10, 32'hffff_0000, 256'h4444);
    repeat (40) @(posedge clk);
    if (partial_write_data_beats != 4) begin
      fail("WriteNoSnpPtl did not issue four AXI data beats");
    end
    if (!saw_partial_strobe) begin
      fail("WriteNoSnpPtl did not preserve a partial AXI strobe");
    end
    @(negedge clk);
    bid = write_dbid[10:0];
    bvalid = 1'b1;
    @(negedge clk);
    bvalid = 1'b0;
    repeat (20) @(posedge clk);
    if (!saw_write_comp) fail("WriteNoSnpPtl did not return Comp");

    if (error_count == 0) begin
      $display("SNF standalone test passed");
    end else begin
      $display("SNF standalone test failed with %0d error(s)", error_count);
    end
    $finish;
  end

  initial begin
    repeat (1000) @(posedge clk);
    fail("testbench timeout");
    $finish;
  end
endmodule
