# AXI2CHI Non-Coherent 方案

本文档定义 `axi2chi_nocoh`。它是独立的 AXI-to-CHI non-coherent bridge，不能与
`axi2chi_coh` 共用在途事务状态、DBID 表或 CHI raw link owner。

## Step 1：Specification Analysis

### 功能与事务边界

- AXI AR 转换为 CHI `ReadNoSnp`。
- AXI AW/W 默认转换为 `WriteNoSnpPtl`。
- 仅当写事务完整覆盖一个 cache line、cache-line 对齐、所有 byte enable 有效，且
  `enable_write_no_snp_full=1` 时，允许使用 `WriteNoSnpFull`。
- 读数据经 AXI R 返回；写在 DBID、TXDAT 与最终 Comp 完成后经 AXI B 返回。
- 首版 `AllowRetry=0`，不实现 `RetryAck`/`PCrdGrant`、snoop、DVM、atomic、exclusive、
  cache maintenance 或 coherent ownership。

AXI AR/AW/W、R/B 均使用 valid/ready。AR/AW 只有在 parent context 和相应 buffer 有空位时
才能握手；AXI4 W 无 WID，必须按已接受的 AW 顺序归属。CHI TXREQ/TXDAT 发送同时受
LinkActive 与可用 credit 约束。R/B 被反压时，完成数据或状态必须保存在本地，直到 AXI
握手。

首版已冻结的 AXI 规则：

- 支持 `INCR` 和 `FIXED` burst；不支持 `WRAP`。
- 支持 unaligned 与 narrow transfer。所有 AXI beat 先归一化为地址、有效 byte lane、数据与
  beat sequence；每个 AXI beat 独立形成 CHI child，绝不跨 beat 合并。若一个 unaligned beat
  跨 cache-line 边界，则拆为两个仅覆盖各自 line 的 CHI child fragment。`FIXED` 的每个 beat
  保持原地址，不能因为地址相同而错误合并为 full-line write。
- 同一 AXI ID 允许多笔 outstanding，但 R/B 必须按该 ID 的接收顺序 retire。`txn_ctx`
  为每个 AXI ID 维护 issue/retire 顺序；后完成的 transaction 即使已有数据/Comp，也必须等待
  该 ID 更早 transaction retire 后才能对 AXI 宣称 valid。

默认生成配置为 `axi_data_width=128`、`chi_dat_width=256`、`cache_line_bytes=64`。
`cache_line_bytes` 允许取 `32/64/128` B。三者均为 elaboration-time 参数，且 AXI 与 CHI 的
每拍 byte width 必须分别整除 `cache_line_bytes`；不满足该关系的配置由生成器拒绝。

### 生成配置

输入配置为 `configs/axi2chi_nocoh.yml`，其 `profile` 必须为 `axi2chi_nocoh`。至少包含：

- `axi_data_width` 与 `chi_dat_width` 必须独立配置。首版允许 AXI 取
  32/64/128/256/512 bit，CHI DAT payload 取 128/256/512 bit；两者必须相等或为整数倍关系。
- 默认值为 `axi_data_width=128`、`chi_dat_width=256`、`cache_line_bytes=64`；
  `cache_line_bytes` 仅允许 `32/64/128` B。
- AXI address/ID/LEN/USER width 与 burst 支持项。
- CHI NodeID、TxnID/DBID width、cache-line size、flit packing 版本。
- read/write parent depth、write-data/read-response buffer depth 和 link receive depth。
- `parent_entries`、`read_data_context_entries`、`write_data_context_entries` 与
  `dbid_map_entries`。所有 outstanding 均为有限、可参数化资源，不能声明为无限制。
- `enable_write_no_snp_full`、输出顶层名、生成目录与 manifest 名。

生成器必须拒绝 coherent opcode、`enable_retry_pcrdgrant=1`、非法 depth/width 及未知字段。
它只能生成参数 package、顶层 wrapper skeleton、filelist/manifest 与配置报告；不能生成或
决定 DBID 生命周期、DataID 排序、AXI ordering、credit 行为或 FSM。

