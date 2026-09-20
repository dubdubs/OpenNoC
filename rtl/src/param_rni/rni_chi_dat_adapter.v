/*
 * Copyright (c) 2024 Beijing Institute of Open Source Chip
 * OpenNoC is licensed under Mulan PSL v2.
 *
 * Parameterized CHI DAT adapter for the Scheme-1 canonical 64-byte line.
 * This module owns DataID-to-ordinal validation and byte-granular DAT
 * pack/unpack.  Protocol controllers continue to own request/completion
 * state and the link controller remains the raw credit owner.
 */

module rni_chi_dat_adapter #(
    parameter integer CHI_DATA_WIDTH = 256,
    parameter integer CHI_BE_WIDTH = CHI_DATA_WIDTH / 8,
    parameter integer TXNID_WIDTH = 12,
    parameter integer CHILD_ID_WIDTH = 6,
    parameter integer CTX_ENTRIES = 32
) (
    input  wire                         clk_i,
    input  wire                         rst_i,

    input  wire                         rd_ctx_alloc_valid_i,
    output wire                         rd_ctx_alloc_ready_o,
    input  wire [CHILD_ID_WIDTH-1:0]    rd_ctx_alloc_child_id_i,
    input  wire [TXNID_WIDTH-1:0]       rd_ctx_alloc_txnid_i,
    input  wire [63:0]                  rd_ctx_alloc_required_mask_i,
    input  wire                         rd_ctx_free_valid_i,
    input  wire [CHILD_ID_WIDTH-1:0]    rd_ctx_free_child_id_i,

    input  wire                         rxdat_valid_i,
    output wire                         rxdat_ready_o,
    input  wire [TXNID_WIDTH-1:0]       rxdat_txnid_i,
    input  wire [1:0]                   rxdat_dataid_i,
    input  wire [CHI_DATA_WIDTH-1:0]    rxdat_data_i,
    input  wire [CHI_BE_WIDTH-1:0]      rxdat_be_i,
    input  wire [1:0]                   rxdat_resperr_i,

    output wire                         rx_line_valid_o,
    input  wire                         rx_line_ready_i,
    output wire [CHILD_ID_WIDTH-1:0]    rx_line_child_id_o,
    output wire [511:0]                 rx_line_data_o,
    output wire [63:0]                  rx_line_byte_mask_o,
    output wire [1:0]                   rx_line_resperr_o,

    output wire                         rx_done_valid_o,
    input  wire                         rx_done_ready_i,
    output wire [CHILD_ID_WIDTH-1:0]    rx_done_child_id_o,

    output wire                         rx_error_valid_o,
    input  wire                         rx_error_ready_i,
    output wire [TXNID_WIDTH-1:0]       rx_error_txnid_o,
    output wire [CHILD_ID_WIDTH-1:0]    rx_error_child_id_o,
    output wire [3:0]                   rx_error_code_o,

    input  wire                         tx_cmd_valid_i,
    output wire                         tx_cmd_ready_o,
    input  wire [CHILD_ID_WIDTH-1:0]    tx_cmd_child_id_i,
    input  wire [511:0]                 tx_cmd_line_data_i,
    input  wire [63:0]                  tx_cmd_required_mask_i,

    output wire                         txdat_valid_o,
    input  wire                         txdat_sent_i,
    output wire [CHILD_ID_WIDTH-1:0]    txdat_child_id_o,
    output wire [1:0]                   txdat_dataid_o,
    output wire [CHI_DATA_WIDTH-1:0]    txdat_data_o,
    output wire [CHI_BE_WIDTH-1:0]      txdat_be_o,
    output wire                         txdat_last_o,

    output wire                         tx_done_valid_o,
    input  wire                         tx_done_ready_i,
    output wire [CHILD_ID_WIDTH-1:0]    tx_done_child_id_o,
    output wire                         adapter_empty_o
);

    localparam integer CHI_BYTES = CHI_DATA_WIDTH / 8;
    localparam integer DATS_PER_LINE = 64 / CHI_BYTES;
    localparam integer CTX_INDEX_WIDTH =
        (CTX_ENTRIES <= 1) ? 1 : $clog2(CTX_ENTRIES);

    localparam [3:0] RX_ERROR_UNMATCHED_TXNID = 4'h1;
    localparam [3:0] RX_ERROR_ILLEGAL_DATAID = 4'h2;
    localparam [3:0] RX_ERROR_UNEXPECTED_DATAID = 4'h3;
    localparam [3:0] RX_ERROR_DUPLICATE_DATAID = 4'h4;
    localparam [3:0] RX_ERROR_MISSING_BE = 4'h5;

    reg ctx_valid_q [0:CTX_ENTRIES-1];
    reg [CHILD_ID_WIDTH-1:0] ctx_child_q [0:CTX_ENTRIES-1];
    reg [TXNID_WIDTH-1:0] ctx_txnid_q [0:CTX_ENTRIES-1];
    reg [3:0] ctx_expected_dat_q [0:CTX_ENTRIES-1];
    reg [3:0] ctx_received_dat_q [0:CTX_ENTRIES-1];
    reg [63:0] ctx_required_byte_q [0:CTX_ENTRIES-1];

    integer alloc_free_index;
    integer alloc_match_count;
    integer rx_match_index;
    integer rx_match_count;
    integer alloc_i;
    integer alloc_byte_index;
    integer rx_i;
    integer rx_byte_index;
    integer rx_line_byte_index;
    integer tx_i;
    integer tx_byte_index;
    integer tx_line_byte_index;
    integer ctx_i;
    integer seq_i;

    reg [3:0] alloc_expected_dat;
    reg [3:0] rx_ordinal_onehot;
    reg [1:0] rx_ordinal;
    reg rx_dataid_legal;
    reg rx_duplicate;
    reg rx_expected;
    reg rx_missing_be;
    reg [63:0] rx_required_chunk;
    reg [63:0] rx_positioned_be;
    reg [511:0] rx_positioned_data;
    reg [3:0] rx_received_next;
    reg rx_protocol_error;
    reg [3:0] rx_protocol_error_code;

    reg rx_line_valid_q;
    reg [CHILD_ID_WIDTH-1:0] rx_line_child_q;
    reg [511:0] rx_line_data_q;
    reg [63:0] rx_line_mask_q;
    reg [1:0] rx_line_resperr_q;
    reg rx_done_valid_q;
    reg [CHILD_ID_WIDTH-1:0] rx_done_child_q;
    reg rx_error_valid_q;
    reg [TXNID_WIDTH-1:0] rx_error_txnid_q;
    reg [CHILD_ID_WIDTH-1:0] rx_error_child_q;
    reg [3:0] rx_error_code_q;

    reg tx_busy_q;
    reg [CHILD_ID_WIDTH-1:0] tx_child_q;
    reg [511:0] tx_line_data_q;
    reg [63:0] tx_required_mask_q;
    reg [3:0] tx_pending_dat_q;
    reg tx_done_valid_q;
    reg [CHILD_ID_WIDTH-1:0] tx_done_child_q;

    reg [3:0] tx_command_dat_mask;
    reg [1:0] tx_selected_ordinal;
    reg [3:0] tx_selected_onehot;
    reg [CHI_DATA_WIDTH-1:0] tx_selected_data;
    reg [CHI_BE_WIDTH-1:0] tx_selected_be;
    reg [1:0] tx_selected_dataid;
    reg ctx_any_valid;

    initial begin
        if (!((CHI_DATA_WIDTH == 128) || (CHI_DATA_WIDTH == 256) ||
              (CHI_DATA_WIDTH == 512)))
            $fatal(1, "rni_chi_dat_adapter: illegal CHI_DATA_WIDTH");
        if (CHI_BE_WIDTH != CHI_BYTES)
            $fatal(1, "rni_chi_dat_adapter: CHI BE width mismatch");
        if (CTX_ENTRIES < 1)
            $fatal(1, "rni_chi_dat_adapter: CTX_ENTRIES must be positive");
    end

    always @* begin
        alloc_free_index = -1;
        alloc_match_count = 0;
        alloc_expected_dat = 4'b0000;
        for (alloc_i = 0; alloc_i < CTX_ENTRIES;
             alloc_i = alloc_i + 1) begin
            if (!ctx_valid_q[alloc_i] && alloc_free_index < 0)
                alloc_free_index = alloc_i;
            if (ctx_valid_q[alloc_i] &&
                ctx_txnid_q[alloc_i] == rd_ctx_alloc_txnid_i)
                alloc_match_count = alloc_match_count + 1;
        end
        for (alloc_i = 0; alloc_i < DATS_PER_LINE;
             alloc_i = alloc_i + 1) begin
            for (alloc_byte_index = 0; alloc_byte_index < CHI_BYTES;
                 alloc_byte_index = alloc_byte_index + 1) begin
                if (rd_ctx_alloc_required_mask_i[
                    (alloc_i * CHI_BYTES) + alloc_byte_index])
                    alloc_expected_dat[alloc_i] = 1'b1;
            end
        end
    end

    assign rd_ctx_alloc_ready_o =
        (alloc_free_index >= 0) && (alloc_match_count == 0);

    always @* begin
        rx_match_index = 0;
        rx_match_count = 0;
        for (rx_i = 0; rx_i < CTX_ENTRIES; rx_i = rx_i + 1) begin
            if (ctx_valid_q[rx_i] &&
                ctx_txnid_q[rx_i] == rxdat_txnid_i) begin
                rx_match_index = rx_i;
                rx_match_count = rx_match_count + 1;
            end
        end

        rx_dataid_legal = 1'b0;
        rx_ordinal = 2'b00;
        if (CHI_DATA_WIDTH == 128) begin
            rx_dataid_legal = 1'b1;
            rx_ordinal = rxdat_dataid_i;
        end else if (CHI_DATA_WIDTH == 256) begin
            rx_dataid_legal = (rxdat_dataid_i[0] == 1'b0);
            rx_ordinal = {1'b0, rxdat_dataid_i[1]};
        end else begin
            rx_dataid_legal = (rxdat_dataid_i == 2'b00);
            rx_ordinal = 2'b00;
        end

        rx_ordinal_onehot = 4'b0001 << rx_ordinal;
        rx_duplicate = 1'b0;
        rx_expected = 1'b0;
        rx_missing_be = 1'b0;
        rx_required_chunk = 64'b0;
        rx_positioned_be = 64'b0;
        rx_positioned_data = 512'b0;
        rx_received_next = 4'b0;
        if (rx_match_count == 1 && rx_dataid_legal) begin
            rx_duplicate =
                |(ctx_received_dat_q[rx_match_index] & rx_ordinal_onehot);
            rx_expected =
                |(ctx_expected_dat_q[rx_match_index] & rx_ordinal_onehot);
            rx_required_chunk = ctx_required_byte_q[rx_match_index] &
                ({{(64-CHI_BE_WIDTH){1'b0}}, {CHI_BE_WIDTH{1'b1}}}
                 << (rx_ordinal * CHI_BYTES));
            for (rx_byte_index = 0; rx_byte_index < CHI_BE_WIDTH;
                 rx_byte_index = rx_byte_index + 1) begin
                rx_line_byte_index =
                    (rx_ordinal * CHI_BYTES) + rx_byte_index;
                if (rx_line_byte_index < 64) begin
                    rx_positioned_be[rx_line_byte_index] =
                        rxdat_be_i[rx_byte_index];
                    if (rxdat_be_i[rx_byte_index])
                        rx_positioned_data[
                            rx_line_byte_index*8 +: 8] =
                            rxdat_data_i[rx_byte_index*8 +: 8];
                end
            end
            rx_missing_be =
                ((rx_positioned_be & rx_required_chunk) != rx_required_chunk);
            rx_received_next = ctx_received_dat_q[rx_match_index] |
                rx_ordinal_onehot;
        end

        rx_protocol_error = 1'b0;
        rx_protocol_error_code = 4'b0;
        if (rx_match_count != 1) begin
            rx_protocol_error = 1'b1;
            rx_protocol_error_code = RX_ERROR_UNMATCHED_TXNID;
        end else if (!rx_dataid_legal) begin
            rx_protocol_error = 1'b1;
            rx_protocol_error_code = RX_ERROR_ILLEGAL_DATAID;
        end else if (!rx_expected) begin
            rx_protocol_error = 1'b1;
            rx_protocol_error_code = RX_ERROR_UNEXPECTED_DATAID;
        end else if (rx_duplicate) begin
            rx_protocol_error = 1'b1;
            rx_protocol_error_code = RX_ERROR_DUPLICATE_DATAID;
        end else if (rx_missing_be) begin
            rx_protocol_error = 1'b1;
            rx_protocol_error_code = RX_ERROR_MISSING_BE;
        end
    end

    assign rxdat_ready_o =
        (!rx_line_valid_q || rx_line_ready_i) &&
        (!rx_done_valid_q || rx_done_ready_i) &&
        (!rx_error_valid_q || rx_error_ready_i);

    assign rx_line_valid_o = rx_line_valid_q;
    assign rx_line_child_id_o = rx_line_child_q;
    assign rx_line_data_o = rx_line_data_q;
    assign rx_line_byte_mask_o = rx_line_mask_q;
    assign rx_line_resperr_o = rx_line_resperr_q;
    assign rx_done_valid_o = rx_done_valid_q;
    assign rx_done_child_id_o = rx_done_child_q;
    assign rx_error_valid_o = rx_error_valid_q;
    assign rx_error_txnid_o = rx_error_txnid_q;
    assign rx_error_child_id_o = rx_error_child_q;
    assign rx_error_code_o = rx_error_code_q;

    always @* begin
        tx_command_dat_mask = 4'b0000;
        for (tx_i = 0; tx_i < DATS_PER_LINE; tx_i = tx_i + 1) begin
            for (tx_byte_index = 0; tx_byte_index < CHI_BYTES;
                 tx_byte_index = tx_byte_index + 1) begin
                if (tx_cmd_required_mask_i[
                    (tx_i * CHI_BYTES) + tx_byte_index])
                    tx_command_dat_mask[tx_i] = 1'b1;
            end
        end

        tx_selected_ordinal = 2'b00;
        tx_selected_onehot = 4'b0000;
        if (tx_pending_dat_q[0]) begin
            tx_selected_ordinal = 2'd0;
            tx_selected_onehot = 4'b0001;
        end else if (tx_pending_dat_q[1]) begin
            tx_selected_ordinal = 2'd1;
            tx_selected_onehot = 4'b0010;
        end else if (tx_pending_dat_q[2]) begin
            tx_selected_ordinal = 2'd2;
            tx_selected_onehot = 4'b0100;
        end else if (tx_pending_dat_q[3]) begin
            tx_selected_ordinal = 2'd3;
            tx_selected_onehot = 4'b1000;
        end

        tx_selected_data = {CHI_DATA_WIDTH{1'b0}};
        tx_selected_be = {CHI_BE_WIDTH{1'b0}};
        for (tx_byte_index = 0; tx_byte_index < CHI_BE_WIDTH;
             tx_byte_index = tx_byte_index + 1) begin
            tx_line_byte_index =
                (tx_selected_ordinal * CHI_BYTES) + tx_byte_index;
            if (tx_line_byte_index < 64) begin
                tx_selected_be[tx_byte_index] =
                    tx_required_mask_q[tx_line_byte_index];
                if (tx_required_mask_q[tx_line_byte_index])
                    tx_selected_data[tx_byte_index*8 +: 8] =
                        tx_line_data_q[tx_line_byte_index*8 +: 8];
            end
        end

        if (CHI_DATA_WIDTH == 128)
            tx_selected_dataid = tx_selected_ordinal;
        else if (CHI_DATA_WIDTH == 256)
            tx_selected_dataid = {tx_selected_ordinal[0], 1'b0};
        else
            tx_selected_dataid = 2'b00;
    end

    assign tx_cmd_ready_o = !tx_busy_q &&
        (!tx_done_valid_q || tx_done_ready_i);
    assign txdat_valid_o = tx_busy_q && (|tx_pending_dat_q);
    assign txdat_child_id_o = tx_child_q;
    assign txdat_dataid_o = tx_selected_dataid;
    assign txdat_data_o = tx_selected_data;
    assign txdat_be_o = tx_selected_be;
    assign txdat_last_o =
        txdat_valid_o && ((tx_pending_dat_q & ~tx_selected_onehot) == 4'b0);
    assign tx_done_valid_o = tx_done_valid_q;
    assign tx_done_child_id_o = tx_done_child_q;
    always @* begin
        ctx_any_valid = 1'b0;
        for (ctx_i = 0; ctx_i < CTX_ENTRIES; ctx_i = ctx_i + 1)
            ctx_any_valid = ctx_any_valid || ctx_valid_q[ctx_i];
    end

    assign adapter_empty_o = !ctx_any_valid && !tx_busy_q &&
        !tx_done_valid_q && !rx_line_valid_q && !rx_done_valid_q &&
        !rx_error_valid_q;

    always @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            rx_line_valid_q <= 1'b0;
            rx_line_child_q <= {CHILD_ID_WIDTH{1'b0}};
            rx_line_data_q <= 512'b0;
            rx_line_mask_q <= 64'b0;
            rx_line_resperr_q <= 2'b00;
            rx_done_valid_q <= 1'b0;
            rx_done_child_q <= {CHILD_ID_WIDTH{1'b0}};
            rx_error_valid_q <= 1'b0;
            rx_error_txnid_q <= {TXNID_WIDTH{1'b0}};
            rx_error_child_q <= {CHILD_ID_WIDTH{1'b0}};
            rx_error_code_q <= 4'b0;
            tx_busy_q <= 1'b0;
            tx_child_q <= {CHILD_ID_WIDTH{1'b0}};
            tx_line_data_q <= 512'b0;
            tx_required_mask_q <= 64'b0;
            tx_pending_dat_q <= 4'b0;
            tx_done_valid_q <= 1'b0;
            tx_done_child_q <= {CHILD_ID_WIDTH{1'b0}};
            for (seq_i = 0; seq_i < CTX_ENTRIES; seq_i = seq_i + 1) begin
                ctx_valid_q[seq_i] <= 1'b0;
                ctx_child_q[seq_i] <= {CHILD_ID_WIDTH{1'b0}};
                ctx_txnid_q[seq_i] <= {TXNID_WIDTH{1'b0}};
                ctx_expected_dat_q[seq_i] <= 4'b0;
                ctx_received_dat_q[seq_i] <= 4'b0;
                ctx_required_byte_q[seq_i] <= 64'b0;
            end
        end else begin
            if (rx_line_valid_q && rx_line_ready_i)
                rx_line_valid_q <= 1'b0;
            if (rx_done_valid_q && rx_done_ready_i)
                rx_done_valid_q <= 1'b0;
            if (rx_error_valid_q && rx_error_ready_i)
                rx_error_valid_q <= 1'b0;
            if (tx_done_valid_q && tx_done_ready_i)
                tx_done_valid_q <= 1'b0;

            if (rd_ctx_alloc_valid_i && rd_ctx_alloc_ready_o) begin
                ctx_valid_q[alloc_free_index] <= 1'b1;
                ctx_child_q[alloc_free_index] <= rd_ctx_alloc_child_id_i;
                ctx_txnid_q[alloc_free_index] <= rd_ctx_alloc_txnid_i;
                ctx_expected_dat_q[alloc_free_index] <= alloc_expected_dat;
                ctx_received_dat_q[alloc_free_index] <= 4'b0;
                ctx_required_byte_q[alloc_free_index] <=
                    rd_ctx_alloc_required_mask_i;
            end

            if (rd_ctx_free_valid_i) begin
                for (seq_i = 0; seq_i < CTX_ENTRIES;
                     seq_i = seq_i + 1) begin
                    if (ctx_valid_q[seq_i] &&
                        ctx_child_q[seq_i] == rd_ctx_free_child_id_i)
                        ctx_valid_q[seq_i] <= 1'b0;
                end
            end

            if (rxdat_valid_i && rxdat_ready_o) begin
                if (rx_protocol_error &&
                    rx_protocol_error_code != RX_ERROR_MISSING_BE) begin
                    rx_error_valid_q <= 1'b1;
                    rx_error_txnid_q <= rxdat_txnid_i;
                    rx_error_child_q <= (rx_match_count == 1) ?
                        ctx_child_q[rx_match_index] :
                        {CHILD_ID_WIDTH{1'b0}};
                    rx_error_code_q <= rx_protocol_error_code;
                end else begin
                    rx_line_valid_q <= 1'b1;
                    rx_line_child_q <= ctx_child_q[rx_match_index];
                    rx_line_data_q <= rx_positioned_data;
                    rx_line_mask_q <= rx_required_chunk;
                    rx_line_resperr_q <=
                        (rxdat_resperr_i != 2'b00 || rx_missing_be) ?
                        2'b10 : 2'b00;
                    ctx_received_dat_q[rx_match_index] <= rx_received_next;
                    if (rx_missing_be) begin
                        rx_error_valid_q <= 1'b1;
                        rx_error_txnid_q <= rxdat_txnid_i;
                        rx_error_child_q <= ctx_child_q[rx_match_index];
                        rx_error_code_q <= RX_ERROR_MISSING_BE;
                    end
                    if (rx_received_next ==
                        ctx_expected_dat_q[rx_match_index]) begin
                        rx_done_valid_q <= 1'b1;
                        rx_done_child_q <= ctx_child_q[rx_match_index];
                    end
                end
            end

            if (tx_cmd_valid_i && tx_cmd_ready_o) begin
                tx_child_q <= tx_cmd_child_id_i;
                tx_line_data_q <= tx_cmd_line_data_i;
                tx_required_mask_q <= tx_cmd_required_mask_i;
                tx_pending_dat_q <= tx_command_dat_mask;
                if (tx_command_dat_mask == 4'b0) begin
                    tx_busy_q <= 1'b0;
                    tx_done_valid_q <= 1'b1;
                    tx_done_child_q <= tx_cmd_child_id_i;
                end else begin
                    tx_busy_q <= 1'b1;
                end
            end

            if (txdat_valid_o && txdat_sent_i) begin
                tx_pending_dat_q <= tx_pending_dat_q & ~tx_selected_onehot;
                if ((tx_pending_dat_q & ~tx_selected_onehot) == 4'b0) begin
                    tx_busy_q <= 1'b0;
                    tx_done_valid_q <= 1'b1;
                    tx_done_child_q <= tx_child_q;
                end
            end
        end
    end

endmodule
