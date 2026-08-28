# JTM iOS 全链路性能优化 Prompt

> 将下方内容完整交给编码代理执行。它针对当前仓库，而不是通用 SwiftUI 项目。

---

你是一名资深 iOS 性能工程师。请在当前 `JTM-iOS-App` 仓库中，对 `ios/` 原生应用做一次**有基线、有证据、行为不变、可验证**的全链路性能优化，并直接完成代码、测试、性能基准与文档更新。

目标不是让代码“看起来更快”，而是让用户可执行的全部操作在真实设备的 Release 构建中更快、更稳、更省内存，同时保留现有业务语义、视觉质量、无障碍行为、数据兼容性和 JavaScript/Swift 对拍结果。

## 1. 先理解当前工程

开始修改前，完整阅读：

- `ios/README.md`
- `ios/AUDIT_PLAN.md`
- `ios/PORTING.md`
- `ios/verify.sh`
- `ios/RailKit/Package.swift`
- 本次涉及文件顶部及相关函数附近的设计注释

当前结构是硬约束：

```text
RailMap app target         SwiftUI / UIKit / MapKit / Vision / AVFoundation / 存储
        ↓
RailPresentation          Foundation + RailCore
        ↓
RailCore                  Foundation only，和 JavaScript 共用 golden fixtures 对拍
```

项目部署下限是 iOS 17，无远程第三方依赖。不要为了性能引入第三方库，也不要把平台类型下沉到 `RailCore` 或 `RailPresentation`。

当前代码已经包含有效优化，必须保留或以数据证明替代方案更好：

- `MKMapView` + `MKMultiPolyline` 批处理，而不是一段一 overlay。
- 基于缩放级别的 LOD、屏外裁剪、顶点预算和 Douglas–Peucker 抽稀。
- 地图平移期间延迟昂贵 rebuild，只连续 restyle。
- 五地区 rail package 后台并发解码、按完成顺序渐进发布。
- 路线运行时缓存、dataset part index、edge index actor cache。
- JSON/路线求解/统计/导入等重工作尽量离开主 actor。
- `ContentView.page(...)` 中的 `AnyView` 是为避免真机主线程栈溢出而保留的实测修复，不得按通用规则删除；除非在 iPhone 真机旋转场景中证明替代方案不会恢复崩溃。

## 2. 不可破坏的契约

1. **行为一致**：增删改、搜索、筛选、地图选择、路线求解、统计、导入导出、OCR、播放和视频导出的结果不得变化。
2. **跨端一致**：`RailCore` 的排序、字符串、浮点计算、坐标 key、缓存 digest、输出顺序和 JSON 拼写不得凭“数学等价”改写。IEEE-754 运算顺序不同也可能破坏 fixture。
3. **持久化安全**：继续保证原子写入、写入顺序、备份先于破坏性操作、最新编辑不会被较旧异步结果覆盖。不得用丢保存、延迟到可能丢数据的方式换取表面响应速度。
4. **地图质量**：不得通过随意隐藏线路、降低标记质量、放大抽稀误差、降低交互命中率来“优化”。现有 `RailStyle.simplifyTolerance` 和 `verify.sh` 的文本契约必须保持通过。
5. **交互和无障碍**：不能减少 Dynamic Type、VoiceOver、Reduce Motion、Reduce Transparency、键盘快捷键或触控反馈能力。
6. **并发正确性**：遵守 Swift 6 strict concurrency；后台任务只传递 `Sendable` 值；UI/MapKit/UIKit 状态只在主 actor 使用；所有长任务都要支持取消或清楚说明为什么只能丢弃结果。
7. **工作区安全**：当前工作树可能已有大量未提交改动。先运行 `git status --short`，保留所有现有修改；不要 reset、checkout、stash、删除或覆盖不属于本任务的内容；不要自行提交。

## 3. 工作方式：测量 → 排序 → 小步优化 → 同场景复测

### Phase A：建立可复现基线

先列出用户操作矩阵，并在**同一台真机、同一 OS、同一数据集、Release 配置**下记录基线。Simulator 只能补充诊断，不得作为唯一结论。

至少覆盖：

