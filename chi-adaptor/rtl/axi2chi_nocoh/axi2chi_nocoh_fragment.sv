// AXI beat to cache-line fragment geometry.

`default_nettype none

module axi2chi_nocoh_fragment #(
  parameter int unsigned AxiAddrWidth = 64,
  parameter int unsigned AxiDataWidth = 128,
  parameter int unsigned AxsizeWidth = 3,
  parameter int unsigned CacheLineBytes = 64
) (
  input logic [AxiAddrWidth-1:0] axi_addr_i,
  input logic [AxsizeWidth-1:0] axi_size_i,
  output logic fragment_two_valid_o,
  output logic [AxiAddrWidth-1:0] fragment0_addr_o,
  output logic [$clog2(AxiDataWidth / 8 + 1)-1:0] fragment0_axi_offset_o,
  output logic [$clog2(CacheLineBytes)-1:0] fragment0_line_offset_o,
  output logic [$clog2(AxiDataWidth / 8 + 1)-1:0] fragment0_byte_count_o,
  output logic [AxiAddrWidth-1:0] fragment1_addr_o,
  output logic [$clog2(AxiDataWidth / 8 + 1)-1:0] fragment1_axi_offset_o,
  output logic [$clog2(CacheLineBytes)-1:0] fragment1_line_offset_o,
  output logic [$clog2(AxiDataWidth / 8 + 1)-1:0] fragment1_byte_count_o
);

  localparam int unsigned AxiBytes = AxiDataWidth / 8;
  localparam int unsigned ByteCountWidth = $clog2(AxiBytes + 1);
  localparam int unsigned LineOffsetWidth = $clog2(CacheLineBytes);

  logic [AxiAddrWidth-1:0] beat_bytes;
  logic [AxiAddrWidth-1:0] line_remaining;
  logic [AxiAddrWidth-1:0] fragment0_bytes;
  logic [AxiAddrWidth-1:0] fragment1_bytes;

  always_comb begin
    beat_bytes = AxiAddrWidth'(1) << axi_size_i;
    line_remaining = AxiAddrWidth'(CacheLineBytes) -
        (axi_addr_i & AxiAddrWidth'(CacheLineBytes - 1));
    fragment_two_valid_o = beat_bytes > line_remaining;
    fragment0_bytes = fragment_two_valid_o ? line_remaining : beat_bytes;
    fragment1_bytes = beat_bytes - fragment0_bytes;

    fragment0_addr_o = axi_addr_i;
    fragment0_axi_offset_o = '0;
    fragment0_line_offset_o = axi_addr_i[LineOffsetWidth-1:0];
    fragment0_byte_count_o = ByteCountWidth'(fragment0_bytes);
    fragment1_addr_o = (axi_addr_i & ~AxiAddrWidth'(CacheLineBytes - 1)) +
        AxiAddrWidth'(CacheLineBytes);
    fragment1_axi_offset_o = ByteCountWidth'(fragment0_bytes);
    fragment1_line_offset_o = '0;
    fragment1_byte_count_o = ByteCountWidth'(fragment1_bytes);
  end

endmodule

`default_nettype wire
