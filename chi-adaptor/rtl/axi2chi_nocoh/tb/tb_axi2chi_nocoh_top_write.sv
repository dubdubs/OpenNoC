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

    chi_rxrsp_flit_i = '0;
    // CompDBIDResp grants the DBID and completes the write before TXDAT.
    chi_rxrsp_flit_i[3:0] = 4'h2;
    chi_rxrsp_flit_i[24 +: ChiDbidWidth] = 8'h5a;
    chi_rxrsp_flit_i[36 +: 2] = 2'b00;
    chi_rxrsp_flitv_i = 1'b1;
    #1;
    `CHECK(chi_rxrsp_lcrdv_o);
    @(posedge clk);
    @(negedge clk);
    chi_rxrsp_flitv_i = 1'b0;

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
    `CHECK(s_axi_bresp == 2'b00);
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

    chi_rxrsp_flit_i = '0;
    chi_rxrsp_flit_i[3:0] = 4'h1;
    chi_rxrsp_flit_i[24 +: ChiDbidWidth] = 8'h33;
    chi_rxrsp_flit_i[36 +: 2] = 2'b00;
    chi_rxrsp_flitv_i = 1'b1;
    @(posedge clk);
    @(negedge clk);
    chi_rxrsp_flitv_i = 1'b0;

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

    chi_rxrsp_flit_i = '0;
    chi_rxrsp_flit_i[3:0] = 4'h3;
    chi_rxrsp_flit_i[36 +: 2] = 2'b00;
    chi_rxrsp_flitv_i = 1'b1;
    @(posedge clk);
    @(negedge clk);
    chi_rxrsp_flitv_i = 1'b0;

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

      chi_rxrsp_flit_i = '0;
      chi_rxrsp_flit_i[3:0] = 4'h1;
      chi_rxrsp_flit_i[8 +: ChiTxnidWidth] = write_txnid;
      chi_rxrsp_flit_i[24 +: ChiDbidWidth] = 8'h80 + beat;
      chi_rxrsp_flit_i[36 +: 2] = 2'b00;
      chi_rxrsp_flitv_i = 1'b1;
      #1;
      `CHECK(chi_rxrsp_lcrdv_o);
      @(posedge clk);
      @(negedge clk);
      chi_rxrsp_flitv_i = 1'b0;

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

      chi_rxrsp_flit_i = '0;
      chi_rxrsp_flit_i[3:0] = 4'h3;
      chi_rxrsp_flit_i[8 +: ChiTxnidWidth] = write_txnid;
      chi_rxrsp_flit_i[36 +: 2] = 2'b00;
      chi_rxrsp_flitv_i = 1'b1;
      #1;
      `CHECK(chi_rxrsp_lcrdv_o);
      @(posedge clk);
      @(negedge clk);
      chi_rxrsp_flitv_i = 1'b0;
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

      chi_rxrsp_flit_i = '0;
      chi_rxrsp_flit_i[3:0] = 4'h1;
      chi_rxrsp_flit_i[8 +: ChiTxnidWidth] = cross_write_txnid;
      chi_rxrsp_flit_i[24 +: ChiDbidWidth] = 8'ha0 + frag;
      chi_rxrsp_flit_i[36 +: 2] = 2'b00;
      chi_rxrsp_flitv_i = 1'b1;
      #1;
      `CHECK(chi_rxrsp_lcrdv_o);
      @(posedge clk);
      @(negedge clk);
      chi_rxrsp_flitv_i = 1'b0;

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

      chi_rxrsp_flit_i = '0;
      chi_rxrsp_flit_i[3:0] = 4'h3;
      chi_rxrsp_flit_i[8 +: ChiTxnidWidth] = cross_write_txnid;
      chi_rxrsp_flit_i[36 +: 2] = 2'b00;
      chi_rxrsp_flitv_i = 1'b1;
      #1;
      `CHECK(chi_rxrsp_lcrdv_o);
      @(posedge clk);
      @(negedge clk);
      chi_rxrsp_flitv_i = 1'b0;
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
    chi_rxrsp_flit_i = '0;
    chi_rxrsp_flit_i[3:0] = 4'h1;
    chi_rxrsp_flit_i[24 +: ChiDbidWidth] = 8'hb1;
    chi_rxrsp_flitv_i = 1'b1;
    #1;
    `CHECK(chi_rxrsp_lcrdv_o);
    @(posedge clk);
    @(negedge clk);
    chi_rxrsp_flitv_i = 1'b0;
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
    chi_rxrsp_flit_i = '0;
    chi_rxrsp_flit_i[3:0] = 4'h3;
    chi_rxrsp_flitv_i = 1'b1;
    #1;
    `CHECK(chi_rxrsp_lcrdv_o);
    @(posedge clk);
    @(negedge clk);
    chi_rxrsp_flitv_i = 1'b0;
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

    $display("PASS: top-level AXI write, including burst and cross-line fragments");
    $finish;
  end
endmodule

`default_nettype wire

`undef CHECK
