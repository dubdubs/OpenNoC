`timescale 1ns/1ps
`default_nettype none

`define CHECK(condition) \
  if (!(condition)) begin \
    $fatal(1, "CHECK failed: %s", `"condition`"); \
  end

module tb_axi2chi_nocoh_slave_admission;
  localparam int unsigned AxiAddrWidth = 64;
  localparam int unsigned AxiDataWidth = 128;
  localparam int unsigned AxiIdWidth = 4;
  localparam int unsigned AxlenWidth = 8;
  localparam int unsigned AxsizeWidth = 3;
  localparam int unsigned ParentEntries = 16;

  logic clk = 1'b0;
  logic rst = 1'b1;
  logic [AxiIdWidth-1:0] s_axi_awid;
  logic [AxiAddrWidth-1:0] s_axi_awaddr;
  logic [AxlenWidth-1:0] s_axi_awlen;
  logic [AxsizeWidth-1:0] s_axi_awsize;
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
  logic [AxlenWidth-1:0] s_axi_arlen;
  logic [AxsizeWidth-1:0] s_axi_arsize;
  logic [1:0] s_axi_arburst;
  logic s_axi_arvalid;
  logic s_axi_arready;
  logic [AxiIdWidth-1:0] s_axi_rid;
  logic [AxiDataWidth-1:0] s_axi_rdata;
  logic [1:0] s_axi_rresp;
  logic s_axi_rlast;
  logic s_axi_rvalid;
  logic s_axi_rready;
  logic rd_admit_valid_o;
  logic rd_admit_ready_i;
  logic [AxiIdWidth-1:0] rd_admit_id_o;
  logic [AxiAddrWidth-1:0] rd_admit_addr_o;
  logic [AxlenWidth-1:0] rd_admit_len_o;
  logic [AxsizeWidth-1:0] rd_admit_size_o;
  logic [1:0] rd_admit_burst_o;
  logic wr_admit_valid_o;
  logic wr_admit_ready_i;
  logic [$clog2(ParentEntries)-1:0] wr_admit_parent_idx_i;
  logic [AxiIdWidth-1:0] wr_admit_id_o;
  logic [AxiAddrWidth-1:0] wr_admit_addr_o;
  logic [AxlenWidth-1:0] wr_admit_len_o;
  logic [AxsizeWidth-1:0] wr_admit_size_o;
  logic [1:0] wr_admit_burst_o;
  logic wr_beat_valid_o;
  logic wr_beat_ready_i;
  logic [$clog2(ParentEntries)-1:0] wr_beat_parent_idx_o;
  logic [AxiDataWidth-1:0] wr_beat_data_o;
  logic [AxiDataWidth / 8-1:0] wr_beat_strb_o;
  logic wr_beat_last_o;
  logic wr_beat_error_o;
  logic rd_rsp_valid_i;
  logic rd_rsp_ready_o;
  logic [AxiIdWidth-1:0] rd_rsp_id_i;
  logic [AxiDataWidth-1:0] rd_rsp_data_i;
  logic [1:0] rd_rsp_resp_i;
  logic rd_rsp_last_i;
  logic wr_rsp_valid_i;
  logic wr_rsp_ready_o;
  logic [AxiIdWidth-1:0] wr_rsp_id_i;
  logic [1:0] wr_rsp_resp_i;

  axi2chi_nocoh_slave #(
    .AxiAddrWidth(AxiAddrWidth),
    .AxiDataWidth(AxiDataWidth),
    .AxiIdWidth(AxiIdWidth),
    .AxlenWidth(AxlenWidth),
    .AxsizeWidth(AxsizeWidth),
    .ParentEntries(ParentEntries)
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
    s_axi_wlast = 1'b1;
    s_axi_wvalid = 1'b0;
    s_axi_bready = 1'b0;
    s_axi_arid = '0;
    s_axi_araddr = '0;
    s_axi_arlen = '0;
    s_axi_arsize = '0;
    s_axi_arburst = '0;
    s_axi_arvalid = 1'b0;
    s_axi_rready = 1'b0;
    rd_admit_ready_i = 1'b0;
    wr_admit_ready_i = 1'b0;
    wr_admit_parent_idx_i = '0;
    wr_beat_ready_i = 1'b0;
    rd_rsp_valid_i = 1'b0;
    rd_rsp_id_i = '0;
    rd_rsp_data_i = '0;
    rd_rsp_resp_i = '0;
    rd_rsp_last_i = 1'b0;
    wr_rsp_valid_i = 1'b0;
    wr_rsp_id_i = '0;
    wr_rsp_resp_i = '0;

    #1;
    `CHECK(!s_axi_awready && !s_axi_arready);
    `CHECK(!wr_admit_valid_o && !rd_admit_valid_o);

    @(negedge clk);
    rst = 1'b0;
    s_axi_awid = 4'ha;
    s_axi_awaddr = 64'h0000_0000_0000_1040;
    s_axi_awlen = 8'd3;
    s_axi_awsize = 3'd4;
    s_axi_awburst = 2'b01;
    s_axi_awvalid = 1'b1;
    s_axi_arid = 4'h3;
    s_axi_araddr = 64'h0000_0000_0000_2080;
    s_axi_arlen = 8'd1;
    s_axi_arsize = 3'd3;
    s_axi_arburst = 2'b00;
    s_axi_arvalid = 1'b1;
    #1;
    `CHECK(!s_axi_awready && !s_axi_arready);
    `CHECK(wr_admit_valid_o && rd_admit_valid_o);
    `CHECK(wr_admit_id_o == s_axi_awid && wr_admit_addr_o == s_axi_awaddr);
    `CHECK(rd_admit_id_o == s_axi_arid && rd_admit_addr_o == s_axi_araddr);

    @(negedge clk);
    wr_admit_ready_i = 1'b1;
    #1;
    `CHECK(s_axi_awready && !s_axi_arready);
    `CHECK(wr_admit_len_o == 8'd3 && wr_admit_size_o == 3'd4);
    `CHECK(wr_admit_burst_o == 2'b01);

    @(posedge clk);
    #1;
    `CHECK(wr_admit_valid_o && s_axi_awready);

    @(negedge clk);
    s_axi_awvalid = 1'b0;
    s_axi_wdata = 128'h0000_0000_0000_0000_0000_0000_0000_0001;
    s_axi_wstrb = '1;
    s_axi_wlast = 1'b1;
    s_axi_wvalid = 1'b1;
    wr_beat_ready_i = 1'b0;
    #1;
    `CHECK(!s_axi_wready && wr_beat_valid_o);

    @(negedge clk);
    wr_beat_ready_i = 1'b1;
    #1;
    `CHECK(s_axi_wready && wr_beat_valid_o);
    `CHECK(wr_beat_parent_idx_o == '0 && wr_beat_data_o == s_axi_wdata);
    `CHECK(wr_beat_error_o);

    @(posedge clk);
    @(negedge clk);
    s_axi_wdata = 128'h0000_0000_0000_0000_0000_0000_0000_0002;
    s_axi_wlast = 1'b0;
    #1;
    `CHECK(s_axi_wready && wr_beat_parent_idx_o == '0);
    `CHECK(!wr_beat_error_o);

    @(posedge clk);
    @(negedge clk);
    s_axi_wdata = 128'h0000_0000_0000_0000_0000_0000_0000_0003;
    #1;
    `CHECK(s_axi_wready && wr_beat_parent_idx_o == '0);

    @(posedge clk);
    @(negedge clk);
    s_axi_wdata = 128'h0000_0000_0000_0000_0000_0000_0000_0004;
    s_axi_wlast = 1'b1;
    #1;
    `CHECK(s_axi_wready && wr_beat_parent_idx_o == '0);

    @(posedge clk);
    @(negedge clk);
    s_axi_wvalid = 1'b0;
    s_axi_wlast = 1'b0;
    #1;
    `CHECK(!s_axi_wready && !wr_beat_valid_o);

    @(negedge clk);
    wr_admit_ready_i = 1'b0;
    rd_admit_ready_i = 1'b1;
    #1;
    `CHECK(!s_axi_awready && s_axi_arready);
    `CHECK(rd_admit_len_o == 8'd1 && rd_admit_size_o == 3'd3);
    `CHECK(rd_admit_burst_o == 2'b00);

    @(posedge clk);
    #1;
    `CHECK(rd_admit_valid_o && s_axi_arready);

    @(negedge clk);
    s_axi_arvalid = 1'b0;
    #1;
    `CHECK(!wr_admit_valid_o && !rd_admit_valid_o);

    s_axi_arid = 4'he;
    s_axi_arlen = 8'd1;
    s_axi_arburst = 2'b10;
    s_axi_arvalid = 1'b1;
    #1;
    `CHECK(s_axi_arready && !rd_admit_valid_o);
    @(posedge clk);
    @(negedge clk);
    s_axi_arvalid = 1'b0;
    repeat (2) begin
      #1;
      `CHECK(s_axi_rvalid && s_axi_rid == 4'he && s_axi_rresp == 2'b11);
      s_axi_rready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      s_axi_rready = 1'b0;
    end
    #1;
    `CHECK(!s_axi_rvalid);

    s_axi_awid = 4'hd;
    s_axi_awlen = 8'd1;
    s_axi_awburst = 2'b10;
    s_axi_awvalid = 1'b1;
    #1;
    `CHECK(s_axi_awready && !wr_admit_valid_o);
    @(posedge clk);
    @(negedge clk);
    s_axi_awvalid = 1'b0;
    s_axi_wvalid = 1'b1;
    s_axi_wlast = 1'b0;
    #1;
    `CHECK(s_axi_wready && !wr_beat_valid_o);
    @(posedge clk);
    @(negedge clk);
    s_axi_wlast = 1'b1;
    #1;
    `CHECK(s_axi_wready && !wr_beat_valid_o);
    @(posedge clk);
    @(negedge clk);
    s_axi_wvalid = 1'b0;
    #1;
    `CHECK(s_axi_bvalid && s_axi_bid == 4'hd && s_axi_bresp == 2'b11);
    s_axi_bready = 1'b1;
    @(posedge clk);
    @(negedge clk);
    s_axi_bready = 1'b0;
    `CHECK(!s_axi_bvalid);
    $display("PASS: slave admission, W-order, and WRAP DECERR rejection");
    $finish;
  end
endmodule

`default_nettype wire

`undef CHECK
