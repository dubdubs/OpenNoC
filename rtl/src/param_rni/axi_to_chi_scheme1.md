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
| `NONCOHERENT` | MMIO、非共享 DRAM、DMA/direct access | `ReadNoSnp`、`WriteNoSnpPtl`，受限条件下 `WriteNoSnpFull` | `chi_rni_core.sv` + `chi_rni_opennoc_profile_shim.sv` |
| `OPENNOC_COHERENT` | cache-coherent memory | `ReadOnce`、`WriteUniquePtl`，以及其已验证的 DAT/response 流程 | 复用/抽取 `rtl/src/rni` 的 coherent request、retry、DBID 与 CompAck 逻辑 |

`OPENNOC_COHERENT` 直接采用现有 `rtl/src/rni/rni.v` 的 coherent RN-I 请求语义：它能
通过 `ReadOnce`、`WriteUniquePtl`、RetryAck/PCrdGrant、DBID、DAT 和可选 CompAck 流程
访问由 HN 管理的一致性内存。当前顶层没有 RX SNP 端口，这只表示本次集成必须按该接口
能力配置 HN 的 snoop 交互；它不否定该 RNI 对 cache-coherent memory 的访问能力。若后续
目标需要 RNI 直接接收/服务 SNP、维护本地 cache state、DVM、cache maintenance 或
atomic/exclusive，则须扩展接口、状态机和验证矩阵。

`AxCACHE/AxDOMAIN/AxPROT` 是事务属性，不等同于授权。对同一物理地址，软件不得在无
ownership transfer 的情况下混用两个 profile；coherent system 需要保持同一地址的一致
属性。[Arm AMBA LTI, A.4](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/IHI0089A_amba_lti.pdf)

## 2. 为什么不采用单一运行时开关

只用 elaboration parameter 不能在同一 AXI port 混合 MMIO 与 shareable memory；只用一个
live CSR 或 input pin 又会使在途 retry、DBID 和 response 在模式切换后被错误解释。仅从
`AxCACHE`/`AxPROT` 推断也不安全：前者只提供 AXI cache hint，后者主要承载特权/安全属性，
二者都不是可信的 coherent-RN 授权。

采用以下三层模型：

1. **静态能力参数**决定综合出的硬件能力，而非每笔模式：`ENABLE_NONCOHERENT`、
   `ENABLE_COHERENT_REQ`、`ENABLE_POLICY_CSR`、表项数、TxnID/queue 深度和支持 opcode。
   这些值 reset 后不可改变。
2. **安全/特权 CSR 区域策略表**决定一个地址、requester/StreamID 和安全域允许哪种
   profile。它是生产环境的权威选择器。
3. **每笔 AXI 属性**在策略允许的范围内细化属性；AXI `AxCACHE/AxDOMAIN/AxPROT` 必须被
   捕获。可选 `AxUSER.coh_intent` 只能在 `ALLOW_INTENT` 区域请求策略已允许的 profile，
   不能越权升级。

因此推荐“CSR 选区域、事务属性选已允许细节”，而非“全局模式寄存器”或“纯运行时参数”。
AXI 的 cache/domain 属性会影响需要访问的 cache 范围；桥不能忽略这个事实后任意改变
CHI 语义。[Arm AMBA AXI/ACE, D3](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/IHI0022H_amba_axi_protocol_spec.pdf)

## 3. 系统架构

```text
AXI AR/AW/W
     |
     v
+----------------------- unified AXI-to-CHI RNI -----------------------+
|  [spine] AXI admission -> attr capture -> policy resolver           |
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

必须只有**一个** raw-link、L-credit 和 NodeID 路径所有者。不得把 legacy `rni` 顶层与
`chi_rni_opennoc_profile_shim` 并联到同一链路：两者都会拥有 TX/RX credit 和 link state。
正确做法是共享 AXI admission、`axi_fragment_adapter`、parent/child bookkeeping、
`line_data_plane`、`chi_dat_adapter` 和 OpenNoC shim；从 legacy RNI 抽取 coherent request
engine 所需的逻辑分段、Retry、DBID 与 CompAck 控制。不得把 legacy 固定宽度的数据路径直接
移入 coherent engine。

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

`rni_link_ctl` 必须继续是唯一的 CHI 物理链路所有者：它集中 RXRSP/RXDAT、L-credit
return、TXREQ AR/AW 仲裁以及 TXDAT/TXRSP 发送门控；`rni_link_handshake` 和
`rni_lcrd_hdlr` 分别管理 link RUN 与每通道 credit。双 profile 只改变 entry 已锁存的
packet/profile state，不能复制或旁路这条 link/credit 数据流。

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

### 3.2 Coherent wire contract（首个不可拆分增量）

`OPENNOC_COHERENT` 不是给现有 non-coherent REQ 增加 opcode 位，而是一次完整的 decoded
core↔shim 契约升级。以下接口和状态机必须在同一个 RTL 增量中交付；在它们齐全前不得宣布
coherent profile 可用：

| 方向 | 强制字段/状态 | 规则 |
|---|---|---|
| TXREQ | `opcode`、完整 `MemAttr/SnpAttr`、allocate、`AllowRetry`、`ExpCompAck`、`TxnID`、`NS/Order/QoS` | 所有字段来自 child 的 immutable `req_attr`，shim 不得再隐式生成 coherent 属性。 |
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
{valid, base, limit, requester_mask/value, security_domain,
 allowed_profile, default_profile, allow_user_intent,
 ns_policy, order_policy, qos_policy, coherent_attr_policy, lock}
```