`parent_entries` 是最大 AXI outstanding 的硬上限，且必须小于等于可分配 TxnID 数；实际
admission 上限还受对应读/写 data context、DBID map 与 AXI ID retire queue 空闲项限制。
默认建议 `parent_entries=16`、`read_data_context_entries=16`、`write_data_context_entries=16`、
`dbid_map_entries=16`。增大这些参数会推导更多 context RAM、比较器和 per-ID 排序状态。

`WriteNoSnpFull` 仅允许一个 AXI W beat 本身完整、对齐地覆盖一个 cache line，且所有该 line 的
byte strobe 有效时使用。因此默认 `axi_data_width=128`、`cache_line_bytes=64` 的配置不会生成
`WriteNoSnpFull`；多拍 burst 即使恰好覆盖完整 line，首版仍逐拍生成 `WriteNoSnpPtl`。

## 候选模块架构

下列是进入 Step 2 后的候选 RTL 划分，不是已经实现的 RTL。每个模块归属于
`axi2chi_nocoh`，在途状态不跨模块重复持有。

| 模块 | 硬件职责 | 主要状态/接口 | 复用关系 |
|---|---|---|---|
| `axi2chi_nocoh_cfg_pkg` | 由 YAML 生成的静态参数、opcode 许可与类型 | 无时序状态 | 可与 `axi2chi_coh` 共享基础 CHI typedef，但 profile 常量独立 |
| `axi2chi_nocoh_top` | 唯一集成点，连接 AXI、core-side flit 与 raw CHI link | 不持有 transaction 状态 | 参考现有 `rni_axi_chi_top.sv` 的顶层边界 |
| `axi2chi_nocoh_slave` | AXI AR/AW/W 接收与 R/B pin-level handshake，维持 AW/W 顺序 | AW order queue；不保存 transaction completion | 可参考 `rni_axi_ingress.sv`，不得复用 coherent parent table |
| `axi2chi_nocoh_rd_engine` | 形成 `ReadNoSnp`、接收完成事件并推进读 transaction FSM | 仅读控制状态 | context 由 `txn_ctx` 唯一拥有；不含 Retry |
| `axi2chi_nocoh_wr_engine` | 判定 Ptl/Full、形成 write REQ、处理 DBID/Comp 事件 | 仅写控制状态 | context 由 `txn_ctx` 唯一拥有；不含 PCrdGrant |
| `axi2chi_nocoh_txn_ctx` | 唯一拥有 parent context、TxnID lookup、DBID、完成状态与释放条件 | parent table、TxnID map、DBID map、AXI ID、error/complete | `txnid_alloc` 只作为其内部 allocator；不可与 coherent 实例共享 |
| `axi2chi_nocoh_wr_data` | 接收 AXI W，按宽度关系聚合/拆分为 CHI DAT fragment | line/fragment RAM、WSTRB mask、AXI beat/CHI fragment progress | 取代简单 W FIFO；可参考 `rni_wr_buffer.v` 的存储职责 |
| `axi2chi_nocoh_rd_data` | 接收 RXDAT，按宽度关系聚合/拆分并在 RREADY 停顿时保留 AXI R | line/fragment RAM、DataID mask、AXI beat/CHI fragment progress | 取代简单 R FIFO；可参考 `rni_rd_buffer.v` 的存储职责 |
| `axi2chi_nocoh_chi_codec` | pack/unpack 本 profile 允许的 REQ/RSP/DAT 字段 | 组合逻辑 | 可参考 `rni_chi_codec.sv`，opcode 白名单固定 |
| `axi2chi_chi_link` | raw CHI link 的唯一 owner：LinkActive、RX dispatch、TX arbitration 与 per-channel credit | link FSM、credit counters、channel buffer control | 公共 transport 源码；每个物理 port 只能例化一个 owner |

`axi2chi_chi_link` 内部按 CHI transport 命名分层：`axi2chi_chi_channel` 负责 raw port 与
LinkActive 状态，`axi2chi_chi_rxflit` 负责 RXRSP/RXDAT 接收 queue 和 L-credit return，
`axi2chi_chi_txflit` 负责 TXREQ/TXDAT/TXRSP queue 与仲裁，`axi2chi_chi_credit` 是仅由
`axi2chi_chi_link` 例化的 per-channel credit counter。它们均不得由 top 或 transaction 层
直接驱动 raw CHI 信号。

数据流为：

