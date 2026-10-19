# 2026-10-08 自动执行记录

> Historical record retained during the 2026-10-10 documentation cleanup. Dates, measurements and unresolved findings below apply to the recorded inputs. Old execution commands are not current instructions; follow [the current verification policy](../../../ios/VERIFICATION.md).

主计划：[FULL_CODEBASE_REFACTOR_PLAN.md](full-codebase-refactor-plan.md)。用户已授权按顺序自动执行，并要求避开 CLI 的并行任务。以下是本轮实际结果，不替代历史验收。

## 输入与并行任务边界

- 起始 HEAD：`14d294653fa11e87b6fbfbe3b4eba43f40b65225`；工作区已有大量业务、铁路数据与品牌资源修改，不以 HEAD 冒充工作树。
- 冻结 `ios/`、`app/`、`port-fixtures/` 共 11,857 文件、1,229,503,592 字节；排除构建缓存。复制前、复制后、快照 SHA-256 一致。数据 revision `2026-10-07.1`；时刻表 DB SHA-256 `d9e72d9aadb3a34fe8112f587be19eb507d1c146cacc53e33fab404e57eaabf7`。
- 快照与收据目录：`/tmp/jtm-refactor-start-20261008/`。`full-snapshot-sha256.json` 记录输入，`candidate-overlay-sha256.json` 记录候选覆盖。临时目录不保证长期留存。
- CLI 的 `JTM NewTrip 1` UI 测试、数据集成与 logo 工作不属于本任务；未停止这些进程，未借用模拟器或 DerivedData，未更新 sample 数据、品牌素材与 golden。

## 批次与已验证结果

| 批次 | 实际改动 | 验证 / 状态 |
| --- | --- | --- |
| PR-00A | 将已存在的 StatisticsArea 登记到 statistics-passport；新增纯 Application 路线验证责任登记 | 边界与 7 项 checker 回归通过，277 生产源码；永久字体范围通过 |
| PR-00B | 冻结完整输入；隔离包构建、native、app 验证 | 原始快照 generic Simulator app build 通过；完整 SwiftPM 基线因内存优先级主动中止，保留部分失败，不宣称全绿 |
| PR-00C-1 | 保留明确 pending 记录；旧迁移入口作为不改数据的兼容 adapter | 原源码复现 pending 被清除；修复后保留 archive、hints 且不进入求解。Core 路线相关 28 tests / 3 suites 通过 |
| PR-00C-2 | TripRouteValidation 验证所有地区的候选；NewTrip 按输入身份接纳物理证明，未证明则保存 pending 并隐藏精确公里；日期关闭过滤仍保留 | Application 35 tests / 5 suites 通过，包括取消、忽略取消的 resolver、普通错误、日期回退与 pending 输入；Simulator 集成编译及完整 app gate 通过 |
| 验证入口修复 | 缓存 harness 对齐实际解码签名及 inbox/publisher；确定性控制迟到结果 | 四组原缓存行为断言通过，未改生产缓存算法 |
| 验证入口修复 | 断口 harness 对齐 SectionGap 的区间端点与 isBoundary；额外检查 segmentIndex/isBoundary | 原始快照独立复现旧断言失败；两组断口、缓存持久化与已乘区间里程检查通过 |
| 构建入口修复 | verify.sh 支持 APP_DESTINATION，保留原默认模拟器 | 本机没有默认 iPhone 17 Pro，generic Simulator 完整 app gate 通过，包括 558 个资源路径 |
| 并发编译告警 | 显式标注地图准备 local helper 为 MainActor；不可变运营商集合标记 nonisolated | 候选 Simulator app gate 验证 RailMap 源码零告警；Core 冷构建仍有既有不可达分支告警 |

针对本轮变动的 package 检查共 63 项通过。Grok 4.7 xhigh 只读复核了 pending 迁移和 NewTrip 确认链路；Codex 负责实现、整合及验证。独立集成复核未发现新增的 stale proof 或取消发布缺陷。

## 尚未收口

完整包基线采用未应用本轮修复的冻结快照，现已主动中止。中止前已观察到 StoreOperationsParityTests、DatedEndpointNameShadowTests、ReviewedUtazuRoutingTests、TrainValidationParityTests、OSMTrackConnectorTests 及个别物理端点/服务路径失败；该全量运行已因用户内存约束主动中止，数量只代表中止前的部分结果。不得因当前失败刷新 golden 或加入邻近、同名桥接。

native 与 app 全门禁已通过下方记录的集成版本；Catalyst 双架构构建通过，独立模拟器的 4 项 NewTrip UI 为 3 PASS / 1 FAIL。地图碰撞网格已原样提取并通过 5 组检查（含 600 次确定性 oracle 对照）。最新内存批次的专门验证见后文；整 App Release 性能和功能/数据全基线仍未收口，不将整体现代化标为完成。后续按主计划前置条件推进，每批记录源码范围、验证与剩余失败。

