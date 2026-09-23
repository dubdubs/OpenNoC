// RXDAT-to-AXI read data assembly skeleton.

`default_nettype none

module axi2chi_nocoh_rd_data #(
  parameter int unsigned AxiDataWidth = 128,
  parameter int unsigned AxiIdWidth = 4,
  parameter int unsigned ChiDataWidth = 256,
  parameter int unsigned CacheLineBytes = 64,
  parameter int unsigned ParentEntries = 16,
  parameter int unsigned ChildEntries = 16
) (
  input logic clk,
  input logic rst,
  input logic fragment_valid_i,
  output logic fragment_ready_o,
  input logic [$clog2(ChildEntries)-1:0] fragment_child_idx_i,
  input logic fragment_lookup_valid_i,
  input logic [$clog2(ParentEntries)-1:0] fragment_parent_idx_i,
  input logic [AxiIdWidth-1:0] fragment_axi_id_i,
  input logic [ChiDataWidth-1:0] fragment_data_i,
  input logic [ChiDataWidth / 8-1:0] fragment_be_i,
  input logic [1:0] fragment_resp_i,
  input logic fragment_last_i,
  input logic fragment_last_fragment_i,
  input logic [1:0] fragment_idx_i,
  input logic [$clog2(AxiDataWidth / 8 + 1)-1:0] fragment_axi_byte_offset_i,
  input logic [$clog2(CacheLineBytes)-1:0] fragment_line_byte_offset_i,
  input logic [$clog2(AxiDataWidth / 8 + 1)-1:0] fragment_byte_count_i,
  output logic rd_rsp_parent_valid_o,
  output logic [$clog2(ParentEntries)-1:0] rd_rsp_parent_idx_o,
  output logic rd_rsp_valid_o,
  input logic rd_rsp_ready_i,
  output logic [AxiIdWidth-1:0] rd_rsp_id_o,
  output logic [AxiDataWidth-1:0] rd_rsp_data_o,
  output logic [1:0] rd_rsp_resp_o,
  output logic rd_rsp_last_o
);

  localparam int unsigned ParentIndexWidth = $clog2(ParentEntries);

  typedef struct packed {
    logic valid;
    logic [AxiDataWidth-1:0] data;
    logic [AxiDataWidth / 8-1:0] valid_byte_mask;
    logic [AxiDataWidth / 8-1:0] error_byte_mask;
    logic [1:0] resp;
  } read_assembly_t;

  read_assembly_t assembly_q [ParentEntries];
  logic rsp_hold_valid_q;
  logic [ParentIndexWidth-1:0] rsp_hold_parent_idx_q;
  logic rsp_hold_parent_valid_q;
  logic [AxiIdWidth-1:0] rsp_hold_id_q;
  logic [AxiDataWidth-1:0] rsp_hold_data_q;
  logic [1:0] rsp_hold_resp_q;
  logic rsp_hold_last_q;
  logic rsp_fire;
  logic fragment_fire;
  logic [AxiIdWidth-1:0] fragment_rsp_id;
  logic [AxiDataWidth-1:0] fragment_rsp_data;
  logic [1:0] fragment_rsp_resp;
  logic [ParentIndexWidth-1:0] fragment_parent_idx_q;
  logic [AxiIdWidth-1:0] fragment_axi_id_q;
  logic fragment_last_q;
  logic fragment_last_fragment_q;
  logic [1:0] fragment_idx_q;
  logic fragment_pending_q;
  logic [AxiDataWidth-1:0] fragment_data_q;
  logic [AxiDataWidth / 8-1:0] fragment_be_q;
  logic [1:0] fragment_resp_q;
  logic [AxiDataWidth-1:0] mapped_axi_data;
  logic [AxiDataWidth / 8-1:0] mapped_axi_be;

  axi2chi_nocoh_rd_byte_map #(
    .AxiDataWidth(AxiDataWidth),
    .ChiDataWidth(ChiDataWidth),
    .CacheLineBytes(CacheLineBytes)
  ) rd_byte_map (
    .chi_data_i(fragment_data_i),
    .chi_be_i(fragment_be_i),
    .axi_byte_offset_i(fragment_axi_byte_offset_i),
    .fragment_byte_count_i(fragment_byte_count_i),
    .line_byte_offset_i(fragment_line_byte_offset_i),
    .axi_data_o(mapped_axi_data),
    .axi_valid_be_o(mapped_axi_be)
  );

  always_comb begin
    fragment_rsp_id = fragment_axi_id_i;
    fragment_rsp_data = fragment_idx_i == 0 ? mapped_axi_data :
        assembly_q[fragment_parent_idx_i].data | mapped_axi_data;
    fragment_rsp_resp = (!fragment_lookup_valid_i || fragment_resp_i[1] ||
        assembly_q[fragment_parent_idx_i].resp[1]) ? 2'b10 : 2'b00;
    fragment_ready_o = fragment_lookup_valid_i && !fragment_pending_q &&
        (!rsp_hold_valid_q || rd_rsp_ready_i);
    rd_rsp_parent_valid_o = rsp_hold_parent_valid_q;
    rd_rsp_parent_idx_o = rsp_hold_parent_idx_q;
    rd_rsp_valid_o = rsp_hold_valid_q;
    rd_rsp_id_o = rsp_hold_id_q;
    rd_rsp_data_o = rsp_hold_data_q;
    rd_rsp_resp_o = rsp_hold_resp_q;
    rd_rsp_last_o = rsp_hold_last_q;
    rsp_fire = rd_rsp_valid_o && rd_rsp_ready_i;
    fragment_fire = fragment_valid_i && fragment_ready_o;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      rsp_hold_valid_q <= 1'b0;
      rsp_hold_parent_valid_q <= 1'b0;
      rsp_hold_parent_idx_q <= '0;
      rsp_hold_id_q <= '0;
      rsp_hold_data_q <= '0;
      rsp_hold_resp_q <= '0;
      rsp_hold_last_q <= 1'b0;
      fragment_parent_idx_q <= '0;
      fragment_axi_id_q <= '0;
      fragment_last_q <= 1'b0;
      fragment_last_fragment_q <= 1'b0;
      fragment_idx_q <= '0;
      fragment_pending_q <= 1'b0;
      fragment_data_q <= '0;
      fragment_be_q <= '0;
      fragment_resp_q <= '0;
      for (int unsigned idx = 0; idx < ParentEntries; idx++) begin
        assembly_q[idx] <= '0;
      end
    end else begin
      if (fragment_pending_q) begin
        assembly_q[fragment_parent_idx_q].data <=
            fragment_idx_q == 0 ? fragment_data_q :
            assembly_q[fragment_parent_idx_q].data | fragment_data_q;
        assembly_q[fragment_parent_idx_q].valid_byte_mask <=
            assembly_q[fragment_parent_idx_q].valid_byte_mask | fragment_be_q;
        assembly_q[fragment_parent_idx_q].error_byte_mask <=
            assembly_q[fragment_parent_idx_q].error_byte_mask |
            ({AxiDataWidth / 8 {fragment_resp_q[1]}} & fragment_be_q);
        assembly_q[fragment_parent_idx_q].resp <=
            assembly_q[fragment_parent_idx_q].resp | fragment_resp_q;
        fragment_pending_q <= 1'b0;
        if (fragment_last_fragment_q) begin
          rsp_hold_valid_q <= 1'b1;
          rsp_hold_parent_valid_q <= 1'b1;
          rsp_hold_parent_idx_q <= fragment_parent_idx_q;
          rsp_hold_id_q <= fragment_axi_id_q;
          rsp_hold_data_q <= fragment_idx_q == 0 ? fragment_data_q :
              assembly_q[fragment_parent_idx_q].data | fragment_data_q;
          rsp_hold_resp_q <= assembly_q[fragment_parent_idx_q].resp |
              fragment_resp_q;
          rsp_hold_last_q <= fragment_last_q;
          assembly_q[fragment_parent_idx_q] <= '0;
        end
      end else if (fragment_fire) begin
        fragment_parent_idx_q <= fragment_parent_idx_i;
        fragment_axi_id_q <= fragment_axi_id_i;
        fragment_last_q <= fragment_last_i;
        fragment_last_fragment_q <= fragment_last_fragment_i;
        fragment_idx_q <= fragment_idx_i;
        fragment_data_q <= mapped_axi_data;
        fragment_be_q <= mapped_axi_be;
        fragment_resp_q <= fragment_rsp_resp;
        if (fragment_last_fragment_i && fragment_idx_i == 0) begin
          rsp_hold_valid_q <= 1'b1;
          rsp_hold_parent_valid_q <= fragment_lookup_valid_i;
          rsp_hold_parent_idx_q <= fragment_parent_idx_i;
          rsp_hold_id_q <= fragment_axi_id_i;
          rsp_hold_data_q <= mapped_axi_data;
          rsp_hold_resp_q <= fragment_rsp_resp;
          rsp_hold_last_q <= fragment_last_i;
          fragment_pending_q <= 1'b0;
        end else begin
          fragment_pending_q <= 1'b1;
        end
      end else if (rsp_fire) begin
        rsp_hold_valid_q <= 1'b0;
        rsp_hold_parent_valid_q <= 1'b0;
      end
    end
  end

endmodule

`default_nettype wire
