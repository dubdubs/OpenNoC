# 方案一：非一致性 AXI-to-CHI Adaptor 架构与验证方案

> 本文档是方案一的唯一规范源（canonical）。若发现 `willow/chi_master_rni/axi_to_chi_scheme1.md`
> 等副本，以本文档为准并删除副本或改作指针，不得并行维护多份规范。

## 1. 目的和范围

本文定义 CHI Adaptor 的方案一：复用 Hybrid 平台既有的 AXI Master Adaptor
（实现形态可以是 `axi_master_bfm`）将 C/C++ Proxy 的事务变为 AXI4，再由新的
AXI-to-CHI RNI 转换至客户 CHI NoC；反向路径将 CHI 请求转换至既有 AXI Slave
Adaptor 或 AXI slave BFM。这样没有 CPU RTL Cache 的 C/C++ CPU Model 仍可访问
客户系统中的内存和外设。

方案一是**非一致性适配方案**。它解决 AXI 与 CHI 的事务、数据、流控和错误语义
转换；它不实现 CPU Cache，也不实现 CHI Cache Coherence。

本文只定义目标架构、接口契约、支持范围和验证交付物。它不以任何现有 RNI、SNF
或 OpenNoC RTL 的实现限制为前提。

### 1.1 V1 wire-profile 定位

V1 是**客户私有部署的受限标准 CHI profile**：只支持本文件批准的 non-snoop opcode、
字段组合和链路参数。除第 7.3 节明确排除的 Retry/P-credit 外，所有已发送/接收的 REQ、
RSP、DAT 与 L-credit 语义均以 IHI0050E 为规范来源。私有部署不等于允许自定义已启用的
字段、DataID、DBID 或 credit 行为；Retry/P-credit 的排除仅能依赖客户 HN/NoC 的硬性
部署保证，不能宣称为通用 CHI raw-wire interoperability。

本文件第 5--8 节与版本化 profile 共同限定允许的 CHI 子集。与第三方 CHI IP 互连前仍需
核对 revision、字段布局、NodeID 路由和所选能力，但不得以“私有 profile”为理由偏离
IHI0050E。

## 2. 使用场景与非目标

### 2.1 目标场景

1. C/C++ CPU Model 启动裸机、bootloader 或受限的 OS bring-up，并访问非共享 DRAM。
2. CPU Model 通过 MMIO 访问客户 NoC 后的外设。
3. C/C++ Model 作为非一致性 initiator 或 target，验证普通 load/store、寄存器访问
   和不依赖 CPU Cache 的 DMA 描述符访问。

### 2.2 非目标

- CPU Cache 状态、line ownership、dirty data 或 replacement policy。
- 接收并响应 CHI snoop。
- 多核共享数据的 Cache Coherence。
- DVM、cache maintenance、原子操作、exclusive monitor 或依赖真实 CPU barrier
  微架构时序的软件验证。
- 通过 AXI 属性推断出完整的 CPU coherent 行为。

若客户软件需要上述能力，应使用带最小 Cache/Coherence Model 的独立方案，而不能
扩大本方案的 AXI-to-CHI 转换范围。

V1 拒绝 AXI lock/exclusive，因而不适用于使用 LDXR/STXR（或等价 AXI exclusive）实现
spinlock 的 bootloader、firmware、RTOS/OS 同步路径；此类 access 将得到 `DECERR`，软件
可能在启动早期失败。目标软件必须证明启动和同步路径不使用 exclusive，或将 exclusive
支持另行立项。

## 3. 系统拓扑

方案一包含两条互相独立的路径：

```text
AXI initiator path

C/C++ CPU Model / Virtual Proxy
          |  DPI / IPC / transaction API
          v
axi_master_bfm / existing AXI Master Adaptor
          |  AXI4 AR/AW/W and R/B
          v
new AXI-to-CHI Adaptor RNI
          |  approved non-snoop CHI requests
          v
Customer CHI profile shim -> Customer CHI NoC / HN

AXI target path

Customer CHI NoC / HN
          |
          v
new CHI-to-AXI Adaptor SNF
          |  AXI4
          v
AXI slave BFM / existing AXI Slave Adaptor
          |  DPI / IPC / transaction API
          v
C++ peripheral or memory model
```

两个 adaptor 不应直接互连以构造所谓的端到端 CHI 路径：上游 initiator request
和下游 target request 的角色、opcode 和一致性责任不同。客户 NoC/HN 必须位于两者
之间，并完成地址路由及其自身承担的一致性处理。

### 3.1 虚拟侧复用与职责边界

`axi_master_bfm` / existing AXI Master Adaptor 是虚拟侧与 RTL 的既有边界，继续负责
如下事项：

- 接收 C++ Proxy 事务、维护命令队列，并依 AXI valid/ready 发出 AR、AW、W；
- 接收 R/B，将完成和读数据回传 C++ Proxy；
- 保持既有 DPI/IPC、poll、trace 和 AXI BFM 验证基础设施。

新的 AXI-to-CHI Adaptor RNI **不**直接连接 C++ Proxy，也不实现 DPI/IPC 或 CPU
transaction API；它仅接收 AXI4，并负责 burst 分段、AXI-to-CHI opcode/attribute
转换、CHI REQ/RSP/DAT 状态、reset/link 以及 AXI R/B 错误返回。客户 CHI raw flit、
credit 和链路参数的差异由 RNI 外侧的 Customer CHI profile shim 收敛。

对 OpenNoC 的可交付顶层必须例化 transaction core 和 profile shim，并暴露 raw
REQ/RSP/DAT flit、L-credit 与 LinkActive 接口；只暴露 decoded ready/valid CHI 的 core 是
内部模块，不能作为 OpenNoC 集成顶层。profile shim 是 REQ/DAT 字段 pack、RSP/DAT 字段
unpack、NodeID 路由、MemAttr、credit epoch 和 link handshake 的唯一归属。core 与 shim
的逐信号契约见 §8.1；当前交付物为 decoded 顶层 `chi_rni.sv` 与独立
`chi_rni_opennoc_profile_shim`，OpenNoC 集成必须在此二者之上再包一层 raw-flit 顶层，
或以 shim 直接作为集成顶层，不得将 decoded 顶层直接对接客户 NoC。

因此虚拟 CPU 发起读写的闭环为：

```text
C++ Proxy -> AXI Master Adaptor/BFM -> AXI-to-CHI RNI -> Customer NoC
          <- AXI R/B               <- CHI RSP/DAT       <- Customer NoC
```

### 3.1.1 profile shim 的差异收敛与参数化边界

profile shim 是 decoded core 与客户 CHI NoC 之间的适配层：负责 REQ/DAT 字段 pack、
RSP/DAT 字段 unpack、NodeID 路由、MemAttr 编码、credit 与 link handshake；core 与 shim
的字段所有权划分见 §8.1。客户之间真实存在、必须由 shim 收敛的差异包括：

- raw flit 字段布局：各字段 LSB 由 profile 的 `NODE_ID_WIDTH`、`TXNID_WIDTH`、
  `DBID_WIDTH`、`DATAID_WIDTH`、`ADDR_WIDTH` 派生，任一宽度变化会平移其后所有字段。