取消与渐进发布 harness 的解码签名、图输入 adapters 及抽取终点已对齐当前接口，分别 5 组检查通过；未修改生产解码/求解。auth、HTTP、请求及站点搜索尾部检查也已通过。Grok 的额外全基线分类尝试达到 turn 上限，未采用未完成结论；上述分类由 Codex 从日志与当前源码核验。

## 已分类的冻结基线失败（主动中止前的部分计数）

| 契约 | 已完成失败套件 / issues | 下一步与文件边界 |
| --- | --- | --- |
| 记录序列化 parity | StoreOperationsParityTests 11；TrainValidationParityTests 1 | 先逐字段对照 canonical payload。已确认的复制样例差异是 stops 的 `platform_number: null` 与省略键；另有 `20260719_04_sakura770` 导出差异尚未判定。检查 Models/TrainValidation 与 JS 导出契约，禁止直接刷新 golden |
| 历史站名身份 | DatedEndpointNameShadowTests 2 | 核对阪急旧名的 reviewed code membership 与 dated alias 证据，不加同名 fallback |
| 宇多津分岔证明 | ReviewedUtazuRoutingTests 24 | 断言发现本四備讃線 expected 与土讃線 actual 及 surveyed path key 不匹配；按铁路数据 owner 核对，不将名称改写冒充物理证明 |
| 物理连接登记 | OSMTrackConnectorTests 1；JunctionApproachTests 1 | 拒绝 ID：naoetsu-shinetsu-hokuriku、goryokaku-hakodate-esashi、goryokaku-esashi-hakodate-kamiiso、aomori-tohoku-tsugaru、tsubata-hokuriku-nanao。核对 surveyed section 身份与 registry 端点；不使用邻近桥接 |
| 站点在线证明 | OnEdgeCertificationTests 1 | 岐阜羽島/吉富/石川样例的 hints 断言失败；定位具体区间与源 geometry，再判断数据或算法 |
| 服务路径全覆盖 | TrainServicePatternRouteTests 未完成 | 按 pattern/direction/leg 收据处理，日期、reference、via、物理连通分别验收；不能把所有失败统一归因于 fixture drift |

Catalyst 在标签网格提取前的候选版本完成 arm64、x86_64 构建（签名关闭）。UI 初次运行未完成任何用例：专用模拟器上的 runner PID 37195 于 23:27 崩溃，主线程在 UIKit accessibility bundle 初始化，故障线程为 `XCTWaiter(StallHandling)` SIGABRT。保存 `ui-runner-stall.ips` 与截图后，只停止本任务挂起的 test coordinator/diagnostic collector；CLI 设备未受影响。专用模拟器已重新启动，后续重试须记录独立结果，不把这次设施故障当作产品测试通过。

## 整合门禁收据

- `candidate-native-final.exit = 0`：包含标签网格、全部 native 生命周期/取消/进度/请求/搜索检查及源码契约。
- `candidate-app-final.exit = 0`：标签网格提取后的 arm64、x86_64 Simulator 构建与全部 app contracts 通过，RailMap 源码无告警。
- 冷构建的 `StationIntervalResolver.swift:259` 不可达分支告警仍需单独处理；native gate 的增量 warning 检查通过不代表冷构建零告警。下一验证入口批次须保留初次 build log，再检查初次与增量日志，不能靠缓存把该项抹去。
- 完整原始基线的 1 秒 host 采样定位到 `RailHistoryPackageTests.everyGeneratedRouteBoundaryMatchesWebSolve → auditBrowserPath → regionalGraph → addStationTransferConnectorEdges`；当时 physical footprint 17.8 GB。它说明批量测试资源开销，不能作为实设 Release 帧率或启动性能证据。
- 初次 UI 的挂起 coordinator exit 143（主动终止本任务的已崩溃 runner 调用）；重启后以单独 result bundle、90 秒默认/120 秒单项上限重试 4 项用例，3 PASS / 1 FAIL，详情见内存批次。


## 内存优先批次（用户最新要求）

用户明确要求严格降低 memory footprint。本任务的完整 SwiftPM 历史验证曾达到 17.8 GB physical footprint，已只终止本任务自己的全量 Swift/JS 进程，保留部分日志；未停止外部 CLI 的设备或指令。完整 Swift 与 JS parity 均未完成，不记 PASS。停止收据为 `/tmp/jtm-refactor-start-20261008/memory-priority-stop.json`。

生产改动：

