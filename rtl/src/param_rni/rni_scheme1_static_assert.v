// Scheme-1 Gate-0 static and transaction-contract assertions.
module rni_scheme1_static_assert #(
    parameter integer AXI_DATA_WIDTH = 128,
    parameter integer CHI_DATA_WIDTH = 256,
    parameter integer CHI_BE_WIDTH = 32,
    parameter integer CHI_TXNID_WIDTH = 12,
    parameter integer SLOT_COUNT = 32,
    parameter integer DBID_MAP_DEPTH = 32,
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
    localparam integer AXI_BYTES = AXI_DATA_WIDTH/8;
    // Keep a one-bit slice for a single-entry implementation; this avoids an
    // illegal [-1:0] part select while preserving the elaboration constraint.
    localparam integer SLOT_BITS = (SLOT_COUNT <= 1) ? 1 : $clog2(SLOT_COUNT);
    initial begin
      if (!((AXI_DATA_WIDTH==8)||(AXI_DATA_WIDTH==16)||(AXI_DATA_WIDTH==32)||(AXI_DATA_WIDTH==64)||(AXI_DATA_WIDTH==128)||(AXI_DATA_WIDTH==256)||(AXI_DATA_WIDTH==512)||(AXI_DATA_WIDTH==1024))) $fatal(1,"Scheme1: illegal AXI4 full width");
      if (!((CHI_DATA_WIDTH==128)||(CHI_DATA_WIDTH==256)||(CHI_DATA_WIDTH==512))) $fatal(1,"Scheme1: illegal CHI DAT width");
      if (CHI_BE_WIDTH != CHI_DATA_WIDTH/8) $fatal(1,"Scheme1: CHIE_BE_WIDTH mismatch");
      if (CHI_TXNID_WIDTH < 2+SLOT_BITS) $fatal(1,"Scheme1: TxnID width cannot encode profile/direction/slot");
      if (DBID_MAP_DEPTH < 2*SLOT_COUNT) $fatal(1,"Scheme1: DBID map too shallow");
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
