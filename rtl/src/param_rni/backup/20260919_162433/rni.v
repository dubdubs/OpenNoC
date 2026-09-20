/*
* Copyright (c) 2024 Beijing Institute of Open Source Chip
* OpenNoC is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
* See the Mulan PSL v2 for more details.
*
* Author:
*    Ziqing Li <liziqing@bosc.ac.cn>
*    Wenhao Li <liwenhao@bosc.ac.cn>
*/

`include "rni_param.v"
`include "rni_defines.v"
`include "axi4_defines.v"
`include "chie_defines.v"

module rni `RNI_PARAM
    (
        // global inputs
        CLK
        ,RST

        // link handshake
        ,TXLINKACTIVEREQ
        ,TXLINKACTIVEACK
        ,RXLINKACTIVEREQ
        ,RXLINKACTIVEACK

        // CHI interface
        ,RXRSPFLITPEND
        ,RXRSPFLITV
        ,RXRSPFLIT
        ,RXRSPLCRDV
        ,RXDATFLITPEND
        ,RXDATFLITV
        ,RXDATFLIT
        ,RXDATLCRDV
        ,TXRSPFLITPEND
        ,TXRSPFLITV
        ,TXRSPFLIT
        ,TXRSPLCRDV
        ,TXDATFLITPEND
        ,TXDATFLITV
        ,TXDATFLIT
        ,TXDATLCRDV
        ,TXREQFLITPEND
        ,TXREQFLITV
        ,TXREQFLIT
        ,TXREQLCRDV

        // AXI interface
        ,AWID0
        ,AWADDR0
        ,AWLEN0
        ,AWSIZE0
        ,AWBURST0
        ,AWLOCK0
        ,AWCACHE0
        ,AWPROT0
        ,AWQOS0
        ,AWREGION0
        ,AWVALID0
        ,AWREADY0
        ,WDATA0
        ,WSTRB0
        ,WLAST0
        ,WVALID0
        ,WREADY0
        ,BID0
        ,BRESP0
        ,BVALID0
        ,BREADY0
        ,ARID0
        ,ARADDR0
        ,ARLEN0
        ,ARSIZE0
        ,ARBURST0
        ,ARLOCK0
        ,ARCACHE0
        ,ARPROT0
        ,ARQOS0
        ,ARREGION0
        ,ARVALID0
        ,ARREADY0
        ,RID0
        ,RDATA0
        ,RRESP0
        ,RLAST0
        ,RVALID0
        ,RREADY0

        // Scheme-1 policy sideband and secure CSR control plane.
        // These ports are part of the versioned AXI integration contract.
        ,ARREQUESTER0
        ,ARNONSECURE0
        ,ARINTENTVALID0
        ,ARCOHINTENT0
        ,AWREQUESTER0
        ,AWNONSECURE0
        ,AWINTENTVALID0
        ,AWCOHINTENT0
        ,POLICYCSRSECURE
        ,POLICYCSRWRITE
        ,POLICYCSRINDEX
        ,POLICYCSRBASE
        ,POLICYCSRLIMIT
        ,POLICYCSRREQUESTERVALUE
        ,POLICYCSRREQUESTERMASK
        ,POLICYCSRALLOWEDPROFILES
        ,POLICYCSRDEFAULTCOHERENT
        ,POLICYCSRALLOWINTENT
        ,POLICYCSRNONSECUREONLY
        ,POLICYCSRLOCK
        ,POLICYCSRCOMMIT
        ,POLICYCSRSECURITYEVENTCLEAR
        ,POLICYCSRLOCKED
        ,POLICYCSRCOMMITBUSY
        ,POLICYCSRCOMMITERROR
        ,POLICYCSRSECURITYEVENT
        ,POLICYEPOCH
    );

    // global ports
    input  wire                                 CLK;
    input  wire                                 RST;

    // link handshake
    output wire                                 TXLINKACTIVEREQ;
    input  wire                                 TXLINKACTIVEACK;
    input  wire                                 RXLINKACTIVEREQ;
    output wire                                 RXLINKACTIVEACK;

    // CHI interface
    input  wire                                 RXRSPFLITPEND;
    input  wire                                 RXRSPFLITV;
    input  wire [`CHIE_RSP_FLIT_RANGE]          RXRSPFLIT;
    output wire                                 RXRSPLCRDV;
    input  wire                                 RXDATFLITPEND;
    input  wire                                 RXDATFLITV;
    input  wire [`CHIE_DAT_FLIT_RANGE]          RXDATFLIT;
    output wire                                 RXDATLCRDV;
    output wire                                 TXRSPFLITPEND;
    output wire                                 TXRSPFLITV;
    output wire [`CHIE_RSP_FLIT_RANGE]          TXRSPFLIT;
    input  wire                                 TXRSPLCRDV;
    output wire                                 TXDATFLITPEND;
    output wire                                 TXDATFLITV;
    output wire [`CHIE_DAT_FLIT_RANGE]          TXDATFLIT;
    input  wire                                 TXDATLCRDV;
    output wire                                 TXREQFLITPEND;
    output wire                                 TXREQFLITV;
    output wire [`CHIE_REQ_FLIT_RANGE]          TXREQFLIT;
    input  wire                                 TXREQLCRDV;

    // AXI interface0
    input  wire [`AXI4_AWID_WIDTH-1:0]          AWID0;
    input  wire [`AXI4_AWADDR_WIDTH-1:0]        AWADDR0;
    input  wire [`AXI4_AWLEN_WIDTH-1:0]         AWLEN0;
    input  wire [`AXI4_AWSIZE_WIDTH-1:0]        AWSIZE0;
    input  wire [`AXI4_AWBURST_WIDTH-1:0]       AWBURST0;
    input  wire [`AXI4_AWLOCK_WIDTH-1:0]        AWLOCK0;
    input  wire [`AXI4_AWCACHE_WIDTH-1:0]       AWCACHE0;
    input  wire [`AXI4_AWPROT_WIDTH-1:0]        AWPROT0;
    input  wire [`AXI4_AWQOS_WIDTH-1:0]         AWQOS0;
    input  wire [`AXI4_AWREGION_WIDTH-1:0]      AWREGION0;
    input  wire                                 AWVALID0;
    output wire                                 AWREADY0;
    input  wire [`AXI4_WDATA_WIDTH-1:0]         WDATA0;
    input  wire [`AXI4_WSTRB_WIDTH-1:0]         WSTRB0;
    input  wire [`AXI4_WLAST_WIDTH-1:0]         WLAST0;
    input  wire                                 WVALID0;
    output wire                                 WREADY0;
    output wire [`AXI4_BID_WIDTH-1:0]           BID0;
    output wire [`AXI4_BRESP_WIDTH-1:0]         BRESP0;
    output wire                                 BVALID0;
    input  wire                                 BREADY0;
    input  wire [`AXI4_ARID_WIDTH-1:0]          ARID0;
    input  wire [`AXI4_ARADDR_WIDTH-1:0]        ARADDR0;
    input  wire [`AXI4_ARLEN_WIDTH-1:0]         ARLEN0;
    input  wire [`AXI4_ARSIZE_WIDTH-1:0]        ARSIZE0;
    input  wire [`AXI4_ARBURST_WIDTH-1:0]       ARBURST0;
    input  wire [`AXI4_ARLOCK_WIDTH-1:0]        ARLOCK0;
    input  wire [`AXI4_ARCACHE_WIDTH-1:0]       ARCACHE0;
    input  wire [`AXI4_ARPROT_WIDTH-1:0]        ARPROT0;
    input  wire [`AXI4_ARQOS_WIDTH-1:0]         ARQOS0;
    input  wire [`AXI4_ARREGION_WIDTH-1:0]      ARREGION0;
    input  wire                                 ARVALID0;
    output wire                                 ARREADY0;
    output wire [`AXI4_RID_WIDTH-1:0]           RID0;
    output wire [`AXI4_RDATA_WIDTH-1:0]         RDATA0;
    output wire [`AXI4_RRESP_WIDTH-1:0]         RRESP0;
    output wire [`AXI4_RLAST_WIDTH-1:0]         RLAST0;
    output wire                                 RVALID0;
    input  wire                                 RREADY0;

    input  wire [POLICY_REQUESTER_WIDTH_PARAM-1:0] ARREQUESTER0;
    input  wire                                 ARNONSECURE0;
    input  wire                                 ARINTENTVALID0;
    input  wire                                 ARCOHINTENT0;
    input  wire [POLICY_REQUESTER_WIDTH_PARAM-1:0] AWREQUESTER0;
    input  wire                                 AWNONSECURE0;
    input  wire                                 AWINTENTVALID0;
    input  wire                                 AWCOHINTENT0;
    input  wire                                 POLICYCSRSECURE;
    input  wire                                 POLICYCSRWRITE;
    input  wire [(POLICY_REGION_COUNT_PARAM <= 1 ? 1 : $clog2(POLICY_REGION_COUNT_PARAM))-1:0] POLICYCSRINDEX;
    input  wire [AXI4_PA_WIDTH_PARAM-1:0]       POLICYCSRBASE;
    input  wire [AXI4_PA_WIDTH_PARAM-1:0]       POLICYCSRLIMIT;
    input  wire [POLICY_REQUESTER_WIDTH_PARAM-1:0] POLICYCSRREQUESTERVALUE;
    input  wire [POLICY_REQUESTER_WIDTH_PARAM-1:0] POLICYCSRREQUESTERMASK;
    input  wire [1:0]                           POLICYCSRALLOWEDPROFILES;
    input  wire                                 POLICYCSRDEFAULTCOHERENT;
    input  wire                                 POLICYCSRALLOWINTENT;
    input  wire                                 POLICYCSRNONSECUREONLY;
    input  wire                                 POLICYCSRLOCK;
    input  wire                                 POLICYCSRCOMMIT;
    input  wire                                 POLICYCSRSECURITYEVENTCLEAR;
    output wire                                 POLICYCSRLOCKED;
    output wire                                 POLICYCSRCOMMITBUSY;
    output wire                                 POLICYCSRCOMMITERROR;
    output wire                                 POLICYCSRSECURITYEVENT;
    output wire [7:0]                           POLICYEPOCH;

    // The legacy data buffers are functionally complete only for the default
    // 128-bit AXI / 256-bit CHI data plane.  Keep the broader parameter
    // contract visible in rni_scheme1_static_assert, but fail elaboration of
    // the real datapath instead of silently corrupting non-default traffic.
    initial begin
        if (AXI4_AXDATA_WIDTH_PARAM != 128)
            $fatal(1, "param_rni: functional AXI data width is currently limited to 128 bits");
        if (CHIE_DATA_WIDTH_PARAM != 256 || CHIE_BE_WIDTH_PARAM != 32)
            $fatal(1, "param_rni: functional CHI DAT/BE widths are currently limited to 256/32 bits");
        if (RNI_AR_ENTRIES_NUM_PARAM > (1 << (`CHIE_REQ_FLIT_TXNID_WIDTH - 2)) ||
            RNI_AW_ENTRIES_NUM_PARAM > (1 << (`CHIE_REQ_FLIT_TXNID_WIDTH - 2)))
            $fatal(1, "param_rni: entry count exceeds the Scheme-1 TxnID slot capacity");
    end

    // wire
    wire [`AXI4_AW_WIDTH-1:0]                   AW_CH_S0;
    wire [`AXI4_W_WIDTH-1:0]                    W_CH_S0;
    wire [`AXI4_B_WIDTH-1:0]                    B_CH_S0;
    wire [`AXI4_AR_WIDTH-1:0]                   AR_CH_S0;
    wire [`AXI4_R_WIDTH-1:0]                    R_CH_S0;
    wire                                        rxrspflitv_d1;
    wire [`CHIE_RSP_FLIT_WIDTH-1:0]             rxrspflit_d1_q;
    wire                                        rxdatflitv_d1;
    wire                                        rxdatflitv_d1_w;
    wire [`CHIE_DAT_FLIT_RANGE]                 rxdatflit_d1;
    wire [`CHIE_DAT_FLIT_TXNID_WIDTH-1:0]       rxdatflit_txnid_d1;
    wire [`CHIE_DAT_FLIT_DATAID_WIDTH-1:0]      rxdatflit_dataid_d1;
    wire                                        arctrl_rxdat_rb_v_d2;
    wire [`RNI_AR_ENTRIES_WIDTH-1:0]            arctrl_rxdat_rb_idx_d2;
    wire                                        rp_fifo_acpt_d4;
    wire                                        arctrl_rb_valid_d4;
    wire [`RNI_DMASK_CT_WIDTH-1:0]              arctrl_rb_ctmask_d4;
    wire                                        arctrl_rb_rlast_d4;
    wire [`AXI4_ARID_WIDTH-1:0]                 arctrl_rb_rid_d4;
    wire [`CHIE_DAT_FLIT_RESPERR_WIDTH-1:0]     arctrl_rdata_resperr_d4;
    wire [`RNI_AR_ENTRIES_WIDTH-1:0]            arctrl_rb_idx_d4;
    wire [`RNI_BC_WIDTH-1:0]                    arctrl_rb_bc_d4;
    wire [`CHIE_DAT_FLIT_WIDTH-1:0]             aw_txdatflit_s3;
    wire                                        aw_txdatflitv_s3;
    wire                                        aw_txdatflit_sent_s3;
    wire                                        pcrdgnt_pkt_v_d2;
    wire [`PCRDGRANT_PKT_WIDTH-1:0]             pcrdgnt_pkt_d2;
    wire [`CHIE_REQ_FLIT_WIDTH-1:0]             arctrl_txreqflit_s4;
    wire                                        arctrl_txreqflitv_s4;
    wire                                        arctrl_txreqflit_sent_s4;
    wire [`CHIE_RSP_FLIT_WIDTH-1:0]             aw_txrspflit_s0;
    wire                                        aw_txrspflitv_s0;
    wire                                        aw_txrspflit_sent_s0;
    wire [`CHIE_REQ_FLIT_WIDTH-1:0]             aw_txreqflit_s0;
    wire                                        aw_txreqflitv_s0;
    wire                                        aw_txreqflit_sent_s0;
    wire                                        arctrl_pcrdgnt_l_present_d3;
    wire                                        arctrl_pcrdgnt_h_present_d3;
    wire                                        aw_pcrdgnt_l_present_d3;
    wire                                        aw_pcrdgnt_h_present_d3;
    wire                                        ar_pcrdgnt_l_win_d3;
    wire                                        ar_pcrdgnt_h_win_d3;
    wire                                        aw_pcrdgnt_l_win_d3;
    wire                                        aw_pcrdgnt_h_win_d3;
    wire [`CHIE_RSP_FLIT_WIDTH-1:0]             awctrl_txrspflit_d0;
    wire                                        awctrl_txrspflitv_d0;
    wire                                        awctrl_txrspflit_sent_d0;
    wire [`CHIE_REQ_FLIT_WIDTH-1:0]             awctrl_txreqflit_s4;
    wire                                        awctrl_txreqflitv_s4;
    wire                                        awctrl_txreqflit_sent_s4;
    wire                                        awctrl_alloc_valid_s2;
    wire [RNI_AW_ENTRIES_NUM_PARAM-1:0]         awctrl_alloc_entry_s2;
    wire [`RNI_DMASK_CT_WIDTH-1:0]              awctrl_ctmask_s2;
    wire [`RNI_DMASK_PD_WIDTH-1:0]              awctrl_pdmask_s2;
    wire [`RNI_BCVEC_WIDTH-1:0]                 awctrl_bc_vec_s2;
    wire [RNI_AW_ENTRIES_NUM_PARAM-1:0]         awctrl_dealloc_entry;
    wire                                        wb_req_fifo_pfull_d1;
    wire                                        wb_req_done_d3;
    wire [RNI_AW_ENTRIES_NUM_PARAM-1:0]         wb_req_entry_d3;
    wire                                        wb_not_busy_d1;
    wire                                        awctrl_txdat_rdy_v_d2;
    wire [RNI_AW_ENTRIES_NUM_PARAM-1:0]         awctrl_txdat_rdy_entry_d2;
    wire [`CHIE_DAT_FLIT_QOS_WIDTH-1:0]         awctrl_txdat_qos_d2;
    wire                                        awctrl_txdat_compack_d2;
    wire [`CHIE_DAT_FLIT_DBID_WIDTH-1:0]        awctrl_txdat_dbid_d2;
    wire [`CHIE_DAT_FLIT_DBID_WIDTH-1:0]        awctrl_txdat_original_txnid_d2;
    wire [`CHIE_DAT_FLIT_TGTID_WIDTH-1:0]       awctrl_txdat_tgtid_d2;
    wire [`CHIE_DAT_FLIT_CCID_WIDTH-1:0]        awctrl_txdat_ccid_d2;
    wire [`RNI_DMASK_CT_WIDTH-1:0]              awctrl_txdat_ctmask_d2;
    wire                                        awctrl_txdat_not_busy_d2;
    wire                                        awctrl_brsp_fifo_pop_d3;
    wire                                        awctrl_brsp_rdy_v_d2;
    wire                                        awctrl_brsp_last_v_d2;
    wire [`AXI4_BID_WIDTH-1:0]                  awctrl_brsp_axid_d2;
    wire [`CHIE_RSP_FLIT_RESPERR_WIDTH-1:0]     awctrl_brsp_resperr_d2;
    wire [`CHIE_DAT_FLIT_WIDTH-1:0]             wb_txdatflit_d3;
    wire                                        wb_txdatflitv_d3;
    wire                                        wb_txdatflit_sent_d3;
    wire                                        arready_core;
    wire                                        awready_core;
    wire                                        arvalid_core;
    wire                                        awvalid_core;
    wire                                        ar_policy_allow;
    wire                                        ar_profile_coherent;
    wire                                        aw_policy_allow;
    wire                                        aw_profile_coherent;
    wire                                        admission_block;
    wire                                        ar_outstanding;
    wire                                        aw_outstanding;
    wire                                        outstanding_empty;
    wire                                        line_hazard_empty;
    wire                                        line_hazard_acquire_ready;
    wire                                        line_hazard_select_ar;
    wire                                        ar_hazard_ready;
    wire                                        aw_hazard_ready;
    wire                                        line_hazard_acquire_valid;
    wire                                        line_hazard_release_valid;
    wire [AXI4_PA_WIDTH_PARAM-1:0]               line_hazard_acquire_addr;
    wire [`AXI4_ARID_WIDTH:0]                    line_hazard_acquire_owner;
    wire [`AXI4_ARID_WIDTH:0]                    line_hazard_release_owner;
    wire                                        line_hazard_acquire_profile;

    assign outstanding_empty = ~ar_outstanding & ~aw_outstanding & line_hazard_empty;
    // A request is visible to a legacy controller only in the cycle in which
    // the policy gate accepts it; profile/epoch are then captured in ar/awlink.
    assign line_hazard_select_ar = ARVALID0 & ar_policy_allow;
    assign ar_hazard_ready = !ARVALID0 || (line_hazard_select_ar &&
                                            line_hazard_acquire_ready);
    assign aw_hazard_ready = !AWVALID0 || (!line_hazard_select_ar &&
                                            line_hazard_acquire_ready);
    assign ARREADY0 = arready_core & (~ARVALID0 | (ar_policy_allow & ar_hazard_ready));
    assign AWREADY0 = awready_core & (~AWVALID0 | (aw_policy_allow & aw_hazard_ready));
    assign arvalid_core = ARVALID0 & ARREADY0;
    assign awvalid_core = AWVALID0 & AWREADY0;
    assign line_hazard_acquire_valid = arvalid_core | awvalid_core;
    assign line_hazard_acquire_addr = line_hazard_select_ar ? ARADDR0 : AWADDR0;
    assign line_hazard_acquire_profile = line_hazard_select_ar ?
        ar_profile_coherent : aw_profile_coherent;
    assign line_hazard_acquire_owner = line_hazard_select_ar ?
        {1'b0, ARID0} : {1'b1, AWID0};
    assign line_hazard_release_valid = (RVALID0 & RREADY0 & RLAST0) |
        (BVALID0 & BREADY0);
    assign line_hazard_release_owner = (RVALID0 & RREADY0 & RLAST0) ?
        {1'b0, RID0} : {1'b1, BID0};

    // A token is acquired at AR/AW acceptance and retained until the final
    // AXI response handshake.  This serializes conflicting profiles on a
    // line across the whole parent lifetime, including AW/WCOLLECT.
    rni_line_hazard #(
        .ADDR_WIDTH(AXI4_PA_WIDTH_PARAM),
        .OWNER_WIDTH(`AXI4_ARID_WIDTH + 1),
        .ENTRIES(LINE_HAZARD_ENTRIES_PARAM)
    ) rni_line_hazard_inst (
        .clk_i(CLK), .rst_i(RST),
        .acquire_valid_i(line_hazard_acquire_valid),
        .acquire_addr_i(line_hazard_acquire_addr),
        .acquire_profile_i(line_hazard_acquire_profile),
        .acquire_owner_i(line_hazard_acquire_owner),
        .acquire_ready_o(line_hazard_acquire_ready),
        .release_valid_i(line_hazard_release_valid),
        .release_owner_i(line_hazard_release_owner),
        .empty_o(line_hazard_empty)
    );

    rni_policy_csr #(
        .ADDR_WIDTH(AXI4_PA_WIDTH_PARAM),
        .REGION_COUNT(POLICY_REGION_COUNT_PARAM),
        .REQUESTER_WIDTH(POLICY_REQUESTER_WIDTH_PARAM),
        .ENABLE_POLICY_CSR(ENABLE_POLICY_CSR_PARAM),
        .ENABLE_NONCOHERENT(ENABLE_NONCOHERENT_PARAM),
        .ENABLE_COHERENT_REQ(ENABLE_COHERENT_REQ_PARAM),
        .DEFAULT_COHERENT(DEFAULT_COHERENT_PARAM)
    ) rni_policy_csr_inst (
        .clk_i(CLK), .rst_i(RST), .outstanding_empty_i(outstanding_empty),
        .csr_secure_i(POLICYCSRSECURE), .csr_write_i(POLICYCSRWRITE),
        .csr_index_i(POLICYCSRINDEX), .csr_base_i(POLICYCSRBASE),
        .csr_limit_i(POLICYCSRLIMIT),
        .csr_requester_value_i(POLICYCSRREQUESTERVALUE),
        .csr_requester_mask_i(POLICYCSRREQUESTERMASK),
        .csr_allowed_profiles_i(POLICYCSRALLOWEDPROFILES),
        .csr_default_coherent_i(POLICYCSRDEFAULTCOHERENT),
        .csr_allow_intent_i(POLICYCSRALLOWINTENT),
        .csr_ns_only_i(POLICYCSRNONSECUREONLY), .csr_lock_i(POLICYCSRLOCK),
        .csr_commit_i(POLICYCSRCOMMIT),
        .csr_security_event_clear_i(POLICYCSRSECURITYEVENTCLEAR),
        .csr_locked_o(POLICYCSRLOCKED), .csr_commit_busy_o(POLICYCSRCOMMITBUSY),
        .csr_commit_error_o(POLICYCSRCOMMITERROR),
        .security_event_o(POLICYCSRSECURITYEVENT),
        .admission_block_o(admission_block), .policy_epoch_o(POLICYEPOCH),
        .ar_query_valid_i(ARVALID0), .ar_addr_i(ARADDR0),
        .ar_requester_i(ARREQUESTER0), .ar_nonsecure_i(ARNONSECURE0),
        .ar_intent_valid_i(ARINTENTVALID0), .ar_coherent_intent_i(ARCOHINTENT0),
        .ar_allow_o(ar_policy_allow), .ar_profile_coherent_o(ar_profile_coherent),
        .aw_query_valid_i(AWVALID0), .aw_addr_i(AWADDR0),
        .aw_requester_i(AWREQUESTER0), .aw_nonsecure_i(AWNONSECURE0),
        .aw_intent_valid_i(AWINTENTVALID0), .aw_coherent_intent_i(AWCOHINTENT0),
        .aw_allow_o(aw_policy_allow), .aw_profile_coherent_o(aw_profile_coherent)
    );

    rni_axi_bus `RNI_PARAM_INST
                rni_axi_bus_inst(
                    // AW Channel0
                    .AWID0                                 ( AWID0                         )
                    ,.AWADDR0                               ( AWADDR0                       )
                    ,.AWLEN0                                ( AWLEN0                        )
                    ,.AWSIZE0                               ( AWSIZE0                       )
                    ,.AWBURST0                              ( AWBURST0                      )
                    ,.AWLOCK0                               ( AWLOCK0                       )
                    ,.AWCACHE0                              ( AWCACHE0                      )
                    ,.AWPROT0                               ( AWPROT0                       )
                    ,.AWQOS0                                ( AWQOS0                        )
                    ,.AWREGION0                             ( AWREGION0                     )
                    ,.AW_CH_S0                              ( AW_CH_S0                      )

                    // W Channel0
                    ,.WDATA0                                ( WDATA0                        )
                    ,.WSTRB0                                ( WSTRB0                        )
                    ,.WLAST0                                ( WLAST0                        )
                    ,.W_CH_S0                               ( W_CH_S0                       )

                    // B Channel0
                    ,.BID0                                  ( BID0                          )
                    ,.BRESP0                                ( BRESP0                        )
                    ,.B_CH_S0                               ( B_CH_S0                       )

                    // AR Channel0
                    ,.ARID0                                 ( ARID0                         )
                    ,.ARADDR0                               ( ARADDR0                       )
                    ,.ARLEN0                                ( ARLEN0                        )
                    ,.ARSIZE0                               ( ARSIZE0                       )
                    ,.ARBURST0                              ( ARBURST0                      )
                    ,.ARLOCK0                               ( ARLOCK0                       )
                    ,.ARCACHE0                              ( ARCACHE0                      )
                    ,.ARPROT0                               ( ARPROT0                       )
                    ,.ARQOS0                                ( ARQOS0                        )
                    ,.ARREGION0                             ( ARREGION0                     )
                    ,.AR_CH_S0                              ( AR_CH_S0                      )

                    // R Channel0
                    ,.RID0                                  ( RID0                          )
                    ,.RDATA0                                ( RDATA0                        )
                    ,.RRESP0                                ( RRESP0                        )
                    ,.RLAST0                                ( RLAST0                        )
                    ,.R_CH_S0                               ( R_CH_S0                       )
                );

    rni_rd_buffer `RNI_PARAM_INST
                  rni_rd_buffer_inst(
                      // global inputs
                      .clk_i                                 ( CLK                           )
                      ,.rst_i                                 ( RST                           )
                      ,.rxdatflitv_d1_i                       ( rxdatflitv_d1                 )
                      ,.rxdatflit_d1_i                        ( rxdatflit_d1                  )
                      ,.rxdatflitv_d1_o                       ( rxdatflitv_d1_w               )
                      ,.rxdatflit_txnid_d1_o                  ( rxdatflit_txnid_d1            )
                      ,.rxdatflit_dataid_d1_o                 ( rxdatflit_dataid_d1           )
                      ,.rp_fifo_acpt_d4_o                     ( rp_fifo_acpt_d4               )
                      ,.arctrl_rb_valid_d4_i                  ( arctrl_rb_valid_d4            )
                      ,.arctrl_rb_idx_d4_i                    ( arctrl_rb_idx_d4              )
                      ,.arctrl_rb_ctmask_d4_i                 ( arctrl_rb_ctmask_d4           )
                      ,.arctrl_rb_rlast_d4_i                  ( arctrl_rb_rlast_d4            )
                      ,.arctrl_rb_rid_d4_i                    ( arctrl_rb_rid_d4              )
                      ,.arctrl_rb_bc_d4_i                     ( arctrl_rb_bc_d4               )
                      ,.R_CH_S0                               ( R_CH_S0                       )
                      ,.RVALID0                               ( RVALID0                       )
                      ,.RREADY0                               ( RREADY0                       )
                  );

    rni_arctrl `RNI_PARAM_INST
               rni_arctrl_inst(
                   // global inputs
                   .clk_i                                 ( CLK                           )
                   ,.rst_i                                 ( RST                           )
                   ,.AR_CH_S0                              ( AR_CH_S0                      )
                   ,.ARVALID0                              ( arvalid_core                  )
                   ,.ARREADY0                              ( arready_core                  )
                   ,.ar_profile_coherent_i                 ( ar_profile_coherent            )
                   ,.ar_policy_epoch_i                     ( POLICYEPOCH                    )
                   ,.ar_outstanding_o                      ( ar_outstanding                 )
                   ,.arctrl_txreqflitv_s4_o                ( arctrl_txreqflitv_s4          )
                   ,.arctrl_txreqflit_s4_o                 ( arctrl_txreqflit_s4           )
                   ,.arctrl_txreqflit_sent_s4_i            ( arctrl_txreqflit_sent_s4      )
                   ,.rxrspflitv_d1_i                       ( rxrspflitv_d1                 )
                   ,.rxrspflit_d1_i                        ( rxrspflit_d1_q                )
                   ,.rxdatflitv_d1_i                       ( rxdatflitv_d1_w               )
                   ,.rxdatflit_txnid_d1_i                  ( rxdatflit_txnid_d1            )
                   ,.rxdatflit_dataid_d1_i                 ( rxdatflit_dataid_d1           )
                   ,.rp_fifo_acpt_d4_i                     ( rp_fifo_acpt_d4               )
                   ,.arctrl_rb_valid_d4_o                  ( arctrl_rb_valid_d4            )
                   ,.arctrl_rb_ctmask_d4_o                 ( arctrl_rb_ctmask_d4           )
                   ,.arctrl_rb_rlast_d4_o                  ( arctrl_rb_rlast_d4            )
                   ,.arctrl_rb_rid_d4_o                    ( arctrl_rb_rid_d4              )
                   ,.arctrl_rb_idx_d4_o                    ( arctrl_rb_idx_d4              )
                   ,.arctrl_rb_bc_d4_o                     ( arctrl_rb_bc_d4               )
                   ,.pcrdgnt_pkt_v_d2_i                    ( pcrdgnt_pkt_v_d2              )
                   ,.pcrdgnt_pkt_d2_i                      ( pcrdgnt_pkt_d2                )
                   ,.arctrl_pcrdgnt_h_present_d3_o         ( arctrl_pcrdgnt_h_present_d3   )
                   ,.arctrl_pcrdgnt_l_present_d3_o         ( arctrl_pcrdgnt_l_present_d3   )
                   ,.ar_pcrdgnt_h_win_d3_i                 ( ar_pcrdgnt_h_win_d3           )
                   ,.ar_pcrdgnt_l_win_d3_i                 ( ar_pcrdgnt_l_win_d3           )
               );

    rni_misc `RNI_PARAM_INST
             rni_misc_inst(
                 // global inputs
                 .clk_i                                 ( CLK                           )
                 ,.rst_i                                 ( RST                           )

                 // rni_link_ctl Interface
                 ,.rxrspflitv_d1_i                       ( rxrspflitv_d1                 )
                 ,.rxrspflit_d1_q_i                      ( rxrspflit_d1_q                )

                 // rni_awctrl Interface
                 ,.pcrdgnt_pkt_v_d2_o                    ( pcrdgnt_pkt_v_d2              )
                 ,.pcrdgnt_pkt_d2_o                      ( pcrdgnt_pkt_d2                )
                 ,.ar_pcrdgnt_l_present_d3_i             ( arctrl_pcrdgnt_l_present_d3   )
                 ,.ar_pcrdgnt_h_present_d3_i             ( arctrl_pcrdgnt_h_present_d3   )
                 ,.aw_pcrdgnt_l_present_d3_i             ( aw_pcrdgnt_l_present_d3       )
                 ,.aw_pcrdgnt_h_present_d3_i             ( aw_pcrdgnt_h_present_d3       )
                 ,.ar_pcrdgnt_l_win_d3_o                 ( ar_pcrdgnt_l_win_d3           )
                 ,.ar_pcrdgnt_h_win_d3_o                 ( ar_pcrdgnt_h_win_d3           )
                 ,.aw_pcrdgnt_l_win_d3_o                 ( aw_pcrdgnt_l_win_d3           )
                 ,.aw_pcrdgnt_h_win_d3_o                 ( aw_pcrdgnt_h_win_d3           )
             );

    rni_awctrl `RNI_PARAM_INST
               rni_awctrl_inst(
                   // global inputs
                   .clk_i                                 ( CLK                           )
                   ,.rst_i                                 ( RST                           )
                   ,.awctrl_txrspflit_d0_o                 ( awctrl_txrspflit_d0           )
                   ,.awctrl_txrspflitv_d0_o                ( awctrl_txrspflitv_d0          )
                   ,.awctrl_txrspflit_sent_d0_i            ( awctrl_txrspflit_sent_d0      )
                   ,.awctrl_txreqflit_s4_o                 ( awctrl_txreqflit_s4           )
                   ,.awctrl_txreqflitv_s4_o                ( awctrl_txreqflitv_s4          )
                   ,.awctrl_txreqflit_sent_s4_i            ( awctrl_txreqflit_sent_s4      )
                   ,.awctrl_rxrspflitv_d1_i                ( rxrspflitv_d1                 )
                   ,.awctrl_rxrspflit_d1_i                 ( rxrspflit_d1_q                )
                   ,.AWVALID0                              ( awvalid_core                  )
                   ,.AW_CH_S0                              ( AW_CH_S0                      )
                   ,.AWREADY0                              ( awready_core                  )
                   ,.aw_profile_coherent_i                 ( aw_profile_coherent            )
                   ,.aw_policy_epoch_i                     ( POLICYEPOCH                    )
                   ,.aw_outstanding_o                      ( aw_outstanding                 )
                   ,.pcrdgnt_pkt_v_d2_i                    ( pcrdgnt_pkt_v_d2              )
                   ,.pcrdgnt_pkt_d2_i                      ( pcrdgnt_pkt_d2                )
                   ,.awctrl_pcrdgnt_h_present_d3_o         ( aw_pcrdgnt_h_present_d3       )
                   ,.awctrl_pcrdgnt_l_present_d3_o         ( aw_pcrdgnt_l_present_d3       )
                   ,.awctrl_pcrdgnt_h_win_d3_i             ( aw_pcrdgnt_h_win_d3           )
                   ,.awctrl_pcrdgnt_l_win_d3_i             ( aw_pcrdgnt_l_win_d3           )
                   ,.awctrl_alloc_valid_s2_o               ( awctrl_alloc_valid_s2         )
                   ,.awctrl_alloc_entry_s2_o               ( awctrl_alloc_entry_s2         )
                   ,.awctrl_ctmask_s2_o                    ( awctrl_ctmask_s2              )
                   ,.awctrl_pdmask_s2_o                    ( awctrl_pdmask_s2              )
                   ,.awctrl_bc_vec_s2_o                    ( awctrl_bc_vec_s2              )
                   ,.awctrl_dealloc_entry_o                ( awctrl_dealloc_entry          )
                   ,.wb_req_fifo_pfull_d1_i                ( wb_req_fifo_pfull_d1          )
                   ,.wb_req_done_d3_i                      ( wb_req_done_d3                )
                   ,.wb_req_entry_d3_i                     ( wb_req_entry_d3               )
                   ,.wb_not_busy_d1_i                      ( wb_not_busy_d1                )
                   ,.awctrl_txdat_rdy_v_d2_o               ( awctrl_txdat_rdy_v_d2         )
                   ,.awctrl_txdat_rdy_entry_d2_o           ( awctrl_txdat_rdy_entry_d2     )
                   ,.awctrl_txdat_qos_d2_o                 ( awctrl_txdat_qos_d2           )
                   ,.awctrl_txdat_compack_d2_o             ( awctrl_txdat_compack_d2       )
                   ,.awctrl_txdat_dbid_d2_o                ( awctrl_txdat_dbid_d2          )
                   ,.awctrl_txdat_original_txnid_d2_o       ( awctrl_txdat_original_txnid_d2 )
                   ,.awctrl_txdat_tgtid_d2_o               ( awctrl_txdat_tgtid_d2         )
                   ,.awctrl_txdat_ccid_d2_o                ( awctrl_txdat_ccid_d2          )
                   ,.awctrl_txdat_ctmask_d2_o              ( awctrl_txdat_ctmask_d2        )
                   ,.awctrl_txdat_not_busy_d2_i            ( awctrl_txdat_not_busy_d2      )
                   ,.awctrl_txdat_sent_d3_i                ( wb_txdatflit_sent_d3          )
                   ,.awctrl_brsp_fifo_pop_d3_i             ( awctrl_brsp_fifo_pop_d3       )
                   ,.awctrl_brsp_rdy_v_d2_o                ( awctrl_brsp_rdy_v_d2          )
                   ,.awctrl_brsp_last_v_d2_o               ( awctrl_brsp_last_v_d2         )
                   ,.awctrl_brsp_axid_d2_o                 ( awctrl_brsp_axid_d2           )
                   ,.awctrl_brsp_resperr_d2_o              ( awctrl_brsp_resperr_d2        )
               );

    rni_wr_buffer `RNI_PARAM_INST
                  rni_wr_buffer_inst(
                      // global inputs
                      .clk_i                                 ( CLK                           )
                      ,.rst_i                                 ( RST                           )
                      ,.aw_alloc_valid_s2_i                   ( awctrl_alloc_valid_s2         )
                      ,.aw_alloc_entry_s2_i                   ( awctrl_alloc_entry_s2         )
                      ,.aw_ctmask_s2_i                        ( awctrl_ctmask_s2              )
                      ,.aw_pdmask_s2_i                        ( awctrl_pdmask_s2              )
                      ,.aw_bc_vec_s2_i                        ( awctrl_bc_vec_s2              )
                      ,.awctrl_dealloc_entry_i                ( awctrl_dealloc_entry          )
                      ,.wb_req_fifo_pfull_d1_o                ( wb_req_fifo_pfull_d1          )
                      ,.wb_req_done_d3_o                      ( wb_req_done_d3                )
                      ,.wb_req_entry_d3_o                     ( wb_req_entry_d3               )
                      ,.wb_not_busy_d1_o                      ( wb_not_busy_d1                )
                      ,.txdat_rdy_v_d2_q_i                    ( awctrl_txdat_rdy_v_d2         )
                      ,.txdat_rdy_entry_d2_q_i                ( awctrl_txdat_rdy_entry_d2     )
                      ,.txdat_qos_d2_i                        ( awctrl_txdat_qos_d2           )
                      ,.txdat_compack_d2_i                    ( awctrl_txdat_compack_d2       )
                      ,.txdat_dbid_d2_i                       ( awctrl_txdat_dbid_d2          )
                      ,.txdat_original_txnid_d2_i             ( awctrl_txdat_original_txnid_d2 )
                      ,.txdat_tgtid_d2_i                      ( awctrl_txdat_tgtid_d2         )
                      ,.txdat_ccid_d2_i                       ( awctrl_txdat_ccid_d2          )
                      ,.txdat_ctmask_d2_q_i                   ( awctrl_txdat_ctmask_d2        )
                      ,.wb_txdat_not_busy_d2_o                ( awctrl_txdat_not_busy_d2      )
                      ,.wb_brsp_fifo_pop_d3_o                 ( awctrl_brsp_fifo_pop_d3       )
                      ,.brsp_rdy_v_d2_i                       ( awctrl_brsp_rdy_v_d2          )
                      ,.brsp_last_v_d2_q_i                    ( awctrl_brsp_last_v_d2         )
                      ,.brsp_axid_d2_i                        ( awctrl_brsp_axid_d2           )
                      ,.brsp_resperr_d2_i                     ( awctrl_brsp_resperr_d2        )
                      ,.W_CH_S0                               ( W_CH_S0                       )
                      ,.WVALID0                               ( WVALID0                       )
                      ,.WREADY0                               ( WREADY0                       )
                      ,.B_CH_S0                               ( B_CH_S0                       )
                      ,.BVALID0                               ( BVALID0                       )
                      ,.BREADY0                               ( BREADY0                       )
                      ,.wb_txdatflit_d3_o                     ( wb_txdatflit_d3               )
                      ,.wb_txdatflitv_d3_o                    ( wb_txdatflitv_d3              )
                      ,.wb_txdatflit_sent_d3_i                ( wb_txdatflit_sent_d3          )
                  );

    rni_link_ctl `RNI_PARAM_INST
                 rni_link_ctl_inst(
                     // global inputs
                     .clk_i                                 ( CLK                           )
                     ,.rst_i                                 ( RST                           )

                     // link handshake
                     ,.TXLINKACTIVEREQ                       ( TXLINKACTIVEREQ               )
                     ,.TXLINKACTIVEACK                       ( TXLINKACTIVEACK               )
                     ,.RXLINKACTIVEREQ                       ( RXLINKACTIVEREQ               )
                     ,.RXLINKACTIVEACK                       ( RXLINKACTIVEACK               )

                     // CHI Interface
                     ,.RXRSPFLITPEND                         ( RXRSPFLITPEND                 )
                     ,.RXRSPFLITV                            ( RXRSPFLITV                    )
                     ,.RXRSPFLIT                             ( RXRSPFLIT                     )
                     ,.RXRSPLCRDV                            ( RXRSPLCRDV                    )
                     ,.RXDATFLITPEND                         ( RXDATFLITPEND                 )
                     ,.RXDATFLITV                            ( RXDATFLITV                    )
                     ,.RXDATFLIT                             ( RXDATFLIT                     )
                     ,.RXDATLCRDV                            ( RXDATLCRDV                    )
                     ,.TXDATFLITPEND                         ( TXDATFLITPEND                 )
                     ,.TXDATFLITV                            ( TXDATFLITV                    )
                     ,.TXDATFLIT                             ( TXDATFLIT                     )
                     ,.TXDATLCRDV                            ( TXDATLCRDV                    )
                     ,.TXRSPFLITPEND                         ( TXRSPFLITPEND                 )
                     ,.TXRSPFLITV                            ( TXRSPFLITV                    )
                     ,.TXRSPFLIT                             ( TXRSPFLIT                     )
                     ,.TXRSPLCRDV                            ( TXRSPLCRDV                    )
                     ,.TXREQFLITPEND                         ( TXREQFLITPEND                 )
                     ,.TXREQFLITV                            ( TXREQFLITV                    )
                     ,.TXREQFLIT                             ( TXREQFLIT                     )
                     ,.TXREQLCRDV                            ( TXREQLCRDV                    )

                     // input from rni_wr_buffer
                     ,.wb_txdatflit_d3_i                     ( wb_txdatflit_d3               )
                     ,.wb_txdatflitv_d3_i                    ( wb_txdatflitv_d3              )
                     ,.wb_txdatflit_sent_d3_o                ( wb_txdatflit_sent_d3          )

                     // input from rni_arctrl
                     ,.ar_txreqflit_s4_i                     ( arctrl_txreqflit_s4           )
                     ,.ar_txreqflitv_s4_i                    ( arctrl_txreqflitv_s4          )
                     ,.ar_txreqflit_sent_s4_o                ( arctrl_txreqflit_sent_s4      )

                     // input from rni_awctrl
                     ,.aw_txrspflit_d0_i                     ( awctrl_txrspflit_d0           )
                     ,.aw_txrspflitv_d0_i                    ( awctrl_txrspflitv_d0          )
                     ,.aw_txrspflit_sent_d0_o                ( awctrl_txrspflit_sent_d0      )
                     ,.aw_txreqflit_s4_i                     ( awctrl_txreqflit_s4           )
                     ,.aw_txreqflitv_s4_i                    ( awctrl_txreqflitv_s4          )
                     ,.aw_txreqflit_sent_s4_o                ( awctrl_txreqflit_sent_s4      )

                     // outputs to rni_arctrl/rni_awctrl/rni_rd_buffer/rni_misc
                     ,.rxrspflitv_d1_o                       ( rxrspflitv_d1                 )
                     ,.rxrspflit_d1_q_o                      ( rxrspflit_d1_q                )
                     ,.rxdatflitv_d1_o                       ( rxdatflitv_d1                 )
                     ,.rxdatflit_d1_q_o                      ( rxdatflit_d1                  )
                 );
endmodule