- `RouteSolveLimiter.shared` 从 2 降到 1；RiddenRouteStore 每台设备均使用单个顺序 journey worker，避免多张私有可变图同时驻留。取消仍须等旧任务真正退出才释放 permit。
- App 的 fallbackGraphStore 使用 `.bounded(maximumNodes: 100_000)`。全图、区域、走廊合计最多缓存一张；构建替代图前先释放旧缓存所有权。超限图完整返回给当前调用者但不缓存；不改变线路、节点、边或物理证明规则。历史 parity/export 默认策略保持既有缓存语义。
- `GraphCachePolicyTests` 检查跨类别替换、在 augmentation 前 ARC 释放、超限不缓存、活动调用者图不被截断、重建后节点及有序 adjacency 一致。缓存/取消/严格拓扑共 26 项测试通过。
- 新增 `tools/measure-route-graph-memory.py`，顺序编译和运行相同的小规模宿主机查询，不加载日本全量数据。

固定负载：36 组互不相交的走廊，各 1,500 个顶点；54,000 节点、107,928 有向边，输出节点摘要均为 `7445723771498410693`。同一机器、相同 Debug 库配置和源输入，对照 frozen baseline 与本轮 candidate：

| Host physical footprint | 原缓存 | bounded 缓存 |
| --- | --- | --- |
| 查询结束驻留 | 123,503,144 bytes（117.78 MiB） | 27,935,200 bytes（26.64 MiB） |
| 每次建图后采样最大值 | 123,503,144 bytes | 27,935,200 bytes |

本次对照结束驻留下降 **77.38%**；另一次同输入运行下降约 78%。采样最大值不是系统完整高水位。该结果仅证明本工作负载的缓存驻留下降；100,000 节点不是硬性字节预算，当前活动的大图、编译后的源数据、地图显示数据仍占内存，iPhone Release 的整 App 峰值与路线延迟尚待测量。记录 `/tmp/jtm-refactor-start-20261008/graph-memory-comparison.json`，工具可用两个冻结 SwiftPM `out/Products/Debug` 目录重跑。

UI 重试已退出：NewTrip 空白/保存条件、无车次保存、交换站点 3 项通过；跨线服务用例在出现 `newTripCorridor-0` 前失败（NewTripUITests.swift:87），未进入保存断言。保留失败与 result bundle，不把 runner 重启后的“0 tests”误计通过。已从既有录像确认第 59 秒仍显示 Route spinner、Save 禁用，没有日期/断路错误；失败是 20 秒 corridor 等待窗口内尚未完成规划/校验。不得通过提高求解并发或绕过物理证明修复该用例。

下一步按内存优先顺序：先确认本批 App 编译及跨线 UI 失败原因，再在固定 iPhone/OS/Release 的冷暖缓存下测启动、长路线与大数据导入的峰值和延迟；后续热点、解码并发及显示缓存预算按测量推进。目录提取与全量重跑顺延，既有历史/序列化失败继续分流到对应 owner。

内存批次的 arm64 Simulator `build-for-testing` 已通过；缓存回归清理 weak-reference 告警后再跑 3 项通过，无新增测试源码告警。生产取消 harness 的 5 组检查也通过。既有 StationIntervalResolver 冷构建告警仍保留。内存配置下仅重跑跨线 UI 用例，使用独立结果包，不重启全量基线。

该固定 Host 缓存负载的后续回归门槛设为结束驻留至少下降 50%，由测量工具强制检查；这是此负载的预算，并非整 App 的字节上限。最新 candidate overlay 已包含 22 个文件及 SHA-256，原始输入快照保持不变。

最终内存门槛复跑：`graph-memory-gate.json` 记录原缓存 122,421,776 bytes、新缓存 27,443,656 bytes，结束驻留下降 **77.58%**，通过至少 50% 的固定负载门槛；节点、边数及摘要一致。该次与前次约 77–78% 的结果一致。

内存配置的跨线 UI 单项重跑退出 65，仍在原有 corridor 的 20 秒窗口内失败；不将其记为新配置下通过，也不假定完整规划已结束。结果包 `memory-throughservice.xcresult`、日志 `memory-throughservice.log` 均保留。这是下一批必须定位的冷启动规划/校验时延问题；现有证据不足以区分 planner 与 resolver 各自耗时。其余 3 项 UI PASS 来自内存改动前的集成候选。边界与 7 项 checker 回归再次通过；此次新增源码差异检查通过。


## 2026-10-09：显示网络缓存责任与驻留重构

继续按用户要求优先减小 footprint。本轮先核对 CLI：NewTripView/RiddenRouteStore 已有并行校验优化，RouteGraph 也有后续修改，未覆盖这些文件；隔离候选保留上一轮输入，仅叠加本批 DisplayNetworkCache 与验证工具。CLI 的新校验实现和 UI 结果不能由上一轮记录推断，需要其本轮收据整合。

文件白名单：`RailMap/DisplayNetworkCache.swift`、`tools/verify-display-network-cache.py`、`verify.sh`、主计划及本执行记录。生产缓存职责保持在原 actor 中，没有新增并行状态 owner。

