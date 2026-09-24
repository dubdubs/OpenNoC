`timescale 1ns/1ps
`default_nettype none

`define CHECK(condition) \
  if (!(condition)) begin \
    $fatal(1, "CHECK failed: %s", `"condition`"); \
  end

module tb_axi2chi_nocoh_top_write;
  localparam int unsigned AxiAddrWidth = 32;
  localparam int unsigned AxiDataWidth = 64;
  localparam int unsigned AxiIdWidth = 2;
  localparam int unsigned ChiTxnidWidth = 8;
  localparam int unsigned ChiDbidWidth = 8;
  localparam int unsigned ChiDataWidth = 64;
  localparam int unsigned ReqFlitWidth = 96;
  localparam int unsigned RspFlitWidth = 64;
  localparam int unsigned DatFlitWidth = 256;
  localparam int unsigned ParentEntries = 4;
  localparam int unsigned ChildEntries = 4;

  logic clk = 1'b0;
  logic aresetn = 1'b0;
  logic [AxiIdWidth-1:0] s_axi_awid;
  logic [AxiAddrWidth-1:0] s_axi_awaddr;
  logic [7:0] s_axi_awlen;
  logic [2:0] s_axi_awsize;
  logic [1:0] s_axi_awburst;
  logic s_axi_awvalid;
  logic s_axi_awready;
  logic [AxiDataWidth-1:0] s_axi_wdata;
  logic [AxiDataWidth / 8-1:0] s_axi_wstrb;
  logic s_axi_wlast;
  logic s_axi_wvalid;
  logic s_axi_wready;
  logic [AxiIdWidth-1:0] s_axi_bid;
  logic [1:0] s_axi_bresp;
  logic s_axi_bvalid;
  logic s_axi_bready;
  logic [AxiIdWidth-1:0] s_axi_arid;
  logic [AxiAddrWidth-1:0] s_axi_araddr;
  logic [7:0] s_axi_arlen;
  logic [2:0] s_axi_arsize;
  logic [1:0] s_axi_arburst;
  logic s_axi_arvalid;
  logic s_axi_arready;
  logic [AxiIdWidth-1:0] s_axi_rid;
  logic [AxiDataWidth-1:0] s_axi_rdata;
  logic [1:0] s_axi_rresp;
  logic s_axi_rlast;
  logic s_axi_rvalid;
  logic s_axi_rready;
  logic chi_txreq_flitv_o;
  logic [ReqFlitWidth-1:0] chi_txreq_flit_o;
  logic chi_txreq_lcrdv_i;
  logic chi_txdat_flitv_o;
  logic [DatFlitWidth-1:0] chi_txdat_flit_o;
  logic chi_txdat_lcrdv_i;
  logic chi_txrsp_flitv_o;
  logic [RspFlitWidth-1:0] chi_txrsp_flit_o;
  logic chi_txrsp_lcrdv_i;
  logic chi_rxrsp_flitv_i;
  logic [RspFlitWidth-1:0] chi_rxrsp_flit_i;
  logic chi_rxrsp_lcrdv_o;
  logic chi_rxdat_flitv_i;
  logic [DatFlitWidth-1:0] chi_rxdat_flit_i;
  logic chi_rxdat_lcrdv_o;
  logic chi_txlinkactivereq_o;
  logic chi_txlinkactiveack_i;
  logic chi_rxlinkactivereq_i;
  logic chi_rxlinkactiveack_o;
  logic [ChiTxnidWidth-1:0] write_txnid;
  logic [ChiTxnidWidth-1:0] cross_write_txnid;
  logic [ChiTxnidWidth-1:0] same_id_txnid [0:2];
  logic [1:0] same_id_completion_order [0:2];
  logic same_id_responder_active;
  logic [2:0] same_id_req_seen;
  logic [$clog2(ParentEntries)-1:0] same_id_parent_idx [0:2];
  logic [RspFlitWidth-1:0] rsp_payload;

  task automatic send_rxrsp(input logic [RspFlitWidth-1:0] payload);
    begin
      chi_rxrsp_flit_i = payload;
      chi_rxrsp_flitv_i = 1'b1;
      do begin
        @(posedge clk);
      end while (!chi_rxrsp_lcrdv_o);
      @(negedge clk);
      chi_rxrsp_flitv_i = 1'b0;
    end
  endtask

  // LCRDV returns a credit; it is not a ready signal.  Keep the receiver's
  // two-entry model replenished while this scenario is active, and sample the
  // flit on the send edge to maintain an address-to-TxnID scoreboard.
  always @(negedge clk) begin
    if (same_id_responder_active) begin
      chi_txreq_lcrdv_i = 1'b1;
    end
  end

  always @(posedge clk) begin
    if (same_id_responder_active && chi_txreq_flitv_o) begin
      for (int unsigned txn = 0; txn < 3; txn++) begin
        if (chi_txreq_flit_o[32 +: AxiAddrWidth] ==
            32'h0000_3100 + (txn << 3)) begin
          `CHECK(!same_id_req_seen[txn]);
          same_id_txnid[txn] = chi_txreq_flit_o[16 +: ChiTxnidWidth];
          same_id_req_seen[txn] = 1'b1;
        end
      end
    end
  end


  axi2chi_nocoh_top #(
    .AxiAddrWidth(AxiAddrWidth),
    .AxiDataWidth(AxiDataWidth),
    .AxiIdWidth(AxiIdWidth),
    .ChiTxnidWidth(ChiTxnidWidth),
    .ChiDbidWidth(ChiDbidWidth),
    .ChiDataWidth(ChiDataWidth),
    .ParentEntries(ParentEntries),
    .ChildEntries(ChildEntries),
    .ReqFlitWidth(ReqFlitWidth),
    .RspFlitWidth(RspFlitWidth),
    .DatFlitWidth(DatFlitWidth)
  ) dut (.*);

  always #5 clk = ~clk;

  initial begin
    s_axi_awid = 2'd2;
    s_axi_awaddr = 32'h0000_2000;
    s_axi_awlen = 8'd0;
    s_axi_awsize = 3'd3;
    s_axi_awburst = 2'b01;
    s_axi_awvalid = 1'b0;
    s_axi_wdata = 64'h0123_4567_89ab_cdef;
    s_axi_wstrb = 8'hff;
    s_axi_wlast = 1'b1;
    s_axi_wvalid = 1'b0;
    s_axi_bready = 1'b0;
    s_axi_arid = '0;
    s_axi_araddr = '0;
    s_axi_arlen = '0;
    s_axi_arsize = '0;
    s_axi_arburst = '0;
    s_axi_arvalid = 1'b0;
    s_axi_rready = 1'b1;
    chi_txreq_lcrdv_i = 1'b0;
    chi_txdat_lcrdv_i = 1'b0;
    chi_txrsp_lcrdv_i = 1'b0;
    chi_rxrsp_flitv_i = 1'b0;
    chi_rxrsp_flit_i = '0;
    chi_rxdat_flitv_i = 1'b0;
    chi_rxdat_flit_i = '0;
    chi_txlinkactiveack_i = 1'b0;
    chi_rxlinkactivereq_i = 1'b1;
    same_id_responder_active = 1'b0;
    same_id_req_seen = '0;

    @(negedge clk);
    aresetn = 1'b1;
    @(posedge clk);
    @(negedge clk);
    chi_txlinkactiveack_i = 1'b1;
    @(posedge clk);
    @(negedge clk);

    s_axi_awvalid = 1'b1;
    #1;
    `CHECK(s_axi_awready);
    @(posedge clk);
    @(negedge clk);
    s_axi_awvalid = 1'b0;

    repeat (3) begin
      if (!chi_txreq_flitv_o) begin
        @(posedge clk);
        @(negedge clk);
      end
    end
    #1;
    `CHECK(chi_txreq_flitv_o);
    `CHECK(chi_txreq_flit_o[6:0] == 7'h18);
    `CHECK(chi_txreq_flit_o[32 +: AxiAddrWidth] == 32'h0000_2000);
    @(posedge clk);
    @(negedge clk);

    rsp_payload = '0;
    // An early CompDBIDResp still supplies DBID for TXDAT, but the AXI write
    // completes with SLVERR because completion preceded the data transfer.
    rsp_payload[3:0] = 4'h2;
    rsp_payload[24 +: ChiDbidWidth] = 8'h5a;
    rsp_payload[36 +: 2] = 2'b00;
    send_rxrsp(rsp_payload);

    s_axi_wvalid = 1'b1;
    repeat (3) begin
      if (!s_axi_wready) begin
        @(posedge clk);
        @(negedge clk);
      end
    end
    #1;
    `CHECK(s_axi_wready);
    @(posedge clk);
    @(negedge clk);
    s_axi_wvalid = 1'b0;

    repeat (3) begin
      if (!chi_txdat_flitv_o) begin
        @(posedge clk);
        @(negedge clk);
      end
    end
    #1;
    `CHECK(chi_txdat_flitv_o);
    `CHECK(chi_txdat_flit_o[24 +: ChiDbidWidth] == 8'h5a);
    `CHECK(chi_txdat_flit_o[128 +: ChiDataWidth] == 64'h0123_4567_89ab_cdef);
    @(posedge clk);
    @(negedge clk);

    repeat (4) begin
      if (!s_axi_bvalid) begin
        @(posedge clk);
        @(negedge clk);
      end
    end
    #1;
    `CHECK(s_axi_bvalid);
    `CHECK(s_axi_bid == 2'd2);
    `CHECK(s_axi_bresp == 2'b10);
    s_axi_bready = 1'b1;
    @(posedge clk);
    @(negedge clk);
    #1;
    `CHECK(!s_axi_bvalid);

    s_axi_awid = 2'd1;
    s_axi_awaddr = 32'h0000_2100;
    s_axi_wdata = 64'h1111_2222_3333_4444;
    s_axi_wstrb = 8'h0f;
    s_axi_bready = 1'b0;
    s_axi_awvalid = 1'b1;
    #1;
    `CHECK(s_axi_awready);
    @(posedge clk);
    @(negedge clk);
    s_axi_awvalid = 1'b0;

    repeat (3) begin
      if (!chi_txreq_flitv_o) begin
        @(posedge clk);
        @(negedge clk);
      end
    end
    #1;
    `CHECK(chi_txreq_flitv_o);
    `CHECK(chi_txreq_flit_o[32 +: AxiAddrWidth] == 32'h0000_2100);
    @(posedge clk);
    @(negedge clk);

    rsp_payload = '0;
    rsp_payload[3:0] = 4'h1;
    rsp_payload[24 +: ChiDbidWidth] = 8'h33;
    rsp_payload[36 +: 2] = 2'b00;
    send_rxrsp(rsp_payload);

    s_axi_wvalid = 1'b1;
    repeat (3) begin
      if (!s_axi_wready) begin
        @(posedge clk);
        @(negedge clk);
      end
    end
    #1;
    `CHECK(s_axi_wready);
    @(posedge clk);
    @(negedge clk);
    s_axi_wvalid = 1'b0;

    repeat (3) begin
      if (!chi_txdat_flitv_o) begin
        @(posedge clk);
        @(negedge clk);
      end
    end
    #1;
    `CHECK(chi_txdat_flitv_o);
    `CHECK(chi_txdat_flit_o[24 +: ChiDbidWidth] == 8'h33);
    `CHECK(chi_txdat_flit_o[128 +: ChiDataWidth] == 64'h1111_2222_3333_4444);
    @(posedge clk);
    @(negedge clk);

    rsp_payload = '0;
    rsp_payload[3:0] = 4'h3;
    rsp_payload[36 +: 2] = 2'b00;
    send_rxrsp(rsp_payload);

    repeat (4) begin
      if (!s_axi_bvalid) begin
        @(posedge clk);
        @(negedge clk);
      end
    end
    #1;
    `CHECK(s_axi_bvalid);
    `CHECK(s_axi_bid == 2'd1);
    `CHECK(s_axi_bresp == 2'b00);
    s_axi_bready = 1'b1;
    @(posedge clk);
    @(negedge clk);

    // Return the two credits consumed by the single-beat transactions above.
    chi_txreq_lcrdv_i = 1'b1;
    chi_txdat_lcrdv_i = 1'b1;
    repeat (2) begin
      @(posedge clk);
      @(negedge clk);
    end
    chi_txreq_lcrdv_i = 1'b0;
    chi_txdat_lcrdv_i = 1'b0;

    // A four-beat INCR burst creates and completes one CHI write child per
    // AXI beat.  Only the final child completion may produce AXI B.
    s_axi_awid = 2'd3;
    s_axi_awaddr = 32'h0000_3000;
    s_axi_awlen = 8'd3;
    s_axi_awsize = 3'd3;
    s_axi_awburst = 2'b01;
    s_axi_bready = 1'b0;
    s_axi_awvalid = 1'b1;
    #1;
    `CHECK(s_axi_awready);
    @(posedge clk);
    @(negedge clk);
    s_axi_awvalid = 1'b0;

    for (int unsigned beat = 0; beat < 4; beat++) begin
      repeat (8) begin
        if (!chi_txreq_flitv_o) begin
          @(posedge clk);
          @(negedge clk);
        end
      end
      #1;
      `CHECK(chi_txreq_flitv_o);
      write_txnid = chi_txreq_flit_o[16 +: ChiTxnidWidth];
      `CHECK(chi_txreq_flit_o[32 +: AxiAddrWidth] ==
          32'h0000_3000 + (beat << 3));
      @(posedge clk);
      @(negedge clk);
      chi_txreq_lcrdv_i = 1'b1;
      @(posedge clk);
      @(negedge clk);
      chi_txreq_lcrdv_i = 1'b0;

      rsp_payload = '0;
      rsp_payload[3:0] = 4'h1;
      rsp_payload[8 +: ChiTxnidWidth] = write_txnid;
      rsp_payload[24 +: ChiDbidWidth] = 8'h80 + beat;
      rsp_payload[36 +: 2] = 2'b00;
      send_rxrsp(rsp_payload);

      s_axi_wdata = 64'h4000_0000_0000_0000 + beat;
      s_axi_wstrb = 8'hff;
      s_axi_wlast = beat == 3;
      s_axi_wvalid = 1'b1;
      repeat (4) begin
        if (!s_axi_wready) begin
          @(posedge clk);
          @(negedge clk);
        end
      end
      #1;
      `CHECK(s_axi_wready);
      @(posedge clk);
      @(negedge clk);
      s_axi_wvalid = 1'b0;

      repeat (4) begin
        if (!chi_txdat_flitv_o) begin
          @(posedge clk);
          @(negedge clk);
        end
      end
      #1;
      `CHECK(chi_txdat_flitv_o);
      `CHECK(chi_txdat_flit_o[24 +: ChiDbidWidth] == 8'h80 + beat);
      `CHECK(chi_txdat_flit_o[128 +: ChiDataWidth] ==
          64'h4000_0000_0000_0000 + beat);
      @(posedge clk);
      @(negedge clk);
      chi_txdat_lcrdv_i = 1'b1;
      @(posedge clk);
      @(negedge clk);
      chi_txdat_lcrdv_i = 1'b0;

      rsp_payload = '0;
      rsp_payload[3:0] = 4'h3;
      rsp_payload[8 +: ChiTxnidWidth] = write_txnid;
      rsp_payload[36 +: 2] = 2'b00;
      send_rxrsp(rsp_payload);
      if (beat < 3) begin
        #1;
        `CHECK(!s_axi_bvalid);
      end
    end

    repeat (4) begin
      if (!s_axi_bvalid) begin
        @(posedge clk);
        @(negedge clk);
      end
    end
    #1;
    `CHECK(s_axi_bvalid);
    `CHECK(s_axi_bid == 2'd3);
    `CHECK(s_axi_bresp == 2'b00);
    s_axi_bready = 1'b1;
    @(posedge clk);
    @(negedge clk);

    // One 8-byte AXI beat at byte 60 of a cache line is split into two CHI
    // children.  Its W payload is accepted once, reused for fragment 1, and
    // AXI B is held off until both CHI Comp responses arrive.
    s_axi_awid = 2'd0;
    s_axi_awaddr = 32'h0000_303c;
    s_axi_awlen = '0;
    s_axi_awsize = 3'd3;
    s_axi_awburst = 2'b01;
    s_axi_wdata = 64'h8877_6655_4433_2211;
    s_axi_wstrb = 8'hff;
    s_axi_wlast = 1'b1;
    s_axi_bready = 1'b0;
    s_axi_awvalid = 1'b1;
    #1;
    `CHECK(s_axi_awready);
    @(posedge clk);
    @(negedge clk);
    s_axi_awvalid = 1'b0;

    for (int unsigned frag = 0; frag < 2; frag++) begin
      repeat (8) begin
        if (!chi_txreq_flitv_o) begin
          @(posedge clk);
          @(negedge clk);
        end
      end
      #1;
      `CHECK(chi_txreq_flitv_o);
      `CHECK(chi_txreq_flit_o[32 +: AxiAddrWidth] ==
          (frag == 0 ? 32'h0000_303c : 32'h0000_3040));
      cross_write_txnid = chi_txreq_flit_o[16 +: ChiTxnidWidth];
      chi_txreq_lcrdv_i = 1'b1;
      @(posedge clk);
      @(negedge clk);
      chi_txreq_lcrdv_i = 1'b0;

      rsp_payload = '0;
      rsp_payload[3:0] = 4'h1;
      rsp_payload[8 +: ChiTxnidWidth] = cross_write_txnid;
      rsp_payload[24 +: ChiDbidWidth] = 8'ha0 + frag;
      rsp_payload[36 +: 2] = 2'b00;
      send_rxrsp(rsp_payload);

      if (frag == 0) begin
        s_axi_wvalid = 1'b1;
        repeat (4) begin
          if (!s_axi_wready) begin
            @(posedge clk);
            @(negedge clk);
          end
        end
        #1;
        `CHECK(s_axi_wready);
        @(posedge clk);
        @(negedge clk);
        s_axi_wvalid = 1'b0;
      end

      repeat (4) begin
        if (!chi_txdat_flitv_o) begin
          @(posedge clk);
          @(negedge clk);
        end
      end
      #1;
      `CHECK(chi_txdat_flitv_o);
      `CHECK(chi_txdat_flit_o[24 +: ChiDbidWidth] == 8'ha0 + frag);
      `CHECK(chi_txdat_flit_o[128 +: ChiDataWidth] ==
          (frag == 0 ? 64'h0000_0000_4433_2211 : 64'h0000_0000_8877_6655));
      `CHECK(chi_txdat_flit_o[64 +: (ChiDataWidth / 8)] ==
          (frag == 0 ? 8'h0f : 8'h0f));
      chi_txdat_lcrdv_i = 1'b1;
      @(posedge clk);
      @(negedge clk);
      chi_txdat_lcrdv_i = 1'b0;

      rsp_payload = '0;
      rsp_payload[3:0] = 4'h3;
      rsp_payload[8 +: ChiTxnidWidth] = cross_write_txnid;
      rsp_payload[36 +: 2] = 2'b00;
      send_rxrsp(rsp_payload);
      if (frag == 0) begin
        #1;
        `CHECK(!s_axi_bvalid);
      end
    end

    repeat (4) begin
      if (!s_axi_bvalid) begin
        @(posedge clk);
        @(negedge clk);
      end
    end
    #1;
    `CHECK(s_axi_bvalid && s_axi_bid == 2'd0 && s_axi_bresp == 2'b00);
    s_axi_bready = 1'b1;
    @(posedge clk);
    @(negedge clk);

    // A narrow, unaligned write must preserve the byte strobes in its packed
    // child fragment rather than widening the transfer to the AXI bus width.
    s_axi_awid = 2'd1;
    s_axi_awaddr = 32'h0000_305d;
    s_axi_awlen = '0;
    s_axi_awsize = 3'd2;
    s_axi_awburst = 2'b01;
    s_axi_wdata = 64'h8877_6655_4433_2211;
    s_axi_wstrb = 8'h0d;
    s_axi_wlast = 1'b1;
    s_axi_bready = 1'b0;
    s_axi_awvalid = 1'b1;
    #1;
    `CHECK(s_axi_awready);
    @(posedge clk);
    @(negedge clk);
    s_axi_awvalid = 1'b0;
    repeat (4) begin
      if (!chi_txreq_flitv_o) begin
        @(posedge clk);
        @(negedge clk);
      end
    end
    #1;
    `CHECK(chi_txreq_flitv_o);
    `CHECK(chi_txreq_flit_o[32 +: AxiAddrWidth] == 32'h0000_305d);
    chi_txreq_lcrdv_i = 1'b1;
    @(posedge clk);
    @(negedge clk);
    chi_txreq_lcrdv_i = 1'b0;
    rsp_payload = '0;
    rsp_payload[3:0] = 4'h1;
    rsp_payload[24 +: ChiDbidWidth] = 8'hb1;
    send_rxrsp(rsp_payload);
    s_axi_wvalid = 1'b1;
    repeat (4) begin
      if (!s_axi_wready) begin
        @(posedge clk);
        @(negedge clk);
      end
    end
    #1;
    `CHECK(s_axi_wready);
    @(posedge clk);
    @(negedge clk);
    s_axi_wvalid = 1'b0;
    repeat (4) begin
      if (!chi_txdat_flitv_o) begin
        @(posedge clk);
        @(negedge clk);
      end
    end
    #1;
    `CHECK(chi_txdat_flitv_o);
    `CHECK(chi_txdat_flit_o[24 +: ChiDbidWidth] == 8'hb1);
    `CHECK(chi_txdat_flit_o[128 +: ChiDataWidth] == 64'h0000_0000_4433_2211);
    `CHECK(chi_txdat_flit_o[64 +: (ChiDataWidth / 8)] == 8'h0d);
    chi_txdat_lcrdv_i = 1'b1;
    @(posedge clk);
    @(negedge clk);
    chi_txdat_lcrdv_i = 1'b0;
    rsp_payload = '0;
    rsp_payload[3:0] = 4'h3;
    send_rxrsp(rsp_payload);
    repeat (4) begin
      if (!s_axi_bvalid) begin
        @(posedge clk);
        @(negedge clk);
      end
    end
    #1;
    `CHECK(s_axi_bvalid && s_axi_bid == 2'd1 && s_axi_bresp == 2'b00);
    s_axi_bready = 1'b1;
    @(posedge clk);
    @(negedge clk);

    // Three outstanding writes sharing one AXI ID may complete on CHI in any
    // order.  Their AXI B responses must still follow AW admission order.
    same_id_completion_order[0] = 2'd1;
    same_id_completion_order[1] = 2'd2;
    same_id_completion_order[2] = 2'd0;
    same_id_req_seen = '0;
    same_id_responder_active = 1'b1;
    s_axi_bready = 1'b0;
    for (int unsigned txn = 0; txn < 3; txn++) begin
      s_axi_awid = 2'd2;
      s_axi_awaddr = 32'h0000_3100 + (txn << 3);
      s_axi_awlen = '0;
      s_axi_awsize = 3'd3;
      s_axi_awburst = 2'b01;
      s_axi_awvalid = 1'b1;
      // Let the combinational AWREADY path settle before polling it.
      #1;
      repeat (8) begin
        if (!s_axi_awready) begin
          @(posedge clk);
          @(negedge clk);
        end
      end
      #1;
      `CHECK(s_axi_awready);
      @(posedge clk);
      // Deassert after the sampled handshake, before a following edge.
      #1;
      s_axi_awvalid = 1'b0;
      @(negedge clk);
      // Leave one complete idle cycle between AW commands.  This makes each
      // directed command a distinct AXI valid phase and prevents a zero-time
      // driver transition from being sampled as a second handshake.
      @(posedge clk);
      @(negedge clk);
    end
    for (int unsigned txn = 0; txn < 3; txn++) begin
      repeat (16) begin
        if (!same_id_req_seen[txn]) begin
          @(posedge clk);
          @(negedge clk);
        end
      end
      `CHECK(same_id_req_seen[txn]);

      rsp_payload = '0;
      rsp_payload[3:0] = 4'h1;
      rsp_payload[8 +: ChiTxnidWidth] = same_id_txnid[txn];
      rsp_payload[24 +: ChiDbidWidth] = 8'hc0 + txn;
      send_rxrsp(rsp_payload);

      s_axi_wdata = 64'h5000_0000_0000_0000 + txn;
      s_axi_wstrb = 8'hff;
      s_axi_wlast = 1'b1;
      s_axi_wvalid = 1'b1;
      repeat (8) begin
        if (!s_axi_wready) begin
          @(posedge clk);
          @(negedge clk);
        end
      end
      #1;
      `CHECK(s_axi_wready);
      @(posedge clk);
      @(negedge clk);
      s_axi_wvalid = 1'b0;
      repeat (64) begin
        if (!chi_txdat_flitv_o) begin
          @(posedge clk);
          @(negedge clk);
        end
      end
      #1;
      `CHECK(chi_txdat_flitv_o);
      `CHECK(chi_txdat_flit_o[24 +: ChiDbidWidth] == 8'hc0 + txn);
      chi_txdat_lcrdv_i = 1'b1;
      @(posedge clk);
      @(negedge clk);
      chi_txdat_lcrdv_i = 1'b0;
    end
    same_id_responder_active = 1'b0;
    chi_txreq_lcrdv_i = 1'b0;
    for (int unsigned ord = 0; ord < 3; ord++) begin
      chi_rxrsp_flit_i = '0;
      chi_rxrsp_flit_i[3:0] = 4'h3;
      chi_rxrsp_flit_i[8 +: ChiTxnidWidth] =
          same_id_txnid[same_id_completion_order[ord]];
      chi_rxrsp_flitv_i = 1'b1;
      #1;
      `CHECK(chi_rxrsp_lcrdv_o);
      @(posedge clk);
      @(negedge clk);
      chi_rxrsp_flitv_i = 1'b0;
      if (ord < 2) begin
        #1;
        `CHECK(!s_axi_bvalid);
      end
    end
    for (int unsigned txn = 0; txn < 3; txn++) begin
      repeat (8) begin
        if (!s_axi_bvalid) begin
          @(posedge clk);
          @(negedge clk);
        end
      end
      #1;
      `CHECK(s_axi_bvalid && s_axi_bid == 2'd2 && s_axi_bresp == 2'b00);
      s_axi_bready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      s_axi_bready = 1'b0;
    end

    $display("PASS: top-level AXI write, including burst and cross-line fragments");
    $finish;
  end
endmodule

`default_nettype wire

`undef CHECK
