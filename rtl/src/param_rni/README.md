# param_rni

`param_rni` 是 OpenNoC 中参数化 AXI4-to-CHI RN-I 的当前实现目录。它在一套 AXI
ingress、事务表、数据缓冲和 CHI 链路上支持两个请求 profile：

- `OPENNOC_COHERENT`：`ReadOnce`、`WriteUniquePtl`
- `NONCOHERENT`：`ReadNoSnp`、`WriteNoSnpPtl`

本目录的设计目标由 [axi_to_chi_scheme1.md](./axi_to_chi_scheme1.md) 定义。本文描述的是
**当前 RTL 已经实现并验证的能力**，不是方案文档中所有目标能力的承诺。

## 1. 当前结论

当前可用于功能仿真的数据面配置是：

| 参数 | 当前功能配置 |
|---|---:|
| AXI data width | 128 bit |
| CHI DAT width | 256 bit |
| CHI BE width | 32 bit |
| cache line | 64 byte |
| canonical slot | 4 × 16 byte |
| clock/reset | 单时钟；高有效异步复位 |

RTL 已实现 coherent/noncoherent profile 的基本读写流程、V2 TxnID 编码、DBID/DAT/Comp、
可选 CompAck、RetryAck/PCrdGrant 骨架、link credit、策略 CSR 基础功能和首 cache-line
hazard。

独立的参数化数据面现已实现 AXI `8..1024` bit fragment、64B canonical line 的逐 byte
scatter/gather，以及 CHI DAT `128/256/512` bit 的 DataID/BE pack/unpack，并有模块级功能
自检。它尚未替换 legacy `rni_segburst/rni_rd_buffer/rni_wr_buffer` 的顶层控制路径，因此
顶层 elaboration guard 仍拒绝非 `AXI=128/CHI DAT=256/BE=32` 的完整 RNI 配置；模块级通过
不能解释为 24 组真实 RNI 已开放。

## 2. 目录与依赖

```text
rtl/src/param_rni/
├── rni.v                         顶层集成
├── rni_axi_bus.v                 AXI 五通道打包/拆包
├── rni_arlink.v / rni_awlink.v   AR/AW ingress FIFO
├── rni_segburst.v                AXI burst 到 64B line/slot 描述
├── rni_arctrl.v / rni_awctrl.v   读/写事务表和协议状态机
├── rni_rd_buffer.v               CHI RXDAT 到 AXI R
├── rni_wr_buffer.v               AXI W 到 CHI TXDAT、AXI B
├── rni_datbuf_bank.v             数据 bank
├── rni_bcount_ctl.v              beat 计数
├── rni_misc.v                    PCrdGrant 缓冲和仲裁辅助
├── rni_link_ctl.v                唯一 CHI raw-link/credit owner
├── rni_link_handshake.v          link activation 状态机
├── rni_lcrd_hdlr.v               单通道 L-credit 计数
├── rni_policy_csr.v              shadow/active policy CSR
├── rni_line_hazard.v             cache-line profile hazard
├── rni_scheme1_static_assert.v   参数契约检查
├── rni_axi_fragment_adapter.v    AXI beat 到 1/2 个 line fragment
├── rni_fragment_dispatch.v       child/line-plane 原子资源提交边界
├── rni_line_data_plane.v         64B canonical line、W scatter/R gather
├── rni_chi_dat_adapter.v         CHI DAT DataID/BE scatter/gather
├── axi_to_chi_scheme1.md         V2 方案规范
└── width_parameterization_plan.md 宽度参数化计划
```

公共宏和默认参数位于：

- `rtl/include/rni_param.v`
- `rtl/include/rni_defines.v`
- `rtl/include/axi4_defines.v`
- `rtl/include/chie_defines.v`

仿真入口为 `rtl/file_list_param_rni_tb.f` 和 `rtl/Makefile`。

## 3. 总体架构

