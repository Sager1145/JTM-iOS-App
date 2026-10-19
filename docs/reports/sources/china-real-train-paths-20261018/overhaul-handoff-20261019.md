# 中国铁路工作交接与数据结构改造准备

状态日期：2026-10-19。本文是本聊天的完成／未完成清单与迁移准备，未宣布数据结构改造已实施。用户最后要求先完整记录工作、准备改造；因此本轮停止在源码和证据候选，未发布攀枝花南补充，未执行新一轮 176 项重放。

## 先读这些记录

- [固定上游研究及算法比较](../crtrainroute-study-20261018.md)：源码、许可、候选接收、可借鉴与不可照搬的做法。
- [正式接入证据](../china-production-evidence-20261018.md)：OSM、官方身份、香港高铁与区域归属。
- [真实车次报告](README.md)、[结构化比较](comparison.json)、[逐项 CSV](comparison.csv)。旧轮次快照和被否决的方案继续保留。
- [原始工作范围账本](../../../superpowers/plans/2026-10-18-china-crtrainroute-intake.md)。本文补充交接，不替换历史证据。
- [现有身份重构提案 ADR 0013](../../../decisions/0013-railway-identity-registry.md) 当前 **Proposed**，包含公司／线路／公司车站／站群／运行模式与物理轨道分层。本聊天没有批准或实现该提案。其旧统计属于提案当时状态，不覆盖本文最新 CN 计数。
- 已有 [WGS84/MapKit 边界 ADR 0004](../../../decisions/0004-wgs84-mapkit-datum-boundary.md)、[拒绝无证连接 ADR 0007](../../../decisions/0007-fail-closed-route-solving.md)、[逐行程解析 ADR 0012](../../../decisions/0012-per-ride-resolution-and-catalog-eligibility.md) 继续适用。

## 已完成并进入正式资源

### 上游研究与独立接入

固定 CRTrainRoute 提交 `d75307df9c812abf1259b86b75202ba7b0048679`，保留来源、许可和候选导入记录。上游按坐标构图、骨架压缩、CSR/A* 及本地数据组织有可借鉴之处；其最短链权重与几何可能失配、同坐标全局焊接、无距离上限的主网吸附和最长 60km 自动补边不能直接用于本项目物理证明。没有把它的 pickle 成品图或算路结果作为正式拓扑。未证明 Railmap 整体更优、速度更快、内存更低或全国完整。

正式 CN 使用独立固定的 `china-261017.osm.pbf` 原始节点／way／relation 与版本，SHA256 `f38c0bfc91bab9451fb7a0a2a5a808fe150585e8785edf78cfdeddb2c2563175`，快照复制时间 2026-10-17T20:20:51Z。只读查询库为 `railway-sources/local/china/osm/china-261017-rail.sqlite3`。源文件在本地目录，不能假定换机器后已存在。

地区归属已明确并用于生产：整条广深港高铁及香港西九龙 XJA 属于 CN；其他香港铁路属于 HK；全部澳门轻轨包括横琴段属于 MO。没有通过跨地区重复身份或跨区域图混接实现高铁连续。

### 当前生产数量与修复

| 对象 | 最后已发布状态 |
| --- | ---: |
| CN compact 线路／记录 | 3,991 |
| compact 区间 | 17,594 |
| compact 站点线路归属记录 | 21,573 |
| compact 官方站码覆盖 | 2,715 / 3,404 |
| 已审定独立物理补充路径 | 14 |
| 补充路径节点出现次数／原始相邻边出现次数 | 2,428 / 2,414 |
| 新增独立物理身份 | 6 |
| raw N02 线路要素 | 17,608 |
| raw N02 车站归属要素／官方站码 | 21,576 / 2,716 |
| CN 原始同节点 junction／保留的审定引入线 | 3,719 / 2 |

出现次数不是去重节点／边数；原始关系分支记录不是 3,991 条独立法定铁路。非 CN junction 行在每次发布时保留，最近一次发布时为 203 行；并行聊天之后可能增加，不可用旧全文件覆盖当前同伴数据。

此前正式恢复的范围包括哈尔滨／小榄引入线、WRQ/ENM/SAO/DOP 的原始站轨归属、京沈联络原始轨道、昆明南和南昆—昆玉原始路径、新会—江门及江海—江门东；随后补齐成昆北段、峨广分支与广通北广昆自有前缀。具体 14 条路径逐项来源由 `railway-sources/china-reviewed-physical-sections.json` 保存，原始 adjacency／坐标／节点和 way 版本均在构建器验证。