```text
AXI AR -> axi_slave -> txn_ctx + rd_engine -> chi_codec -> chi_link -> CHI TXREQ
CHI RXDAT -> chi_link -> chi_codec -> rd_engine -> rd_data -> AXI R

AXI AW/W -> axi_slave -> txn_ctx + wr_engine + wr_data
wr_engine -> chi_codec -> chi_link -> CHI TXREQ
wr_data + DBID -> wr_engine -> chi_codec -> chi_link -> CHI TXDAT
CHI RXRSP(DBID/Comp) -> chi_link -> chi_codec -> txn_ctx + wr_engine -> AXI B
```

CHI error response 映射为 AXI `SLVERR`；`DECERR` 只用于 bridge 在 AXI admission 前即可判定的
本地 decode/配置错误。`CompDBIDResp` 必须被 decoder 识别并原子写入 DBID 与 completion event；
若 write data 尚未完整收集或所需 TXDAT 尚未发完，txn_ctx 记录 protocol-error 并以
`SLVERR` 完成，而不是提前释放 context 或伪造成功 B response。

### Link 与 Reset 策略

- reset 释放后，`axi2chi_chi_link` 主动发起 LinkActive handshake；仅当 link 进入 `RUN` 且 credit
  初始化完成时，允许新的 AXI AR/AW admission。
- 正常下电：先停止新的 AXI admission，等待 txn_ctx、TX queue、RX queue 全部 drain，
  再撤销 LinkActive。RX buffer 满时不归还对应 L-credit，以阻止 peer 继续发送；credit 只能在
  flit 已被安全写入数据面或已释放 RX slot 后归还。
- 非预期 link-down 或 reset：不合成 AXI 成功/错误 response，因为对端 CHI transaction 结果不可知。
  正常 SoC 集成应将其视为 fabric reset/containment：先 quiesce AXI master，再清空 context、
  buffer、credit 与 allocator。若系统要求 link fault 后继续运行，必须另行定义可证明的 abort
  协议，才允许返回 `SLVERR`。

## Step 2：Microarchitecture Design

### 1. 设计原则与事务粒度

首版采用 **beat-exact non-coherent bridge**：一个 AXI burst 是一个 parent transaction；每个
AXI beat 是一个独立 child transaction。一个 beat 只要没有跨 cache-line，就只占一个 child；
若 unaligned byte range 跨 cache-line，拆成两个 child fragment。所有 child 的 CHI opcode 由
该 child 的有效 byte range 决定，绝不因相邻 beat 或相同地址做合并。

这使 `INCR`、`FIXED`、narrow 和 unaligned 的 AXI 可观察语义保持不变：`FIXED` beat 永远单独
访问相同地址；`INCR` 仅改变下一个 beat 的地址。代价是一个 `LEN=255` burst 最多产生 256 个
正常 child，且 child table 满时 scheduler 停止生成新的 child，而 parent 仍安全保留在 context
table 中。

```text
AXI AR/AW parent
  -> per-ID retire queue entry
  -> beat sequencer (0 .. AWLEN/ARLEN)
  -> one or two CHI child fragments per AXI beat
  -> CHI REQ / DBID-DAT-Comp or RXDAT
  -> AXI beat completion
  -> parent final RLAST or B
```

### 2. 模块间接口与所有权

| 连接 | 方向 | 协议 | 含义 |
|---|---|---|---|
| `axi_slave` -> `txn_ctx` | AR/AW admission | valid/ready + command payload | 仅在 parent slot、per-ID queue 与所需 write admission resource 可保留时握手 |
| `axi_slave` -> `wr_data` | W beat | valid/ready + AXI data/strb/last + parent index | W 按 AW-order queue 绑定；`wr_data` 接收后保证数据稳定保存 |
| `txn_ctx` <-> `rd_engine` / `wr_engine` | context command/event | request/response valid-ready | engine 读取 context、请求 child allocation、提交 CHI event；只有 `txn_ctx` 写 context RAM |
| `rd_engine` <-> `rd_data` | read fragment | child index、byte range、RXDAT payload、commit | `rd_data` 写入 fragment 并在可形成下一个 AXI R beat 时通知 context |
| `wr_engine` <-> `wr_data` | write fragment | child index、byte range、DBID、TXDAT request/ready | `wr_data` 在 TXDAT handshake 前保持 payload、BE 和 child index 不变 |
| engine <-> `chi_codec` | canonical flit fields | 组合 payload | codec 无 valid bit、无状态、无 credit；只 pack/unpack |
| engine <-> `axi2chi_chi_link` | TXREQ/TXDAT 与 RXRSP/RXDAT | 每 channel valid/ready | valid 在 payload 被接受前保持；link 不理解 TxnID/DBID 语义 |
| `rd_data` / `txn_ctx` -> `axi_slave` | AXI R/B response | valid/ready | R/B payload 在对应 AXI ready 前稳定；retire permission 必须来自 `txn_ctx` |

