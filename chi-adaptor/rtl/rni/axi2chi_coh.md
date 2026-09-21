# AXI2CHI Coherent 方案

本文档定义 `axi2chi_coh`。它是独立的 AXI-to-CHI coherent bridge，以
`OpenNoC/rtl/src/rni` 为行为基线；不能与 `axi2chi_nocoh` 共用 parent/child table、
line data plane、TxnID/DBID 生命周期或 CHI raw link owner。

## Step 1：Specification Analysis

### 功能与事务边界

- AXI AR 转换为 `ReadOnce`，CHI RXDAT/CompData 转换为 AXI R。
- AXI AW/W 转换为 `WriteUniquePtl`。
- coherent write 接收 DBID response 后，只有数据 ready 与 DBID ready 才能发送 TXDAT；
  之后等待最终 Comp，并在 request 设置 `ExpCompAck=1` 时发送 CompAck。
- 必须处理 `RetryAck`：保存原事务上下文，等待匹配 `PCrdGrant`，再以原 opcode/TxnID
  语义重发。
- AXI R/B backpressure、CHI credit 与 LinkActive 均不得导致数据丢失或在途状态泄漏。

首版不承担 `ReadNoSnp`、`WriteNoSnpPtl`、`WriteNoSnpFull` 的 non-coherent bridge 语义，
不通过 AXI `AxCACHE/AxPROT` 在 coherent/non-coherent 之间运行时切换，也不增加 snoop/DVM/
atomic/exclusive/CMO 支持，除非 CHI profile 明确要求。

`axi2chi_coh` 沿用与 `axi2chi_nocoh` 相同的 AXI 形状：支持 `INCR`/`FIXED`、unaligned 与
narrow transfer，不支持 `WRAP`；同一 AXI ID 可多笔 outstanding，但必须由 per-ID retire queue
按接收顺序返回 R/B。默认配置为 `axi_data_width=128`、`chi_dat_width=256`、
`cache_line_bytes=64`。`cache_line_bytes` 允许取 `32/64/128` B，且 AXI 与 CHI 的每拍 byte
width 必须分别整除 cache line。

本方案当前只冻结 specification 和 microarchitecture 目标，不进入 RTL 实现或验证排期。
尚待以后冻结：CHI 编码版本，ExpCompAck 默认策略、Retry 次数限制/timeout、CHI error 映射，
以及 reset/link-down 期间在途 coherent transaction 的处置。

### 生成配置

输入配置为 `configs/axi2chi_coh.yml`，其 `profile` 必须为 `axi2chi_coh`。至少包含：

- `axi_data_width` 与 `chi_dat_width` 必须独立配置。首版允许 AXI 取
  32/64/128/256/512 bit，CHI DAT payload 取 128/256/512 bit；两者必须相等或为整数倍关系。
- 默认值为 `axi_data_width=128`、`chi_dat_width=256`、`cache_line_bytes=64`；
  `cache_line_bytes` 仅允许 `32/64/128` B。
- AXI address/ID/LEN/USER width 与 burst 支持项。
- CHI NodeID、TxnID/DBID/DataID width、cache-line size、flit packing 版本。
- AR/AW entry depth、read/write line buffer depth、retry context depth、link receive depth。
- `parent_entries`、`read_data_context_entries`、`write_data_context_entries`、
  `retry_context_entries` 与 `dbid_map_entries`。outstanding 必须由有限参数限制，不能声明为无限制。
- `enable_retry_pcrdgrant`、`enable_exp_compack`、LinkActive/reset policy、输出命名与 manifest。

生成器必须拒绝 non-coherent opcode、`enable_write_no_snp_full=1`、禁用 retry 的 coherent
配置以及非法 depth/width/未知字段。它只能生成参数 package、profile 顶层 wrapper skeleton、
filelist/manifest 和配置报告；DBID、DataID、CompAck、Retry/PCrdGrant、AW/W ordering、credit
和 FSM 必须由后续 RTL 实现。

建议未来以 `parent_entries=16` 为默认初值，并要求其不超过可分配 TxnID 数。实际 admission
还必须同时检查 read/write data context、DBID map、retry context 与 per-ID retire queue。

## 候选模块架构

下列模块以既有 coherent RNI 的职责为基线，并以 `axi2chi_coh_` 前缀建立新代码命名空间。
是否直接迁移或重写，应在 Step 2 完成时决定。

