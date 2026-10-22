`timescale 1ns/1ps
`default_nettype none

// This test elaborates every legal AXI/CHI/cache-line geometry defined for
// the first release. Each DUT's elaboration-time checks must accept it.
module tb_axi2chi_nocoh_profile_elaboration;
`define LEGAL_PROFILE(INSTANCE, AXI_WIDTH, CHI_WIDTH, LINE_BYTES) \
  axi2chi_nocoh_top #( \
      .AxiAddrWidth(32), \
      .AxiDataWidth(AXI_WIDTH), \
      .AxiIdWidth(2), \
      .ChiTxnidWidth(8), \
      .ChiDbidWidth(8), \
      .ChiDataWidth(CHI_WIDTH), \
      .CacheLineBytes(LINE_BYTES), \
      .ParentEntries(4), \
      .ChildEntries(4), \
      .ReqFlitWidth(128), \
      .RspFlitWidth(64), \
      .DatFlitWidth(CHI_WIDTH + 128)) INSTANCE ();

  `LEGAL_PROFILE(profile_032_128_l32, 32, 128, 32)
  `LEGAL_PROFILE(profile_032_256_l32, 32, 256, 32)
  `LEGAL_PROFILE(profile_064_128_l32, 64, 128, 32)
  `LEGAL_PROFILE(profile_064_256_l32, 64, 256, 32)
  `LEGAL_PROFILE(profile_128_128_l32, 128, 128, 32)
  `LEGAL_PROFILE(profile_128_256_l32, 128, 256, 32)
  `LEGAL_PROFILE(profile_256_128_l32, 256, 128, 32)
  `LEGAL_PROFILE(profile_256_256_l32, 256, 256, 32)

  `LEGAL_PROFILE(profile_032_128_l64, 32, 128, 64)
  `LEGAL_PROFILE(profile_032_256_l64, 32, 256, 64)
  `LEGAL_PROFILE(profile_032_512_l64, 32, 512, 64)
  `LEGAL_PROFILE(profile_064_128_l64, 64, 128, 64)
  `LEGAL_PROFILE(profile_064_256_l64, 64, 256, 64)
  `LEGAL_PROFILE(profile_064_512_l64, 64, 512, 64)
  `LEGAL_PROFILE(profile_128_128_l64, 128, 128, 64)
  `LEGAL_PROFILE(profile_128_256_l64, 128, 256, 64)
  `LEGAL_PROFILE(profile_128_512_l64, 128, 512, 64)
  `LEGAL_PROFILE(profile_256_128_l64, 256, 128, 64)
  `LEGAL_PROFILE(profile_256_256_l64, 256, 256, 64)
  `LEGAL_PROFILE(profile_256_512_l64, 256, 512, 64)
  `LEGAL_PROFILE(profile_512_128_l64, 512, 128, 64)
  `LEGAL_PROFILE(profile_512_256_l64, 512, 256, 64)
  `LEGAL_PROFILE(profile_512_512_l64, 512, 512, 64)

  `LEGAL_PROFILE(profile_032_128_l128, 32, 128, 128)
  `LEGAL_PROFILE(profile_032_256_l128, 32, 256, 128)
  `LEGAL_PROFILE(profile_032_512_l128, 32, 512, 128)
  `LEGAL_PROFILE(profile_064_128_l128, 64, 128, 128)
  `LEGAL_PROFILE(profile_064_256_l128, 64, 256, 128)
  `LEGAL_PROFILE(profile_064_512_l128, 64, 512, 128)
  `LEGAL_PROFILE(profile_128_128_l128, 128, 128, 128)
  `LEGAL_PROFILE(profile_128_256_l128, 128, 256, 128)
  `LEGAL_PROFILE(profile_128_512_l128, 128, 512, 128)
  `LEGAL_PROFILE(profile_256_128_l128, 256, 128, 128)
  `LEGAL_PROFILE(profile_256_256_l128, 256, 256, 128)
  `LEGAL_PROFILE(profile_256_512_l128, 256, 512, 128)
  `LEGAL_PROFILE(profile_512_128_l128, 512, 128, 128)
  `LEGAL_PROFILE(profile_512_256_l128, 512, 256, 128)
  `LEGAL_PROFILE(profile_512_512_l128, 512, 512, 128)

  initial begin
    #1;
    $display("PASS: all 38 legal AXI/CHI/cache-line profiles elaborate");
    $finish;
  end
`undef LEGAL_PROFILE
endmodule

`default_nettype wire