| 场景 | 必测操作 |
| --- | --- |
| 启动 | 冷启动、暖启动、首个可交互画面、五地区网络加载、首条已乘路线出现 |
| 地图 | 连续平移、持续 pinch 跨多个 zoom tier、旋转、开关完整网络、切换线路/站点/类别图层、地图点选重叠路线、点选车站、自动聚焦 |
| 面板 | 拖动 compact/medium/expanded、切 tab、横竖屏切换、列表滚动 |
| Journeys | 全量列表、日期筛选、逐字搜索、选择、隐藏/显示、移动、复制、删除、保存编辑、站点选择器搜索 |
| Passport/统计 | 单地区/全部地区首次打开、切地区、切日期、展开线路明细、路线编辑后刷新 |
| 数据 | 样例载入、1 MB 级 JSON 导入预检/提交、导出、保存、备份、恢复、删除全部 |
| 路线 | 冷缓存加载、暖缓存加载、单条重建、大批 cache miss 求解 |
| 播放 | 单条/多条播放、暂停、倍速、自动跟随、持续 60 秒 |
| 视频 | 各分辨率/比例导出、取消后生成部分视频、长时间导出 |
| OCR | 单图、多图、长截图、多 tile、取消、接近内存上限的合法图片 |
| Maps 搜索 | 首次车站卡、同站重复打开、命中、未命中、网络失败 |

添加轻量、可保留的性能观测层，优先使用 `OSSignposter`/`os_signpost`，至少标记：

- app launch、network package decode/publish；
- `RailMapView.Coordinator.update`、rebuild 的纯计算阶段、MapKit apply 阶段、annotation 更新；
- map tap candidate query；
- itinerary group/save/load/import；
- route cache read、dataset lookup、solver context build、solve、cache write；
- edge index build/merge、ride matching、statistics aggregate；
- playback tick/render、video frame capture/append；
- OCR decode/render/recognize/stitch。

禁止在每帧热路径留下同步 `print`/`NSLog`。Release 中观测开销必须极低，并可用编译条件或统一开关关闭。

使用 Instruments 至少采集：

- SwiftUI instrument / View Body Updates；
- Time Profiler；
- Hangs / Animation Hitches；
- Allocations + Leaks；
- Core Animation；
- Energy Log（播放、视频、OCR）；
- 必要时 Metal System Trace（地图）。

输出一张基线表，包含 p50/p95/最大耗时、主线程最长连续阻塞、hitch 数、CPU、内存峰值和关键对象/overlay/vertex 数。没有基线前，不要开始大规模重构。

### Phase B：按实测影响排序

下面是当前代码审查发现的**高价值候选点**。它们是待验证假设，不是要求盲改的清单。先用 trace/signpost 证明，再按“用户影响 × 频率 × 成本”排序。

#### P0：高频主线程与帧更新

1. `RailMapView.Surface.Coordinator.rebuild(on:)`
   - 当前代码注释记录日本网络一次 rebuild 约 150–460 ms；`ios/README.md` 也有 19/98/229 ms 的历史测量。
   - 保留现有 batching、LOD、built rect、zoom bucket、vertex budget 和 gesture defer。
   - 将 rebuild 拆成：后台生成纯 `Sendable` build plan；主 actor 只创建/复用 MapKit 对象并做最小 diff/apply。
   - 使用 generation token + cancellation，旧 pan/zoom 结果绝不能覆盖新视口。
   - 比较一次性 remove-all/add-all 与 overlay/annotation 增量更新；只有 trace 证明更好才采用。
   - MapKit 对象不得越过 actor 边界；后台阶段只处理坐标、索引、样式 token 和普通值。

2. `RailMapView.Coordinator.handleMapTap(_:)`
   - 当前实现每次 tap 都把所有 ride 的每个坐标投影到屏幕，再交给 `RideTapResolver`，复杂度接近 O(全部可见/不可见顶点)。
   - 建立随 ride generation 更新的空间索引/包围盒，先按点击容差和可见 rect 选出少量候选，再只投影候选 segment。
   - 保持“命中一条直接选中、命中多条弹选择、零条逐级返回”的现有语义及精确容差。

