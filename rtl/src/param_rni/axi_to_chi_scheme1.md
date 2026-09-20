# 方案一：双配置档 AXI-to-CHI RNI 架构与验证方案

> 本文档是方案一的唯一规范源。它取代原先“仅非一致性”的方案一：同一个 AXI
> ingress 可按**已锁存的事务策略**发出非一致性或 OpenNoC 一致性请求。OpenNoC 的
> `rni` 是 coherent RN-I 请求实现，能够访问 cache-coherent memory；本文要求将这项
> 能力纳入 `chi_rni` 的运行时选择。运行时全局开关不得改变在途事务的语义。

术语版本固定如下：**V1** 是本文取代的仅 `NONCOHERENT` 基线；**V2** 是本文定义的双
profile 规范。除非明确标注为 V1 行为，所有“必须”均指 V2。

## 1. 目的、范围与能力边界

方案一将 C/C++ Proxy/AXI master BFM 的 AXI4 `AR/AW/W` 转换为客户 OpenNoC 的 CHI
`REQ/DAT`，并将 `RSP/DAT` 转回 AXI `R/B`。它同时支持两个请求配置档（profile）：

| Profile | 用途 | 请求集合（V2 初始集） | 当前实现基础 |
|---|---|---|---|
| `NONCOHERENT` | MMIO、非共享 DRAM、DMA/direct access | `ReadNoSnp`、`WriteNoSnpPtl`，受限条件下 `WriteNoSnpFull` | `chi_rni_core.sv` + `rni_link_ctl` 直连 OpenNoC `chi_xp_channel` |
| `OPENNOC_COHERENT` | cache-coherent memory | `ReadOnce`、`WriteUniquePtl`，以及其已验证的 DAT/response 流程 | 复用/抽取 `rtl/src/rni` 的 coherent request、retry、DBID 与 CompAck 逻辑 |

`OPENNOC_COHERENT` 直接采用现有 `rtl/src/rni/rni.v` 的 coherent RN-I 请求语义：它能
通过 `ReadOnce`、`WriteUniquePtl`、RetryAck/PCrdGrant、DBID、DAT 和可选 CompAck 流程
访问由 HN 管理的一致性内存。当前顶层没有 RX SNP 端口，这只表示本次集成必须按该接口
能力配置 HN 的 snoop 交互；它不否定该 RNI 对 cache-coherent memory 的访问能力。若后续
目标需要 RNI 直接接收/服务 SNP、维护本地 cache state、DVM、cache maintenance 或
atomic/exclusive，则须扩展接口、状态机和验证矩阵。

对同一物理地址，软件不得在无 ownership transfer 的情况下配置或使用多个 region type；
coherent system 必须保持该地址的一致属性。[Arm AMBA LTI, A.4](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/IHI0089A_amba_lti.pdf)

## 2. 为什么不采用单一运行时开关

只用 elaboration parameter 不能在同一 AXI port 混合 MMIO 与 shareable memory；只用一个
live CSR 或 input pin 又会使在途 retry、DBID 和 response 在模式切换后被错误解释。AXI
`AxCACHE` 是 cache hint，`AxPROT` 是访问属性；二者均不用于本桥的 region type、profile
或 CHI 属性选择。

采用以下三层模型：

1. **静态能力参数**决定综合出的硬件能力，而非每笔模式：`ENABLE_NONCOHERENT`、
   `ENABLE_COHERENT_REQ`、`ENABLE_POLICY_CSR`、表项数、TxnID/queue 深度和支持 opcode。
   这些值 reset 后不可改变。
2. **安全/特权 CSR 区域策略表**以地址（可选叠加 requester/StreamID 和安全域）唯一决定
   region type、profile 和 CHI 请求属性。它是生产环境的权威选择器。
3. **每笔事务快照**在 AR/AW handshake 锁存 CSR 解析结果，并在 transaction 生命周期内
   保持不变。AXI `AxCACHE/AxPROT` 即使在顶层接口存在，也一律忽略，不得影响该快照。

因此固定采用“CSR 按地址选区域”的模型，而非“全局模式寄存器”“纯运行时参数”或
“AXI 属性推断”。桥只能按命中的 CSR region 生成 CHI 语义。

## 3. 系统架构

```text
AXI AR/AW/W
     |
     v
+----------------------- unified AXI-to-CHI RNI -----------------------+
|  [spine] AXI admission -> CSR region resolver -> policy snapshot    |
|              |  immutable txn_profile {profile, access_class,       |
|              |    opcode, memattr, snpattr, allow_retry,            |
|              |    exp_compack, ns, order, qos, epoch}               |
|              v                                                       |
|  axi_fragment_adapter -> 共享 parent/child 表                        |
|              |                    |                                  |
|              |                    v                                  |
|              |     shared line_data_plane + chi_dat_adapter          |
|              |       64B logical line / 16B canonical slot           |
|     +--------+--------------------------+                            |
|     |                                   |                            |
|     v                                   v                            |
|  nc_request_engine              coherent_request_engine              |
|  Read/WriteNoSnp 完成 FSM        ReadOnce / WriteUniquePtl           |
|  class-specific request rules     Retry/PCrdGrant + DBID/CompAck      |
|     |                                   |                            |
|     +----------------+------------------+                            |
|                      v                                               |
|   common TxnID/DBID map, response reorder, error handling           |
+--------------------------------------+-------------------------------+
                                       v
                    one raw OpenNoC profile shim / link-credit owner
                                       v
                              OpenNoC HN / NoC
```

Device 与 NonCacheable 不是两个 engine：二者共享同一无-retry 完成 FSM（读 `CompData`、写
`DBIDResp->DAT->Comp`），只在分段器与 `WSTRB=0`/BE 规则上按 `access_class` 分叉。

### 3.0 时钟与复位契约

AXI、CSR、RNI、XP 与 HNF 处于同一个时钟域。`RST` 为异步置位复位；所有状态机、FIFO、
credit counter、parent/child/TxnID/DBID 表和 policy shadow/active bank 必须在本时钟域同步
释放复位。不得在该版本引入跨时钟的 synchronizer 或 async FIFO。link-down 是
`COORDINATED_RESET` 平台事件，不得被当作普通的 link stall。

在 **RNI 内部**必须只有一个 raw CHI link、L-credit 和 NodeID 路径所有者：`rni_link_ctl`
（连同其 `rni_link_handshake`/`rni_lcrd_hdlr`）。它直接连接 OpenNoC `chi_xp_channel` 的一个
本地 P port；XP router 作为链路对端，合法地维护自己的 RX buffer 与 credit 状态。不得把
legacy `rni` 顶层或第二个 link controller 并联到同一 RNI 端口。正确做法是共享 AXI admission、
`axi_fragment_adapter`、parent/child bookkeeping、
`line_data_plane`、`chi_dat_adapter` 和唯一的 `rni_link_ctl`；从 legacy RNI 抽取 coherent
request engine 所需的逻辑分段、Retry、DBID 与 CompAck 控制。不得把 legacy 固定宽度的数据
路径直接移入 coherent engine。

首版全局 CHI parameter bundle 以既有 RNI 默认值为基准，固定 `CHIE_NID_WIDTH=11`。XP 的
TargetID 提取、XY/port 路由切片和所有 `REQ/RSP/DAT/SNP` flit width 必须参数化为该 bundle；
HNF 也必须以同一 `CHIE_NID_WIDTH` elaboration。不得在 RNI--XP--HNF 链中进行隐式 NodeID
截断、补零或 flit 宽度转换。

首版采用过渡路由编码：CHI flit 中的 `NodeID` 字段仍为 11 bit，但 XP 仅以
`NodeID[6:0] = {x[2:0], y[2:0], local_port[0]}` 路由；所有有效 source/target NodeID 都必须
静态满足 `NodeID[10:7]==0`。这是接通现有 8x8x2-port XP 拓扑的限制，不是对 11-bit 全空间的
支持。扩展拓扑前，Gate 0 必须对 RNI、HNF 和所有可达 target NodeID 断言该限制。

当前 `chi_rni_core` 的每 AXI ID 单 active parent、单 live child/parent、写数据先收齐再
发 CHI、以及 final `R/B` handshake 后释放 ID 的约束保持不变。profile 必须在 AR/AW
handshake 时写入 parent，并随 child、retry/reissue、DBID 和 response 一起保存；W 只能
继承其 AW parent 的 profile，禁止重新查表。

### 3.1 OpenNoC coherent 数据流的复用基线

`rtl/src/rni/rni.v` 已给出 coherent profile 的实装结构：`rni_axi_bus` 汇集 AXI 五通道；
`rni_arlink`/`rni_awlink` 各以两项 FIFO 接收地址；`rni_segburst` 将 burst 组织为 64B
line、四个 16B slot 的 `ctmask/pdmask/bc_vec`；读/写表默认各 32 项，默认 AXI/CHI DAT
宽度分别为 128/256 bit（`rtl/include/rni_param.v`）。

读路径为 `AR -> arlink -> segburst -> arctrl -> link_ctl TXREQ -> ReadOnce -> RXDAT ->
rd_buffer -> AXI R`。`rni_arctrl` 用 AR entry index（MSB=0）作为读 TxnID，保存同 AXI ID
依赖、DataID completion mask 和 RetryAck 所需的 PCrdType；`rni_misc` 在收到 PCrdGrant
后释放重发。`rni_rd_buffer` 将 RXDAT 按 TxnID/DataID 放入四 bank DAT RAM，完成后经
`rp_fifo/rd_fifo` 重组为 AXI R，故 RREADY backpressure 不会倒灌到 CHI link。