```text
                         +-----------------------+
AXI AR/AW/W ------------>| rni_axi_bus           |
                         +-----------+-----------+
                                     |
                    +----------------+----------------+
                    |                                 |
             +------v------+                   +------v------+
             | rni_arlink  |                   | rni_awlink  |
             +------+------+                   +------+------+
                    |                                 |
             +------v------+                   +------v------+
             | rni_segburst|                   | rni_segburst|
             +------+------+                   +------+------+
                    |                                 |
             +------v------+                   +------v------+
             | rni_arctrl  |                   | rni_awctrl  |
             | AR entries  |                   | AW entries  |
             +--+--------+-+                   +--+--------+-+
                |        |                        |        |
             TXREQ    RXDAT/RSP                TXREQ    DBID/Comp
                |        |                        |        |
                |  +-----v--------+      +--------v-----+  |
                |  | rni_rd_buffer|      | rni_wr_buffer|<-+--- AXI W
                |  +-----+--------+      +--------+-----+
                |        |                        |
                |       AXI R                 TXDAT / AXI B
                |                                 |
                +----------------+----------------+
                                 |
                         +-------v--------+
                         | rni_link_ctl   |
                         | one link owner |
                         +-------+--------+
                                 |
                         CHI REQ/RSP/DAT + L-credit
```

`rni.v` 还在 AXI admission 前集成：

- `rni_policy_csr`：按地址、requester、安全域和 intent 解析 profile。
- `rni_line_hazard`：阻止同一首 cache line 的不同 profile 同时进入。
- outstanding/quiesce：policy commit 等待在途事务排空后切换 active bank。

所有模块处于同一时钟域，没有 CDC。各 FIFO、entry 和 link 状态由同一个高有效异步复位
清空。

## 4. 事务标识和资源模型

V2 CHI TxnID 使用统一编码：

```text
{profile, direction, slot}
```

- `profile=1`：coherent；`profile=0`：noncoherent。
- `direction=0`：read；`direction=1`：write。
- `slot`：AR/AW entry index。
- AR/AW entry 数必须不超过 TxnID 中 slot 字段的容量。

写数据遵循 CHI 路由规则：

```text
TXDAT.TxnID = RXRSP.DBID
TXDAT.DBID  = original TXREQ.TxnID
```

完整 original TxnID 由 `rni_awctrl` 按所选 AW entry 生成，经 `rni.v` 传给
`rni_wr_buffer` 锁存，不能在数据缓冲中只用 entry index 重建。这样 coherent profile
位和 write direction 位在 TXDAT 阶段仍保持不变。

默认 AR/AW 表各 32 项。入口 FIFO、request FIFO 和数据 bank 深度是实现资源，不等同于
AXI ID 数；资源满时由 ready/backpressure 阻止继续分配。

## 5. 模块职责