- 条目不得重叠；未命中、多个命中、security/requester 不匹配或所选 profile 未综合时，
  在 AXI admission 返回整个 parent 的 `DECERR`。
- `FORCE_NONCOHERENT`、`FORCE_COHERENT` 和 `ALLOW_INTENT` 是 `allowed_profile` 的三种
  受支持策略。`ALLOW_INTENT` 仅接受已授权的 `AxUSER.coh_intent`，否则选择
  `default_profile`。
- `NS` 只能由匹配的 `security_domain/ns_policy` 生成。Non-secure 请求不得借助 profile
  override 变成 Secure；coherency 不是访问权限。地址防火墙/TrustZone 检查仍必须独立生效。
- `AxCACHE/AxDOMAIN/AxPROT`、可选 intent、解析出的 profile、最终 opcode/MemAttr/SnpAttr/
  Order/AllowRetry、以及 `policy_epoch` 都要写入 parent/child trace。

建议从 reset default table 启动；当 `ENABLE_POLICY_CSR=0` 时，此表可由静态参数固化，仍使用
同样的 resolver 和 profile snapshot，避免产生两套事务语义。

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

V2 coherent 读固定 `ExpCompAck=0`（legacy `rni_arctrl` 亦然）：读不产生 CompAck，也不产生
读 DBID；§6.1 的 DBID/data-route 生命周期只适用于写 child。写路径的 `ExpCompAck` 可由客户
capability matrix 配置为 0 或 1。

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
| write completion | DBID/DAT/Comp；不发 CompAck | DBID/DAT/Comp；按 `ExpCompAck` 发 CompAck |
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

当前 `chi_rni` 的 AXI 端口没有 `AxCACHE`、`AxDOMAIN` 或 `AxUSER`，不能把这些字段称为
“已捕获”。V2 顶层必须选择且固定下列接口之一：

- **AXI4 基线**：暴露 `AxPROT`，另以集成 sideband 提供 `requester_id/security_domain`；
  policy 不使用不存在的 `AxCACHE/AxDOMAIN/AxUSER`，`ALLOW_INTENT` 在此配置下禁止。
- **扩展 AXI/ACE-Lite**：在 AR/AW 明确增加 `AxCACHE`、`AxDOMAIN` 和受控 `AxUSER.coh_intent`；
  它们在 handshake 进入 `axi_attr_capture`，并作为版本化接口的一部分接受 lint、CDC 和
  backward-compatibility 验证。

两种接口都不得由未定义输入推断 security、profile 或 CHI 属性。

### 5.5 每 model 的请求与完成 FSM

四个 FSM 全部挂 §7.1.1 的统一 engine 接口；nc 读写 FSM 由 Device/NonCacheable 共用，仅
`SEGMENT`/`WCOLLECT` 按 `access_class` 分叉；coherent 读写 FSM 独立。