### 3. `axi2chi_nocoh_txn_ctx`

`txn_ctx` 是唯一的 transaction lifetime owner，综合为 context RAM/寄存器阵列、TxnID lookup
table、per-ID FIFO 指针和 allocator bitmap。它不组包 flit，也不直接驱动 AXI/CHI pin。

主要表项如下；`P_IDX_W=$clog2(PARENT_ENTRIES)`、`C_IDX_W=$clog2(CHILD_ENTRIES)`、
`BEAT_W=$clog2(MAX_AXI_BEATS)`、`LINE_OFF_W=$clog2(CACHE_LINE_BYTES)`。

| 寄存器/表 | 宽度 | reset | 更新条件 | 用途 |
|---|---:|---|---|---|
| parent entry | `PARENT_ENTRIES x parent_t` | `valid=0` | AR/AW admission；parent retire | 保存 AXI ID、addr、len、size、burst、is_write、next issue/complete beat、error、child count |
| child entry | `CHILD_ENTRIES x child_t` | `valid=0` | child alloc；CHI event；child retire | 保存 parent index、AXI beat index、fragment offset/bytes、TxnID、DBID、REQ/DAT/Comp 状态 |
| TxnID map | `2^TXNID_W` valid/index 或 CAM | invalid | child TXREQ alloc/free | 将 RXRSP/RXDAT 的 TxnID 路由到唯一 child |
| DBID fields | 在 write child 内 | `dbid_valid=0` | DBIDResp/CompDBIDResp fire | 保存 DBID、responder NodeID；仅 `wr_engine` 在状态条件满足时请求使用 |
| per-ID retire FIFO | `AXI_ID_COUNT x depth` | empty | parent admission/retire | 同 ID 多 outstanding 的接收顺序；仅队首 parent 可向 AXI 提交 R/B |
| parent/child free bitmap | `PARENT_ENTRIES` / `CHILD_ENTRIES` | all free | allocate/free fire | admission 和 scheduler 的资源判定 |

`parent_t` 至少包含 `axi_id`、`start_addr`、`len`、`size`、`burst`、`is_write`、
`next_issue_beat`、`next_retire_beat`、`completed_beat_count`、`w_beats_seen`、`error_seen`、
`all_children_issued`、`all_children_complete`。`child_t` 至少包含 `parent_idx`、`axi_beat_idx`、
`frag_idx`、`frag_addr`、`frag_byte_offset`、`frag_byte_count`、`txnid`、`dbid`、`dbid_valid`、
`req_sent`、`dat_sent`、`comp_seen`、`rxdat_seen`、`resp_error`。

在每个 `clk` 上升沿，admission fire 才写入新 parent；TXREQ fire 才使 child `req_sent=1`；
RXRSP/RXDAT fire 才更新 DBID、completion 或 error；AXI R/B fire 才 retire parent/child。任何
ready 低、credit 不足或 AXI backpressure 都不会改变未 fire 的 entry。

### 4. 读路径：`rd_engine` 与 `rd_data`

`rd_engine` 保存 child scheduler/FSM，不保存 AXI 或 CHI transaction payload。为避免同一 parent
内的 AXI read reordering，首版每个 parent 同时最多一个 read child 在 flight；不同 parent 可以
并行发出 CHI request，受 `CHILD_ENTRIES` 与 TXREQ credit 限制。

```text
RD_IDLE -> RD_ALLOC -> RD_ISSUE_REQ -> RD_WAIT_DAT
        -> RD_COMMIT_DATA -> RD_WAIT_RETIRE -> RD_IDLE
```

