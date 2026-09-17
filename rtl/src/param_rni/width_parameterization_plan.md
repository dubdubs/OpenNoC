# OpenNoC RNI 数据位宽参数化修改方案

## 1. 目标

将 legacy `rni` 的 AXI4 数据位宽和 CHI DAT 数据位宽由当前实际可用的固定组合
`AXI=128 bit`、`CHI DAT=256 bit` 扩展为 AMBA 协议允许的编译期配置空间：

| 接口 | 支持宽度 |
|---|---|
| AXI4 full `WDATA/RDATA` | 8 / 16 / 32 / 64 / 128 / 256 / 512 / 1024 bit |
| CHI `DAT.DATA` | 128 / 256 / 512 bit |
| Cache line | 固定 64B（本 RNI 的架构约束，并非由 AXI 规定） |

AXI 宽度是 interface capacity；`AxSIZE`（`1 << AxSIZE`）给出 nominal transfer size，且受
`AxSIZE <= log2(AXI bus bytes)` 约束。地址和 byte-lane/WSTRB 决定实际有效 byte，特别是
非对齐 burst 的首拍；不能以编译期 `WDATA/RDATA` 宽度替代运行时的 size 与 lane 映射。

本方案不改变 RNI 的 CHI 请求、Retry/PCrdGrant、DBID、CompAck、AXI ID 依赖、link
handshake 或 L-credit 协议语义；只重构 line 内数据存储、搬运和计数逻辑。

## 2. 当前限制

顶层参数 `AXI4_AXDATA_WIDTH_PARAM`、`CHIE_DATA_WIDTH_PARAM` 和
`CHIE_BE_WIDTH_PARAM` 已能向多数子模块传播，但数据路径实际固定为：

```text
64B cache line = 4 x 16B slot = 4 x 128b bank
AXI WDATA      = 128b（每 beat 对应一个 slot）
CHI DAT        = 256b（每 line 固定两个 DAT flit）
```

其中 `rni_wr_buffer` 将四个 AXI 宽度 bank 直接拼为两个 DAT，且 DataID 固定使用两个
packet；`rni_rd_buffer` 对 AXI 输出仅实现 128/256b 组合，并带有 `AXI=128`、`CHI=256`
的断言。因此不能仅删除断言或改顶层 parameter。

## 3. 基本架构决策

### 3.1 固定 canonical storage

保持 cache line 和内部存储粒度不变：

```text
64B line
└── slot[0..3]，每个 slot 固定为 16B / 128b
```

`rni_datbuf_bank` 继续保存每 entry 的四个 128b bank。AXI 和 CHI DAT 宽度均通过
slot 与接口之间的 scatter/gather 转换实现；不得令 bank 宽度跟随 AXI 宽度，否则不同
AXI 配置会改变 line 的存储布局。

### 3.2 统一派生参数

在 `rtl/include/rni_param.v` 或新增的参数定义区域中统一定义：

```systemverilog
localparam integer RNI_LINE_BYTES = 64;
localparam integer RNI_SLOT_BYTES = 16;
localparam integer RNI_SLOT_COUNT = 4;

localparam integer RNI_AXI_BUS_BYTES = AXI4_AXDATA_WIDTH_PARAM / 8;
localparam integer RNI_CHI_DAT_BYTES = CHIE_DATA_WIDTH_PARAM / 8;
localparam integer RNI_CHI_DATS_PER_LINE = RNI_LINE_BYTES / RNI_CHI_DAT_BYTES;
localparam integer RNI_AXI_MAX_LINES_PER_BEAT =
    (RNI_AXI_BUS_BYTES + RNI_LINE_BYTES - 1) / RNI_LINE_BYTES;
```

必须在 elaboration 时检查：

- AXI4 full 宽度属于 `{8, 16, 32, 64, 128, 256, 512, 1024}`；
- CHI DAT 宽度属于 `{128, 256, 512}`；
- AXI bus bytes 与 CHI DAT bytes 均为 2 的幂；
- 每笔 AXI 事务满足 `AxSIZE <= $clog2(RNI_AXI_BUS_BYTES)`；
- `CHIE_BE_WIDTH_PARAM == CHIE_DATA_WIDTH_PARAM / 8`；
- 参数变化不改变 `RNI_LINE_BYTES=64`、`RNI_SLOT_BYTES=16`。