```text
nc read FSM（ReadNoSnp，class ∈ {DEVICE, NOCACHE}）
  ADMIT -> SEGMENT -> ISSUE_REQ -> WAIT_DAT -> R_RESP -> DONE
    ADMIT:     AR handshake、attr capture、policy 锁存、parent/child 分配
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
6. AXI barrier 若在启用的上游接口出现，必须按 AXI 的 `AxID/AxBAR/AxDOMAIN/AxPROT` 规则
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
| `axi_attr_capture` | 在 AR/AW acceptance 锁存所有 AXI 属性和 address-burst 摘要 |
| `policy_resolver` + `policy_ram/csr` | shadow/active 策略表、授权、epoch、commit/quiesce |
| `axi_fragment_adapter` | 按 `AxADDR/AxSIZE/AxBURST`、beat ordinal 与 lane mask 生成规范化 line fragment；非对齐首拍不得扩展未选 byte |
| `line_data_plane` | 64B logical line / 16B canonical slot 存储、fragment scatter/gather、read error metadata 与按 beat 重组 |
| `chi_dat_adapter` | 唯一的 CHI DAT width/BE/DataID pack-unpack；使用 elaborated CHI DAT width，不解释 profile 完成语义 |
| `chi_rni_core` 演进版 | 公共 parent/child/fragment 表、AXI R/B、profile snapshot、共享 TxnID/DBID/reorder 仲裁 |
| `nc_request_engine` | 非一致分段（精确 non-snoop child）+ Read/WriteNoSnp 路径 |
| `coherent_request_engine` | 一致逻辑分段（64B line/16B slot 的 `ctmask/pdmask/bc_vec`）+ ReadOnce/WriteUnique、Retry/PCrd、DBID/CompAck；不得私有 DAT bank |
| `chi_rni_opennoc_profile_shim` 演进版 | 唯一 raw REQ/RSP/DAT pack/unpack、TXRSP/credit、NodeID、opcode profile、link owner |
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

模块间数据流固定为：`axi_attr_capture` -> `policy_resolver`（锁存）-> `axi_fragment_adapter`
-> `chi_rni_core` 公共 parent/child/fragment 表 -> 分派到 `nc_request_engine` 或
`coherent_request_engine`；两个 engine 通过 `dat_plan` 使用同一 `line_data_plane` 和
`chi_dat_adapter`，再经统一 TxnID/DBID map 与 reorder 到 `chi_rni_opennoc_profile_shim`
（唯一 raw pack/credit/link owner）。`profile_hazard_monitor` 只观察 spine 的
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
  均是静态参数；还缺 §5.4 所定义的 AXI4 sideband 或扩展 AXI/ACE-Lite 顶层契约。
- `chi_rni_core.sv` 仅定义 non-snoop opcode，`chi_rni_defines.svh` 也仅有
  `ReadNoSnp/WriteNoSnp*` 常量；必须增加 §3.2 的版本化 coherent `req_attr`、RXRSP、
  retry/PCrdGrant 与 TxnID 合同。
- `chi_rni_opennoc_profile_shim.sv` 当前硬编码 non-coherent `MemAttr` 并固定
  `AllowRetry=0`，且没有 raw TXRSP/RSP credit；要支持 coherent profile 必须完成 §3.2 的
  decoded interface、RSP/DAT handling、CompAck pack 和 credit 状态机。
- legacy RNI 已实现 coherent memory access 所需的 retry/PCrd 与 CompAck 请求控制；无
  RX SNP 是当前接口能力的集成约束，只有目标要求直接 snoop 服务时才成为扩展项。
- 当前 `chi_rni` link-active/credit/`FLITPEND` 行为与 legacy `rni_link_handshake` 不等价；
  选择哪一种时序模型必须在 profile shim 中版本化，不能以“同为 LinkActive”假定互通。

## 8. 集成契约

每个客户集成须提供版本化 capability matrix：CHI revision/flit layout、NodeID 路由、DAT/BE/
DataID 宽度与编码、TXREQ/TXDAT/TXRSP 的 credit 初值/返还/link/`FLITPEND` 时序、每 profile
允许的 request/response/retry/PCrdGrant/CompAck、MemAttr/SnpAttr 编码、§6.1 的可用 TxnID/
DBID 容量，以及 HN 对该 coherent RNI 接口能力的配置确认。

集成还必须在 elaboration 固定数据面参数：AXI4 full `WDATA/RDATA` 只能取
`{8,16,32,64,128,256,512,1024}` bit，CHI `DAT.DATA` 只能取 `{128,256,512}` bit，且
`CHIE_BE_WIDTH == CHIE_DATA_WIDTH/8`。64B line/16B slot 是固定内部布局。profile、CSR
policy 与 `policy_epoch` 只选择访问语义，绝不可在运行时修改上述接口位宽、DAT DataID
映射或 buffer 布局；改变位宽必须重新 elaboration、reset 并重新完成 capability 验证。

还必须交付策略表的 reset 映像、CSR 安全访问控制、地址 firewall、每个 shareable region 的
software ownership-transfer 说明，以及无 RX SNP 接口下的 HN 行为证明：HN 不得把本节点当作
snoop target，也不得授予要求此节点后续回送稳定/脏 line 数据的状态；若不能证明，
`WriteUniquePtl` 不在该集成的 coherent capability matrix 内。平台还须交付
`COORDINATED_RESET` 的 link-down/AXI reset/HN abort 时序波形。profile shim 是所有 raw 字段
与 credit 差异的唯一归属；core 不得自行拼 raw flit 或管理 L-credit。

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

推荐的生产方案是：**静态能力参数 + secure CSR 区域策略表 + 每笔事务属性锁存**。它允许
同一 RNI 安全地发出非一致性和经 HN 批准的一致性请求，同时避免全局运行时切换破坏在途
事务。实施顺序被固定为：

1. 完成 §3.2 coherent wire contract、§6.1 ID/DBID 生命周期及 `COORDINATED_RESET`；
2. 完成 profile snapshot、CSR commit、AW/WCOLLECT drain 与 line hazard；
3. 接入 coherent request engine，并以 capability matrix/Gate 0--3 验证；
4. 仅在前三步闭环后扩大 opcode、autonomous recovery 或 snoop 能力。

第 1 步未完成前，`OPENNOC_COHERENT` 只能是架构目标，不能连接到当前 `chi_rni` shim。