- `RD_ALLOC`：从 parent 的 `next_issue_beat` 计算 AXI beat address 和有效 byte range；跨 line 时
  先发 fragment 0，fragment 1 在 fragment 0 完成后发出。child allocation 失败则保持状态。
- `RD_ISSUE_REQ`：由 codec 产生 `ReadNoSnp`。只有 `chi_link.txreq_ready=1` 的时钟沿才发送并写
  `req_sent`；link stall 时 address、TxnID、size 和 payload 全部保持。
- `RD_WAIT_DAT`：仅接收 TxnID 命中的 RXDAT。错误 response 同时记录 `resp_error`；未知 TxnID
  不修改任何 context，并进入 link/error counter 路径。
- `RD_COMMIT_DATA`：`rd_data` 将 CHI payload 的 byte lane 复制到 AXI beat assembly slot。若一个
  AXI beat 有两个 child fragment，只有两个 required-byte mask 均完成才形成 R beat。
- `RD_WAIT_RETIRE`：仅当 parent 位于该 AXI ID retire FIFO 队首时，向 `axi_slave` 提供 R；
  `rvalid && rready` 后释放 child，增加 `next_retire_beat`。`RLAST` 仅在
  `axi_beat_idx == len` 的 AXI R beat 上置位。

`rd_data` 由每个 active read parent 的 AXI beat assembly RAM、valid-byte mask、error-byte mask
和 response holding register 组成。默认 `AXI=128b`、`CHI_DAT=256b` 时，RXDAT 的 32B payload
按 child `frag_addr` 与 AXI beat byte range 选择相交 bytes；不向 AXI 返回额外的 CHI payload bytes。

### 5. 写路径：`wr_engine` 与 `wr_data`

`wr_data` 在 `WVALID && WREADY` 的上升沿写入 AXI beat store。它以 AW-order queue 给出的 parent
index 归属 W；`WLAST` 必须与该 parent 的 `len` 对应。过早/过晚 WLAST、W beat 数超过 LEN 或
WSTRB 覆盖非法 lane 均置 parent `error_seen`，但已经接收的数据不被覆盖。

每个完整 W beat 建立一个或两个 write child fragment。首版不等待整个 burst 收齐：一个 beat 被
`wr_data` 保存并形成 child 后即可由 `wr_engine` 发请求。因此大 burst 不需要一次性缓存全部 W
数据；已完成 TXDAT 的 data slot 在 child 最终 Comp 后可释放。

```text
WR_IDLE -> WR_WAIT_W -> WR_ALLOC -> WR_ISSUE_REQ -> WR_WAIT_DBID
        -> WR_ISSUE_DAT -> WR_WAIT_COMP -> WR_COMPLETE -> WR_IDLE
```

- `WR_ALLOC`：计算 fragment address、有效 byte mask。只有单 AXI beat 完整对齐覆盖一个 line、
  `WSTRB` 全 1 且 `enable_write_no_snp_full=1` 时，opcode 选择 `WriteNoSnpFull`；否则固定为
  `WriteNoSnpPtl`。
- `WR_ISSUE_REQ`：TXREQ fire 后锁定 child TxnID。请求未 fire 前，child 不可接收 DBID。
- `WR_WAIT_DBID`：接收匹配 `DBIDResp`；收到 `CompDBIDResp` 时同时记录 DBID/Comp，但只有
  `dat_sent=1` 才允许完成，否则置 protocol error。
- `WR_ISSUE_DAT`：仅当 `dbid_valid && wr_data.fragment_valid && txdat_ready` 时发送。TXDAT 的
  payload 包含当前 child 的 DBID、DataID、full CHI data width 与 byte enable；未被 AXI WSTRB
  覆盖的 bytes 置零且 BE=0。
- `WR_WAIT_COMP`：等待匹配 Comp；Comp fire 后 child 完成。parent 的所有 beat/fragment 都完成、
  且该 parent 为同 ID retire FIFO 队首时，`axi_slave` 才产生一个 B response。

### 6. CHI transport：`axi2chi_chi_link`

`axi2chi_chi_link` 只处理 transport，内部四个子模块的时序职责如下：