- `NODE_ID_WIDTH`（通常 7--11）对 `SrcID/TgtID/ReturnNID` 位宽，以及 RSP 方向反查
  completer 身份的影响。
- `MemAttr` / opcode / `RespErr` / DataID 的编码取值：由 CHI issue 决定；跨 issue 的
  字段集合可能不同（例如 snoopability 在 Issue E 内嵌于 `MemAttr`，在 E.b 拆为独立
  `SnpAttr`）。
- credit 策略：每通道初始 credit、上限、返还粒度（收一还一 vs 批量 LCRDRET），以及
  是否存在 P-Credit。
- CHI revision / 数据总线宽度决定的 DataID 编码公式形状，以及 HN 实际批准的 opcode 集合。

这些差异按“是否只改变数值”分为两类，接入新客户时按以下判据处理：

- 纯数值差异（位宽、由位宽派生的 LSB、初始 credit 数量、NS/QoS 默认值等）在同一个
  shim 内用 parameter / `localparam` 配置，不因此复制 RTL。
- 结构/语义差异（字段集合增删、字段含义变化、DataID 公式形状变化、credit 返还粒度
  或 P-Credit 有无、link handshake 序列变化）需要换 shim 或在该 shim 内用 `generate`
  分支，且必须纳入 Gate 0 静态断言。

因此“shim 是 profile 差异的唯一归属”应理解为：所有 profile 常量的 pin 点、字段
pack/unpack 表达式与结构性分支都收敛在 shim 一层；core 只保留与客户无关的事务语义。
每个新客户/NoC 接入时，要么复用同一 shim 换一组参数，要么提供新 shim，二者都须通过
§8 的版本化集成配置与 Gate 0 断言。

### 3.2 Target 路径的规范归属

本文规范 AXI-to-CHI initiator 路径。CHI-to-AXI target/SNF 路径的 opcode、AXI burst、
DBID/DataID、completion、credit/retry、reset/link 和错误规则，由
`snf_chi_to_axi_scheme1_optimization.md` 规范性定义。两条路径共用本文件第 4、5、
8 节的非一致性边界、静态属性和集成契约；不得仅依据本节拓扑图推断 target 行为。

## 4. 一致性边界

AXI 协议没有表达 CHI snoop、cache line ownership 或 dirty-data 回写的完整语义。
因此，AXI-to-CHI adaptor 必须被客户 NoC 视为**非一致性节点**。

硬性契约如下：

- 客户私有 HN 不向 AXI-to-CHI adaptor 发送 SNP。
- adaptor 的地址区域不得被客户配置为需要该节点参与 snoop 的 coherent shareable
  region。
- Shared DMA buffer 只能验证 non-cacheable/direct-access 行为；不能据此验证 CPU
  cache maintenance 或 DMA 与 CPU Cache 的一致性。
- 客户提供私有 profile 支持的 opcode 集合；adaptor 仅发送该集合中明确批准的 non-snoop
  opcode。

## 5. 地址属性与操作码策略

当前工程没有可供 adaptor 查询的地址属性表。因此 V1 不假设存在 `region_attr`，也不
根据 `AxCACHE` 或 `AxPROT` 动态猜测 Device/Normal。每个 adaptor 实例在集成时采用
一个固定的、编译期配置的访问策略：

```text
ACCESS_CLASS = DEVICE | NORMAL_NONCACHEABLE
READ_OPCODE  = ReadNoSnp（V1 固定）
WRITE_OPCODE = WriteNoSnpPtl（V1 固定；Normal 可选 WriteNoSnpFull）
BURST_BEAT_COALESCING = 0 | 1
NS_POLICY = FORCE_SECURE | FORCE_NONSECURE
# FORCE_* 表示本实例固定为某安全类，AxPROT[1] 不匹配即入口 DECERR
ORDER_VALUE = 0（V1 固定 Request Order）
QOS_VALUE = 0 | 客户定义的常量
ENDIAN_POLICY = LITTLE_ENDIAN
ALLOW_RETRY = 0
PCREDIT_SUPPORT = 0
```

`AxCACHE` 仅供 trace，不用于动态选择 coherent opcode。`AxPROT` 表示特权、安全和
指令属性；它不是 Device/Normal 分类字段。安全
属性是否映射到 CHI `NS` 必须由该实例的静态 `NS_POLICY` 冻结；不支持时入口拒绝。
V1 默认 `NS_POLICY=FORCE_NONSECURE`（CHI `NS=1`）、`Order=0`、`QoS=0`、little-endian；
`FORCE_SECURE` 只能由客户显式配置并经 HN 批准。AXI 映射固定为 `AxPROT[1]=0` 表示
secure、`AxPROT[1]=1` 表示 non-secure；仅当
`(FORCE_SECURE && AxPROT[1]==0) || (FORCE_NONSECURE && AxPROT[1]==1)` 时才受理。其他
情况以 parent 级 `DECERR` 完成，不得动态改变 CHI `NS`。

初始策略如下，最终 opcode 须由客户 HN 能力确认：

| 静态访问类别 | AXI 读 | AXI 写 | burst 内规则 |
|---|---|---|---|
| Device | `ReadNoSnp` | `WriteNoSnpPtl` | 一个 AXI beat 对应一个 CHI child；禁止 beat 组合、预取与 over-fetch |
| NormalNonCacheable | `ReadNoSnp` | 默认 `WriteNoSnpPtl` | 仅 `BURST_BEAT_COALESCING=1` 时可组合相邻 beat |

V1 暂不实现 router；无 router 时整个 port 只能一个静态 `ACCESS_CLASS`（`DEVICE` 或
`NORMAL_NONCACHEABLE` 二选一，默认 `DEVICE`）。以下 router 规则仅作为未来单端口混合
Device/Normal 访问的扩展方向保留。若同一 AXI port 必须同时访问 Device 和
NormalNonCacheable 区域，必须加入集成层 `axi_region_router`，不能将两个 adaptor
实例直接并联到同一 AXI channel：

```text
AXI proxy → axi_region_router → Device adaptor instance
                              └→ NormalNonCacheable adaptor instance
```

router 持有静态且无重叠的 `ADAPTOR_ADDR_MAP[]`，每项至少为
`{base, limit, adaptor_instance, access_class, NS_POLICY, ORDER_VALUE, QOS_VALUE}`。
map 使用半开区间 `[base, limit)`。令 `B=1<<AxSIZE`，INCR 的
`beat_addr[i]=AxADDR+i*B`，FIXED 的 `beat_addr[i]=AxADDR`；仅当存在同一个 map `M`，
使所有 beat 都满足 `M.base <= beat_addr[i] && beat_addr[i]+B <= M.limit` 才可路由。否则
为跨 map/target/属性边界并返回 `DECERR`；WRAP 在 router 入口直接拒绝。

仅当 security 满足
`(AxPROT[1]==0 && M.NS_POLICY==FORCE_SECURE) || (AxPROT[1]==1 &&
M.NS_POLICY==FORCE_NONSECURE)` 时才受理；否则为属性不匹配并 `DECERR`。`AxCACHE` 不构成
router mismatch。AXI4 W 没有 WID，且
不支持 write-data interleaving：router 的 `AW-route queue` 按 AW handshake 顺序入队，
从队首向唯一 downstream adaptor 转发 W，直到 WLAST handshake 才出队；不得按
WDATA/WSTRB/AXI ID 重 decode。队首 adaptor 的 W buffer 满导致队头阻塞是 V1 接受的
性能限制。AXI3 或自定义 WID 接口不适用此 router，必须另行实现和验证。

