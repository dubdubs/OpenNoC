`timescale 1ns/1ps

`include "rni_param.v"
`include "rni_defines.v"
`include "axi4_defines.v"
`include "chie_defines.v"

// Focused Scheme-1 smoke test.  Unlike tb_rni, request classification uses
// opcode and the V2 {profile, direction, slot} TxnID contract.
module tb_param_rni_noncoherent;
  localparam integer ADDR_WIDTH = 44;
  localparam integer AXI_DATA_WIDTH = 128;
  localparam integer AXI_ID_WIDTH = 11;
  localparam integer REQUESTER_WIDTH = 8;
  // CHI field macros are parameterized and are used for the testbench flit
  // declarations as well as by the DUT.
  localparam integer CHIE_NID_WIDTH_PARAM = 11;
  localparam integer CHIE_REQ_RSVDC_WIDTH_PARAM = 0;
  localparam integer CHIE_DAT_RSVDC_WIDTH_PARAM = 0;
  localparam integer CHIE_REQ_ADDR_WIDTH_PARAM = 44;
  localparam integer CHIE_SNP_ADDR_WIDTH_PARAM = 41;
  localparam integer CHIE_PA_WIDTH_PARAM = 44;
  localparam integer CHIE_DATA_WIDTH_PARAM = 256;
  localparam integer CHIE_BE_WIDTH_PARAM = 32;
  localparam integer CHIE_POISON_WIDTH_PARAM = 0;
  localparam integer CHIE_DATACHECK_WIDTH_PARAM = 0;

  logic clk;
  logic rst;
  logic tx_link_active_ack;
  logic rx_link_active_req;
  wire tx_link_active_req;
  wire rx_link_active_ack;

  logic rx_rsp_flit_valid;
  logic [`CHIE_RSP_FLIT_RANGE] rx_rsp_flit;
  logic rx_dat_flit_valid;
  logic [`CHIE_DAT_FLIT_RANGE] rx_dat_flit;
  wire rx_rsp_lcrd_valid;
  wire rx_dat_lcrd_valid;
  wire tx_rsp_flit_pending;
  wire tx_rsp_flit_valid;
  wire [`CHIE_RSP_FLIT_RANGE] tx_rsp_flit;
  logic tx_rsp_lcrd_valid;
  wire tx_dat_flit_pending;
  wire tx_dat_flit_valid;
  wire [`CHIE_DAT_FLIT_RANGE] tx_dat_flit;
  logic tx_dat_lcrd_valid;
  wire tx_req_flit_pending;
  wire tx_req_flit_valid;
  wire [`CHIE_REQ_FLIT_RANGE] tx_req_flit;
  logic tx_req_lcrd_valid;

  logic [AXI_ID_WIDTH-1:0] awid;
  logic [ADDR_WIDTH-1:0] awaddr;
  logic [7:0] awlen;
  logic [2:0] awsize;
  logic [1:0] awburst;
  logic awlock;
  logic [3:0] awcache;
  logic [2:0] awprot;
  logic [3:0] awqos;
  logic [3:0] awregion;
  logic awvalid;
  wire awready;
  logic [AXI_DATA_WIDTH-1:0] wdata;
  logic [AXI_DATA_WIDTH / 8-1:0] wstrb;
  logic wlast;
  logic wvalid;
  wire wready;
  wire [AXI_ID_WIDTH-1:0] bid;
  wire [1:0] bresp;
  wire bvalid;
  logic bready;

  logic [AXI_ID_WIDTH-1:0] arid;
  logic [ADDR_WIDTH-1:0] araddr;
  logic [7:0] arlen;
  logic [2:0] arsize;
  logic [1:0] arburst;
  logic arlock;
  logic [3:0] arcache;
  logic [2:0] arprot;
  logic [3:0] arqos;
  logic [3:0] arregion;
  logic arvalid;
  wire arready;
  wire [AXI_ID_WIDTH-1:0] rid;
  wire [AXI_DATA_WIDTH-1:0] rdata;
  wire [1:0] rresp;
  wire rlast;
  wire rvalid;
  logic rready;

  logic [REQUESTER_WIDTH-1:0] arrequester;
  logic arnonsecure;
  logic arintentvalid;
  logic arcohintent;
  logic [REQUESTER_WIDTH-1:0] awrequester;
  logic awnonsecure;
  logic awintentvalid;
  logic awcohintent;
  logic policy_csr_secure;
  logic policy_csr_write;
  logic [1:0] policy_csr_index;
  logic [ADDR_WIDTH-1:0] policy_csr_base;
  logic [ADDR_WIDTH-1:0] policy_csr_limit;
  logic [REQUESTER_WIDTH-1:0] policy_csr_requester_value;
  logic [REQUESTER_WIDTH-1:0] policy_csr_requester_mask;
  logic [1:0] policy_csr_allowed_profiles;
  logic policy_csr_default_coherent;
  logic policy_csr_allow_intent;
  logic policy_csr_nonsecure_only;
  logic policy_csr_lock;
  logic policy_csr_commit;
  logic policy_csr_security_event_clear;
  wire policy_csr_locked;
  wire policy_csr_commit_busy;
  wire policy_csr_commit_error;
  wire policy_csr_security_event;
  wire [7:0] policy_epoch;

  logic read_seen;
  logic write_seen;
  logic txdat_seen;
  logic [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0] read_txnid;
  logic [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0] write_txnid;
  integer failure_count;

  rni #(
      .AXI4_PA_WIDTH_PARAM(ADDR_WIDTH),
      .AXI4_AXDATA_WIDTH_PARAM(AXI_DATA_WIDTH),
      .ENABLE_POLICY_CSR_PARAM(0),
      .DEFAULT_COHERENT_PARAM(0)
  ) dut (
      .CLK(clk), .RST(rst),
      .TXLINKACTIVEREQ(tx_link_active_req),
      .TXLINKACTIVEACK(tx_link_active_ack),
      .RXLINKACTIVEREQ(rx_link_active_req),
      .RXLINKACTIVEACK(rx_link_active_ack),
      .RXRSPFLITPEND(1'b1), .RXRSPFLITV(rx_rsp_flit_valid),
      .RXRSPFLIT(rx_rsp_flit), .RXRSPLCRDV(rx_rsp_lcrd_valid),
      .RXDATFLITPEND(1'b1), .RXDATFLITV(rx_dat_flit_valid),
      .RXDATFLIT(rx_dat_flit), .RXDATLCRDV(rx_dat_lcrd_valid),
      .TXRSPFLITPEND(tx_rsp_flit_pending), .TXRSPFLITV(tx_rsp_flit_valid),
      .TXRSPFLIT(tx_rsp_flit), .TXRSPLCRDV(tx_rsp_lcrd_valid),
      .TXDATFLITPEND(tx_dat_flit_pending), .TXDATFLITV(tx_dat_flit_valid),
      .TXDATFLIT(tx_dat_flit), .TXDATLCRDV(tx_dat_lcrd_valid),
      .TXREQFLITPEND(tx_req_flit_pending), .TXREQFLITV(tx_req_flit_valid),
      .TXREQFLIT(tx_req_flit), .TXREQLCRDV(tx_req_lcrd_valid),
      .AWID0(awid), .AWADDR0(awaddr), .AWLEN0(awlen), .AWSIZE0(awsize),
      .AWBURST0(awburst), .AWLOCK0(awlock), .AWCACHE0(awcache),
      .AWPROT0(awprot), .AWQOS0(awqos), .AWREGION0(awregion),
      .AWVALID0(awvalid), .AWREADY0(awready), .WDATA0(wdata),
      .WSTRB0(wstrb), .WLAST0(wlast), .WVALID0(wvalid), .WREADY0(wready),
      .BID0(bid), .BRESP0(bresp), .BVALID0(bvalid), .BREADY0(bready),
      .ARID0(arid), .ARADDR0(araddr), .ARLEN0(arlen), .ARSIZE0(arsize),
      .ARBURST0(arburst), .ARLOCK0(arlock), .ARCACHE0(arcache),
      .ARPROT0(arprot), .ARQOS0(arqos), .ARREGION0(arregion),
      .ARVALID0(arvalid), .ARREADY0(arready), .RID0(rid), .RDATA0(rdata),
      .RRESP0(rresp), .RLAST0(rlast), .RVALID0(rvalid), .RREADY0(rready),
      .ARREQUESTER0(arrequester), .ARNONSECURE0(arnonsecure),
      .ARINTENTVALID0(arintentvalid), .ARCOHINTENT0(arcohintent),
      .AWREQUESTER0(awrequester), .AWNONSECURE0(awnonsecure),
      .AWINTENTVALID0(awintentvalid), .AWCOHINTENT0(awcohintent),
      .POLICYCSRSECURE(policy_csr_secure), .POLICYCSRWRITE(policy_csr_write),
      .POLICYCSRINDEX(policy_csr_index), .POLICYCSRBASE(policy_csr_base),
      .POLICYCSRLIMIT(policy_csr_limit),
      .POLICYCSRREQUESTERVALUE(policy_csr_requester_value),
      .POLICYCSRREQUESTERMASK(policy_csr_requester_mask),
      .POLICYCSRALLOWEDPROFILES(policy_csr_allowed_profiles),
      .POLICYCSRDEFAULTCOHERENT(policy_csr_default_coherent),
      .POLICYCSRALLOWINTENT(policy_csr_allow_intent),
      .POLICYCSRNONSECUREONLY(policy_csr_nonsecure_only),
      .POLICYCSRLOCK(policy_csr_lock), .POLICYCSRCOMMIT(policy_csr_commit),
      .POLICYCSRSECURITYEVENTCLEAR(policy_csr_security_event_clear),
      .POLICYCSRLOCKED(policy_csr_locked),
      .POLICYCSRCOMMITBUSY(policy_csr_commit_busy),
      .POLICYCSRCOMMITERROR(policy_csr_commit_error),
      .POLICYCSRSECURITYEVENT(policy_csr_security_event),
      .POLICYEPOCH(policy_epoch)
  );

  always #5 clk = ~clk;
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      tx_link_active_ack <= 1'b0;
    end else begin
      tx_link_active_ack <= tx_link_active_req;
    end
  end

  always_ff @(posedge clk) begin
    tx_req_lcrd_valid <= !rst && tx_req_flit_valid;
    tx_dat_lcrd_valid <= !rst && tx_dat_flit_valid;
    tx_rsp_lcrd_valid <= !rst && tx_rsp_flit_valid;
    if (!rst && tx_req_flit_valid &&
        tx_req_flit[`CHIE_REQ_FLIT_OPCODE_RANGE] == `CHIE_READNOSNP) begin
      read_seen <= 1'b1;
      read_txnid <= tx_req_flit[`CHIE_REQ_FLIT_TXNID_RANGE];
      if (tx_req_flit[`CHIE_REQ_FLIT_TXNID_MSB] != 1'b0 ||
          tx_req_flit[`CHIE_REQ_FLIT_TXNID_MSB-1] != 1'b0) begin
        $error("ReadNoSnp TxnID=%h did not use non-coherent/read encoding",
               tx_req_flit[`CHIE_REQ_FLIT_TXNID_RANGE]);
        failure_count <= failure_count + 1;
      end
    end
    if (!rst && tx_req_flit_valid &&
        tx_req_flit[`CHIE_REQ_FLIT_OPCODE_RANGE] == `CHIE_WRITENOSNPPTL) begin
      write_seen <= 1'b1;
      write_txnid <= tx_req_flit[`CHIE_REQ_FLIT_TXNID_RANGE];
      if (tx_req_flit[`CHIE_REQ_FLIT_TXNID_MSB] != 1'b0 ||
          tx_req_flit[`CHIE_REQ_FLIT_TXNID_MSB-1] != 1'b1) begin
        $error("WriteNoSnpPtl TxnID=%h did not use non-coherent/write encoding",
               tx_req_flit[`CHIE_REQ_FLIT_TXNID_RANGE]);
        failure_count <= failure_count + 1;
      end
    end
    if (!rst && tx_dat_flit_valid) begin
      txdat_seen <= 1'b1;
    end
  end

  task automatic send_compdata(
      input logic [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0] txnid,
      input logic [1:0] dataid,
      input logic [255:0] data
  );
    begin
      @(negedge clk);
      rx_dat_flit = '0;
      rx_dat_flit[`CHIE_DAT_FLIT_TGTID_RANGE] = 11'd6;
      rx_dat_flit[`CHIE_DAT_FLIT_SRCID_RANGE] = 11'd0;
      rx_dat_flit[`CHIE_DAT_FLIT_TXNID_RANGE] = txnid;
      rx_dat_flit[`CHIE_DAT_FLIT_OPCODE_RANGE] = `CHIE_COMPDATA;
      rx_dat_flit[`CHIE_DAT_FLIT_DATAID_RANGE] = dataid;
      rx_dat_flit[`CHIE_DAT_FLIT_BE_RANGE] = {`CHIE_DAT_FLIT_BE_WIDTH{1'b1}};
      rx_dat_flit[`CHIE_DAT_FLIT_DATA_RANGE] = data;
      rx_dat_flit_valid = 1'b1;
      @(negedge clk);
      rx_dat_flit_valid = 1'b0;
    end
  endtask

  task automatic send_rsp(
      input logic [`CHIE_RSP_FLIT_TXNID_WIDTH-1:0] txnid,
      input logic [`CHIE_RSP_FLIT_DBID_WIDTH-1:0] dbid,
      input logic [`CHIE_RSP_FLIT_OPCODE_WIDTH-1:0] opcode
  );
    begin
      @(negedge clk);
      rx_rsp_flit = '0;
      rx_rsp_flit[`CHIE_RSP_FLIT_TGTID_RANGE] = 11'd6;
      rx_rsp_flit[`CHIE_RSP_FLIT_SRCID_RANGE] = 11'd0;
      rx_rsp_flit[`CHIE_RSP_FLIT_TXNID_RANGE] = txnid;
      rx_rsp_flit[`CHIE_RSP_FLIT_DBID_RANGE] = dbid;
      rx_rsp_flit[`CHIE_RSP_FLIT_OPCODE_RANGE] = opcode;
      rx_rsp_flit_valid = 1'b1;
      @(negedge clk);
      rx_rsp_flit_valid = 1'b0;
    end
  endtask

  task automatic issue_read(
      input logic [AXI_ID_WIDTH-1:0] id,
      input logic [ADDR_WIDTH-1:0] addr,
      input logic [2:0] size,
      input logic [1:0] burst
  );
    begin
      @(negedge clk);
      arid = id;
      araddr = addr;
      arlen = 8'd0;
      arsize = size;
      arburst = burst;
      arcache = 4'b1111;
      arvalid = 1'b1;
      do @(posedge clk); while (!arready);
      @(negedge clk);
      arvalid = 1'b0;
    end
  endtask

  task automatic issue_write(
      input logic [AXI_ID_WIDTH-1:0] id,
      input logic [ADDR_WIDTH-1:0] addr,
      input logic [2:0] size,
      input logic [1:0] burst
  );
    begin
      @(negedge clk);
      awid = id;
      awaddr = addr;
      awlen = 8'd0;
      awsize = size;
      awburst = burst;
      awcache = 4'b1111;
      awvalid = 1'b1;
      do @(posedge clk); while (!awready);
      @(negedge clk);
      awvalid = 1'b0;
      wdata = 128'h0123_4567_89ab_cdef_0011_2233_4455_6677;
      wstrb = {AXI_DATA_WIDTH / 8{1'b1}};
      wlast = 1'b1;
      wvalid = 1'b1;
      do @(posedge clk); while (!wready);
      @(negedge clk);
      wvalid = 1'b0;
    end
  endtask

  initial begin
    clk = 1'b0;
    rst = 1'b1;
    rx_link_active_req = 1'b1;
    rx_rsp_flit_valid = 1'b0;
    rx_dat_flit_valid = 1'b0;
    tx_req_lcrd_valid = 1'b0;
    tx_dat_lcrd_valid = 1'b0;
    tx_rsp_lcrd_valid = 1'b0;
    awvalid = 1'b0;
    wvalid = 1'b0;
    arvalid = 1'b0;
    bready = 1'b1;
    rready = 1'b1;
    awlock = 1'b0;
    awprot = '0;
    awqos = '0;
    awregion = '0;
    arlock = 1'b0;
    arprot = '0;
    arqos = '0;
    arregion = '0;
    arrequester = '0;
    arnonsecure = 1'b0;
    arintentvalid = 1'b0;
    arcohintent = 1'b0;
    awrequester = '0;
    awnonsecure = 1'b0;
    awintentvalid = 1'b0;
    awcohintent = 1'b0;
    policy_csr_secure = 1'b0;
    policy_csr_write = 1'b0;
    policy_csr_index = '0;
    policy_csr_base = '0;
    policy_csr_limit = '0;
    policy_csr_requester_value = '0;
    policy_csr_requester_mask = '0;
    policy_csr_allowed_profiles = '0;
    policy_csr_default_coherent = 1'b0;
    policy_csr_allow_intent = 1'b0;
    policy_csr_nonsecure_only = 1'b0;
    policy_csr_lock = 1'b0;
    policy_csr_commit = 1'b0;
    policy_csr_security_event_clear = 1'b0;
    read_seen = 1'b0;
    write_seen = 1'b0;
    txdat_seen = 1'b0;
    read_txnid = '0;
    write_txnid = '0;
    failure_count = 0;

    repeat (8) @(posedge clk);
    rst = 1'b0;
    repeat (4) @(posedge clk);
    tx_req_lcrd_valid = 1'b1;
    tx_dat_lcrd_valid = 1'b1;
    tx_rsp_lcrd_valid = 1'b1;
    repeat (4) @(posedge clk);
    tx_req_lcrd_valid = 1'b0;
    tx_dat_lcrd_valid = 1'b0;
    tx_rsp_lcrd_valid = 1'b0;

    // Exercise aligned INCR, unaligned INCR, and FIXED AXI attributes.  The
    // old tb_rni has a much larger random-like catalogue; these cases retain
    // the essential request/response path while checking the Scheme-1 tags.
    issue_read(11'h011, 44'h0000_0000_1000, 3'd4, 2'b01);
    wait (read_seen);
    send_compdata(read_txnid, 2'b00, 256'h00112233445566778899aabbccddeeff);
    send_compdata(read_txnid, 2'b10, 256'hffeeddccbbaa99887766554433221100);
    wait (rvalid && rlast);
    if (rid != 11'h011 || rresp != 2'b00) begin
      $error("AXI read completion mismatch: RID=%h RRESP=%h", rid, rresp);
      failure_count = failure_count + 1;
    end

    read_seen = 1'b0;
    issue_read(11'h012, 44'h0000_0000_1041, 3'd2, 2'b01);
    wait (read_seen);
    send_compdata(read_txnid, 2'b00, 256'h0123456789abcdef0011223344556677);
    send_compdata(read_txnid, 2'b10, 256'h7766554433221100fedcba9876543210);
    wait (rvalid && rlast);
    if (rid != 11'h012 || rresp != 2'b00) begin
      $error("Unaligned AXI read completion mismatch: RID=%h RRESP=%h", rid, rresp);
      failure_count = failure_count + 1;
    end

    read_seen = 1'b0;
    issue_read(11'h013, 44'h0000_0000_1080, 3'd4, 2'b00);
    wait (read_seen);
    send_compdata(read_txnid, 2'b00, 256'h11111111111111112222222222222222);
    send_compdata(read_txnid, 2'b10, 256'h33333333333333334444444444444444);
    wait (rvalid && rlast);

    issue_write(11'h022, 44'h0000_0000_2000, 3'd4, 2'b01);
    wait (write_seen);
    send_rsp(write_txnid, 12'h155, `CHIE_DBIDRESP);
    wait (txdat_seen);
    send_rsp(write_txnid, 12'h155, `CHIE_COMP);
    wait (bvalid);
    if (bid != 11'h022 || bresp != 2'b00) begin
      $error("AXI write completion mismatch: BID=%h BRESP=%h", bid, bresp);
      failure_count = failure_count + 1;
    end

    write_seen = 1'b0;
    txdat_seen = 1'b0;
    issue_write(11'h023, 44'h0000_0000_2040, 3'd2, 2'b00);
    wait (write_seen);
    send_rsp(write_txnid, 12'h156, `CHIE_DBIDRESP);
    wait (txdat_seen);
    send_rsp(write_txnid, 12'h156, `CHIE_COMP);
    wait (bvalid);
    if (bid != 11'h023 || bresp != 2'b00) begin
      $error("FIXED AXI write completion mismatch: BID=%h BRESP=%h", bid, bresp);
      failure_count = failure_count + 1;
    end

    repeat (4) @(posedge clk);
    if (failure_count != 0) begin
      $fatal(1, "tb_param_rni_noncoherent failed with %0d mismatches", failure_count);
    end
    $display("tb_param_rni_noncoherent PASS: ReadNoSnp/WriteNoSnpPtl, DBID/DAT/Comp, V2 TxnID");
    $finish;
  end

  initial begin
    #20000;
    $fatal(1, "tb_param_rni_noncoherent timeout");
  end
endmodule