写路径为 `AW -> awlink -> segburst -> awctrl`，以及 `W -> wr_buffer wd_fifo ->
aw_req_fifo -> 4 x 128-bit bank`。写 TxnID 为 AW entry index（MSB=1）；`rni_awctrl`
发出 `WriteUniquePtl` 后匹配 `DBIDResp/CompDBIDResp`。获得 DBID 且数据就绪时，
`rni_wr_buffer` 以 `NonCopyBackWrData` 发送 256-bit DAT 的低/高半；收到最终 Comp，且在
要求时发出 CompAck 后，才经 BRSP FIFO 产生 AXI B 并释放 entry/bank。

`rni_link_ctl` 必须是 RNI 内唯一的 CHI 链路所有者：它集中 RXRSP/RXDAT、L-credit return、
TXREQ 仲裁以及 TXDAT/TXRSP 发送门控；`rni_link_handshake` 和 `rni_lcrd_hdlr` 分别管理
link RUN 与每通道 credit。它直接与 `chi_xp_channel` P port 相连；双 profile 只改变 entry
已锁存的 packet/profile state，不能复制或旁路这条 RNI link/credit 数据流。

写 parent 从 AW handshake 起依序经历 `WCOLLECT` 阶段：在 AXI4 W 无 WID 的约束下，按
AW 受理顺序收齐并验证该 parent 的全部 W beat/WLAST，随后才可进入 DBID/DAT 相关阶段。
`WCOLLECT` parent 已锁存 profile/epoch，属于 CSR commit、line hazard 和 reset 统计的
outstanding parent，不能因尚未发出 CHI request 而忽略。

### 3.1.1 参数化共享数据面

V2 的两个 profile 共用一套参数化数据面，接口宽度是 elaboration-time contract，不能由
policy CSR 或运行时 profile 改写：AXI4 full `WDATA/RDATA` 取 AMBA 合法离散值
`{8,16,32,64,128,256,512,1024}` bit；CHI `DAT.DATA` 取 `{128,256,512}` bit。64B line 与四个
16B canonical slot 是本 RNI 的内部逻辑存储布局，不是 AXI 接口限制。

`axi_fragment_adapter` 以 `AxADDR/AxSIZE/AxBURST`、AXI beat ordinal 和 byte lane（写为
`WSTRB`）生成 `{parent_id, beat_id, fragment_id, line_addr, line_byte_offset, byte_count,
byte_mask}`。一个 AXI data-bus presentation 最多覆盖两条 64B line。AXI 非对齐只影响 burst
首拍：首拍未选 lane 不是访问数据，后续拍按自然边界对齐。`line_data_plane` 仅按该规范化
fragment scatter/gather canonical slot 与 error metadata；它不解释 profile、opcode、retry 或
DBID 生命周期。`chi_dat_adapter` 仅负责按 elaborated CHI DAT width 进行 DATA/BE/DataID 的
pack/unpack 和完整 DAT width 的错误/byte-enable 处理。

对于读，所有 fragment 返回后才允许 `line_data_plane` 为该 `beat_id` 产生一个 AXI R beat；
对于写，只有该 beat 的全部有效 byte 已吸收，才允许相应 engine 推进 request/DAT 状态。这样
AXI 宽度适配、跨 line 与 DAT 宽度变化不会复制到两个 profile engine 中。

### 3.1.2 参数化数据面的代码实施契约

本节定义将当前 `AXI=128 bit / CHI DAT=256 bit` 固定数据面升级为完整参数化数据面时必须
同时完成的代码工作。不得通过单独删除 `rni.v` 的宽度断言、增加局部 `generate` 分支，或
继续让 write bank 宽度跟随 AXI bus width 来声明支持非默认宽度。

#### 3.1.2.1 参数、派生常量与静态约束

`rni_param.v`/`rni_defines.v` 必须提供或等价实现以下唯一派生关系；所有数据面模块必须引用
同一组定义，不得各自计算不同版本：

```systemverilog
RNI_LINE_BYTES        = 64;
RNI_SLOT_BYTES        = 16;
RNI_SLOT_COUNT        = RNI_LINE_BYTES / RNI_SLOT_BYTES;       // 4
RNI_AXI_BYTES         = AXI4_AXDATA_WIDTH_PARAM / 8;
RNI_CHI_DAT_BYTES     = CHIE_DATA_WIDTH_PARAM / 8;
RNI_CHI_DATS_PER_LINE = RNI_LINE_BYTES / RNI_CHI_DAT_BYTES;    // 4/2/1
RNI_SLOTS_PER_DAT     = RNI_CHI_DAT_BYTES / RNI_SLOT_BYTES;    // 1/2/4
```

elaboration/static assertion 至少检查：

- AXI data width 属于 `{8,16,32,64,128,256,512,1024}`，CHI DAT width 属于
  `{128,256,512}`，两者均可整除为 byte 且为 2 的幂；
- `CHIE_BE_WIDTH_PARAM == RNI_CHI_DAT_BYTES`；
- line 固定 64B、slot 固定 16B，`RNI_SLOT_COUNT==4`；
- 每笔事务 `AxSIZE <= $clog2(RNI_AXI_BYTES)`；
- AR/AW entry、parent/child/fragment table、TxnID slot 和 DBID route 的深度互相满足容量约束；
- fragment descriptor 的 `beat_id/fragment_id/byte_count` 位宽能表达配置允许的最大 burst；
- DataID 位宽能无歧义表达所选 CHI revision 和 DAT width 的全部合法 ordinal。

`rni_scheme1_static_assert.v` 负责合法参数空间；真实 `rni` 顶层的默认宽度 guard 只能在本节
全部功能 Gate 通过后移除。静态 24 组合通过不等于真实数据面已经支持 24 组合。

#### 3.1.2.2 AXI beat 地址与 fragment descriptor

新增 `axi_fragment_adapter`，或将 `rni_segburst` 重构为具有等价职责的模块。它不能再只输出
4-bit `ctmask/pdmask/lsmask` 和固定 slot beat count，而须为每个 AXI beat 生成 1 至 2 个
规范化 line fragment：

```text
fragment_desc = {
  parent_id, beat_id, fragment_id, direction,
  line_addr, line_byte_offset, beat_byte_offset,
  byte_count, line_byte_mask[63:0], beat_lane_mask[AXI_BYTES-1:0],
  first_fragment, last_fragment, last_beat
}
```

其中 `line_addr` 64B 对齐；`line_byte_offset` 是该 fragment 在 line 中的起点；
`beat_byte_offset`/`beat_lane_mask` 定义数据在 AXI `WDATA/RDATA` 中的位置。对每个 byte，AXI
lane 的权威计算为 `absolute_byte_address % RNI_AXI_BYTES`，不能由 slot index 或总线宽度分支
猜测。

AXI INCR 非对齐首拍使用 AMBA byte-lane 规则。设 `B=1<<AxSIZE`，
`AB=AxADDR & ~(B-1)`：

```text
beat_addr(0)  = AxADDR
beat_bytes(0) = B - (AxADDR - AB)
beat_addr(i)  = AB + i*B, i>0
beat_bytes(i) = B,        i>0
```

FIXED 的每拍地址和 lane 集保持不变；WRAP 必须检查合法长度和对齐，并按 wrap boundary 计算，
不支持时必须在 admission 返回错误，不能按 INCR 静默执行。随后将每拍实际 byte interval 在
64B boundary 处分割；因最大 AXI bus 为 128B，一个 data-bus presentation 最多生成两个 line
fragment。

fragment 必须满足以下不变量：

- 同一 beat 的 fragment 地址集合互斥，且并集精确等于该 beat 的实际请求 byte 集；
- fragment 不跨 64B line，不扩展非对齐首拍未选择的 lane；
- `beat_id` 决定 AXI 可见 R beat/W beat，`fragment_id` 不能被当成额外 AXI beat；
- descriptor 必须通过 ready/valid 接口排队；descriptor 或目标 line context 无空间时反压，
  不能接受 AXI beat 后再报告内部资源不足。

#### 3.1.2.3 Canonical line storage 与 byte ownership

`line_data_plane` 固定为每 line `4 x 128-bit` canonical slot，不随 AXI 或 CHI width 改变。
每个 live line context 至少保存：

```text
{owner_parent, owner_child, line_addr,
 data[511:0], valid_mask[63:0], dirty_mask[63:0], error_mask[63:0],
 required_mask[63:0], received_dat_mask, sent_dat_mask}
```

`rni_datbuf_bank` 可以继续作为四个 128-bit bank 的物理实现，但必须支持 byte write enable 和
byte merge；禁止继续以整 slot 覆盖 partial RXDAT/WSTRB。owner lookup 必须命中唯一 active
context，不能只截取 TxnID 低位后直接写 RAM。

读、写 byte ownership 分别定义：

- read fragment 的 `required_mask` 并集必须精确等于 AXI 请求 byte 集，每个 byte 只有一个
  fragment owner；
- write fragment 的请求 envelope 来自地址/size/burst，实际 enabled 集为
  `beat_lane_mask & WSTRB`；所有 child 的 `BE=1` 地址并集必须精确等于所有 AXI
  `WSTRB=1` 地址并集；允许 envelope 内有洞；