| 模块 | 职责 | 关键边界 |
|---|---|---|
| `rni` | 顶层参数、AXI/CHI 端口、policy/hazard/link/读写路径集成 | 只允许当前已实现的默认功能宽度；不拥有具体 entry FSM |
| `rni_axi_bus` | AXI AR/AW/W 输入及 R/B 输出的内部总线打包/拆包 | 不解析 policy，不生成 CHI opcode |
| `rni_arlink` | AR 与 profile/epoch sideband 的 ingress FIFO | profile 在 AR 接受时快照，后续不能重查 live CSR |
| `rni_awlink` | AW 与 profile/epoch sideband 的 ingress FIFO | W 没有独立 profile，只继承 AW parent |
| `rni_segburst` | 根据 AxADDR/LEN/SIZE/BURST 生成 64B line、`ctmask/pdmask/bc_vec` | 当前仍带有固定 16B slot/默认数据面假设 |
| `rni_arctrl` | AR entry 分配、同 ID 依赖、TXREQ、Retry、RXDAT 完成跟踪 | 当前 RXDAT/DataID 校验和 entry 释放时点仍有边界 |
| `rni_awctrl` | AW entry、写请求、DBID route、DAT 调度、Comp/CompAck、B 调度 | 保存 DBID、completer 和完整 original TxnID |
| `rni_rd_buffer` | RXDAT 写入 bank，按 AXI beat 重组 RDATA/RRESP/RLAST | 当前功能实现以 CHI=256、AXI=128 为基线 |
| `rni_wr_buffer` | W FIFO、写 bank、WSTRB→BE、TXDAT 打包、B FIFO | TXDAT 未使能 byte 清零；当前 gather 固定为两片 256-bit |
| `rni_datbuf_bank` | 同步数据存储 bank | bank 组织是当前 64B/4×16B 数据面的基础 |
| `rni_bcount_ctl` | burst beat 地址/计数推进 | 服务于 legacy segburst 和 buffer 控制 |
| `rni_misc` | PCrdGrant FIFO、grant present/winner 辅助 | unmatched/非法 grant 尚无统一错误闭环 |
| `rni_link_ctl` | RX 分发、TXREQ 仲裁、TXDAT/TXRSP 发送、L-credit return | 全设计唯一 raw-link owner；credit return 不得伪装 producer sent |
| `rni_link_handshake` | CHI link activation/deactivation 状态 | outstanding link-down 的系统故障策略尚未完成 |
| `rni_lcrd_hdlr` | 每个 CHI 通道 credit 计数和可发送门控 | 已覆盖 credit=0、credit return 和 reset |
| `rni_policy_csr` | region shadow/active bank、secure write、commit、epoch、lock、resolver | resolver 当前只输出 allow/profile；完整 req_attr 尚未形成 |
| `rni_line_hazard` | line tag/profile/owner token，冲突时反压 | 当前只登记起始 line，owner 仍基于方向和 AXI ID |
| `rni_scheme1_static_assert` | width、BE、TxnID/entry 等 elaboration 契约 | 只证明参数合法，不证明对应数据路径功能正确 |
| `rni_axi_fragment_adapter` | 按 AxADDR/AxSIZE/beat ordinal 生成逐 byte fragment descriptor | 支持 FIXED/INCR；WRAP/reserved 显式报错；一次最多两个 64B line |
| `rni_fragment_dispatch` | 同周期提交 child descriptor 和 line context 配置 | 任一路反压均不允许半分配；fragment/cfg error 送控制层回收 |
| `rni_line_data_plane` | child/line 唯一归属、partial WSTRB scatter、RX byte merge、AXI R gather、snapshot | 与 profile/opcode/DBID 解耦；需要控制层分配 parent/child 并管理释放 |
| `rni_chi_dat_adapter` | 128/256/512-bit DAT 的 DataID 校验和 DATA/BE pack/unpack | 维护 expected/received/sent DAT mask；错误事件仍需接入顶层 AXI 错误闭环 |

## 6. 读数据流

### 6.1 AXI admission

1. AR 到达 `rni.v`。
2. policy resolver 根据地址、requester、nonsecure 和 intent 产生 allow/profile。
3. admission 同时受 commit quiesce、AR 内部 ready 和 line hazard 控制。
4. AR handshake 后，profile/epoch 随 AR 进入 `rni_arlink`。
5. `rni_segburst` 生成 line/slot mask，`rni_arctrl` 分配 entry。

### 6.2 CHI request

`rni_arctrl` 从 ready entry 生成 TXREQ：

| Profile | Opcode |
|---|---|
| coherent | `ReadOnce` |
| noncoherent | `ReadNoSnp` |

TXREQ 经 `rni_link_ctl` 与写请求仲裁，只有 link RUN 且 TXREQ credit 可用时发送。

coherent request 收到 `RetryAck` 后保存 PCrdType；匹配的 `PCrdGrant` 经
`rni_misc` 到达后以相同 TxnID/entry 重发，并将 `AllowRetry` 清零。当前实现有此骨架，
但非法 response 和 noncoherent RetryAck 尚未形成 AXI 错误闭环。

### 6.3 CHI data 到 AXI R

