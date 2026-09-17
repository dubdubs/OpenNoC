// Copyright 2026
//
// Shared constants and helper functions for chi_rni, the Scheme-1
// (non-coherent AXI-to-CHI) adaptor.  This header is `include`d by both
// the standalone segmenter and the transaction engine so the child-size
// algorithm and DataID layout have exactly one source of truth.
//
// Wire-format opcodes follow AMBA CHI Issue E.b (see OpenNoC
// rtl/include/chie_defines.v).

`ifndef CHI_RNI_DEFINES_SVH
`define CHI_RNI_DEFINES_SVH

// AXI AxBURST encodings
`define CHI_RNI_AXI_BURST_FIXED 2'b00
`define CHI_RNI_AXI_BURST_INCR  2'b01
`define CHI_RNI_AXI_BURST_WRAP  2'b10

// AXI RRESP / BRESP encodings
`define CHI_RNI_AXI_OKAY   2'b00
`define CHI_RNI_AXI_EXOKAY 2'b01
`define CHI_RNI_AXI_SLVERR 2'b10
`define CHI_RNI_AXI_DECERR 2'b11

// Decoded CHI RSP channel "kind".  The profile shim decodes the 5-bit
// RSP opcode into this 2-bit tag; Scheme 6.5 only accepts these write
// completion shapes (all with ExpCompAck=0).
`define CHI_RNI_RSP_DBIDRESP      2'b00
`define CHI_RNI_RSP_COMPDBIDRESP  2'b01
`define CHI_RNI_RSP_COMP          2'b10

// CHI REQ opcodes (Issue E.b).  ReadNoSnp is the only V1 read opcode;
// WriteNoSnpPtl is the V1 default write opcode (WriteNoSnpFull optional).
`define CHI_RNI_OPCODE_READNOSNP      7'h04
`define CHI_RNI_OPCODE_WRITENOSNPPTL  7'h1c
`define CHI_RNI_OPCODE_WRITENOSNPFULL 7'h1d

// CHI Size encodes 1B..64B (REQ Size field is 3 bits, 0..6).
`define CHI_RNI_MAX_CHILD_BYTES 64
`define CHI_RNI_MAX_CHILD_LOG2  6

// Largest aligned power-of-two child size (log2) starting at abs_low that
// fits within `limit` bytes and is no bigger than 2^max_log2.
// Returns 0 (1B child) in the worst case, which is always legal.
function automatic [2:0] chi_rni_next_child_size_log2(
    input logic [11:0] abs_low,
    input integer      limit,
    input integer      max_log2);
  integer s;
  begin
    s = max_log2;
    while (s > 0 && ((1 << s) > limit || |(abs_low & ((12'h1 << s) - 12'd1))))
      s = s - 1;
    chi_rni_next_child_size_log2 = s[2:0];
  end
endfunction

// Number of DAT beats for a child of 2^size_log2 bytes on a CHI bus of
// 2^chi_bytes_log2 bytes per beat.  At least one beat.
function automatic integer chi_rni_data_beat_count(input integer size_log2,
                                                   input integer chi_bytes_log2);
  integer beats;
  begin
    beats = (1 << size_log2) >> chi_bytes_log2;
    if (beats == 0) beats = 1;
    chi_rni_data_beat_count = beats;
  end
endfunction

// DATAID_LAYOUT selects the selected CHI revision's DataID rule.  V1 uses
// the IHI0050E packetization rule: DataID identifies Addr[5:4] of the lowest
// addressed byte in a DAT packet.  No ordinal-only encoding is permitted.
`define CHI_RNI_DATAID_LAYOUT_IHI0050E 0

// ORDER_POLICY selects whether DAT beats may arrive out of ordinal order.
`define CHI_RNI_ORDER_POLICY_ANY_ORDER   0
`define CHI_RNI_ORDER_POLICY_PERMISSIVE  `CHI_RNI_ORDER_POLICY_ANY_ORDER
`define CHI_RNI_ORDER_POLICY_IN_ORDER    1

// Keep child address and size in the profile API.  IHI0050E DataID is the
// 128-bit chunk offset within the 64B transfer window.  One DAT packet spans
// DATA_WIDTH/128 adjacent chunks, so ordinal advances DataID by that amount.
function automatic integer chi_rni_expected_dataid(
    input integer dataid_layout,
    input logic [63:0] child_addr,
    input integer child_size_log2,
    input integer ordinal,
    input integer chi_bytes_log2);
  integer chunks_per_packet;
  begin
    child_size_log2 = child_size_log2;
    chunks_per_packet = 1 << (chi_bytes_log2 - 4);
    case (dataid_layout)
      `CHI_RNI_DATAID_LAYOUT_IHI0050E:
          chi_rni_expected_dataid =
              (child_addr[5:4] + ordinal * chunks_per_packet) & 2'b11;
      default: chi_rni_expected_dataid = -1;
    endcase
  end
endfunction

`endif