| 模块 | 硬件职责 | 既有基线 | 主要状态/接口 |
|---|---|---|---|
| `axi2chi_coh_cfg_pkg` | YAML 生成的静态参数、coherent opcode 与 CHI/AXI type | `rni_param.v`、`rni_defines.v` | 无时序状态 |
| `axi2chi_coh_top` | 唯一 AXI/CHI 集成与参数传播点 | `rni.v` | 不保存 transaction 状态 |
| `axi2chi_coh_axi_slave` | AXI AR/AW/W 接收、R/B pin-level handshake 与 AW/W 顺序约束 | `rni_axi_ingress.sv` | ingress queue；不保存 transaction completion |
| `axi2chi_coh_rd_engine` | ReadOnce issue 与 coherent 读 transaction FSM | `rni_arctrl.v`、`rni_arlink.v` | 仅读控制状态；context 由 `txn_ctx` 拥有 |
| `axi2chi_coh_wr_engine` | WriteUniquePtl issue、DAT-ready、CompAck 控制 | `rni_awctrl.v`、`rni_awlink.v` | 仅写控制状态；context 由 `txn_ctx` 拥有 |
| `axi2chi_coh_txn_ctx` | 唯一拥有 AR/AW context、TxnID/DBID map、retry snapshot、DataID completion 与释放条件 | `rni_core.sv` 的 child context 思路 | parent/child table、AXI ID、DBID、retry、error/complete |
| `axi2chi_coh_rd_data` | 保存 RXDAT，按宽度关系聚合/拆分并在 RREADY 停顿时保留 AXI R | `rni_rd_buffer.v` | line/fragment RAM、DataID mask、AXI beat/CHI fragment progress |
| `axi2chi_coh_wr_data` | 保存 AXI W，按宽度关系聚合/拆分为 TXDAT fragment | `rni_wr_buffer.v` | line/fragment RAM、WSTRB mask、AXI beat/CHI fragment progress |
| `axi2chi_coh_pcrdgrant_ctl` | 缓存并仲裁 PCrdGrant event | `rni_misc.v` | grant FIFO/winner select；不拥有 retry context |
| `axi2chi_chi_link` | raw CHI link 的唯一 owner：LinkActive、RX dispatch、TX arbitration 与 per-channel credit | `rni_link_ctl.v`、`rni_link_handshake.v`、`rni_lcrd_hdlr.v` | 公共 transport 源码；每个物理 port 只能例化一个 owner |
| `axi2chi_coh_chi_codec` | coherent REQ/RSP/DAT 的字段 pack/unpack | 现有 flit defines 与 `rni_chi_codec.sv` | 组合逻辑；不决定 protocol 状态 |

`axi2chi_chi_link` 的内部子模块固定为 `axi2chi_chi_channel`、`axi2chi_chi_rxflit`、
`axi2chi_chi_txflit` 与 `axi2chi_chi_credit`。它们只实现 profile-neutral transport，不保存
ReadOnce/WriteUniquePtl、Retry 或 CompAck 的 transaction 语义。

数据流为：

```text
AXI AR -> axi_slave -> txn_ctx + rd_engine -> chi_codec -> chi_link -> CHI TXREQ(ReadOnce)
CHI RXDAT/RXRSP -> chi_link -> chi_codec -> txn_ctx + rd_engine -> rd_data -> AXI R

AXI AW/W -> axi_slave -> txn_ctx + wr_engine + wr_data
wr_engine -> chi_codec -> chi_link -> CHI TXREQ(WriteUniquePtl)
RXRSP(DBID) -> chi_link -> txn_ctx + wr_engine -> wr_data -> TXDAT
RXRSP(Comp/RetryAck/PCrdGrant) -> chi_link -> txn_ctx + wr_engine/pcrdgrant_ctl -> AXI B or reissue
wr_engine(ExpCompAck) -> chi_codec -> chi_link -> CHI TXRSP(CompAck)
```

## Step 2 前必须冻结的项

- AXI burst 拆为一个或多个 coherent CHI request/fragment 的精确规则，特别是 `FIXED` burst
  的重复地址与 narrow byte lane 映射。
- 宽度转换的完整映射：AXI beat 与 CHI DAT fragment 的数目、地址/lane 对齐、WSTRB/byte-enable、
  DataID、`WLAST/RLAST` 与 error 的映射。
- cache-line size 与 `axi_data_width`、`chi_dat_width` 的整除约束；每拍 byte width 不能整除
  cache line 的组合首版必须拒绝。
- `RetryAck`/`PCrdGrant` 的匹配 key、重试上限与 timeout 行为。
- `CompDBIDResp` 的合法性以及它与 TXDAT/最终 Comp 的状态机关系。
- DataID/line fragment 顺序、buffer full 时 L-credit return 的精确定义。
- ExpCompAck 默认值、谁决定其值及 CompAck 仲裁优先级。
- 正常 LinkActive 上电/下电、credit drain 和非预期 link-down/reset 的 containment 规则；建议
  future implementation 与 nocoh 一致：正常下电 drain，故障/reset 时由系统 quiesce master，
  不对结果未知的 CHI transaction 伪造 AXI response。

## 实现状态

`axi2chi_coh` 当前不进入 Step 3/Step 4。它保留为与 `rtl/src/rni` 对照的 specification 与
microarchitecture 方案，待 `axi2chi_nocoh` 的 transaction context、宽度转换和 CHI link
验证稳定后，再冻结 coherent 专有的 Retry/PCrdGrant/CompAck 细节。

## 验证焦点

- ReadOnce 连续读、RREADY 停顿、DataID 乱序/缺失/重复。
- WriteUniquePtl 的 AW/W 分离、DBID 先后顺序、TXDAT 仅在 DBID 和数据均 ready 后发生。
- Comp、CompDBIDResp 与 CompAck 时序；BREADY 停顿。
- RetryAck 至 PCrdGrant 的暂停和原事务重发；不匹配 grant、重试耗尽和无效 TxnID。
- LinkActive、credit 耗尽、reset 与所有 context/allocator/buffer 的清空。