router reset 与 adaptor reset 使用同一取消边界：清空 AW-route queue、active-parent 表与
下游响应归属，不为 reset 前 parent 伪造 R/B。router 是“每原始 AXI ID 至多一个 active
parent”的唯一权威；adaptor 内同名限制仅是单实例直连时的兜底断言，不得采用不同策略。

方案一不产生 `ReadOnce`、`WriteUnique*` 等要求节点承担 coherent-RN 角色的请求，
除非客户将该扩展作为单独能力重新评审，并同时补齐 snoop/状态模型。

### 5.1 Opcode 与属性转换规则

`ReadNoSnp` 是 V1 唯一支持的 AXI read opcode；V1 只接收其 `CompData` 完成形状。
`ReadNoSnpSep`、任何 coherent read、DVM、atomic 和 cache-maintenance request 均不在
V1 范围内。

`WriteNoSnpPtl` 是 V1 默认且唯一必选的 AXI write opcode。它同时覆盖满字节和 partial
WSTRB 写入。NormalNonCacheable 实例可选产生 `WriteNoSnpFull`，但必须满足标准 CHI 的
完整 cache-line 语义：child Size 等于配置 cache-line 大小、地址按该大小对齐、parent 有效
写 byte 完整覆盖该 line，且每个 DAT flit 的 BE 全为 1。任一条件不满足（包括小于完整
cache line 的满 byte-enable 写）都必须使用 Ptl。Device 实例不得产生 Full。
V1 的 write response 必须处理客户批准的 `DBIDResp`、`CompDBIDResp` 和最终 `Comp`。
`ExpCompAck` 在 V1 固定为 0；若客户要求其为 1，必须先实现并验证 `CompAck`。V1 RN 固定
采用 DBID 写流程：REQ 发出后等待 `DBIDResp`/`CompDBIDResp` 再发 DAT，不接受 no-DBID
完成；客户 HN 必须对每个写返回 `DBIDResp` 或 `CompDBIDResp`，否则 adaptor 会永久等待
DBID。该要求是 §8 集成契约的硬性条款。

每个 child 的 CHI 字段按以下规则生成：

| 字段 | Device | NormalNonCacheable |
|---|---|---|
| `Opcode` | `ReadNoSnp` / `WriteNoSnpPtl` | `ReadNoSnp` / `WriteNoSnpPtl`，满足条件时可选 `WriteNoSnpFull` |
| `Size` | 等于一个不超过 64B 的 AXI beat 的字节数 | 等于精确 child 的 2 次幂字节数，最大为客户批准值且不超过 64B |
| `Addr` | AXI beat 地址 | child 的自然对齐起始地址 |
| `MemAttr` | 静态 Device、non-cacheable、non-allocate | 静态 Normal non-cacheable、non-allocate |
| `SnpAttr` | 0 | 0 |
| `NS`、`Order`、`QoS` | NS/QoS 为客户静态配置；V1 `Order=0` | NS/QoS 为客户静态配置；V1 `Order=0` |
| `Endian` | V1 固定 little-endian；AXI byte lane、`read_map[]`、`write_map[]` 使用同一低地址到低 lane 映射 | 同左 |
| `AllowRetry` | V1 固定 0 | V1 固定 0 |

`AxCACHE` 不选择 CHI opcode；`AxPROT` 不用于 Device/Normal 分类。V1 拒绝
AXI exclusive/lock。安全属性按 `NS_POLICY` 匹配：`FORCE_SECURE` 仅受理 `AxPROT[1]==0`
并置 CHI `NS=0`，`FORCE_NONSECURE` 仅受理 `AxPROT[1]==1` 并置 CHI `NS=1`；不匹配以
parent 级 `DECERR` 拒绝，不得动态改变 CHI `NS`。

V1 不传播 `AxUSER`、`AxREGION` 或 `AxQOS`：它们不参与 opcode、MemAttr、NS、Order、
QoS 或 router 选择，也不写入 CHI flit；trace 可选择记录原始值。`AxCACHE` 同样仅供
trace，不是 opcode 或路由输入。客户若要求这些字段影响 CHI 行为，必须增加版本化的
静态映射/校验规则，不能在 RTL 中隐式猜测。

## 6. AXI burst 到 CHI child 的转换

### 6.1 Parent 与 child

一个 AXI address burst 是一个 **parent**；一个可独立发出的 CHI request 是一个
**child**。parent 保存原始 AXI ID、地址序列、`LEN/SIZE/BURST`、每 byte 的数据/
strobe、完成和错误状态。child 保存：

```text
parent_id, child_id, CHI TxnID,
opcode, address, size_log2, MemAttr, NS, Order, QoS, Endian,
req_byte_base, req_byte_count,
read_map[] = {axi_beat_index, axi_byte_lane, child_byte_offset},
write_map[] = {child_byte_offset, source_wbeat, source_wlane, valid},
expected_dat_beats, expected_dataid_set, lane_BE, retry state
```

child 的自然对齐定义为 `child_addr % (1 << child_size_log2) == 0`。
`read_map[]` 是 adaptor 内部逐字节映射，不是 CHI read byte-enable；CHI read request
本身没有 byte-enable。`lane_BE` 由 `write_map[]` 投影到每个 DAT flit 的完整
`CHI_DAT_BYTES` 宽度。`expected_dat_beats = ceil(2^size_log2 / CHI_DAT_BYTES)`；read
DataID 由 CHI 规范按请求 `Addr`/`Size`/数据总线宽度确定性定义，completer 必须按规范
编码发出，adaptor 按 §6.1.1 的 `expected_dataid` 表校验并重组，不得按到达顺序拼接。

### 6.1.1 DAT、DataID 与 map 编码契约

`CHI_DAT_BYTES=CHI_DAT_WIDTH/8`、`CHI_DATAID_WIDTH` 与
`DATAID_ORDER_POLICY=IN_ORDER|ANY_ORDER` 是强制静态配置。DataID 编码由所选 CHI revision、
数据总线宽度、child 地址和 DAT packet ordinal 按 IHI0050E 的 DataID 规则确定。profile
只能选择对应 revision/宽度的版本化查表实现
`expected_dataid(child_addr, child_size_log2, dat_ordinal)`，不得自定义或重解释编码；HN
必须按规范发送 DAT，RNI 必须按同一表校验、去重和重组。

对 child 大小 `S=1<<size_log2`、`N=ceil(S/CHI_DAT_BYTES)`，第 `i` 个 DAT 的
`child_byte_base=i*CHI_DAT_BYTES`，`valid_byte_count=min(CHI_DAT_BYTES,S-child_byte_base)`，
并在 child issue 时预计算 `expected_dataid[i]`。接收 DataID 后只能由该表反查 `i`，因此
byte offset 为 `i*CHI_DAT_BYTES+j`；DataID 本身不是 byte offset。无匹配、重复或多于 `N`
拍均为协议错误。read child 的 REQ TxnID 仅在全部预期 CompData DAT 都已接收、重组并使
所有关联 AXI byte 进入完成或错误状态后才可释放；不能因收到首个 CompData flit 而复用。

