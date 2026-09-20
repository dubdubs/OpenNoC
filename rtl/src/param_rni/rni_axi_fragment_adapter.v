/*
 * Copyright (c) 2024 Beijing Institute of Open Source Chip
 * OpenNoC is licensed under Mulan PSL v2.
 * You can use this software according to the terms and conditions of the
 * Mulan PSL v2.
 *
 * AXI beat to canonical 64-byte line fragment adapter.
 *
 * One accepted AXI beat produces one or two fragment descriptors.  The
 * descriptors are held internally and emitted in address order.  WRAP is
 * deliberately rejected until complete WRAP address generation is provided.
 */

module rni_axi_fragment_adapter #(
    parameter integer ADDR_WIDTH = 44,
    parameter integer AXI_DATA_WIDTH = 128,
    parameter integer PARENT_ID_WIDTH = 6,
    parameter integer BEAT_ID_WIDTH = 8,
    parameter integer FRAGMENT_ID_WIDTH = BEAT_ID_WIDTH + 1,
    parameter integer AXI_BYTES = AXI_DATA_WIDTH / 8,
    parameter integer AXI_BYTE_OFFSET_WIDTH =
        (AXI_BYTES <= 1) ? 1 : $clog2(AXI_BYTES)
) (
    input  wire                         clk_i,
    input  wire                         rst_i,

    input  wire                         req_valid_i,
    output wire                         req_ready_o,
    input  wire [PARENT_ID_WIDTH-1:0]   req_parent_id_i,
    input  wire [BEAT_ID_WIDTH-1:0]     req_beat_id_i,
    input  wire [ADDR_WIDTH-1:0]        req_axaddr_i,
    input  wire [2:0]                   req_axsize_i,
    input  wire [1:0]                   req_axburst_i,
    input  wire                         req_write_i,
    input  wire                         req_first_beat_i,
    input  wire                         req_last_beat_i,

    output wire                         fragment_valid_o,
    input  wire                         fragment_ready_i,
    output wire [PARENT_ID_WIDTH-1:0]   fragment_parent_id_o,
    output wire [BEAT_ID_WIDTH-1:0]     fragment_beat_id_o,
    output wire [FRAGMENT_ID_WIDTH-1:0] fragment_id_o,
    output wire                         fragment_write_o,
    output wire [ADDR_WIDTH-1:0]        fragment_line_addr_o,
    output wire [5:0]                   fragment_line_byte_offset_o,
    output wire [AXI_BYTE_OFFSET_WIDTH-1:0]
                                               fragment_beat_byte_offset_o,
    output wire [6:0]                   fragment_byte_count_o,
    output wire [63:0]                  fragment_line_byte_mask_o,
    output wire [AXI_BYTES-1:0]         fragment_beat_lane_mask_o,
    output wire                         fragment_first_o,
    output wire                         fragment_last_o,
    output wire                         fragment_last_beat_o,
    output wire                         req_error_o
);

    localparam integer AXI_SIZE_MAX = $clog2(AXI_BYTES);
    localparam [1:0] AXI_BURST_FIXED = 2'b00;
    localparam [1:0] AXI_BURST_INCR = 2'b01;

    reg                              valid_q;
    reg [1:0]                        fragment_count_q;
    reg [PARENT_ID_WIDTH-1:0]        parent_id_q;
    reg [BEAT_ID_WIDTH-1:0]          beat_id_q;
    reg [FRAGMENT_ID_WIDTH-1:0]      fragment_id_q;
    reg                              fragment_write_q;
    reg [ADDR_WIDTH-1:0]             line_addr_q;
    reg [5:0]                        line_byte_offset_q;
    reg [AXI_BYTE_OFFSET_WIDTH-1:0]  beat_byte_offset_q;
    reg [6:0]                        byte_count_q;
    reg [63:0]                       line_byte_mask_q;
    reg [AXI_BYTES-1:0]              beat_lane_mask_q;
    reg                              first_fragment_q;
    reg                              last_fragment_q;
    reg                              last_beat_q;
    reg                              error_q;

    reg [PARENT_ID_WIDTH-1:0]        second_parent_id_q;
    reg [BEAT_ID_WIDTH-1:0]          second_beat_id_q;
    reg [FRAGMENT_ID_WIDTH-1:0]      second_fragment_id_q;
    reg                              second_fragment_write_q;
    reg [ADDR_WIDTH-1:0]             second_line_addr_q;
    reg [5:0]                        second_line_byte_offset_q;
    reg [AXI_BYTE_OFFSET_WIDTH-1:0]  second_beat_byte_offset_q;
    reg [6:0]                        second_byte_count_q;
    reg [63:0]                       second_line_byte_mask_q;
    reg [AXI_BYTES-1:0]              second_beat_lane_mask_q;
    reg                              second_first_fragment_q;
    reg                              second_last_fragment_q;
    reg                              second_last_beat_q;
    reg                              second_error_q;

    reg [1:0]                        generated_count;
    reg [PARENT_ID_WIDTH-1:0]        generated_parent_id [0:1];
    reg [BEAT_ID_WIDTH-1:0]          generated_beat_id [0:1];
    reg [FRAGMENT_ID_WIDTH-1:0]      generated_fragment_id [0:1];
    reg                              generated_fragment_write [0:1];
    reg [ADDR_WIDTH-1:0]             generated_line_addr [0:1];
    reg [5:0]                        generated_line_byte_offset [0:1];
    reg [AXI_BYTE_OFFSET_WIDTH-1:0]  generated_beat_byte_offset [0:1];
    reg [6:0]                        generated_byte_count [0:1];
    reg [63:0]                       generated_line_byte_mask [0:1];
    reg [AXI_BYTES-1:0]              generated_beat_lane_mask [0:1];
    reg                              generated_first_fragment [0:1];
    reg                              generated_last_fragment [0:1];
    reg                              generated_last_beat [0:1];
    reg                              generated_error [0:1];

    reg [ADDR_WIDTH:0]               transfer_bytes;
    reg [ADDR_WIDTH:0]               aligned_beat_addr;
    reg [ADDR_WIDTH:0]               beat_addr;
    reg [ADDR_WIDTH:0]               beat_bytes;
    reg [ADDR_WIDTH:0]               beat_end_addr;
    reg [ADDR_WIDTH:0]               absolute_byte_addr;
    reg [ADDR_WIDTH:0]               first_line_addr;
    reg [ADDR_WIDTH:0]               second_line_addr;
    reg [AXI_BYTE_OFFSET_WIDTH-1:0]  lane_index;
    reg [5:0]                        line_index;
    reg                              request_error;
    integer                          byte_index;
    integer                          descriptor_index;

    assign req_ready_o = !valid_q ||
                         (fragment_ready_i && (fragment_count_q == 2'd1));

    assign fragment_valid_o = valid_q;
    assign fragment_parent_id_o = parent_id_q;
    assign fragment_beat_id_o = beat_id_q;
    assign fragment_id_o = fragment_id_q;
    assign fragment_write_o = fragment_write_q;
    assign fragment_line_addr_o = line_addr_q;
    assign fragment_line_byte_offset_o = line_byte_offset_q;
    assign fragment_beat_byte_offset_o = beat_byte_offset_q;
    assign fragment_byte_count_o = byte_count_q;
    assign fragment_line_byte_mask_o = line_byte_mask_q;
    assign fragment_beat_lane_mask_o = beat_lane_mask_q;
    assign fragment_first_o = first_fragment_q;
    assign fragment_last_o = last_fragment_q;
    assign fragment_last_beat_o = last_beat_q;
    assign req_error_o = error_q;

    /*
     * Build both possible descriptors combinationally.  All address
     * arithmetic is performed with an extra bit so address overflow can be
     * reported instead of silently wrapping.
     */
    always @* begin
        generated_count = 2'd1;
        transfer_bytes = {{ADDR_WIDTH{1'b0}}, 1'b1} << req_axsize_i;
        aligned_beat_addr = {1'b0, req_axaddr_i} & ~(transfer_bytes - 1'b1);
        beat_addr = {1'b0, req_axaddr_i};
        beat_bytes = transfer_bytes -
                     ({1'b0, req_axaddr_i} - aligned_beat_addr);
        beat_end_addr = {(ADDR_WIDTH + 1){1'b0}};
        absolute_byte_addr = {(ADDR_WIDTH + 1){1'b0}};
        first_line_addr = {(ADDR_WIDTH + 1){1'b0}};
        second_line_addr = {(ADDR_WIDTH + 1){1'b0}};
        lane_index = {AXI_BYTE_OFFSET_WIDTH{1'b0}};
        line_index = 6'b0;
        request_error = 1'b0;
        descriptor_index = 0;

        generated_parent_id[0] = req_parent_id_i;
        generated_parent_id[1] = req_parent_id_i;
        generated_beat_id[0] = req_beat_id_i;
        generated_beat_id[1] = req_beat_id_i;
        generated_fragment_id[0] =
            ({req_beat_id_i, 1'b0});
        generated_fragment_id[1] =
            ({req_beat_id_i, 1'b0} + 1'b1);
        generated_fragment_write[0] = req_write_i;
        generated_fragment_write[1] = req_write_i;
        generated_line_addr[0] = {ADDR_WIDTH{1'b0}};
        generated_line_addr[1] = {ADDR_WIDTH{1'b0}};
        generated_line_byte_offset[0] = 6'b0;
        generated_line_byte_offset[1] = 6'b0;
        generated_beat_byte_offset[0] =
            {AXI_BYTE_OFFSET_WIDTH{1'b0}};
        generated_beat_byte_offset[1] =
            {AXI_BYTE_OFFSET_WIDTH{1'b0}};
        generated_byte_count[0] = 7'b0;
        generated_byte_count[1] = 7'b0;
        generated_line_byte_mask[0] = 64'b0;
        generated_line_byte_mask[1] = 64'b0;
        generated_beat_lane_mask[0] = {AXI_BYTES{1'b0}};
        generated_beat_lane_mask[1] = {AXI_BYTES{1'b0}};
        generated_first_fragment[0] = 1'b1;
        generated_first_fragment[1] = 1'b0;
        generated_last_fragment[0] = 1'b1;
        generated_last_fragment[1] = 1'b1;
        generated_last_beat[0] = req_last_beat_i;
        generated_last_beat[1] = req_last_beat_i;
        generated_error[0] = 1'b0;
        generated_error[1] = 1'b0;

        if (req_axsize_i > AXI_SIZE_MAX) begin
            request_error = 1'b1;
        end else if (req_axburst_i == AXI_BURST_FIXED) begin
            /* FIXED uses the same address and byte lanes on every beat. */
            beat_addr = {1'b0, req_axaddr_i};
        end else if (req_axburst_i == AXI_BURST_INCR) begin
            if (req_beat_id_i == {BEAT_ID_WIDTH{1'b0}}) begin
                beat_addr = {1'b0, req_axaddr_i};
            end else begin
                beat_addr = aligned_beat_addr +
                            (req_beat_id_i * transfer_bytes);
                beat_bytes = transfer_bytes;
            end
        end else begin
            /* WRAP and the reserved encoding are never treated as INCR. */
            request_error = 1'b1;
        end

        if (beat_addr[ADDR_WIDTH]) begin
            request_error = 1'b1;
        end
        beat_end_addr = beat_addr + beat_bytes;
        if (beat_end_addr[ADDR_WIDTH] &&
            (|beat_end_addr[ADDR_WIDTH-1:0])) begin
            request_error = 1'b1;
        end
        if ((beat_addr[11:0] + beat_bytes) > 13'd4096) begin
            request_error = 1'b1;
        end
        if (req_first_beat_i !=
            (req_beat_id_i == {BEAT_ID_WIDTH{1'b0}})) begin
            request_error = 1'b1;
        end

        if (request_error) begin
            generated_line_addr[0] =
                {req_axaddr_i[ADDR_WIDTH-1:6], 6'b0};
            generated_line_byte_offset[0] = req_axaddr_i[5:0];
            generated_beat_byte_offset[0] =
                req_axaddr_i[AXI_BYTE_OFFSET_WIDTH-1:0];
            generated_error[0] = 1'b1;
        end else begin
            first_line_addr = beat_addr & ~{{(ADDR_WIDTH - 5){1'b0}}, 6'h3f};
            second_line_addr = first_line_addr + 7'd64;

            for (byte_index = 0; byte_index < AXI_BYTES;
                 byte_index = byte_index + 1) begin
                if (byte_index < beat_bytes) begin
                    absolute_byte_addr = beat_addr + byte_index;
                    lane_index = absolute_byte_addr & (AXI_BYTES - 1);
                    line_index = absolute_byte_addr[5:0];
                    if ((absolute_byte_addr >> 6) ==
                        (first_line_addr >> 6)) begin
                        descriptor_index = 0;
                    end else begin
                        descriptor_index = 1;
                    end

                    generated_line_byte_mask[descriptor_index][line_index] =
                        1'b1;
                    generated_beat_lane_mask[descriptor_index][lane_index] =
                        1'b1;
                    generated_byte_count[descriptor_index] =
                        generated_byte_count[descriptor_index] + 1'b1;
                end
            end

            generated_line_addr[0] = first_line_addr[ADDR_WIDTH-1:0];
            generated_line_byte_offset[0] = beat_addr[5:0];
            generated_beat_byte_offset[0] =
                beat_addr[AXI_BYTE_OFFSET_WIDTH-1:0];

            if (generated_byte_count[1] != 7'b0) begin
                generated_count = 2'd2;
                generated_line_addr[1] =
                    second_line_addr[ADDR_WIDTH-1:0];
                generated_line_byte_offset[1] = 6'b0;
                generated_beat_byte_offset[1] =
                    second_line_addr[AXI_BYTE_OFFSET_WIDTH-1:0];
                generated_last_fragment[0] = 1'b0;
            end
        end
    end

    always @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            valid_q <= 1'b0;
            fragment_count_q <= 2'd0;
            parent_id_q <= {PARENT_ID_WIDTH{1'b0}};
            beat_id_q <= {BEAT_ID_WIDTH{1'b0}};
            fragment_id_q <= {FRAGMENT_ID_WIDTH{1'b0}};
            fragment_write_q <= 1'b0;
            line_addr_q <= {ADDR_WIDTH{1'b0}};
            line_byte_offset_q <= 6'b0;
            beat_byte_offset_q <= {AXI_BYTE_OFFSET_WIDTH{1'b0}};
            byte_count_q <= 7'b0;
            line_byte_mask_q <= 64'b0;
            beat_lane_mask_q <= {AXI_BYTES{1'b0}};
            first_fragment_q <= 1'b0;
            last_fragment_q <= 1'b0;
            last_beat_q <= 1'b0;
            error_q <= 1'b0;
            second_parent_id_q <= {PARENT_ID_WIDTH{1'b0}};
            second_beat_id_q <= {BEAT_ID_WIDTH{1'b0}};
            second_fragment_id_q <= {FRAGMENT_ID_WIDTH{1'b0}};
            second_fragment_write_q <= 1'b0;
            second_line_addr_q <= {ADDR_WIDTH{1'b0}};
            second_line_byte_offset_q <= 6'b0;
            second_beat_byte_offset_q <= {AXI_BYTE_OFFSET_WIDTH{1'b0}};
            second_byte_count_q <= 7'b0;
            second_line_byte_mask_q <= 64'b0;
            second_beat_lane_mask_q <= {AXI_BYTES{1'b0}};
            second_first_fragment_q <= 1'b0;
            second_last_fragment_q <= 1'b0;
            second_last_beat_q <= 1'b0;
            second_error_q <= 1'b0;
        end else if (req_valid_i && req_ready_o) begin
            valid_q <= 1'b1;
            fragment_count_q <= generated_count;
            parent_id_q <= generated_parent_id[0];
            beat_id_q <= generated_beat_id[0];
            fragment_id_q <= generated_fragment_id[0];
            fragment_write_q <= generated_fragment_write[0];
            line_addr_q <= generated_line_addr[0];
            line_byte_offset_q <= generated_line_byte_offset[0];
            beat_byte_offset_q <= generated_beat_byte_offset[0];
            byte_count_q <= generated_byte_count[0];
            line_byte_mask_q <= generated_line_byte_mask[0];
            beat_lane_mask_q <= generated_beat_lane_mask[0];
            first_fragment_q <= generated_first_fragment[0];
            last_fragment_q <= generated_last_fragment[0];
            last_beat_q <= generated_last_beat[0];
            error_q <= generated_error[0];
            second_parent_id_q <= generated_parent_id[1];
            second_beat_id_q <= generated_beat_id[1];
            second_fragment_id_q <= generated_fragment_id[1];
            second_fragment_write_q <= generated_fragment_write[1];
            second_line_addr_q <= generated_line_addr[1];
            second_line_byte_offset_q <=
                generated_line_byte_offset[1];
            second_beat_byte_offset_q <=
                generated_beat_byte_offset[1];
            second_byte_count_q <= generated_byte_count[1];
            second_line_byte_mask_q <= generated_line_byte_mask[1];
            second_beat_lane_mask_q <= generated_beat_lane_mask[1];
            second_first_fragment_q <= generated_first_fragment[1];
            second_last_fragment_q <= generated_last_fragment[1];
            second_last_beat_q <= generated_last_beat[1];
            second_error_q <= generated_error[1];
        end else if (fragment_valid_o && fragment_ready_i) begin
            if (fragment_count_q == 2'd2) begin
                fragment_count_q <= 2'd1;
                parent_id_q <= second_parent_id_q;
                beat_id_q <= second_beat_id_q;
                fragment_id_q <= second_fragment_id_q;
                fragment_write_q <= second_fragment_write_q;
                line_addr_q <= second_line_addr_q;
                line_byte_offset_q <= second_line_byte_offset_q;
                beat_byte_offset_q <= second_beat_byte_offset_q;
                byte_count_q <= second_byte_count_q;
                line_byte_mask_q <= second_line_byte_mask_q;
                beat_lane_mask_q <= second_beat_lane_mask_q;
                first_fragment_q <= second_first_fragment_q;
                last_fragment_q <= second_last_fragment_q;
                last_beat_q <= second_last_beat_q;
                error_q <= second_error_q;
            end else begin
                valid_q <= 1'b0;
                fragment_count_q <= 2'd0;
            end
        end
    end

    initial begin
        if (!((AXI_DATA_WIDTH == 8) || (AXI_DATA_WIDTH == 16) ||
              (AXI_DATA_WIDTH == 32) || (AXI_DATA_WIDTH == 64) ||
              (AXI_DATA_WIDTH == 128) || (AXI_DATA_WIDTH == 256) ||
              (AXI_DATA_WIDTH == 512) || (AXI_DATA_WIDTH == 1024))) begin
            $error("rni_axi_fragment_adapter: illegal AXI_DATA_WIDTH");
        end
        if (ADDR_WIDTH < 13) begin
            $error("rni_axi_fragment_adapter: ADDR_WIDTH must be at least 13");
        end
        if (FRAGMENT_ID_WIDTH < (BEAT_ID_WIDTH + 1)) begin
            $error("rni_axi_fragment_adapter: fragment_id is too narrow");
        end
        if (AXI_BYTES != (AXI_DATA_WIDTH / 8)) begin
            $error("rni_axi_fragment_adapter: AXI_BYTES derivation mismatch");
        end
    end

endmodule
