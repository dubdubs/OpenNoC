// AXI-facing bridge frontend and AW-order state.

`default_nettype none

module axi2chi_nocoh_slave #(
  parameter int unsigned AxiAddrWidth = 64,
  parameter int unsigned AxiDataWidth = 128,
  parameter int unsigned AxiIdWidth = 4,
  parameter int unsigned AxlenWidth = 8,
  parameter int unsigned AxsizeWidth = 3,
  parameter int unsigned ParentEntries = 16
) (
  input  logic clk,
  input  logic rst,
  input  logic [AxiIdWidth-1:0] s_axi_awid,
  input  logic [AxiAddrWidth-1:0] s_axi_awaddr,
  input  logic [AxlenWidth-1:0] s_axi_awlen,
  input  logic [AxsizeWidth-1:0] s_axi_awsize,
  input  logic [1:0] s_axi_awburst,
  input  logic s_axi_awvalid,
  output logic s_axi_awready,
  input  logic [AxiDataWidth-1:0] s_axi_wdata,
  input  logic [AxiDataWidth / 8-1:0] s_axi_wstrb,
  input  logic s_axi_wlast,
  input  logic s_axi_wvalid,
  output logic s_axi_wready,
  output logic [AxiIdWidth-1:0] s_axi_bid,
  output logic [1:0] s_axi_bresp,
  output logic s_axi_bvalid,
  input  logic s_axi_bready,
  input  logic [AxiIdWidth-1:0] s_axi_arid,
  input  logic [AxiAddrWidth-1:0] s_axi_araddr,
  input  logic [AxlenWidth-1:0] s_axi_arlen,
  input  logic [AxsizeWidth-1:0] s_axi_arsize,
  input  logic [1:0] s_axi_arburst,
  input  logic s_axi_arvalid,
  output logic s_axi_arready,
  output logic [AxiIdWidth-1:0] s_axi_rid,
  output logic [AxiDataWidth-1:0] s_axi_rdata,
  output logic [1:0] s_axi_rresp,
  output logic s_axi_rlast,
  output logic s_axi_rvalid,
  input  logic s_axi_rready,
  output logic rd_admit_valid_o,
  input  logic rd_admit_ready_i,
  output logic [AxiIdWidth-1:0] rd_admit_id_o,
  output logic [AxiAddrWidth-1:0] rd_admit_addr_o,
  output logic [AxlenWidth-1:0] rd_admit_len_o,
  output logic [AxsizeWidth-1:0] rd_admit_size_o,
  output logic [1:0] rd_admit_burst_o,
  output logic wr_admit_valid_o,
  input  logic wr_admit_ready_i,
  input  logic [$clog2(ParentEntries)-1:0] wr_admit_parent_idx_i,
  output logic [AxiIdWidth-1:0] wr_admit_id_o,
  output logic [AxiAddrWidth-1:0] wr_admit_addr_o,
  output logic [AxlenWidth-1:0] wr_admit_len_o,
  output logic [AxsizeWidth-1:0] wr_admit_size_o,
  output logic [1:0] wr_admit_burst_o,
  output logic wr_beat_valid_o,
  input  logic wr_beat_ready_i,
  output logic [$clog2(ParentEntries)-1:0] wr_beat_parent_idx_o,
  output logic [AxiDataWidth-1:0] wr_beat_data_o,
  output logic [AxiDataWidth / 8-1:0] wr_beat_strb_o,
  output logic wr_beat_last_o,
  input  logic rd_rsp_valid_i,
  output logic rd_rsp_ready_o,
  input  logic [AxiIdWidth-1:0] rd_rsp_id_i,
  input  logic [AxiDataWidth-1:0] rd_rsp_data_i,
  input  logic [1:0] rd_rsp_resp_i,
  input  logic rd_rsp_last_i,
  input  logic wr_rsp_valid_i,
  output logic wr_rsp_ready_o,
  input  logic [AxiIdWidth-1:0] wr_rsp_id_i,
  input  logic [1:0] wr_rsp_resp_i
);

  localparam int unsigned ParentIndexWidth = $clog2(ParentEntries);
  typedef struct packed {
    logic valid;
    logic [ParentIndexWidth-1:0] parent_idx;
    logic [AxlenWidth-1:0] len;
  } aw_order_entry_t;

  aw_order_entry_t aw_order_q [ParentEntries];
  logic [ParentIndexWidth-1:0] aw_order_wr_ptr_q;
  logic [ParentIndexWidth-1:0] aw_order_rd_ptr_q;
  logic [ParentIndexWidth:0] aw_order_count_q;
  logic [AxlenWidth-1:0] active_w_beat_count_q;
  logic aw_order_push;
  logic aw_order_pop;
  logic wr_beat_fire;
  logic active_w_expected_last;

  // AR/AW admission is a combinational valid/ready boundary. The transaction
  // context owns the registers that capture a command on an admission fire.
  always_comb begin
    s_axi_awready = 1'b0;
    s_axi_wready = 1'b0;
    s_axi_bid = '0;
    s_axi_bresp = '0;
    s_axi_bvalid = 1'b0;
    s_axi_arready = 1'b0;
    s_axi_rid = '0;
    s_axi_rdata = '0;
    s_axi_rresp = '0;
    s_axi_rlast = 1'b0;
    s_axi_rvalid = 1'b0;

    rd_admit_valid_o = 1'b0;
    rd_admit_id_o = s_axi_arid;
    rd_admit_addr_o = s_axi_araddr;
    rd_admit_len_o = s_axi_arlen;
    rd_admit_size_o = s_axi_arsize;
    rd_admit_burst_o = s_axi_arburst;

    wr_admit_valid_o = 1'b0;
    wr_admit_id_o = s_axi_awid;
    wr_admit_addr_o = s_axi_awaddr;
    wr_admit_len_o = s_axi_awlen;
    wr_admit_size_o = s_axi_awsize;
    wr_admit_burst_o = s_axi_awburst;

    wr_beat_valid_o = 1'b0;
    wr_beat_parent_idx_o = '0;
    wr_beat_data_o = '0;
    wr_beat_strb_o = '0;
    wr_beat_last_o = 1'b0;
    rd_rsp_ready_o = 1'b0;
    wr_rsp_ready_o = 1'b0;

    active_w_expected_last =
        active_w_beat_count_q == aw_order_q[aw_order_rd_ptr_q].len;

    if (!rst) begin
      s_axi_awready = wr_admit_ready_i && (aw_order_count_q < ParentEntries);
      wr_admit_valid_o = s_axi_awvalid;
      s_axi_arready = rd_admit_ready_i;
      rd_admit_valid_o = s_axi_arvalid;

      if (aw_order_count_q != 0) begin
        s_axi_wready = wr_beat_ready_i;
        wr_beat_valid_o = s_axi_wvalid;
        wr_beat_parent_idx_o = aw_order_q[aw_order_rd_ptr_q].parent_idx;
        wr_beat_data_o = s_axi_wdata;
        wr_beat_strb_o = s_axi_wstrb;
        wr_beat_last_o = s_axi_wlast;
      end

      s_axi_rvalid = rd_rsp_valid_i;
      s_axi_rid = rd_rsp_id_i;
      s_axi_rdata = rd_rsp_data_i;
      s_axi_rresp = rd_rsp_resp_i;
      s_axi_rlast = rd_rsp_last_i;
      rd_rsp_ready_o = s_axi_rready;

      s_axi_bvalid = wr_rsp_valid_i;
      s_axi_bid = wr_rsp_id_i;
      s_axi_bresp = wr_rsp_resp_i;
      wr_rsp_ready_o = s_axi_bready;
    end

    aw_order_push = s_axi_awvalid && s_axi_awready;
    wr_beat_fire = s_axi_wvalid && s_axi_wready;
    aw_order_pop = wr_beat_fire && active_w_expected_last;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      aw_order_wr_ptr_q <= '0;
      aw_order_rd_ptr_q <= '0;
      aw_order_count_q <= '0;
      active_w_beat_count_q <= '0;
    end else begin
      if (aw_order_push) begin
        aw_order_q[aw_order_wr_ptr_q].valid <= 1'b1;
        aw_order_q[aw_order_wr_ptr_q].parent_idx <= wr_admit_parent_idx_i;
        aw_order_q[aw_order_wr_ptr_q].len <= s_axi_awlen;
        if (aw_order_wr_ptr_q == ParentEntries - 1) begin
          aw_order_wr_ptr_q <= '0;
        end else begin
          aw_order_wr_ptr_q <= aw_order_wr_ptr_q + 1'b1;
        end
      end

      if (aw_order_pop) begin
        aw_order_q[aw_order_rd_ptr_q].valid <= 1'b0;
        if (aw_order_rd_ptr_q == ParentEntries - 1) begin
          aw_order_rd_ptr_q <= '0;
        end else begin
          aw_order_rd_ptr_q <= aw_order_rd_ptr_q + 1'b1;
        end
      end

      case ({aw_order_push, aw_order_pop})
        2'b10: aw_order_count_q <= aw_order_count_q + 1'b1;
        2'b01: aw_order_count_q <= aw_order_count_q - 1'b1;
        default: aw_order_count_q <= aw_order_count_q;
      endcase

      if (wr_beat_fire) begin
        if (active_w_expected_last) begin
          active_w_beat_count_q <= '0;
        end else begin
          active_w_beat_count_q <= active_w_beat_count_q + 1'b1;
        end
      end
    end
  end

`ifndef SYNTHESIS
  // WLAST is checked against the accepted AWLEN-derived beat count.  The
  // assertion is intentionally gated by the W handshake so a stalled source
  // may hold either value stable without being reported as a protocol error.
  always_ff @(posedge clk) begin
    if (!rst) begin
      assert (!(wr_beat_fire && (s_axi_wlast != active_w_expected_last)))
      else $fatal(1, "AXI WLAST does not match the admitted AWLEN");
    end
  end
`endif

endmodule

`default_nettype wire
