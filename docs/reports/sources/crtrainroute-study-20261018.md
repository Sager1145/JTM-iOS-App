# CRTrainRoute 中国铁路源研究与生产续接（2026-10-18）

## 上游结论、初期接收与当前生产范围

CRTrainRoute 可作为中国铁路的**本地候选源和算法参考**，不能把其成品图或算路输出直接当作 Railmap 已审核的物理铁路。OSM 可以按韩国包相同的几何回退层级使用；上游快照缺少来源元数据、线路与站点身份、连接证据和坐标基准，生产续接需要独立补齐这些证据。

**初期候选接收记录：** 上游 JSON 源已保存到 `railway-sources/local/china/crtrainroute/`，以 [候选接收清单](../../../railway-sources/china-crtrainroute.json) 跟踪固定版本、原始 CRS 声明、来源指纹与计数。[候选导入器](../../../app/scripts/railway/import-crtrainroute.py) 当时生成大陆 31 省级文件的 322,506 个轨道候选（其中 `rail` 298,224 个），按省级文件排除港澳 2,128 个轨道要素，并保留全部 3,404 个车站码。这些是初期候选计数，不是生产包覆盖或最终区域归属。

**当前生产范围：** CN 独占整条广深港高铁，包括香港段与香港西九龙 XJA；MO 独占澳门轻轨，包括横琴段；香港其余铁路留在 HK。三个数据集不共享这些线路或站点身份，不借跨区域图混接实现连续线路。生产续接采用独立获取、固定到 2026-10-17 的 Geofabrik 原始 OSM 拓扑，不把上游候选图升级为生产事实。已取得的官方身份、MTR 站序和 WGS84 证据见 [生产证据记录](china-production-evidence-20261018.md)；续接状态与产物引用见文末。