对 DAT `i` 内 byte `j`，令 `abs_addr=child_addr+i*CHI_DAT_BYTES+j`、
`lane=abs_addr % CHI_DAT_BYTES`。little-endian 时该 byte 位于
`DAT.DATA[8*lane +: 8]`，`DAT.BE[lane]` 是其使能。write path 将有效 `write_map` 条目
投影到该 lane，其余 DATA/BE lane 分别置零；read path 用同一 lane 取数并按 `read_map`
写回 AXI。所有 flit 保持完整 `CHI_DAT_BYTES` 宽 DATA/BE，不得缩窄总线。

V1 的 `MAX_CHILD_BYTES=64`；两张 map 都是按 `child_byte_offset` 索引的定长 64 项 dense
数组，而非不定长列表：`read_map[0:63]={dst_valid, axi_beat_index, axi_byte_lane}`，
`write_map[0:63]={src_valid, source_wbeat, source_wlane}`。child 范围外项无效；read 的每个
请求 byte 必须恰有一个有效目的项，write 仅对 `WSTRB=1` 置有效，且一个 child offset
不得映射多个 AXI byte。map 元数据容量必须计入
`MAX_ACTIVE_CHILD * 64 * (read_map_entry_bits + write_map_entry_bits)`。

`ANY_ORDER` 允许同 TxnID、预计算表中且尚未收到的 DataID 任意到达并重组。`IN_ORDER`
要求到达 ordinal 等于 `next_expected_ordinal`；否则为 profile/协议违规。这里的“有序”
是 profile ordinal 顺序，而非 DataID 数值大小。

### 6.1.2 SegBurst 地址计算参考

新的方案一 segmenter 可以借鉴现有 `rtl/src/rni/rni_segburst.v` 的两类纯地址计算：

- 从 `AxADDR`、`AxLEN`、`AxSIZE`、`AxBURST` 展开 parent 的逐 beat 地址序列；
- 以 64B line boundary 识别 INCR burst 的首段、中间整 line 与尾段，并为后续
  64B child 选择提供边界信息。

这只是算法参考，不是直接复用该 RTL。方案一 segmenter 的输入和输出必须扩展为：

```text
input:  AXI parent descriptor + WSTRB（写）+ 静态访问策略
output: child {address, Size, opcode, MemAttr, NS, Order, QoS, Endian,
               parent/child ID, read/write map, expected DataID set, lane BE}
```

现有 `rni_segburst` 不可直接复用的行为包括：

- 固定以 64B cache line、四个 16B slot 组织，且只计算 16/32/64B internal Size；
  方案一需要按 child 精确生成 1B--64B 的 2 次幂 Size。
- `dmask` / `bc_vec` 是当前 RNI 的内部 16B-slot 重组元数据，不是 CHI read BE 或
  CHI DAT BE；方案一需要独立的 `read_map[]` 与写 lane-BE 生成器。
- 没有 WSTRB、opcode、MemAttr、NS、Order、静态访问类别或 parent/child 标识。
- 没有 AXI 4KB-crossing、非法 `BURST=2'b11`、非法 WRAP 长度/对齐、unaligned 或
  lock/exclusive 的准入检查。
- 它不区分 Device 与 NormalNonCacheable，也没有 `BURST_BEAT_COALESCING` 策略；
  因而不能保证 Device 逐 beat、无 over-fetch 语义。

尤其要注意：参考实现的读控制会覆写 segburst 的 Size 输出，因此现有模块输出的
internal Size 并不保证成为线上 read `REQ.Size`。方案一必须在新的 child descriptor
到 CHI request packer 之间直接连接 `child.Size`，不能只依赖地址切段结果。

### 6.2 不跨 AXI transaction 合并

V1 中每一次 AXI AR 或 AW address handshake 都创建一个独立 parent。adaptor 不得将
多个独立的 AXI address transaction 合并为一个 CHI request，即使它们地址连续、AXI ID
相同且属性相同。

同一个合法 AXI INCR burst 内的多个 beat 属于同一个 parent；采用
`NormalNonCacheable + BURST_BEAT_COALESCING=1` 静态策略的实例可以将这些 beat
分段或组合为更大的 CHI child。所有 child 的
字节并集必须与该 parent 的请求字节范围完全相同：不得 over-fetch、不得漏字节，也不得
跨 region、target 或属性边界。

### 6.3 Device 规则

Device 访问不得因优化改变访问次数或地址范围：

- 每个自然对齐 AXI beat 生成一个精确的 non-snoop child，即使这些 beat 同属一个 burst。
- 不合并、不 prefetch；不使用大于该 beat 请求范围的 CHI `Size`。
- `beat_unaligned` 定义为 `beat_addr % beat_bytes != 0`，其中
  `beat_bytes = 2^AxSIZE`。Device 的任一 unaligned beat 均返回 `DECERR`：在禁止
  over-fetch 且不得改变访问次数的前提下，不能安全地拆分为多个 CHI access。
- Device 的 `INCR` 与 `FIXED` 均采用严格串行语义：child 按 AXI beat 序号 issue，且
  收到 child `i` 的最终 completion 后才可 issue child `i+1`；读 response 按原 beat
  序号返回。这保证 MMIO 读副作用与寄存器写序不被 CHI 乱序改变。
- `FIXED` 的每个 beat 均为一次独立、精确的同地址访问；不得因地址相同而合并、
  抑制或预取。`WRAP` 或跨 region burst 必须在 AXI 入口明确拒绝/报错。

### 6.4 NormalNonCacheable 规则

只有 `BURST_BEAT_COALESCING=1` 的 Normal non-cacheable 实例才可在**同一个 AXI
INCR burst**内组合连续 beat；`FIXED` burst 永远逐 beat 处理。不得跨 parent 合并独立
AXI transaction。组合后的每个 child 必须：

- 不跨 region、target、属性变化或客户规定的边界。
- 使用客户 HN 接受的 non-snoop opcode。
- 使用自然对齐且不超过 CHI 最大支持粒度的精确 `Size`。
- 不读取或写入原 AXI parent 访问范围以外的字节。

NormalNonCacheable 的 `INCR` 可接受 unaligned beat。segmenter 先展开每个 beat 的实际
请求 byte 集合，再以自然对齐、1B--64B 的 2 次幂 child 精确覆盖；不得读取或写入范围
外 byte。`FIXED` 仍只接受自然对齐 beat。示例：`AxADDR=0x38`、`AxSIZE=4`（16B）、
`AxLEN=7`、`AxBURST=INCR` 覆盖 `0x38..0xB7`，可拆为 `8B@0x38`、`64B@0x40`、
`32B@0x80`、`16B@0xA0`、`8B@0xB0`。

### 6.5 写 DAT 规则

写路径首先完整接收一个允许的 AXI parent 的 W beat 和 WSTRB，再生成 child。这样
可以在发 CHI request 前验证 WLAST、byte coverage 和 child 边界。