CNW、PSW、XCE 三条 raw 站轨绑定已接入：标识来自真实原始关系成员车站和精确官方电报码／站名；锚点必须位于已验证的自有原始轨道、保留原始版本和 WGS84，沿用已有 1,500m 自有线路约束。PSW 新增一个运行时官方站身份；其余两条是既有身份新增真实线路归属。没有虚构中间客运站，没有把这些物理补充伪装为新 compact 线路。PSW/XCE 锚点不声称原始 stop_position。

南昆—昆玉 crossover 的运营机构来自明确记录的官方审阅推断；不能迁移后变成“原始 way 显式 operator”或法律产权证明。其他各条也应保留各自证据类型。

### 已修复的跨层问题

`source_review_id` 是审阅来源，不是物理身份 `source_id`。此前把审阅键写入 `source_id` 会污染身份，已经纠正。Swift/JS 对 CN 原始身份和 source-qualified 站点锚点增加约束，避免替换成附近地铁或同站其他站台；CN 图缓存保留 `source-display-identity:1|source-anchor:1` 纪元。编译缓存／显示几何不能掩盖原始物理缺口。

## 最后一次有效的大样本结果

完成时间 **2026-10-19T08:50:40Z**；176 个唯一车次／模式结果，completed、active=false、evidenceReady。原始输出在 `railway-sources/local/china/comparisons/real-trains-20261018/native-boundary-d271-final-session/`。实际执行环境见 [execution context](native-boundary-d271-execution-context.json)。

输入固定为 88 个公开车次号、87 个内部服务、1,098 次停站观察，两模式共 176 项；G383/G386 同服务别名，K458 部分停站记录，主要分析另列 86 个完整且去重服务。输入 SHA256 `67dd98c13ecfd536517ef34d591eaceb088fb717aa5d41cf19e021f78a023335`。无公司、指定线路 ID 或目标里程提示。官方记录证明公开停站表，不证明当天实际开行及唯一经由股道。

| 模式／指标（全部 88） | 原始 repo | Railmap 最后正式结果 |
| --- | ---: | ---: |
| 仅端点完整候选 | 75/88 | 14/88 |
| 强制真实停站完整候选 | 49/88 | 14/88 |
| 强制停站返回几何区段 | 756/1,010 | 552/1,010 |
| 其中内部已解析 | 756/1,010（原 repo 定义） | 507/1,010 |
| 物理缺口条目 | 无等价证明模型，null | 45 |

完整候选必须覆盖全部请求区段且无未解析或物理缺口；它仍不是实际列车唯一轨道认证。原 repo 的 null 缺口不能当零。Railmap 本轮之前的几何提升为 542→552，完整仍 14；新发现的攀枝花南候选未计入。

主样本 86：原 repo 两模式完整 73/86、47/86，强制几何 717/971；Railmap 完整均 14/86，强制几何 535/971、内部已解析 491、缺口 44。完整候选的同源站位筛查 112 个有参照、4 个无参照，未发现超过 2km；这不是独立坐标精度测量。

最后 CN 资源修订 `0f6ce85ec6d41ecc9db431a31d8ae04ac907bf89cefb2c5ac86943f9455ce2d6`，编译 UUID `B8FD2EEC-47F0-3FB3-AE63-7370C4FC356A` arm64；CN-only 依赖，标准诊断缓存，产品默认 bounded100000 未修改。原生结构失败 0、待审阅条目 714；这些不是全国验收通过。

原 repo 代码／7 个输入文件在最后正式复测时核对不变，复用固定 baseline，没有为每轮修复重跑原始引擎。在线坐标传输 HTTP502 后采用同提交离线站点 JSON，不改上游算法或原始坐标。最后逐项独立审阅确认原始 176 项结果不变、Railmap 10 个新几何部分、无丢失；554 个旧坐标数组完全相同，另两个保留完整原坐标后缀。详见 `boundary-d271-result-review.json` 与 `boundary-d271-independent-output-review.json`。

## 四个目标：已知事实与缺口