- 国家网络和合并 scope 网络共用一个已完成缓存槽。旧网络在下一次构建获准后释放缓存所有权；持有网络的活动调用者不受影响。
- 未使用的布局 seed 只保留一份，读取时消费。丢弃 seed 仅影响是否重用布局，不删线路或改变几何。
- 专用 `RouteSolveLimiter(limit: 1)` 串行化显示网络构建，独立于路线求解 limiter，避免正在持有路线许可的调用者再次申请同一许可。
- 同地区 inFlight 请求仍共享唯一 detached task，单个等待者取消不取消共享工作。构建在释放许可前发布缓存，等待者只消费结果，防止旧等待者晚到时重新插入旧国家。
- 合并 scope 保持 catalog 地区顺序和原 line identities；失去缓存后按需重建，不建立物理连接。

`verify-display-network-cache.py` 抽取实际 actor 代码，仅替换重型 package 构建和负载。五组确定性检查通过：同地区 coalescing/取消与跨地区构建串行、替换分配前 ARC 释放、seed 上限及消费、scope 顺序/共享缓存槽/活动调用者完整性、错误后 permit/inFlight 清理及重试。入口已接入 native gate。

额外小规模 host 对照使用真实 RailCore.RouteNetwork（不使用生命周期测试的 class payload double），顺序请求六个独立网络，每个 15,000 坐标，累计输出均为 90,000 坐标。对照同一 Core 库和构建参数、相同实际 actor 前后版本，只将文件读取替换为固定 synthetic builder：

| 查询结束 | 本批前 | 本批后 |
| --- | --- | --- |
| 缓存驻留网络数 | 6 | 1 |
| Host physical footprint | 4,374,984 bytes | 2,949,600 bytes |

本次结束 footprint 下降 **32.58%**。这是显示缓存小负载的单次 host 测量，不是整 App 内存，也不能与前批图缓存下降百分比相加。实际 App 的其他 owner（例如 EdgeIndexCache）仍可能持有网络；缓存槽数量和串行构建也不是硬性字节上限。切换地区时可能增加重新布局耗时，需后续固定设备冷暖测量。

所有本批日志和 before/after benchmark 源码保存在 `/tmp/jtm-display-cache-refactor-20261009/`。主工作树边界 gate 当前发现 CLI 新增 ShareCardRendering/ShareComposerModel/ShareComposerView 尚未登记归属，未顺手改动并行功能；冻结候选的边界与 7 项 checker 回归通过。App 编译收据与只读复核结论在下方补记。

本批 arm64 generic Simulator App 隔离编译退出 0（`app-build.log`）；RailMap 源码无新增告警，既有 StationIntervalResolver 不可达分支与 AppIntents metadata skip 仍保留。冻结候选边界回归通过，主工作树并行 ShareComposer 的归属登记失败单独记录。当前 candidate overlay 24 文件 SHA-256 与补丁已更新；本批没有替换 CLI 正在编辑的 NewTrip/RiddenRouteStore/RouteGraph。

Grok 4.7 xhigh 的本批只读调用者复核在超过 9 分钟后仍未返回 findings；只停止匹配本批 prompt-file 的进程（收据 `review-stop.json`），未采用不完整结论，也未停止外部 CLI。Codex 已直接核对 EdgeIndexCache 与 RailNetworkStore 调用契约，负责最终整合与上述本地验证。后续实设测量和 CLI 校验链路收据仍须整合，不能将本批记为全代码库验收完成。


## 2026-10-09 resumed integration (durable receipts)

The user authorized automatic completion of the refactor with strictly lower memory footprint. Previous /tmp receipts and frozen builds were absent after the interruption; their historical observations above remain historical and cannot be re-inspected from those paths. New logs are in `outputs/refactor-20261009-resume/` (local ignored reports). No external CLI process, build directory, or simulator was stopped or reset.

- Integrated the batch `RailApplication.TripRouteValidation` use case with the CLI's historical-date-only route probes. All candidates share the ordered batch; unavailable proof keeps candidates. Date filtering retains the CLI's fast current/future bypass and no route-cache writes.
- Repaired the missing proof publication in NewTrip: publish physically resolved IDs only after cancellation/input identity checks; clear on replanning/region changes. Drafts are confirmed only for the current proved candidate, otherwise pending. Exact candidate kilometres require the same proof. The validation bypass does not manufacture proof.
- Extracted selected-station snapshot ownership into `MapSelectedStationSnapshotController`; controlled noncooperative-load tests pass for cache/coalescing, replacement, cleared selection, mount identity, teardown and exactly-once callback.
- Sharing retains only the current renderKey's cache/images and releases old content on replacement/dismissal. Renderer generation and view export tickets reject late results and stale busy cleanup. The actual controller/view control-flow harness passes 16 checks. Unused ShareRequestController and its old harness are retired; the replacement harness is wired to verify.sh and source ownership.
- Source ownership and permanent typography pass: 280 production Swift sources, seven checker regressions. Label collision (including 600-operation oracle), map-worker lifecycle, route cancellation and five display-network-cache groups pass. Timetable/resource snapshot alignment and 3,937 station references across 337 patterns pass.
- Preserve the first package build log for warning inspection; default package jobs and test parallelism are bounded. App verification now passes one Xcode build job and one Swift driver compilation batch rather than relying on Xcode's generated -j value alone. This limits compiler scheduling; it is not a measured hard byte cap.
- Fresh app snapshot: 11,880 files, zero live hash differences after copying. Package inputs match the focused-test snapshot. Manifest: `app-input-sha256.json`; package manifest: `package-input.json`. Builds run on disposable unsynced copies to avoid resource-fork code-sign failures; source and logs remain durable.

