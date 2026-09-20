// Stateless atomic handoff bridge between AXI ingress bundles and rni_core.

`default_nettype none

module rni_axi_core_admission_bridge #(
  parameter int unsigned AddrWidth = 64,
  parameter int unsigned DataWidth = 32,
  parameter int unsigned IdWidth = 4,
  parameter int unsigned AxlenWidth = 8,
  parameter int unsigned AxsizeWidth = 3
) (
  input  logic                        clk,
  input  logic                        rst,
  input  logic                        write_bundle_valid_i,
  input  logic [IdWidth-1:0]          write_bundle_id_i,
  input  logic [AddrWidth-1:0]        write_bundle_addr_i,
  input  logic [AxlenWidth-1:0]       write_bundle_len_i,
  input  logic [AxsizeWidth-1:0]      write_bundle_size_i,
  input  logic [1:0]                  write_bundle_burst_i,
  input  logic [DataWidth-1:0]        write_bundle_data_i,
  input  logic [DataWidth / 8-1:0]    write_bundle_strb_i,
  output logic                        write_bundle_ready_o,
  output logic                        core_write_cmd_valid_o,
  output logic [IdWidth-1:0]          core_write_cmd_id_o,
  output logic [AddrWidth-1:0]        core_write_cmd_addr_o,
  output logic [AxlenWidth-1:0]       core_write_cmd_len_o,
  output logic [AxsizeWidth-1:0]      core_write_cmd_size_o,
  output logic [1:0]                  core_write_cmd_burst_o,
  input  logic                        core_write_cmd_ready_i,
  output logic                        core_write_data_valid_o,
  output logic [DataWidth-1:0]        core_write_data_o,
  output logic [DataWidth / 8-1:0]    core_write_strb_o,
  output logic                        core_write_last_o,
  input  logic                        core_write_data_ready_i,
  input  logic                        read_bundle_valid_i,
  input  logic [IdWidth-1:0]          read_bundle_id_i,
  input  logic [AddrWidth-1:0]        read_bundle_addr_i,
  input  logic [AxlenWidth-1:0]       read_bundle_len_i,
  input  logic [AxsizeWidth-1:0]      read_bundle_size_i,
  input  logic [1:0]                  read_bundle_burst_i,
  output logic                        read_bundle_ready_o,
  output logic                        core_read_cmd_valid_o,
  output logic [IdWidth-1:0]          core_read_cmd_id_o,
  output logic [AddrWidth-1:0]        core_read_cmd_addr_o,
  output logic [AxlenWidth-1:0]       core_read_cmd_len_o,
  output logic [AxsizeWidth-1:0]      core_read_cmd_size_o,
  output logic [1:0]                  core_read_cmd_burst_o,
  input  logic                        core_read_cmd_ready_i
);

  always_comb begin
    core_write_cmd_valid_o = write_bundle_valid_i;
    core_write_cmd_id_o = write_bundle_id_i;
    core_write_cmd_addr_o = write_bundle_addr_i;
    core_write_cmd_len_o = write_bundle_len_i;
    core_write_cmd_size_o = write_bundle_size_i;
    core_write_cmd_burst_o = write_bundle_burst_i;
    core_write_data_valid_o = write_bundle_valid_i;
    core_write_data_o = write_bundle_data_i;
    core_write_strb_o = write_bundle_strb_i;
    core_write_last_o = 1'b1;
    write_bundle_ready_o = core_write_cmd_ready_i && core_write_data_ready_i;
    core_read_cmd_valid_o = read_bundle_valid_i;
    core_read_cmd_id_o = read_bundle_id_i;
    core_read_cmd_addr_o = read_bundle_addr_i;
    core_read_cmd_len_o = read_bundle_len_i;
    core_read_cmd_size_o = read_bundle_size_i;
    core_read_cmd_burst_o = read_bundle_burst_i;
    read_bundle_ready_o = core_read_cmd_ready_i;
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (!rst && write_bundle_valid_i) begin
      assert (core_write_cmd_ready_i == core_write_data_ready_i)
          else $fatal(1, "core write command/data readiness diverged");
    end
  end
`endif

endmodule

`default_nettype wire