| 目标 | 最后正式原生结果 | 本轮新证据 | 仍未完成 |
| --- | --- | --- | --- |
| G6045 广州南 | 11/11 几何、10 内部解析，section4 边界缺口 | 原始 stop_area13696629v4 有广州局 operator；track15 的 stop11832431941v2 确在 way845559683v3 | 6 条 sidings 缺逐轨运营者归属，其余 5 条没有自身 stop 成员／track_ref；未证明固定锚点可通，也未找到 G6045 实际使用 15 道证据。不能泛化站运营者覆盖整个咽喉或换锚点 |
| G101 沈阳北 | 4/4 几何、3 内部解析，section1 边界缺口 | 自有306原始链可延伸至哈尔滨，再接704原始部分；1067140203v3 后的1067140215v3 确恢复704成员身份 | 沈阳北 crossover1364948209v1 无 operator／客运／关系证据；哈牡1067140203v3 虽有客运名／ref3073，却无 operator、无关系成员。不能仅将缺口移到下游即宣称修复 |
| D271 攀枝花南 | 14/14 几何、13 内部解析，section6 边界缺口 | **找到固定锚点间 15 条原始相邻边、1,486.71m**。742037844v20 补8边，1101437978v9供7边；两 way 明确 name峨广线/ref0084/operator中国铁路成都局集团 | 742037844 无原始 relation 成员、无直接 passenger tag。直接 way 归属候选未完成合同／客运关联负例，未编译正式数据，未做原生聚焦或176复测，不能说 D271 已完整 |
| D239 楚雄—丽江 | 6/7 几何、5 内部解析；section2 攀枝花南缺口及 section4 未解析 | 两端官方绑定和各自已发布路径完整；最小漏链为1004183415v2，原始节点9265421518↔2215382233 | 此 way 无 owning-relation／operator／显式客运证据；附近14条 component bridges均未满足当前要求，211549795v3 有客运标签仍缺关系／机构。尚无可正式接入方案 |

源报告：[广州南](guangzhou-south-boundary-continuation3.json)、[沈阳北](shenyang-north-boundary-continuation3.json)、[攀枝花南本轮](panzhihua-south-continuation4.json)、[楚雄—丽江本轮](chuxiong-lijiang-continuation4.json)、[直接 way 归属合同审阅](original-way-ownership-contract4.json)。邻近、同名、站群、视觉交叉和坐标重合均不能代替原始相邻轨道证明。