AW admission 不预留 TxnID；TxnID 仅在 child 实际 issue 前分配。AW handshake 必须原子
预留一个 parent slot、该 parent 的全部 WDATA/WSTRB 空间和 `MAX_CHILD_PER_PARENT` 个
segment-descriptor 配额。令
`parent_bytes=(AWLEN+1)*(1<<AWSIZE)`、`worst_child_count=parent_bytes`（每个有效 byte
都可能退化为一个 1B child）。若 `parent_bytes>MAX_WRITE_PARENT_BYTES` 或
`worst_child_count>MAX_CHILD_PER_PARENT`，该 AW 为配置范围外请求并以 `DECERR` 完成；
预留资源暂时不足时只能拉低 AWREADY，不得先接收 AW 再因资源不足返回 `DECERR`。
`MAX_CHILD_PER_PARENT` 的安全下限为 `MAX_WRITE_PARENT_BYTES`。active-child window 仅是
运行期 issue 节流，不能作为 AW 已接受后的拒绝理由。

AXI admission 的结果必须写入 immutable `parent.admission_state`。若 AW/AR 因 lock、
security、burst、地址属性或资源上限被拒绝，则该 parent 只能 drain 已允许接收的 W 并返回
`DECERR`；后续 W 收齐、link 恢复或资源释放均不得改变其状态，更不得生成任何 CHI REQ 或 DAT。

每个 child 的 DAT plan 必须按 CHI profile 生成，`DAT.BE` 保持 CHI DAT 总线宽度的
lane 表示（例如 256-bit DAT 对应 32-bit BE）；小尺寸请求不能将 BE 缩为 8-bit 信号。
V1 默认写 opcode 为 `WriteNoSnpPtl`，其逐拍 BE 规则按静态访问类别分界：

- `WriteNoSnpPtl -> Normal`：数据窗口 `[Addr, Addr+Size-1]` 内，任意拍可断言任意 BE
  组合，包括全 1 和全 0。
- `WriteNoSnpPtl -> Device`：BE 只能断言在 `Addr` 及其以上的字节上（不得断言低于请求
  地址的 byte lane）；满足该条件的任意组合均可，包括全 1 和全 0。
- `*Full` 一族 opcode（`WriteNoSnpFull`、`WriteBackFull`、`WriteCleanFull`、
  `WriteEvictFull`、`WriteUniqueFull`、`WriteUniqueFullStash`）要求每拍 BE 全 1。
- `WriteBackPtl` / `WriteUniquePtl` / `WriteUniquePtlStash` 允许任意 BE 组合（含全 0），
  但 V1 不产生这些 opcode。

所有写 child 还须满足两条通用规则：

- 数据窗口 `[Addr, Addr+Size-1]` 之外的 BE lane 必须 deassert；任何 BE=0 的 lane，其
  对应 DATA 字节必须置零（§6.1.1 的“其余 DATA/BE lane 置零”即此规则）。
- 稀疏 WSTRB 本身不构成缩小 child 的协议理由：segmenter 只按自然对齐、2 次幂 `Size`、
  4KB/region 边界（§6.6）和字节并集不得超出 parent 范围（§6.2）拆分，不需要为满足
  “中间拍 partial”而缩小。

`WSTRB=0` 的 AXI beat 按访问类别分界：Normal 下是 no-op，不生成 CHI write child；
Device 下仍生成一个 `WriteNoSnpPtl` child 且 BE 全 0，以保留访问次数（§6.3），不得
因 `WSTRB=0` 改变 Device 访问次数。两种情况都必须保持该 AXI burst 的 WLAST、顺序和
最终 B response 语义。Normal 下全 0 BE 的 child 虽被规范允许，V1 仍选择不产生
（少发一笔无意义请求）。对于部分 WSTRB，`WriteNoSnpPtl` 的 child 不得写入任何
WSTRB=0 的 byte lane。

写 child FSM 只接受以下 V1 completion 形状：

```text
SENT_REQ
  DBIDResp(OK)       -> HAVE_DBID -> SEND_DAT -> WAIT_COMP
  CompDBIDResp(OK)   -> HAVE_DBID_AND_COMP -> SEND_DAT -> DONE
```

`DBIDResp` 仅在 `RespErr=OK` 时捕获 DBID，随后按该 DBID 发完整 DAT 序列，并在最后 DAT
后等待最终 `Comp`。`CompDBIDResp` 同时捕获 DBID 和 completion；仍必须发完整 DAT，最后
DAT 发出即 child 完成，不再等待 Comp。bare `Comp` 只能在该 child 已取得 DBID 后记录为
completion；它可以在 DAT 之前或之后到达。若 completion 先到，child 进入
`HAVE_DBID_AND_COMP` 并继续发送完整 DAT；最后 DAT handshake 才完成 child。bare `Comp`
先于 DBID、重复或与 child 不匹配的 completion 均为协议错误。若 V1 部署 profile 不接受
`DBIDResp -> Comp -> DAT`，必须在集成配置中显式声明 HN 不会产生该合法形状并在 Gate 2
中验证。`DBIDResp/CompDBIDResp` 的非 OK `RespErr` 标记 child `SLVERR` 且不发送 DAT；DAT
已开始后不得因 response error 截断后续 DAT。

DBID response 还必须保存 response flit 的路由身份。每个 write DAT 使用该 child 的 DBID
作为 `DAT.TxnID`，使用 DBID response 指定的 completer 身份作为 `DAT.TgtID`，并保持本 RNI
的 `DAT.SrcID`、`TxnID`、`TgtID` 在该 child 的全部 DAT flit 中一致。每个 write DAT flit
的 opcode 固定为 `NonCopyBackWrData`（DAT opcode 0x3，非 copyback 写数据）；其 `DataID`
按 §6.1.1 的同一规范性编码由 `child_addr`、`child_size_log2` 和 `dat_ordinal` 生成，
profile 不得自定义。原 REQ TxnID 在 DBID、所有 DAT 与最终 completion 都完成前不得复用；
DBID 在全部 DAT handshake 后才释放。

### 6.6 AXI burst 类型转换规则

每个 AXI AR/AW handshake 是一个 parent。V1 先检查 AXI burst 的合法性，再生成 child；
不合法请求不得被“尽量拆分”后继续执行。

| AXI burst 类型 | V1 规则 | CHI child 规则 |
|---|---|---|
| `INCR` | 主支持类型 | Device：每 beat 一个精确 child，严格串行。NormalNonCacheable：仅同一 parent 内、静态允许时，将连续 beat 合成为自然对齐、2 次幂、最大 64B 的 child；允许 unaligned beat 的精确分解，不得 over-fetch。 |
| `FIXED` | 支持 | `beat_bytes = 2^AxSIZE`，所有 beat 地址均为 `AxADDR`。自然对齐的每个 read beat 或 non-no-op write beat 映射一个精确的同地址 child，禁止组合、预取、去重及 over-fetch；child 必须按 AXI beat 顺序串行 issue，并在前一 child completion 后才可发下一 child。Normal 的 `WSTRB=0` write beat 不产生 child；Device 的 `WSTRB=0` write beat 仍产生 BE 全 0 的 `WriteNoSnpPtl` child（§6.5）。两种情况都保留 beat 序号、W/WLAST 消费和最终单一 B response。 |
| `WRAP` | V1 拒绝 | 后续扩展只能先展开为 AXI 定义的逐 beat 地址序列；wrap 边界两侧不得组合。 |