- 未请求/未使能 byte 的 canonical DATA 保持 0 或旧值均不可被观察，输出到 CHI/AXI 时必须
  由 mask 屏蔽；发往 CHI 的 `BE=0` byte，其 DATA 强制为 0。

若实现缓存原始 W beat，物理容量按 `最大 beat 数 x RNI_AXI_BYTES` 的 DATA 加同宽 WSTRB
计算；若实现直接 scatter，容量按并发 line context 的 64B DATA/valid metadata 计算。方案和
RTL 参数必须明确选择一种 layout，不能用“逻辑请求 byte 数”替代实际存储容量。

#### 3.1.2.4 AXI W scatter

`rni_wr_buffer` 的 W ingress 必须从“一个 beat 写一个 AXI-width bank”改为逐 byte scatter：

1. W 仍按 AW FIFO 队首绑定，因为 AXI4 W 无 WID；
2. 使用当前 parent 的 `beat_id` 和全部 fragment descriptor 计算每个有效 WSTRB lane 的
   absolute address、line context、slot 和 slot byte；
3. 对每个 byte 执行 `DATA` merge，并设置 `valid_mask/dirty_mask`；WSTRB 在该 beat 合法 lane
   之外置位属于 AXI protocol error；
4. 一个 W beat 跨两条 line 时，必须在拉高 `WREADY` 前原子保证两个 fragment/context 均能
   接收；禁止只写第一条 line 后再因第二条 line 满而丢失半拍；
5. 用 AWLEN/AxSIZE/beat ordinal 判定预期拍数，并校验 WLAST early/late；WLAST 不能继续只被
   解码而不参与错误判断；
6. 全部预期 W beat 被吸收并完成 WLAST 校验后，执行 `WCOLLECT -> FRAGMENT_FINALIZE`，冻结
   child/required-byte mask，之后才能进入 `ISSUE_REQ`。

最后一条是强制边界：当前 `rni_awctrl` 可在 W 数据收齐前选择新 TXREQ；参数化实现不得在
不知道最终 WSTRB、空 fragment 和 required DAT mask 时预发 CHI write request，除非所选客户
profile 明确证明这种预发对所有 partial/全零 WSTRB 形状合法。

#### 3.1.2.5 Canonical line 到 CHI TXDAT gather

新增 `chi_dat_adapter`，或把等价逻辑从 `rni_wr_buffer` 中独立出来。它按 `dat_ordinal` 从
canonical line gather DATA/BE：

| CHI DAT width | DAT/64B line | slot/DAT | 合法 DataID 候选集 |
|---:|---:|---:|---|
| 128 | 4 | 1 | `00,01,10,11` |
| 256 | 2 | 2 | `00,10` |
| 512 | 1 | 4 | `00` |

表中编码必须由项目锁定的 CHI revision/profile 再确认；RTL 必须使用版本化纯函数
`dat_ordinal_to_dataid()`，不得把 `00/10` 写死。对应反函数
`dataid_to_dat_ordinal()` 必须能检测非法编码。

每个 write child 保存 `required_dat_mask` 和 `sent_dat_mask`，替换
`two_packets/current_half` 一类 CHI=256 专用状态。只有真实
`TXDATVALID && link/credit accept` 才设置对应 sent bit；全部 required bit 发送后才产生
`dat_done`。改变 DAT/line 数量不得改变以下生命周期：

- completion record 仍以 original TxnID 查找；
- data-route `{DBID, completer}` 至少保持到最后一个 required DAT handshake；
- `ExpCompAck=1` 时 data-route 继续保持到 CompAck handshake；
- AXI parent、AW ordering 和 hazard token 保持到最终 `BVALID && BREADY`。

#### 3.1.2.6 CHI RXDAT scatter 与 DataID 校验

RXDAT 必须先经过统一 `chi_dat_adapter`，再写 canonical line：

1. 用完整 active ownership lookup 校验 profile、direction、TxnID、entry valid、opcode 和
   当前 child state；
2. 用 `dataid_to_dat_ordinal()` 校验 DataID，并确认它属于该 child 的
   `expected_dat_mask`；
3. duplicate、未知、与 DAT width 不匹配或已完成 child 的 DataID 均为 protocol error，
   不得覆盖已经接收的 byte，也不得推进完成 mask；
4. 将 RXDAT 的 16/32/64 个 byte 按 BE scatter 到对应 canonical slot；每个覆盖 byte 的
   RespErr 写入 `error_mask`；需要但 BE=0 的 read byte 必须形成 data/protocol error；
5. 最后一个 required DataID/byte 到达前，不得报告 fragment complete 或释放 child/TxnID。

`rni_arctrl` 当前只观察 `DataID[1]` 的 completion 公式必须删除，改由 adapter 输出
`fragment_complete`、`received_dat_mask` 和归属明确的 error event。

#### 3.1.2.7 Canonical line 到 AXI R gather

读路径增加 beat assembly table，至少保存：

```text
{parent_id, beat_id, expected_fragment_mask, done_fragment_mask,
 rid, last, rdata[AXI_WIDTH-1:0], byte_valid[AXI_BYTES-1:0],
 byte_error[AXI_BYTES-1:0]}
```

fragment complete 时，按 descriptor 的 absolute address/`beat_byte_offset` 将 byte gather 到
对应 AXI lane。一个 AXI beat 跨两条 line 时，必须等待两个 fragment 全部完成后只生成一个
AXI R beat。未请求 lane 输出 0；任一请求 byte 的 CHI error、缺失 BE 或可归属 protocol
error按统一规则聚合成该 beat 的 `SLVERR`。`RID/RLAST` 来自 parent/beat ordinal，不来自
fragment 顺序。

R response FIFO 只保存已经装配完成的 beat，并在 `RREADY=0` 时保持 payload 稳定。line
context 可在数据安全复制到 response FIFO 后回收，但 parent、TxnID、same-ID ordering 和
hazard ownership 必须保持到最终 `RVALID && RREADY && RLAST`，不能沿用当前“写入 pending
FIFO 即释放 AR entry”的行为。

#### 3.1.2.8 控制模块和文件修改清单

| 文件/模块 | 强制代码修改 |
|---|---|
| `rtl/include/rni_param.v` | 统一 line/slot/AXI byte/CHI byte/DAT 数派生参数与合法值检查 |
| `rtl/include/rni_defines.v` | write bank 固定为 128-bit slot；增加 64-bit byte mask、descriptor/table 宽度；移除 bank width 跟随 AXI width |
| `rni_scheme1_static_assert.v` | 增加 canonical layout、DataID capacity、descriptor/table/TxnID 容量断言 |
| `rni_segburst.v` / 新 `rni_axi_fragment_adapter.v` | 用 beat/fragment/byte-mask 描述符替换固定 `[5:4]` slot 和 4-bit count 假设 |
| `rni_arlink.v`、`rni_awlink.v` | 排队并传递 descriptor、profile、epoch；ready/valid 覆盖 descriptor 资源 |
| `rni_bcount_ctl.v` | 从固定 slot 旋转计数改为 beat ordinal、fragment count、WLAST/last-beat 校验 |
| `rni_datbuf_bank.v` / 新 `rni_line_data_plane.v` | 固定 4x128-bit canonical storage、byte write-enable、valid/dirty/error mask、唯一 owner |
| `rni_wr_buffer.v` | W byte scatter、跨 line 原子接收、required DAT mask；移除 `4*AXI_WIDTH` bank 和固定低/高 256-bit gather |
| `rni_awctrl.v` | 增加 WCOLLECT/finalize 边界；以 required/sent DAT mask 替换 two-packet 状态；保持 DBID/data-route 生命周期 |
| `rni_rd_buffer.v` | RXDAT byte scatter、beat assembly 和 AXI 8..1024 gather；移除只覆盖 AXI128/256 的分支 |
| `rni_arctrl.v` | 以 expected/received DAT 和 fragment complete 替换 `DataID[1]` 完成逻辑；延迟 parent/TxnID 释放 |
| 新 `rni_chi_dat_adapter.v` | DAT width、DataID、DATA/BE pack/unpack、重复/非法检查的唯一 owner |
| `rni.v` | 实例化/连接 adapter、line plane 和表；全部 Gate 通过前保留默认宽度 guard |
| `file_list_param_rni_tb.f`、`Makefile` | 加入新 RTL/TB，并为每个 width pair 独立 compile/run，避免全局 CHI 宏互相污染 |

`rni_link_ctl` 继续是 RNI 内唯一 raw link/credit owner；本改造只向它提供参数化 TXDAT payload
和经过 ownership validator 的 RXDAT，不得复制 link 或 credit 状态机。

#### 3.1.2.9 Backpressure、错误与守恒断言

资源预留必须覆盖一次 admission 可能需要的 parent、两个 fragment、line context、TxnID、
response reorder 和发送队列；不足时只反压。所有 ready/valid 接口在 stall 时保持 payload
稳定。link-down/credit=0 只暂停发送，不得释放 line、TxnID、DBID 或伪造完成。

错误按阶段处理：

- issue 前地址/size/burst/WLAST/WSTRB 非法：不发 CHI，排空整个 parent 并返回 AXI DECERR
  或项目定义的协议错误响应；
- issue 后 CHI RespErr：关联 R beat/B 返回 SLVERR，同时按协议 drain；
- 可归属的 duplicate/非法 DataID、wrong state/opcode/DBID：标记 owner parent SLVERR 并
  drain，禁止污染其他 entry；
