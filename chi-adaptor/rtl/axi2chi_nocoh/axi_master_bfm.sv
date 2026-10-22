`timescale 1ns/1ps

module axi_master_bfm #(
    parameter int H2S_RUNTIME_ID = 0,
    parameter int BFM_ID = 0,
    parameter int ADDR_WIDTH = 64,
    parameter int DATA_WIDTH = 32,
    parameter int AWID_WIDTH = 4,
    parameter int BID_WIDTH = AWID_WIDTH,
    parameter int ARID_WIDTH = 4,
    parameter int RID_WIDTH = ARID_WIDTH,
    parameter int AXLEN_WIDTH = 8,
    parameter int AXSIZE_WIDTH = 3,
    parameter int USER_REQ_WIDTH = 0,
    parameter int USER_DATA_WIDTH = 0,
    parameter int USER_RESP_WIDTH = 0,
    parameter int CMD_FIFO_DEPTH = 16,
    parameter int WBEAT_FIFO_DEPTH = 64,
    parameter int RSP_FIFO_DEPTH = 64,
    parameter int INITIAL_POLL_INTERVAL = 1
) (
    input bit aclk,
    input bit aresetn,

    output bit [AWID_WIDTH-1:0] m_axi_awid,
    output bit [ADDR_WIDTH-1:0] m_axi_awaddr,
    output bit [AXLEN_WIDTH-1:0] m_axi_awlen,
    output bit [AXSIZE_WIDTH-1:0] m_axi_awsize,
    output bit [1:0] m_axi_awburst,
    output bit [(USER_REQ_WIDTH > 0 ? USER_REQ_WIDTH : 1)-1:0] m_axi_awuser,
    output bit m_axi_awvalid,
    input bit m_axi_awready,

    output bit [DATA_WIDTH-1:0] m_axi_wdata,
    output bit [DATA_WIDTH/8-1:0] m_axi_wstrb,
    output bit [(USER_DATA_WIDTH > 0 ? USER_DATA_WIDTH : 1)-1:0] m_axi_wuser,
    output bit m_axi_wlast,
    output bit m_axi_wvalid,
    input bit m_axi_wready,

    input bit [BID_WIDTH-1:0] m_axi_bid,
    input bit [1:0] m_axi_bresp,
    input bit [(USER_RESP_WIDTH > 0 ? USER_RESP_WIDTH : 1)-1:0] m_axi_buser,
    input bit m_axi_bvalid,
    output bit m_axi_bready,

    output bit [ARID_WIDTH-1:0] m_axi_arid,
    output bit [ADDR_WIDTH-1:0] m_axi_araddr,
    output bit [AXLEN_WIDTH-1:0] m_axi_arlen,
    output bit [AXSIZE_WIDTH-1:0] m_axi_arsize,
    output bit [1:0] m_axi_arburst,
    output bit [(USER_REQ_WIDTH > 0 ? USER_REQ_WIDTH : 1)-1:0] m_axi_aruser,
    output bit m_axi_arvalid,
    input bit m_axi_arready,

    input bit [RID_WIDTH-1:0] m_axi_rid,
    input bit [DATA_WIDTH-1:0] m_axi_rdata,
    input bit [1:0] m_axi_rresp,
    input bit [(USER_DATA_WIDTH + USER_RESP_WIDTH > 0 ? USER_DATA_WIDTH + USER_RESP_WIDTH : 1)-1:0] m_axi_ruser,
    input bit m_axi_rlast,
    input bit m_axi_rvalid,
    output bit m_axi_rready
);

  localparam int USER_REQ_SAFE = (USER_REQ_WIDTH > 0) ? USER_REQ_WIDTH : 1;
  localparam int USER_DATA_SAFE = (USER_DATA_WIDTH > 0) ? USER_DATA_WIDTH : 1;
  localparam int USER_RESP_SAFE = (USER_RESP_WIDTH > 0) ? USER_RESP_WIDTH : 1;
  localparam int RUSER_SAFE = (USER_DATA_WIDTH + USER_RESP_WIDTH > 0) ?
                              (USER_DATA_WIDTH + USER_RESP_WIDTH) : 1;

  import "DPI-C" context function void h2s_axi_master_init_v2(
      input int id,
      input int addr_width,
      input int data_width,
      input int awid_width,
      input int bid_width,
      input int arid_width,
      input int rid_width,
      input int axlen_width,
      input int axsize_width,
      input int user_req_width,
      input int user_data_width,
      input int user_resp_width,
      input int cmd_fifo_depth,
      input int wbeat_fifo_depth,
      input int rsp_fifo_depth,
      input int initial_poll_interval
  );

  import "DPI-C" context function void h2s_axi_master_init_v3(
      input int runtime_id,
      input int id,
      input int addr_width,
      input int data_width,
      input int awid_width,
      input int bid_width,
      input int arid_width,
      input int rid_width,
      input int axlen_width,
      input int axsize_width,
      input int user_req_width,
      input int user_data_width,
      input int user_resp_width,
      input int cmd_fifo_depth,
      input int wbeat_fifo_depth,
      input int rsp_fifo_depth,
      input int initial_poll_interval
  );

  import "DPI-C" context function void h2s_axi_master_poll(input int id);
  import "DPI-C" context function int h2s_axi_master_configured_poll_interval(
      input int id, input int fallback_poll_interval);

  import "DPI-C" context function void h2s_axi_master_bresp(
      input int id,
      input bit [BID_WIDTH-1:0] bid,
      input bit [1:0] bresp,
      input bit [USER_RESP_SAFE-1:0] buser
  );

  import "DPI-C" context function void h2s_axi_master_rbeat(
      input int id,
      input bit [RID_WIDTH-1:0] rid,
      input bit [DATA_WIDTH-1:0] rdata,
      input bit [1:0] rresp,
      input bit [RUSER_SAFE-1:0] ruser,
      input bit rlast
  );

  import "DPI-C" context function void h2s_axi_master_credit(
      input int id,
      input int write_begin_credit,
      input int read_credit,
      input int write_beat_credit
  );

  import "DPI-C" context function void h2s_axi_master_reset_notify(input int id);

  export "DPI-C" function s2h_axi_master_push_write_begin;
  export "DPI-C" function s2h_axi_master_push_write_beat;
  export "DPI-C" function s2h_axi_master_push_read;
  export "DPI-C" function s2h_axi_master_set_poll_interval;

  typedef struct packed {
    bit [AWID_WIDTH-1:0] id;
    bit [ADDR_WIDTH-1:0] addr;
    bit [AXLEN_WIDTH-1:0] len;
    bit [AXSIZE_WIDTH-1:0] size;
    bit [1:0] burst;
    bit [USER_REQ_SAFE-1:0] user;
  } write_begin_t;

  typedef struct packed {
    bit [ARID_WIDTH-1:0] id;
    bit [ADDR_WIDTH-1:0] addr;
    bit [AXLEN_WIDTH-1:0] len;
    bit [AXSIZE_WIDTH-1:0] size;
    bit [1:0] burst;
    bit [USER_REQ_SAFE-1:0] user;
  } read_cmd_t;

  typedef struct packed {
    bit [DATA_WIDTH-1:0] data;
    bit [DATA_WIDTH/8-1:0] strb;
    bit [USER_DATA_SAFE-1:0] user;
    bit last;
  } write_beat_t;

  write_begin_t write_begin_fifo [CMD_FIFO_DEPTH];
  read_cmd_t read_fifo [CMD_FIFO_DEPTH];
  write_beat_t write_beat_fifo [WBEAT_FIFO_DEPTH];

  int configured_poll_interval;
  int poll_counter;
  int write_begin_wr_ptr;
  int write_begin_rd_ptr;
  int write_begin_count;
  int read_wr_ptr;
  int read_rd_ptr;
  int read_count;
  int write_beat_wr_ptr;
  int write_beat_rd_ptr;
  int write_beat_count;
  int pending_write_beat_credit;
  int write_push_active;
  int expected_write_beats;
  int received_write_beats;
  bit sticky_overflow_error;
  bit sticky_sequence_error;
  bit reset_reported;

  initial begin
    configured_poll_interval = INITIAL_POLL_INTERVAL;
    poll_counter = INITIAL_POLL_INTERVAL;
    h2s_axi_master_init_v3(H2S_RUNTIME_ID, BFM_ID, ADDR_WIDTH, DATA_WIDTH,
                           AWID_WIDTH, BID_WIDTH, ARID_WIDTH, RID_WIDTH,
                           AXLEN_WIDTH, AXSIZE_WIDTH, USER_REQ_WIDTH,
                           USER_DATA_WIDTH, USER_RESP_WIDTH, CMD_FIFO_DEPTH,
                           WBEAT_FIFO_DEPTH, RSP_FIFO_DEPTH,
                           INITIAL_POLL_INTERVAL);
    configured_poll_interval = h2s_axi_master_configured_poll_interval(
        BFM_ID, INITIAL_POLL_INTERVAL);
    poll_counter = configured_poll_interval;
  end

  function void s2h_axi_master_set_poll_interval(input int cycles);
    configured_poll_interval = cycles;
  endfunction

  function void s2h_axi_master_push_write_begin(
      input bit [AWID_WIDTH-1:0] awid,
      input bit [ADDR_WIDTH-1:0] awaddr,
      input bit [AXLEN_WIDTH-1:0] awlen,
      input bit [AXSIZE_WIDTH-1:0] awsize,
      input bit [1:0] awburst,
      input bit [USER_REQ_SAFE-1:0] awuser
  );
    $display("AXI_MASTER_BFM_TRACE: push write addr=0x%0h len=%0d", awaddr, awlen);
    if (write_push_active != 0 || write_begin_count >= CMD_FIFO_DEPTH) begin
      sticky_sequence_error = 1'b1;
      if (write_begin_count >= CMD_FIFO_DEPTH) begin
        sticky_overflow_error = 1'b1;
      end
    end else begin
      write_begin_fifo[write_begin_wr_ptr].id = awid;
      write_begin_fifo[write_begin_wr_ptr].addr = awaddr;
      write_begin_fifo[write_begin_wr_ptr].len = awlen;
      write_begin_fifo[write_begin_wr_ptr].size = awsize;
      write_begin_fifo[write_begin_wr_ptr].burst = awburst;
      write_begin_fifo[write_begin_wr_ptr].user = awuser;
      write_begin_wr_ptr = (write_begin_wr_ptr + 1) % CMD_FIFO_DEPTH;
      write_begin_count = write_begin_count + 1;
      write_push_active = 1;
      expected_write_beats = awlen + 1;
      received_write_beats = 0;
    end
  endfunction

  function void s2h_axi_master_push_write_beat(
      input bit [DATA_WIDTH-1:0] wdata,
      input bit [DATA_WIDTH/8-1:0] wstrb,
      input bit [USER_DATA_SAFE-1:0] wuser,
      input bit wlast
  );
    $display("AXI_MASTER_BFM_TRACE: push write beat last=%0b", wlast);
    if (write_push_active == 0 || write_beat_count >= WBEAT_FIFO_DEPTH) begin
      sticky_sequence_error = 1'b1;
      if (write_beat_count >= WBEAT_FIFO_DEPTH) begin
        sticky_overflow_error = 1'b1;
      end
    end else begin
      write_beat_fifo[write_beat_wr_ptr].data = wdata;
      write_beat_fifo[write_beat_wr_ptr].strb = wstrb;
      write_beat_fifo[write_beat_wr_ptr].user = wuser;
      write_beat_fifo[write_beat_wr_ptr].last = wlast;
      write_beat_wr_ptr = (write_beat_wr_ptr + 1) % WBEAT_FIFO_DEPTH;
      write_beat_count = write_beat_count + 1;
      received_write_beats = received_write_beats + 1;
      if (wlast) begin
        if (received_write_beats + 1 != expected_write_beats) begin
          sticky_sequence_error = 1'b1;
        end
        write_push_active = 0;
      end else if (received_write_beats + 1 == expected_write_beats) begin
        sticky_sequence_error = 1'b1;
      end
    end
  endfunction

  function void s2h_axi_master_push_read(
      input bit [ARID_WIDTH-1:0] arid,
      input bit [ADDR_WIDTH-1:0] araddr,
      input bit [AXLEN_WIDTH-1:0] arlen,
      input bit [AXSIZE_WIDTH-1:0] arsize,
      input bit [1:0] arburst,
      input bit [USER_REQ_SAFE-1:0] aruser
  );
    if (write_push_active != 0 || read_count >= CMD_FIFO_DEPTH) begin
      sticky_sequence_error = 1'b1;
      if (read_count >= CMD_FIFO_DEPTH) begin
        sticky_overflow_error = 1'b1;
      end
    end else begin
      read_fifo[read_wr_ptr].id = arid;
      read_fifo[read_wr_ptr].addr = araddr;
      read_fifo[read_wr_ptr].len = arlen;
      read_fifo[read_wr_ptr].size = arsize;
      read_fifo[read_wr_ptr].burst = arburst;
      read_fifo[read_wr_ptr].user = aruser;
      read_wr_ptr = (read_wr_ptr + 1) % CMD_FIFO_DEPTH;
      read_count = read_count + 1;
    end
  endfunction

  always @(posedge aclk) begin
    if (!aresetn) begin
      m_axi_awid <= '0;
      m_axi_awaddr <= '0;
      m_axi_awlen <= '0;
      m_axi_awsize <= '0;
      m_axi_awburst <= '0;
      m_axi_awuser <= '0;
      m_axi_awvalid <= 1'b0;
      m_axi_wdata <= '0;
      m_axi_wstrb <= '0;
      m_axi_wuser <= '0;
      m_axi_wlast <= 1'b0;
      m_axi_wvalid <= 1'b0;
      pending_write_beat_credit <= 0;
      m_axi_bready <= 1'b1;
      m_axi_arid <= '0;
      m_axi_araddr <= '0;
      m_axi_arlen <= '0;
      m_axi_arsize <= '0;
      m_axi_arburst <= '0;
      m_axi_aruser <= '0;
      m_axi_arvalid <= 1'b0;
      m_axi_rready <= 1'b1;
      poll_counter <= configured_poll_interval;
      if (!reset_reported) begin
        h2s_axi_master_reset_notify(BFM_ID);
        h2s_axi_master_credit(BFM_ID, CMD_FIFO_DEPTH, CMD_FIFO_DEPTH, WBEAT_FIFO_DEPTH);
        reset_reported <= 1'b1;
      end
    end else begin
      reset_reported <= 1'b0;
      if (poll_counter <= 0) begin
        h2s_axi_master_poll(BFM_ID);
        poll_counter <= configured_poll_interval;
      end else begin
        poll_counter <= poll_counter - 1;
      end

      if (m_axi_bvalid && m_axi_bready) begin
        h2s_axi_master_bresp(BFM_ID, m_axi_bid, m_axi_bresp, m_axi_buser);
      end
      if (m_axi_rvalid && m_axi_rready) begin
        h2s_axi_master_rbeat(BFM_ID, m_axi_rid, m_axi_rdata, m_axi_rresp, m_axi_ruser,
                             m_axi_rlast);
      end

      if (m_axi_awvalid && m_axi_awready) begin
        m_axi_awvalid <= 1'b0;
      end
      if (!m_axi_awvalid && write_begin_count > 0) begin
        $display("AXI_MASTER_BFM_TRACE: drive AW addr=0x%0h", 
                 write_begin_fifo[write_begin_rd_ptr].addr);
        m_axi_awid <= write_begin_fifo[write_begin_rd_ptr].id;
        m_axi_awaddr <= write_begin_fifo[write_begin_rd_ptr].addr;
        m_axi_awlen <= write_begin_fifo[write_begin_rd_ptr].len;
        m_axi_awsize <= write_begin_fifo[write_begin_rd_ptr].size;
        m_axi_awburst <= write_begin_fifo[write_begin_rd_ptr].burst;
        m_axi_awuser <= write_begin_fifo[write_begin_rd_ptr].user;
        m_axi_awvalid <= 1'b1;
        write_begin_rd_ptr <= (write_begin_rd_ptr + 1) % CMD_FIFO_DEPTH;
        write_begin_count <= write_begin_count - 1;
        h2s_axi_master_credit(BFM_ID, 1, 0, 0);
      end

      if (m_axi_wvalid && m_axi_wready) begin
        m_axi_wvalid <= 1'b0;
      end
      if (!m_axi_wvalid && write_beat_count > 0) begin
        $display("AXI_MASTER_BFM_TRACE: drive W last=%0b", 
                 write_beat_fifo[write_beat_rd_ptr].last);
        m_axi_wdata <= write_beat_fifo[write_beat_rd_ptr].data;
        m_axi_wstrb <= write_beat_fifo[write_beat_rd_ptr].strb;
        m_axi_wuser <= write_beat_fifo[write_beat_rd_ptr].user;
        m_axi_wlast <= write_beat_fifo[write_beat_rd_ptr].last;
        m_axi_wvalid <= 1'b1;
        write_beat_rd_ptr <= (write_beat_rd_ptr + 1) % WBEAT_FIFO_DEPTH;
        write_beat_count <= write_beat_count - 1;
        if (write_beat_fifo[write_beat_rd_ptr].last) begin
          h2s_axi_master_credit(BFM_ID, 0, 0, pending_write_beat_credit + 1);
          pending_write_beat_credit <= 0;
        end else begin
          pending_write_beat_credit <= pending_write_beat_credit + 1;
        end
      end

      if (m_axi_arvalid && m_axi_arready) begin
        m_axi_arvalid <= 1'b0;
      end
      if (!m_axi_arvalid && read_count > 0) begin
        m_axi_arid <= read_fifo[read_rd_ptr].id;
        m_axi_araddr <= read_fifo[read_rd_ptr].addr;
        m_axi_arlen <= read_fifo[read_rd_ptr].len;
        m_axi_arsize <= read_fifo[read_rd_ptr].size;
        m_axi_arburst <= read_fifo[read_rd_ptr].burst;
        m_axi_aruser <= read_fifo[read_rd_ptr].user;
        m_axi_arvalid <= 1'b1;
        read_rd_ptr <= (read_rd_ptr + 1) % CMD_FIFO_DEPTH;
        read_count <= read_count - 1;
        h2s_axi_master_credit(BFM_ID, 0, 1, 0);
      end
    end
  end

endmodule
