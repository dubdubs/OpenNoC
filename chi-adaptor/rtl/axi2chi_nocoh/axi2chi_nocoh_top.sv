// AXI-to-CHI non-coherent bridge top-level integration shell.

`default_nettype none

module axi2chi_nocoh_top #(
  parameter int unsigned AxiAddrWidth = 64,
  parameter int unsigned AxiDataWidth = 128,
  parameter int unsigned AxiIdWidth = 4,
  parameter int unsigned AxlenWidth = 8,
  parameter int unsigned AxsizeWidth = 3,
  parameter int unsigned ChiNidWidth = 7,
  parameter int unsigned ChiTxnidWidth = 12,
  parameter int unsigned ChiDbidWidth = 12,
  parameter int unsigned ChiDataWidth = 256,
  parameter int unsigned CacheLineBytes = 64,
  parameter int unsigned DataIdWidth =
      ((CacheLineBytes / (ChiDataWidth / 8)) > 1) ?
          $clog2(CacheLineBytes / (ChiDataWidth / 8)) : 1,
  parameter int unsigned ParentEntries = 16,
  parameter int unsigned ChildEntries = 16,
  parameter int unsigned ReqFlitWidth = 131,
  parameter int unsigned RspFlitWidth = 73,
  parameter int unsigned DatFlitWidth = 406
  ,parameter bit EnableWriteNoSnpFull = 1'b0
) (
  input  logic                         clk,
  input  logic                         aresetn,

  input  logic [AxiIdWidth-1:0]        s_axi_awid,
  input  logic [AxiAddrWidth-1:0]      s_axi_awaddr,
  input  logic [AxlenWidth-1:0]        s_axi_awlen,
  input  logic [AxsizeWidth-1:0]       s_axi_awsize,
  input  logic [1:0]                   s_axi_awburst,
  input  logic                         s_axi_awvalid,
  output logic                         s_axi_awready,
  input  logic [AxiDataWidth-1:0]      s_axi_wdata,
  input  logic [AxiDataWidth / 8-1:0]  s_axi_wstrb,
  input  logic                         s_axi_wlast,
  input  logic                         s_axi_wvalid,
  output logic                         s_axi_wready,
  output logic [AxiIdWidth-1:0]        s_axi_bid,
  output logic [1:0]                   s_axi_bresp,
  output logic                         s_axi_bvalid,
  input  logic                         s_axi_bready,
  input  logic [AxiIdWidth-1:0]        s_axi_arid,
  input  logic [AxiAddrWidth-1:0]      s_axi_araddr,
  input  logic [AxlenWidth-1:0]        s_axi_arlen,
  input  logic [AxsizeWidth-1:0]       s_axi_arsize,
  input  logic [1:0]                   s_axi_arburst,
  input  logic                         s_axi_arvalid,
  output logic                         s_axi_arready,
  output logic [AxiIdWidth-1:0]        s_axi_rid,
  output logic [AxiDataWidth-1:0]      s_axi_rdata,
  output logic [1:0]                   s_axi_rresp,
  output logic                         s_axi_rlast,
  output logic                         s_axi_rvalid,
  input  logic                         s_axi_rready,

  output logic                         chi_txreq_flitv_o,
  output logic [ReqFlitWidth-1:0]      chi_txreq_flit_o,
  input  logic                         chi_txreq_lcrdv_i,
  output logic                         chi_txdat_flitv_o,
  output logic [DatFlitWidth-1:0]      chi_txdat_flit_o,
  input  logic                         chi_txdat_lcrdv_i,
  output logic                         chi_txrsp_flitv_o,
  output logic [RspFlitWidth-1:0]      chi_txrsp_flit_o,
  input  logic                         chi_txrsp_lcrdv_i,
  input  logic                         chi_rxrsp_flitv_i,
  input  logic [RspFlitWidth-1:0]      chi_rxrsp_flit_i,
  output logic                         chi_rxrsp_lcrdv_o,
  input  logic                         chi_rxdat_flitv_i,
  input  logic [DatFlitWidth-1:0]      chi_rxdat_flit_i,
  output logic                         chi_rxdat_lcrdv_o,
  output logic                         chi_txlinkactivereq_o,
  input  logic                         chi_txlinkactiveack_i,
  input  logic                         chi_rxlinkactivereq_i,
  output logic                         chi_rxlinkactiveack_o
);

  localparam int unsigned AxiStrbWidth = AxiDataWidth / 8;
  localparam int unsigned ChiBeWidth = ChiDataWidth / 8;
  localparam int unsigned ParentIndexWidth = $clog2(ParentEntries);
  localparam int unsigned ChildIndexWidth = $clog2(ChildEntries);
  localparam int unsigned RxdatDataIdLsb = 24;
  localparam int unsigned RxdatRespLsb = RxdatDataIdLsb + DataIdWidth;

`ifndef SYNTHESIS
  // Elaboration-time profile checks.  These guard widths used by the
  // fragment scheduler and flit field slices; no runtime datapath state is
  // created by this block.
  initial begin
    if (AxiDataWidth == 0 || AxiDataWidth % 8 != 0) begin
      $fatal(1, "AxiDataWidth must be a non-zero multiple of 8");
    end
    if (ChiDataWidth == 0 || ChiDataWidth % 8 != 0) begin
      $fatal(1, "ChiDataWidth must be a non-zero multiple of 8");
    end
    if (CacheLineBytes == 0 || (CacheLineBytes & (CacheLineBytes - 1)) != 0) begin
      $fatal(1, "CacheLineBytes must be a power of two");
    end
    if (CacheLineBytes % (ChiDataWidth / 8) != 0) begin
      $fatal(1, "CacheLineBytes must be an integer number of CHI data segments");
    end
    if (ParentEntries < 2 || ChildEntries < 2) begin
      $fatal(1, "ParentEntries and ChildEntries must both be at least 2");
    end
    if (ReqFlitWidth < 32 + AxiAddrWidth ||
        DatFlitWidth < 64 + ChiDataWidth ||
        DatFlitWidth < 32 + ChiDataWidth / 8 ||
        DatFlitWidth < RxdatRespLsb + 2) begin
      $fatal(1, "CHI flit widths do not cover configured payload fields");
    end
  end