1. RXDAT 由 `rni_link_ctl` 接收并分发。
2. `rni_arctrl` 依据 TxnID 找到 AR entry，并跟踪 DataID 完成 mask。
3. `rni_rd_buffer` 按 DataID 将数据放入四个 16B bank。
4. line 数据完整后进入 response pending FIFO，再重组为 AXI R beat。
5. AXI R FIFO 吸收 RREADY backpressure。

当前风险：AR entry/TxnID 在数据移入 pending FIFO时即可释放，早于最终
`RVALID && RREADY && RLAST`。在较深 backpressure 或 slot 快速复用场景下，这不满足
方案要求的 parent 生命周期。

## 7. 写数据流

### 7.1 AW/W 收集

1. AW 经 policy/hazard admission，在 `rni_awlink` 锁存 profile/epoch。
2. `rni_segburst` 产生 line/slot mask，`rni_awctrl` 分配 AW entry。
3. W 进入 `rni_wr_buffer` 的 W FIFO。
4. 因 AXI4 W 无 WID，W 必须按已接受 AW 的顺序绑定；WSTRB 转换为 bank byte-enable。

### 7.2 CHI request、DBID 和 DAT

`rni_awctrl` 发出：

| Profile | Opcode |
|---|---|
| coherent | `WriteUniquePtl` |
| noncoherent | `WriteNoSnpPtl` |

收到 `DBIDResp` 或 `CompDBIDResp` 后，entry 保存：

- DBID
- completer SourceID
- original request TxnID
- CompAck 要求

数据就绪且 TXDAT credit 可用后，`rni_wr_buffer` 发送
`NonCopyBackWrData`/相应写 DAT。默认 CHI=256 时，一个 64B line 由低、高清晰的两个
DAT flit 发送，DataID 为 `00` 和 `10`。DATA 会按 BE 将未使能 byte 清零。

### 7.3 completion 和 AXI B

1. 最终 `Comp` 与 entry 匹配。
2. 若请求需要 CompAck，`rni_awctrl` 通过独立 TXRSP 路径向保存的 completer 发送。
3. DAT/CompAck 所需 handshake 完成后，写响应进入 B FIFO。
4. `BVALID && BREADY` 后释放 AXI 可见 parent/hazard。

当前写侧正常响应错误码仍以 OKAY 为主，CHI RespErr、非法/重复/乱序 DBID/DataID 尚未统一
映射为 AXI SLVERR。

## 8. Policy、commit 和 line hazard

`rni_policy_csr` 提供 region shadow bank 和 active bank：

1. secure manager 写 shadow entry。
2. commit 时校验 region、profile 能力及配置合法性。
3. commit pending 期间停止新的 admission，`commit_busy` 保持有效，并冻结 shadow 写。
4. 等待 outstanding 排空。
5. 原子切换 active bank，`policy_epoch++`。
6. lock 后拒绝后续配置修改，直到 reset。

当前已经实现/验证 secure write、非法写安全事件、region match、overlap error、commit
drain/busy、epoch、lock、requester/nonsecure/intent/profile 选择和静态能力过滤。

仍未完成的是 policy deny 的 AXI 终止响应：当前 deny 会反压 AR/AW，而方案要求接受整个
parent，并对读返回各 beat DECERR、对写排空全部 W beat 后返回一个 DECERR B。完整的
NS/Order/MemAttr/SnpAttr/AllowRetry/ExpCompAck immutable `txn_profile` 也尚未贯穿 entry。

`rni_line_hazard` 当前能阻止同一已登记 line 的跨 profile 并发并在最终 R/B handshake
释放 token，但只使用首地址，而且 owner 是 `{direction, AXI ID}`。跨多 line burst和同
AXI ID 多 parent 仍可能遗漏或提前释放 hazard。

## 9. CHI link 和流控

`rni_link_ctl` 是唯一 CHI 链路所有者：