| 子模块 | 时序状态 | 输入输出与 stall 行为 |
|---|---|---|
| `axi2chi_chi_channel` | LinkActive FSM：`RESET/ACTIVATE/RUN/DRAIN` | reset 后主动 request；只有 `RUN` 向 TX 开门；DRAIN 阻止新 TXREQ，等待 queue 和 credit drain |
| `axi2chi_chi_txflit` | 每 channel 1-entry skid 或参数化 FIFO、TX arbiter pointer | REQ 仲裁 rd/wr；DAT 为 write child；RSP 首版空闲。payload 在 valid 到 ready/fire 前保持 |
| `axi2chi_chi_rxflit` | RXRSP/RXDAT FIFO pointers 与 occupancy | 仅 FIFO 有空或同拍 pop 时接受 flit；接收后向 core 给 ready/valid event |
| `axi2chi_chi_credit` | REQ/RSP/DAT TX credit counter；RX return eligibility | TX credit 只在外部 L-credit 增加、TX fire 减少；RX L-credit 只在 RX slot 对 core 成功转交/释放时返还 |

RXRSP 与 RXDAT 各有独立 FIFO，深度由 `link_receive_depth` 配置；必须至少为 2，避免同拍
consume/refill 时的零深度组合环。所有 raw flit、FLITV、LCRDV、LinkActive 信号只由此模块驱动。

### 7. 时序示例

默认配置下，一个 128-bit AXI write beat 到 256-bit CHI DAT 的理想无 stall 顺序：

```text
C0: AW handshake，txn_ctx 分配 parent，axi_slave 将 parent 推入 AW-order queue
C1: W handshake，wr_data 写 16B + WSTRB；wr_engine 分配 child/TxnID
C2: WR_ISSUE_REQ，TXREQ(WriteNoSnpPtl) fire
C3..Cn: 等待 RXRSP(DBIDResp)
Cn+1: DBIDResp fire，txn_ctx 写 DBID；WR_ISSUE_DAT fire，TXDAT payload 的低/高 lane 按地址选择
Cn+2..Cm: 等待 Comp
Cm: Comp fire，child complete；若该 burst 全部 child complete 且为 per-ID 队首，BVALID=1
Cm+1: BREADY fire，释放 parent/child/data slot/TxnID
```

在任意一个等待周期，若 link credit、link `RUN`、TX FIFO、RX FIFO 或 AXI ready 不满足，前一
状态的寄存器和值保持不变；不允许重新分配 TxnID、重发 TXREQ、重复写 data RAM 或重复产生 R/B。

### 8. 性能、面积与验证敏感点

- 默认 `PARENT_ENTRIES=16`、`CHILD_ENTRIES=16`，read parent 内单 child in-flight；这是吞吐与
  可验证性优先的首版。后续可参数化为每 parent 多 child，但必须增加 per-parent reorder bitmap。
- `rd_data/wr_data` 按 active child 存储 AXI beat assembly，不按整个 burst存储；面积近似随
  `CHILD_ENTRIES * max(AXI_BYTES, CHI_DAT_BYTES)` 增长。
- 必须断言：TxnID map 唯一；DBID 仅写入已发 REQ 的 write child；TXDAT 仅在 DBID/data valid；
  child 不在 AXI R/B fire 前释放；同 ID 的 retire FIFO 不越序；credit 不下溢、不溢出。
- 重点 testcase：FIXED read FIFO 语义、同 ID 两笔 read 的后笔先完成、unaligned beat 跨 line、
  narrow WSTRB、TX credit=0、RX FIFO 满、DBID/Comp 顺序、RREADY/BREADY 长时间停顿和 reset。

### 9. Step 2 完成结论

`axi2chi_nocoh` 的 datapath、control path、buffer/FIFO、context ownership、pipeline 边界、
clock/reset 行为及验证敏感点已定义。进入 Step 3 前唯一需要以项目 CHI include/codec 核验的是：
跨 line child fragment 的 `ReadNoSnp` size/address 编码与 TXDAT DataID 编码；这不会改变上述
模块边界，但会决定 codec 的具体 field assignment。

## 验证焦点

- reset 后 valid/credit/allocator/DBID map 全部清零。
- 连续 AR、连续 AW/W、AW 与 W 延迟到达、R/B backpressure。
- `WriteNoSnpFull` 合法与非法边界、WSTRB/ WLAST 错误、buffer full。
- credit 耗尽、LinkActive 未完成、DBID/Comp 顺序及未知 TxnID/DBID。