- 无法归属的 TxnID/DataID：隔离 flit、记录 platform protocol event，并进入协调复位策略，
  不得命中新复用的 TxnID。

至少增加以下动态断言：

- 每个 beat 的 fragment byte 集 exact-cover、无重叠、最多两个 line；
- AXI lane、line byte、slot byte 映射一一对应，scatter/gather byte 数守恒；
- `BE=0 -> TXDAT.DATA byte==0`，RX duplicate/非法 DataID 不推进 mask；
- 每个 child 的 DataID 合法且只接收/发送一次，DAT handshake 数等于 required mask popcount；
- TxnID、DBID route、line context 均为单 owner；
- WLAST 与 AWLEN 一致；R/B stall payload 稳定；parent 只完成一次；
- 最终 AXI RLAST/B handshake 前不得释放 parent、same-ID ordering 或 hazard token。

#### 3.1.2.10 分阶段实现与功能准入

当前实现进度（2026-09-18）：已加入 `rni_axi_fragment_adapter`、
`rni_fragment_dispatch`、`rni_line_data_plane` 和 `rni_chi_dat_adapter`。模块级功能仿真已经
覆盖 AXI 8..1024 fragment exact-cover、AXI512 跨 line partial-WSTRB scatter/R gather，以及
CHI DAT 128/256/512 的 4/2/1 DAT pack/unpack。`rni_fragment_dispatch` 保证 child descriptor
与 line context 同周期原子提交。legacy `rni_arctrl/rni_awctrl/rni_rd_buffer/rni_wr_buffer` 尚未
切换到该接口，因此 G1 和 G6 仍未通过，`rni.v` 默认宽度 guard 必须保留。

| Gate | 代码交付 | 必须通过的验证 |
|---|---|---|
| G0 参数契约 | 统一派生参数和 static assertions | 24 个合法 width pair；非法 AXI/CHI/BE/AxSIZE 预期失败 |
| G1 默认兼容 | descriptor/line-plane/dat-adapter 接入默认路径 | AXI128/CHI256 两 profile bit-exact；逐 byte DATA/BE/RDATA 检查 |
| G2 写数据面 | W scatter、可变 DAT gather、required/sent mask | CHI128/256/512 的 4/2/1 DAT；full/partial/all-zero WSTRB；跨 slot |
| G3 读数据面 | RXDAT scatter、DataID validator、AXI gather | AXI 8..1024 lane；DataID 正序/逆序/交错；RespErr；RREADY backpressure |
| G4 跨 line | beat assembly、双 fragment 原子资源 | 非对齐首拍、AXI512/1024、跨 64B；一个 parent beat 只产生一个 R beat |
| G5 压力/错误 | 完整生命周期和错误 drain | credit=0、FIFO/table 满、重复/非法 DataID、wrong TxnID、reset/link-down |
| G6 全矩阵 | 移除默认宽度 guard | 全部 8x3=24 width pair 运行真实 DUT read/write smoke，风险组合深测通过 |

每个 Gate 必须重跑 G0/G1。`tb_param_rni_width_matrix` 的静态抽样和
`tb_param_rni_contracts` 的 24 点 checker 不能替代 G6；G6 要求每个 width pair 分别编译真实
`rni`，至少完成对齐 64B 读写、partial WSTRB、DataID 非自然顺序、R/B backpressure、
TXDAT credit=0 恢复和 RespErr 注入。

### 3.2 Coherent wire contract（首个不可拆分增量）

`OPENNOC_COHERENT` 不是给现有 non-coherent REQ 增加 opcode 位，而是一次完整的 decoded
core↔shim 契约升级。以下接口和状态机必须在同一个 RTL 增量中交付；在它们齐全前不得宣布
coherent profile 可用：

| 方向 | 强制字段/状态 | 规则 |
|---|---|---|
| TXREQ | `opcode`、完整 `MemAttr/SnpAttr`、allocate、`AllowRetry`、`ExpCompAck`、`TxnID`、`NS/Order/QoS` | 所有字段来自 child 的 immutable `req_attr`，`rni_link_ctl` 只负责 flit pack，不得隐式生成 coherent 属性。 |
| RXRSP | `DBIDResp`、`CompDBIDResp`、`Comp`、`RetryAck`、`PCrdGrant`、`RespErr`、`DBID`、`TxnID`、`PCrdType`、completer NodeID | 不在白名单的编码为 protocol error；不得把 RetryAck/PCrdGrant 伪装成 Comp。 |
| TXDAT | `DBID`、原 TxnID、目标 completer NodeID、DataID/BE/DATA | **data-route** `{DBID, completer}` 保留至最后 DAT handshake；它不是 completion record。 |
| TXRSP | `CompAck`、目标 completer NodeID | 必须有独立 valid/ready、raw flit pack 与 TXRSP L-credit；若 `ExpCompAck=1`，data-route 还须保留至 CompAck handshake，child 才可完成。 |

coherent child 在 RetryAck 时锁存 `PCrdType`，保持原 `TxnID/req_attr` 和分段状态；只在
匹配 PCrdGrant 到达后 reissue，且 reissue 的 `AllowRetry=0`。`rni_misc` 式 PCrdGrant FIFO
及 AR/AW 仲裁属于共享控制层，不能由读/写 engine 各自私有实现。

## 4. 策略表与 CSR 契约

### 4.1 区域表

每个有效项使用半开区间 `[base, limit)`，至少包含：

```text
{valid, base, limit, region_type, profile, opcode_policy, memattr_policy, snpattr_policy,
 ns_policy, order_policy, qos_policy, allow_retry_policy, exp_compack_policy, lock}
```

- `region_type` 为 `DEVICE`、`NORMAL_NOCACHE` 或 `NORMAL_COHERENT`；它唯一导出
  `profile` 与 CHI opcode/属性策略。地址是唯一 match key：条目不得重叠；未命中、多个命中
  或所选 profile 未综合时，在 AXI admission 返回整个 parent 的 `DECERR`。
- `NS` 由 region 的 `ns_policy` 固定生成。coherency 不是访问权限；若系统需要独立的地址
  firewall/TrustZone 检查，必须在本模块之外完成，不得重新引入 AXI 属性作为 region match key。
- 顶层即使携带 `AxCACHE/AxPROT`，bridge 也必须忽略它们，且不得因其值产生拒绝、profile
  切换或 CHI 属性变化。解析出的 `region_type/profile`、最终 opcode/MemAttr/SnpAttr/
  Order/AllowRetry 和 `policy_epoch` 都要写入 parent/child trace。

建议从 reset default table 启动；当 `ENABLE_POLICY_CSR=0` 时，此表可由静态参数固化，仍使用
同样的 resolver 和 profile snapshot，避免产生两套事务语义。

### 4.1.1 独立 CHI policy CSR-slave 与 reset 默认表

首版 runtime 配置使用独立的 `policy_csr_chi_slave`，而非 APB。它是 RNI node 内独立于 AXI
request engine 的 CHI Device 从端控制器，与 RNI requester 共用 RNI NodeID 和 P0 local link；
它们不共享 parent/child、TxnID、DBID 或 line-data 状态。

`POLICY_CSR_BASE=64'h0000_0020_0000_0000`、`POLICY_CSR_SIZE=64'h0000_0000_0000_1000`、
`POLICY_CSR_NID` 和该 aperture 的 Device 属性是 reset 后不可更改的 bootstrap 参数，且
`POLICY_CSR_NID == RNI_NID`。CSR 地址窗口严格为
`[POLICY_CSR_BASE, POLICY_CSR_BASE + POLICY_CSR_SIZE)`，即
`[64'h0000_0020_0000_0000, 64'h0000_0020_0000_1000)`；这里的 `SIZE` 不得误写成绝对地址
上界 `LIMIT`。进入 RNI P0 的 RXREQ 先按目标 NodeID 和该固定
address aperture 分流至 `policy_csr_chi_slave`；不得用 active policy table 判断 CSR 请求，否则
会产生配置自身的循环依赖。HN/address-map 必须把该 aperture 路由至 RNI NodeID。

配置发起者为 CPU，经 `virtual side -> axi_bridge_proxy -> axi_master_bfm -> RNI AXI ingress`。
RNI AXI request engine 命中该固定窗口后绕过动态 region-policy lookup，固定生成到自身
`POLICY_CSR_NID` 的 Device CHI 请求；这条 bootstrap 路径本身不允许被 runtime CSR 改写。

CSR 配置的是 policy shadow table，而不是数据、TxnID、DBID、FIFO 深度或 CHI flit 宽度：

```text
POLICY_CONTROL:  commit / clear-error
POLICY_STATUS:   busy / commit-error / active-bank / policy-epoch
REGION[i].BASE:  shadow 区间下界
REGION[i].LIMIT: shadow 区间上界（不包含）
REGION[i].ATTR:  valid / region_type / CHI 属性策略 / lock
```

每个 `REGION[i]` 都可表示一段离散地址区间；多个离散区间使用多个 table entry。reset 时 active
和 shadow bank 从 elaboration-time 的 `RESET_REGIONi_*` 参数装载，例如
`VALID/BASE/LIMIT/REGION_TYPE/ATTR`。这使 SoC 能在不依赖软件首笔配置的情况下启动其默认 memory
map；policy CSR 的固定 bootstrap 地址已如上定义。

