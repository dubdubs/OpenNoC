`timescale 1ns/1ps
module tb_new_rni;
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    reg [43:0] addr1024;
    reg [1023:0] data1024;
    reg [127:0] valid1024;
    wire [1:0] fragments1024;
    wire [43:0] f0_addr1024, f1_addr1024;
    wire [63:0] f0_mask1024, f1_mask1024;
    wire [511:0] f0_data1024, f1_data1024;
    new_rni_axi_fragment_adapter #(.AXI_DATA_WIDTH(1024)) adapter1024 (
        .axi_addr_i(addr1024), .axi_size_i(3'd7), .axi_burst_i(2'b01), .axi_beat_index_i(8'd0),
        .axi_data_i(data1024), .axi_lane_valid_i(valid1024), .fragment_count_o(fragments1024),
        .fragment0_line_addr_o(f0_addr1024), .fragment0_byte_mask_o(f0_mask1024), .fragment0_data_o(f0_data1024),
        .fragment1_line_addr_o(f1_addr1024), .fragment1_byte_mask_o(f1_mask1024), .fragment1_data_o(f1_data1024));
    reg [43:0] addr32;
    reg [31:0] data32;
    reg [3:0] valid32;
    wire [1:0] fragments32;
    new_rni_axi_fragment_adapter #(.AXI_DATA_WIDTH(32)) adapter32 (
        .axi_addr_i(addr32), .axi_size_i(3'd2), .axi_burst_i(2'b00), .axi_beat_index_i(8'd2),
        .axi_data_i(data32), .axi_lane_valid_i(valid32), .fragment_count_o(fragments32),
        .fragment0_line_addr_o(), .fragment0_byte_mask_o(), .fragment0_data_o(),
        .fragment1_line_addr_o(), .fragment1_byte_mask_o(), .fragment1_data_o());

    reg [511:0] line_data;
    reg [63:0] line_be;
    wire [127:0] dat128;
    wire [15:0] be128;
    wire last128;
    wire [255:0] dat256;
    wire [31:0] be256;
    wire last256;
    wire [511:0] dat512;
    wire [63:0] be512;
    wire last512;
    new_rni_chi_dat_adapter #(.CHI_DATA_WIDTH(128)) dat_adapter128 (
        .tx_line_data_i(line_data), .tx_line_be_i(line_be), .tx_ordinal_i(2'd3), .tx_dat_data_o(dat128),
        .tx_dat_be_o(be128), .tx_dat_last_o(last128), .clk_i(clk), .rst_ni(rst_n), .rx_dat_valid_i(1'b0),
        .rx_ordinal_i(2'b0), .rx_dat_data_i(128'b0), .rx_dat_be_i(16'b0), .rx_line_data_o(), .rx_line_be_o());
    new_rni_chi_dat_adapter #(.CHI_DATA_WIDTH(512)) dat_adapter512 (
        .tx_line_data_i(line_data), .tx_line_be_i(line_be), .tx_ordinal_i(1'b0), .tx_dat_data_o(dat512),
        .tx_dat_be_o(be512), .tx_dat_last_o(last512), .clk_i(clk), .rst_ni(rst_n), .rx_dat_valid_i(1'b0),
        .rx_ordinal_i(1'b0), .rx_dat_data_i(512'b0), .rx_dat_be_i(64'b0), .rx_line_data_o(), .rx_line_be_o());
    new_rni_chi_dat_adapter #(.CHI_DATA_WIDTH(256)) dat_adapter256 (
        .tx_line_data_i(line_data), .tx_line_be_i(line_be), .tx_ordinal_i(1'b1), .tx_dat_data_o(dat256),
        .tx_dat_be_o(be256), .tx_dat_last_o(last256), .clk_i(clk), .rst_ni(rst_n), .rx_dat_valid_i(1'b0),
        .rx_ordinal_i(1'b0), .rx_dat_data_i(256'b0), .rx_dat_be_i(32'b0), .rx_line_data_o(), .rx_line_be_o());

    integer byte_index;
    initial begin
        addr1024 = 44'h3f;
        data1024 = '0;
        valid1024 = '0;
        addr32 = 44'h20;
        data32 = 32'h03020100;
        valid32 = 4'hf;
        for (byte_index = 63; byte_index < 128; byte_index = byte_index + 1) begin
            data1024[byte_index*8 +: 8] = byte_index[7:0];
            valid1024[byte_index] = 1'b1;
        end
        for (byte_index = 0; byte_index < 64; byte_index = byte_index + 1) begin
            line_data[byte_index*8 +: 8] = byte_index[7:0];
            line_be[byte_index] = 1'b1;
        end
        #12 rst_n = 1;
        #1;
        if (fragments1024 != 2 || f0_mask1024[63] != 1'b1 || f1_mask1024 != {64{1'b1}})
            $fatal(1, "1024-bit unaligned AXI lane split failed");
        if (fragments32 != 1)
            $fatal(1, "32-bit FIXED AXI fragment mapping failed");
        if (!last128 || dat128[7:0] != 8'd48 || be128 != {16{1'b1}})
            $fatal(1, "128-bit CHI DAT ordinal packing failed");
        if (!last256 || dat256[7:0] != 8'd32 || be256 != {32{1'b1}})
            $fatal(1, "256-bit CHI DAT ordinal packing failed");
        if (!last512 || dat512 != line_data || be512 != line_be)
            $fatal(1, "512-bit CHI DAT packing failed");
        $display("tb_new_rni PASS: INCR lane split, AXI=1024, CHI DAT=128/512");
        $finish;
    end
endmodule
