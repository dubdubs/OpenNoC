// RXDAT fragment assembly and per-parent completed-response storage.

`default_nettype none

module axi2chi_nocoh_rd_data #(
  parameter int unsigned AxiDataWidth = 128,
  parameter int unsigned AxiIdWidth = 4,
  parameter int unsigned AxlenWidth = 8,
  parameter int unsigned ChiDataWidth = 256,
  parameter int unsigned CacheLineBytes = 64,
  parameter int unsigned ParentEntries = 16,
  parameter int unsigned ChildEntries = 16
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
  input logic [1:0] fragment_resp_i, input logic fragment_last_i,
  input logic fragment_last_fragment_i, input logic [1:0] fragment_idx_i,
  input logic [$clog2(AxiDataWidth / 8 + 1)-1:0] fragment_axi_byte_offset_i,
  input logic [$clog2(CacheLineBytes)-1:0] fragment_line_byte_offset_i,
  input logic [$clog2(AxiDataWidth / 8 + 1)-1:0] fragment_byte_count_i,
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

  axi2chi_nocoh_rd_byte_map #(
    .AxiDataWidth(AxiDataWidth), .ChiDataWidth(ChiDataWidth),
    .CacheLineBytes(CacheLineBytes)
  ) rd_byte_map (
    .chi_data_i(fragment_data_i), .chi_be_i(fragment_be_i),
    .axi_byte_offset_i(fragment_axi_byte_offset_i),
    .fragment_byte_count_i(fragment_byte_count_i),
    .line_byte_offset_i(fragment_line_byte_offset_i),
    .axi_data_o(mapped_data), .axi_valid_be_o(mapped_be)
  );

  always_comb begin
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
    rsp_fire = rd_rsp_valid_o && rd_rsp_ready_i;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      for (int unsigned idx = 0; idx < ParentEntries; idx++) begin
        assembly_q[idx] <= '0;
        response_q[idx] <= '0;
      end
    end else begin
      if (rsp_fire) begin
        response_q[selected_idx].valid <= 1'b0;
      end
      if (fragment_fire) begin
        if (fragment_last_fragment_i && fragment_idx_i == 0) begin
          response_q[fragment_parent_idx_i].valid <= 1'b1;
          response_q[fragment_parent_idx_i].axi_id <= fragment_axi_id_i;
          response_q[fragment_parent_idx_i].data <= mapped_data;
          response_q[fragment_parent_idx_i].resp <=
              fragment_resp_i[1] ? 2'b10 : 2'b00;
          response_q[fragment_parent_idx_i].last <= fragment_last_i;
          response_q[fragment_parent_idx_i].child_idx <= fragment_child_idx_i;
          response_q[fragment_parent_idx_i].axi_beat <= fragment_axi_beat_i;
        end else if (fragment_last_fragment_i) begin
          response_q[fragment_parent_idx_i].valid <= 1'b1;
          response_q[fragment_parent_idx_i].axi_id <= fragment_axi_id_i;
          response_q[fragment_parent_idx_i].data <=
              assembly_q[fragment_parent_idx_i].data | mapped_data;
          response_q[fragment_parent_idx_i].resp <=
              assembly_q[fragment_parent_idx_i].resp |
              (fragment_resp_i[1] ? 2'b10 : 2'b00);
          response_q[fragment_parent_idx_i].last <= fragment_last_i;
          response_q[fragment_parent_idx_i].child_idx <= fragment_child_idx_i;
          response_q[fragment_parent_idx_i].axi_beat <= fragment_axi_beat_i;
          assembly_q[fragment_parent_idx_i] <= '0;
        end else begin
          assembly_q[fragment_parent_idx_i].data <= fragment_idx_i == 0 ?
              mapped_data : assembly_q[fragment_parent_idx_i].data | mapped_data;
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
