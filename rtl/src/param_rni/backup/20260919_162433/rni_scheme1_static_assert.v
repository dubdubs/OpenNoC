// Scheme-1 Gate-0 static and transaction-contract assertions.
module rni_scheme1_static_assert #(
    parameter integer AXI_DATA_WIDTH = 128,
    parameter integer CHI_DATA_WIDTH = 256,
    parameter integer CHI_BE_WIDTH = 32,
    parameter integer CHI_TXNID_WIDTH = 12,
    parameter integer SLOT_COUNT = 32,
    parameter integer DBID_MAP_DEPTH = 64,
    parameter integer CHI_DATAID_WIDTH = 2,
    parameter integer LINE_BYTES = 64,
    parameter integer SLOT_BYTES = 16,
    parameter integer AR_ENTRIES = 32,
    parameter integer AW_ENTRIES = 32,
    parameter integer PARENT_TABLE_DEPTH = 64,
    parameter integer CHILD_TABLE_DEPTH = 64,
    parameter integer FRAGMENT_TABLE_DEPTH = 128,
    parameter integer MAX_AXI_BEATS = 256,
    parameter integer BEAT_ID_WIDTH = 8,
    parameter integer FRAGMENT_ID_WIDTH = 9,
    parameter integer BYTE_COUNT_WIDTH = 7,
    parameter integer ENABLE_NONCOHERENT = 1,
    parameter integer ENABLE_COHERENT = 1,
    parameter integer TXRSP_CREDITS = 4
) (
    input wire clk, input wire rst,
    input wire admission_valid, input wire [2:0] axsize,
    input wire profile_coherent, input wire profile_enabled,
    input wire [CHI_TXNID_WIDTH-1:0] txnid,
    input wire txrsp_valid, input wire txrsp_credit,
    input wire req_attr_complete
);
    localparam integer AXI_BYTES = AXI_DATA_WIDTH / 8;
    localparam integer CHI_DAT_BYTES = CHI_DATA_WIDTH / 8;
    localparam integer CANONICAL_SLOT_COUNT = LINE_BYTES / SLOT_BYTES;
    localparam integer CHI_DATS_PER_LINE = LINE_BYTES / CHI_DAT_BYTES;
    localparam integer DATAID_ORDINAL_BITS =
        (CHI_DATS_PER_LINE <= 1) ? 1 : $clog2(CHI_DATS_PER_LINE);
    // Keep a one-bit slice for a single-entry implementation; this avoids an
    // illegal [-1:0] part select while preserving the elaboration constraint.
    localparam integer SLOT_BITS = (SLOT_COUNT <= 1) ? 1 : $clog2(SLOT_COUNT);
    initial begin
      if (!((AXI_DATA_WIDTH==8)||(AXI_DATA_WIDTH==16)||(AXI_DATA_WIDTH==32)||(AXI_DATA_WIDTH==64)||(AXI_DATA_WIDTH==128)||(AXI_DATA_WIDTH==256)||(AXI_DATA_WIDTH==512)||(AXI_DATA_WIDTH==1024))) $fatal(1,"Scheme1: illegal AXI4 full width");
      if (!((CHI_DATA_WIDTH==128)||(CHI_DATA_WIDTH==256)||(CHI_DATA_WIDTH==512))) $fatal(1,"Scheme1: illegal CHI DAT width");
      if ((AXI_DATA_WIDTH % 8) != 0 || (AXI_BYTES & (AXI_BYTES - 1)) != 0) $fatal(1,"Scheme1: AXI width must contain a power-of-two byte count");
      if ((CHI_DATA_WIDTH % 8) != 0 || (CHI_DAT_BYTES & (CHI_DAT_BYTES - 1)) != 0) $fatal(1,"Scheme1: CHI DAT width must contain a power-of-two byte count");
      if (CHI_BE_WIDTH != CHI_DAT_BYTES) $fatal(1,"Scheme1: CHIE_BE_WIDTH mismatch");
      if (LINE_BYTES != 64 || SLOT_BYTES != 16 || CANONICAL_SLOT_COUNT != 4) $fatal(1,"Scheme1: canonical layout must remain four 128-bit slots per 64-byte line");
      if ((LINE_BYTES % SLOT_BYTES) != 0 || (LINE_BYTES % CHI_DAT_BYTES) != 0 || (CHI_DAT_BYTES % SLOT_BYTES) != 0) $fatal(1,"Scheme1: slot/DAT/line layout is not integral");
      if (SLOT_COUNT <= 0 || CHI_TXNID_WIDTH < 2 + SLOT_BITS) $fatal(1,"Scheme1: TxnID width cannot encode profile/direction/slot");
      if (AR_ENTRIES <= 0 || AW_ENTRIES <= 0) $fatal(1,"Scheme1: AR/AW entry counts must be positive");
      if (AR_ENTRIES > SLOT_COUNT || AW_ENTRIES > SLOT_COUNT) $fatal(1,"Scheme1: AR/AW entries exceed TxnID slot capacity");
      if (PARENT_TABLE_DEPTH < AR_ENTRIES + AW_ENTRIES) $fatal(1,"Scheme1: parent table cannot cover all AR/AW entries");
      if (CHILD_TABLE_DEPTH < AR_ENTRIES + AW_ENTRIES) $fatal(1,"Scheme1: child table cannot cover the active parent window");
      if (FRAGMENT_TABLE_DEPTH < 2 * PARENT_TABLE_DEPTH) $fatal(1,"Scheme1: fragment table cannot reserve two fragments per admitted parent");
      if (DBID_MAP_DEPTH < 2 * SLOT_COUNT) $fatal(1,"Scheme1: DBID map too shallow");
      if (MAX_AXI_BEATS <= 0 || (1 << BEAT_ID_WIDTH) < MAX_AXI_BEATS) $fatal(1,"Scheme1: beat_id cannot encode the maximum AXI burst");
      if ((1 << FRAGMENT_ID_WIDTH) < 2 * MAX_AXI_BEATS) $fatal(1,"Scheme1: fragment_id cannot encode two fragments per AXI beat");
      if ((1 << BYTE_COUNT_WIDTH) <= LINE_BYTES) $fatal(1,"Scheme1: byte_count cannot encode a full canonical line");
      if (CHI_DATAID_WIDTH < DATAID_ORDINAL_BITS || (1 << CHI_DATAID_WIDTH) < CHI_DATS_PER_LINE) $fatal(1,"Scheme1: DataID cannot encode every legal DAT ordinal");
      if (TXRSP_CREDITS == 0) $fatal(1,"Scheme1: CompAck needs TXRSP credit");
    end
    always @(posedge clk) if (!rst) begin
      if (admission_valid && axsize > $clog2(AXI_BYTES)) $error("Scheme1: AxSIZE exceeds AXI bus width");
      if (admission_valid && !profile_enabled) $error("Scheme1: request selected unimplemented profile");
      if (admission_valid && profile_coherent && !ENABLE_COHERENT) $error("Scheme1: coherent request disabled");
      if (admission_valid && !profile_coherent && !ENABLE_NONCOHERENT) $error("Scheme1: noncoherent request disabled");
      if (admission_valid && !req_attr_complete) $error("Scheme1: incomplete req_attr");
      if (txrsp_valid && !txrsp_credit) $error("Scheme1: CompAck attempted without TXRSP credit");
      if (admission_valid && txnid[SLOT_BITS-1:0] >= SLOT_COUNT)
        $error("Scheme1: TxnID slot is outside the configured range");
    end
endmodule
