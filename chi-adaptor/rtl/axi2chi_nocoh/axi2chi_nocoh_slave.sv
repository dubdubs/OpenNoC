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
  output logic wr_beat_error_o,
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
    logic local_error;
    logic [ParentIndexWidth-1:0] parent_idx;
    logic [AxiIdWidth-1:0] axi_id;
    logic [AxlenWidth-1:0] len;
    logic [AxsizeWidth-1:0] size;
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
  logic [AxiDataWidth / 8-1:0] active_w_legal_strb;
  logic local_rd_valid_q;
  logic [AxiIdWidth-1:0] local_rd_id_q;
  logic [AxlenWidth-1:0] local_rd_len_q;
  logic [AxlenWidth-1:0] local_rd_beat_q;
  logic local_b_valid_q;
  logic [AxiIdWidth-1:0] local_b_id_q;
  logic local_ar_fire;
  logic local_rd_fire;
  logic local_b_fire;
  logic local_wrap_read;
  logic local_wrap_write;

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
    wr_beat_error_o = 1'b0;
    rd_rsp_ready_o = 1'b0;
    wr_rsp_ready_o = 1'b0;

    active_w_expected_last =
        active_w_beat_count_q == aw_order_q[aw_order_rd_ptr_q].len;
    active_w_legal_strb = '0;
    for (int unsigned byte_idx = 0; byte_idx < AxiDataWidth / 8; byte_idx++) begin
      if (byte_idx < (1 << aw_order_q[aw_order_rd_ptr_q].size)) begin
        active_w_legal_strb[byte_idx] = 1'b1;
      end
    end
    local_wrap_read = s_axi_arburst == 2'b10;
    local_wrap_write = s_axi_awburst == 2'b10;

    if (!rst) begin
      s_axi_awready = (aw_order_count_q < ParentEntries) &&
          (local_wrap_write || wr_admit_ready_i);
      wr_admit_valid_o = s_axi_awvalid && !local_wrap_write;
      s_axi_arready = !local_rd_valid_q &&
          (local_wrap_read || rd_admit_ready_i);
      rd_admit_valid_o = s_axi_arvalid && !local_wrap_read;

      if (aw_order_count_q != 0) begin
        if (aw_order_q[aw_order_rd_ptr_q].local_error) begin
          s_axi_wready = 1'b1;
        end else begin
          s_axi_wready = wr_beat_ready_i;
          wr_beat_valid_o = s_axi_wvalid;
          wr_beat_parent_idx_o = aw_order_q[aw_order_rd_ptr_q].parent_idx;
          wr_beat_data_o = s_axi_wdata;
          wr_beat_strb_o = s_axi_wstrb;
          wr_beat_last_o = s_axi_wlast;
          wr_beat_error_o = (s_axi_wlast != active_w_expected_last) ||
              |(s_axi_wstrb & ~active_w_legal_strb);
        end
      end

      if (local_rd_valid_q) begin
        s_axi_rvalid = 1'b1;
        s_axi_rid = local_rd_id_q;
        s_axi_rresp = 2'b11;
        s_axi_rlast = local_rd_beat_q == local_rd_len_q;
      end else begin
        s_axi_rvalid = rd_rsp_valid_i;
        s_axi_rid = rd_rsp_id_i;
        s_axi_rdata = rd_rsp_data_i;
        s_axi_rresp = rd_rsp_resp_i;
        s_axi_rlast = rd_rsp_last_i;
        rd_rsp_ready_o = s_axi_rready;
      end

      if (local_b_valid_q) begin
        s_axi_bvalid = 1'b1;
        s_axi_bid = local_b_id_q;
        s_axi_bresp = 2'b11;
      end else begin
        s_axi_bvalid = wr_rsp_valid_i;
        s_axi_bid = wr_rsp_id_i;
        s_axi_bresp = wr_rsp_resp_i;
        wr_rsp_ready_o = s_axi_bready;
      end
    end

    aw_order_push = s_axi_awvalid && s_axi_awready;
    wr_beat_fire = s_axi_wvalid && s_axi_wready;
    aw_order_pop = wr_beat_fire && active_w_expected_last;
    local_ar_fire = s_axi_arvalid && s_axi_arready && local_wrap_read;
    local_rd_fire = local_rd_valid_q && s_axi_rready;
    local_b_fire = local_b_valid_q && s_axi_bready;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      aw_order_wr_ptr_q <= '0;
      aw_order_rd_ptr_q <= '0;
      aw_order_count_q <= '0;
      active_w_beat_count_q <= '0;
      local_rd_valid_q <= 1'b0;
      local_rd_id_q <= '0;
      local_rd_len_q <= '0;
      local_rd_beat_q <= '0;
      local_b_valid_q <= 1'b0;
      local_b_id_q <= '0;
    end else begin
      if (aw_order_push) begin
        aw_order_q[aw_order_wr_ptr_q].valid <= 1'b1;
        aw_order_q[aw_order_wr_ptr_q].local_error <= local_wrap_write;
        aw_order_q[aw_order_wr_ptr_q].parent_idx <= wr_admit_parent_idx_i;
        aw_order_q[aw_order_wr_ptr_q].axi_id <= s_axi_awid;
        aw_order_q[aw_order_wr_ptr_q].len <= s_axi_awlen;
        aw_order_q[aw_order_wr_ptr_q].size <= s_axi_awsize;
        if (aw_order_wr_ptr_q == ParentEntries - 1) begin
          aw_order_wr_ptr_q <= '0;
        end else begin
          aw_order_wr_ptr_q <= aw_order_wr_ptr_q + 1'b1;
        end
      end

      if (aw_order_pop) begin
        if (aw_order_q[aw_order_rd_ptr_q].local_error) begin
          local_b_valid_q <= 1'b1;
          local_b_id_q <= aw_order_q[aw_order_rd_ptr_q].axi_id;
        end
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

      if (local_ar_fire) begin
        local_rd_valid_q <= 1'b1;
        local_rd_id_q <= s_axi_arid;
        local_rd_len_q <= s_axi_arlen;
        local_rd_beat_q <= '0;
      end

      if (local_rd_fire) begin
        if (local_rd_beat_q == local_rd_len_q) begin
          local_rd_valid_q <= 1'b0;
        end else begin
          local_rd_beat_q <= local_rd_beat_q + 1'b1;
        end
      end

      if (local_b_fire) begin
        local_b_valid_q <= 1'b0;
      end
    end
  end

endmodule

`default_nettype wire