Current Core policy comparison (same current library for both policies, not an old-source rebuild): 36 disjoint corridors / 54,000 nodes / 107,928 directed edges, digest 7445723771498410693. Default cache ends at 123,404,888 bytes; bounded cache ends at 26,411,536 bytes: 78.60% lower, passing the unchanged >=50% fixed-workload gate. These are host physical-footprint samples, not full App/Release peaks. Tool now gives swiftc its own temporary module cache rather than requiring writes to the user's cache. Receipts: `graph-cache-policy-memory.json`, `.stderr`, `.exit` (0).

Focused package tests and current app/UI integration are still in progress. Initial package build/signing attempts failed due synchronized filesystem metadata; preliminary native checks run before Application libraries were available or under macro sandbox restrictions are not acceptance results. Those will be rerun after a successful build with the required host permissions. Existing full-suite/data failures and M NO-GO remain open; no golden or physical topology evidence was weakened.


Resumed focused package acceptance: 22 Core tests in three suites and nine Application tests in one suite pass (`package-tests-final.log`, exit 0). Two initial StationIntervalResolver fixture-file failures were fixed by mounting the already-hashed frozen app/port-fixtures tree; production and test assertions were unchanged. The compiled package reports no StationIntervalResolver production warning; two existing PhysicalEndpointTrimTests unused-expression warnings are recorded in the cold log rather than hidden by an incremental build.

All 14 native lifecycle groups have now passed on the frozen source/package inputs: the initial successful groups are in `native-contracts.json`, and five early build-artifact/macro-sandbox failures were rerun after complete libraries and required host permissions with all five passing (`native-contracts-retry.json`). The additional sharing, selected-station, display-cache, label and map-worker/cancellation groups above remain separate checks; their counts are not inflated into full-suite acceptance.


### 2026-10-09 current continuation: sharing and historical endpoint preflight

The CLI subsequently split bounded preview rendering from full-resolution export. The current integration preserves that implementation, its ticket renderer, statistics publication identity, and cancellation handler. Each render/export now owns a reference staging buffer. Cancel or render replacement empties all partial buffers immediately; operation UUIDs isolate same-generation exports. Export requires the exact completed render key. The actual production-controller/view harness passes 34 checks with no compiler warnings (`sharing-current.log`), including immediate weak-image release during noncooperative map waits and independent full-resolution exports.

Endpoint preflight now resolves/filters the same endpoint candidates before allocating corridor or full graphs; viable endpoints retain the original fallback and physical topology rules. Current focused Core/Application acceptance is 44 + 9 tests (`endpoint-preflight-tests.log`). The three Yuubari historical tests pass in 38.430 seconds (`history-preflight.log`, exit 0): both retired and undated rejection complete in 0.001 seconds. The memory sampler encountered a null process record as the test exited; its partial samples are not a complete peak receipt. The sampler now tolerates those empty records. The earlier preflight-free retired query exceeded the owned-process 2 GiB operational budget; that budget is a test execution guard, not an App memory target.

Temporary execution state disappeared again during continuation: isolated build directories, the previous dedicated simulator and active test sessions were absent. An unfinished non-history package run therefore has no acceptance exit status. Existing logs remain durable. Current source/resource inputs are copied to `outputs/refactor-20261009-resume/app-input-durable/` with a SHA-256 manifest and no source differences during copying. Successful test products will also be retained there; disposable builds still run outside the synced workspace to avoid code-sign metadata failures. No external CLI work or user simulator was reset. Current source boundaries and seven checker regressions pass (`boundaries-current.log`). A fresh isolated app build and dedicated simulator are in progress.