非法组合必须通过 `$error/$fatal` 或现有 `assert_checker` 在仿真开始时失败，禁止截断或
隐式扩展。

## 4. 数据流改造

### 4.1 AXI write → canonical bank

`rni_wr_buffer` 的 W ingress 从“一个 AXI beat 写一个 AXI 宽度 bank”改为按 byte lane
scatter：

1. 用已分配的 `entry`、`AxADDR/AxSIZE/AxBURST`、segment 描述符和 W beat ordinal 计算本
   beat 的实际字节范围；不得由 AXI bus width 推导。
2. 对每个有效 `WSTRB` byte，计算 `slot_index = byte_offset / 16` 与
   `slot_byte_index = byte_offset % 16`。
3. 写入相应 128b bank 的 byte，同时更新该 byte 的 strobe。
4. AXI 的非对齐仅影响 burst 首拍：首拍以 address/byte-lane（写为 WSTRB）表示有效 byte，
   并在自然对齐边界结束，后续拍对齐。故 1024b bus 上的一个 data-bus presentation 最多覆盖
   两条 64B line；前端必须按有效 byte 生成最多两个 line fragment，且不得把首拍未选 byte
   当成访问数据。窄 beat 则可更新一个 slot 的部分 byte。

W channel 仍按 AXI4 无 WID 的规则与 AW FIFO 队首绑定；参数化不能改变现有 write-data
ordering。

### 4.2 Canonical bank → CHI TXDAT

`rni_wr_buffer` 按 `dat_ordinal` 将连续 slot gather 成 CHI DAT flit：

| CHI DAT 宽度 | 每 line DAT 数 | 每 DAT 覆盖 slot |
|---|---:|---|
| 128b | 4 | 1 |
| 256b | 2 | 2 |
| 512b | 1 | 4 |

每个 DAT 的 DATA/BE 都由覆盖 slot 逐字节拼接。DataID 由版本化函数
`dat_ordinal_to_dataid()` 生成，不能继续硬编码为默认 256b profile 的 `00/10`。函数必须
与所选 CHI revision 和 DAT width 的规范编码一致。

DBID、原 write TxnID、目标 NodeID、`ExpCompAck` 和最后 DAT 状态的生命周期维持现有
write completion 契约；改变 DAT 数量不得提前释放 DBID route。

### 4.3 CHI RXDAT → canonical bank

`rni_rd_buffer` 新增或重构 `dataid_to_dat_ordinal()`：

1. 以 `TxnID` 和合法 DataID 找到该 DAT 覆盖的 line slot 起点。
2. 将 128/256/512b RXDAT 分拆为一至四个 128b slot，写入对应 bank。
3. 将该 DAT 的 `RespErr` 写入所有覆盖 slot 的 error metadata。
4. 以 DataID completion mask 判断一个 segment 的所需 slot 是否齐全。

未知、重复、不属于该 transaction 或与当前 CHI DAT width 不匹配的 DataID 必须报告协议
错误，不得仅按到达顺序写 bank。

### 4.4 Canonical bank → AXI read

`rni_rd_buffer` 按每个 AXI read beat 的 `AxSIZE` 与地址计算 slot/byte 覆盖范围并 gather
RDATA。一个 beat 若跨 line，两个 line fragment 的数据必须在 parent beat 内按地址顺序合并，
然后才产生一项 AXI R；不得将 fragment 误报为额外 R beat。RDATA 和 RRESP 均由对应 slot
的 data/error metadata 合成。AXI R FIFO、RID/RLAST 和 backpressure 的既有协议不变。

## 5. 模块修改边界