CSR 的总线访问粒度固定为单拍、4-byte 对齐、32-bit。由于 policy address 是 64-bit，首版每个
region 至少包含 `BASE_LO`、`BASE_HI`、`LIMIT_LO`、`LIMIT_HI`、`ATTR` 五个 32-bit word（20 bytes）；
实现可按 32-byte stride 预留空间。byte enable 只允许在该 32-bit word 内更新，不支持非对齐、
64-bit 或 burst CSR 访问。

CSR 仅接受如下首版 CHI Device 事务，且固定 `ExpCompAck=0`：

```text
read:   RXREQ ReadNoSnp -> CSR read -> TXDAT CompData
write:  RXREQ WriteNoSnpPtl -> TXRSP DBIDResp
        -> RXDAT NonCopyBackWrData -> byte-enable CSR write -> TXRSP Comp
```

`ReadNoSnpSep`、`WriteDataCancel`、`WriteNoSnpFull`、coherent/atomic/DVM/CMO 与 CompAck 均不在
首版 CSR-slave 范围。RXREQ 必须保存 `SrcID/TxnID/ReturnNID/ReturnTxnID/Size/Addr/Order/MemAttr/
TraceTag`；RXDAT 必须按 `DBID/TxnID/DataID/opcode/BE` 唯一匹配，partial BE 仅更新被选中的 CSR
byte。TXRSP/TXDAT 仅在各自 XP credit 到达时发送。

软件可在运行中修改未 lock 的 shadow entry，并执行 `POLICY_COMMIT`；static capability 参数
（数据/ID 位宽、表深度、支持 opcode、是否综合 coherent engine）不可由 CHI CSR 改写。commit 规则
仍严格遵循 §4.2，且所有已接收 AXI transaction 保持其 admission 时锁存的 policy snapshot。

首版固定 `ENABLE_RETRY=0`：所有已支持 profile 的 `AllowRetry=0`，RNI 不实现 Retry context、
P-Credit/PCrdGrant、RetryAck 或 request replay。HN-F/NoC integration contract 必须保证这类请求不会
收到 CHI Retry；资源不足时必须在请求接收前通过 credit/admission backpressure 流控。任何违反该契约的
Retry 都是 protocol error，不得被当作 Comp/CompData 或静默重发。

### 4.2 安全更新与切换

CSR 只允许 secure/privileged 管理者访问，支持 `LOCK_UNTIL_RESET`。软件写入 **shadow**
bank；`POLICY_COMMIT` 不能直接翻转 live policy，而须执行：

```text
shadow 写入和校验 -> commit 请求 -> 停止受影响区域 admission
-> 等待 AR parent、AW/WCOLLECT parent、CHI child、Retry、DBID、DAT、CompAck 清空
-> 原子切换 active bank / policy_epoch++ -> 恢复 admission
```

简化 V2 可以先实现全局 quiesce；优化版本可按 region/refcount quiesce。若无法在规定
timeout 内排空，commit 返回 busy/error，active bank 不变。任何已接收事务只能使用其
captured epoch，绝不可读取 live CSR。

改变某个 buffer 的 coherent/non-coherent ownership 还需要软件协议：停止该 buffer 的访问、
等待完成/屏障、按系统 cache 路径完成 clean 或 invalidate，再提交新策略并恢复访问。硬件
寄存器切换本身不能使旧 cache line 自动安全。AXI 同 ID 的可观察响应顺序、AW/W 绑定顺序
必须保持；不同 ID 可并发，但同一 cache line 的跨 profile 访问不能在桥内重排。硬件必须
在 AR/AW admission 获取 `line_hazard`（至少覆盖请求的每个 cache line），并在最终 AXI R/B
handshake 后释放；冲突的 profile 在该时间点前只能反压或按文档化规则序列化，不能仅在收到
CHI Comp 时释放。

## 5. Profile 的请求与完成语义

### 5.1 非一致性 profile

保持现有 `chi_rni_core` 语义：读为 `ReadNoSnp`，写为 `WriteNoSnpPtl`；只有完整 cache-line
对齐、全 BE 覆盖且客户 profile 明确批准时才使用 `WriteNoSnpFull`。默认
`AllowRetry=0`，支持 `DBIDResp`、`CompDBIDResp`、`Comp` 及读 `CompData`。shim 的
`MemAttr` 为 device/normal non-cacheable、non-allocate，`SnpAttr=0`。

### 5.2 OpenNoC 一致性请求 profile

初始映射必须以 legacy RNI 已有且验证过的语义为基线，而不是给 non-snoop opcode 加一位：

| AXI 操作 | 初始 CHI request | 必须保留的控制 |
|---|---|---|
| Read | `ReadOnce` | `AllowRetry=1`、RetryAck/PCrdGrant 后重发、正确 `MemAttr/SnpAttr`、allocate hint |
| Write | `WriteUniquePtl` | `AllowRetry=1`、DBID/CompDBIDResp、write DAT、最终 Comp；若 `ExpCompAck=1` 则发送 CompAck |

legacy RNI 目前对读硬编码 `ReadOnce`、对写硬编码 `WriteUniquePtl`，并从 `ARCACHE/AWCACHE`
得到 allocate hint；新引擎必须把这些值变为 profile resolver 的明确输出，而不能继续硬编码。

V2 首版固定 `ENABLE_EXP_COMPACK=0`：所有 coherent 读、写请求的 `ExpCompAck` 均为 0。读不
产生 CompAck，也不产生读 DBID；写在最终 Comp 后进入 AXI B 流程。§6.1 的 DBID/data-route
生命周期只适用于写 child。未来如需启用 `ExpCompAck=1`，必须作为独立 capability 增量，同时
实现并验证 RNI TXRSP.CompAck、RSP channel credit、DBID route 延寿与 HNF MSHR retire。

是否扩展为其他 `Read*`/`Write*` opcode、non-temporal、ordered request 或 full-line write，
必须逐项由客户 HN capability matrix 批准并增加 response/retry/CompAck 状态机。

`WriteUniquePtl` 使 RN 成为该 line 的 Unique 所有者。本 RNI 从不缓存/保留该 line 且无
RX SNP，因此 HN 必须按“此 RN 写完即弃、永不作为 snoop 目标”配置，否则后续对同 line 的
snoop 会指向一个无法响应的节点；这是 §8“HN snoop 配置证明”的具体内容。

coherent profile 的 shim 也必须随 opcode 改变 REQ pack、MemAttr/SnpAttr、AllowRetry，以及
RSP/DAT 白名单；现有 non-coherent shim 把 `AllowRetry` 固定为 0，不能直接复用为 coherent
wire profile。任何不在该 profile 的 response、未知 TxnID/DataID、非法 DBID 或不匹配的
completion 都是 protocol error，保留 credit 后上报并使关联 AXI parent 以 `SLVERR` 完成。

`ExpCompAck=1` 时，最终 `Comp` 仅表示可进入 CompAck 阶段，不能释放 completion record、
TxnID、data-route 或 AXI B；只有 TXRSP `CompAck` 被对端接收后才允许完成。因为 CompAck
要使用 response credit，TXRSP 队列满/credit 为零时必须对 completion state 施加背压，而不能
丢弃或以 B 提前完成。

### 5.3 运行时选择到 RNI 状态的精确映射

在 AR/AW handshake，`policy_resolver` 的输出必须写入对应 AR/AW entry，而非仅写入一个
全局寄存器：

| entry 字段 | `NONCOHERENT` | `OPENNOC_COHERENT` |
|---|---|---|
| read opcode | `ReadNoSnp` | `ReadOnce` |
| write opcode | `WriteNoSnpPtl` / 合法时 `WriteNoSnpFull` | `WriteUniquePtl` |
| retry state | 禁用，`AllowRetry=0` | 启用，保存 PCrdType，等待 PCrdGrant 后 reissue |
| write completion | DBID/DAT/Comp；不发 CompAck | DBID/DAT/Comp；V2 首版不发 CompAck |
| segment/data bank | profile 专属的精确 non-snoop request 映射 | profile 无关的 `axi_fragment_adapter`、64B/16B canonical slot、`line_data_plane` 与 `chi_dat_adapter`；coherent 仅保留逻辑 `ctmask/pdmask/bc_vec` |
| trace | profile、epoch、最终属性 | 同左，另记录 retry/DBID/CompAck 状态 |

`policy_epoch`、profile、opcode、MemAttr/SnpAttr、AllowRetry、ExpCompAck 和 security
属性必须随 entry 经过 retry、DBID、DAT 与 B/R completion 全程保留。CSR commit 只能阻止
新 entry 采用旧策略；不得修改既有 AR/AW entry，也不得要求 `rni_link_ctl` 在一个 link epoch
中重新解释已进入 TX/RX 流水线的 flit。

`policy_resolver` 的固定输出（在 AR/AW admission 锁存进 entry）为：

```text
{profile, access_class, opcode, memattr, snpattr, allow_retry,
 exp_compack, ns, order, qos, epoch}
```

engine 分派规则固定为：`profile==NONCOHERENT` 进入 `nc_request_engine`，`access_class`
（`DEVICE` 或 `NOCACHE`）只选择该 engine 的分段器与 `WSTRB/BE` 规则，不改变完成 FSM；
`profile==OPENNOC_COHERENT` 进入 `coherent_request_engine`，`access_class` 对该路径无意义、
必须固定为保留值并由 Gate 0 断言。分派发生在 admission 且随 `txn_profile` 全程锁存，禁止在
child 中途改换 engine。