上游研究固定版本为 [`d75307df9c812abf1259b86b75202ba7b0048679`](https://github.com/Laide140/CRTrainRoute/commit/d75307df9c812abf1259b86b75202ba7b0048679)，提交时间 2026-10-18 17:46:47 +0800。初期研究依据源码审阅和 JSON 定向计数；没有启动上游服务、重建上游全国图、读取 pickle 对象或运行上游测试。候选导入器的聚焦测试结果见初期证据记录；独立原始 OSM 生产工作另见文末续接记录。

## 初期固定上游输入规模

直接解析该提交的 JSON 得到以下结果；坐标数是折线中的出现次数，不是去重节点数。

| 项目 | 本次计数 |
| --- | ---: |
| `data/geojson/*.geojson` | 33 个 |
| 全部要素 | 324,634 |
| `fclass=rail` 要素 | 298,960 |
| 被上游建图器排除的其他类型 | 25,674 |
| 全部坐标出现次数 | 2,401,153 |
| `rail` 坐标出现次数 | 2,037,776 |
| `station_names.json` 电报码/站名 | 3,404 |
| `stations.json` 坐标记录 | 2,879 |
| 有站名但无坐标的码 | 525 |
| 人工同址别名记录 | 6 |

33 个文件实际为 31 个大陆省级单位，加香港 `810000` 与澳门 `820000`，没有台湾文件；不能无差别合入已有港澳包。其他类型为 `subway` 20,957、`tram` 1,815、`narrow_gauge` 1,171、`light_rail` 954、`monorail` 663、`funicular` 68、`miniature_railway` 46。上游仅保留 `rail`，所以这也不是完整的中国客运轨道覆盖。

计数输入：[GeoJSON 目录](https://github.com/Laide140/CRTrainRoute/tree/d75307df9c812abf1259b86b75202ba7b0048679/data/geojson)、[站名表](https://github.com/Laide140/CRTrainRoute/blob/d75307df9c812abf1259b86b75202ba7b0048679/data/station_names.json)、[站点表](https://github.com/Laide140/CRTrainRoute/blob/d75307df9c812abf1259b86b75202ba7b0048679/data/stations.json)、[别名表](https://github.com/Laide140/CRTrainRoute/blob/d75307df9c812abf1259b86b75202ba7b0048679/data/station_lanes.json)。README 的“32 省”和部分坐标/节点规模不能代替固定输入的实际计数；本次没有独立核实 `rail_graph.pkl` 内的节点、边、连通分量数量。

## 算法实现及可复核问题

上游不是按实际列车服务算路：它对两站吸附点求几何最短路，再用邻近几何猜测途经站。下面的定位均固定到上述提交。

| 环节 | 实现与影响 | 源码 |
| --- | --- | --- |
| 建图 | 坐标按 `1e-6` 度量化，全局同坐标合并；相邻点双向连接，权重为大圆距离。仅看 `fclass=rail`，不以层级、线路、运营者或原始节点身份限制连接。相交折线若没有共享顶点，也不会自动建立正确道岔。 | [build_graph.py:48–121](https://github.com/Laide140/CRTrainRoute/blob/d75307df9c812abf1259b86b75202ba7b0048679/build_graph.py#L48-L121) |
| 骨架压缩 | 保留度数不为二和站点吸附节点，累计折线长度并保留中间几何。同端点的多条链折叠成一条，损失并行线路身份。若后来找到更短链，权重会更新，但 `edge_geom` 仅在键不存在时写入，因而可能仍保留先前链。 | [build_graph.py:184–250](https://github.com/Laide140/CRTrainRoute/blob/d75307df9c812abf1259b86b75202ba7b0048679/build_graph.py#L184-L250) |
| 断链补齐 | 含站且至少 20 个骨架节点的孤立分量，找距主网最近点对；60 km 内直接补边，低于 5 km 不标轮渡，其他标轮渡。没有核对真实轨道、桥梁、港口或运输服务。 | [build_graph.py:280–347](https://github.com/Laide140/CRTrainRoute/blob/d75307df9c812abf1259b86b75202ba7b0048679/build_graph.py#L280-L347) |
| 查询端点 | 强制吸附到最大连通分量，没有距离上限；超过 2 km 只警告。能够返回路径不构成该站已连接到正确铁路的证明。 | [server.py:276–311](https://github.com/Laide140/CRTrainRoute/blob/d75307df9c812abf1259b86b75202ba7b0048679/server.py#L276-L311)、[437–487](https://github.com/Laide140/CRTrainRoute/blob/d75307df9c812abf1259b86b75202ba7b0048679/server.py#L437-L487) |
| 最短路 | CSR 邻接数组、堆、稠密状态数组与到终点的大圆距离启发式，实为 A*，方法名仍叫 `dijkstra`。这能求该图的最短路，不能证明图中的连接真实或所选路线为某班列车路线。 | [server.py:206–242](https://github.com/Laide140/CRTrainRoute/blob/d75307df9c812abf1259b86b75202ba7b0048679/server.py#L206-L242)、[313–372](https://github.com/Laide140/CRTrainRoute/blob/d75307df9c812abf1259b86b75202ba7b0048679/server.py#L313-L372) |
| 途经站 | 站到折线距离不超过 800 m 即入选，不核对站台所在线路；里程取最近线段起点累计值，未加投影比例。六对人工别名只能修补已登记案例。 | [server.py:712–820](https://github.com/Laide140/CRTrainRoute/blob/d75307df9c812abf1259b86b75202ba7b0048679/server.py#L712-L820) |
| 缓存 | 缓存键只有吸附节点对，但途经站计算会按起终站电报码排除站点；不同站码吸附到同节点时可能复用不适用的站列表。 | [server.py:462–480](https://github.com/Laide140/CRTrainRoute/blob/d75307df9c812abf1259b86b75202ba7b0048679/server.py#L462-L480) |

反向几何需要准确区分：建图器把不含起点、含终点的链直接反转，反向链本身不满足同一存储约定；但运行时会跳过起点并补终点，因此**不能仅凭反转代码断言每条反向路径都错**。运行时又用“链首/尾哪个距起点更近”猜方向；弯曲折线端点靠近时，这个距离关系不保证等于拓扑顺序。缺少几何链时，代码实际使用空序列，没有按注释补出终点。以上是源码层面的风险/分支分析，没有测量当前成品图中受影响的具体路径数量。[几何恢复实现](https://github.com/Laide140/CRTrainRoute/blob/d75307df9c812abf1259b86b75202ba7b0048679/server.py#L657-L710)

“自动轮渡”已有明确反例：上游 README 将大陆—平潭的 15.10 km 补边列为轮渡，但平潭海峡公铁大桥铁路已于 2020-12-26 通车。[上游轮渡表](https://github.com/Laide140/CRTrainRoute/blob/d75307df9c812abf1259b86b75202ba7b0048679/README.md#L137-L145)、[国资委 2020-12-30 原始说明](https://wap.sasac.gov.cn/n4470048/n13461446/n16336544/n16336551/n16336599/c16355501/content.html)。缺失桥梁几何应补回有据可查的铁路，而不是被改成海上运输。

指定里程功能用整条已选路径边的六倍惩罚生成候选，再用局部避边路线替换区间；`reached` 容差是 5 km 与目标 5% 中较大者。它没有证明真实列车服务，也不保证全局最接近目标里程或拼接后没有重复访问。README 记载其曾放弃随机扰动、局部边惩罚、单独整路径惩罚；这些经验不应变成 Railmap 生产路线选择规则。[实现](https://github.com/Laide140/CRTrainRoute/blob/d75307df9c812abf1259b86b75202ba7b0048679/server.py#L522-L609)

## 坐标与来源元数据

上游明确称 OSM 为 WGS84、12306 站坐标为 GCJ02，并只在 AMap 绘图前转换线路。可是建图吸附、运行时端点吸附和途经站判断都直接比较这两组原始数字，没有在计算层统一基准。这与其自身声明不一致。**本次未从 12306 官方说明独立确定该端点的坐标基准**；不能把 README 的判断当作已确认事实，更不能直接把这些站坐标标为 WGS84。[坐标声明](https://github.com/Laide140/CRTrainRoute/blob/d75307df9c812abf1259b86b75202ba7b0048679/README.md#L244-L248)、[前端转换](https://github.com/Laide140/CRTrainRoute/blob/d75307df9c812abf1259b86b75202ba7b0048679/index.html#L418-L421)、[建图吸附](https://github.com/Laide140/CRTrainRoute/blob/d75307df9c812abf1259b86b75202ba7b0048679/build_graph.py#L168-L176)。

每个 GeoJSON 要素只有 `osm_id`、`code`、`fclass`、`name`、`layer`、`bridge`、`tunnel` 七个属性。`osm_id` 可保留为原始要素线索，但没有原始 OSM 节点 ID、关系成员身份及顺序。上游建图后连这些线索也不保留。几何经作者站点 `next.laide.net.cn` 下载，包内没有提取日期、OSM 版本或提取工具清单；固定 Git 提交只能固定本副本，不能恢复这些缺失事实。[下载实现](https://github.com/Laide140/CRTrainRoute/blob/d75307df9c812abf1259b86b75202ba7b0048679/download_geojson.py#L15-L48)

授权来源需要分开记录事实：代码附有作者 MIT 许可；OSM 数据来源应另记 ODbL 与署名；12306 站点接口和站名资源的来源已写明，但该仓库未附它们自己的授权说明。这是元数据未知项，不在此推定额外限制或将代码 MIT 扩张为所有第三方数据的授权。[MIT 文件](https://github.com/Laide140/CRTrainRoute/blob/d75307df9c812abf1259b86b75202ba7b0048679/LICENSE)、[OSM 官方版权/许可说明](https://www.openstreetmap.org/copyright)、[12306 坐标获取代码](https://github.com/Laide140/CRTrainRoute/blob/d75307df9c812abf1259b86b75202ba7b0048679/fetch_stations.py#L9-L29)、[数据来源表](https://github.com/Laide140/CRTrainRoute/blob/d75307df9c812abf1259b86b75202ba7b0048679/README.md#L176-L182)。

## 与当前 Railmap 的比较

| 维度 | CRTrainRoute | 当前 Railmap 与中国接入要求 |
| --- | --- | --- |
| 物理拓扑 | 全局同坐标合并；最近分量补边 | Swift/JS 按物理轨道身份分隔节点；跨身份以已审核连接证据成立，不能用站群或展示几何替代 |
| 端点 | 主连通分量最近点；远距警告 | 保留有界吸附、线路身份与已审连接约束；不能靠强制接主网解决缺口 |
| 线路/服务身份 | `fclass` 和邻近几何为主 | 线路、运营者、客运状态、站序、有效期分别有来源；班次和实际物理路径分开 |
| 数据基准 | 上游称 WGS84/GCJ02 混用 | 原始值与基准判断分开保留，确认后规范为共享层 WGS84；地图服务转换留在展示边界 |
| 搜索 | CSR + A*，单一终点 | 已有多源、多目标 Dijkstra、线路/运营者限制、日期与所需铁路状态；不能直接替换为上游单目标搜索 |
| 线路几何 | 压缩边保留折线；并行链折叠 | 压缩不得丢线路身份、分叉、平台锚点、边有效期或来源 |

本地实现依据：[RouteGraph.swift](../../../ios/RailKit/Sources/RailCore/Routing/RouteGraph.swift)、[RouteSolver.swift](../../../ios/RailKit/Sources/RailCore/Routing/RouteSolver.swift)、[JS 图构建](../../../app/public/app-route-graph.js)、[JS 求解](../../../app/public/app-route-solver.js)。

## 初期生产接入清单（当时完成源码核对，当前续接见文末）

不能只加一项国家选择器。与现有国家同标准的交付必须从同一模型生成
`app/public/rail/cn-2025.json`、`app/data/rail-sections-cn.json`、
`stations-cn.json`、`station-readings-cn.json` 和 `station-names-cn.json`，以及来源说明。
`compact-v1` 的站点必须按真实线路顺序排列，锚点与区间端点重合；线路必须具备
稳定身份、运营者、类型、名称/读音及有来源的显示属性。上游只有轨道碎片，不能自动填出这些字段。

| 层 | 需要同步接入的位置 |
| --- | --- |
| 原生区域与导入 | `RegionCatalog.swift`、`RailDisplayNetworkFormats.swift` 的 shippedRegions、RailCore 的 `Stations.swift`、`Train.swift`、`Localization.swift` 白名单 |
| 原生产品行为 | `RegionClock.swift` 的中国时区、`Statistics.swift` 的分类与日期、`StoreOperations.swift` 的空行程、`RideLibrary.swift` 与 `StatisticsFormatting.swift` 的穷举分支、`Localizable.xcstrings` |
| 展示坐标 | `AppleMapDatum.swift` 与 `AppleMapDatumProbe.swift`；保留按设备地图服务探测的机制，不能依据旧报告强制所有设备使用 GCJ02 |
| 资源链 | `ios/copy-rail-packages.sh`、`build-display-network.py`、`rail_resource_revisions.py`、站名构建器、`rail-database/load.mjs` 的国家表 |
| JavaScript 对应 | `app-config.js`、`app-validation.js`、`i18n.js`、`i18n-strings.js`、`index.html`、`app-store-ops.js`、`app-stats.js`、`app/shared/artifact-inputs.js` |

中国没有已审样例时不伪造样例；没有历史证据时不伪造 history 日期。
`physical-rail-junctions.json` 的新增连接必须有独立证据和真实端点；不能因同名、同址或展示直通而添加。

## 初期候选接收后的工作要求

1. 以固定提交接收完整候选资料，保留原文件、第三方来源和各自许可说明；不把 `rail_graph.pkl` 作为可信输入执行反序列化。
2. 补取原始 OSM **节点 ID、way 版本及有序节点链、relation 成员及顺序**，保留层级、轨距、服务/使用状态等可用标签，再按 Railmap 物理身份构建规则接入。
3. 建立有来源的官方车站身份与**线路归属、站序、运营者、客运状态及有效期**；将人工同址别名视为待核对记录，不因距离接近而合并身份。
4. 确认站点坐标基准，记录来源原值、判定证据和规范化过程；修复平潭等具体缺口时逐项提供真实轨道与服务证据。
5. 将断链保留为明确候选缺口；真实铁路轮渡单独建模。几何最短路、指定里程绕行和 800 m 邻近站列表均不得充当真实列车路线证据。

CSR、稠密搜索数组、受身份约束的度二压缩和地理 A* 都值得单独评估，但**尚未在 Railmap 上证明更快、更省内存或结果等价**。A* 尤其需要适配多目标启发式、所需铁路状态和当前提前停止规则。中国候选源接收不应顺带重写通用求解器；有具体性能问题时再用一个聚焦场景判断。

## 初期候选接收证据记录

范围：固定上游源码、JSON 输入、Swift/JS 图与搜索对应实现。结果：可完整保存为候选源；不具备直接发布生产中国物理路网所需的身份、来源与连接证据。计数来自 JSON 定向读取；没有把 README 的速度/准确度示例当作本地测量，没有运行全套检查或新增验证管线。剩余不确定性：12306 坐标基准、第三方数据各自授权说明、OSM 提取时间与原始身份、实际成品图中几何缺陷影响数量。

导入实施证据：`python3 -m unittest discover -s app/scripts/railway/tests -p test_crtrainroute_intake.py -v`
的 **8 个聚焦用例通过**。覆盖不同断链与同 OSM ID 碎片不合并、同址站码及别名不合并、港澳排除、
保留地铁/有轨电车、缺坐标与源坐标基准隔离、拒绝错误 CRS、保留 CRS84 声明、处理中断不写成功 manifest。
独立源码审查发现的 CRS 声明校验缺口已修正；实际输入声明 CRS84，重新接收结果保留该声明。
实际导入产生 31 个分省 JSONL 与一个车站 JSONL，合计 225,949,071 bytes；原始输入留在同一 source centre，
36 个 JSON 输入的指纹与 0 条合成连接记录在 manifest。此体积是候选存储量，不是运行时包大小。
没有新增自动检查入口、没有运行原生构建或求解器性能测试。

## 生产续接证据（2026-10-18）

用户已明确要求继续获取证据并完成生产 CN 接入，初期候选接收不是交付终点。
当前原始拓扑来自固定的 **Geofabrik China 2026-10-17 PBF**；
[提取器](../../../app/scripts/railway/extract-china-osm.py) 保留原始 node/way/relation ID、
对象版本、way 的有序 node ID、relation 成员及角色、标签与 WGS84 坐标。
本地 `railway-sources/local/china/osm/china-261017-rail.sqlite3` 已有完成提取的
source/counts/crs 元数据；不以全局坐标取整或视觉重合替代这些物理身份。

当前 12306 官方 3,404 条资源只提供名称、电报码和拼音身份；不采用上游 12306
坐标、不把未经证实的 GCJ02 数值标成 WGS84，也不需要反算其坐标来构建原始 OSM 网络。
MTR 官方旅客指南支持完整的七站广深港高铁顺序；QSQ 的当前名称为南沙北，
自 2025-10-11 起取代庆盛，XJA 全部留在 CN。官方原件、逐站身份及独立 OSM
坐标证据见 [China production evidence](china-production-evidence-20261018.md)。
该证据记录内的七站 Overpass 坐标快照为 2026-07-28，与生产 PBF 的 2026-10-17
来源日期分别保留，不混称为同一份快照。

其他线路的成员与顺序来自原始 OSM relation/轨道成员证据时，来源必须明确写为 OSM，
不能因为部分站名可匹配 12306 就称整条线的站序经过官方确认。缺少站轨归属、
真实连续轨道或乘客线路证据的区间继续作为未解决记录；不补直弦，不将同名站、
行人换乘或邻近几何视作轨道道岔。

生产审阅还纠正了两个具体来源解释问题：基础设施 `route=railway/tracks` 的站点
成员清单不等于旅客停站顺序，必须从该线路自己的原始轨道邻接推导；上下行站台
即使在远端相连，也不能过早压成一个全局连通分量的最近锚点。广深港七站改用
官方站序，并联合选择连续的原始站台轨道，消除了远端折返的绕行。

生产资料以 [CN 包来源说明](../../../app/public/rail/cn-2025.sources.md) 和
[生产源清单](../../../railway-sources/china-production.json) 为交付引用；这两项由生产集成步骤
生成并记录实际产物，本文不预填最终线路/车站/区间数量或构建成功结论。
当前进度见 [拥有范围的计划记录](../../superpowers/plans/2026-10-18-china-crtrainroute-intake.md)。

上游可借鉴的是：CSR 邻接布局、稠密查询状态、保留中间折线的度二压缩思路，以及
把数据获取和查询分开组织的接口。采用前仍须保留并行线路、站台锚点、分叉、来源与
有效期，A* 须适配已有多目标和状态限制。不能借用的启发式包括强吸附主连通分量、
60 km 自动补边/轮渡、800 m 即认定途经站、全局同坐标合并，以及按目标里程惩罚
搜索来代替实际列车路径。这是源码与约束比较，**不是已测得 Railmap 更快、更省内存
或全面更准确**。后续按用户要求新增的真实车次对照，单独记录在
[真实车次比较报告](china-real-train-paths-20261018/README.md)；其中运行结果、失败原因和性能限制不可用本段源码判断代替。

## 后续真实车次实测结果

后续已实际运行固定提交的原始图与服务逻辑，并对 88 个公开车次分别做起终点及全部停站对照；本节更新初期“尚未运行”的范围。图记录为 196,848 个节点、245,285 条无向边。坐标传输采用同一提交的原值快照，在线探测失败的限制仍保留。

去重且停站完整的 86 个服务中，原仓库完整候选为起终点 73/86、全部停站 47/86；修复后 Railmap 均为 12/86。强制停站返回几何区段为原仓库 717/971、Railmap 505/971，后者另有 40 条物理断点记录。原仓库起终点候选有 44 条至少偏离一个可参考停站超过 2 km；加入停站后降至 2 条，但同源 OSM 筛查不是独立实际轨道认证。

实测推动了哈尔滨原始连接、国铁站轨锚点和 71 处小站端点身份记录的具体修复。修复后的完整 176 项原生重放已完成，仍有大量待审阅和未解析项目。当前不支持整体优于原仓库的结论。方法、原始来源、失败案例、分母及当前 CSV 见[真实车次报告](china-real-train-paths-20261018/README.md)。


## 2026-10-19 真实车次证据修复与重放

四个逐站原始节点／关系绑定修复（WRQ、DOP、SAO、ENM）及小榄原始客运轨道边已正式合入。当前为3,991条路径、17,594区间、21,573站点成员、2,715官方代码。完整176项原生重放后，强制停站返回几何从522增至538/1,010，完整候选从12增至13/88；原始CRTrainRoute基线为756/1,010与49/88。534个共有输出部件坐标逐点不变，残余断点、错误来源与未证明区间继续显式保留，不宣称总体更优。详见[逐车次报告](china-real-train-paths-20261018/README.md)及[本轮结果核对](china-real-train-paths-20261018/topology-repair-result-review.json)。


### 2026-10-19：三处联络路径正式接入

通过既有 N02 物理区段契约接入六段原始路径（372 条相邻边、四个新增独立轨道身份），包括京沈联络线及京哈原身份引入段、昆明南联络线及单独命名的南昆—昆玉渡线、新会—江门及江海—江门东遗漏主线。未增加虚构客运站，既有站序和严格站轨源锚点不变。九个新增接点全部共享同一原始 OSM 节点；203 条其他地区接点保持一致。运营者、客运用途和原始关系成员证据见 [复核记录](china-real-train-paths-20261018/three-connectors-source-review.json)。昆明渡线运营者为明确标注的官方资料复核推断，不冒充源 way 标签或法律所有权。广州南尚无原始连续证据的跨站台路径继续拒绝接入。真实88车次重放结果以该目录 README 最新章节为准。

最终同批88车次×两模式重放于2026-10-19T07:44:15Z完成：完整候选13→14/88，强制停站返回几何538→542/1,010；原仓库仍为49/88与756/1,010。C293已完整，G101与G6045虽返回全部区段几何，仍分别保留沈阳北、广州南站台边界断点。源身份显示与CN缓存修复消除昆明地铁误标；551个旧源几何部件坐标完全保留。0结构失败、704项审阅不等于全部路径认证。聚焦回归及最终独立输出复核通过，串行窗口已归还。详见[最终报告](china-real-train-paths-20261018/README.md)。


### 2026-10-19：平台边界继续取证与 D271 正式补齐

新增八段有原始关系、逐边版本及运营者／客运用途证据的物理补段和三个真实站点绑定，保留全部旧站点及紧凑客运库；原始补充路径现为14段／2414相邻边。D271达到14/14段几何、13/14内部连续（原仓库9/14），D239为6/7几何、5/7内部连续（原仓库3/7）；攀枝花南缺证边界仍保留。广通北自身客运way前三边已正式接回。广州南、沈阳北缺证连接没有降低标准接入；沈阳北扩展追查在哈牡线遇到无原始关系成员归属的way，也未用新契约绕过。

最终同批176项于2026-10-19T08:50:40Z完成，强制停站几何542→552/1010、内部499→507、完整候选14/88不变；原仓库仍756/1010与49/88。0结构失败、714项审阅。旧556部件零丢失，554坐标数组完全一致，另两部件仅增加原始前缀／同节点重复点、保留全部旧坐标。21项聚焦回归及独立实际输出复核通过，运行窗口已归还。局部覆盖改善不构成总体更优结论。详见[最终结果与源证据](china-real-train-paths-20261018/README.md)。
