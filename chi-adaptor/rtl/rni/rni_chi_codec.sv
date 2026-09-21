// Canonical CHI flit codec. Core logic must not depend on raw flit slices.
`default_nettype none
module rni_chi_codec #(
  parameter int unsigned NidWidth = 7,
  parameter int unsigned TxnidWidth = 12,
  parameter int unsigned ReqAddrWidth = 44,
  parameter int unsigned DataWidth = 256,
  parameter int unsigned BeWidth = 32,
  parameter int unsigned DatRsvdcWidth = 0,
  parameter int unsigned ReqFlitWidth = ReqAddrWidth + 3 * NidWidth + 66,
  parameter int unsigned RspFlitWidth = 73,
  parameter int unsigned DatFlitWidth = 406
) (
  input  logic [ReqFlitWidth-1:0] req_flit_i,
  output logic [6:0] req_opcode_o,
  output logic [NidWidth-1:0] req_src_id_o,
  output logic [NidWidth-1:0] req_return_nid_o,
  output logic [TxnidWidth-1:0] req_txnid_o,
  output logic [TxnidWidth-1:0] req_return_txnid_o,
  output logic [ReqAddrWidth-1:0] req_addr_o,
  output logic [2:0] req_size_o,
  output logic req_is_readnosnp_o,
  input  logic [NidWidth-1:0] read_tgt_id_i,
  input  logic [NidWidth-1:0] read_src_id_i,
  input  logic [TxnidWidth-1:0] read_txnid_i,
  input  logic [NidWidth-1:0] read_return_nid_i,
  input  logic [TxnidWidth-1:0] read_return_txnid_i,
  input  logic [ReqAddrWidth-1:0] read_addr_i,
  input  logic [2:0] read_size_i,
  input  logic read_ns_i,
  input  logic [1:0] read_order_i,
  input  logic [3:0] read_memattr_i,
  output logic [ReqFlitWidth-1:0] readnosnp_flit_o,
  input  logic [NidWidth-1:0] write_tgt_id_i,
  input  logic [NidWidth-1:0] write_src_id_i,
  input  logic [TxnidWidth-1:0] write_txnid_i,
  input  logic [NidWidth-1:0] write_return_nid_i,
  input  logic [TxnidWidth-1:0] write_return_txnid_i,
  input  logic [ReqAddrWidth-1:0] write_addr_i,
  input  logic [2:0] write_size_i,
  input  logic write_ns_i,
  input  logic [1:0] write_order_i,
  input  logic [3:0] write_memattr_i,
  output logic [ReqFlitWidth-1:0] writenosnpptl_flit_o,
  input  logic [RspFlitWidth-1:0] rsp_flit_i,
  output logic [4:0] rsp_opcode_o,
  output logic [NidWidth-1:0] rsp_src_id_o,
  output logic [TxnidWidth-1:0] rsp_txnid_o,
  output logic [TxnidWidth-1:0] rsp_dbid_o,
  output logic [1:0] rsp_resperr_o,
  output logic rsp_is_dbidresp_o,
  output logic rsp_is_compdbidresp_o,
  output logic rsp_is_comp_o,
  input  logic [DatFlitWidth-1:0] dat_flit_i,
  output logic [3:0] dat_opcode_o,
  output logic [TxnidWidth-1:0] dat_txnid_o,
  output logic [1:0] dat_dataid_o,
  output logic [1:0] dat_resperr_o,
  output logic [BeWidth-1:0] dat_be_o,
  output logic [DataWidth-1:0] dat_data_o,
  input  logic [NidWidth-1:0] comp_tgt_id_i,
  input  logic [NidWidth-1:0] comp_src_id_i,
  input  logic [NidWidth-1:0] comp_home_nid_i,
  input  logic [TxnidWidth-1:0] comp_txnid_i,
  input  logic [TxnidWidth-1:0] comp_dbid_i,
  input  logic [31:0] comp_data_i,
  output logic [DatFlitWidth-1:0] compdata_flit_o,
  input  logic [NidWidth-1:0] wrdat_tgt_id_i,
  input  logic [NidWidth-1:0] wrdat_src_id_i,
  input  logic [NidWidth-1:0] wrdat_home_nid_i,
  input  logic [TxnidWidth-1:0] wrdat_txnid_i,
  input  logic [TxnidWidth-1:0] wrdat_dbid_i,
  input  logic [1:0] wrdat_dataid_i,
  input  logic [BeWidth-1:0] wrdat_be_i,
  input  logic [DataWidth-1:0] wrdat_data_i,
  output logic [DatFlitWidth-1:0] noncopyback_wrdata_flit_o
);
  localparam int unsigned ReqSrcIdLsb = NidWidth + 4;
  localparam int unsigned ReqTxnidLsb = 2 * NidWidth + 4;
  localparam int unsigned ReqReturnNidLsb = 2 * NidWidth + 16;
  localparam int unsigned ReqReturnTxnidLsb = 3 * NidWidth + 17;
  localparam int unsigned ReqOpcodeLsb = 3 * NidWidth + 29;
  localparam int unsigned ReqSizeLsb = 3 * NidWidth + 36;
  localparam int unsigned ReqAddrLsb = 3 * NidWidth + 39;
  localparam int unsigned ReqNsLsb = ReqAddrLsb + ReqAddrWidth;
  localparam int unsigned RspSrcIdLsb = NidWidth + 4;
  localparam int unsigned RspTxnidLsb = 2 * NidWidth + 4;
  localparam int unsigned RspOpcodeLsb = 2 * NidWidth + 16;
  localparam int unsigned RspRespErrLsb = 2 * NidWidth + 21;
  localparam int unsigned RspDbidLsb = 2 * NidWidth + 32;
  localparam int unsigned DatTxnidLsb = 2 * NidWidth + 4;
  localparam int unsigned DatHomeNidLsb = 2 * NidWidth + 16;
  localparam int unsigned DatOpcodeLsb = 3 * NidWidth + 16;
  localparam int unsigned DatDbidLsb = 3 * NidWidth + 32;
  localparam int unsigned DatBeLsb = 3 * NidWidth + DataWidth / 32 +
                                     DataWidth / 128 + DatRsvdcWidth + 51;
  localparam int unsigned DatDataLsb = DatBeLsb + BeWidth;
  always_comb begin
    req_opcode_o = req_flit_i[ReqOpcodeLsb +: 7];
    req_src_id_o = req_flit_i[ReqSrcIdLsb +: NidWidth];
    req_return_nid_o = req_flit_i[ReqReturnNidLsb +: NidWidth];
    req_txnid_o = req_flit_i[ReqTxnidLsb +: TxnidWidth];
    req_return_txnid_o = req_flit_i[ReqReturnTxnidLsb +: TxnidWidth];
    req_addr_o = req_flit_i[ReqAddrLsb +: ReqAddrWidth];
    req_size_o = req_flit_i[ReqSizeLsb +: 3];
    req_is_readnosnp_o = (req_opcode_o == 7'h04);
    readnosnp_flit_o = '0;
    readnosnp_flit_o[4 +: NidWidth] = read_tgt_id_i;
    readnosnp_flit_o[ReqSrcIdLsb +: NidWidth] = read_src_id_i;
    readnosnp_flit_o[ReqTxnidLsb +: TxnidWidth] = read_txnid_i;
    readnosnp_flit_o[ReqReturnNidLsb +: NidWidth] = read_return_nid_i;
    readnosnp_flit_o[ReqReturnTxnidLsb +: TxnidWidth] = read_return_txnid_i;
    readnosnp_flit_o[ReqOpcodeLsb +: 7] = 7'h04;
    readnosnp_flit_o[ReqSizeLsb +: 3] = read_size_i;
    readnosnp_flit_o[ReqAddrLsb +: ReqAddrWidth] = read_addr_i;
    readnosnp_flit_o[ReqNsLsb] = read_ns_i;
    readnosnp_flit_o[ReqNsLsb + 2] = 1'b0;
    readnosnp_flit_o[ReqNsLsb + 3 +: 2] = read_order_i;
    readnosnp_flit_o[ReqNsLsb + 9 +: 4] = read_memattr_i;
    writenosnpptl_flit_o = '0;
    writenosnpptl_flit_o[4 +: NidWidth] = write_tgt_id_i;
    writenosnpptl_flit_o[ReqSrcIdLsb +: NidWidth] = write_src_id_i;
    writenosnpptl_flit_o[ReqTxnidLsb +: TxnidWidth] = write_txnid_i;
    writenosnpptl_flit_o[ReqReturnNidLsb +: NidWidth] = write_return_nid_i;
    writenosnpptl_flit_o[ReqReturnTxnidLsb +: TxnidWidth] =
        write_return_txnid_i;
    writenosnpptl_flit_o[ReqOpcodeLsb +: 7] = 7'h1c;
    writenosnpptl_flit_o[ReqSizeLsb +: 3] = write_size_i;
    writenosnpptl_flit_o[ReqAddrLsb +: ReqAddrWidth] = write_addr_i;
    writenosnpptl_flit_o[ReqNsLsb] = write_ns_i;
    writenosnpptl_flit_o[ReqNsLsb + 2] = 1'b0;
    writenosnpptl_flit_o[ReqNsLsb + 3 +: 2] = write_order_i;
    writenosnpptl_flit_o[ReqNsLsb + 9 +: 4] = write_memattr_i;
    rsp_opcode_o = rsp_flit_i[RspOpcodeLsb +: 5];
    rsp_src_id_o = rsp_flit_i[RspSrcIdLsb +: NidWidth];
    rsp_txnid_o = rsp_flit_i[RspTxnidLsb +: TxnidWidth];
    rsp_dbid_o = rsp_flit_i[RspDbidLsb +: TxnidWidth];
    rsp_resperr_o = rsp_flit_i[RspRespErrLsb +: 2];
    rsp_is_dbidresp_o = (rsp_opcode_o == 5'h06);
    rsp_is_compdbidresp_o = (rsp_opcode_o == 5'h05);
    rsp_is_comp_o = (rsp_opcode_o == 5'h04);
    dat_opcode_o = dat_flit_i[DatOpcodeLsb +: 4];
    dat_txnid_o = dat_flit_i[DatTxnidLsb +: TxnidWidth];
    dat_dataid_o = dat_flit_i[3 * NidWidth + 46 +: 2];
    dat_resperr_o = dat_flit_i[3 * NidWidth + 20 +: 2];
    dat_be_o = dat_flit_i[DatBeLsb +: BeWidth];
    dat_data_o = dat_flit_i[DatDataLsb +: DataWidth];
    compdata_flit_o = '0;
    compdata_flit_o[4 +: NidWidth] = comp_tgt_id_i;
    compdata_flit_o[ReqSrcIdLsb +: NidWidth] = comp_src_id_i;
    compdata_flit_o[DatTxnidLsb +: TxnidWidth] = comp_txnid_i;
    compdata_flit_o[DatHomeNidLsb +: NidWidth] = comp_home_nid_i;
    compdata_flit_o[DatOpcodeLsb +: 4] = 4'h4;
    compdata_flit_o[3 * NidWidth + 22 +: 3] = 3'b010;
    compdata_flit_o[DatDbidLsb +: TxnidWidth] = comp_dbid_i;
    compdata_flit_o[DatBeLsb +: BeWidth] = {{(BeWidth-4){1'b0}}, 4'hf};
    compdata_flit_o[DatDataLsb +: 32] = comp_data_i;
    noncopyback_wrdata_flit_o = '0;
    noncopyback_wrdata_flit_o[4 +: NidWidth] = wrdat_tgt_id_i;
    noncopyback_wrdata_flit_o[ReqSrcIdLsb +: NidWidth] = wrdat_src_id_i;
    noncopyback_wrdata_flit_o[DatHomeNidLsb +: NidWidth] = wrdat_home_nid_i;
    noncopyback_wrdata_flit_o[DatTxnidLsb +: TxnidWidth] = wrdat_txnid_i;
    noncopyback_wrdata_flit_o[DatOpcodeLsb +: 4] = 4'h3;
    noncopyback_wrdata_flit_o[DatDbidLsb +: TxnidWidth] = wrdat_dbid_i;
    noncopyback_wrdata_flit_o[3 * NidWidth + 46 +: 2] = wrdat_dataid_i;
    noncopyback_wrdata_flit_o[DatBeLsb +: BeWidth] = wrdat_be_i;
    noncopyback_wrdata_flit_o[DatDataLsb +: DataWidth] = wrdat_data_i;
  end
endmodule
`default_nettype wire