### 5.4 AXI sideband 与 policy 输入契约

V2 policy 的唯一输入是地址及已定义的集成 sideband `requester_id/security_domain`。当前
`chi_rni` 即使后来暴露 `AxCACHE`、`AxPROT` 或扩展 sideband，它们也不是 policy 输入：bridge
在 AR/AW handshake 不捕获、不检查且不使用这些值生成 CHI。`AxDOMAIN` 不属于本 AXI4
接口契约。

顶层仍须冻结 `requester_id/security_domain` 的来源、位宽和 CDC；未定义输入不得用于推断
security、profile 或 CHI 属性。

### 5.5 每 model 的请求与完成 FSM

四个 FSM 全部挂 §7.1.1 的统一 engine 接口；nc 读写 FSM 由 Device/NonCacheable 共用，仅
`SEGMENT`/`WCOLLECT` 按 `access_class` 分叉；coherent 读写 FSM 独立。

```text
nc read FSM（ReadNoSnp，class ∈ {DEVICE, NOCACHE}）
  ADMIT -> SEGMENT -> ISSUE_REQ -> WAIT_DAT -> R_RESP -> DONE
    ADMIT:     AR handshake、CSR region 解析与锁存、parent/child 分配
    SEGMENT:   按规范化 fragment 形成精确 non-snoop child；class=NOCACHE 可合并合法 child。
               一个 AXI data-bus presentation 可映射至最多两个 64B line fragment。
    ISSUE_REQ: ReadNoSnp，AllowRetry=0
    WAIT_DAT:  按 DataID mask 收 CompData DAT，全部到齐才进 R_RESP
    R_RESP:    按 AXI beat 序回 R，末 beat RLAST，释放 TxnID/parent

nc write FSM（WriteNoSnpPtl，class ∈ {DEVICE, NOCACHE}）
  ADMIT -> WCOLLECT -> SEGMENT -> ISSUE_REQ -> WAIT_DBID -> SEND_DAT -> WAIT_COMP -> B_RESP -> DONE
    WCOLLECT:  收齐 AW 对应全部 W/WLAST；class=DEVICE 的 WSTRB=0 保留全 0 BE child，
               class=NOCACHE 的 WSTRB=0 不产生 child
    ISSUE_REQ: WriteNoSnpPtl，AllowRetry=0
    WAIT_DBID: DBIDResp/CompDBIDResp（RespErr=OK），锁存 DBID+completer
    SEND_DAT:  TxnID=DBID、DBID=original_txnid；最后 DAT 后（无 ExpCompAck）释放 data-route
    WAIT_COMP: 校验 DBID 字段匹配，记录 comp_done
    B_RESP:    全部 child 完成后回单一 B，释放 completion record/TxnID/parent

coherent read FSM（ReadOnce，ExpCompAck=0）
  ADMIT -> SEGMENT(logical 64B/16B) -> ISSUE_REQ(AllowRetry=1)
     -> [ RetryAck -> WAIT_PCRD -> REISSUE(AllowRetry=0) ]*
     -> WAIT_DAT(CompData，DataID mask) -> R_RESP -> DONE
    RetryAck 锁存 PCrdType，保持 TxnID/req_attr/分段；PCrdGrant 后 reissue 同一 TxnID

coherent write FSM（WriteUniquePtl）
  ADMIT -> WCOLLECT -> SEGMENT(logical 64B/16B) -> ISSUE_REQ(AllowRetry=1)
     -> [ RetryAck -> WAIT_PCRD -> REISSUE(AllowRetry=0) ]*
     -> WAIT_DBID -> SEND_DAT -> WAIT_COMP -> [ExpCompAck=1: SEND_COMPACK] -> B_RESP -> DONE
    ExpCompAck=1 时 Comp 只进 CompAck 阶段，data-route/TxnID/completion record 保留至
    CompAck handshake；TXRSP credit=0 时对 completion state 背压
```

## 6. 事务、流控与错误规则

1. 一个 AXI AR/AW handshake 建立一个 parent；先验证 burst、地址范围、安全域、策略表和
   资源，再分配 profile snapshot。被拒绝的 parent 返回 `DECERR`，不得发 CHI flit。
2. 一个 parent 可分为多个 child。child 保存 `parent_id`、TxnID、地址/Size、映射、
   `txn_profile`、`policy_epoch`、DBID、retry state 和最终 response 期望；关联的 fragment
   描述符保存 `beat_id/fragment_id/line_byte_offset/byte_count/byte_mask`。一个 AXI data-bus
   presentation 最多生成两个 64B line fragment，且读路径必须在其 fragment 全部返回后才产生
   一个 AXI R beat。TxnID 直到最终 DAT/response/CompAck（如适用）完成才可复用。
3. AXI `INCR/FIXED`、4KB、对齐、WRAP/exclusive 拒绝与 byte-lane/BE 规则沿用 V1 非一致性
   方案的保守定义，要点内联如下：INCR 首末字节必须位于同一 4KB page；Device 与 FIXED 的
   beat 必须按 `beat_bytes` 自然对齐，否则 `DECERR`；`WRAP`、exclusive/lock 在 admission
   直接拒绝；byte-lane 采用低地址到低 lane 映射，`BE=0` 的 lane 其 DATA 置零；`WSTRB=0`
   按访问类别分界（Device 保留全 0 BE 的 write child，Normal 为 no-op）。`W` 没有 WID，
   必须按 AW handshake 顺序绑定，不能按 WDATA 重新选择 profile。
4. 同 AXI ID 至多一个 active parent；R/B 在该 ID 内保序。profile 合流点必须有 response
   reorder/ownership 表，不能因 coherent 与 non-coherent engine 独立完成而破坏 AXI 顺序。
5. raw shim 仅在 link active 且对应通道有 credit 时发送。V2 的
   `LINK_LOSS_POLICY=COORDINATED_RESET`：任何有 outstanding 的 link-down 都是平台故障，
   外部编排器必须同时 abort HN transaction 并对本 RNI 施加 AXI reset；在 reset 前不得清表、
   复用 TxnID/DBID 或接受新 AR/AW。无 outstanding 时才允许重建 credit epoch。该版本不支持
   autonomous relink/retry；若要支持，必须定义远端取消协议和不可 ABA 的 transaction tag。
6. AXI barrier 若在启用的上游接口出现，必须按 AXI 的 `AxID/AxBAR/AxPROT` 规则
   成对保持和映射，或在 admission 明确 `DECERR`；不得静默降级。[AXI barrier rules](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/IHI0022H_amba_axi_protocol_spec.pdf)

### 6.1 TxnID 与 DBID 生命周期

所有 profile 共用一个 CHI TxnID namespace，编码固定为：

```text
TxnID = {profile_bit, direction_bit, slot}
profile_bit: 0 = NONCOHERENT, 1 = OPENNOC_COHERENT
direction_bit: 0 = read, 1 = write
slot: 对应 profile/direction 的已分配 child slot
```

`CHI_TXNID_WIDTH >= 2 + ceil_log2(MAX_SLOT_PER_PROFILE_DIRECTION)` 是 Gate 0 静态断言；所有
四个 profile/direction 范围不重叠。legacy RNI 的“MSB=读/写”编码必须适配为以上统一编码，
不得与 nc pool 并存。reissue 永远复用同一 TxnID，且 TxnID 只在最终 DAT/CompAck（如适用）
和 AXI completion 后释放。

DBID 不是全局唯一 key。每个 write child 建立两个不同生命周期的对象：

- **completion record** 以 `{profile, original_txnid}` 为 key，保存
  `{DBID, completer_node_id, dbid_valid, dat_done, comp_done, compack_done}`。所有写 RXRSP
  形状（`DBIDResp`、`CompDBIDResp`、分离的最终 `Comp`、`RetryAck`）均按 original TxnID
  查此记录；最终 `Comp` 还必须校验其 DBID 等于此前绑定的 DBID。completion record 直到
  必需的 `Comp`、可选 CompAck 和 AXI B handshake 都结束后才可回收。
- **data-route** 以 completion record 的引用保存 `{DBID, completer_node_id}`；TXDAT 的
  `TxnID=DBID`、`DBID=original_txnid`，只经该 route 打包。无 `ExpCompAck` 时它在最后 DAT
  handshake 后可释放；有 `ExpCompAck` 时必须延至 CompAck handshake，因为 CompAck 的
  `TxnID=DBID` 且仍需 completer 路由。

因此 DBID 只用于 TXDAT/CompAck 的 packet identifier 和 route，不得用作 RXRSP completion
record 的全局反查 key。表深度必须同时覆盖两 profile 的最大 active write child，满时对 AW
合法背压。

## 7. RTL 实现边界与迁移

### 7.1 模块职责

