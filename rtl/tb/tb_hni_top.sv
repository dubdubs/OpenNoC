/* Standalone UVS smoke test for the OpenNoC HNI RTL. */
`include "chie_defines.v"
`include "axi4_defines.v"
`include "hni_param.v"

module tb_hni_top `HNI_PARAM;
  localparam [43:0] kReadAddress = 44'h0000_0000_1000;
  localparam [43:0] kWriteAddress = 44'h0000_0000_2000;
  localparam [11:0] kReadTxnId = 12'h101;
  localparam [11:0] kWriteTxnId = 12'h102;
  localparam [6:0] kRequesterNid = 7'h01;

  reg clk;
  reg rst;
  reg tx_link_active_ack;
  reg rx_link_active_req;
  reg rx_sactive;
  reg rx_req_flit_v;
  reg [`CHIE_REQ_FLIT_RANGE] rx_req_flit;
  wire rx_req_flit_pend = 1'b1;
  reg rx_rsp_flit_v;
  reg [`CHIE_RSP_FLIT_RANGE] rx_rsp_flit;
  wire rx_rsp_flit_pend = 1'b1;
  reg rx_dat_flit_v;
  reg [`CHIE_DAT_FLIT_RANGE] rx_dat_flit;
  wire rx_dat_flit_pend = 1'b1;
  wire tx_rsp_flit_pend = 1'b1;
  wire tx_dat_flit_pend = 1'b1;

  wire tx_link_active_req;
  wire rx_link_active_ack;
  wire tx_sactive;
  wire rx_req_lcrd_v;
  wire rx_rsp_lcrd_v;
  wire rx_dat_lcrd_v;
  wire tx_rsp_flit_v;
  wire [`CHIE_RSP_FLIT_RANGE] tx_rsp_flit;
  wire tx_dat_flit_v;
  wire [`CHIE_DAT_FLIT_RANGE] tx_dat_flit;

  wire [10:0] arid;
  wire [`AXI4_ARADDR_WIDTH-1:0] araddr;
  wire [7:0] arlen;
  wire [2:0] arsize;
  wire [1:0] arburst;
  wire [0:0] arlock;
  wire [3:0] arcache;
  wire [2:0] arprot;
  wire [3:0] arqos;
  wire [3:0] arregion;
  wire arvalid;
  reg arready;
  reg [10:0] rid;
  reg [`AXI4_RDATA_WIDTH-1:0] rdata;
  reg [1:0] rresp;
  reg rlast;
  reg rvalid;
  wire rready;
  wire [10:0] awid;
  wire [`AXI4_AWADDR_WIDTH-1:0] awaddr;
  wire [7:0] awlen;
  wire [2:0] awsize;
  wire [1:0] awburst;
  wire [0:0] awlock;
  wire [3:0] awcache;
  wire [2:0] awprot;
  wire [3:0] awqos;
  wire [3:0] awregion;
  wire awvalid;
  reg awready;
  wire [`AXI4_WDATA_WIDTH-1:0] wdata;
  wire [`AXI4_WSTRB_WIDTH-1:0] wstrb;
  wire wlast;
  wire wvalid;
  reg wready;
  reg [10:0] bid;
  reg [1:0] bresp;
  reg bvalid;
  wire bready;

  integer error_count;
  integer read_data_flits;
  integer write_data_beats;
  reg saw_write_response;
  reg [11:0] write_dbid;
  reg [10:0] write_awid;

  hni `HNI_PARAM_INST u_hni (
      .CLK(clk), .RST(rst), .TXLINKACTIVEREQ(tx_link_active_req),
      .TXLINKACTIVEACK(tx_link_active_ack), .RXLINKACTIVEREQ(rx_link_active_req),
      .RXLINKACTIVEACK(rx_link_active_ack), .TXSACTIVE(tx_sactive),
      .RXSACTIVE(rx_sactive), .RXREQFLITV(rx_req_flit_v),
      .RXREQFLIT(rx_req_flit), .RXREQFLITPEND(rx_req_flit_pend),
      .RXREQLCRDV(rx_req_lcrd_v), .RXRSPFLITV(rx_rsp_flit_v),
      .RXRSPFLIT(rx_rsp_flit), .RXRSPFLITPEND(rx_rsp_flit_pend),
      .RXRSPLCRDV(rx_rsp_lcrd_v), .RXDATFLITV(rx_dat_flit_v),
      .RXDATFLIT(rx_dat_flit), .RXDATFLITPEND(rx_dat_flit_pend),
      .RXDATLCRDV(rx_dat_lcrd_v), .TXRSPFLITV(tx_rsp_flit_v),
      .TXRSPFLIT(tx_rsp_flit), .TXRSPFLITPEND(tx_rsp_flit_pend),
      .TXRSPLCRDV(1'b1), .TXDATFLITV(tx_dat_flit_v),
      .TXDATFLIT(tx_dat_flit), .TXDATFLITPEND(tx_dat_flit_pend),
      .TXDATLCRDV(1'b1), .ARID(arid), .ARADDR(araddr), .ARLEN(arlen),
      .ARSIZE(arsize), .ARBURST(arburst), .ARLOCK(arlock), .ARCACHE(arcache),
      .ARPROT(arprot), .ARQOS(arqos), .ARREGION(arregion), .ARVALID(arvalid),
      .ARREADY(arready), .RID(rid), .RDATA(rdata), .RRESP(rresp),
      .RLAST(rlast), .RVALID(rvalid), .RREADY(rready), .AWID(awid),
      .AWADDR(awaddr), .AWLEN(awlen), .AWSIZE(awsize), .AWBURST(awburst),
      .AWLOCK(awlock), .AWCACHE(awcache), .AWPROT(awprot), .AWQOS(awqos),
      .AWREGION(awregion), .AWVALID(awvalid), .AWREADY(awready),
      .WDATA(wdata), .WSTRB(wstrb), .WLAST(wlast), .WVALID(wvalid),
      .WREADY(wready), .BID(bid), .BRESP(bresp), .BVALID(bvalid),
      .BREADY(bready));

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
      rx_req_flit[`CHIE_REQ_FLIT_TGTID_RANGE] = HNI_NODEID_PARAM;
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
      input [11:0] dbid, input [1:0] data_id,
      input [`CHIE_DAT_FLIT_DATA_RANGE] data);
    begin
      @(negedge clk);
      rx_dat_flit = '0;
      rx_dat_flit[`CHIE_DAT_FLIT_OPCODE_RANGE] = `CHIE_NONCOPYBACKWRDATA;
      rx_dat_flit[`CHIE_DAT_FLIT_TXNID_RANGE] = dbid;
      rx_dat_flit[`CHIE_DAT_FLIT_DATAID_RANGE] = data_id;
      rx_dat_flit[`CHIE_DAT_FLIT_BE_RANGE] = '1;
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
        rdata = {96'h0, 32'h2000_0000 + beat};
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
      if (araddr != kReadAddress[31:0] || arlen != 8'd3 || arsize != 3'd4)
        fail("unexpected AXI read address transaction");
      rid = arid;
      fork send_axi_read_data(); join_none
    end
    if (!rst && awvalid && awready) begin
      if (awaddr != kWriteAddress[31:0] || awlen != 8'd3 || awsize != 3'd4)
        fail("unexpected AXI write address transaction");
      write_awid = awid;
    end
    if (!rst && wvalid && wready) begin
      write_data_beats = write_data_beats + 1;
      if (wstrb != '1) fail("AXI write strobe is not full width");
      if (wlast && write_data_beats != 4) fail("AXI WLAST occurred on wrong beat");
    end
    if (!rst && tx_dat_flit_v) begin
      read_data_flits = read_data_flits + 1;
      if (tx_dat_flit[`CHIE_DAT_FLIT_OPCODE_RANGE] != `CHIE_COMPDATA)
        fail("ReadNoSnp did not return CompData");
    end
    if (!rst && tx_rsp_flit_v &&
        tx_rsp_flit[`CHIE_RSP_FLIT_OPCODE_RANGE] == `CHIE_COMPDBIDRESP) begin
      saw_write_response = 1'b1;
      write_dbid = tx_rsp_flit[`CHIE_RSP_FLIT_DBID_RANGE];
    end
  end

  initial begin
    clk = 1'b0; rst = 1'b1; tx_link_active_ack = 1'b1;
    rx_link_active_req = 1'b0; rx_sactive = 1'b1;
    rx_req_flit_v = 1'b0; rx_req_flit = '0;
    rx_rsp_flit_v = 1'b0; rx_rsp_flit = '0;
    rx_dat_flit_v = 1'b0; rx_dat_flit = '0;
    arready = 1'b1; rid = '0; rdata = '0; rresp = '0; rlast = 1'b0; rvalid = 1'b0;
    awready = 1'b1; wready = 1'b1; bid = '0; bresp = '0; bvalid = 1'b0;
    error_count = 0; read_data_flits = 0; write_data_beats = 0;
    saw_write_response = 1'b0; write_dbid = '0; write_awid = '0;
    repeat (4) @(posedge clk);
    rst = 1'b0; rx_link_active_req = 1'b1;
    repeat (3) @(posedge clk);
    send_request(`CHIE_READNOSNP, kReadTxnId, kReadAddress);
    repeat (80) @(posedge clk);
    if (read_data_flits != 2) fail("ReadNoSnp did not return two CompData flits");
    send_request(`CHIE_WRITENOSNPFULL, kWriteTxnId, kWriteAddress);
    repeat (20) @(posedge clk);
    if (!saw_write_response) fail("WriteNoSnpFull did not return CompDBIDResp");
    send_write_data(write_dbid, 2'b00, 256'haaaa);
    send_write_data(write_dbid, 2'b10, 256'hbbbb);
    repeat (40) @(posedge clk);
    if (write_data_beats != 4) fail("WriteNoSnpFull did not issue four AXI data beats");
    @(negedge clk); bid = write_awid; bvalid = 1'b1;
    @(negedge clk); bvalid = 1'b0;
    repeat (10) @(posedge clk);
    if (error_count == 0) $display("HNI standalone test passed");
    else $display("HNI standalone test failed with %0d error(s)", error_count);
    $finish;
  end

  initial begin
    repeat (1000) @(posedge clk);
    fail("testbench timeout");
    $finish;
  end
endmodule
