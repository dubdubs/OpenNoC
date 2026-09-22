`timescale 1ns/1ps
`default_nettype none

`define CHECK(condition) \
  if (!(condition)) begin \
    $fatal(1, "CHECK failed: %s", `"condition`"); \
  end

module tb_axi2chi_chi_link;
  localparam int unsigned ReqFlitWidth = 16;
  localparam int unsigned RspFlitWidth = 12;
  localparam int unsigned DatFlitWidth = 24;
  localparam int unsigned ReqRxDepth = 2;
  localparam int unsigned RspRxDepth = 2;
  localparam int unsigned DatRxDepth = 2;

  logic clk = 1'b0;
  logic rst = 1'b1;
  logic core_txreq_valid_i;
  logic [ReqFlitWidth-1:0] core_txreq_flit_i;
  logic core_txreq_ready_o;
  logic core_txdat_valid_i;
  logic [DatFlitWidth-1:0] core_txdat_flit_i;
  logic core_txdat_ready_o;
  logic core_rxrsp_valid_o;
  logic [RspFlitWidth-1:0] core_rxrsp_flit_o;
  logic core_rxrsp_ready_i;
  logic core_rxdat_valid_o;
  logic [DatFlitWidth-1:0] core_rxdat_flit_o;
  logic core_rxdat_ready_i;
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

  axi2chi_chi_link #(
    .ReqFlitWidth(ReqFlitWidth),
    .RspFlitWidth(RspFlitWidth),
    .DatFlitWidth(DatFlitWidth),
    .ReqRxDepth(ReqRxDepth),
    .RspRxDepth(RspRxDepth),
    .DatRxDepth(DatRxDepth)
  ) dut (.*);

  always #5 clk = ~clk;

  initial begin
    core_txreq_valid_i = 1'b0;
    core_txreq_flit_i = '0;
    core_txdat_valid_i = 1'b0;
    core_txdat_flit_i = '0;
    core_rxrsp_ready_i = 1'b0;
    core_rxdat_ready_i = 1'b0;
    chi_txreq_lcrdv_i = 1'b0;
    chi_txdat_lcrdv_i = 1'b0;
    chi_txrsp_lcrdv_i = 1'b0;
    chi_rxrsp_flitv_i = 1'b0;
    chi_rxrsp_flit_i = '0;
    chi_rxdat_flitv_i = 1'b0;
    chi_rxdat_flit_i = '0;
    chi_txlinkactiveack_i = 1'b0;
    chi_rxlinkactivereq_i = 1'b0;

    @(negedge clk);
    rst = 1'b0;
    core_txreq_valid_i = 1'b1;
    core_txreq_flit_i = 16'ha111;
    #1;
    `CHECK(!core_txreq_ready_o);

    @(posedge clk);
    @(negedge clk);
    #1;
    `CHECK(chi_txlinkactivereq_o);
    chi_txlinkactiveack_i = 1'b1;
    @(posedge clk);
    @(negedge clk);
    #1;
    `CHECK(core_txreq_ready_o);
    @(posedge clk);

    @(negedge clk);
    core_txreq_valid_i = 1'b0;
    #1;
    `CHECK(chi_txreq_flitv_o);
    `CHECK(chi_txreq_flit_o == 16'ha111);
    @(posedge clk);

    @(negedge clk);
    #1;
    `CHECK(!chi_txreq_flitv_o);

    chi_rxrsp_flitv_i = 1'b1;
    chi_rxrsp_flit_i = 12'h5a1;
    @(posedge clk);
    @(negedge clk);
    chi_rxrsp_flitv_i = 1'b0;
    #1;
    `CHECK(core_rxrsp_valid_o);
    `CHECK(core_rxrsp_flit_o == 12'h5a1);
    core_rxrsp_ready_i = 1'b1;
    @(posedge clk);
    @(negedge clk);
    core_rxrsp_ready_i = 1'b0;
    #1;
    `CHECK(!core_rxrsp_valid_o);

    core_txdat_valid_i = 1'b1;
    core_txdat_flit_i = 24'hd0_0001;
    #1;
    `CHECK(core_txdat_ready_o);
    @(posedge clk);
    @(negedge clk);
    core_txdat_flit_i = 24'hd0_0002;
    @(posedge clk);
    @(negedge clk);
    #1;
    core_txdat_valid_i = 1'b0;
    #1;
    `CHECK(chi_txdat_flitv_o);
    `CHECK(chi_txdat_flit_o == 24'hd0_0002);

    chi_rxlinkactivereq_i = 1'b1;
    @(posedge clk);
    @(negedge clk);
    #1;
    `CHECK(chi_rxlinkactiveack_o);
    `CHECK(!chi_txrsp_flitv_o);
    `CHECK(chi_txrsp_flit_o == '0);

    $display("PASS: CHI link active and transport integration");
    $finish;
  end
endmodule

`default_nettype wire

`undef CHECK