3. `PlaybackController.tick(timestamp:)` 与观察扇出
   - `progress`、`stationName`、`exportFrameSerial` 等在 display link 路径更新；地图需要 60 fps，但 SwiftUI 文本/进度条不需要整棵 `RailWorkspaceView` 以 60 fps 重算。
   - 将 60 fps 渲染状态与低频 UI 展示快照分离；地图仍逐帧，SwiftUI 可按视觉可辨阈值或 10–15 Hz 发布。
   - 把播放条、当前行程状态等观察范围收窄到叶子 view，验证列表中非当前行程不会随每帧重算。
   - 不得降低动画路径、时序、站点 pulse 或视频帧正确性。

4. `RailWorkspaceView` 的高频失效
   - `ContentView.swift` 中 sheet 拖动会逐帧更新 `sheetHeight`/expansion；同一大 view 还读取多个 store 和大量派生数组。
   - 用 SwiftUI body update trace 找出拖动、播放、地图回调时实际重算的子树。
   - 将实时 sheet chrome、地图、列表、统计、播放条拆成观察输入更窄的稳定子树；传入小型 value snapshot，而不是让叶子读取整个 root store。
   - 不要对所有 view 机械添加 `.equatable()`；只有比较成本显著低于重建且输入是稳定值语义时才使用。
   - 不要删除为真机栈溢出保留的 `WorkspacePage`/`AnyView` 边界。

#### P1：重复派生、搜索与列表

5. 缓存或集中生成下列派生结果，避免在一次 body 中多次扫描同一批 trains/rides：
   - `statisticsScopedTrains`、`statisticsDates`、`mapRides`、`playbackScope`、`rideIDs`、`riddenCountries`；
   - `upcomingTrains`、`latestPastTrain`、`filteredDays(...)`；
   - `PassportWorkspaceView.scopedTrains`/`logDays`；
   - `StatisticsDashboardContent.scoped(...)`、line coverage rows/排序。
   - 建立一个由明确输入 generation 驱动的派生 snapshot/cache；不要把任意计算塞进 `@State` 充当不透明缓存。

6. Journeys 搜索与 station picker：
   - `filteredDays`/`JourneySearchMatcher.filter` 当前会在输入过程中重复遍历字段；先测量 201 条及更大数据集。
   - 为每条 journey 预生成保持 locale 语义的 searchable projection；query 做规范化后复用；必要时加入短 debounce，但清空和结果反馈仍要即时。
   - `RideEditorView.filteredStations` 当前每次先去重、再 locale 排序、再过滤。把与 query 无关的去重/排序移到 stations generation 变化时；逐字输入只做过滤。
   - 所有 `ForEach` 检查稳定身份。只对真正动态、可插入/删除/移动的数组替换 `.offset`/indices；静态显示数组不做无收益改写。

7. 编辑器验证：
   - `RideEditorView` 在整个 `draft` 每次变化时重新编码并运行完整验证。用 signpost 测量长 stops 列表逐字输入。
   - 可将便宜字段规则即时执行，把昂贵的全量 canonical validation 做可取消的短 debounce；保存前必须同步执行最终权威验证。
   - 错误顺序、字段定位、保存禁用条件和 fixture 语义必须完全一致。

#### P1：加载、求解、统计和存储

8. `EdgeIndexCache.merged(countries:)`
   - 当前循环逐个 `await index(country:)`，首次“全部地区”可能把本可并行的地区构建串行化。
   - 评估用 task group 并发请求各地区 index，最后严格按输入 countries 顺序 merge。
   - 同一地区仍只能有一个 in-flight build；取消一个等待者不能取消其他调用者依赖的共享构建。

9. `RiddenRouteStore`
   - 审查同一 train 在 `loadCached`、dataset 校验、`drawnRide`、`saveCache` 中重复执行 `normalizeExportTrain`、canonical sections、template/cache digest 的次数。
   - 为一次 load 生成不可变 `PreparedRouteRequest`，一次计算并复用 normalized train、region、sections、policy、digests。
   - route cache 小文件逐条 read/decode、dataset part 顺序 I/O、各地区 solve 可在内存预算内做有界并发；最终输出顺序必须与 itinerary 顺序一致。
   - solver resources/graph/index 是否缓存要以冷/暖路径和内存峰值共同决定。避免为了省 CPU 长期保留五套巨大 graph 导致内存恶化。
   - `solveMissing` 中 section 之间有 continuity 依赖，不能错误并行；不同 train/region 只有在 graph/cache 的线程安全与确定性被证明后才能并行。