Current cold app acceptance: `app-build-source-modes.log` exits 0 with TEST BUILD SUCCEEDED; RailMap production-source warnings are absent. `StatisticsShareImage` now copies the CGSize before the cancellation-handler suspension, so the captured snapshotter/options region is not accessed afterwards. Snapshot file modes are restored from source (copyfile had omitted executable bits), and successful Products are retained at `outputs/refactor-20261009-resume/app-built-products/`. Source manifests plus the focused size-isolation overlay identify the input. App resource/behavior contracts extracted unchanged from verify.sh pass against this actual bundle (`app-bundle-contracts-current.log`, exit 0).

Grok 4.7 xhigh completed the authorized read-only RenderBuffer review with no missed stale-pixel retention or buffer collision reported (`grok-memory-review.log`, exit 0). Codex checked the cited generation guards, per-operation cleanup and completed-key guard against the local source; the 34-check local harness remains the validation evidence. No external messages were sent.

Targeted device workflows are running on the new dedicated simulator. Initial sharing failed before opening the composer: the test tapped Japan, which is now a submenu, and immediately expected a selected country. The test now explicitly selects Japan (all), retaining the same Japan/date/export assertions. This is an adaptation to the CLI area-menu behavior, not an accepted sharing result. The map camera selection, multiple corridor selection and no-number save tests have passed in this run; final counts and the corrected sharing rerun remain pending. A single map-workflow Debug footprint sample records peak 1,230,573,240 bytes and current 490,311,304 bytes for owned App PID 9155; this is diagnostic only, with no matched baseline or Release gate.


### Bounded statistics-index ownership

`EdgeIndexCache` now retains one completed country, merged, or area-scoped result instead of all country indexes plus three derived slots. A private single permit covers country construction through its display-network await and pure merges/clipping. Composite operations obtain dependencies before requesting this permit, avoiding nested admission. Active callers keep their immutable results. Country tasks publish under admission; their waiters only consume the result and cannot reinsert an evicted country.

The N02 denominator count travels with each country result; eviction cannot substitute the appended display-edge count in area coverage. Japan clipping occurs in a helper whose full-country local lifetime ends before another region is loaded. Old cache ownership is dropped before replacement allocation. Country ordering, duplicate country slots, date-independent identity, vector fallback and all static metric/geometry algorithms are preserved; the static `merge`/build tail matches the saved prior source byte for byte (`edge-index-before.swift`). Returning to an evicted scope can cost recomputation; a slot bound is not a hard byte cap.

The actual actor/permit extraction harness passes seven groups with zero warnings (`edge-index-cache.log`, exit 0), including a suspended display builder, independent cancelled joiner, eviction ARC before allocation, duplicate/order/warm merge behavior, clipping denominator after eviction, full Japan owner release before another country wait, retry cleanup, empty/single scopes. Only heavyweight payloads and geometry builders are doubled. The entry is wired into the native gate. Current App compilation with this change is pending; there is no whole-App before/after memory claim.

The six-case UI run has finished: four NewTrip tests and one map camera test pass; the sharing test fails at the old country menu step. `ui-current.log` and durable `ui-current.xcresult` contain the actual run, exit 65. Corrected sharing is not yet accepted. No timeouts or production topology guards were relaxed.


### Current continuation acceptance receipts

- Mounted ticket rendering fixes a reproduced UIKit/SwiftUI crash. `recordTicketFace` previously ran outside the installed view environment and trapped at `StatisticsDashboardContent.passportDataPage`'s localization getter. The face is now selected inside the dashboard View body; its private helper cannot be called externally before mounting. Exact ticket dimensions, preview/full-export split, and CLI rendering styles remain. App compilation passes (`app-build-ticket-environment.log`, exit 0); sharing lifecycle still passes 34 checks (`sharing-ticket-environment.log`).
- Corrected sharing passes the Japan/date/render/export device path in 48.329 seconds (`ui-ticket-fixed.log`, exit 0, durable result bundle). Together with the earlier four NewTrip and one map-camera successes, all six targeted flows have current passing receipts; these are separate runs, not a full UI suite or a six-case run with one global exit 0.
- Current package focus: nine Core tests across cache policy, endpoint preflight and three historical Yuubari cases, plus nine Application tests pass (`package-memory-focus-current.log`, exit 0). Complete owned-process sampling peaks at 218,202,832 bytes with no budget stop (`memory-focus-current-summary.json`, watcher exit 0). The retired/undated queries remain 0.001 seconds. Two pre-existing test unused-expression warnings remain in the cold log.
- The broader non-history package run hits 2,152,876,456 bytes in `RailValidityTests.testCodedDonanEndpointsResolvePreTransferStationVariants`, which constructs real historical Japan graphs; it is not accepted (`package-nonhistory-current.exit`: -15). SwiftPM continued launching another test binary after its over-budget child died, so the verified owned runner and descendants were also terminated (`nonhistory-budget-stop-runner.json`). The guard now stops the runner before its children and stays active until completion; no external CLI process was terminated. This is an operational test budget, not a product memory guarantee.
- Ten current native contract groups all pass (`current-native-contracts.json`), including persistence ordering, editor validation, physical continuity, partial passport accounting, endpoints, subscriptions, completion, sharing, statistics cache and selected-station ownership. Final app bundle contracts and source/typography boundaries also pass.