| 文件 | 修改内容 | 不变部分 |
|---|---|---|
| `rtl/include/rni_param.v` | 增加统一派生参数、AMBA 合法取值与 AxSIZE 约束 | 顶层用户参数名与默认 128/256 值 |
| `rtl/include/rni_defines.v` | 将 bank 宽度从 AXI 宽度解绑，定义 slot/line 常量 | 四 slot、64B line 语义 |
| `rtl/src/rni/rni_wr_buffer.v` | W scatter、DAT gather、可变 DAT 数/DataID | AW/W FIFO 与 B FIFO 接口、DBID/CompAck 协议 |
| `rtl/src/rni/rni_rd_buffer.v` | RXDAT scatter、AXI R gather、可变 AXI 宽度 | 四 bank 存储、R FIFO 接口 |
| `rtl/src/rni/rni_bcount_ctl.v` | 改为按 `AxSIZE`、beat ordinal 和 fragment 计数 | burst 与 entry 生命周期 |
| `rtl/src/rni/rni_segburst.v` | 产生可跨 line 的 byte-range/fragment descriptor | 64B/16B 分段、mask 语义 |
| `rtl/src/rni/rni_datbuf_bank.v` | 仅在端口宏需整理时修改 | 128b canonical bank 宽度 |
| `rtl/src/rni/rni.v` | 确认 parameter 继续完整下传 | 模块层级、链路接口 |
| `rtl/tb/tb_rni.sv`、`rtl/Makefile` | 添加 AMBA 宽度空间的 override 与回归分层 | 默认回归入口 |

`rni_arctrl.v`、`rni_awctrl.v`、`rni_link_ctl.v` 的协议控制不应因本次改动复制或重写；仅在
其传递的 DAT 数量、完成 mask 或计数接口需要参数化时进行最小调整。

## 6. 实施顺序

1. 增加参数契约和 compile/elaboration 断言；默认 `AXI=128 / DAT=256` 必须 bit-exact。
2. 重构 write scatter/gather；先验证同一 line 的 full/partial WSTRB、所有 DAT 宽度。
3. 重构 read scatter/gather；验证 DataID、RespErr、AXI RDATA/RLAST。
4. 重构 `rni_segburst`、`rni_bcount_ctl` 的 `AxSIZE` byte-range 与跨 line fragment 计数。
5. 移除旧的 `AXI=128 / DAT=256` 限制断言，替换为 AMBA 合法配置与每事务 AxSIZE 断言。
6. 增加编译与仿真覆盖，在全部通过后才对外宣称位宽可配置。

每一步都要求默认配置回归通过后再进行下一步，避免同时引入宽度与协议行为变化。

## 7. 验证覆盖

参数契约的编译/elaboration 回归应覆盖 8 个 AXI4 full 合法 data width 与 3 个 CHI 合法
DAT width 的全部 24 个配置点。功能回归按风险分层，而非将实现能力限制为一张项目自定义
矩阵：

| 覆盖类 | 配置或场景 | 重点 |
|---|---|---|
| 基准兼容 | AXI=128、DAT=256 | legacy 默认行为 bit-exact 回归 |
| AXI 最窄端点 | AXI=8、DAT=128/512 | 一个 line 内多 beat、byte strobe、窄 `AxSIZE` |
| AXI 最宽端点 | AXI=1024、DAT=128/512 | 两条 64B line fragment 的重组，以及非对齐首拍的 lane mask |
| CHI 最窄端点 | 任一 AXI、DAT=128 | 一个 line 的四个 DAT、DataID 和 credit 调度 |
| CHI 最宽端点 | 任一 AXI、DAT=512 | 单 DAT 覆盖完整 line、BE/DataCheck/Poison 宽度 |
| 运行时 size | 每种 AXI bus width | 覆盖合法的最小、中间和最大 `AxSIZE`，以及首尾跨 slot/line |

每组都须验证 read/write、INCR/FIXED、partial WSTRB、line 首尾、DataID 顺序、DBID 写流程、
Retry/PCrdGrant、`ExpCompAck`、AXI backpressure、credit=0 和 reset/link-down。

## 8. 风险与准入条件

- DataID 不是简单的 flit 数；实现必须按选定 CHI revision/DAT width 使用规范映射函数。
- 64B line 内的 AXI beat 可能跨 16B slot；在 AXI=1024 且最大合法 `AxSIZE` 时，一个 data
  presentation 可覆盖两个 line，非对齐首拍还含无效 lane。禁止沿用“每 beat 一个 bank”或
  “所有 lane 都是有效数据”的假设。
- CHI DAT 的 BE 必须按完整 DAT width 生成，未覆盖 byte 的 DATA 清零、BE 置零。
- 所有 `TxnID/DBID`、Retry、CompAck 和 L-credit 生命周期必须与 DAT 数量无关；DAT 数量改变
  只能改变 packet scheduler，不能改变 completion ownership。

本方案完成前，`AXI=128 / CHI DAT=256` 是 legacy RNI 唯一已验证组合。