10. `MileageStatisticsStore`
    - 保留 `EdgeIndexCache` 和已有 prepared `Context`。
    - 测量 `matchRides`、`Statistics.collectTrainStatsEntry`、`buildMileageStatsView`；只重算受编辑影响的 train entry，并按 stable id/digest 缓存，其余复用。
    - 进度发布继续批量化，禁止每条记录一次主 actor hop。
    - 切日期只做 scope aggregate，不得重读网络或重匹配路线。

11. `RailNetworkStore.loadAll()`
    - 已经并发解码并渐进发布，默认保留。
    - 量化五包同时解码的峰值内存和启动争用；若内存压力明显，使用 2–3 个任务的有界并发，并证明首个可用地区/总完成时间的综合表现更好。
    - 避免每个地区发布都导致隐藏的完整 network 或所有 ride overlay 重建。

12. `ItineraryStore` / `RideLibrary`
    - 保留后台 grouping、storage actor、原子写和有序队列。
    - 测量一次编辑引发的完整 regroup、route reload、statistics reload、全量 JSON canonical export/write。
    - 使用 store generation 和精确 change set，让纯 visibility/order 改动不触发不相关的路线求解；几何相关字段变化仍必须失效。
    - 相邻 fire-and-forget 保存如果要合并，只能在不跨越 backup/import/delete/restore 等顺序屏障的情况下采用 latest-write-wins，并必须保证调用者等待的 save 能得到自身准确结果。
    - 不得改成另一个数据库格式；保存文件必须继续与 WebUI 双向兼容。

#### P2：播放、视频、OCR、图片与系统服务

13. `PlaybackVideoExporter.append(_:)`
    - 当前逐帧在主 actor 执行 `mapView.layer.render(in:)`、caption 绘制和 pixel-buffer append。分别测量 capture、caption、writer backpressure、内存分配。
    - MapKit/UIKit capture 留在主 actor；可发送已完成的 pixel buffer/纯值给专用编码执行上下文，但先确认 `AVAssetWriterInput` 的线程约束和顺序。
    - 复用 CGContext、文字布局、颜色等现有 cache；为每帧建立 `autoreleasepool`，验证长视频内存不阶梯增长。
    - 正确处理 `input.isReadyForMoreMediaData`，不得通过无提示丢帧让进度与成片时间错位。

14. `TransferGuideOCR`
    - 已有像素上限、tiling、取消检查。测量 decode、scale、Vision recognition 和 stitch 的占比。
    - 只有在 Vision 与内存行为允许时才做小规模有界并发；合并顺序必须按 page/tile 稳定，进度单调，取消及时。
    - tile 用完即释放，不同时持有不再需要的原图、crop、scaled image 和 Vision results。

15. `StationPlaceStore`
    - 已缓存命中、miss 和 in-flight task，保留。
    - 增加取消/超时场景验证；不要让关闭卡片导致共享查询被错误取消，也不要让失败查询无限重试。
    - 不试图用 CPU 微优化掩盖 `MKLocalSearch` 网络时延。

16. `RailCore` 算法
    - 先为 RouteSolver、RouteGraph、Statistics、OverlapLanes、StationJoinSmoothing、DisplayParts 增加可重复的 benchmark。
    - 优先减少重复扫描、临时数组、字符串 key、字典查找和不必要 copy；合理 `reserveCapacity`。
    - 任何算法改写都必须通过同一 fixtures，输出顺序与浮点 bit pattern 要按该函数现有契约验证。不能仅凭“大致相等”接受。

### Phase C：实施纪律

每次只处理一个可测瓶颈：