`endif

  // Canonical internal boundaries are declared here for the later integration step.
  logic rst;
  logic core_txreq_valid;
  logic [ReqFlitWidth-1:0] core_txreq_payload;
  logic core_txreq_ready;
  logic core_txdat_valid;
  logic [DatFlitWidth-1:0] core_txdat_payload;
  logic core_txdat_ready;
  logic core_rxrsp_valid;
  logic [RspFlitWidth-1:0] core_rxrsp_payload;
  logic core_rxrsp_ready;
  logic rd_core_rxrsp_ready;
  logic wr_core_rxrsp_ready;
  logic core_rxdat_valid;
  logic [DatFlitWidth-1:0] core_rxdat_payload;
  logic core_rxdat_ready;
  logic slave_rd_admit_valid;
  logic slave_rd_admit_ready;
  logic [AxiIdWidth-1:0] slave_rd_admit_id;
  logic [AxiAddrWidth-1:0] slave_rd_admit_addr;
  logic [AxlenWidth-1:0] slave_rd_admit_len;
  logic [AxsizeWidth-1:0] slave_rd_admit_size;
  logic [1:0] slave_rd_admit_burst;
  logic slave_wr_admit_valid;
  logic [AxiIdWidth-1:0] slave_wr_admit_id;
  logic [AxiAddrWidth-1:0] slave_wr_admit_addr;
  logic [AxlenWidth-1:0] slave_wr_admit_len;
  logic [AxsizeWidth-1:0] slave_wr_admit_size;
  logic [1:0] slave_wr_admit_burst;
  logic slave_wr_beat_valid;
  logic [ParentIndexWidth-1:0] slave_wr_beat_parent_idx;
  logic [AxiDataWidth-1:0] slave_wr_beat_data;
  logic [AxiStrbWidth-1:0] slave_wr_beat_strb;
  logic slave_wr_beat_last;
  logic slave_wr_beat_error;
  logic ctx_rd_admit_ready;
  logic [ParentIndexWidth-1:0] ctx_rd_admit_parent_idx;
  logic ctx_wr_admit_ready;
  logic [ParentIndexWidth-1:0] ctx_wr_admit_parent_idx;
  logic rd_issue_ready;
  logic ctx_rd_issue_valid;
  logic [ParentIndexWidth-1:0] ctx_rd_issue_parent_idx;
  logic [AxiAddrWidth-1:0] ctx_rd_issue_addr;
  logic [AxlenWidth-1:0] ctx_rd_issue_axi_beat;
  logic [1:0] ctx_rd_issue_frag_idx;
  logic ctx_wr_issue_valid;
  logic [ParentIndexWidth-1:0] ctx_wr_issue_parent_idx;
  logic [AxiAddrWidth-1:0] ctx_wr_issue_addr;
  logic [AxlenWidth-1:0] ctx_wr_issue_axi_beat;
  logic [1:0] ctx_wr_issue_frag_idx;
  logic ctx_wr_issue_full_candidate;
  logic rd_core_txreq_valid;
  logic [ReqFlitWidth-1:0] rd_core_txreq_payload;
  logic rd_core_txreq_ready;
  logic rd_child_alloc_valid;
  logic rd_child_alloc_ready;
  logic [ParentIndexWidth-1:0] rd_child_alloc_parent_idx;
  logic [AxiAddrWidth-1:0] rd_child_alloc_addr;
  logic [AxlenWidth-1:0] rd_child_alloc_axi_beat;
  logic [1:0] rd_child_alloc_frag_idx;
  logic [ChildIndexWidth-1:0] rd_child_alloc_idx;
  logic [ChiTxnidWidth-1:0] rd_child_alloc_txnid;
  logic rd_child_event_valid;
  logic [ChildIndexWidth-1:0] rd_child_event_idx;
  logic [2:0] rd_child_event_type;
  logic rd_data_child_complete_valid;
  logic [ChildIndexWidth-1:0] rd_data_child_complete_idx;
  logic [1:0] rd_data_child_complete_resp;
  logic rd_fragment_valid;
  logic rd_fragment_ready;
  logic [ChildIndexWidth-1:0] rd_fragment_child_idx;
  logic [DatFlitWidth-1:0] rd_fragment_payload;
  logic rd_rsp_valid;
  logic rd_rsp_ready;
  logic rd_rsp_parent_valid;
  logic [ParentIndexWidth-1:0] rd_rsp_parent_idx;
  logic [ChildIndexWidth-1:0] rd_rsp_child_idx;
  logic [AxlenWidth-1:0] rd_rsp_axi_beat;
  logic [AxiIdWidth-1:0] rd_rsp_id;
  logic [AxiDataWidth-1:0] rd_rsp_data;
  logic [1:0] rd_rsp_resp;
  logic rd_rsp_last;
  logic wr_issue_ready;
  logic wr_core_txreq_valid;
  logic [ReqFlitWidth-1:0] wr_core_txreq_payload;
  logic wr_core_txreq_ready;
  logic wr_child_alloc_valid;
  logic wr_child_alloc_ready;
  logic [ParentIndexWidth-1:0] wr_child_alloc_parent_idx;
  logic [AxiAddrWidth-1:0] wr_child_alloc_addr;
  logic [AxlenWidth-1:0] wr_child_alloc_axi_beat;
  logic [1:0] wr_child_alloc_frag_idx;
  logic [ChildIndexWidth-1:0] wr_child_alloc_idx;
  logic [ChiTxnidWidth-1:0] wr_child_alloc_txnid;
  logic wr_child_event_valid;
  logic [ChildIndexWidth-1:0] wr_child_event_idx;
  logic [2:0] wr_child_event_type;
  logic [ChiDbidWidth-1:0] wr_child_event_dbid;
  logic [1:0] wr_child_event_resp;
  logic wr_data_fragment_valid;
  logic wr_data_fragment_ready;
  logic wr_data_child_bind_ready;
  logic [ChildEntries-1:0] wr_wait_child_vec;
  logic wr_beat_ready;
  logic [ChildIndexWidth-1:0] wr_data_fragment_child_idx;
  logic [DataIdWidth-1:0] wr_data_fragment_dataid;
  logic wr_data_fragment_last;
  logic wr_data_fragment_error;
  logic [ParentEntries-1:0] wr_beat_present_vec;
  logic [ParentEntries-1:0] wr_beat_full_vec;
  logic [ChiDataWidth-1:0] wr_data_fragment_data;
  logic [ChiBeWidth-1:0] wr_data_fragment_be;
  logic [DatFlitWidth-1:0] wr_fragment_payload;
  logic child_alloc_valid;
  logic child_alloc_ready;
  logic child_alloc_is_write;
  logic [ParentIndexWidth-1:0] child_alloc_parent_idx;
  logic [AxiAddrWidth-1:0] child_alloc_addr;
  logic [ChildIndexWidth-1:0] child_alloc_idx;
  logic [ChiTxnidWidth-1:0] child_alloc_txnid;
  logic child_alloc_last_fragment;
  logic [$clog2(AxiDataWidth / 8 + 1)-1:0] child_alloc_axi_byte_offset;
  logic [$clog2(CacheLineBytes)-1:0] child_alloc_line_byte_offset;
  logic [$clog2(AxiDataWidth / 8 + 1)-1:0] child_alloc_fragment_byte_count;
  logic child_event_valid;
  logic [ChildIndexWidth-1:0] child_event_idx;
  logic [2:0] child_event_type;
  logic [ChiDbidWidth-1:0] child_event_dbid;
  logic [1:0] child_event_resp;
  logic [ParentIndexWidth-1:0] child_event_parent_idx;
  logic child_event_parent_complete;
  logic child_event_parent_error;
  logic child_lookup_valid;
  logic [ParentIndexWidth-1:0] child_lookup_parent_idx;
  logic [AxiIdWidth-1:0] child_lookup_axi_id;
  logic child_lookup_is_write;
  logic child_lookup_last;
  logic [AxlenWidth-1:0] child_lookup_axi_beat;
  logic [1:0] child_lookup_frag_idx;
  logic child_lookup_last_fragment;
  logic [$clog2(AxiDataWidth / 8 + 1)-1:0] child_lookup_axi_byte_offset;
  logic [$clog2(CacheLineBytes)-1:0] child_lookup_line_byte_offset;
  logic [$clog2(AxiDataWidth / 8 + 1)-1:0] child_lookup_fragment_byte_count;
  logic parent_retire_valid;
  logic [ParentIndexWidth-1:0] parent_retire_idx;
  logic wr_rsp_valid;
  logic wr_rsp_ready;
  logic [AxiIdWidth-1:0] wr_rsp_id;
  logic [1:0] wr_rsp_resp;
  logic [ParentEntries-1:0] wr_rsp_valid_q;
  logic [1:0] wr_rsp_resp_q [ParentEntries];
  logic wr_rsp_selected_found;
  logic [ParentIndexWidth-1:0] wr_rsp_selected_idx;
  logic unused_wr_rsp_ready;
  logic unused_child_release_ready;
  logic unused_parent_retire_ready;
  logic rd_rsp_retire_permit;
  logic [ParentEntries-1:0] parent_retire_permit_vec;
  logic axi_beat_retire_valid;
  logic [ParentIndexWidth-1:0] axi_beat_retire_parent_idx;
  logic [AxlenWidth-1:0] axi_beat_retire_beat;
  logic axi_beat_retire_all;
  logic parent_lookup_valid;
  logic [ParentIndexWidth-1:0] parent_lookup_idx;
  logic [AxiIdWidth-1:0] parent_lookup_axi_id;

  assign rst = !aresetn;

  assign slave_rd_admit_ready = ctx_rd_admit_ready && core_txreq_ready;
  assign core_txreq_valid = rd_core_txreq_valid || wr_core_txreq_valid;
  assign core_txreq_payload =
      rd_core_txreq_valid ? rd_core_txreq_payload : wr_core_txreq_payload;
  assign rd_core_txreq_ready = core_txreq_ready && rd_core_txreq_valid;
  assign wr_core_txreq_ready =
      core_txreq_ready && !rd_core_txreq_valid && wr_core_txreq_valid;
  always_comb begin
    wr_rsp_selected_found = 1'b0;
    wr_rsp_selected_idx = '0;
    for (int unsigned idx = 0; idx < ParentEntries; idx++) begin
      if (wr_rsp_valid_q[idx] && parent_retire_permit_vec[idx] &&
          !wr_rsp_selected_found) begin
        wr_rsp_selected_found = 1'b1;
        wr_rsp_selected_idx = ParentIndexWidth'(idx);
      end
    end
  end
  assign wr_rsp_valid = wr_rsp_selected_found;
  assign parent_lookup_valid = wr_rsp_selected_found;
  assign parent_lookup_idx = wr_rsp_selected_idx;
  assign wr_rsp_id = parent_lookup_axi_id;
  assign wr_rsp_resp = wr_rsp_resp_q[wr_rsp_selected_idx];
  // Preserve an RXRSP flit at the CHI boundary until the engine that owns its
  // TxnID and expected response opcode can accept it.
  assign core_rxrsp_ready = rd_core_rxrsp_ready || wr_core_rxrsp_ready;
  assign wr_fragment_payload = '0 |
      (DatFlitWidth'(wr_data_fragment_dataid) << 36) |
      (DatFlitWidth'(wr_data_fragment_be) << 64) |
      (DatFlitWidth'(wr_data_fragment_data) << 128);
  assign child_alloc_valid = rd_child_alloc_valid || wr_child_alloc_valid;
  assign child_alloc_is_write = !rd_child_alloc_valid && wr_child_alloc_valid;
  assign child_alloc_parent_idx =
      rd_child_alloc_valid ? rd_child_alloc_parent_idx : wr_child_alloc_parent_idx;
  assign child_alloc_addr =
      rd_child_alloc_valid ? rd_child_alloc_addr : wr_child_alloc_addr;
  assign rd_child_alloc_ready = child_alloc_ready && rd_child_alloc_valid;
  assign wr_child_alloc_ready =
      child_alloc_ready && wr_data_child_bind_ready && !rd_child_alloc_valid &&
      wr_child_alloc_valid;
  assign rd_child_alloc_idx = child_alloc_idx;
  assign wr_child_alloc_idx = child_alloc_idx;
  assign rd_child_alloc_txnid = child_alloc_txnid;
  assign wr_child_alloc_txnid = child_alloc_txnid;
  assign child_event_valid = rd_data_child_complete_valid || wr_child_event_valid;
  assign child_event_idx =
      rd_data_child_complete_valid ? rd_data_child_complete_idx : wr_child_event_idx;
  assign child_event_type =
      rd_data_child_complete_valid ? 3'd4 : wr_child_event_type;
  assign child_event_dbid = rd_data_child_complete_valid ? '0 : wr_child_event_dbid;
  assign child_event_resp = rd_data_child_complete_valid ?
      rd_data_child_complete_resp : wr_child_event_resp;
  assign parent_retire_valid =
      (rd_rsp_valid && rd_rsp_ready && rd_rsp_parent_valid && rd_rsp_last) ||
      (wr_rsp_valid && wr_rsp_ready);
  assign parent_retire_idx =
      (rd_rsp_valid && rd_rsp_ready && rd_rsp_parent_valid) ?
      rd_rsp_parent_idx : wr_rsp_selected_idx;
  assign axi_beat_retire_valid =
      (rd_rsp_valid && rd_rsp_ready && rd_rsp_parent_valid) ||
      (wr_rsp_valid && wr_rsp_ready);
  assign axi_beat_retire_parent_idx =
      (rd_rsp_valid && rd_rsp_ready && rd_rsp_parent_valid) ?
      rd_rsp_parent_idx : wr_rsp_selected_idx;
  assign axi_beat_retire_beat =
      (rd_rsp_valid && rd_rsp_ready && rd_rsp_parent_valid) ?
      rd_rsp_axi_beat : '0;
  assign axi_beat_retire_all = wr_rsp_valid && wr_rsp_ready;

  axi2chi_nocoh_slave #(
    .AxiAddrWidth(AxiAddrWidth),
    .AxiDataWidth(AxiDataWidth),
    .AxiIdWidth(AxiIdWidth),
    .AxlenWidth(AxlenWidth),
    .AxsizeWidth(AxsizeWidth),
    .ParentEntries(ParentEntries)
  ) slave (
    .clk(clk),
    .rst(rst),
    .s_axi_awid(s_axi_awid),
    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awlen(s_axi_awlen),
    .s_axi_awsize(s_axi_awsize),
    .s_axi_awburst(s_axi_awburst),
    .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wlast(s_axi_wlast),
    .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready),
    .s_axi_bid(s_axi_bid),
    .s_axi_bresp(s_axi_bresp),
    .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bready(s_axi_bready),
    .s_axi_arid(s_axi_arid),
    .s_axi_araddr(s_axi_araddr),
    .s_axi_arlen(s_axi_arlen),
    .s_axi_arsize(s_axi_arsize),
    .s_axi_arburst(s_axi_arburst),
    .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready),
    .s_axi_rid(s_axi_rid),
    .s_axi_rdata(s_axi_rdata),
    .s_axi_rresp(s_axi_rresp),
    .s_axi_rlast(s_axi_rlast),
    .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rready(s_axi_rready),
    .rd_admit_valid_o(slave_rd_admit_valid),
    .rd_admit_ready_i(slave_rd_admit_ready),
    .rd_admit_id_o(slave_rd_admit_id),
    .rd_admit_addr_o(slave_rd_admit_addr),
    .rd_admit_len_o(slave_rd_admit_len),
    .rd_admit_size_o(slave_rd_admit_size),
    .rd_admit_burst_o(slave_rd_admit_burst),
    .wr_admit_valid_o(slave_wr_admit_valid),
    .wr_admit_ready_i(ctx_wr_admit_ready),
    .wr_admit_parent_idx_i(ctx_wr_admit_parent_idx),
    .wr_admit_id_o(slave_wr_admit_id),
    .wr_admit_addr_o(slave_wr_admit_addr),
    .wr_admit_len_o(slave_wr_admit_len),
    .wr_admit_size_o(slave_wr_admit_size),
    .wr_admit_burst_o(slave_wr_admit_burst),
    .wr_beat_valid_o(slave_wr_beat_valid),
    .wr_beat_ready_i(wr_beat_ready),
    .wr_beat_parent_idx_o(slave_wr_beat_parent_idx),
    .wr_beat_data_o(slave_wr_beat_data),
    .wr_beat_strb_o(slave_wr_beat_strb),
    .wr_beat_last_o(slave_wr_beat_last),
    .wr_beat_error_o(slave_wr_beat_error),
    .rd_rsp_valid_i(rd_rsp_valid),
    .rd_rsp_ready_o(rd_rsp_ready),
    .rd_rsp_id_i(rd_rsp_id),
    .rd_rsp_data_i(rd_rsp_data),
    .rd_rsp_resp_i(rd_rsp_resp),
    .rd_rsp_last_i(rd_rsp_last),
    .wr_rsp_valid_i(wr_rsp_valid),
    .wr_rsp_ready_o(wr_rsp_ready),
    .wr_rsp_id_i(wr_rsp_id),
    .wr_rsp_resp_i(wr_rsp_resp)
  );

  axi2chi_nocoh_txn_ctx #(
    .AxiAddrWidth(AxiAddrWidth),
    .AxiDataWidth(AxiDataWidth),
    .AxiIdWidth(AxiIdWidth),
    .AxlenWidth(AxlenWidth),
    .AxsizeWidth(AxsizeWidth),
    .ChiTxnidWidth(ChiTxnidWidth),
    .ChiDbidWidth(ChiDbidWidth),
    .ParentEntries(ParentEntries),
    .ChildEntries(ChildEntries),
    .CacheLineBytes(CacheLineBytes)
  ) txn_ctx (
    .clk(clk),
    .rst(rst),
    .rd_admit_valid_i(slave_rd_admit_valid && core_txreq_ready),
    .rd_admit_ready_o(ctx_rd_admit_ready),
    .rd_admit_id_i(slave_rd_admit_id),
    .rd_admit_addr_i(slave_rd_admit_addr),
    .rd_admit_len_i(slave_rd_admit_len),
    .rd_admit_size_i(slave_rd_admit_size),
    .rd_admit_burst_i(slave_rd_admit_burst),
    .wr_admit_valid_i(slave_wr_admit_valid),
    .wr_admit_ready_o(ctx_wr_admit_ready),
    .wr_admit_id_i(slave_wr_admit_id),
    .wr_admit_addr_i(slave_wr_admit_addr),
    .wr_admit_len_i(slave_wr_admit_len),
    .wr_admit_size_i(slave_wr_admit_size),
    .wr_admit_burst_i(slave_wr_admit_burst),
    .rd_admit_parent_idx_o(ctx_rd_admit_parent_idx),
    .wr_admit_parent_idx_o(ctx_wr_admit_parent_idx),
    .rd_issue_valid_o(ctx_rd_issue_valid),
    .rd_issue_ready_i(rd_issue_ready),
    .rd_issue_parent_idx_o(ctx_rd_issue_parent_idx),
    .rd_issue_addr_o(ctx_rd_issue_addr),
    .rd_issue_axi_beat_o(ctx_rd_issue_axi_beat),
    .rd_issue_frag_idx_o(ctx_rd_issue_frag_idx),
    .wr_issue_valid_o(ctx_wr_issue_valid),
    .wr_issue_ready_i(wr_issue_ready),
    .wr_issue_parent_idx_o(ctx_wr_issue_parent_idx),
    .wr_issue_addr_o(ctx_wr_issue_addr),
    .wr_issue_axi_beat_o(ctx_wr_issue_axi_beat),
    .wr_issue_frag_idx_o(ctx_wr_issue_frag_idx),
    .wr_issue_full_candidate_o(ctx_wr_issue_full_candidate),
    .child_alloc_valid_i(child_alloc_valid),
    .child_alloc_ready_o(child_alloc_ready),
    .child_alloc_parent_idx_i(child_alloc_parent_idx),
    .child_alloc_is_write_i(child_alloc_is_write),
    .child_alloc_axi_beat_i(rd_child_alloc_valid ?
        rd_child_alloc_axi_beat : wr_child_alloc_axi_beat),
    .child_alloc_addr_i(child_alloc_addr),
    .child_alloc_frag_idx_i(rd_child_alloc_valid ? rd_child_alloc_frag_idx :
        wr_child_alloc_frag_idx),
    .child_alloc_idx_o(child_alloc_idx),
    .child_alloc_txnid_o(child_alloc_txnid),
    .child_alloc_last_fragment_o(child_alloc_last_fragment),
    .child_alloc_axi_byte_offset_o(child_alloc_axi_byte_offset),
    .child_alloc_line_byte_offset_o(child_alloc_line_byte_offset),
    .child_alloc_fragment_byte_count_o(child_alloc_fragment_byte_count),
    .child_release_valid_i(1'b0),
    .child_release_ready_o(unused_child_release_ready),
    .child_release_idx_i('0),
    .axi_beat_retire_valid_i(axi_beat_retire_valid),
    .axi_beat_retire_parent_idx_i(axi_beat_retire_parent_idx),
    .axi_beat_retire_beat_i(axi_beat_retire_beat),
    .axi_beat_retire_all_i(axi_beat_retire_all),
    .child_event_valid_i(child_event_valid),
    .child_event_idx_i(child_event_idx),
    .child_event_type_i(child_event_type),
    .child_event_dbid_i(child_event_dbid),
    .child_event_resp_i(child_event_resp),
    .child_event_parent_idx_o(child_event_parent_idx),
    .child_event_parent_complete_o(child_event_parent_complete),
    .child_event_parent_error_o(child_event_parent_error),
    .child_lookup_valid_i(rd_fragment_valid),
    .child_lookup_idx_i(rd_fragment_child_idx),
    .child_lookup_valid_o(child_lookup_valid),
    .child_lookup_parent_idx_o(child_lookup_parent_idx),
    .child_lookup_axi_id_o(child_lookup_axi_id),
    .child_lookup_is_write_o(child_lookup_is_write),
    .child_lookup_last_o(child_lookup_last),
    .child_lookup_axi_beat_o(child_lookup_axi_beat),
    .child_lookup_frag_idx_o(child_lookup_frag_idx),
    .child_lookup_last_fragment_o(child_lookup_last_fragment),
    .child_lookup_axi_byte_offset_o(child_lookup_axi_byte_offset),
    .child_lookup_line_byte_offset_o(child_lookup_line_byte_offset),
    .child_lookup_fragment_byte_count_o(child_lookup_fragment_byte_count),
    .parent_retire_valid_i(parent_retire_valid),
    .parent_retire_idx_i(parent_retire_idx),
    .parent_retire_ready_o(unused_parent_retire_ready),
    .parent_retire_query_valid_i(rd_rsp_parent_valid),
    .parent_retire_query_idx_i(rd_rsp_parent_idx),
    .parent_retire_query_permit_o(rd_rsp_retire_permit),
    .parent_retire_permit_vec_o(parent_retire_permit_vec),
    .parent_lookup_valid_i(parent_lookup_valid),
    .parent_lookup_idx_i(parent_lookup_idx),
    .parent_lookup_axi_id_o(parent_lookup_axi_id)
  );

  axi2chi_nocoh_rd_engine #(
    .AxiAddrWidth(AxiAddrWidth),
    .AxiIdWidth(AxiIdWidth),
    .ChiTxnidWidth(ChiTxnidWidth),
    .ReqFlitWidth(ReqFlitWidth),
    .RspFlitWidth(RspFlitWidth),
    .DatFlitWidth(DatFlitWidth),
    .ParentEntries(ParentEntries),
    .ChildEntries(ChildEntries)
  ) rd_engine (
    .clk(clk),
    .rst(rst),
    .rd_issue_valid_i(ctx_rd_issue_valid),
    .rd_issue_ready_o(rd_issue_ready),
    .rd_issue_parent_idx_i(ctx_rd_issue_parent_idx),
    .rd_issue_addr_i(ctx_rd_issue_addr),
    .rd_issue_axi_beat_i(ctx_rd_issue_axi_beat),
    .rd_issue_frag_idx_i(ctx_rd_issue_frag_idx),
    .child_alloc_valid_o(rd_child_alloc_valid),
    .child_alloc_ready_i(rd_child_alloc_ready),
    .child_alloc_parent_idx_o(rd_child_alloc_parent_idx),
    .child_alloc_addr_o(rd_child_alloc_addr),
    .child_alloc_axi_beat_o(rd_child_alloc_axi_beat),
    .child_alloc_frag_idx_o(rd_child_alloc_frag_idx),
    .child_alloc_idx_i(rd_child_alloc_idx),
    .child_alloc_txnid_i(rd_child_alloc_txnid),
    .child_event_valid_o(rd_child_event_valid),
    .child_event_idx_o(rd_child_event_idx),
    .child_event_type_o(rd_child_event_type),
    .txreq_valid_o(rd_core_txreq_valid),
    .txreq_payload_o(rd_core_txreq_payload),
    .txreq_ready_i(rd_core_txreq_ready),
    .rxdat_valid_i(core_rxdat_valid),
    .rxdat_payload_i(core_rxdat_payload),
    .rxdat_ready_o(core_rxdat_ready),
    .rxrsp_valid_i(core_rxrsp_valid),
    .rxrsp_payload_i(core_rxrsp_payload),
    .rxrsp_ready_o(rd_core_rxrsp_ready),
    .rd_fragment_valid_o(rd_fragment_valid),
    .rd_fragment_child_idx_o(rd_fragment_child_idx),
    .rd_fragment_payload_o(rd_fragment_payload),
    .rd_fragment_ready_i(rd_fragment_ready),
    .rd_child_complete_valid_i(rd_data_child_complete_valid),
    .rd_child_complete_idx_i(rd_data_child_complete_idx)
  );

  axi2chi_nocoh_rd_data #(
    .AxiDataWidth(AxiDataWidth),
    .AxiIdWidth(AxiIdWidth),
    .AxlenWidth(AxlenWidth),
    .ChiDataWidth(ChiDataWidth),
    .CacheLineBytes(CacheLineBytes),
    .ParentEntries(ParentEntries),
    .ChildEntries(ChildEntries),
    .DataIdWidth(DataIdWidth)
  ) rd_data (
    .clk(clk),
    .rst(rst),
    .fragment_valid_i(rd_fragment_valid),
    .fragment_ready_o(rd_fragment_ready),
    .fragment_child_idx_i(rd_fragment_child_idx),
    .fragment_lookup_valid_i(child_lookup_valid && !child_lookup_is_write),
    .fragment_parent_idx_i(child_lookup_parent_idx),
    .fragment_axi_id_i(child_lookup_axi_id),
    .fragment_axi_beat_i(child_lookup_axi_beat),
    .fragment_data_i(rd_fragment_payload[64 +: ChiDataWidth]),
    .fragment_be_i(rd_fragment_payload[32 +: ChiBeWidth]),
    .fragment_dataid_i(rd_fragment_payload[24 +: DataIdWidth]),
    .fragment_resp_i(rd_fragment_payload[RxdatRespLsb +: 2]),
    .fragment_last_i(child_lookup_last),
    .fragment_last_fragment_i(child_lookup_last_fragment),
    .fragment_idx_i(child_lookup_frag_idx),
    .fragment_axi_byte_offset_i(child_lookup_axi_byte_offset),
    .fragment_line_byte_offset_i(child_lookup_line_byte_offset),
    .fragment_byte_count_i(child_lookup_fragment_byte_count),
    .child_complete_valid_o(rd_data_child_complete_valid),
    .child_complete_idx_o(rd_data_child_complete_idx),
    .child_complete_resp_o(rd_data_child_complete_resp),
    .rd_rsp_parent_valid_o(rd_rsp_parent_valid),
    .rd_rsp_parent_idx_o(rd_rsp_parent_idx),
    .rd_rsp_child_idx_o(rd_rsp_child_idx),
    .rd_rsp_axi_beat_o(rd_rsp_axi_beat),
    .rd_rsp_retire_permit_vec_i(parent_retire_permit_vec),
    .rd_rsp_valid_o(rd_rsp_valid),
    .rd_rsp_ready_i(rd_rsp_ready),
    .rd_rsp_id_o(rd_rsp_id),
    .rd_rsp_data_o(rd_rsp_data),
    .rd_rsp_resp_o(rd_rsp_resp),
    .rd_rsp_last_o(rd_rsp_last)
  );

  axi2chi_nocoh_wr_data #(
    .AxiDataWidth(AxiDataWidth),
    .ChiDataWidth(ChiDataWidth),
    .CacheLineBytes(CacheLineBytes),
    .ParentEntries(ParentEntries),
    .ChildEntries(ChildEntries),
    .DataIdWidth(DataIdWidth)
  ) wr_data (
    .clk(clk),
    .rst(rst),
    .wr_beat_valid_i(slave_wr_beat_valid),
    .wr_beat_ready_o(wr_beat_ready),
    .wr_beat_parent_idx_i(slave_wr_beat_parent_idx),
    .wr_beat_data_i(slave_wr_beat_data),
    .wr_beat_strb_i(slave_wr_beat_strb),
    .wr_beat_last_i(slave_wr_beat_last),
    .wr_beat_error_i(slave_wr_beat_error),
    .child_bind_valid_i(wr_child_alloc_valid && wr_child_alloc_ready),
    .child_waiting_i(wr_wait_child_vec),
    .child_bind_ready_o(wr_data_child_bind_ready),
    .child_bind_parent_idx_i(wr_child_alloc_parent_idx),
    .child_bind_idx_i(wr_child_alloc_idx),
    .child_bind_last_fragment_i(child_alloc_last_fragment),
    .child_bind_axi_byte_offset_i(child_alloc_axi_byte_offset),
    .child_bind_line_byte_offset_i(child_alloc_line_byte_offset),
    .child_bind_fragment_byte_count_i(child_alloc_fragment_byte_count),
    .txdat_fragment_valid_o(wr_data_fragment_valid),
    .txdat_fragment_ready_i(wr_data_fragment_ready),
    .txdat_fragment_child_idx_o(wr_data_fragment_child_idx),
    .txdat_fragment_dataid_o(wr_data_fragment_dataid),
    .txdat_fragment_last_o(wr_data_fragment_last),
    .txdat_fragment_error_o(wr_data_fragment_error),
    .wr_beat_present_vec_o(wr_beat_present_vec),
    .wr_beat_full_vec_o(wr_beat_full_vec),
    .txdat_fragment_data_o(wr_data_fragment_data),
    .txdat_fragment_be_o(wr_data_fragment_be)
  );

  axi2chi_nocoh_wr_engine #(
    .AxiAddrWidth(AxiAddrWidth),
    .ChiTxnidWidth(ChiTxnidWidth),
    .ChiDbidWidth(ChiDbidWidth),
    .ReqFlitWidth(ReqFlitWidth),
    .RspFlitWidth(RspFlitWidth),
    .DatFlitWidth(DatFlitWidth),
    .ParentEntries(ParentEntries),
    .ChildEntries(ChildEntries),
    .EnableWriteNoSnpFull(EnableWriteNoSnpFull)
  ) wr_engine (
    .clk(clk),
    .rst(rst),
    .wr_issue_valid_i(ctx_wr_issue_valid),
    .wr_issue_ready_o(wr_issue_ready),
    .wr_issue_parent_idx_i(ctx_wr_issue_parent_idx),
    .wr_issue_addr_i(ctx_wr_issue_addr),
    .wr_issue_axi_beat_i(ctx_wr_issue_axi_beat),
    .wr_issue_frag_idx_i(ctx_wr_issue_frag_idx),
    .wr_issue_full_candidate_i(ctx_wr_issue_full_candidate),
    .wr_beat_present_vec_i(wr_beat_present_vec),
    .wr_beat_full_vec_i(wr_beat_full_vec),
    .child_alloc_valid_o(wr_child_alloc_valid),
    .child_alloc_ready_i(wr_child_alloc_ready),
    .child_alloc_parent_idx_o(wr_child_alloc_parent_idx),
    .child_alloc_addr_o(wr_child_alloc_addr),
    .child_alloc_axi_beat_o(wr_child_alloc_axi_beat),
    .child_alloc_frag_idx_o(wr_child_alloc_frag_idx),
    .child_alloc_idx_i(wr_child_alloc_idx),
    .child_alloc_txnid_i(wr_child_alloc_txnid),
    .child_event_valid_o(wr_child_event_valid),
    .child_event_idx_o(wr_child_event_idx),
    .child_event_type_o(wr_child_event_type),
    .child_event_dbid_o(wr_child_event_dbid),
    .child_event_resp_o(wr_child_event_resp),
    .txreq_valid_o(wr_core_txreq_valid),
    .txreq_payload_o(wr_core_txreq_payload),
    .txreq_ready_i(wr_core_txreq_ready),
    .txdat_valid_o(core_txdat_valid),
    .txdat_payload_o(core_txdat_payload),
    .txdat_ready_i(core_txdat_ready),
    .rxrsp_valid_i(core_rxrsp_valid),
    .rxrsp_payload_i(core_rxrsp_payload),
    .rxrsp_ready_o(wr_core_rxrsp_ready),
    .wr_fragment_valid_i(wr_data_fragment_valid),
    .wr_fragment_child_idx_i(wr_data_fragment_child_idx),
    .wr_fragment_payload_i(wr_fragment_payload),
    .wr_fragment_last_i(wr_data_fragment_last),
    .wr_fragment_error_i(wr_data_fragment_error),
    .wr_fragment_ready_o(wr_data_fragment_ready),
    .wr_wait_child_vec_o(wr_wait_child_vec)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      wr_rsp_valid_q <= '0;
      for (int unsigned idx = 0; idx < ParentEntries; idx++) begin
        wr_rsp_resp_q[idx] <= '0;
      end
    end else begin
      if (wr_child_event_valid && child_event_parent_complete) begin
        wr_rsp_valid_q[child_event_parent_idx] <= 1'b1;
        wr_rsp_resp_q[child_event_parent_idx] <=
            child_event_parent_error ? 2'b10 : 2'b00;
      end
      if (wr_rsp_valid && wr_rsp_ready) begin
        wr_rsp_valid_q[wr_rsp_selected_idx] <= 1'b0;
      end
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (!rst) begin
      assert (!(wr_child_event_valid && child_event_parent_complete &&
          wr_rsp_valid_q[child_event_parent_idx]))
      else $fatal(1, "Write response slot is already occupied");
    end
  end
`endif

  axi2chi_chi_link #(
    .ReqFlitWidth(ReqFlitWidth),
    .RspFlitWidth(RspFlitWidth),
    .DatFlitWidth(DatFlitWidth),
    .ReqRxDepth(2),
    .RspRxDepth(2),
    .DatRxDepth(2)
  ) chi_link (
    .clk(clk),
    .rst(rst),
    .core_txreq_valid_i(core_txreq_valid),
    .core_txreq_flit_i(core_txreq_payload),
    .core_txreq_ready_o(core_txreq_ready),
    .core_txdat_valid_i(core_txdat_valid),
    .core_txdat_flit_i(core_txdat_payload),
    .core_txdat_ready_o(core_txdat_ready),
    .core_rxrsp_valid_o(core_rxrsp_valid),
    .core_rxrsp_flit_o(core_rxrsp_payload),
    .core_rxrsp_ready_i(core_rxrsp_ready),
    .core_rxdat_valid_o(core_rxdat_valid),
    .core_rxdat_flit_o(core_rxdat_payload),
    .core_rxdat_ready_i(core_rxdat_ready),
    .chi_txreq_flitv_o(chi_txreq_flitv_o),
    .chi_txreq_flit_o(chi_txreq_flit_o),
    .chi_txreq_lcrdv_i(chi_txreq_lcrdv_i),
    .chi_txdat_flitv_o(chi_txdat_flitv_o),
    .chi_txdat_flit_o(chi_txdat_flit_o),
    .chi_txdat_lcrdv_i(chi_txdat_lcrdv_i),
    .chi_txrsp_flitv_o(chi_txrsp_flitv_o),
    .chi_txrsp_flit_o(chi_txrsp_flit_o),
    .chi_txrsp_lcrdv_i(chi_txrsp_lcrdv_i),
    .chi_rxrsp_flitv_i(chi_rxrsp_flitv_i),
    .chi_rxrsp_flit_i(chi_rxrsp_flit_i),
    .chi_rxrsp_lcrdv_o(chi_rxrsp_lcrdv_o),
    .chi_rxdat_flitv_i(chi_rxdat_flitv_i),
    .chi_rxdat_flit_i(chi_rxdat_flit_i),
    .chi_rxdat_lcrdv_o(chi_rxdat_lcrdv_o),
    .chi_txlinkactivereq_o(chi_txlinkactivereq_o),
    .chi_txlinkactiveack_i(chi_txlinkactiveack_i),
    .chi_rxlinkactivereq_i(chi_rxlinkactivereq_i),
    .chi_rxlinkactiveack_o(chi_rxlinkactiveack_o)
  );

endmodule

`default_nettype wire
