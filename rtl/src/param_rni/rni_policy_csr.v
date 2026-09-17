// Scheme-1 secure region policy table.
// Shadow updates are committed atomically after all admitted work, including
// AW transactions still collecting W data, has drained.
module rni_policy_csr #(
    parameter integer ADDR_WIDTH = 44,
    parameter integer REGION_COUNT = 4,
    parameter integer REQUESTER_WIDTH = 8,
    parameter integer INDEX_WIDTH = (REGION_COUNT <= 1) ? 1 : $clog2(REGION_COUNT),
    parameter integer ENABLE_POLICY_CSR = 0,
    parameter integer ENABLE_NONCOHERENT = 1,
    parameter integer ENABLE_COHERENT_REQ = 1,
    parameter integer DEFAULT_COHERENT = 0
) (
    input  wire clk_i,
    input  wire rst_i,
    input  wire outstanding_empty_i,

    input  wire csr_secure_i,
    input  wire csr_write_i,
    input  wire [INDEX_WIDTH-1:0] csr_index_i,
    input  wire [ADDR_WIDTH-1:0] csr_base_i,
    input  wire [ADDR_WIDTH-1:0] csr_limit_i,
    input  wire [REQUESTER_WIDTH-1:0] csr_requester_value_i,
    input  wire [REQUESTER_WIDTH-1:0] csr_requester_mask_i,
    input  wire [1:0] csr_allowed_profiles_i,
    input  wire csr_default_coherent_i,
    input  wire csr_allow_intent_i,
    input  wire csr_ns_only_i,
    input  wire csr_lock_i,
    input  wire csr_commit_i,
    input  wire csr_security_event_clear_i,
    output reg  csr_locked_o,
    output reg  csr_commit_busy_o,
    output reg  csr_commit_error_o,
    output reg  security_event_o,
    output reg  admission_block_o,
    output reg  [7:0] policy_epoch_o,

    input  wire ar_query_valid_i,
    input  wire [ADDR_WIDTH-1:0] ar_addr_i,
    input  wire [REQUESTER_WIDTH-1:0] ar_requester_i,
    input  wire ar_nonsecure_i,
    input  wire ar_intent_valid_i,
    input  wire ar_coherent_intent_i,
    output reg  ar_allow_o,
    output reg  ar_profile_coherent_o,

    input  wire aw_query_valid_i,
    input  wire [ADDR_WIDTH-1:0] aw_addr_i,
    input  wire [REQUESTER_WIDTH-1:0] aw_requester_i,
    input  wire aw_nonsecure_i,
    input  wire aw_intent_valid_i,
    input  wire aw_coherent_intent_i,
    output reg  aw_allow_o,
    output reg  aw_profile_coherent_o
);
    reg [ADDR_WIDTH-1:0] shadow_base [0:REGION_COUNT-1];
    reg [ADDR_WIDTH-1:0] shadow_limit [0:REGION_COUNT-1];
    reg [REQUESTER_WIDTH-1:0] shadow_requester_value [0:REGION_COUNT-1];
    reg [REQUESTER_WIDTH-1:0] shadow_requester_mask [0:REGION_COUNT-1];
    reg [1:0] shadow_allowed_profiles [0:REGION_COUNT-1];
    reg shadow_default_coherent [0:REGION_COUNT-1];
    reg shadow_allow_intent [0:REGION_COUNT-1];
    reg shadow_ns_only [0:REGION_COUNT-1];

    reg [ADDR_WIDTH-1:0] active_base [0:REGION_COUNT-1];
    reg [ADDR_WIDTH-1:0] active_limit [0:REGION_COUNT-1];
    reg [REQUESTER_WIDTH-1:0] active_requester_value [0:REGION_COUNT-1];
    reg [REQUESTER_WIDTH-1:0] active_requester_mask [0:REGION_COUNT-1];
    reg [1:0] active_allowed_profiles [0:REGION_COUNT-1];
    reg active_default_coherent [0:REGION_COUNT-1];
    reg active_allow_intent [0:REGION_COUNT-1];
    reg active_ns_only [0:REGION_COUNT-1];
    reg commit_pending_q;
    reg shadow_invalid;
    integer i;
    integer j;

    always @* begin
        shadow_invalid = 1'b0;
        for (i = 0; i < REGION_COUNT; i = i + 1) begin
            if ((shadow_allowed_profiles[i] != 2'b00) &&
                (shadow_limit[i] <= shadow_base[i]))
                shadow_invalid = 1'b1;
            for (j = i + 1; j < REGION_COUNT; j = j + 1)
                if ((shadow_allowed_profiles[i] != 2'b00) &&
                    (shadow_allowed_profiles[j] != 2'b00) &&
                    (shadow_base[i] < shadow_limit[j]) &&
                    (shadow_base[j] < shadow_limit[i]))
                    shadow_invalid = 1'b1;
        end
    end

    always @* begin
        ar_allow_o = 1'b0;
        ar_profile_coherent_o = DEFAULT_COHERENT;
        if (!ENABLE_POLICY_CSR) begin
            ar_allow_o = ar_query_valid_i && !admission_block_o &&
                (DEFAULT_COHERENT ? ENABLE_COHERENT_REQ : ENABLE_NONCOHERENT);
        end
        for (i = 0; i < REGION_COUNT; i = i + 1) begin
            if (ENABLE_POLICY_CSR && !ar_allow_o && ar_query_valid_i && !admission_block_o &&
                (active_allowed_profiles[i] != 2'b00) &&
                (ar_addr_i >= active_base[i]) && (ar_addr_i < active_limit[i]) &&
                ((ar_requester_i & active_requester_mask[i]) ==
                 (active_requester_value[i] & active_requester_mask[i])) &&
                (!active_ns_only[i] || ar_nonsecure_i)) begin
                ar_profile_coherent_o =
                    (ar_intent_valid_i && active_allow_intent[i]) ?
                    ar_coherent_intent_i : active_default_coherent[i];
                ar_allow_o = ar_profile_coherent_o ?
                    active_allowed_profiles[i][1] : active_allowed_profiles[i][0];
            end
        end
    end

    always @* begin
        aw_allow_o = 1'b0;
        aw_profile_coherent_o = DEFAULT_COHERENT;
        if (!ENABLE_POLICY_CSR) begin
            aw_allow_o = aw_query_valid_i && !admission_block_o &&
                (DEFAULT_COHERENT ? ENABLE_COHERENT_REQ : ENABLE_NONCOHERENT);
        end
        for (i = 0; i < REGION_COUNT; i = i + 1) begin
            if (ENABLE_POLICY_CSR && !aw_allow_o && aw_query_valid_i && !admission_block_o &&
                (active_allowed_profiles[i] != 2'b00) &&
                (aw_addr_i >= active_base[i]) && (aw_addr_i < active_limit[i]) &&
                ((aw_requester_i & active_requester_mask[i]) ==
                 (active_requester_value[i] & active_requester_mask[i])) &&
                (!active_ns_only[i] || aw_nonsecure_i)) begin
                aw_profile_coherent_o =
                    (aw_intent_valid_i && active_allow_intent[i]) ?
                    aw_coherent_intent_i : active_default_coherent[i];
                aw_allow_o = aw_profile_coherent_o ?
                    active_allowed_profiles[i][1] : active_allowed_profiles[i][0];
            end
        end
    end

    always @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            csr_locked_o <= 1'b0;
            csr_commit_busy_o <= 1'b0;
            csr_commit_error_o <= 1'b0;
            security_event_o <= 1'b0;
            admission_block_o <= 1'b0;
            policy_epoch_o <= 8'b0;
            commit_pending_q <= 1'b0;
            for (i = 0; i < REGION_COUNT; i = i + 1) begin
                shadow_base[i] <= {ADDR_WIDTH{1'b0}};
                shadow_limit[i] <= {ADDR_WIDTH{1'b0}};
                shadow_requester_value[i] <= {REQUESTER_WIDTH{1'b0}};
                shadow_requester_mask[i] <= {REQUESTER_WIDTH{1'b0}};
                shadow_allowed_profiles[i] <= 2'b00;
                shadow_default_coherent[i] <= 1'b0;
                shadow_allow_intent[i] <= 1'b0;
                shadow_ns_only[i] <= 1'b0;
                active_base[i] <= {ADDR_WIDTH{1'b0}};
                active_limit[i] <= {ADDR_WIDTH{1'b0}};
                active_requester_value[i] <= {REQUESTER_WIDTH{1'b0}};
                active_requester_mask[i] <= {REQUESTER_WIDTH{1'b0}};
                active_allowed_profiles[i] <= 2'b00;
                active_default_coherent[i] <= 1'b0;
                active_allow_intent[i] <= 1'b0;
                active_ns_only[i] <= 1'b0;
            end
        end else begin
            csr_commit_busy_o <= 1'b0;
            csr_commit_error_o <= 1'b0;
            if (csr_security_event_clear_i && csr_secure_i)
                security_event_o <= 1'b0;
            if (ENABLE_POLICY_CSR && (csr_write_i || csr_commit_i || csr_lock_i) && !csr_secure_i)
                security_event_o <= 1'b1;
            if (ENABLE_POLICY_CSR && csr_write_i && csr_secure_i && !csr_locked_o) begin
                shadow_base[csr_index_i] <= csr_base_i;
                shadow_limit[csr_index_i] <= csr_limit_i;
                shadow_requester_value[csr_index_i] <= csr_requester_value_i;
                shadow_requester_mask[csr_index_i] <= csr_requester_mask_i;
                shadow_allowed_profiles[csr_index_i] <= csr_allowed_profiles_i;
                shadow_default_coherent[csr_index_i] <= csr_default_coherent_i;
                shadow_allow_intent[csr_index_i] <= csr_allow_intent_i;
                shadow_ns_only[csr_index_i] <= csr_ns_only_i;
            end
            if (ENABLE_POLICY_CSR && csr_lock_i && csr_secure_i)
                csr_locked_o <= 1'b1;
            if (ENABLE_POLICY_CSR && csr_commit_i && csr_secure_i && !csr_locked_o) begin
                if (shadow_invalid) begin
                    csr_commit_error_o <= 1'b1;
                end else begin
                    commit_pending_q <= 1'b1;
                    admission_block_o <= 1'b1;
                    if (!outstanding_empty_i)
                        csr_commit_busy_o <= 1'b1;
                end
            end
            if (commit_pending_q && outstanding_empty_i) begin
                for (i = 0; i < REGION_COUNT; i = i + 1) begin
                    active_base[i] <= shadow_base[i];
                    active_limit[i] <= shadow_limit[i];
                    active_requester_value[i] <= shadow_requester_value[i];
                    active_requester_mask[i] <= shadow_requester_mask[i];
                    active_allowed_profiles[i] <= shadow_allowed_profiles[i];
                    active_default_coherent[i] <= shadow_default_coherent[i];
                    active_allow_intent[i] <= shadow_allow_intent[i];
                    active_ns_only[i] <= shadow_ns_only[i];
                end
                policy_epoch_o <= policy_epoch_o + 1'b1;
                commit_pending_q <= 1'b0;
                admission_block_o <= 1'b0;
            end
            if (ENABLE_POLICY_CSR && ((ar_query_valid_i && !ar_allow_o) ||
                (aw_query_valid_i && !aw_allow_o))
                )
                security_event_o <= 1'b1;
        end
    end
endmodule
