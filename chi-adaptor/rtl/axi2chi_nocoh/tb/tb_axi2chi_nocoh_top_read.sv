`timescale 1ns/1ps
`default_nettype none

`define CHECK(condition) \
  if (!(condition)) begin \
    $fatal(1, "CHECK failed: %s", `"condition`"); \
  end

module tb_axi2chi_nocoh_top_read;
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
    s_axi_bready = 1'b1;
    s_axi_arid = 2'd1;
    s_axi_araddr = 32'h0000_1000;
    s_axi_arlen = 8'd3;
    s_axi_arsize = 3'd3;
    s_axi_arburst = 2'b01;
    s_axi_arvalid = 1'b0;
    s_axi_rready = 1'b0;
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
    #1;
    `CHECK(chi_txlinkactivereq_o);

    s_axi_arvalid = 1'b1;
    #1;
    `CHECK(s_axi_arready);
    @(posedge clk);
    @(negedge clk);
    s_axi_arvalid = 1'b0;
    for (int unsigned beat = 0; beat < 4; beat++) begin
      repeat (4) begin
        if (!chi_txreq_flitv_o) begin
          @(posedge clk);
          @(negedge clk);
        end
      end
      #1;
      `CHECK(chi_txreq_flitv_o);
      `CHECK(chi_txreq_flit_o[6:0] == 7'h04);
      `CHECK(chi_txreq_flit_o[32 +: AxiAddrWidth] ==
          32'h0000_1000 + (beat << 3));
      chi_txreq_lcrdv_i = 1'b1;
      @(posedge clk);
      @(negedge clk);
      chi_txreq_lcrdv_i = 1'b0;

      chi_rxdat_flit_i = '0;
      chi_rxdat_flit_i[26 +: 2] = 2'b00;
      chi_rxdat_flit_i[32 +: (ChiDataWidth / 8)] = 8'hff;
      chi_rxdat_flit_i[64 +: ChiDataWidth] = 64'hfeed_face_cafe_bee0 + beat;
      chi_rxdat_flitv_i = 1'b1;
      #1;
      `CHECK(chi_rxdat_lcrdv_o);
      @(posedge clk);
      @(negedge clk);
      chi_rxdat_flitv_i = 1'b0;
      s_axi_rready = 1'b0;
      repeat (4) begin
        if (!s_axi_rvalid) begin
          @(posedge clk);
          @(negedge clk);
        end
      end
      #1;
      `CHECK(s_axi_rvalid);
      `CHECK(s_axi_rid == 2'd1);
      `CHECK(s_axi_rdata == 64'hfeed_face_cafe_bee0 + beat);
      `CHECK(s_axi_rresp == 2'b00);
      `CHECK(s_axi_rlast == (beat == 3));
      s_axi_rready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      s_axi_rready = 1'b0;
    end

    s_axi_arid = 2'd3;
    s_axi_araddr = 32'h0000_1100;
    s_axi_arlen = 8'd0;
    s_axi_arvalid = 1'b1;
    s_axi_rready = 1'b0;
    #1;
    `CHECK(s_axi_arready);
    @(posedge clk);
    @(negedge clk);
    s_axi_arvalid = 1'b0;

    repeat (3) begin
      if (!chi_txreq_flitv_o) begin
        @(posedge clk);
        @(negedge clk);
      end
    end
    #1;
    `CHECK(chi_txreq_flitv_o);
    `CHECK(chi_txreq_flit_o[32 +: AxiAddrWidth] == 32'h0000_1100);
    chi_txreq_lcrdv_i = 1'b1;
    @(posedge clk);
    @(negedge clk);
    chi_txreq_lcrdv_i = 1'b0;

    chi_rxdat_flit_i = '0;
    chi_rxdat_flit_i[26 +: 2] = 2'b00;
    chi_rxdat_flit_i[32 +: (ChiDataWidth / 8)] = 8'hff;
    chi_rxdat_flit_i[64 +: ChiDataWidth] = 64'h1111_2222_3333_4444;
    chi_rxdat_flitv_i = 1'b1;
    #1;
    `CHECK(chi_rxdat_lcrdv_o);
    @(posedge clk);
    @(negedge clk);
    chi_rxdat_flitv_i = 1'b0;
    repeat (4) begin
      if (!s_axi_rvalid) begin
        @(posedge clk);
        @(negedge clk);
      end
    end
    #1;
    `CHECK(s_axi_rvalid);
    `CHECK(s_axi_rid == 2'd3);
    `CHECK(s_axi_rdata == 64'h1111_2222_3333_4444);
    s_axi_rready = 1'b1;
    @(posedge clk);
    @(negedge clk);

    // FIXED burst still allocates one child per AXI beat, but every CHI
    // request must retain the admitted AXI address.
    s_axi_arid = 2'd0;
    s_axi_araddr = 32'h0000_1200;
    s_axi_arlen = 8'd1;
    s_axi_arsize = 3'd3;
    s_axi_arburst = 2'b00;
    s_axi_arvalid = 1'b1;
    s_axi_rready = 1'b0;
    #1;
    `CHECK(s_axi_arready);
    @(posedge clk);
    @(negedge clk);
    s_axi_arvalid = 1'b0;

    for (int unsigned beat = 0; beat < 2; beat++) begin
      repeat (4) begin
        if (!chi_txreq_flitv_o) begin
          @(posedge clk);
          @(negedge clk);
        end
      end
      #1;
      `CHECK(chi_txreq_flitv_o);
      `CHECK(chi_txreq_flit_o[32 +: AxiAddrWidth] == 32'h0000_1200);
      chi_txreq_lcrdv_i = 1'b1;
      @(posedge clk);
      @(negedge clk);
      chi_txreq_lcrdv_i = 1'b0;

      chi_rxdat_flit_i = '0;
      chi_rxdat_flit_i[26 +: 2] = 2'b00;
      chi_rxdat_flit_i[32 +: (ChiDataWidth / 8)] = 8'hff;
      chi_rxdat_flit_i[64 +: ChiDataWidth] = 64'hf1ed_0000_0000_0000 + beat;
      chi_rxdat_flitv_i = 1'b1;
      #1;
      `CHECK(chi_rxdat_lcrdv_o);
      @(posedge clk);
      @(negedge clk);
      chi_rxdat_flitv_i = 1'b0;
      repeat (4) begin
        if (!s_axi_rvalid) begin
          @(posedge clk);
          @(negedge clk);
        end
      end
      #1;
      `CHECK(s_axi_rvalid);
      `CHECK(s_axi_rid == 2'd0);
      `CHECK(s_axi_rdata == 64'hf1ed_0000_0000_0000 + beat);
      `CHECK(s_axi_rlast == (beat == 1));
      s_axi_rready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      s_axi_rready = 1'b0;
    end

    $display("PASS: top-level AXI read including FIXED burst addressing");
    $finish;
  end
endmodule

`default_nettype wire

`undef CHECK
