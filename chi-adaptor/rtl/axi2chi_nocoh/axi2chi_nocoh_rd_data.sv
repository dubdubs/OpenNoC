// RXDAT-to-AXI read data assembly skeleton.

`default_nettype none

module axi2chi_nocoh_rd_data #(
  parameter int unsigned AxiDataWidth = 128,
  parameter int unsigned AxiIdWidth = 4,
  parameter int unsigned ChiDataWidth = 256,
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

  read_assembly_t assembly_q [ChildEntries];
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

  always_comb begin
    fragment_rsp_id = fragment_axi_id_i;
    fragment_rsp_data = fragment_data_i[AxiDataWidth-1:0];
    fragment_rsp_resp = (!fragment_lookup_valid_i || fragment_resp_i[1]) ? 2'b10 : 2'b00;
    fragment_ready_o = fragment_lookup_valid_i && (!rsp_hold_valid_q || rd_rsp_ready_i);
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
      for (int unsigned idx = 0; idx < ChildEntries; idx++) begin
        assembly_q[idx] <= '0;
      end
    end else begin
      if (fragment_fire) begin
        rsp_hold_valid_q <= 1'b1;
        rsp_hold_parent_valid_q <= fragment_lookup_valid_i;
        rsp_hold_parent_idx_q <= fragment_parent_idx_i;
        rsp_hold_id_q <= fragment_rsp_id;
        rsp_hold_data_q <= fragment_rsp_data;
        rsp_hold_resp_q <= fragment_rsp_resp;
        rsp_hold_last_q <= fragment_last_i;
      end else if (rsp_fire) begin
        rsp_hold_valid_q <= 1'b0;
        rsp_hold_parent_valid_q <= 1'b0;
      end
    end
  end

endmodule

`default_nettype wire