对于支持的 `INCR` / `FIXED` burst：

1. `beat_bytes = 2^AxSIZE`，`beat_count = AxLEN + 1`。INCR 的 `beat_addr[i]` 按 AXI
   INCR 规则计算；FIXED 的 `beat_addr[i] = AxADDR`。
2. INCR parent 的首、末请求 byte 必须位于同一 4KB page。FIXED 的每一个 exact beat
   必须满足 `(AxADDR % 4096) + beat_bytes <= 4096`，且不得跨本 adaptor 实例的目标/
   属性边界。`beat_bytes` 不得超过 AXI data width 或 64B。Device 的每个 beat 与 FIXED
   的所有 beat 都必须满足 `AxADDR % beat_bytes == 0`（按 `beat_bytes` 自然对齐）；
   不满足者为未对齐访问，在 AXI slave 入口以 `DECERR` 拒绝。NormalNonCacheable INCR
   可按第 6.4 节分解，不受该对齐约束。
3. Device 逐 beat 保留访问次数；FIXED 对 Device 和 NormalNonCacheable 都产生
   exact-size child。FIXED child 必须按 beat 顺序发出，且仅在前一 child completion 后
   才能发下一 child；读数据亦按 beat 顺序回送。即使地址相同，也不得合并为更大的
   CHI read/write。
4. NormalNonCacheable 的 INCR 组合时，segmenter 只覆盖连续、全有效的 byte 区间；每个 child
   的 `Size` 为 1B--64B 的 2 次幂且 `Addr` 自然对齐。读请求没有 CHI BE，因此不得
   取回 parent 范围外的字节。
5. 写 burst 在收齐 WDATA/WSTRB 后产生 child。Normal 直接把 WSTRB 投影为逐拍 BE；
   Device 只保证 BE 不落在低于 `Addr` 的 lane 上，数据窗口外一律 deassert。两种访问
   类别都不因“中间拍 partial”而缩小 child；child 只在自然对齐、2 次幂 `Size`、
   4KB/region 边界或字节并集超出 parent 范围时拆分。

Device 未对齐 beat、FIXED 未对齐 beat、4KB-crossing burst、`WRAP`（包括非法 WRAP 长度/
对齐）、`AxSIZE` 超出接口宽度、exclusive/lock 和静态策略不允许的属性，应在 adaptor
AXI slave 入口返回冻结的错误码（建议 `DECERR`）并记录 trace；不得转换成 CHI flit。

## 7. 流控、顺序、完成与错误

### 7.1 顺序

V1 实行保守 admission：每个 AXI ID 最多一个 active parent。这样保证同 ID read
response 和 write response 保序。V1 的所有 CHI REQ 均使用 `Order=0`，不请求
Request/Endpoint Order 或 Ordered Write Observation，因此不接收/不生成 `ReadReceipt`。
`RespSepData` / `DataSepResp` 是读完成的数据形状（与 Order 无关），V1 因只接受
`CompData` 完成形状而拒绝；`CompAck` 因 V1 固定 `ExpCompAck=0` 而拒绝。三者拒绝理由
不同，不得合并为同一条件。未来若启用任一非零 Order，必须先定义跨 AXI ID 的 CHI order
domain、ReadReceipt 门控以及 OWO 的 `ExpCompAck=1`/CompAck 状态机，不得只修改
`ORDER_VALUE`。未来可以使用 per-ID completion queue 扩展，但不得破坏 AXI 的同 ID 响应顺序。

### 7.2 资源和背压

资源以 watermark 管理，而非按每个 parent 预分配最大 child 数：

- parent table：保存 AXI burst 语义和总体进度。
- active-child window：只为已发出、未完成的 child 分配 TxnID 和 response buffer。
- write buffer：保存允许的 parent WDATA/WSTRB；空间不足时拉低 WREADY。
- read reorder buffer：保存按 TxnID/DataID 到达的 response；空间不足时对 AR 背压。
- TxnID pool、child window 或 buffer 不足时对 AR/AW 合法反压；不得丢失请求。

V1 限制 AXI INCR burst 不跨 4KB boundary；FIXED 的每一个 exact beat 也必须位于同一
4KB 页面内。最大 buffer 深度、parent 数和 active child 数由 adaptor 实例的静态参数配置。

配置必须满足以下下限，而非只给出任意 watermark：

```text
MAX_WRITE_PARENT_BYTES = (MAX_AWLEN + 1) * (1 << MAX_AWSIZE)
WRITE_BUFFER_BYTES >= MAX_WRITE_PARENT_BYTES * MAX_ACTIVE_WRITE_PARENTS
MAX_CHILD_PER_PARENT >= MAX_WRITE_PARENT_BYTES
MAX_ACTIVE_CHILD <= min(USABLE_CHI_TXNIDS, CHILD_WINDOW_DEPTH)
READ_REORDER_BYTES >= MAX_ACTIVE_READ_CHILD * MAX_CHILD_BYTES
```

例如 256-bit AXI、`AWLEN=255`、`AWSIZE=5` 时，单个已接受 write parent 至少需要
`256 * 32 = 8192B` WDATA 空间，另加 WSTRB 与元数据。Normal sparse WSTRB 最坏可退化为
每个有效 byte 一个 1B child；child/window 描述符不得按“每 64B 一个 child”估算。每个
child issue 前必须同时预留 TxnID、完成状态及完整 response 的 reorder 空间。

### 7.3 L-credit（Retry/P-credit 排除）

L-credit 按 CHI 通道和链路维护，而非按 child 维护。每个通道仅在实际发送 flit 时消耗
一个 credit，并在收到对端同通道 L-credit return 时增加一个 credit；child 另行维护
TxnID 与完成阶段。V1 不使用 SNP 通道。

V1 不实现 Retry/P-credit：所有 REQ 的 `AllowRetry=0`，不保存 retry replay state，也不
处理 `RetryAck` / `PCrdGrant`。这是客户私有部署约束，不是标准 CHI Retry 能力；客户必须
在 HN/NoC 配置、集成断言和回归证据中保证该 RNI 可达路径永不产生 RetryAck 或 PCrdGrant。
收到任一 flit 时 adaptor 报告 profile violation 并进入平台定义的恢复路径；不得尝试重发。

发送 flit 前必须拥有对应通道 credit；credit 仅在对端同通道 L-credit return 后增加。链路
进入 active epoch 后，每个接收端必须主动发出已配置数量的初始 L-credit；初始 credit 不依赖
先收到 flit。每通道授予数必须满足 IHI0050E 的范围及 receiver storage 保证；reset/link-down
清除旧 epoch 的 credit accounting、parent、child、DBID 和 TxnID 状态；不得在新 epoch
返还旧 epoch credit。

接收端仅在 flit 已写入预留的 ingress buffer 后返还对应通道 credit。V1 采用“收一
还一”：每个接收 flit 在下一可发送周期产生同通道 credit return；无可预留存储时不得
接收或返还。reset/link-down 后不得返还旧 epoch 的 credit。

### 7.3.1 AXI reset 与 link 状态

AXI reset 是事务取消边界：reset 期间 `ARREADY/AWREADY/WREADY=0`、`RVALID/BVALID=0`；
采样 reset 后清空 parent、child、write/read buffer、TxnID/DBID ownership 和 credit epoch，
不为 reset 前已接受但未完成的 AXI transaction 伪造 R/B response。AXI master 必须在 reset
释放后重发。

