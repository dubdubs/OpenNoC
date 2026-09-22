// Profile-neutral CHI transport owner skeleton.

`default_nettype none

module axi2chi_chi_link #(
  parameter int unsigned ReqFlitWidth = 131,
  parameter int unsigned RspFlitWidth = 73,
  parameter int unsigned DatFlitWidth = 406,
  parameter int unsigned ReqRxDepth = 2,
  parameter int unsigned RspRxDepth = 2,
  parameter int unsigned DatRxDepth = 2
) (
  input logic clk,
  input logic rst,
  input logic core_txreq_valid_i,
  input logic [ReqFlitWidth-1:0] core_txreq_flit_i,
  output logic core_txreq_ready_o,
  input logic core_txdat_valid_i,
  input logic [DatFlitWidth-1:0] core_txdat_flit_i,
  output logic core_txdat_ready_o,
  output logic core_rxrsp_valid_o,
  output logic [RspFlitWidth-1:0] core_rxrsp_flit_o,
  input logic core_rxrsp_ready_i,
  output logic core_rxdat_valid_o,
  output logic [DatFlitWidth-1:0] core_rxdat_flit_o,
  input logic core_rxdat_ready_i,
  output logic chi_txreq_flitv_o,
  output logic [ReqFlitWidth-1:0] chi_txreq_flit_o,
  input logic chi_txreq_lcrdv_i,
  output logic chi_txdat_flitv_o,
  output logic [DatFlitWidth-1:0] chi_txdat_flit_o,
  input logic chi_txdat_lcrdv_i,
  output logic chi_txrsp_flitv_o,
  output logic [RspFlitWidth-1:0] chi_txrsp_flit_o,
  input logic chi_txrsp_lcrdv_i,
  input logic chi_rxrsp_flitv_i,
  input logic [RspFlitWidth-1:0] chi_rxrsp_flit_i,
  output logic chi_rxrsp_lcrdv_o,
  input logic chi_rxdat_flitv_i,
  input logic [DatFlitWidth-1:0] chi_rxdat_flit_i,
  output logic chi_rxdat_lcrdv_o,
  output logic chi_txlinkactivereq_o,
  input logic chi_txlinkactiveack_i,
  input logic chi_rxlinkactivereq_i,
  output logic chi_rxlinkactiveack_o
);

  typedef enum logic [1:0] {
    kLinkReset,
    kLinkActivate,
    kLinkRun,
    kLinkDrain
  } link_state_t;

  link_state_t link_state_q;
  logic tx_link_active_req_q;
  logic rx_link_active_ack_q;
  logic link_run;
  logic txreq_credit_available;
  logic txdat_credit_available;
  logic txreq_send_fire;
  logic txdat_send_fire;
  logic core_txreq_ready_raw;
  logic core_txdat_ready_raw;
  logic txreq_producer_valid;
  logic txdat_producer_valid;
  logic [$clog2(ReqRxDepth + 1)-1:0] txreq_credit_count;
  logic [$clog2(DatRxDepth + 1)-1:0] txdat_credit_count;

  assign link_run = link_state_q == kLinkRun;
  assign txreq_producer_valid = core_txreq_valid_i && link_run;
  assign txdat_producer_valid = core_txdat_valid_i && link_run;
  assign core_txreq_ready_o = core_txreq_ready_raw && link_run;
  assign core_txdat_ready_o = core_txdat_ready_raw && link_run;
  assign chi_txrsp_flitv_o = 1'b0;
  assign chi_txrsp_flit_o = '0;
  assign chi_txlinkactivereq_o = tx_link_active_req_q;
  assign chi_rxlinkactiveack_o = rx_link_active_ack_q;

  axi2chi_chi_credit #(
    .MaxCredits(ReqRxDepth)
  ) txreq_credit (
    .clk(clk),
    .rst(rst),
    .credit_return_i(chi_txreq_lcrdv_i),
    .send_fire_i(txreq_send_fire),
    .credit_available_o(txreq_credit_available),
    .credit_count_o(txreq_credit_count)
  );

  axi2chi_chi_credit #(
    .MaxCredits(DatRxDepth)
  ) txdat_credit (
    .clk(clk),
    .rst(rst),
    .credit_return_i(chi_txdat_lcrdv_i),
    .send_fire_i(txdat_send_fire),
    .credit_available_o(txdat_credit_available),
    .credit_count_o(txdat_credit_count)
  );

  axi2chi_chi_txflit #(
    .FlitWidth(ReqFlitWidth),
    .Depth(ReqRxDepth)
  ) txreq_fifo (
    .clk(clk),
    .rst(rst),
    .producer_valid_i(txreq_producer_valid),
    .producer_flit_i(core_txreq_flit_i),
    .producer_ready_o(core_txreq_ready_raw),
    .credit_available_i(txreq_credit_available && link_run),
    .chi_flitv_o(chi_txreq_flitv_o),
    .chi_flit_o(chi_txreq_flit_o),
    .send_fire_o(txreq_send_fire)
  );

  axi2chi_chi_txflit #(
    .FlitWidth(DatFlitWidth),
    .Depth(DatRxDepth)
  ) txdat_fifo (
    .clk(clk),
    .rst(rst),
    .producer_valid_i(txdat_producer_valid),
    .producer_flit_i(core_txdat_flit_i),
    .producer_ready_o(core_txdat_ready_raw),
    .credit_available_i(txdat_credit_available && link_run),
    .chi_flitv_o(chi_txdat_flitv_o),
    .chi_flit_o(chi_txdat_flit_o),
    .send_fire_o(txdat_send_fire)
  );

  axi2chi_chi_rxflit #(
    .FlitWidth(RspFlitWidth),
    .Depth(RspRxDepth)
  ) rxrsp_fifo (
    .clk(clk),
    .rst(rst),
    .chi_flitv_i(chi_rxrsp_flitv_i),
    .chi_flit_i(chi_rxrsp_flit_i),
    .chi_lcrdv_o(chi_rxrsp_lcrdv_o),
    .core_valid_o(core_rxrsp_valid_o),
    .core_flit_o(core_rxrsp_flit_o),
    .core_ready_i(core_rxrsp_ready_i)
  );

  axi2chi_chi_rxflit #(
    .FlitWidth(DatFlitWidth),
    .Depth(DatRxDepth)
  ) rxdat_fifo (
    .clk(clk),
    .rst(rst),
    .chi_flitv_i(chi_rxdat_flitv_i),
    .chi_flit_i(chi_rxdat_flit_i),
    .chi_lcrdv_o(chi_rxdat_lcrdv_o),
    .core_valid_o(core_rxdat_valid_o),
    .core_flit_o(core_rxdat_flit_o),
    .core_ready_i(core_rxdat_ready_i)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      link_state_q <= kLinkReset;
      tx_link_active_req_q <= 1'b0;
      rx_link_active_ack_q <= 1'b0;
    end else begin
      rx_link_active_ack_q <= chi_rxlinkactivereq_i;
      unique case (link_state_q)
        kLinkReset: begin
          tx_link_active_req_q <= 1'b1;
          link_state_q <= kLinkActivate;
        end
        kLinkActivate: begin
          if (chi_txlinkactiveack_i) begin
            link_state_q <= kLinkRun;
          end
        end
        kLinkRun: begin
          tx_link_active_req_q <= 1'b1;
        end
        default: begin
          link_state_q <= kLinkReset;
        end
      endcase
    end
  end

endmodule

`default_nettype wire