Statistics-cache host comparison uses actual pre-change/current actor country lifecycle, actual current RailCore.Statistics.EdgeIndex, the same current library/toolchain, and fixed synthetic N02 builders for five sequential supported country keys. No vector package or UI is included. Both runs return 125,000 edges and identical total 113.9850069627507 km. End footprint changes from 38,846,992 to 12,681,720 bytes (67.35% lower). Receipt `edge-index-memory.json` is the latest run after replacing the synthetic unsupported cn key with supported kr; the earlier 67.48% run was preliminary. This is a single host retention comparison, not a whole-App/Release peak, not additive with graph/display cache percentages, and no new percentage gate was chosen after seeing results.

The final cache-tail comparison accounts for the adapted ready(country:) ownership lookup; all static build/merge/metric algorithms are unchanged. Its ready lookup is covered by the actor harness. Current manifests: `final-continuation-overlay-sha256.json` plus the initial durable source/resource manifest. Required product-wide Release memory comparison, complete large-fixture suite acceptance, resource clean/incremental identity repetition, rollback read/write acceptance and M/full-viewport dimming remain open. S6 and the entire roadmap are not marked complete.

### 2026-10-09 resource determinism and Release protocol continuation

The final clean/incremental repetition passes: all 1,086 packaged files are byte-identical (`resource-clean-incremental-final.json`). `ios/copy-rail-packages.sh` removes execution timestamps and timings from the two bundled display-network descriptors and records those values in build diagnostics. Input/package hashes and every geometry payload remain intact; the web generator is unchanged. Owned stale output sentinels are pruned. The earlier failed comparisons remain in the receipts and are superseded by this explicit successful repetition.

A production Release whole-App comparison is in progress on a separately created simulator. It seeds only that simulator's own default App container with canonical synthetic pending rides across jp/tw/hk/mo/kr. This avoids inventing physically confirmed fixture paths while exercising real bundled country statistics. The UI test uses public tabs, localization arguments and ready/export control state, without DEBUG injection. Baseline and candidate have 11,885 identical build input files except EdgeIndexCache.swift; Finder metadata is explicitly excluded (`release-pair-source-sha256.json`). The declared protocol is three fresh processes per build in alternating order: candidate median settled footprint must be strictly lower, and median process peak must not rise. No whole-App result is claimed before all six UI runs and samples complete. Baseline Release build-for-testing passes; candidate build and runtime receipts follow separately.

### Whole-App memory gate: first measurement and allocation follow-up

The initial synthetic fixture marked the origin ridden and destination un-ridden. The real Release App correctly showed five unconfirmed journeys and did not build statistics; that run is invalid and preserved under `release-invalid-fixture-first-run/`. The corrected fixture marks both stops ridden while preserving `.pending` physical route confirmation. It exercises real five-country reference denominators without asserting any surveyed route between invented names. Its canonical bytes and hash are recorded.

All six corrected Release UI runs pass. Cache-lifecycle-only candidate median settled footprint is 243,075,904 bytes versus baseline 323,226,504 bytes (24.797% lower), but median process peak rises from 372,263,840 to 376,998,840 bytes. `release-app-memory.json` explicitly records `gate_pass: false`; this is not accepted as satisfying the predeclared combined retention/peak gate.

The next allocation change removes the full offset `mapValues` dictionary before merge, directly retains the first destination key, reserves final parallel-array capacity once, and appends qualified line names without a temporary mapped array. Temporal padding, duplicate-country rows, variant offsets, totals, order and first-owner rules remain unchanged. Read-only Grok 4.7/xhigh review confirmed the semantics and highlighted dictionary growth as a larger transient; Codex also reserves the destination map's upper-bound key count. Actual before/after static merge methods and the real RailCore.EdgeIndex pass all 781 ordered scopes through length four, including duplicate countries, edge collisions, shared/empty labels and short/long temporal arrays (`merge-allocation-parity.log`, exit 0). All seven cache lifecycle groups pass again. An incremental Release rebuild passes and a second, separately preserved six-run comparison is in progress under `release-merge-allocation/` using the same gate, fixture and unchanged baseline. No new threshold is selected.

### Accepted production Release retention and peak comparison

The allocation follow-up passes all six public Release UI runs and the unchanged declared gate. Baseline/candidate settled footprint medians are 327,453,600 / 239,454,968 bytes, **26.874% lower**. Process peak medians are 376,441,784 / 311,413,616 bytes, **17.274% lower**. No run reaches the operational budget. The same five-region canonical ridden-stop/pending-route fixture, device, SDK/toolchain, App code, data and Release flags are used; only EdgeIndexCache.swift differs. All trials and individual process samples are retained in `release-merge-allocation/release-app-memory.json`, protocol/source hashes and six result bundles. Both clean baseline and incremental candidate Release bundles also match all 1,086 deterministically packaged resource hashes (`release-bundle-resource-identity.json`).

