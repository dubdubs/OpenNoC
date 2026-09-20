// CHI Device CSR-slave skeleton for the RNI policy region table.
//
// This is not the raw P0-link owner. It consumes canonical flits after
// rni_xp_p0_link_ctl dispatches a request within the immutable CSR window.
// Register update, CHI field decode/pack and commit behavior are deferred to
// incremental RTL steps.

`default_nettype none

module policy_csr_chi_slave #(
  parameter int unsigned AxiAddrWidth = 64,
  parameter int unsigned RegionEntries = 32,
  parameter int unsigned PolicyEpochWidth = 8,
  parameter int unsigned ReqFlitWidth = 131,
  parameter int unsigned RspFlitWidth = 73,
  parameter int unsigned DatFlitWidth = 406,
  parameter logic [AxiAddrWidth-1:0] PolicyCsrBase =
      64'h0000_0020_0000_0000,
  parameter logic [AxiAddrWidth-1:0] PolicyCsrSize =
      64'h0000_0000_0000_1000
) (
  input  logic                         clk,
  input  logic                         rst,

  // Canonical inbound CHI request/data flits from the sole P0-link owner.
  input  logic                         rxreq_valid_i,
  input  logic [ReqFlitWidth-1:0]      rxreq_payload_i,
  output logic                         rxreq_ready_o,
  input  logic                         rxdat_valid_i,
  input  logic [DatFlitWidth-1:0]      rxdat_payload_i,
  output logic                         rxdat_ready_o,

  // Canonical outbound CHI responses from this Device slave.
  output logic                         txrsp_valid_o,
  output logic [RspFlitWidth-1:0]      txrsp_payload_o,
  input  logic                         txrsp_ready_i,
  output logic                         txdat_valid_o,
  output logic [DatFlitWidth-1:0]      txdat_payload_o,
  input  logic                         txdat_ready_i,

  // Policy lookup boundary to rni_core. A lookup observes active-bank data
  // only; shadow writes cannot change an admitted transaction's snapshot.
  input  logic                         lookup_valid_i,
  input  logic [AxiAddrWidth-1:0]      lookup_addr_i,
  output logic                         lookup_hit_o,
  output logic [1:0]                   lookup_region_type_o,
  output logic [PolicyEpochWidth-1:0]  policy_epoch_o,
  output logic                         quiesce_req_o,
  input  logic                         drain_done_i
);

  localparam int unsigned RegionIndexWidth = $clog2(RegionEntries);
  localparam int unsigned CsrWordBytes = 4;
  localparam int unsigned RegionStrideBytes = 32;

  typedef enum logic [2:0] {
    kCsrIdle,
    kCsrReadRespond,
    kCsrWriteSendDbidResp,
    kCsrWriteWaitData,
    kCsrWriteSendComp,
    kCsrCommitDrain
  } csr_state_t;

  typedef struct packed {
    logic                        valid;
    logic [AxiAddrWidth-1:0]     base;
    logic [AxiAddrWidth-1:0]     limit;
    logic [31:0]                 attr;
  } region_entry_t;

  // Sequential active/shadow state. Both banks reset from elaboration-time
  // reset image parameters in the later register-update increment.
  region_entry_t active_region_q [RegionEntries];
  region_entry_t shadow_region_q [RegionEntries];
  csr_state_t csr_state_q;
  logic [PolicyEpochWidth-1:0] policy_epoch_q;
  logic commit_pending_q;
  logic commit_error_q;

  // Sequential write context required between WriteNoSnpPtl DBIDResp and its
  // matching NonCopyBackWrData. Exact CHI field positions are deliberately
  // not assumed in the skeleton.
  logic [ReqFlitWidth-1:0] write_req_context_q;
  logic write_context_valid_q;

  // All request decoding, CSR address decode, non-overlap validation,
  // byte-enable updates, DBID allocation/match, CHI response construction,
  // active-bank lookup and commit sequencing are deferred. Future
  // combinational blocks provide defaults; all state updates use always_ff.

endmodule

`default_nettype wire
