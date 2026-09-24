// RXDAT fragment assembly and per-parent completed-response storage.

`default_nettype none

module axi2chi_nocoh_rd_data #(
  parameter int unsigned AxiDataWidth = 128,
  parameter int unsigned AxiIdWidth = 4,
  parameter int unsigned AxlenWidth = 8,
  parameter int unsigned ChiDataWidth = 256,
  parameter int unsigned CacheLineBytes = 64,
  parameter int unsigned ParentEntries = 16,
  parameter int unsigned ChildEntries = 16,
  parameter int unsigned DataIdWidth =
      ((CacheLineBytes / (ChiDataWidth / 8)) > 1) ?
          $clog2(CacheLineBytes / (ChiDataWidth / 8)) : 1
) (
  input logic clk, input logic rst,
  input logic fragment_valid_i, output logic fragment_ready_o,
  input logic [$clog2(ChildEntries)-1:0] fragment_child_idx_i,
  input logic fragment_lookup_valid_i,
  input logic [$clog2(ParentEntries)-1:0] fragment_parent_idx_i,
  input logic [AxiIdWidth-1:0] fragment_axi_id_i,
  input logic [AxlenWidth-1:0] fragment_axi_beat_i,
  input logic [ChiDataWidth-1:0] fragment_data_i,
  input logic [ChiDataWidth / 8-1:0] fragment_be_i,
  input logic [DataIdWidth-1:0] fragment_dataid_i,
  input logic [1:0] fragment_resp_i, input logic fragment_last_i,
  input logic fragment_last_fragment_i, input logic [1:0] fragment_idx_i,
  input logic [$clog2(AxiDataWidth / 8 + 1)-1:0] fragment_axi_byte_offset_i,
  input logic [$clog2(CacheLineBytes)-1:0] fragment_line_byte_offset_i,
  input logic [$clog2(AxiDataWidth / 8 + 1)-1:0] fragment_byte_count_i,
  output logic child_complete_valid_o,
  output logic [$clog2(ChildEntries)-1:0] child_complete_idx_o,
  output logic [1:0] child_complete_resp_o,
  output logic rd_rsp_parent_valid_o,
  output logic [$clog2(ParentEntries)-1:0] rd_rsp_parent_idx_o,
  output logic [$clog2(ChildEntries)-1:0] rd_rsp_child_idx_o,
  output logic [AxlenWidth-1:0] rd_rsp_axi_beat_o,
  input logic [ParentEntries-1:0] rd_rsp_retire_permit_vec_i,
  output logic rd_rsp_valid_o, input logic rd_rsp_ready_i,
  output logic [AxiIdWidth-1:0] rd_rsp_id_o,
  output logic [AxiDataWidth-1:0] rd_rsp_data_o,
  output logic [1:0] rd_rsp_resp_o, output logic rd_rsp_last_o
);

  localparam int unsigned ParentIndexWidth = $clog2(ParentEntries);
  localparam int unsigned ChiBytes = ChiDataWidth / 8;
  localparam int unsigned SegmentCount = CacheLineBytes / ChiBytes;
  localparam int unsigned SegmentMaskWidth =
      (SegmentCount > 1) ? SegmentCount : 1;
  typedef struct packed {
    logic [AxiDataWidth-1:0] data;
    logic [AxiDataWidth / 8-1:0] valid_byte_mask;
    logic [1:0] resp;
  } assembly_t;
  typedef struct packed {
    logic valid;
    logic [AxiIdWidth-1:0] axi_id;
    logic [AxiDataWidth-1:0] data;
    logic [1:0] resp;
    logic last;
    logic [$clog2(ChildEntries)-1:0] child_idx;
    logic [AxlenWidth-1:0] axi_beat;
  } response_t;

  assembly_t assembly_q [ParentEntries];
  response_t response_q [ParentEntries];
  logic [AxiDataWidth-1:0] mapped_data;
  logic [AxiDataWidth / 8-1:0] mapped_be;
  logic selected_found;
  logic [ParentIndexWidth-1:0] selected_idx;
  logic fragment_fire, rsp_fire;
  logic child_complete_valid_q;
  logic [$clog2(ChildEntries)-1:0] child_complete_idx_q;
  logic [1:0] child_complete_resp_q;
  logic [SegmentMaskWidth-1:0] received_segment_mask_q [ParentEntries];
  logic [SegmentMaskWidth-1:0] required_segment_mask;
  logic [SegmentMaskWidth-1:0] received_segment_mask_next;
  logic [SegmentMaskWidth-1:0] current_segment_mask;
  logic child_segments_complete;
  logic [$clog2(CacheLineBytes + 1)-1:0] segment_start_byte;
  logic [$clog2(CacheLineBytes + 1)-1:0] segment_end_byte;
  logic [$clog2(CacheLineBytes + 1)-1:0] fragment_end_byte;
  logic [$clog2(AxiDataWidth / 8 + 1)-1:0] mapped_axi_byte_offset;
  logic [$clog2(AxiDataWidth / 8 + 1)-1:0] mapped_byte_count;
  logic [$clog2(ChiBytes + 1)-1:0] mapped_chi_byte_offset;
  logic [AxiDataWidth / 8-1:0] child_valid_mask_q [ParentEntries];
  logic [AxiDataWidth / 8-1:0] child_valid_mask_next;
  logic [AxiDataWidth / 8-1:0] fragment_required_be;
  logic child_missing_data;
  logic child_data_error_q [ParentEntries];

  axi2chi_nocoh_rd_byte_map #(
    .AxiDataWidth(AxiDataWidth), .ChiDataWidth(ChiDataWidth),
    .CacheLineBytes(CacheLineBytes)
  ) rd_byte_map (
    .chi_data_i(fragment_data_i), .chi_be_i(fragment_be_i),
    .axi_byte_offset_i(mapped_axi_byte_offset),
    .fragment_byte_count_i(mapped_byte_count),
    .line_byte_offset_i(segment_start_byte[$clog2(CacheLineBytes)-1:0]),
    .chi_byte_offset_i(mapped_chi_byte_offset),
    .axi_data_o(mapped_data), .axi_valid_be_o(mapped_be)
  );

  always_comb begin
    required_segment_mask = '0;
    current_segment_mask = '0;
    segment_start_byte = '0;
    segment_end_byte = '0;
    fragment_end_byte = '0;
    mapped_axi_byte_offset = fragment_axi_byte_offset_i;
    mapped_byte_count = '0;
    mapped_chi_byte_offset = '0;
    fragment_required_be = '0;
    if (fragment_byte_count_i != 0) begin
      // Extend the line offset before arithmetic.  A fragment ending at the
      // cache-line boundary must not wrap in the LineOffsetWidth domain.
      fragment_end_byte = {1'b0, fragment_line_byte_offset_i} +
          fragment_byte_count_i - 1'b1;
      for (int unsigned segment = 0; segment < SegmentCount; segment++) begin
        if (segment * ChiBytes <= fragment_end_byte &&
            (segment + 1) * ChiBytes > fragment_line_byte_offset_i) begin
          required_segment_mask[segment] = 1'b1;
        end
      end
      if (fragment_dataid_i < SegmentCount) begin
        current_segment_mask[fragment_dataid_i] = 1'b1;
        segment_start_byte = ChiBytes * fragment_dataid_i;
        segment_end_byte = segment_start_byte + ChiBytes;
        if (segment_start_byte < fragment_line_byte_offset_i) begin
          mapped_axi_byte_offset = fragment_axi_byte_offset_i;
          mapped_chi_byte_offset = fragment_line_byte_offset_i - segment_start_byte;
        end else begin
          mapped_axi_byte_offset = fragment_axi_byte_offset_i +
              (segment_start_byte - fragment_line_byte_offset_i);
        end
        if (segment_end_byte > fragment_end_byte + 1'b1) begin
          mapped_byte_count = fragment_end_byte + 1'b1 -
              ((segment_start_byte > fragment_line_byte_offset_i) ?
              segment_start_byte : fragment_line_byte_offset_i);
        end else begin
          mapped_byte_count = segment_end_byte -
              ((segment_start_byte > fragment_line_byte_offset_i) ?
              segment_start_byte : fragment_line_byte_offset_i);
        end
      end
    end
    received_segment_mask_next = received_segment_mask_q[fragment_parent_idx_i] |
        current_segment_mask;
    for (int unsigned byte_idx = 0; byte_idx < AxiDataWidth / 8; byte_idx++) begin
      if (byte_idx >= mapped_axi_byte_offset &&
          byte_idx < mapped_axi_byte_offset + mapped_byte_count) begin
        fragment_required_be[byte_idx] = 1'b1;
      end
    end
    child_valid_mask_next = child_valid_mask_q[fragment_parent_idx_i] | mapped_be;
    child_missing_data =
        (child_valid_mask_next & fragment_required_be) != fragment_required_be;
    child_segments_complete =
        (received_segment_mask_next & required_segment_mask) == required_segment_mask &&
        required_segment_mask != '0;
    selected_found = 1'b0;
    selected_idx = '0;
    for (int unsigned idx = 0; idx < ParentEntries; idx++) begin
      if (response_q[idx].valid && rd_rsp_retire_permit_vec_i[idx] &&
          !selected_found) begin
        selected_found = 1'b1;
        selected_idx = ParentIndexWidth'(idx);
      end
    end
    fragment_ready_o = fragment_lookup_valid_i &&
        !response_q[fragment_parent_idx_i].valid;
    rd_rsp_parent_valid_o = selected_found;
    rd_rsp_parent_idx_o = selected_idx;
    rd_rsp_child_idx_o = response_q[selected_idx].child_idx;
    rd_rsp_axi_beat_o = response_q[selected_idx].axi_beat;
    rd_rsp_valid_o = selected_found;
    rd_rsp_id_o = response_q[selected_idx].axi_id;
    rd_rsp_data_o = response_q[selected_idx].data;
    rd_rsp_resp_o = response_q[selected_idx].resp;
    rd_rsp_last_o = response_q[selected_idx].last;
    fragment_fire = fragment_valid_i && fragment_ready_o;
    child_complete_valid_o = child_complete_valid_q;
    child_complete_idx_o = child_complete_idx_q;
    child_complete_resp_o = child_complete_resp_q;
    rsp_fire = rd_rsp_valid_o && rd_rsp_ready_i;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      child_complete_valid_q <= 1'b0;
      child_complete_idx_q <= '0;
      child_complete_resp_q <= '0;
      for (int unsigned idx = 0; idx < ParentEntries; idx++) begin
        assembly_q[idx] <= '0;
        response_q[idx] <= '0;
        received_segment_mask_q[idx] <= '0;
        child_valid_mask_q[idx] <= '0;
        child_data_error_q[idx] <= 1'b0;
      end
    end else begin
      child_complete_valid_q <= 1'b0;
      if (rsp_fire) begin
        response_q[selected_idx].valid <= 1'b0;
      end
      if (fragment_fire) begin
        received_segment_mask_q[fragment_parent_idx_i] <= received_segment_mask_next;
        child_valid_mask_q[fragment_parent_idx_i] <= child_valid_mask_next;
        child_data_error_q[fragment_parent_idx_i] <=
            child_data_error_q[fragment_parent_idx_i] || child_missing_data;
        if (child_segments_complete) begin
          child_complete_valid_q <= 1'b1;
          child_complete_idx_q <= fragment_child_idx_i;
          child_complete_resp_q <= assembly_q[fragment_parent_idx_i].resp |
              ((fragment_resp_i[1] || child_missing_data ||
              child_data_error_q[fragment_parent_idx_i]) ? 2'b10 : 2'b00);
          received_segment_mask_q[fragment_parent_idx_i] <= '0;
          child_valid_mask_q[fragment_parent_idx_i] <= '0;
          child_data_error_q[fragment_parent_idx_i] <= 1'b0;
        end
        if (child_segments_complete && fragment_last_fragment_i &&
            fragment_idx_i == 0) begin
          response_q[fragment_parent_idx_i].valid <= 1'b1;
          response_q[fragment_parent_idx_i].axi_id <= fragment_axi_id_i;
          response_q[fragment_parent_idx_i].data <= mapped_data;
          response_q[fragment_parent_idx_i].resp <=
              (fragment_resp_i[1] || child_missing_data) ? 2'b10 : 2'b00;
          response_q[fragment_parent_idx_i].last <= fragment_last_i;
          response_q[fragment_parent_idx_i].child_idx <= fragment_child_idx_i;
          response_q[fragment_parent_idx_i].axi_beat <= fragment_axi_beat_i;
        end else if (child_segments_complete && fragment_last_fragment_i) begin
          response_q[fragment_parent_idx_i].valid <= 1'b1;
          response_q[fragment_parent_idx_i].axi_id <= fragment_axi_id_i;
          response_q[fragment_parent_idx_i].data <=
              assembly_q[fragment_parent_idx_i].data | mapped_data;
          response_q[fragment_parent_idx_i].resp <=
              assembly_q[fragment_parent_idx_i].resp |
              ((fragment_resp_i[1] || child_missing_data) ? 2'b10 : 2'b00);
          response_q[fragment_parent_idx_i].last <= fragment_last_i;
          response_q[fragment_parent_idx_i].child_idx <= fragment_child_idx_i;
          response_q[fragment_parent_idx_i].axi_beat <= fragment_axi_beat_i;
          assembly_q[fragment_parent_idx_i] <= '0;
        end else begin
          assembly_q[fragment_parent_idx_i].data <=
              assembly_q[fragment_parent_idx_i].data | mapped_data;
          assembly_q[fragment_parent_idx_i].valid_byte_mask <=
              assembly_q[fragment_parent_idx_i].valid_byte_mask | mapped_be;
          assembly_q[fragment_parent_idx_i].resp <=
              assembly_q[fragment_parent_idx_i].resp |
              (fragment_resp_i[1] ? 2'b10 : 2'b00);
        end
      end
    end
  end
endmodule

`default_nettype wire