- 管理 link RUN/deactivate。
- 接收并路由 RXRSP/RXDAT。
- 仲裁 AR/AW TXREQ。
- 对 TXREQ/TXDAT/TXRSP 分别使用独立 L-credit。
- 在需要时发送 RX channel L-credit return。
- 只有真实 producer flit 被通道接受时才产生对应 `sent`，credit-return 不会伪造 DAT 或
  CompAck 完成。

这保证 profile 选择只影响已锁存事务语义，不复制 NodeID、raw flit 或 credit ownership。

尚未完成的协议错误闭环包括：response opcode/state/SrcID/DBID 白名单、重复或非法 DataID、
unmatched PCrdGrant、credit/link 中断时的 outstanding 处置，以及错误到 AXI SLVERR 的一致
映射。

## 10. 已验证功能

以下结果来自当前工作区 `rtl/uvs_dir/param_rni*/uvs_param_rni*_run.log`，日志均显示
`0 error(s)`：

| Make target | 测试顶层 | 已验证内容 |
|---|---|---|
| `run_param_rni` | `tb_param_rni` | coherent ReadOnce/WriteUniquePtl、默认宽度读写、partial WSTRB、DBID/DAT/Comp、V2 TxnID、TXDAT DBID/original TxnID |
| `run_param_rni_noncoherent` | `tb_param_rni_noncoherent` | ReadNoSnp/WriteNoSnpPtl、默认宽度读写、DBID/DAT/Comp、V2 TxnID、TXDAT DBID/original TxnID |
| `run_param_rni_width_matrix` | `tb_param_rni_width_matrix` | AXI 8..1024 与 CHI 128/256/512 的 24 种静态 Gate-0 参数组合 |
| `run_param_rni_contracts` | `tb_param_rni_contracts` | 24 种宽度及 Scheme-1 边界契约 |
| `run_param_rni_resource` | `tb_param_rni_resource` | hazard、容量、释放、reset 的模块级行为 |
| `run_param_rni_lcrd` | `tb_param_rni_lcrd` | credit=0、credit return、reset |
| `run_param_rni_policy` | `tb_param_rni_policy` | security、region、commit、profile capability、epoch、lock |
| `run_param_rni_fragment` | `tb_param_rni_fragment` | AXI1024 对齐/非对齐双 line fragment、反压稳定、WRAP 拒绝 |
| `run_param_rni_axi_widths` | `tb_param_rni_axi_widths` | AXI 8/16/32/64/128/256/512/1024 的功能 fragment byte exact-cover |
| `run_param_rni_line_data_plane` | `tb_param_rni_line_data_plane` | AXI512 partial WSTRB 跨 line scatter、snapshot、乱序 line 返回后的单 beat R gather、R backpressure |
| `run_param_rni_chi_dat` | `tb_param_rni_chi_dat` | CHI 128/256/512 的 4/2/1 DAT、逆序 RX scatter、DataID/BE、TX gather |
| `run_param_rni_fragment_dispatch` | `tb_param_rni_fragment_dispatch` | child/line 双边原子 handshake、反压和 fragment/line error 路由 |

运行单项：

```sh
cd /home/xylan/workspace/willow/chi-adaptor/OpenNoC/rtl
make run_param_rni
make run_param_rni_noncoherent
make run_param_rni_policy
```

运行全部 param_rni 用例：

```sh
make run_param_rni_all
```

`run_param_rni_all` 是串行聚合目标。生成物位于
`rtl/uvs_dir/<test-name>/`，不应提交到源代码版本管理。

## 11. 实现和验证边界

