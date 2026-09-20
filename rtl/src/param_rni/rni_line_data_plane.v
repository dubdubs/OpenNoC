/*
 * Copyright (c) 2024 Beijing Institute of Open Source Chip
 * OpenNoC is licensed under Mulan PSL v2.
 *
 * Canonical 64-byte line data plane.  A child owns one line context and a
 * descriptor maps a contiguous part of that line to an AXI beat.  beat_last
 * closes the descriptor set for one beat; parent_last is the AXI RLAST/WLAST
 * expectation for that beat.
 */

module rni_line_data_plane #(
    parameter integer ADDR_WIDTH = 44,
    parameter integer AXI_DATA_WIDTH = 128,
    parameter integer PARENT_ID_WIDTH = 4,
    parameter integer CHILD_ID_WIDTH = 4,
    parameter integer FRAGMENT_ID_WIDTH = 9,
    parameter integer FRAG_ENTRIES = 16,
    parameter integer LINE_ENTRIES = 8
) (
    input  wire clk_i,
    input  wire rst_i,

    input  wire cfg_valid_i,
    output wire cfg_ready_o,
    input  wire cfg_write_i,
    input  wire [PARENT_ID_WIDTH-1:0] cfg_parent_id_i,
    input  wire [CHILD_ID_WIDTH-1:0] cfg_child_id_i,
    input  wire [ADDR_WIDTH-1:0] cfg_line_addr_i,
    input  wire [7:0] cfg_beat_id_i,
    input  wire [FRAGMENT_ID_WIDTH-1:0] cfg_frag_id_i,
    input  wire [5:0] cfg_line_offset_i,
    input  wire [((AXI_DATA_WIDTH/8 <= 1) ? 1 :
                 $clog2(AXI_DATA_WIDTH/8))-1:0] cfg_lane_offset_i,
    input  wire [6:0] cfg_byte_count_i,
    input  wire [63:0] cfg_byte_mask_i,
    input  wire cfg_beat_last_i,
    input  wire cfg_parent_last_i,
    output wire cfg_error_o,

    input  wire child_finalize_valid_i,
    output wire child_finalize_ready_o,
    input  wire [CHILD_ID_WIDTH-1:0] child_finalize_child_id_i,
    input  wire [63:0] child_finalize_required_mask_i,
    output wire child_finalize_error_o,

    input  wire w_valid_i,
    output wire w_ready_o,
    input  wire [PARENT_ID_WIDTH-1:0] w_parent_id_i,
    input  wire [7:0] w_beat_id_i,
    input  wire [AXI_DATA_WIDTH-1:0] w_data_i,
    input  wire [AXI_DATA_WIDTH/8-1:0] w_strb_i,
    input  wire w_last_i,

    output wire w_done_valid_o,
    input  wire w_done_ready_i,
    output wire [PARENT_ID_WIDTH-1:0] w_done_parent_id_o,
    output wire [7:0] w_done_beat_id_o,
    output wire w_done_last_o,
    output wire w_done_error_o,

    output wire wr_child_ready_valid_o,
    input  wire wr_child_ready_ready_i,
    output wire [CHILD_ID_WIDTH-1:0] wr_child_ready_child_id_o,
    output wire [63:0] wr_child_ready_required_mask_o,

    input  wire rx_valid_i,
    output wire rx_ready_o,
    input  wire [CHILD_ID_WIDTH-1:0] rx_child_id_i,
    input  wire [511:0] rx_line_data_i,
    input  wire [63:0] rx_byte_mask_i,
    input  wire [1:0] rx_resperr_i,

    output wire r_valid_o,
    input  wire r_ready_i,
    output wire [PARENT_ID_WIDTH-1:0] r_parent_id_o,
    output wire [7:0] r_beat_id_o,
    output wire [AXI_DATA_WIDTH-1:0] r_data_o,
    output wire [1:0] r_resp_o,
    output wire r_last_o,

    input  wire snapshot_req_valid_i,
    output wire snapshot_req_ready_o,
    input  wire [CHILD_ID_WIDTH-1:0] snapshot_req_child_id_i,
    output wire snapshot_rsp_valid_o,
    input  wire snapshot_rsp_ready_i,
    output wire [CHILD_ID_WIDTH-1:0] snapshot_rsp_child_id_o,
    output wire [ADDR_WIDTH-1:0] snapshot_rsp_line_addr_o,
    output wire [511:0] snapshot_rsp_data_o,
    output wire [63:0] snapshot_rsp_be_o,

    input  wire child_free_valid_i,
    input  wire [CHILD_ID_WIDTH-1:0] child_free_child_id_i,
    input  wire parent_free_valid_i,
    input  wire [PARENT_ID_WIDTH-1:0] parent_free_parent_id_i,
    output wire plane_empty_o
);

    localparam integer AXI_BYTES = AXI_DATA_WIDTH / 8;
    localparam integer LANE_WIDTH = (AXI_BYTES <= 1) ? 1 : $clog2(AXI_BYTES);
    localparam integer FRAG_INDEX_WIDTH =
        (FRAG_ENTRIES <= 1) ? 1 : $clog2(FRAG_ENTRIES);
    localparam integer LINE_INDEX_WIDTH =
        (LINE_ENTRIES <= 1) ? 1 : $clog2(LINE_ENTRIES);

    reg line_valid_q [0:LINE_ENTRIES-1];
    reg line_write_q [0:LINE_ENTRIES-1];
    reg [PARENT_ID_WIDTH-1:0] line_parent_q [0:LINE_ENTRIES-1];
    reg [CHILD_ID_WIDTH-1:0] line_child_q [0:LINE_ENTRIES-1];
    reg [ADDR_WIDTH-1:0] line_addr_q [0:LINE_ENTRIES-1];
    reg [511:0] line_data_q [0:LINE_ENTRIES-1];
    reg [63:0] line_valid_mask_q [0:LINE_ENTRIES-1];
    reg [63:0] line_dirty_mask_q [0:LINE_ENTRIES-1];
    reg [63:0] line_error_mask_q [0:LINE_ENTRIES-1];
    reg [63:0] line_required_mask_q [0:LINE_ENTRIES-1];
    reg line_finalized_q [0:LINE_ENTRIES-1];

    reg frag_valid_q [0:FRAG_ENTRIES-1];
    reg frag_write_q [0:FRAG_ENTRIES-1];
    reg [PARENT_ID_WIDTH-1:0] frag_parent_q [0:FRAG_ENTRIES-1];
    reg [CHILD_ID_WIDTH-1:0] frag_child_q [0:FRAG_ENTRIES-1];
    reg [7:0] frag_beat_q [0:FRAG_ENTRIES-1];
    reg [FRAGMENT_ID_WIDTH-1:0] frag_id_q [0:FRAG_ENTRIES-1];
    reg [5:0] frag_line_offset_q [0:FRAG_ENTRIES-1];
    reg [LANE_WIDTH-1:0] frag_lane_offset_q [0:FRAG_ENTRIES-1];
    reg [6:0] frag_byte_count_q [0:FRAG_ENTRIES-1];
    reg [63:0] frag_byte_mask_q [0:FRAG_ENTRIES-1];
    reg frag_beat_last_q [0:FRAG_ENTRIES-1];
    reg frag_parent_last_q [0:FRAG_ENTRIES-1];
    reg [LINE_INDEX_WIDTH-1:0] frag_line_index_q [0:FRAG_ENTRIES-1];
    reg frag_w_received_q [0:FRAG_ENTRIES-1];
    reg frag_wr_notified_q [0:FRAG_ENTRIES-1];
    reg frag_r_issued_q [0:FRAG_ENTRIES-1];

    reg w_done_valid_q;
    reg [PARENT_ID_WIDTH-1:0] w_done_parent_q;
    reg [7:0] w_done_beat_q;
    reg w_done_last_q;
    reg w_done_error_q;

    reg wr_child_valid_q;
    reg [CHILD_ID_WIDTH-1:0] wr_child_id_q;
    reg [63:0] wr_child_required_q;

    reg r_valid_q;
    reg [PARENT_ID_WIDTH-1:0] r_parent_q;
    reg [7:0] r_beat_q;
    reg [AXI_DATA_WIDTH-1:0] r_data_q;
    reg [1:0] r_resp_q;
    reg r_last_q;

    reg snapshot_valid_q;
    reg [CHILD_ID_WIDTH-1:0] snapshot_child_q;
    reg [ADDR_WIDTH-1:0] snapshot_line_addr_q;
    reg [511:0] snapshot_data_q;
    reg [63:0] snapshot_be_q;

    integer cfg_free_frag;
    integer cfg_free_line;
    integer cfg_match_line;
    integer cfg_match_count;
    integer rx_match_line;
    integer rx_match_count;
    integer finalize_match_line;
    integer finalize_match_count;
    integer wr_candidate_frag;
    integer r_candidate_last_frag;
    integer cfg_i;
    integer finalize_i;
    integer w_i;
    integer w_j;
    integer w_lane_index;
    integer w_line_index;
    integer wr_i;
    integer wr_j;
    integer rx_i;
    integer r_i;
    integer r_j;
    integer r_lane_index;
    integer r_line_index;
    integer state_i;
    integer seq_i;
    integer seq_j;
    integer seq_lane_index;
    integer seq_line_index;

    reg cfg_resource_available;
    reg cfg_alias_error;
    reg w_descriptor_set_valid;
    reg w_expected_last;
    reg w_protocol_error;
    reg [AXI_BYTES-1:0] w_lane_envelope;
    reg wr_candidate_valid;
    reg wr_candidate_complete;
    reg r_candidate_valid;
    reg [PARENT_ID_WIDTH-1:0] r_candidate_parent;
    reg [7:0] r_candidate_beat;
    reg [AXI_DATA_WIDTH-1:0] r_candidate_data;
    reg [1:0] r_candidate_resp;
    reg r_candidate_last;
    reg r_candidate_complete;
    reg plane_has_state;

    initial begin
        if (AXI_DATA_WIDTH < 8 || AXI_DATA_WIDTH > 1024 ||
            (AXI_DATA_WIDTH % 8) != 0 ||
            (AXI_DATA_WIDTH & (AXI_DATA_WIDTH - 1)) != 0)
            $fatal(1, "rni_line_data_plane: illegal AXI_DATA_WIDTH");
        if (FRAG_ENTRIES < 1 || LINE_ENTRIES < 1)
            $fatal(1, "rni_line_data_plane: table depths must be positive");
    end

    /* Allocation lookup.  An existing child line may accept another
     * descriptor; otherwise descriptor and line allocation are atomic. */
    always @* begin
        cfg_free_frag = -1;
        cfg_free_line = -1;
        cfg_match_line = -1;
        cfg_match_count = 0;
        cfg_alias_error = 1'b0;
        for (cfg_i = 0; cfg_i < FRAG_ENTRIES; cfg_i = cfg_i + 1) begin
            if (!frag_valid_q[cfg_i] && cfg_free_frag < 0)
                cfg_free_frag = cfg_i;
        end
        for (cfg_i = 0; cfg_i < LINE_ENTRIES; cfg_i = cfg_i + 1) begin
            if (!line_valid_q[cfg_i] && cfg_free_line < 0)
                cfg_free_line = cfg_i;
            if (line_valid_q[cfg_i] &&
                line_child_q[cfg_i] == cfg_child_id_i) begin
                if (line_parent_q[cfg_i] == cfg_parent_id_i &&
                    line_addr_q[cfg_i] == cfg_line_addr_i &&
                    line_write_q[cfg_i] == cfg_write_i) begin
                    cfg_match_line = cfg_i;
                    cfg_match_count = cfg_match_count + 1;
                end else begin
                    cfg_alias_error = 1'b1;
                end
            end
        end
        cfg_resource_available = (cfg_free_frag >= 0) &&
            ((cfg_match_count == 1) ||
             ((cfg_match_count == 0) && (cfg_free_line >= 0)));
    end

    assign cfg_ready_o = cfg_resource_available && !cfg_alias_error;
    assign cfg_error_o = cfg_valid_i && cfg_alias_error;

    always @* begin
        finalize_match_line = 0;
        finalize_match_count = 0;
        for (finalize_i = 0; finalize_i < LINE_ENTRIES;
             finalize_i = finalize_i + 1) begin
            if (line_valid_q[finalize_i] && line_write_q[finalize_i] &&
                line_child_q[finalize_i] == child_finalize_child_id_i) begin
                finalize_match_line = finalize_i;
                finalize_match_count = finalize_match_count + 1;
            end
        end
    end

    assign child_finalize_ready_o = (finalize_match_count == 1) &&
        !line_finalized_q[finalize_match_line];
    assign child_finalize_error_o = child_finalize_valid_i &&
        (finalize_match_count != 1 ||
         line_finalized_q[finalize_match_line]);

    /* W is accepted only after the closing descriptor is present.  All
     * fragments of the beat are updated in the same clock edge. */
    always @* begin
        w_descriptor_set_valid = 1'b0;
        w_expected_last = 1'b0;
        w_protocol_error = 1'b0;
        w_lane_envelope = {AXI_BYTES{1'b0}};
        for (w_i = 0; w_i < FRAG_ENTRIES; w_i = w_i + 1) begin
            if (frag_valid_q[w_i] && frag_write_q[w_i] &&
                frag_parent_q[w_i] == w_parent_id_i &&
                frag_beat_q[w_i] == w_beat_id_i) begin
                if (frag_w_received_q[w_i])
                    w_protocol_error = 1'b1;
                if (frag_beat_last_q[w_i]) begin
                    w_descriptor_set_valid = 1'b1;
                    w_expected_last = frag_parent_last_q[w_i];
                end
                for (w_j = 0; w_j < 64; w_j = w_j + 1) begin
                    w_lane_index = frag_lane_offset_q[w_i] + w_j;
                    w_line_index = frag_line_offset_q[w_i] + w_j;
                    if (w_j < frag_byte_count_q[w_i] &&
                        w_lane_index < AXI_BYTES && w_line_index < 64 &&
                        frag_byte_mask_q[w_i][w_line_index])
                        w_lane_envelope[w_lane_index] = 1'b1;
                end
            end
        end
        if ((w_strb_i & ~w_lane_envelope) != {AXI_BYTES{1'b0}})
            w_protocol_error = 1'b1;
        if (w_last_i != w_expected_last)
            w_protocol_error = 1'b1;
    end

    assign w_ready_o = w_descriptor_set_valid &&
        (!w_done_valid_q || w_done_ready_i);

    /* A completed write child is reported once. */
    always @* begin
        wr_candidate_valid = 1'b0;
        wr_candidate_frag = 0;
        wr_candidate_complete = 1'b0;
        for (wr_i = 0; wr_i < FRAG_ENTRIES; wr_i = wr_i + 1) begin
            if (!wr_candidate_valid && frag_valid_q[wr_i] &&
                frag_write_q[wr_i] && frag_w_received_q[wr_i] &&
                !frag_wr_notified_q[wr_i] &&
                line_finalized_q[frag_line_index_q[wr_i]]) begin
                wr_candidate_complete = 1'b1;
                for (wr_j = 0; wr_j < FRAG_ENTRIES;
                     wr_j = wr_j + 1) begin
                    if (frag_valid_q[wr_j] && frag_write_q[wr_j] &&
                        frag_child_q[wr_j] == frag_child_q[wr_i] &&
                        !frag_w_received_q[wr_j])
                        wr_candidate_complete = 1'b0;
                end
                if (wr_candidate_complete) begin
                    wr_candidate_valid = 1'b1;
                    wr_candidate_frag = wr_i;
                end
            end
        end
    end

    /* RX ownership must resolve to exactly one active line. */
    always @* begin
        rx_match_line = 0;
        rx_match_count = 0;
        for (rx_i = 0; rx_i < LINE_ENTRIES; rx_i = rx_i + 1) begin
            if (line_valid_q[rx_i] && !line_write_q[rx_i] &&
                line_child_q[rx_i] == rx_child_id_i) begin
                rx_match_line = rx_i;
                rx_match_count = rx_match_count + 1;
            end
        end
    end

    assign rx_ready_o = (rx_match_count == 1);

    /* Select one complete read beat.  The registered output decouples all
     * line storage updates from AXI backpressure. */
    always @* begin
        r_candidate_valid = 1'b0;
        r_candidate_last_frag = 0;
        r_candidate_parent = {PARENT_ID_WIDTH{1'b0}};
        r_candidate_beat = 8'h00;
        r_candidate_data = {AXI_DATA_WIDTH{1'b0}};
        r_candidate_resp = 2'b00;
        r_candidate_last = 1'b0;
        for (r_i = 0; r_i < FRAG_ENTRIES; r_i = r_i + 1) begin
            if (!r_candidate_valid && frag_valid_q[r_i] &&
                !frag_write_q[r_i] && frag_beat_last_q[r_i] &&
                !frag_r_issued_q[r_i]) begin
                r_candidate_complete = 1'b1;
                for (r_j = 0; r_j < FRAG_ENTRIES; r_j = r_j + 1) begin
                    if (frag_valid_q[r_j] && !frag_write_q[r_j] &&
                        frag_parent_q[r_j] == frag_parent_q[r_i] &&
                        frag_beat_q[r_j] == frag_beat_q[r_i]) begin
                        if (frag_r_issued_q[r_j] ||
                            ((line_valid_mask_q[frag_line_index_q[r_j]] &
                              frag_byte_mask_q[r_j]) !=
                             frag_byte_mask_q[r_j]))
                            r_candidate_complete = 1'b0;
                    end
                    if (frag_valid_q[r_j] && !frag_write_q[r_j] &&
                        frag_parent_q[r_j] == frag_parent_q[r_i] &&
                        !frag_r_issued_q[r_j] &&
                        frag_beat_q[r_j] < frag_beat_q[r_i])
                        r_candidate_complete = 1'b0;
                end
                if (r_candidate_complete) begin
                    r_candidate_valid = 1'b1;
                    r_candidate_last_frag = r_i;
                    r_candidate_parent = frag_parent_q[r_i];
                    r_candidate_beat = frag_beat_q[r_i];
                    r_candidate_last = frag_parent_last_q[r_i];
                end
            end
        end

        if (r_candidate_valid) begin
            for (r_i = 0; r_i < FRAG_ENTRIES; r_i = r_i + 1) begin
                if (frag_valid_q[r_i] && !frag_write_q[r_i] &&
                    frag_parent_q[r_i] == r_candidate_parent &&
                    frag_beat_q[r_i] == r_candidate_beat) begin
                    for (r_j = 0; r_j < 64; r_j = r_j + 1) begin
                        r_lane_index = frag_lane_offset_q[r_i] + r_j;
                        r_line_index = frag_line_offset_q[r_i] + r_j;
                        if (r_j < frag_byte_count_q[r_i] &&
                            r_lane_index < AXI_BYTES && r_line_index < 64 &&
                            frag_byte_mask_q[r_i][r_line_index]) begin
                            r_candidate_data[r_lane_index*8 +: 8] =
                                line_data_q[frag_line_index_q[r_i]][
                                    r_line_index*8 +: 8];
                            if (line_error_mask_q[
                                frag_line_index_q[r_i]][r_line_index])
                                r_candidate_resp = 2'b10;
                        end
                    end
                end
            end
        end
    end

    assign w_done_valid_o = w_done_valid_q;
    assign w_done_parent_id_o = w_done_parent_q;
    assign w_done_beat_id_o = w_done_beat_q;
    assign w_done_last_o = w_done_last_q;
    assign w_done_error_o = w_done_error_q;

    assign wr_child_ready_valid_o = wr_child_valid_q;
    assign wr_child_ready_child_id_o = wr_child_id_q;
    assign wr_child_ready_required_mask_o = wr_child_required_q;

    assign r_valid_o = r_valid_q;
    assign r_parent_id_o = r_parent_q;
    assign r_beat_id_o = r_beat_q;
    assign r_data_o = r_data_q;
    assign r_resp_o = r_resp_q;
    assign r_last_o = r_last_q;

    assign snapshot_req_ready_o = !snapshot_valid_q || snapshot_rsp_ready_i;
    assign snapshot_rsp_valid_o = snapshot_valid_q;
    assign snapshot_rsp_child_id_o = snapshot_child_q;
    assign snapshot_rsp_line_addr_o = snapshot_line_addr_q;
    assign snapshot_rsp_data_o = snapshot_data_q;
    assign snapshot_rsp_be_o = snapshot_be_q;

    always @* begin
        plane_has_state = w_done_valid_q || wr_child_valid_q || r_valid_q ||
            snapshot_valid_q;
        for (state_i = 0; state_i < FRAG_ENTRIES;
             state_i = state_i + 1)
            plane_has_state = plane_has_state || frag_valid_q[state_i];
        for (state_i = 0; state_i < LINE_ENTRIES;
             state_i = state_i + 1)
            plane_has_state = plane_has_state || line_valid_q[state_i];
    end
    assign plane_empty_o = !plane_has_state;

    always @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            w_done_valid_q <= 1'b0;
            w_done_parent_q <= {PARENT_ID_WIDTH{1'b0}};
            w_done_beat_q <= 8'h00;
            w_done_last_q <= 1'b0;
            w_done_error_q <= 1'b0;
            wr_child_valid_q <= 1'b0;
            wr_child_id_q <= {CHILD_ID_WIDTH{1'b0}};
            wr_child_required_q <= 64'h0;
            r_valid_q <= 1'b0;
            r_parent_q <= {PARENT_ID_WIDTH{1'b0}};
            r_beat_q <= 8'h00;
            r_data_q <= {AXI_DATA_WIDTH{1'b0}};
            r_resp_q <= 2'b00;
            r_last_q <= 1'b0;
            snapshot_valid_q <= 1'b0;
            snapshot_child_q <= {CHILD_ID_WIDTH{1'b0}};
            snapshot_line_addr_q <= {ADDR_WIDTH{1'b0}};
            snapshot_data_q <= 512'h0;
            snapshot_be_q <= 64'h0;
            for (seq_i = 0; seq_i < LINE_ENTRIES; seq_i = seq_i + 1) begin
                line_valid_q[seq_i] <= 1'b0;
                line_write_q[seq_i] <= 1'b0;
                line_parent_q[seq_i] <= {PARENT_ID_WIDTH{1'b0}};
                line_child_q[seq_i] <= {CHILD_ID_WIDTH{1'b0}};
                line_addr_q[seq_i] <= {ADDR_WIDTH{1'b0}};
                line_data_q[seq_i] <= 512'h0;
                line_valid_mask_q[seq_i] <= 64'h0;
                line_dirty_mask_q[seq_i] <= 64'h0;
                line_error_mask_q[seq_i] <= 64'h0;
                line_required_mask_q[seq_i] <= 64'h0;
                line_finalized_q[seq_i] <= 1'b0;
            end
            for (seq_i = 0; seq_i < FRAG_ENTRIES; seq_i = seq_i + 1) begin
                frag_valid_q[seq_i] <= 1'b0;
                frag_write_q[seq_i] <= 1'b0;
                frag_parent_q[seq_i] <= {PARENT_ID_WIDTH{1'b0}};
                frag_child_q[seq_i] <= {CHILD_ID_WIDTH{1'b0}};
                frag_beat_q[seq_i] <= 8'h00;
                frag_id_q[seq_i] <= {FRAGMENT_ID_WIDTH{1'b0}};
                frag_line_offset_q[seq_i] <= 6'h00;
                frag_lane_offset_q[seq_i] <= {LANE_WIDTH{1'b0}};
                frag_byte_count_q[seq_i] <= 7'h00;
                frag_byte_mask_q[seq_i] <= 64'h0;
                frag_beat_last_q[seq_i] <= 1'b0;
                frag_parent_last_q[seq_i] <= 1'b0;
                frag_line_index_q[seq_i] <= {LINE_INDEX_WIDTH{1'b0}};
                frag_w_received_q[seq_i] <= 1'b0;
                frag_wr_notified_q[seq_i] <= 1'b0;
                frag_r_issued_q[seq_i] <= 1'b0;
            end
        end else begin
            if (w_done_valid_q && w_done_ready_i)
                w_done_valid_q <= 1'b0;
            if (wr_child_valid_q && wr_child_ready_ready_i)
                wr_child_valid_q <= 1'b0;
            if (r_valid_q && r_ready_i)
                r_valid_q <= 1'b0;
            if (snapshot_valid_q && snapshot_rsp_ready_i)
                snapshot_valid_q <= 1'b0;

            if (cfg_valid_i && cfg_ready_o) begin
                frag_valid_q[cfg_free_frag] <= 1'b1;
                frag_write_q[cfg_free_frag] <= cfg_write_i;
                frag_parent_q[cfg_free_frag] <= cfg_parent_id_i;
                frag_child_q[cfg_free_frag] <= cfg_child_id_i;
                frag_beat_q[cfg_free_frag] <= cfg_beat_id_i;
                frag_id_q[cfg_free_frag] <= cfg_frag_id_i;
                frag_line_offset_q[cfg_free_frag] <= cfg_line_offset_i;
                frag_lane_offset_q[cfg_free_frag] <= cfg_lane_offset_i;
                frag_byte_count_q[cfg_free_frag] <= cfg_byte_count_i;
                frag_byte_mask_q[cfg_free_frag] <= cfg_byte_mask_i;
                frag_beat_last_q[cfg_free_frag] <= cfg_beat_last_i;
                frag_parent_last_q[cfg_free_frag] <= cfg_parent_last_i;
                frag_w_received_q[cfg_free_frag] <= 1'b0;
                frag_wr_notified_q[cfg_free_frag] <= 1'b0;
                frag_r_issued_q[cfg_free_frag] <= 1'b0;
                if (cfg_match_count == 1) begin
                    frag_line_index_q[cfg_free_frag] <= cfg_match_line;
                    if (!cfg_write_i)
                        line_required_mask_q[cfg_match_line] <=
                            line_required_mask_q[cfg_match_line] |
                            cfg_byte_mask_i;
                end else begin
                    frag_line_index_q[cfg_free_frag] <= cfg_free_line;
                    line_valid_q[cfg_free_line] <= 1'b1;
                    line_write_q[cfg_free_line] <= cfg_write_i;
                    line_parent_q[cfg_free_line] <= cfg_parent_id_i;
                    line_child_q[cfg_free_line] <= cfg_child_id_i;
                    line_addr_q[cfg_free_line] <= cfg_line_addr_i;
                    line_data_q[cfg_free_line] <= 512'h0;
                    line_valid_mask_q[cfg_free_line] <= 64'h0;
                    line_dirty_mask_q[cfg_free_line] <= 64'h0;
                    line_error_mask_q[cfg_free_line] <= 64'h0;
                    line_required_mask_q[cfg_free_line] <=
                        cfg_write_i ? 64'h0 : cfg_byte_mask_i;
                    line_finalized_q[cfg_free_line] <= 1'b0;
                end
            end

            if (child_finalize_valid_i && child_finalize_ready_o) begin
                line_finalized_q[finalize_match_line] <= 1'b1;
                line_required_mask_q[finalize_match_line] <=
                    child_finalize_required_mask_i;
            end

            if (w_valid_i && w_ready_o) begin
                w_done_valid_q <= 1'b1;
                w_done_parent_q <= w_parent_id_i;
                w_done_beat_q <= w_beat_id_i;
                w_done_last_q <= w_expected_last;
                w_done_error_q <= w_protocol_error;
                for (seq_i = 0; seq_i < FRAG_ENTRIES;
                     seq_i = seq_i + 1) begin
                    if (frag_valid_q[seq_i] && frag_write_q[seq_i] &&
                        frag_parent_q[seq_i] == w_parent_id_i &&
                        frag_beat_q[seq_i] == w_beat_id_i) begin
                        frag_w_received_q[seq_i] <= 1'b1;
                        for (seq_j = 0; seq_j < 64; seq_j = seq_j + 1) begin
                            seq_lane_index =
                                frag_lane_offset_q[seq_i] + seq_j;
                            seq_line_index =
                                frag_line_offset_q[seq_i] + seq_j;
                            if (seq_j < frag_byte_count_q[seq_i] &&
                                seq_lane_index < AXI_BYTES &&
                                seq_line_index < 64 &&
                                frag_byte_mask_q[seq_i][seq_line_index] &&
                                w_strb_i[seq_lane_index]) begin
                                if (!w_protocol_error) begin
                                    line_data_q[frag_line_index_q[seq_i]][
                                        seq_line_index*8 +: 8] <=
                                        w_data_i[seq_lane_index*8 +: 8];
                                    line_valid_mask_q[
                                        frag_line_index_q[seq_i]][
                                        seq_line_index] <= 1'b1;
                                    line_dirty_mask_q[
                                        frag_line_index_q[seq_i]][
                                        seq_line_index] <= 1'b1;
                                    line_required_mask_q[
                                        frag_line_index_q[seq_i]][
                                        seq_line_index] <= 1'b1;
                                end
                            end
                        end
                    end
                end
            end

            if ((!wr_child_valid_q || wr_child_ready_ready_i) &&
                wr_candidate_valid) begin
                wr_child_valid_q <= 1'b1;
                wr_child_id_q <= frag_child_q[wr_candidate_frag];
                wr_child_required_q <=
                    line_required_mask_q[frag_line_index_q[wr_candidate_frag]];
                for (seq_i = 0; seq_i < FRAG_ENTRIES;
                     seq_i = seq_i + 1) begin
                    if (frag_valid_q[seq_i] && frag_write_q[seq_i] &&
                        frag_child_q[seq_i] ==
                        frag_child_q[wr_candidate_frag])
                        frag_wr_notified_q[seq_i] <= 1'b1;
                end
            end

            if (rx_valid_i && rx_ready_o) begin
                for (seq_i = 0; seq_i < 64; seq_i = seq_i + 1) begin
                    if (rx_byte_mask_i[seq_i]) begin
                        if (line_valid_mask_q[rx_match_line][seq_i])
                            line_error_mask_q[rx_match_line][seq_i] <= 1'b1;
                        else begin
                            line_data_q[rx_match_line][seq_i*8 +: 8] <=
                                rx_line_data_i[seq_i*8 +: 8];
                            line_valid_mask_q[rx_match_line][seq_i] <= 1'b1;
                            if (rx_resperr_i != 2'b00)
                                line_error_mask_q[rx_match_line][seq_i] <= 1'b1;
                        end
                    end
                end
            end

            if ((!r_valid_q || r_ready_i) && r_candidate_valid) begin
                r_valid_q <= 1'b1;
                r_parent_q <= r_candidate_parent;
                r_beat_q <= r_candidate_beat;
                r_data_q <= r_candidate_data;
                r_resp_q <= r_candidate_resp;
                r_last_q <= r_candidate_last;
                for (seq_i = 0; seq_i < FRAG_ENTRIES;
                     seq_i = seq_i + 1) begin
                    if (frag_valid_q[seq_i] && !frag_write_q[seq_i] &&
                        frag_parent_q[seq_i] == r_candidate_parent &&
                        frag_beat_q[seq_i] == r_candidate_beat)
                        frag_r_issued_q[seq_i] <= 1'b1;
                end
            end

            if (snapshot_req_valid_i && snapshot_req_ready_o) begin
                snapshot_valid_q <= 1'b1;
                snapshot_child_q <= snapshot_req_child_id_i;
                snapshot_line_addr_q <= {ADDR_WIDTH{1'b0}};
                snapshot_data_q <= 512'h0;
                snapshot_be_q <= 64'h0;
                for (seq_i = 0; seq_i < LINE_ENTRIES;
                     seq_i = seq_i + 1) begin
                    if (line_valid_q[seq_i] &&
                        line_child_q[seq_i] == snapshot_req_child_id_i) begin
                        snapshot_data_q <= line_data_q[seq_i];
                        snapshot_line_addr_q <= line_addr_q[seq_i];
                        snapshot_be_q <= line_write_q[seq_i] ?
                            line_dirty_mask_q[seq_i] :
                            line_valid_mask_q[seq_i];
                    end
                end
            end

            if (child_free_valid_i) begin
                for (seq_i = 0; seq_i < FRAG_ENTRIES;
                     seq_i = seq_i + 1) begin
                    if (frag_valid_q[seq_i] &&
                        frag_child_q[seq_i] == child_free_child_id_i)
                        frag_valid_q[seq_i] <= 1'b0;
                end
                for (seq_i = 0; seq_i < LINE_ENTRIES;
                     seq_i = seq_i + 1) begin
                    if (line_valid_q[seq_i] &&
                        line_child_q[seq_i] == child_free_child_id_i)
                        line_valid_q[seq_i] <= 1'b0;
                end
            end

            if (parent_free_valid_i) begin
                for (seq_i = 0; seq_i < FRAG_ENTRIES;
                     seq_i = seq_i + 1) begin
                    if (frag_valid_q[seq_i] &&
                        frag_parent_q[seq_i] == parent_free_parent_id_i)
                        frag_valid_q[seq_i] <= 1'b0;
                end
                for (seq_i = 0; seq_i < LINE_ENTRIES;
                     seq_i = seq_i + 1) begin
                    if (line_valid_q[seq_i] &&
                        line_parent_q[seq_i] == parent_free_parent_id_i)
                        line_valid_q[seq_i] <= 1'b0;
                end
            end
        end
    end

endmodule
