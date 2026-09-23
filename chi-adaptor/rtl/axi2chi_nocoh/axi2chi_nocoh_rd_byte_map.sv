// Maps one CHI read fragment into AXI beat byte lanes.

`default_nettype none

module axi2chi_nocoh_rd_byte_map #(
  parameter int unsigned AxiDataWidth = 128,
  parameter int unsigned ChiDataWidth = 256,
  parameter int unsigned CacheLineBytes = 64
) (
  input logic [ChiDataWidth-1:0] chi_data_i,
  input logic [ChiDataWidth / 8-1:0] chi_be_i,
  input logic [$clog2(AxiDataWidth / 8 + 1)-1:0] axi_byte_offset_i,
  input logic [$clog2(AxiDataWidth / 8 + 1)-1:0] fragment_byte_count_i,
  input logic [$clog2(CacheLineBytes)-1:0] line_byte_offset_i,
  output logic [AxiDataWidth-1:0] axi_data_o,
  output logic [AxiDataWidth / 8-1:0] axi_valid_be_o
);

  localparam int unsigned AxiBytes = AxiDataWidth / 8;
  localparam int unsigned ChiBytes = ChiDataWidth / 8;

  always_comb begin
    axi_data_o = '0;
    axi_valid_be_o = '0;
    for (int unsigned byte_idx = 0; byte_idx < AxiBytes; byte_idx++) begin
      if (byte_idx >= axi_byte_offset_i &&
          byte_idx < axi_byte_offset_i + fragment_byte_count_i &&
          byte_idx - axi_byte_offset_i < ChiBytes) begin
        axi_data_o[byte_idx * 8 +: 8] =
            chi_data_i[(byte_idx - axi_byte_offset_i) * 8 +: 8];
        axi_valid_be_o[byte_idx] =
            chi_be_i[byte_idx - axi_byte_offset_i];
      end
    end
  end

endmodule

`default_nettype wire