| 范围 | 当前状态 | 说明 |
|---|---|---|
| AXI=128、CHI=256 基本数据通路 | 已实现并功能验证 | coherent/noncoherent smoke |
| V2 profile/direction/slot TxnID | 已实现并功能验证 | 包括 TXDAT original TxnID |
| partial WSTRB | 基本验证 | 默认宽度单拍场景；未覆盖所有跨 beat/line 组合 |
| RetryAck/PCrdGrant | 部分实现 | 有重试骨架；缺 profile 限制、非法 grant 和错误闭环 |
| DBID/Comp/CompAck | 部分实现并 smoke 验证 | 缺重复/乱序/state/SrcID/DBID 全面校验 |
| policy CSR | 模块级实现并验证 | deny→DECERR 和完整 req_attr 传播未完成 |
| line hazard | 模块级实现并验证 | 仅首 line；owner 唯一性和跨 line burst 未完成 |
| 资源满/回收 | 模块级验证 | 真实多事务 AR/AW 表压满、混合 profile 并发仍需集成测试 |
| AXI backpressure | FIFO 支持 | 长时间 RREADY/BREADY/WREADY 压力和 slot 复用需增强 |
| 参数化数据面模块 | 已实现并模块级验证 | fragment、line scatter/gather、CHI 128/256/512 DataID/BE；尚未接管 legacy 顶层 |
| 非默认宽度完整 RNI | 未开放 | parent/child admission、REQ/DBID/Comp 生命周期和 link 路径尚未接到新数据面 |
| CHI protocol error→AXI error | 未完成 | 需要统一 RX validator、entry error 状态和 drain |
| reset/link-down outstanding | 未完成 | 尚无 coordinated reset/platform fault 语义 |
| poison/datacheck/RSVDC | 未覆盖 | 参数存在不等于端到端功能已验证 |
| RX SNP/DVM/atomic/exclusive | 不在当前接口范围 | 需要新增接口、状态机和验证环境 |

## 12. 非默认宽度开放条件

解除顶层默认宽度 guard 前，至少要成组完成并验证：

1. AXI beat/fragment 描述符，以及最多跨两个 64B line 的拆分。
2. 固定 4×128-bit canonical write bank。
3. 窄/宽 AXI W scatter 和 AXI R gather。
4. CHI DAT=128/256/512 的可变 flit 调度。
5. 对应 DataID 合法性、重复检测和 completion mask。
6. RXDAT/TXDAT 的 BE 映射、partial WSTRB 和未使能 byte 清零。
7. parent/child、TxnID、DBID 与最终 AXI handshake 的完整生命周期。
8. 对每个功能宽度组合运行读写、backpressure、跨 line 和错误注入测试。

在这些条件满足前，`width_matrix`/contracts PASS 只能解释为“参数合同可 elaboration”，不能
解释为“完整 RNI 数据路径可用”。

## 13. 后续实现优先级

建议按以下顺序继续收敛 Scheme-1：

1. 修正 AR entry/TxnID，延迟到最终 AXI RLAST handshake 后释放。
2. 实现 policy deny parent 的 R/B DECERR 本地完成路径，并正确 drain W。
3. 建立统一 RXRSP/RXDAT validator 和 protocol-error→AXI SLVERR 闭环。
4. 完成 RetryAck/PCrdGrant 的 coherent-only 规则与 unmatched grant 处理。
5. 将 NS、Order、MemAttr、SnpAttr、AllowRetry、ExpCompAck、QoS、epoch 组成 immutable
   transaction profile 并贯穿 entry/retry/data/trace。
6. 将 line hazard 扩展到 burst 覆盖的每条 line，并使用唯一 parent/entry owner。
7. 将已完成的参数化 fragment/scatter/gather 模块接入 parent/child 控制和 raw-link 路径，
   完成 G1--G6 后再开放非默认宽度。

## 14. 修改约束

修改本目录时应保持以下不变量：

- `rni_link_ctl` 始终是唯一 raw-link 和 credit owner。
- profile 在 AR/AW handshake 时锁存；在途事务不得重读 live CSR。
- W 只能继承 AW profile。
- TXDAT data-route 保留到最后 DAT handshake；需要 CompAck 时继续保留到 CompAck handshake。
- TxnID/entry/hazard 不得早于最终 AXI 可见完成释放。
- 所有未支持参数组合应在 elaboration 时明确失败，不能静默产生错误数据。
- 新功能必须同时增加自检用例和 Makefile 目标或纳入现有回归。
