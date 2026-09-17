// Scheme-1 line hazard table.  Opposite profiles for the same 64-byte line
// are serialized until the owning AXI parent releases its token after R/B.
module rni_line_hazard #(
    parameter integer ADDR_WIDTH = 44,
    parameter integer OWNER_WIDTH = 8,
    parameter integer ENTRIES = 64
) (
    input wire clk_i,
    input wire rst_i,
    input wire acquire_valid_i,
    input wire [ADDR_WIDTH-1:0] acquire_addr_i,
    input wire acquire_profile_i,
    input wire [OWNER_WIDTH-1:0] acquire_owner_i,
    output reg acquire_ready_o,
    input wire release_valid_i,
    input wire [OWNER_WIDTH-1:0] release_owner_i,
    output reg empty_o
);
    reg valid_q [0:ENTRIES-1];
    reg [ADDR_WIDTH-1:6] line_q [0:ENTRIES-1];
    reg profile_q [0:ENTRIES-1];
    reg [OWNER_WIDTH-1:0] owner_q [0:ENTRIES-1];
    reg conflict;
    reg free_found;
    integer free_index;
    integer i;

    always @* begin
        conflict = 1'b0;
        free_found = 1'b0;
        free_index = 0;
        empty_o = 1'b1;
        for (i = 0; i < ENTRIES; i = i + 1) begin
            if (valid_q[i]) begin
                empty_o = 1'b0;
                if ((line_q[i] == acquire_addr_i[ADDR_WIDTH-1:6]) &&
                    (profile_q[i] != acquire_profile_i))
                    conflict = 1'b1;
            end else if (!free_found) begin
                free_found = 1'b1;
                free_index = i;
            end
        end
        acquire_ready_o = free_found && !conflict;
    end

    always @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            for (i = 0; i < ENTRIES; i = i + 1)
                valid_q[i] <= 1'b0;
        end else begin
            if (release_valid_i)
                for (i = 0; i < ENTRIES; i = i + 1)
                    if (valid_q[i] && owner_q[i] == release_owner_i)
                        valid_q[i] <= 1'b0;
            if (acquire_valid_i && acquire_ready_o) begin
                valid_q[free_index] <= 1'b1;
                line_q[free_index] <= acquire_addr_i[ADDR_WIDTH-1:6];
                profile_q[free_index] <= acquire_profile_i;
                owner_q[free_index] <= acquire_owner_i;
            end
        end
    end
endmodule
