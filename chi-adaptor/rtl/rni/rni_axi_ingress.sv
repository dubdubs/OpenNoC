// AXI ingress skeleton for the AXI-to-CHI RNI.
//
// The port shape matches axi_master_bfm m_axi_* signals. This module is
// synthesizable RTL scaffolding only; the DPI-based BFM remains simulation
// infrastructure and is never instantiated by the RNI implementation.

`default_nettype none

module rni_axi_ingress #(
  parameter int unsigned AddrWidth = 64,
  parameter int unsigned DataWidth = 32,
  parameter int unsigned AwidWidth = 4,
  parameter int unsigned BidWidth = AwidWidth,
  parameter int unsigned AridWidth = 4,
  parameter int unsigned RidWidth = AridWidth,
  parameter int unsigned AxlenWidth = 8,
  parameter int unsigned AxsizeWidth = 3,
  parameter int unsigned UserReqWidth = 0,
  parameter int unsigned UserDataWidth = 0,
  parameter int unsigned UserRespWidth = 0
) (
  input  logic                         aclk,
  input  logic                         aresetn,

  input  logic [AwidWidth-1:0]         s_axi_awid,
  input  logic [AddrWidth-1:0]         s_axi_awaddr,
  input  logic [AxlenWidth-1:0]        s_axi_awlen,
  input  logic [AxsizeWidth-1:0]       s_axi_awsize,
  input  logic [1:0]                   s_axi_awburst,
  input  logic [(UserReqWidth > 0 ? UserReqWidth : 1)-1:0] s_axi_awuser,
  input  logic                         s_axi_awvalid,
  output logic                         s_axi_awready,

  input  logic [DataWidth-1:0]         s_axi_wdata,
  input  logic [DataWidth / 8-1:0]     s_axi_wstrb,
  input  logic [(UserDataWidth > 0 ? UserDataWidth : 1)-1:0] s_axi_wuser,
  input  logic                         s_axi_wlast,
  input  logic                         s_axi_wvalid,
  output logic                         s_axi_wready,

  output logic [BidWidth-1:0]          s_axi_bid,
  output logic [1:0]                   s_axi_bresp,
  output logic [(UserRespWidth > 0 ? UserRespWidth : 1)-1:0] s_axi_buser,
  output logic                         s_axi_bvalid,
  input  logic                         s_axi_bready,

  input  logic [AridWidth-1:0]         s_axi_arid,
  input  logic [AddrWidth-1:0]         s_axi_araddr,
  input  logic [AxlenWidth-1:0]        s_axi_arlen,
  input  logic [AxsizeWidth-1:0]       s_axi_arsize,
  input  logic [1:0]                   s_axi_arburst,
  input  logic [(UserReqWidth > 0 ? UserReqWidth : 1)-1:0] s_axi_aruser,
  input  logic                         s_axi_arvalid,
  output logic                         s_axi_arready,

  output logic [RidWidth-1:0]          s_axi_rid,
  output logic [DataWidth-1:0]         s_axi_rdata,
  output logic [1:0]                   s_axi_rresp,
  output logic [(UserDataWidth + UserRespWidth > 0 ?
                    UserDataWidth + UserRespWidth : 1)-1:0] s_axi_ruser,
  output logic                         s_axi_rlast,
  output logic                         s_axi_rvalid,
  input  logic                         s_axi_rready,

  // Atomic write handoff. A bundle always represents one legal single-beat
  // AXI write; command and data must be accepted together by the consumer.
  output logic                         write_bundle_valid_o,
  output logic [AwidWidth-1:0]         write_bundle_id_o,
  output logic [AddrWidth-1:0]         write_bundle_addr_o,
  output logic [AxlenWidth-1:0]        write_bundle_len_o,
  output logic [AxsizeWidth-1:0]       write_bundle_size_o,
  output logic [1:0]                   write_bundle_burst_o,
  output logic [DataWidth-1:0]         write_bundle_data_o,
  output logic [DataWidth / 8-1:0]     write_bundle_strb_o,
  input  logic                         write_bundle_ready_i,

  // Atomic read handoff. A bundle represents one captured AXI AR command.
  output logic                         read_bundle_valid_o,
  output logic [AridWidth-1:0]         read_bundle_id_o,
  output logic [AddrWidth-1:0]         read_bundle_addr_o,
  output logic [AxlenWidth-1:0]        read_bundle_len_o,
  output logic [AxsizeWidth-1:0]       read_bundle_size_o,
  output logic [1:0]                   read_bundle_burst_o,
  input  logic                         read_bundle_ready_i
);

  localparam int unsigned UserReqWidthSafe =
      (UserReqWidth > 0) ? UserReqWidth : 1;
  localparam int unsigned UserDataWidthSafe =
      (UserDataWidth > 0) ? UserDataWidth : 1;
  localparam int unsigned UserRespWidthSafe =
      (UserRespWidth > 0) ? UserRespWidth : 1;
  localparam int unsigned RuserWidthSafe =
      (UserDataWidth + UserRespWidth > 0) ?
          (UserDataWidth + UserRespWidth) : 1;

  typedef struct packed {
    logic [AwidWidth-1:0] id;
    logic [AddrWidth-1:0] addr;
    logic [AxlenWidth-1:0] len;
    logic [AxsizeWidth-1:0] size;
    logic [1:0] burst;
    logic [UserReqWidthSafe-1:0] user;
  } axi_aw_t;

  typedef struct packed {
    logic [AridWidth-1:0] id;
    logic [AddrWidth-1:0] addr;
    logic [AxlenWidth-1:0] len;
    logic [AxsizeWidth-1:0] size;
    logic [1:0] burst;
    logic [UserReqWidthSafe-1:0] user;
  } axi_ar_t;

  typedef struct packed {
    logic [DataWidth-1:0] data;
    logic [DataWidth / 8-1:0] strb;
    logic [UserDataWidthSafe-1:0] user;
    logic last;
  } axi_w_t;

  typedef enum logic [2:0] {
    kWriteIdle,
    kWriteCollect,
    kWriteWaitChild,
    kWritePresentB,
    kWriteErrorDrain
  } write_state_t;

  typedef enum logic [2:0] {
    kReadIdle,
    kReadWaitChild,
    kReadPresentR,
    kReadErrorDrain
  } read_state_t;

  // Sequential state placeholders. Clock and reset source ownership belongs
  // to the final system integration; axi_master_bfm will connect aclk and
  // aresetn at that boundary.
  write_state_t write_state_q;
  read_state_t  read_state_q;
  axi_aw_t      aw_capture_q;
  axi_ar_t      ar_capture_q;
  axi_w_t       w_capture_q;
  logic         aw_capture_valid_q;
  logic         ar_capture_valid_q;
  logic         w_capture_valid_q;
  logic         w_protocol_error_q;

  // Response holding registers preserve AXI payload stability under BREADY
  // and RREADY backpressure.
  logic [BidWidth-1:0]          b_id_q;
  logic [1:0]                   b_resp_q;
  logic [UserRespWidthSafe-1:0] b_user_q;
  logic                         b_valid_q;
  logic [RidWidth-1:0]          r_id_q;
  logic [DataWidth-1:0]         r_data_q;
  logic [1:0]                   r_resp_q;
  logic [RuserWidthSafe-1:0]    r_user_q;
  logic                         r_last_q;
  logic                         r_valid_q;

  // AR skid-buffer hardware. This one-entry register prevents a second AR
  // from overwriting an accepted request before a future core interface has
  // consumed it. The enable is exactly the AXI AR handshake.
  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      write_state_q <= kWriteIdle;
      read_state_q <= kReadIdle;
      aw_capture_q <= '0;
      ar_capture_q <= '0;
      w_capture_q <= '0;
      aw_capture_valid_q <= 1'b0;
      ar_capture_valid_q <= 1'b0;
      w_capture_valid_q <= 1'b0;
      w_protocol_error_q <= 1'b0;
      b_id_q <= '0;
      b_resp_q <= '0;
      b_user_q <= '0;
      b_valid_q <= 1'b0;
      r_id_q <= '0;
      r_data_q <= '0;
      r_resp_q <= '0;
      r_user_q <= '0;
      r_last_q <= 1'b0;
      r_valid_q <= 1'b0;
    end else begin
      // AW and AR are independent AXI channels. Separate enables permit both
      // address registers to capture on the same clock edge.
      if (s_axi_awvalid && s_axi_awready) begin
        aw_capture_q.id <= s_axi_awid;
        aw_capture_q.addr <= s_axi_awaddr;
        aw_capture_q.len <= s_axi_awlen;
        aw_capture_q.size <= s_axi_awsize;
        aw_capture_q.burst <= s_axi_awburst;
        aw_capture_q.user <= s_axi_awuser;
        aw_capture_valid_q <= 1'b1;
      end

      if (s_axi_arvalid && s_axi_arready) begin
        ar_capture_q.id <= s_axi_arid;
        ar_capture_q.addr <= s_axi_araddr;
        ar_capture_q.len <= s_axi_arlen;
        ar_capture_q.size <= s_axi_arsize;
        ar_capture_q.burst <= s_axi_arburst;
        ar_capture_q.user <= s_axi_aruser;
        ar_capture_valid_q <= 1'b1;
      end

      // This increment accepts exactly one W beat only after its AW context
      // has been captured. Multi-beat writes remain backpressured until the
      // later beat-counter/data-buffer increment exists.
      if (s_axi_wvalid && s_axi_wready) begin
        w_capture_q.data <= s_axi_wdata;
        w_capture_q.strb <= s_axi_wstrb;
        w_capture_q.user <= s_axi_wuser;
        w_capture_q.last <= s_axi_wlast;
        w_capture_valid_q <= 1'b1;
        w_protocol_error_q <= !s_axi_wlast;
      end

      // The pair is released only by one atomic downstream handshake. This
      // prevents a command/data association from being split by backpressure.
      if (write_bundle_valid_o && write_bundle_ready_i) begin
        aw_capture_valid_q <= 1'b0;
        w_capture_valid_q <= 1'b0;
      end

      if (read_bundle_valid_o && read_bundle_ready_i) begin
        ar_capture_valid_q <= 1'b0;
      end
    end
  end

  // Combinational AXI boundary. All channels except AR remain deliberately
  // backpressured until their individual incremental implementations exist.
  always_comb begin
    s_axi_awready = aresetn && !aw_capture_valid_q;
    s_axi_wready = aresetn && aw_capture_valid_q && !w_capture_valid_q &&
                   (aw_capture_q.len == '0);
    s_axi_bid = b_id_q;
    s_axi_bresp = b_resp_q;
    s_axi_buser = b_user_q;
    s_axi_bvalid = b_valid_q;
    s_axi_arready = aresetn && !ar_capture_valid_q;
    s_axi_rid = r_id_q;
    s_axi_rdata = r_data_q;
    s_axi_rresp = r_resp_q;
    s_axi_ruser = r_user_q;
    s_axi_rlast = r_last_q;
    s_axi_rvalid = r_valid_q;
    write_bundle_valid_o = aw_capture_valid_q && w_capture_valid_q &&
                           !w_protocol_error_q;
    write_bundle_id_o = aw_capture_q.id;
    write_bundle_addr_o = aw_capture_q.addr;
    write_bundle_len_o = aw_capture_q.len;
    write_bundle_size_o = aw_capture_q.size;
    write_bundle_burst_o = aw_capture_q.burst;
    write_bundle_data_o = w_capture_q.data;
    write_bundle_strb_o = w_capture_q.strb;
    read_bundle_valid_o = ar_capture_valid_q;
    read_bundle_id_o = ar_capture_q.id;
    read_bundle_addr_o = ar_capture_q.addr;
    read_bundle_len_o = ar_capture_q.len;
    read_bundle_size_o = ar_capture_q.size;
    read_bundle_burst_o = ar_capture_q.burst;
  end

  // Admission, AR-to-core dequeue, policy lookup, parent/child allocation,
  // write channels and response generation are deferred to later increments.

endmodule

`default_nettype wire
