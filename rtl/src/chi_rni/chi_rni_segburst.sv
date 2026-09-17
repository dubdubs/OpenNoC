// Copyright 2026
//
// chi_rni_segburst: incremental AXI-parent -> CHI-child segmenter for the
// Scheme-1 non-coherent adaptor.
//
// This replaces the role of OpenNoC rni_segburst.v with the behaviour the
// scheme document (axi_to_chi_scheme1.md, section 6) actually requires:
//
//   * FIXED      : one exact child per AXI beat, same address each beat.
//   * Device     : one exact child per AXI beat, no coalescing / over-fetch.
//                  (unaligned Device beats are rejected upstream, in the
//                  transaction engine's admission check)
//   * Normal INCR: exact power-of-two decomposition into naturally-aligned
//                  1B..64B children.  With coalesce=1 adjacent beats may
//                  merge; with coalesce=0 children never cross a beat
//                  boundary (unaligned beats are decomposed in place).
//
// The module is intentionally small and testable.  The transaction engine
// keeps per-parent byte position itself and calls
// chi_rni_next_child_size_log2() directly; this module is the single-parent
// reference/unit-test form of the same algorithm.

`include "chi_rni_defines.svh"

module chi_rni_segburst #(
    parameter int unsigned ADDR_WIDTH = 44
)(
    input  logic clk,
    input  logic rst_n,

    // New parent descriptor
    input  logic                  start_valid,
    output logic                  start_ready,
    input  logic [ADDR_WIDTH-1:0] start_addr,
    input  logic [7:0]            start_len,
    input  logic [2:0]            start_size,
    input  logic [1:0]            start_burst,
    input  logic                  coalesce,   // Normal + BURST_BEAT_COALESCING
    input  logic                  device,     // Device access class

    // Next child (valid until child_ready)
    output logic                  child_valid,
    input  logic                  child_ready,
    output logic [ADDR_WIDTH-1:0] child_addr,
    output logic [2:0]            child_size,   // log2, 0..6
    output logic [6:0]            child_bytes,  // 1..64
    output logic                  child_last
);

  typedef enum logic [0:0] {S_IDLE, S_RUN} state_t;
  state_t state_q;

  logic [ADDR_WIDTH-1:0] addr_q;
  logic [7:0]            len_q;
  logic [2:0]            size_q;
  logic [1:0]            burst_q;
  logic                  coalesce_q;
  logic                  device_q;
  logic [14:0]           pos_q;    // bytes already issued (<= 256*64 = 16384)
  logic [14:0]           total_q;  // parent byte count

  logic [ADDR_WIDTH-1:0] child_addr_c;
  logic [2:0]            child_size_c;
  logic [6:0]            child_bytes_c;

  assign start_ready = (state_q == S_IDLE);

  always_comb begin
    integer beat_bytes, remaining, limit, max_log2;
    logic [ADDR_WIDTH-1:0] byte_pos;
    begin
      beat_bytes = 1 << size_q;
      remaining  = total_q - pos_q;
      child_addr_c = addr_q;
      child_size_c = size_q;
      child_bytes_c = beat_bytes[6:0];

      if (burst_q == `CHI_RNI_AXI_BURST_FIXED) begin
        // Same address every beat; per-beat exact child.
        child_addr_c  = addr_q;
        child_size_c  = size_q;
        child_bytes_c = beat_bytes[6:0];
      end else if (device_q) begin
        // Device: exactly one child per beat.  Unaligned beats are rejected
        // upstream, so (addr_q + pos_q) is naturally Size-aligned.
        child_addr_c  = addr_q + pos_q;
        child_size_c  = size_q;
        child_bytes_c = beat_bytes[6:0];
      end else begin
        // Normal INCR: exact power-of-two decomposition.
        byte_pos     = addr_q + pos_q;
        child_addr_c = byte_pos;
        if (coalesce_q) begin
          limit = (remaining < `CHI_RNI_MAX_CHILD_BYTES)
                  ? remaining : `CHI_RNI_MAX_CHILD_BYTES;
          max_log2 = `CHI_RNI_MAX_CHILD_LOG2;
        end else begin
          limit    = beat_bytes - (pos_q % beat_bytes);
          max_log2 = size_q;
        end
        child_size_c  = chi_rni_next_child_size_log2(child_addr_c[11:0],
                                                     limit, max_log2);
        child_bytes_c = (1 << child_size_c);
      end
    end
  end

  assign child_valid = (state_q == S_RUN);
  assign child_addr  = child_addr_c;
  assign child_size  = child_size_c;
  assign child_bytes = child_bytes_c;
  assign child_last  = (pos_q + child_bytes_c == total_q);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= S_IDLE;
      pos_q   <= '0;
      total_q <= '0;
    end else begin
      case (state_q)
        S_IDLE: begin
          if (start_valid && start_ready) begin
            addr_q     <= start_addr;
            len_q      <= start_len;
            size_q     <= start_size;
            burst_q    <= start_burst;
            coalesce_q <= coalesce;
            device_q   <= device;
            pos_q      <= '0;
            total_q    <= (start_len + 8'd1) << start_size;
            state_q    <= S_RUN;
          end
        end
        S_RUN: begin
          if (child_valid && child_ready) begin
            pos_q <= pos_q + child_bytes_c;
            if (child_last) state_q <= S_IDLE;
          end
        end
        default: state_q <= S_IDLE;
      endcase
    end
  end

endmodule