| 模块 | 责任 |
|---|---|
| `axi_request_capture` | 在 AR/AW acceptance 锁存 address-burst 摘要及已定义的 requester/security sideband；不使用 `AxCACHE/AxPROT`。 |
| `csr_region_resolver` + `policy_ram/csr` | shadow/active 策略表、region type/profile 解析、epoch、commit/quiesce |
| `axi_fragment_adapter` | 按 `AxADDR/AxSIZE/AxBURST`、beat ordinal 与 lane mask 生成规范化 line fragment；非对齐首拍不得扩展未选 byte |
| `line_data_plane` | 64B logical line / 16B canonical slot 存储、fragment scatter/gather、read error metadata 与按 beat 重组 |
| `chi_dat_adapter` | 唯一的 CHI DAT width/BE/DataID pack-unpack；使用 elaborated CHI DAT width，不解释 profile 完成语义 |
| `chi_rni_core` 演进版 | 公共 parent/child/fragment 表、AXI R/B、profile snapshot、共享 TxnID/DBID/reorder 仲裁 |
| `nc_request_engine` | 非一致分段（精确 non-snoop child）+ Read/WriteNoSnp 路径 |
| `coherent_request_engine` | 一致逻辑分段（64B line/16B slot 的 `ctmask/pdmask/bc_vec`）+ ReadOnce/WriteUnique、Retry/PCrd、DBID/CompAck；不得私有 DAT bank |
| `rni_link_ctl` + `rni_link_handshake` + `rni_lcrd_hdlr` | RNI 内唯一 CHI REQ/RSP/DAT pack/unpack、TXRSP、L-credit、NodeID、link owner；直接连接 `chi_xp_channel` 本地 P port。 |
| `profile_hazard_monitor` | 同 line 跨 profile、epoch、非法 response、权限升级的 assertion/trace |

### 7.1.1 统一 engine 接口与模块连接

每个 engine 与共享 spine 之间只允许下列信号组，方向固定：

| 信号组 | 方向 | 载荷 |
|---|---|---|
| `issue_req` | engine -> spine | `req_attr`{opcode, size, addr, memattr, snpattr, allow_retry, exp_compack, ns, order, qos, txnid} |
| `req_retry` | engine -> spine | 复用 txnid；reissue 同一请求且 `AllowRetry=0` |
| `dat_plan` | engine -> shared data plane | `{child_id, direction, logical segment, required_byte_mask}`；不含固定 AXI/DAT width 假设 |
| `push_txdat` | `chi_dat_adapter` -> spine | `{txnid=DBID, dbid=original_txnid, tgtid, dataid, be, data}` |
| `accept_rxrsp` | spine -> engine | `{opcode, txnid, dbid, resp_err, pcrdtype, srcid}` |
| `accept_rxdat` | spine -> `chi_dat_adapter` | `{opcode=CompData, txnid, dataid, be, data, resp_err}`；转换后以 fragment-complete 通知关联 engine |
| `complete` | engine -> spine | `{txnid, axid, rresp/bresp, last}` |
| `error` | engine -> spine | `{txnid, error_kind}` |

模块间数据流固定为：`csr_region_resolver`（在 AR/AW handshake 锁存）-> `axi_fragment_adapter`
-> `chi_rni_core` 公共 parent/child/fragment 表 -> 分派到 `nc_request_engine` 或
`coherent_request_engine`；两个 engine 通过 `dat_plan` 使用同一 `line_data_plane` 和
`chi_dat_adapter`，再经统一 TxnID/DBID map 与 reorder 到 `rni_link_ctl`，并直接连接
`chi_xp_channel` 本地 P port（RNI 内唯一 raw pack/credit/link owner）。`profile_hazard_monitor` 只观察 spine 的
parent/child/fragment/line 状态，不参与数据流。

`accept_rxrsp` 由 spine 按 §6.1 的 active-ownership lookup 分发到唯一 owner engine；
`accept_rxdat` 先按同一 ownership lookup 进入唯一的 `chi_dat_adapter`/`line_data_plane`
上下文，再以 `fragment_complete` 通知 owner engine。未命中、双命中或 DataID 与 fragment
不匹配即 protocol error，不得广播给两个 engine。

双 engine 结构必须遵守三条纪律，否则“一 model 一 FSM”会退化为复制粘贴：

- **统一接口**：每个 engine 对共享层只暴露同一组接口（`issue_req / dat_plan /
  accept_rxrsp / fragment_complete / complete / error`），不得各自私藏 parent/child、
  fragment、TxnID、DAT bank 或 reorder 状态。
- **profile snapshot 不可变**：AR/AW 锁存的 `txn_profile / policy_epoch / opcode` 一经
  写入即随 retry、DBID、DAT 与 B/R 全程携带，engine 不得引用任何 live CSR 或全局模式位。
- **语义分段封在 engine 内，数据 fragment 统一**：非一致的“精确 child”与一致的
  “64B/16B slot”两套 request 表示各自封在 engine 内；共享 fragment 描述符只负责 byte-range
  与 canonical slot 映射。nc 不理解 `ctmask`，coherent 不理解精确 child map，但二者都不得
  自行解释 AXI bus width、DAT width 或 byte lane。

TxnID/DBID 命名空间以 §6.1 为唯一权威；任何 engine 均不得自行假定“MSB=读/写”或将 DBID
当作跨 profile 的全局唯一值。

legacy `rni_awctrl` 的 RSP entry 选择依赖单热轮转指针 `awctrl_rxrsp_ptr_r`，只做
write-MSB/TgtID 基础检查，并不解码 RSP TxnID 低位选 entry，隐含“写 RSP 按 AW 分配序到达”
的假设；迁移到统一 TxnID 后必须改为 §6.1 的 full `{profile, original_txnid}` active-ownership
lookup。不得直接复用这一按序指针逻辑，更不得把它解释为跨 profile 的 completion 匹配机制。

不要把 `rtl/src/rni/rni.v` 当作可与 `chi_rni` 并列实例化的 backend：它同时拥有 AXI 和 raw
链路。可复用的粒度是其 read/write controller、逻辑 segment、retry/PCrd 和 completion
逻辑；固定宽度的 buffer/DAT pack 仅能作为 `line_data_plane`/`chi_dat_adapter` 的迁移参考。
第一实现阶段也可保持现有“每 parent 单 child”限制，先完成 immutable profile 与 policy
commit；增加多 child 并发前必须验证跨 engine 的 TxnID/DBID/reorder 资源仲裁。

### 7.2 已知实现差距

- `chi_rni.sv` 当前没有 CSR，wrapper 的 `ACCESS_DEVICE/FORCE_NONSECURE/ORDER/QOS/Full`
  均是静态参数；还缺 §5.4 所定义的 `requester_id/security_domain` 集成 sideband 契约。
- `chi_rni_core.sv` 仅定义 non-snoop opcode，`chi_rni_defines.svh` 也仅有
  `ReadNoSnp/WriteNoSnp*` 常量；必须增加 §3.2 的版本化 coherent `req_attr`、RXRSP、
  retry/PCrdGrant 与 TxnID 合同。
- `rni_link_ctl` 直连 `chi_xp_channel` 前，必须支持 coherent `req_attr` 的完整 flit pack、
  RXRSP/RXDAT decode、每通道 L-credit 和 NodeID 路由；不得继续采用当前 non-coherent-only 的
  隐式 `MemAttr` 或固定 `AllowRetry=0` 行为。TXRSP CompAck 属于未来 `ENABLE_EXP_COMPACK=1`
  增量，不是 V2 首版连接条件。
- legacy RNI 已实现 coherent memory access 所需的 retry/PCrd 与 CompAck 请求控制；无
  RX SNP 是当前接口能力的集成约束，只有目标要求直接 snoop 服务时才成为扩展项。
- 当前 `chi_rni` link-active/credit/`FLITPEND` 行为与 legacy `rni_link_handshake` 不等价；
  RNI 到 `chi_xp_channel` 的具体时序模型必须按 OpenNoC link contract 冻结，不能以“同为
  LinkActive”假定互通。

## 8. 集成契约

### 8.1 首版全局 CHI parameter bundle

首版 RNI--XP--HNF 直接互联固定使用下表，所有三端必须引用同一套参数；四种 flit width 从
这些字段推导，XP 不执行格式转换。

| 字段 | 首版值 | 说明 |
|---|---:|---|
| `CHIE_REQ_ADDR_WIDTH` | 44 | REQ address width |
| `CHIE_SNP_ADDR_WIDTH` | 41 | SNP address width |
| `CHIE_NID_WIDTH` | 11 | flit NodeID field width |
| `CHIE_TXNID_WIDTH` | 12 | 当前 `chie_defines` 固定字段 |
| `CHIE_DBID_WIDTH` | 12 | 当前 `chie_defines` 固定字段 |
| `CHIE_DATAID_WIDTH` | 2 | 当前 `chie_defines` 固定字段 |
| `CHIE_DATA_WIDTH` | 256 | DAT.DATA width |
| `CHIE_BE_WIDTH` | 32 | `DATA_WIDTH/8` |
| `CHIE_POISON_WIDTH` | 0 | direct-link configuration |
| `CHIE_DATACHECK_WIDTH` | 0 | direct-link configuration |
| `REQ/RSP/SNP/DAT_FLIT_WIDTH` | 143 / 73 / 100 / 382 | 由上述配置和 `chie_defines` 公式推导 |
| `RNI_NID/HNF_NID` | 6 / 0 | 均满足 `NID[10:7]==0` |
| `HNF_MSHR_RNI_NUM` | 0 | RNI 不进入 RNF snoop/sharer 集合 |
| `ENABLE_EXP_COMPACK` | 0 | 首版所有 request 强制 `ExpCompAck=0` |