LinkActive/SActive 或 credit 初始化未完成时采用 `LINK_DOWN_POLICY=STALL`：不接受新的
AR/AW，且不 issue 新 CHI child；对已经接受 AW 的 parent，若本地 W buffer 有空间则继续
接受其 W，避免 AXI W channel 悬挂。运行中 link-down 视作平台故障并等待协调 reset；不得
自动转换为 AXI error。快速失败须另行定义 `LINK_DOWN_POLICY=DECERR` 并独立验证。

### 7.4 完成和错误

V1 写路径覆盖客户批准且 `ExpCompAck=0` 的 `DBIDResp`、`CompDBIDResp` 和 `Comp`
形状，不发送 `CompAck`。客户若要求 `ExpCompAck=1`，必须作为扩展能力实现完整的
CompAck 状态机和回归后，才能修改该限制。

本节是 `RespErr` 到 AXI response 的唯一权威：客户 profile 只能声明 HN 会发送的已批准
RespErr 集合，不能重定义映射。`RespErr=OK` 映射 `OKAY`；任何已批准的非 OK RespErr 映射
`SLVERR`；未知、保留或未批准编码产生 protocol-error event 并映射 `SLVERR`。本地
admission/decode/attribute/burst 拒绝为整 parent `DECERR`；V1 永不输出 `EXOKAY`。

每个 read child 保存其覆盖的 AXI byte 集合；child 失败时仅将关联 byte 标记错误，仍 drain
已 issue 的其余 child。一个 AXI R beat 只有在所需 byte 的数据或错误状态都就绪后才可发送；
已 issue parent 的逐 beat RRESP 只在 `OKAY/SLVERR` 间变化，`DECERR` 仅在尚未发 CHI 的
整 parent 拒绝时出现。任一 byte 出错时该 beat `RDATA` 固定为零，`RLAST` 只出现在原
AXI 最后 beat，绝不因错误提前结束。

AXI write 只在所有已产生 child 的最终 completion 到达后发送一个 B；已 issue parent
的 BRESP 为任一 child error 时 `SLVERR`，否则 `OKAY`；admission 拒绝才返回 `DECERR`。
跨多个 child 的写在出现错误时可能已部分提交；AXI response 报错不表示已提交 child 会
回滚。需要 all-or-nothing 语义时，必须由上层软件或客户系统提供事务机制。

DataID 到达顺序由 `DATAID_ORDER_POLICY` 决定：`ANY_ORDER` 时仅允许同一 TxnID、属于
child 预计算 expected 表且尚未收到的 DataID 乱序重排；`IN_ORDER` 时 ordinal 必须等于
`next_expected_ordinal`，否则为 profile/协议违规。重复、缺失、未知、越界或与 child
Size 不匹配的 DataID，以及未知 TxnID、非法 completion 和 credit 违反，均应立即作为
协议错误报告。shim 对 RSP/DAT 必须采用白名单：所有未批准 opcode 均为 protocol error。
V1 批准集合为：RSP opcode = `DBIDResp`、`CompDBIDResp`、
`Comp`；DAT opcode = `CompData`（读返回）。`RespSepData`、`DataSepResp`、
`ReadReceipt`、`CompAck`、`RetryAck`、`PCrdGrant` 及其余所有未批准 opcode 均为 protocol
error；不得仅返还 credit 后静默丢弃，否则关联 child 会无限等待。
缺失 response 使用验证 watchdog 和平台恢复策略诊断；adaptor 不应臆造 CHI timeout
并自动转换为 AXI error。

## 8. 客户集成契约

客户必须提供每个 adaptor 实例的版本化集成配置，至少包含：

- 私有 profile version、REQ/RSP/DAT/BE 字段宽度、`CHI_DAT_BYTES`、`CHI_DATAID_WIDTH`、
  DataID 编码表/算法版本、`DATAID_ORDER_POLICY`、支持 child Size 范围、时钟/reset/
  link-active 时序及 `LINK_DOWN_POLICY`。
- RNI `SrcID/NodeID`、默认 HN `TgtID`、`ReturnNID`/返回路由规则、该实例的静态访问类别和
  已批准 read/write opcode。NodeID 值可以恰好为零，但必须是客户 NoC 拓扑中已分配的真实
  身份，不能把零作为“隐式单对端”的占位值；profile shim 必须逐字段 pack 这些配置。
- L-credit 初值、RX credit return 速率和 epoch 规则；RNI 可达 HN/NoC 路径不产生
  RetryAck/PCrdGrant 的配置与断言证据，以及 DBID/completion 规则。
- HN 可能发送的已批准 `RespErr` 编码集合；AXI 映射以第 7.4 节为唯一权威。
- Endian 编码、NS/QoS 的默认值、V1 `Order=0` 的固定约束、AXI `AxPROT[1]` 与
  `NS_POLICY` 的匹配/拒绝规则、
  OpenNoC MemAttr 各 bit 的规范编码和断言、错误 policy，以及是否允许同一 Normal burst内
  的 beat 组合。
- `USABLE_CHI_TXNIDS`、各类 buffer/window 深度及第 7.2 节容量公式的满足证据。
- `axi_region_router` 是独立于本 RNI 的交付物，V1 不实现（无 router 时单 port 单静态
  `ACCESS_CLASS`）。未来若需单实例内混合 Device/Normal 访问，router 在 AXI slave 侧按
  `ADAPTOR_ADDR_MAP[]` 为每个 AR/AW 解析出该 transaction 的 `ACCESS_CLASS`，并随
  AW-route 队列传递给 RNI；RNI 只消费解析结果，不自行查表。router 的 AW-route FIFO
  深度、map-miss/overlap 错误策略由 router 规格单独定义。V1 RNI 本身按每实例一个静态
  `ACCESS_CLASS` 建模。
- link-up、初始 credit 初始化、adaptor AXI reset release 与 CPU Model/AXI master reset
  release 的时序波形及断言证据。
- 不向 adaptor 发送 SNP 的确认。

集成时先使用 protocol shim 对方向、宽度、字段和 link policy 做静态断言；之后才连接
客户真实 CHI IP。两侧边界均应保留 CHI monitor 与 trace。

在 `LINK_DOWN_POLICY=STALL` 下，平台必须先完成 LinkActive/SActive 与初始 credit 初始化，
再释放 adaptor AXI reset，最后释放 CPU Model/AXI master reset；不得依赖首个 AXI access
触发链路启动。若该次序无法保证，必须使用并验证独立启动编排器，或另行批准并验证
`LINK_DOWN_POLICY=DECERR`。

### 8.1 core 与 profile shim 的接口契约

decoded core 与 profile shim 的边界按字段所有权划分；任何字段都不得由两侧同时产生，
也不得在边界处缺少来源：

- **core 产出（REQ 语义字段）**：`Opcode`、`Addr`、`Size`、`TxnID`、Device/Normal
  分类位、`NS`（静态 `NS_POLICY` 决定的值，非 per-transaction 决策）、`Order`（V1 恒 0）、
  `QoS`、`AllowRetry`（V1 恒 0）。