This is a whole-App measurement of the five-region statistics workflow on one simulator/device/runtime, comparing cache lifecycle plus merge allocation with the prior statistics-cache implementation. It does not establish every screen's memory bound or equal Instruments results on physical hardware. The first failed peak gate and invalid fixture receipts remain preserved. Host-only graph, display and index-cache percentages are not added to these measurements. Grok handled the bounded read-only merge review; Codex implemented and validated the change.

The large-fixture follow-up only changes RailValidityTests' CodedHistoryEnvironment cache ownership to `.bounded(maximumNodes: 100_000)`, matching App admission, and invalidates it at query completion. Physical build policy, surveyed data, connector logic, endpoint variants, required line and 25–50 km assertions are unchanged. The earlier standard-cache run remains a failed budget receipt. The new focused run is pending; no successful history/full-suite assertion is made before completion.

### Rollback reader and bounded compiled-vertex ownership

Native rollback acceptance passes in a fresh injected storage directory: current RideStorage writes the canonical five-region fixture, the pinned repository-baseline reader/writer at `14d294653fa11e87b6fbfbe3b4eba43f40b65225` reads and rewrites it, and current code reads it again. All five region/record identities, ridden-stop flags and pending physical-route confirmation survive; final on-disk canonical bytes are identical (`rollback-reader.log`/`.json`, exit 0). Train, StoreOperations, Import, JSString and JSNumber schema/serialization sources are hash-identical to that pinned baseline, so both separately compiled App storage versions use the same schema library. This validates the repository baseline reader, not an untested App Store binary; no actual user container or offline North America archive is touched.

The first standalone historical test retry lacked the repository fixture root and failed before routing (`validity-bounded-current.log`); frozen app data/port fixtures were subsequently attached within the owned test snapshot. The data-correct retry still exceeds the 2 GiB operational budget at 2,312,538,656 bytes (`validity-bounded-data-current-summary.json`, watcher 2, test 143). Oversized graph construction is not silently truncated or made unsolvable.

Inspection found CompiledSections' growing vertex-ID/string tables were still retained beside uncached oversized graphs under bounded policy. RouteGraphStore now drops an over-budget compiler memo after graph construction and before station augmentation. The graph remains complete; `.standard` memo behavior is unchanged. Internal retainedCompiledNodeCount supports lifetime verification without a new public API. Three cache-policy tests pass, including release-before-augmentation and default-policy retention. An additional 26 tests across four suites pass: cache policy, compiled graph equivalence against the surveyed slice, physical topology and endpoint preflight (`compiled-cache-equivalence-tests.log`, exit 0).

Same-policy pre/post native comparison uses frozen actual RailCore libraries, 36 oversized 1,500-node corridors and a 1,000-node memo budget. Both return exactly 54,000 nodes, 107,928 edges and digest 7445723771498410693. End footprint changes from 25,231,864 to 7,553,528 bytes, **70.064% lower** (`compiled-cache-memory.json`). This measures compiler memo retention, not the national graph's allocation peak and not App UI; it is not added to the Release workflow percentages. The national historical retry still reaches 2,241,431,976 bytes and is stopped (`validity-compiled-budget-current-summary.json`, watcher 2, test 143). That large-fixture acceptance remains open. A surveyed-fixture rebuild-after-eviction check and latest integrated Release build follow separately.

The extra surveyed-fixture test passes after an oversized compiler memo is dropped and then rebuilt (`compiled-cache-surveyed-fixture.log`, exit 0). It compares all node coordinates, ordered adjacency, node metadata, ordered grid values and physical-junction rejection IDs/reasons with the direct physical builder. Latest code overlays are recorded in `compiled-cache-budget-overlay-sha256.json` and `current-code-overlay-sha256.json`; previous successful Release memory samples remain tied to their frozen pre-compiled-cache-change source manifest.

Latest production Release integration after compiler-memo eviction passes (`release-final-compiled-cache-build.exit`: 0), and its five-region public statistics workflow passes in 19.592 seconds (`release-final-statistics.exit`: 0, durable result bundle). Final Release again matches all 1,086 resource baseline hashes. Production source ownership (280 Swift files) and permanent xSmall...xLarge typography bounds pass. `current-validation-summary.json` records accepted scopes and open national-fixture/device/M conditions. S6/roadmap completion stays false. The earlier six-run App memory comparison remains scoped to its exact frozen statistics-cache source pair; the latest integrated build adds separately validated compiler-memo eviction, without relabeling earlier process samples as measurements of a new build.
