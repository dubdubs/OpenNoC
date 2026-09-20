/*
 * Copyright (c) 2024 Beijing Institute of Open Source Chip
 * OpenNoC is licensed under Mulan PSL v2.
 *
 * Atomic dispatch boundary between the AXI fragment adapter, the child
 * allocator/request engine, and the canonical line data plane.  A normal
 * fragment is accepted only when the child descriptor and line-plane
 * configuration can both handshake in the same cycle.
 */

module rni_fragment_dispatch #(
    parameter integer ADDR_WIDTH = 44,
    parameter integer AXI_DATA_WIDTH = 128,
    parameter integer PARENT_ID_WIDTH = 6,
    parameter integer CHILD_ID_WIDTH = 6,
    parameter integer BEAT_ID_WIDTH = 8,
    parameter integer FRAGMENT_ID_WIDTH = BEAT_ID_WIDTH + 1,
    parameter integer AXI_BYTES = AXI_DATA_WIDTH / 8,
    parameter integer AXI_BYTE_OFFSET_WIDTH =
        (AXI_BYTES <= 1) ? 1 : $clog2(AXI_BYTES)
) (
    input  wire fragment_valid_i,
    output wire fragment_ready_o,
    input  wire [PARENT_ID_WIDTH-1:0] fragment_parent_id_i,
    input  wire [BEAT_ID_WIDTH-1:0] fragment_beat_id_i,
    input  wire [FRAGMENT_ID_WIDTH-1:0] fragment_id_i,
    input  wire fragment_write_i,
    input  wire [ADDR_WIDTH-1:0] fragment_line_addr_i,
    input  wire [5:0] fragment_line_offset_i,
    input  wire [AXI_BYTE_OFFSET_WIDTH-1:0]
        fragment_beat_offset_i,
    input  wire [6:0] fragment_byte_count_i,
    input  wire [63:0] fragment_line_mask_i,
    input  wire [AXI_BYTES-1:0] fragment_lane_mask_i,
    input  wire fragment_last_i,
    input  wire fragment_last_beat_i,
    input  wire fragment_error_i,

    input  wire child_alloc_valid_i,
    output wire child_alloc_ready_o,
    input  wire [CHILD_ID_WIDTH-1:0] child_alloc_id_i,

    output wire line_cfg_valid_o,
    input  wire line_cfg_ready_i,
    input  wire line_cfg_error_i,
    output wire line_cfg_write_o,
    output wire [PARENT_ID_WIDTH-1:0] line_cfg_parent_id_o,
    output wire [CHILD_ID_WIDTH-1:0] line_cfg_child_id_o,
    output wire [BEAT_ID_WIDTH-1:0] line_cfg_beat_id_o,
    output wire [FRAGMENT_ID_WIDTH-1:0] line_cfg_fragment_id_o,
    output wire [ADDR_WIDTH-1:0] line_cfg_line_addr_o,
    output wire [5:0] line_cfg_line_offset_o,
    output wire [AXI_BYTE_OFFSET_WIDTH-1:0] line_cfg_lane_offset_o,
    output wire [6:0] line_cfg_byte_count_o,
    output wire [63:0] line_cfg_byte_mask_o,
    output wire line_cfg_beat_last_o,
    output wire line_cfg_parent_last_o,

    output wire child_desc_valid_o,
    input  wire child_desc_ready_i,
    output wire [PARENT_ID_WIDTH-1:0] child_desc_parent_id_o,
    output wire [CHILD_ID_WIDTH-1:0] child_desc_child_id_o,
    output wire [BEAT_ID_WIDTH-1:0] child_desc_beat_id_o,
    output wire [FRAGMENT_ID_WIDTH-1:0] child_desc_fragment_id_o,
    output wire child_desc_write_o,
    output wire [ADDR_WIDTH-1:0] child_desc_line_addr_o,
    output wire [63:0] child_desc_byte_mask_o,
    output wire child_desc_last_beat_o,
    output wire child_desc_error_o
);

    wire dispatch_error;
    wire dispatch_available;

    assign dispatch_error = fragment_error_i || line_cfg_error_i;
    assign dispatch_available = dispatch_error || line_cfg_ready_i;

    assign child_desc_valid_o = fragment_valid_i && child_alloc_valid_i &&
        dispatch_available;
    assign line_cfg_valid_o = fragment_valid_i && child_alloc_valid_i &&
        child_desc_ready_i && !fragment_error_i;
    assign fragment_ready_o = child_alloc_valid_i && child_desc_ready_i &&
        dispatch_available;
    assign child_alloc_ready_o = fragment_valid_i && child_desc_ready_i &&
        dispatch_available;

    assign line_cfg_write_o = fragment_write_i;
    assign line_cfg_parent_id_o = fragment_parent_id_i;
    assign line_cfg_child_id_o = child_alloc_id_i;
    assign line_cfg_beat_id_o = fragment_beat_id_i;
    assign line_cfg_fragment_id_o = fragment_id_i;
    assign line_cfg_line_addr_o = fragment_line_addr_i;
    assign line_cfg_line_offset_o = fragment_line_offset_i;
    assign line_cfg_lane_offset_o = fragment_beat_offset_i;
    assign line_cfg_byte_count_o = fragment_byte_count_i;
    assign line_cfg_byte_mask_o = fragment_line_mask_i;
    assign line_cfg_beat_last_o = fragment_last_i;
    assign line_cfg_parent_last_o = fragment_last_beat_i;

    assign child_desc_parent_id_o = fragment_parent_id_i;
    assign child_desc_child_id_o = child_alloc_id_i;
    assign child_desc_beat_id_o = fragment_beat_id_i;
    assign child_desc_fragment_id_o = fragment_id_i;
    assign child_desc_write_o = fragment_write_i;
    assign child_desc_line_addr_o = fragment_line_addr_i;
    assign child_desc_byte_mask_o = fragment_line_mask_i;
    assign child_desc_last_beat_o = fragment_last_beat_i;
    assign child_desc_error_o = dispatch_error;

    initial begin
        if (FRAGMENT_ID_WIDTH < (BEAT_ID_WIDTH + 1))
            $fatal(1, "rni_fragment_dispatch: fragment ID is too narrow");
        if (AXI_BYTES != (AXI_DATA_WIDTH / 8))
            $fatal(1, "rni_fragment_dispatch: AXI byte derivation mismatch");
    end

endmodule