XP 的 `FLIT_WIDTH` 和 `FLIT_TGT_OFFSET` 分别接四类 flit 的推导值与 CHI 定义的 TargetID LSB。
`XP_ROUTE_NID_WIDTH=7`、`XP_XID_WIDTH=3`、`XP_YID_WIDTH=3`、`XP_LOCAL_PORT_WIDTH=1`；对每一
条 flit 的 TargetID 必须断言高 4 bit 为 0。

### 8.2 RNI P0--XP P0 local-link profile

REQ、RSP、DAT 是三个独立双向 XP channel；每个 channel 的 P0 都有独立 TX/RX flit、FIFO、
credit counter 和 arbitration。SNP network 可服务 RNF，但 RNI P0 SNP port 必须禁用，且 HNF
不得将 RNI NID 写入 `RNF_NID_LIST` 或 sharer vector。

`FLITPEND` 首版固定 disabled：`LINKFLITPEND_EN=0`，XP P0 不传递或采样 PEND，接收条件仅为
`link_run && FLITV && rx_credit_available`。任何打开该 feature 的配置必须同时扩展 XP 和 RNI
两端并重新验证。

link 使用“reset 后一次 bring-up、保持 active 至下次 reset”的 profile，不支持动态 deactivate：

```text
RST assert:        link_run=0, TX credit=0, RX FIFO invalid, FLITV=0
RST sync release:  RNI 与 XP 各自置 TXLinkActiveReq=1
peer request seen: 各自置 TXLinkActiveAck=1
双方 req/ack 均已观察到：link_run=1
link_run 后：接收方按自己的 RX FIFO 空槽数发 initial credit
收到 credit 后：发送方才允许对应 channel 的 FLITV
```

每个 channel 的 credit 是接收端所有权，方向可不对称：XP P0 RX FIFO 深度为 2，因此 XP 向
RNI 宣告的该方向 initial credit 为 2；RNI 接收 RSP/DAT 的 initial credit 由其实际 RX buffer
深度决定。credit 只在接收 FIFO dequeue 时归还；不得在 flit 到达、仲裁获胜或 link active 时
伪造返还。

RSP 与 DAT 均须按下列双向规则连线：

```text
RNI TX<channel>  -> XP RX<channel>_P0 ; XP RXLCRDV_<channel>_P0 -> RNI TX credit
XP  TX<channel>_P0 -> RNI RX<channel> ; RNI RXLCRDV_<channel> -> XP TX credit
```

除 AXI request engine 的 `TXREQ/TXDAT` 和 `RXRSP/RXDAT` 外，P0 还支持 CHI CSR-slave 的反向
从端方向：`XP TXREQ_P0 -> policy_csr_chi_slave RXREQ`、`XP TXDAT_P0 -> policy_csr_chi_slave
RXDAT`、`policy_csr_chi_slave TXRSP/TXDAT -> XP RXRSP/RXDAT_P0`。`rni_xp_p0_link_ctl` 是唯一
raw-link owner，按 RXREQ address aperture 和 RXDAT 的 DBID/TxnID ownership 在 AXI request
engine 与 CSR-slave 之间唯一分发；TXRSP/TXDAT 也由该模块仲裁，不能由两个 engine 直接驱动
XP。

`ENABLE_EXP_COMPACK=0` 时 AXI request engine 不产生 CompAck；TXRSP 仍被 CSR-slave 用于
`DBIDResp/Comp`，TXDAT 仍被 CSR-slave 用于 `CompData`。

### 8.3 Local-link 验证准入

1. 参数静态断言：三端每类 flit width、NID/TxnID/DBID/DataID/DAT/BE 参数相等，且所有静态
   NodeID 高 4 bit 为零。
2. 每个 REQ/RSP/DAT 方向独立验证 `initial credits -> 连续发送至零 -> dequeue 后返还一 credit`
   的守恒时序；credit=0 时 `FLITV=0`。
3. LinkActive 未完成时不得发送 flit 或发 initial credit；reset 中不得保留 FIFO valid 或 credit。
4. RXRSP/RXDAT 和 CSR RXDAT 必须由唯一 active owner 接收；未知 TxnID/DataID/DBID 触发
   protocol error，不得广播。
5. SNP directed test 证明 HNF 不向 RNI NID 发送 snoop；ReadOnce/WriteUniquePtl 仅对 RNF
   target 发 SnpOnce/SnpUnique。

每个客户集成仍须提供版本化 capability matrix：每 profile 允许的 request/response/retry/
PCrdGrant、MemAttr/SnpAttr 编码、§6.1 的可用 TxnID/DBID 容量，以及 HN 对该 coherent RNI
接口能力的配置确认。

集成还必须在 elaboration 固定数据面参数：AXI4 full `WDATA/RDATA` 只能取
`{8,16,32,64,128,256,512,1024}` bit，CHI `DAT.DATA` 只能取 `{128,256,512}` bit，且
`CHIE_BE_WIDTH == CHIE_DATA_WIDTH/8`。64B line/16B slot 是固定内部布局。profile、CSR
policy 与 `policy_epoch` 只选择访问语义，绝不可在运行时修改上述接口位宽、DAT DataID
映射或 buffer 布局；改变位宽必须重新 elaboration、reset 并重新完成 capability 验证。

还必须交付策略表的 reset 映像、CSR 安全访问控制、地址 firewall、每个 shareable region 的
software ownership-transfer 说明，以及无 RX SNP 接口下的 HN 行为证明：HN 不得把本节点当作
snoop target，也不得授予要求此节点后续回送稳定/脏 line 数据的状态；若不能证明，
`WriteUniquePtl` 不在该集成的 coherent capability matrix 内。平台还须交付
`COORDINATED_RESET` 的 link-down/AXI reset/HN abort 时序波形。`rni_link_ctl` 是 RNI 内所有
raw 字段与 L-credit 的唯一归属；core 不得自行拼 raw flit 或管理 L-credit。

## 9. 验证与准入

### Gate 0：静态与安全

- 参数、flit layout、NodeID、opcode/response capability matrix 和 CSR lock 的静态断言。
- AXI4 full 合法 data width、CHI DAT 合法 Data_Width、`CHIE_BE_WIDTH`、64B/16B canonical
  layout，以及 `AxSIZE` 不超过 AXI bus bytes 的静态/事务级断言。
- §3.2 的 RXRSP/TXRSP 字段、TXRSP credit、`req_attr` 完整字段，以及 §6.1 TxnID 位宽/范围/
  DBID-map 深度的编译期断言。
- 区域重叠/miss、安全域/requester mismatch、非法 intent、未综合 profile 和 Non-secure
  升级的 `DECERR`/security-event 测试。
- `policy_epoch` 在 AR/AW handshake 后稳定；commit 的 shadow->quiesce->atomic switch 波形，
  包括 AW 已握手但 W 尚未收齐时 commit 不能完成的检查。

### Gate 1：功能与顺序

- 两 profile 的 read/write、partial WSTRB、DBID/DAT/Comp、DataID 重组、AXI ID 保序与
  AW/W 绑定。
- AXI lane/fragment 数据面：最窄与最宽 AXI width、每个合法 `AxSIZE` 的端点、非对齐首拍
  的 byte mask、一个 presentation 跨两条 64B line、以及 CHI DAT=128/256/512 的 pack/unpack。
- coherent profile 的 `RetryAck -> PCrdGrant -> reissue`、write `ExpCompAck`、以及所有
  客户批准 response 形状；reissue 必须复用 TxnID/req_attr 且 `AllowRetry=0`。
- `ExpCompAck=1` 的 TXRSP credit 耗尽、CompAck handshake 前禁止 B/释放 data-route 的检查。
- 同一 line 的跨 profile 访问：策略不变时拒绝/序列化；commit 时 admission 停止且在途
  事务使用旧 epoch；line_hazard 必须保持到 AXI R/B handshake；软件 ownership-transfer
  场景的系统测试。

### Gate 2：压力与故障

- TXREQ/TXDAT/TXRSP credit=0、随机 backpressure、TxnID/DBID 资源耗尽、retry、response
  乱序、protocol error drain，以及 `COORDINATED_RESET` 的 link-down/AXI reset/HN abort
  取消边界。不得把 link re-epoch 当作无损恢复测试。
- 双 engine 并发时同 ID 保序、不同 ID 吞吐、无重复 TxnID/DBID/CompAck、无 credit 泄漏。

### Gate 3：系统声明

只有全部 Gate 通过后，才可声明支持“指定 OpenNoC profile 下的 non-coherent 访问与
OpenNoC coherent RNI 对 cache-coherent memory 的访问”。直接 RX SNP 服务、atomic/
exclusive、DVM、cache maintenance 或 CPU 本地 cache-state 仍须以单独 Gate 覆盖。

## 10. 实施结论

推荐的生产方案是：**静态能力参数 + secure CSR 区域策略表 + 每笔 CSR 解析结果锁存**。它允许
同一 RNI 安全地发出非一致性和经 HN 批准的一致性请求，同时避免全局运行时切换破坏在途
事务。实施顺序被固定为：

1. 完成 §3.2 coherent wire contract、§6.1 ID/DBID 生命周期及 `COORDINATED_RESET`；
2. 完成 profile snapshot、CSR commit、AW/WCOLLECT drain 与 line hazard；
3. 接入 coherent request engine，并以 capability matrix/Gate 0--3 验证；
4. 仅在前三步闭环后扩大 opcode、autonomous recovery 或 snoop 能力。

第 1 步未完成前，`OPENNOC_COHERENT` 只能是架构目标，不能连接到当前 `chi_rni` shim。