1. 记录 baseline trace/signpost 数值和根因。
2. 写回归测试或 benchmark，确保能捕获预期改善或至少防止退化。
3. 做最小改动。
4. 跑相关单测和场景复测。
5. 记录 before/after、统计口径、设备、构建配置和数据规模。
6. 改善不足 10% 且增加明显复杂度时，回退该优化；不要留下“可能更快”的复杂代码。

禁止：

- 把所有东西都放进 `Task.detached`；
- 用无界并发同时解析所有文件/图片/路线；
- 在 `body` 中排序、过滤、解码图片、做 I/O 或业务运算；
- 用 `AnyView`、`.equatable()`、`drawingGroup()`、缓存、lazy 作为全局万能药；
- 用降低视觉/数据正确性换 benchmark；
- 为了漂亮数字只测 Debug、Simulator 或空数据集；
- 一次性重写整个 `RailMapView`、`ContentView` 或 store 层，导致无法归因。

## 4. 性能验收标准

所有比较必须同设备、同数据、同交互脚本、Release 构建，至少重复 5 次并报告中位数和 p95。优先满足：

- 用户手势期间不执行可避免的 50–100 ms 主线程工作；持续 pan/pinch/sheet drag 不出现可重复 hitch 或 hang。
- 地图完整 rebuild 的主线程 apply 被显著缩短；总耗时相对基线至少改善 30%，或给出 trace 证明瓶颈已是不可后台化的 MapKit 系统工作。
- 地图 tap 不再随全部路线总顶点近似线性增长；大数据集 p95 明显低于基线且命中结果完全一致。
- 播放保持地图 60 fps 目标，同时 SwiftUI body update 数大幅下降；非当前行程 row 不应逐帧更新。
- 搜索和 station picker 输入没有可感知卡顿；每次 query 的主线程工作应控制在一帧附近，超大数据集允许短 debounce 但结果必须及时。
- 冷启动、暖缓存路线加载、首次全部地区统计、导入、OCR、视频导出各自至少改善主要瓶颈 20%，否则不保留高复杂度改动。
- 稳态内存不增长；长播放/长视频/OCR 结束后可回落；无新 leak；峰值内存不得无解释地增加超过 5%。
- CPU/能耗不能因轮询、过度并发或过密进度发布明显恶化。

若某目标无法达到，不要伪造数字或继续堆复杂度。说明系统瓶颈、证据、已尝试方案及下一步需要的 Instruments 数据。

## 5. 正确性与构建门禁

每个阶段至少运行相关测试，最后必须运行完整门禁：

```sh
cd ios/RailKit
swift test --scratch-path /tmp/jtm-performance-railkit

cd ../
./verify.sh
```

同时：

- 保持 Swift build/app build 0 warning；
- 保持所有 RailCore/RailPresentation parity tests 通过；
- 为缓存 generation、取消、latest-wins、稳定顺序、空间索引命中、UI 发布节流添加单测；
- 为地图 pan/pinch、sheet drag、播放、搜索、导入、统计添加或扩充 UI/performance 测试；
- 在至少一台 iPhone 真机验证横竖屏切换，防止移除或绕过 `WorkspacePage` 后恢复 stack overflow；
- 检查 `verify.sh` 中所有路径/文本契约仍然有效。若移动代码，必须同步调整 gate，不能删除检查。

## 6. 最终交付格式

完成后提供：

1. 一页摘要：最主要的 5 个瓶颈、根因、改法、用户影响。
2. before/after 表：设备、OS、Release 配置、数据集、重复次数、p50/p95、CPU、内存、hitch。
3. 按操作列出结果：启动、地图、面板、列表/搜索、编辑/保存、导入导出、路线、统计、播放、视频、OCR、Maps 搜索。
4. 修改文件与架构说明，特别标出新的 cache/generation/cancellation 边界。
5. 测试与门禁结果。
6. 尚未解决或只能由系统框架决定的瓶颈，以及下一次应采集的精确 trace。

结论中区分：

- **trace-backed**：有 Instruments/signpost 数据确认；
- **benchmark-backed**：有稳定微基准确认；
- **code-backed hypothesis**：仅由代码审查推断，尚需运行证据。

不要只报告“减少重复计算”“使用异步”等手段。必须说明哪一个操作从多少变成多少，以及为什么没有改变结果。