- **shim 从集成配置注入**：RNI `SrcID/NodeID`、默认 HN `TgtID`、`ReturnNID`、`MemAttr` 的
  其余 bit、`SnpAttr=0`、`Endian=LE`、flit 保留位与 `RSVDC`。core 不产生这些字段；缺少
  任何路由身份或以未分配零值代替配置，均属于 Gate 0 配置错误。
- **shim 独占**：REQ/DAT 字段 pack、RSP/DAT 字段 unpack、NodeID 路由、MemAttr 完整
  编码、L-credit 计数、LinkActive/link handshake 与 credit epoch。core 只看到
  `valid/ready` 与 backpressure 快照，不参与 link/credit 状态。
- **路由身份不穿越 core 边界**：RSP 方向由 shim 保存每个 `TxnID/DBID` 对应的 completer
  身份（RSP flit 的 `SrcID`），并在该 child 的 TXDAT pack 时作为 `DAT.TgtID` 回填；decoded
  core 接口不携带 `SrcID/TgtID/ReturnNID`。

本契约是 Gate 0 中 core↔shim 静态断言（方向、宽度、字段 ownership）的唯一输入。
纯数值差异与结构/语义差异的判据见 §3.1.1。

## 9. 验证与准入门槛

### Gate 0：配置与链路

- 静态配置检查：revision、DAT/BE/DataID width、规范性 DataID 编码、RNI/HN NodeID 路由字段、
  MemAttr、访问类别和 opcode matrix。
- reset、LinkActive/SActive、每通道初始 credit，以及 link-up 到 CPU reset release 的启动顺序。

### Gate 1：功能映射

- Device：不同 size 的精确单 beat read/write、INCR/FIXED 严格 completion 顺序，证明即使
  在 burst 内也无 beat 组合和 over-fetch。
- Normal non-cacheable：同一 burst 内、静态策略允许时的精确分段/beat 组合、读数据重组和 partial write；以及跨 AXI transaction 不合并的断言。
- `LEN/SIZE`、byte lane、WSTRB、DataID、DBID、RLAST、BID/RID 的逐字段检查。
- `INCR` 的 1/2/4/8/16/32/64B beat、首尾边界与 4KB 边界；NormalNonCacheable
  `AxADDR=0x38/AxLEN=7/AxSIZE=4/INCR` 的精确分解；Device unaligned 的 `DECERR`。
- `FIXED` 的重复地址 read/write、逐 beat CHI child 数、严格 completion 顺序、
  WSTRB=0 的顺序位置以及无合并/去重断言。
- `WRAP`、FIXED unaligned、lock/exclusive 和非法 burst 的明确拒绝/错误响应。
- `AxPROT[1]` 与 NS policy 的匹配/拒绝、`AxUSER/AxREGION/AxQOS` 不传播断言。V1 不实现
  `axi_region_router`；router map 边界、跨 map、属性不匹配以及 AXI4 AW-route queue 的
  WLAST 出队和队头阻塞属于未来独立 router 交付物的验证范围。
- DAT lane/BE 地址取模、`S<CHI_DAT_BYTES`、64B 多 DAT、dense map 64 项上界、
  `ANY_ORDER` 全排列，以及 `IN_ORDER` 反序 DataID 的违规断言；写 BE 需分别验证
  Normal 的任意逐拍 BE（含全 0 拍）、Device 低于 `Addr` 的 lane 强制 deassert，
  以及 BE=0 时 DATA 字节置零。

### Gate 2：异常与流控

- credit=0、RX credit 收一还一、随机回补、backpressure、TxnID/window/buffer 耗尽。
- `AllowRetry=0` 固定编码、RetryAck/PCrdGrant 的 profile-violation 断言，以及客户
  HN/NoC 不产生该两类 flit 的配置和回归证据。
- `DBIDResp`、`CompDBIDResp`、`Comp` 的所有 V1 批准形状，包括 `DBIDResp -> Comp -> DAT`；
  DBID 到 DAT 的 TxnID/TgtID/SrcID 映射与资源释放断言；以及 `ExpCompAck=1` 的拒绝断言。
- AW admission 的 `MAX_WRITE_PARENT_BYTES/MAX_CHILD_PER_PARENT` 边界、资源不足的 AWREADY
  背压、非 OK DBIDResp 无 DAT、以及禁止 early `Comp` 的断言。
- AXI/CHI error、DataID 的所有到达排列、重复/缺失/越界 DataID、逐 beat RRESP/RLAST、
  AXI/CHI 各阶段 reset 与 link-down stall。router miss/跨 map 属于未来独立 router 交付物。

### Gate 3：系统回归

- 多 ID、同 ID admission、重叠地址、随机延迟和长时间无泄漏回归。
- 每个客户 target 输出 feature matrix、trace、assertion/coverage、已知限制和软件场景
  的 silicon escape risk。

### 当前交付物与规范的已知差距

以下条目为规范已要求、但仍未完成 Gate 级验证或配置闭环；在相应 Gate 通过前不得声明
对应能力已支持：

- §6.1.1 / §7.4 的 DataID：core 已使用 IHI0050E DataID packetization 规则，并由
  `DATAID_LAYOUT`/`ORDER_POLICY` 透传至顶层；尚缺 profile version 与客户配置文件之间的
  自动一致性断言，以及 128/256/512-bit 下多 DAT 的 Gate 1 回归。
- §7.3 的 L-credit：shim 已改为 TX credit 仅由对端 return/grant 增加，并以 RX ingress FIFO
  容量产生初始及收一还一 return；尚缺随机 credit、FIFO 满与 link re-epoch 的 Gate 2 回归。
  Retry/P-credit 不属于 V1 实现范围，客户“不产生 RetryAck/PCrdGrant”的部署保证仍须纳入
  Gate 0/Gate 2。
- §3.1 raw-flit 集成：raw RNI-to-HNF 顶层属于验证环境，不属于 `rtl/src/chi_rni` 的
  synthesizable 交付。验证环境须将 decoded core、OpenNoC shim、HNF 和下游 SNF/memory model
  连接为 raw REQ/RSP/DAT、L-credit、LinkActive 闭环；该环境尚待建立。
- 标准 NodeID 路由：shim 已从集成参数 pack REQ/DAT 身份，并记录 DBID response 的 `SrcID`
  以回填 write DAT `TgtID`；尚缺非零 NodeID、多 completer 和错误路由的 Gate 0/Gate 2 断言。
- §5 的 `axi_region_router`：仅为规范定义，V1 不实现、无 RTL；无 router 时单 port
  单静态 `ACCESS_CLASS`。

这些差距不改变 §10 的结论；它们标记了在对外宣称已完成 Gate 级 DataID、credit、路由和
标准 CHI raw-flit 集成验证之前必须补齐的工作。

## 10. 可交付结论

完成 Gate 0--3 后，方案一可声明支持：指定 CHI revision/profile 下、各 adaptor 实例静态
配置中批准的 Device/MMIO 或 Normal non-cacheable AXI 访问，以及不依赖 CPU Cache Coherence
的软件功能验证。

方案一不可声明支持：coherent CPU replacement、多核共享 cache、snoop、DVM、atomic、
exclusive、cache maintenance，或 Hybrid PASS 即等价于真实 CPU Cache 场景 PASS。