攀枝花南的 [中国铁路原始机构发布](https://www.thepaper.cn/newsDetail_forward_21310477) 明确列出米易东—攀枝花南、攀枝花南—永仁已运营区段并描述 CR200J 客运；这属于走廊级证据，未证明某车次具体隧道／股道。way 的 2020-05-26 start_date 不作为客运开通日。

## 本轮已改代码，但尚未发布的工作

工作树中有本轮两处源码改动：

- `app/scripts/railway/build-china-physical-junctions.py`：可选 `sourceOwnership.mode=original-way-identity`，每条原始 way 的 name、ref、operator 必须逐字匹配独立物理身份；默认仍需完整原始 relation 成员。
- `app/scripts/railway/tests/test_china_physical_junctions.py`：最终 **24 tests passed / 0 failures/errors / exit0 / 0.036s**。记录了真实 RED/GREEN；检查直接身份缺省／漂移、上下文原始字段／版本。此结果只覆盖聚焦测试，不是新资源或原生结果。

新模式输入还需要 `sourceRelations[{id,version,name,ref,operator}]` 与自身原始上下文字段一致。上下文 relation 的泛称运营者中国铁路和直接 way 的中国铁路成都局集团分别保留，不做无证据别名。输出 proof 增加 `sourceOwnership`、`sourceRelationEvidence.memberPathWayIds` 和 `sourceWayEvidence.sourceRelationIds`，不虚构遗漏 way 的关系成员。

**发布前必须解决：** reviewed-official-corridor 选中的上下文 name/ref 尚未显式校验等于 direct-way identity 的 name/ref；新直接模式下的客运缺失／不相干走廊负例尚未补全。当前生产 manifest 的14条全部未启用新模式，因此没有依赖这个未完机制。不能因24测试通过就认为这个接口可发布；改造时应明确建模这条证据关联，而不是漏掉它。

[保存的攀枝花南 proposedSection](overhaul-preparation4/panzhihua-south-proposed-section.json) 只是审阅输入；本地完整候选在 `/private/tmp/cn-fourth-20261019/reviewed-physical-candidate.json`，15条候选不能当成生产14条。**未运行 candidate junction 构建、未安装资源、未修改 rail.db、未重签应用、未构建二进制、未重放4目标或176输入。** 新代码不回滚、不删除；交给后续改造明确承接。

## Apple Maps / RailInspector：准备与未完成

用户要求缺数据时参考另一个 chat 的 RailInspector 截图。已阅读其流程及现有实现：自动 alignment 只接受 JP，任意相机可手动定位 CN，可导入外部 GeoJSON。准备了 [四处原始参考路径](overhaul-preparation4/original-targets.geojson)、[七个相机](overhaul-preparation4/camera-plan.json) 和 [能力／限制报告](apple-capture-preparation4.json)，坐标仍为原始 WGS84。

本聊天实际打开隔离 B8 Diagnostics、进入 Alignment、手动定位沈阳北 `123.422,41.815,z17` 并切底图。**没有导入这份参考文件，没有导出截图，没有查看／比较实际原图，没有形成像素或连通结论。** 因用户改为先文档交接而停止。

现有手动导出的 metadata 即使相机在 CN，仍会标记选中的 JP 区间；必须显式标为外部参考／底图证据，不能伪称 CN 原生线路验收。后续可审查是否为 inspector 增加地区中立的参考视点身份；当前未实现。Apple 截图本身也不证明运营者、法律归属、原始 OSM 节点连接或实际班次股道。未建立跨多处独立坐标基准的像素测量，不能移动 canonical WGS84 来迎合底图。

已用⌘Q退出本聊天应用，随后 focused ps 未见 RailDiagnostics／RailMap／xcodebuild；已明确向 `继续逐线检查车站线路偏移与断点` 归还重型／原生窗口。后续启动任何 capture/build/solve 必须重新协调；其他 chat 的当前状态不可由这条历史退出记录推定。

## 数据结构改造的输入与不可丢失的信息

当前依赖链：原始 SQLite → `cn_package.py` 与两类 CN builder／审阅 manifest → compact + sources.byLine/byPhysicalSection + raw sections/stations + junction registry → Swift/JS 路由、显示与导入；`rail.db` 是派生镜像，不能作为唯一权威，也没有包含 US/CA 管线。`app/data/registry/` 此次读取时尚不存在；ADR 0013 中的注册表不是已落地资源。

迁移必须同时承接以下对象，而不是把现有 `line` 一对一改名：

| 必须区分的对象 | CN 的真实案例／迁移风险 |
| --- | --- |
| 源对象、稳定实体、证据记录 | OSM relation/way/node 各有源版本；`source_review_id` 不是 trackID；源编号只应作外部引用，不能把审阅键当物理连接身份 |
| 官方线路、方向／分支／服务模式、物理路径、绘图分段 | 3,991条compact记录含OSM方向和branch；14条物理补充独立于compact，不能丢失或自动升级成14条客运线路 |
| 运营机构、法律产权、线路上下文 | 泛称中国铁路、精确局集团名称、官方推断分别保留来源／角色；字符串正规化不能变成产权证明 |
| 官方车站、站群、线路成员、物理锚点 | 同一12306站码可有多个轨道归属；三个raw-only绑定未完整出现在compact／rail.db中。站群只表达归组，不自动生成轨道转移 |
| 归属地区与地理边界 | HK境内高铁属CN，横琴澳门轻轨属MO；region不能从经纬度或行政区反推覆盖用户已定数据归属 |
| 有效日期与采集日期 | reviewedAt／snapshot／way start_date不等于客运开业；未知保留null，按既有半开有效期模型迁移 |
| 物理证明、显示几何、诊断结果 | 原始sourceCoordinates与MapKit转换、display smoothing／lanes／history各自有用途；新缓存必须随相关来源／模型变化失效，不能复用旧的“证明” |
| 路径几何、区段覆盖、边界缺口 | 14/14有几何但1处边界未证是partial。迁移不能把nonnull polyline当complete，不能把原repo缺口null当0 |

## 迁移代码定位与已有提案的差异

| 数据责任 | 当前实际入口／消费者 |
| --- | --- |
| 原始源库 | `app/scripts/railway/extract-china-osm.py::extract`，保留原始节点、way顺序、成员角色、标签和版本 |
| 中国打包 | `build-china-rail-package.py::main` → `cn_package.py::ChinaBuilder` 的 `graph`、`stations`、`choose_ordered_anchors`、`compile_route`、`build`；`make_artifacts` / `write_outputs` 输出compact及raw |
| 来源引用 | `cn_package.py::factor_source_records` / `resolve_line_sources`；compact的 `sourceRef` 指向 `sources.byLine`，不能因来源去重丢失逐区段和逐站证据 |
| 物理补充 | `build-china-physical-junctions.py::compile_reviewed_physical_sections` / `compile_reviewed_physical_station_bindings` → `byPhysicalSection`；`physical_graph_view` 仅是校验视图，不能冒充显示包 |
| 物理拓扑 | 同一builder的 `build_reviewed_connections` / `build_junctions` → `app/data/physical-rail-junctions.json` |
| 原生与Web图／求解 | `ios/RailKit/Sources/RailCore/Routing/RouteGraph.swift`、`RouteSolver.swift` ↔ `app/public/app-route-graph.js`、`app-route-solver.js` |
| 显示与目录 | `CompactPackage.swift`、`Rendering/DisplayParts.swift`、`EditorCatalog.swift::StationKey` ↔ `app/public/rail-network.js` |
| 行程兼容 | `Import/ImportEngine.swift` ↔ `app-import.js`；`Journeys/StoreOperations.swift` ↔ `app-store-ops.js`；`JourneyCompletion.swift` 与canonical export |
| 派生数据库 | `app/scripts/build/build-rail-database.mjs` → `rail-database/load.mjs` / `schema.sql`；该镜像不是应用当前读取的主数据库 |
| 资源与缓存 | `RailResourceRevisions.swift`、`EdgeIndexCache.swift`、`RouteGraph.swift` 与JS图缓存策略 |

具体耦合：Swift `RouteSolver.recordedStationSourceAnchorKey` 与JS同名函数由 lineID、operator、lineName、class、原始anchor构造qualified key。当前Swift没有在此提供sourceID，JS会展开feature properties；新增身份字段前必须检查这一差异。Swift `RouteGraph` 解码 `source_id`，不解码 `source_review_id`；两者不能在新结构中互为alias。

`rail-database/load.mjs` 的 `stationAgg` 来自compact的line stations；raw-only车站在 `source_station` 可以因compact缺group而 `station_id=null`。因此只迁移rail.db会漏掉真实站轨绑定，也不能把null行当坏数据删除。

ADR0013 §8 当前安排P0一对一铸造身份，CN relation归并延后P3；本聊天不提前宣称归并完成。§7提到compact构建器在另一网站仓库，但本checkout实际上含CN提取和构建器，执行前需明确这部分责任。P1行程／导出版本时机与运行时注册表格式仍待定。0004／0007中的旧runner描述仅为历史，当前 `ios/VERIFICATION.md` 的聚焦流程优先，不恢复已退役验证矩阵。

## 改造准备的下一步（均未执行）

1. **对齐 ADR 0013 的阶段和实体边界。** 先确认其稳定ID、alias、external_ref、line_stop／track_section能保存上述CN源版本／证据和站轨锚点。将直接way／relation成员／官方走廊作为可区分的关系，不预设数据库或新字段已获最终批准。
2. **确定兼容映射。** 为当前每个published legacy lineID/branch、station code/group、physical trackID、source node、review ID建立明确映射；保留多对多与未决状态。对已保存行程的旧引用提供alias兼容；一对多身份不明时按0012拒绝自动选择。映射不能按站名或同坐标推断。
3. **先完成证据合同。** 使用PNE742037844、SBT1067140203、GZS六sidings和D2391004183415作为真实正负例；补齐直接way与官方客运上下文关联以及负例，再决定是否生产启用。PNE真实原始连续链不等于全部新模式已经可发布。
4. **做可比较的兼容导出。** 先从新结构导出旧compact/raw/source/junction接口，逐个审阅上述真实目标的源节点、归属、缺口与历史引用；不要立即同时替换所有运行时。保留旧资源和可回退读取路径，不要求为了文档重建全国数据。
5. **同步审阅Swift/JS与诊断。** 原始身份、站轨锚点、资源revision／缓存、ride persistence／导入解析和显示映射必须引用同一实体规则；把JP专属inspector receipt与CN外部视点分开。
6. **正式变更后再验证。** 先执行相关现有聚焦回归和四目标原生检查；出现真实依赖变化才做一次共享增量构建。届时重用固定输入执行用户要求的88×2复测，对比原repo固定结果，并保存新revision/实际完成状态。没有改动相关baseline依赖时不重复重跑原repo。

这些是改造准备与执行顺序，不是全部细节已定的实现合同。迁移范围、存储格式、ID分配／alias持久化、源证据关系、跨国适配以及与已有ADR提案的最终取舍尚未完成。

## 会话状态和禁止误读

没有commit、push、merge或发布授权，未执行这些操作。共享工作树含大量其他聊天改动，不应reset、清理或按本聊天旧全文件覆盖。Grok本会话鉴权不可用，未盲目重试；源取证和有界代码／文档审阅由GPT-6.1 Sol子任务完成，Codex负责集成判断。

本轮只补证据、24聚焦测试和文档交接。所有正式生产计数与176结果仍指向08:50:40Z的旧已完成状态。广州南／沈阳北／攀枝花南边界和楚雄—丽江缺口没有在本轮宣称修复。全国路径完整性、实际班次唯一经由、性能、像素对齐、完整历史开通日期仍未证明。
