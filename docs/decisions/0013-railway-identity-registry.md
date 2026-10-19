# 0013: 铁路身份注册表 —— 公司 / 线路 / 车站的统一重构方案

- Status: Proposed（尚未实施；本文不构成提交、推送或发布的授权）
- Date: 2026-10-19（同日按 [重构准备与交接](../reference/railway-data-overhaul-preparation.md) 修订）
- Decision owners: Project maintainers
- Extends: 0004 (WGS84/MapKit 边界), 0008 (display identity tables), 0010 (station code grammar), 0011 (dated history), 0012 (fail-closed resolution)
- Constraints: `ios/AGENTS.md`（North America 已退役；物理拓扑不由邻近、同名、换乘站群或直通显示关系建立）、`ios/VERIFICATION.md`、[重构准备与交接](../reference/railway-data-overhaul-preparation.md)

> 修改 §8 中已定的 id 形式或账本格式，必须更新本 ADR 的状态与理由，不得在其他文档里静默换方案。

## 1. 现状（`app/data/rail.db` schema v3 的调查快照，2026-10-19）

以下数字是对 `rail.db` 的一次只读查询，**不是运行时资源的普查**，不能外推为所有包、chunk 或缓存的当前数量。
`rail.db` 汇总 6 个地区（JP/TW/HK/KR/MO/CN）：425 个 operator、4796 条 line、24961 个 station、34191 个 line_station。
对照：JP compact-v1 `2025.5.2` 本身只有 658 个 line id（与排序输入的 658 个唯一 id 集合相同，排序输入含 9580 个区间）；
4796 是六地区合计且含 CN 的 relation 级行。集合相等不等于全部铁路、区间或站台已验收（准备文档 L14）。

问题不在“有没有数据”，而在“身份是怎么定义的”：

| # | 问题 | 证据 |
|---|---|---|
| 1 | **`station` 实为换乘站群，不是某公司的车站。** JP 的 `station.code` 是 N02 group code，一行跨多家公司。 | `003700 新宿` 一行包含 京王・小田急・東京メトロ・都営・JR東日本，`source_station` 里有 11 行、6 个不同的 N02 站码。JP 站码 10154 个 vs group 9046 个；KR 1400 vs 1097。 |
| 2 | **公司层面的车站没有实体。** “JR 新宿”与“京王 新宿”只存在于 `source_station`（原始导入行）和乘车记录的 `n02_station_code` 里。 | 乘车记录 stop 只存 `name` + `n02_station_code`；`company` 是自由文本（`"JR西日本"`），不指向 `operator.id`。 |
| 3 | **同名不同站靠名字查会歧义。** | 同一地区同名不同站：JP 425 组、CN 1275 组、HK 38 组、TW 14 组，共 1752 组（府中 ×4：京王 / JR西日本 / JR四国 / 丹後海陸）。`station_name` 有 10.2 万行以裸站名 (`key_type='name'`) 为键。 |
| 4 | **线路 id 由可变名字拼成，并混入绘图分段。** | `jp-東海旅客鉄道-東海道線-2-p1`：公司全名 + 线名 + 序号 + 绘图 part。公司改名或线路转让（如 2002 IGR）即改 id。名字拼接 id、绘图 `-pN` 与物理身份之间的关系目前没有显式映射。 |
| 5 | **同名线路跨公司。** | 28 个线名被多家公司使用；`本線` ×11 家、`東海道線` 7 行分属 JR东/东海/西 及其分段。 |
| 6 | **`railway_identity` 语义过载。** | 4796 线只有 595 个 identity，有的是“同一铁路”，有的是运行系统（`jp-jr-east-ueno-tokyo-through`）。 |
| 7 | **CN 的“线路”是 OSM 方向/分支 relation。** | `cn-osm-relation-1667139-branch-2…9` 全叫 `地铁 1号线/八通线: 环球度假区 → 苹果园`；方向分支不自动是独立铁路。 |
| 8 | **历史与身份变更靠 名字 + bbox 匹配。** | `rail-history.json` 的 `retirements` / `identity_periods` 用 `{line_name, operator, bbox}` 定位要素，改名即失配。 |
| 9 | **名称表多套并行。** | `station_name`(3 种 key_type)、`line_station_name`、`station_english`、`station_english_jp`、`line_station_english`、`line_name` 视图。 |
| 10 | **数组序号承载含义。** | 修复脚本、区间、part、follow、evidence candidate 都用索引；稳定实体 id 不能隐式改变这些序列语义（准备文档 L58）。 |

North America (us/ca) **已退役**（`ios/AGENTS.md`）：不打包、不载入、不迁移、不提供兼容；`backups/north-america/` 只是离线证据。本 ADR 不覆盖 NA。

## 2. 目标

1. 收录 JP/TW/HK/MO/KR/CN 的全部铁路（JR/私铁/第三セクター/地铁/路面/单轨/缆车/新交通/BRT 转换、已废止线路），一个身份模型。
2. **公司、线路、车站各有不依赖名字的稳定 id**，改名、转让、合并、拆分都不改 id。
3. 同名车站、同名线路在数据层永远可区分，UI 层能自动生成不歧义的显示名。
4. 所有外部编码（N02、TDX、MTR、OSM、駅ナンバリング 等）只作为交叉引用，不作为主键。
5. 时间维度（开业、废止、改名、转让）统一用 0011 的半开区间 `[valid_from, valid_to)`，日期必须有来源。
6. 已保存的乘车记录始终可读（0010 的 alias 原则）。
7. **注册表只管身份。** 几何、测量尺、显示派生、服务状态、历史事实、诊断/审阅证据继续由各自现有 owner 持有（§3.8–3.10）。

## 3. 目标模型

### 3.1 实体

```
operator ──< line_operation >── line ──< line_part ──< line_stop >── station ──> station_facility? ──> station_complex
   │  └──< station_operator >────────────────────────────────────────┘ (多公司多角色)
   └─ operator_name (dated)     ├─ route_pattern (方向/支线/运行系统/直通)
                                └─ line_name (dated)
station ──< station_link >── station   (同站群内的乘客换乘信息，不是物理连接)
```

| 实体 | 含义 | 例 | 现有来源 |
|---|---|---|---|
| `operator` | 法人/运营主体 | JR東日本、京王電鉄、東京都交通局 | `operator`（name 唯一 → 改为 id） |
| `line` | 官方/法定的一条线路（路線） | JR東日本 東海道線 | **只由显式 crosswalk 决定**哪些 `line_part` 属于同一 line（§9.3-2）；同名、去后缀相同只产生报告，不自动合并 |
| `line_part` | 一个现有 package line id 的身份（1:1），保留它在包中的 id、区间序号与 part 含义 | `jp-東海旅客鉄道-東海道線-2-p1` | 现有 package line（含 `-N`、`-pN`）；P0–P3 **不在包里收拢**，如确需收拢只能在 P5 由网站仓库的包构建器完成，并经 index-space map 映射 |
| `route_pattern` | 方向、支线、运行系统、直通 | 上野東京ライン、八通线 环球度假区→苹果园 | CN OSM relation、`railway_identity` 的运行系统部分、through-service catalog |
| `station_complex` | 换乘站群（同名或相连的所有公司车站） | 新宿、押上 | N02 group code、TDX 站群、HK/MO group |
| `station_facility` | 多家公司**共用**的同一个实体车站（共用站台/检票口），可选，只在有来源的人工审定后存在 | 押上（京成・都営）、目黒（東急・メトロ・都営） | P0 只出候选报告（§9.5）；距离或共用代码只作线索 |
| `station` | **某公司的一个车站**（乘车记录引用的层级），一家公司在一个站群里通常只有一个，可挂多条线 | JR東日本 新宿（山手線・中央線…）、京王 新宿 | 由 (group_code, operator) 派生 + 审定后的覆写表 |
| `line_stop` | 车站在某个 `line_part` 上的停靠点（包内序号） | 中央線 新宿 (003693) | `line_station` + `source_station` 的 N02 站码 |

不在注册表里的东西（各有现有 owner，见 §3.8）：原始物理轨道边、站点焊接后的区间、显示 part / lane / follow / family、乘降面（站台面、进出站方向）。
`station` 与 `station_complex` 是**身份分组**，不证明共用股道、站台端点或物理连接；乘降面不从站群派生（准备文档 L22、L25）。

关键变化：**今天的 `station` 降为 `station_complex`，在它和 `line_stop` 之间插入真正的“公司车站”层。**

### 3.2 稳定 id

- 形如 `{kind}:{region}:{seq}`，例如 `op:jp:42`、`ln:jp:1234`、`lp:jp:412`、`st:jp:5871`、`cx:jp:3700`、`fc:jp:12`（不透明序号，已定）。
  `seq` 由注册表一次性分配、**永不重用、永不从名字推导**，序号本身不携带任何含义（`cx:jp:3700` 与 N02 group `003700` 无关）。
- **一个不透明序号只表示一个实体身份**，不能兼任区间序号、顶点序号、part 索引、测量尺位置、native chain 或采集 `pointOrdinal`（§3.8）。
- `rail.db` 是每次从零重建的派生物，app 也不读它，所以 id 不能只活在 `rail.db` 里：
  分配结果保存在入库的**只追加 JSON Lines 账本** `app/data/registry/{region}/*.jsonl`（已定，见 §9.2），构建器读账本、
  只为新实体追加新行，已写入的行永不改变；只追加由校验器对照基线版本强制。
- 另带一个仅供人读的 `slug`（`jr-east/tokaido`），可变、不做键。
- 旧 id 通过 crosswalk 映射：`jp-東海旅客鉄道-東海道線-2-p1` → `lp:jp:…`（1:1）→ 经审定的 `ln:jp:…`；N02 站码 `007958` → `line_stop` / `station`。
  合并与拆分走 alias（一对多拆分要求按日期或线路消歧，否则 fail closed，见 0012）。

### 3.3 交叉引用表（覆盖“所有铁路”的关键）

```sql
external_ref(entity_id, scheme, value, valid_from, valid_to, source)   -- 实体种类由 id 前缀给出
-- scheme: n02-station | n02-group | package-line | tdx | mtr | mlm | kric | osm-relation
--         | osm-way | osm-node | eki-numbering | wikidata | legacy-station-code
UNIQUE(scheme, value, valid_from)
```

每个地区的导入器只做一件事：**把源记录映射到注册表 id**；未映射的源记录在校验里报错而不是静默丢弃
（现在 `source_station.station_id IS NULL` 有 JP 6 行、TW 2 行就是这种情况）。
审阅编号（如 CN `source_review_id`）是 provenance，不是源身份，不进 `external_ref` 的身份 scheme（准备文档 L26、L92）。

### 3.4 时间维度

身份类表都带 `valid_from / valid_to`：

- `operator_name`（社名变更）、`line_operation(line_id, operator_id, role, valid_from, valid_to)`（转让、第二种/第三种事业者）、
  `line_name`、`station_name_period`、`line_stop`（开业/废站/移设）。
- **日期只来自有来源的事件**（0011：N02 版本差异只提名候选，事件才确认日期）；不补造开通日期，缺失就保持无界或进报告。
- `line_stop` 的有效期只表示“这个停靠点存在”，不表示服务状态：停运、`substitute_bus`、区间停驶仍由 §3.9 的 owner 持有。
- `rail-history.json` 的 `retirements` / `identity_periods` 改为直接引用 id，不再用 `line_name + operator + bbox`；半开区间规则不变。
- 路由仍按 0011：日期为 `d` 的乘车只能用有效区间包含 `d` 的边与站。

### 3.5 名称统一为一张表

```sql
name(entity_kind, entity_id, lang, form, value, valid_from, valid_to, source, status)
-- lang: ja | zh-Hant | zh-Hans | ko | en ...   form: official | kana | romaji | short | alias
```

替代 `station_name`、`line_station_name`、`station_english*`、`line_station_english`、`line_name` 视图；
`translation_may_be_wrong` 由 `status` 派生成视图列。裸名查询只返回候选集合。

### 3.6 同名消歧规则（数据层 + 显示层）

数据层：身份只认 id，相似或同名永不合并（沿用 0008）。

显示层：统一使用 `站名 (CC, 线路标签)`，括号部分在界面上以小字显示（规则见 §11.5）。
线路标签在国家内唯一：线名唯一时用线名，否则用公司限定名（`本線` → `京成本線` / `阪神本線`）。
预计算 `homonym_group` 供搜索与导入使用；导入遇到多个候选时按 §11.3 依次筛选，仍不唯一则拒绝（0012）。

### 3.7 一个车站对应多家公司、多条线路

现实中“一个车站”常常同时属于多家公司、多条线路。`rail.db` 快照（按站群统计）：

| 地区 | 站群 | 多公司站群 | ≥3 家公司 | 单站群最多公司 / 线路 | 挂多条铁路的公司车站 |
|---|---|---|---|---|---|
| JP | 9042 | 398 | 54 | 6 / 8 | 549（最多 5 条） |
| KR | 1097 | 151 | 20 | 5 / 6 | 118 |
| TW | 505 | 30 | 5 | 4 / 5 | 40 |
| HK | 282 | 0 | 0 | 1 / 7 | 94 |
| CN | 14065 | 698 | 31 | 4 / 18 | 5000（OSM 变体虚高，P3 重测） |

模型把这几种关系分开表达，不再塞进一个 `station` 行：

| 情形 | 例 | 表达方式 |
|---|---|---|
| 一个站群里有多家公司的车站 | 新宿：JR東日本・京王・小田急・メトロ・都営 | 一个 `station_complex`，每家公司一个 `station` |
| 一家公司的车站挂多条线路 | JR 新宿：山手線・中央線・埼京線…；都営 新宿：新宿線・大江戸線 | 一个 `station`，多条 `line_stop` |
| 多家公司共用同一实体车站（共同使用駅） | 押上（京成・都営共用；メトロ・東武共用）、目黒、中目黒、代々木上原 | 每家公司仍各有 `station`（各自站码、駅ナンバリング `KS45`/`A20`/`Z14`/`TS03`、运价、站名写法）；共用关系在有来源审定后由 `station_facility` 表达，记 `manager` |
| 公司边界站 | 熱海（JR東日本 / JR東海）、米原（JR東海 / JR西日本） | 两个 `station`；审定后可共属一个 `station_facility` |
| 第二种 / 第三种事业 | 成田空港（京成・JR東日本列车；成田空港高速鉄道 持有设施） | `station_operator` 角色：`owner`（站的身份归属）、`manager`、`facility_owner`；线路层面用 `line_operation` |
| 直通运转：他社列车停靠本社车站 | 小田急列车经 代々木上原 进入 千代田線 | 不复制 `line_stop`；`route_pattern` 引用各段所属公司的 `line_stop`；直通显示/时刻表延续不建立物理连接 |
| 同站群内的换乘关系 | 改札内换乘、出站换乘、步行连络 | `station_link(a, b, kind, walk_m?)`，`kind ∈ {same_facility, gate_transfer, street_transfer}`；只是乘客换乘信息 |
| 同一实体车站各公司站名写法不同 | 押上〈スカイツリー前〉（京成・都営） vs 押上（メトロ・東武） | 名称挂在各 `station` 上；`station_complex` 另有代表名；解析时任一写法都匹配 |

表结构：

```sql
station_operator(station_id, operator_id, role, valid_from, valid_to)   -- role: owner | manager | facility_owner
station_facility(id, complex_id, manager_operator_id, source, valid_from, valid_to)
station.facility_id  -- 可空；同一 facility 的 station 必须属于同一 complex
station_link(a_station_id, b_station_id, kind, walk_m, source, valid_from, valid_to)
```

边界（`ios/AGENTS.md`、准备文档 L22–25、L73）：

- `station_facility` 与 `station_link` **只能由有来源的人工审定**产生；点位距离、共用 N02 代码、同一站群都只进候选报告，不直接铸造。
- 它们不是物理拓扑边、不是乘降面，也不是双向客运关系；路线求解不把它们当作轨道连接。
- 加入或改变 facility 分组不改变已铸造的 `st` id。

`station` 的身份是“一个公司 × 一个站群”：与源数据粒度一致（N02 按公司路线给站码），乘车记录引用它时公司语义明确。

公司与线路：

- `line_operation` 的 `role`：`operator`（第一种）、`track_owner`（第三种）、`service_operator`（第二种）。
  例：成田スカイアクセス線の京成（第二种）与成田高速鉄道アクセス（第三种）。
- 乘车记录的 `company` 自由文本解析到 `operator_id`；`operator_alias` 扩充为带地区和有效期的别名表。

### 3.8 坐标阶段、测量尺与索引空间（注册表不接管）

注册表 id 只是身份。以下阶段各有现有 owner，迁移只能**显式映射**，不能合并成一个“轨道几何”实体（准备文档 L25–27、L106–118、L150–153）：

| 阶段 | 现有 owner | 规则 |
|---|---|---|
| 原始源证据（N02 / OSM way/node / 官方 polyline） | 源数据及其版本 | 保留自己的身份；审阅编号不能替代 |
| 站点焊接后的物理区间 | `CompactPackage.decodeIntervals`、`rail-network.js decodeIntervals`、`build-display-network.py decoded_intervals` | 是焊接后的输入，不等于未处理的原始 N02；**源公里（`distanceKm`）是权威里程**，显示几何长度不得替代 |
| 显式显示区间/站点坐标 | `decodeDisplayIntervals`、`displayStationCoordinates` | 只影响绘制 |
| 本线显示 part | JS `displayPartsForLine`、Swift `DisplayParts` | 派生；`LineTopology` 的 `reversalTails`、`extraSegments` 在任何 schema 合并中必须保留 |
| lane / follow / family / hub / chain | `build-display-lanes.mjs`、`display-lanes.json` | 派生的测量合同；follow 是 lineKey + chain + ruler，不是物理关系 |
| 编译后的 native 显示 | `build-display-network.py`（唯一再生成者） | manifest、per-line catalog、blob、joins、资源 revision 是一次构建的一组产物 |
| 平滑 / MapKit 输出 | 渲染层（0004） | MapKit 调整后的坐标永远不成为物理源 |

索引空间各自独立，迁移前先发布映射（P0 交付，§9.1）：

| 索引空间 | 例 | 映射到 |
|---|---|---|
| 稳定实体 id | `lp:jp:412`、`st:jp:5871` | 注册表 |
| 包 line id + 区间序号 / 区间代码 | `jp-…-中央線` 第 37 区间 | `lp` + `line_stop` 范围 |
| 原始 / 显示顶点序号 | interval_vertex seq | 不映射到注册表；保持在几何 owner |
| 显示 part 索引 + 米制测量尺 | `display-lanes.json` 行 | 不映射；修复时更新依赖行（包括作为他线 follow leader 的线） |
| native chain | display chunk | 不映射 |
| 采集 `pointOrdinal` | `BatchInspectionPlan` | 属于不可变 identity plan，不重排、不复用 |

测量尺：原始 N02/源测量尺、display/groomed 测量尺、序列化后的测量尺都有实际消费者，不得混用；
北松江自跟随后缀只 rebase 源区间，target part1 的 150→0 不变——测量尺合同不得用统一四舍五入或全局 mapper 代替；另外，共享几何的精确 support 度量不得降为一位小数（准备文档 L59）。

### 3.9 服务状态与历史的归属（注册表不接管）

| 事实 | 现有 owner | 规则 |
|---|---|---|
| 地图停驶区间 | compact `serviceSpans` `[firstStation,lastStation,code]`，JS `serviceSplitForLine` / `drawsContinuousStroke` | 含 `substitute_bus`；Swift `CompactPackage.Line` 目前不解码 `serviceSpans`，不得因此把它“规范化”掉 |
| 进不进描边模型 | `build-display-lanes.mjs` 产出的 `strokeExcludedByRegion`，编译器显式读取 | 不另造第二条服务状态规则；无连续描边不等于 Main 普通区间不可见 |
| 有日期的列车种别/车次及来源 | `LineServiceCatalog` | 不是 compact 停驶区间的替代 |
| 年代/有效期/历史叠加 | `RailHistoryOverlay`、`RailHistoryStations`、`RailDisplayHistoryFile`、`build_region_history` | P2 只把定位方式从“名字 + bbox”改为 id 引用 |
| 直通 / 时刻表延续 | `JapanThroughServices`、through-service catalog | 不建立物理连接 |

保护样例：夷隅的 `substitute_bus` 状态与 Main 普通区间绘制保持不变，不凭 continuous part 数推断可见性。

### 3.10 诊断与审阅身份（不进注册表）

- 诊断与审阅身份保持现状：`DiagnosticRequest` / `DiagnosticSession`、`BatchInspectionIdentity`（冻结 IEEE bitPattern）、
  `identity-plan-<digest>.json`、`pointOrdinal`、`evidenceSHA256`。
- 采集完成、人工/agent 图像审阅、来源归属、候选 native 像素、Main 最终合成是**不同状态**，新 schema 不得合成一个“passed”。
- provenance 与可变审阅状态分开；已 apply 的证据补充 Main 结果时写后续 metadata，不改顶层状态。
- 已收敛的六项诊断简化保持现状、不重做（准备文档 L54）：移除第二条路线启动旁路；精确范围只准入一次；完成统计由 capture owner 提供；进度写状态而非反复写完整证据；只绘制/编码请求的 PNG；through 摘要在持有文档的 actor 内计算。
  同时不恢复三款活动诊断 App、另一套截图算法、后台 watcher 或自动全国 runner。
- 完成截图或测试通过不能代替地理归属、平台中心或最终组合像素验收（准备文档 L29）。
- P5 若要把诊断里引用的 line/station id 改为注册表 id，只能在保持上述分离的前提下 rekey，旧 identity plan 与 receipts 不重写。

## 4. 地区映射

| 地区 | complex | station | line_stop | line | route_pattern |
|---|---|---|---|---|---|
| JP | N02 group | (group, operator) + 审定覆写 | N02 站码 | 显式 crosswalk 把 `lp` 归入 `ln`（同名去后缀只是候选） | through-service catalog、上野東京ライン 等 |
| TW | TDX 站群 | `OP-ID`（0010 语法） | 站 × 线 | TDX route | 支线/区间车 |
| HK/MO | group | `MTR-ADM` / `MLM-X` | 站 × 线 | 线 | 东铁马场支线、电车 6 条服务 |
| KR | group | 站码（1400） | 站 × 线 | 线 | 急行/普通 |
| CN | OSM `public_transport=stop_area`（候选） | stop_area × operator | relation 中的 stop | `network + ref + operator` 只作**候选归并键**，逐项审阅 | 每个 OSM 方向/分支 relation |

CN（P3，单独项目）的边界（准备文档 L24、L26、L75、L92–93）：

- 保留原始 way/node 与源 id；设施线路与 route pattern 分开。
- 源铁路不能被最近的地铁显示身份或 `source_review_id` 替换；地铁误标进报告。
- 返回几何、显示匹配、整车完整、客运认证是四个独立判断，不合成一个布尔值。
- 广州南（GZS）/ 沈阳北（SBT）/ 攀枝花南（PNE）的返回部件与楚雄—丽江的真实连接缺证分别迁移、保持显式未决；不得由公司站群或近邻节点补边。

## 5. 迁移阶段（每期只有一个写入 owner，可单独交付、可回退）

兼容读取若有必要，集中在现有导入/解码 interface（`StationCodeAliases`、`JourneyCompletion`、`CompactPackage`），不让所有调用方同时理解两套身份。

| 阶段 | 内容 | 本期不改变 | 结束条件 |
|---|---|---|---|
| 0 冻结迁移输入 | 列出当前 schema、旧 id、外部引用、各事实 owner（§3.8–3.10）、已有修复 authority、已否决候选与例外清单 | 不改几何和历史事实；不重跑全国基线 | 读写链与已知坏例子（§9.6 保护样例）逐项可定位；**完成前不铸造** |
| P0 身份账本 | 只追加账本、唯一 mint 入口、只读 builder、旧身份 crosswalk、索引空间映射、例外与同名报告（§9） | app、compact 包、display-network、乘车记录不切换；CN 不归并 | 唯一性、只追加、retire/alias、歧义拒绝、重跑稳定 |
| P1 公司车站与记录引用 | 经现有 alias/import 路径解析旧记录，按公司车站层写新引用；审定后的 station 覆写、line crosswalk、facility | 不在包里收拢 `-N`/`-pN`；不从站群制造乘降面或换乘物理边；不猜缺失身份 | 旧记录可读且无歧义升级；新记录往返稳定；已知同名异站不误合并 |
| P1b 导入语法与小字标签 | §11 | 不阻塞 P1 的身份迁移 | 见 §11.6 |
| P2 历史改键 | 有效期与改名/运营者关系按 id 引用；路由缓存 key 的 overlay revision 随之升级 | 不补造开通日期；半开区间规则不变 | 已知日期边界与旧记录解析结果保留 |
| P3 CN 单独归并 | §4 CN 边界 | 不合成单一布尔 | 固定车次逐项差异可解释，GZS/SBT/PNE 等未证边界仍显式存在 |
| P4 | **排除**：NA 已退役（`ios/AGENTS.md`），不实施 | — | — |
| P5 下游切换 | Swift/JS、现有 builders（`build-display-lanes.mjs`、`build-display-network.py`）、chunks、history、cached routes、诊断引用切到注册表 id | 不新增第二套长期 writer / renderer / 求解器 / 显示编译器 | manifest、catalog、blob、joins、资源 revision 同步更新；受影响字段可追踪映射；临时兼容有移除条件 |

## 6. 不变量（校验器分期断言）

各条从哪一期开始由校验器强制：1–5、8、11 自 P0；6 自 P2；7 对 JP/HK/MO/KR 自 P0 报告、P1 起强制，TW 在 P1 修正两处后强制，CN 在 P3 后强制；9、10 自 P0 起作为输入/输出约束（不读、不产出违规数据）。


1. id 一经分配永不复用、永不改变含义；名字变更只改 `name` 行。
2. 每个 `line_stop` 恰属一个 `station`、一个 `line_part`；每个 `station` 恰有一个 `owner` 角色的 operator（可另有 `manager` 等角色），恰属一个 `station_complex`、至多一个 `station_facility`；同一 facility 的各 station 属于同一 complex 且 owner 互不相同。
3. 每条外部源记录恰好映射一个注册表实体，或出现在显式的 `excluded_source` 中并写明原因。
4. 同一 `(scheme, value)` 在同一时刻只指向一个实体。
5. 任何旧 id / 旧站码都能经 alias 解析；无法唯一解析时拒绝，而不是取第一个。
6. 有效期区间不重叠（同一实体同一属性）；日期都有来源。
7. 同一国家内，`(站名, 线路标签)` 至多指向一个站群（§11.4）；线路标签在国家内唯一；等于受支持国家代码的线路别名/记号（P0 实测：東京モノレール `line_code = MO`）不作为单独括号元素解析，只能用 `(CC, 线名)` 两元素形式。
8. 一个整数只属于一个索引空间（§3.8）；注册表序号不兼任区间、顶点、part、测量尺、chain 或 `pointOrdinal`。
9. `station_complex`、`station_facility`、`station_link`、`route_pattern`、follow / family 都不产生物理拓扑边。
10. 已否决候选（宫福、布崎、西野尻 等）永不成为 accepted repair、默认数据或自动兜底；同一 authority 下已接受的修复不被后续 export 覆盖。
11. 注册表输入只有 compact 包、站点表、名称表、历史叠加与审定覆写；不读修复候选目录、显示派生或 MapKit 输出。

## 7. 范围与仓库边界

- 本仓库可做：`rail.db` 构建脚本与校验（`app/scripts/build/build-rail-database.mjs`）、RailKit 读取层与 alias、乘车记录迁移、`app/data/` 内 iOS 打包的数据。
- **compact-v1 包（jp/tw/hk/mo/kr/cn）的构建器在网站仓库 `Japan-Train-Map`。** P3、P5 若要求包本身输出新 id，需要在那边另立任务；本仓库在 P0–P2 只在 `rail.db` 层叠加注册表，不改包。
- 现有 builders 是唯一实现：`build-display-lanes.mjs`、`build-display-network.py` 继续是显示派生的唯一再生成者；不新建第二个迁移 runner 或通用验证框架。
- NA 已退役，不在范围内。
- `rail.db` 目前是纯派生的查询库（`build-rail-database.mjs` 头注释：“Nothing in the app reads the database”）。
  app 运行时读的是 compact-v1 包、`stations*.json`、display-network chunks 与名称表。因此 P0 不影响 app；
  P1 起乘车记录要引用新 id，就必须同时向 app 打包一份精简的身份表（§10）。

## 8. 已定事项（2026-10-19）

| # | 问题 | 决定 |
|---|---|---|
| 1 | id 形式 | **不透明序号**；slug 仅供人读，不做键。 |
| 2 | 乘车记录引用层级 | **公司车站 `station`**；`line_stop` 仍由 stop 的 `n02_station_code` 等原码经 `external_ref` 推出，不入乘车记录主键。 |
| 3 | CN | **本轮不做**，P0 仅为 CN 铸造与现状一一对应的 id（relation 级），归并留给单独的 P3 项目。 |
| 4 | `station` 派生例外 | **先出报告，不先覆写**；P0 只产出例外清单，覆写表在 P1 按清单人工审定后再填。 |
| 5 | 账本格式 | **JSON Lines**，按地区 × 实体种类分文件，规范化序列化，行不可变（§9.2）。曾考虑 SQLite：触发器强制更强，但二进制不可 diff、不可合并，且本仓库位于 iCloud 同步目录，二进制冲突副本无法调和。 |
| 6 | NA | **排除**（`ios/AGENTS.md`）。 |
| 7 | `line` 归并 | **只按显式 crosswalk**；同名/去后缀只出报告。 |

仍待决：

- P1 的乘车记录 schema 升级是否与下一次导出格式版本（1.3 之后）合并发布？

## 9. P0 详细计划 —— 注册表与账本（不改 app、不改包）

前置：阶段 0 的冻结清单已完成（§5）。

### 9.1 交付物

| 文件 | 内容 |
|---|---|
| `app/data/registry/{region}/*.jsonl`、`runs.jsonl` | 只追加账本，格式见 §9.2 |
| `.gitattributes` 一行 | `app/data/registry/**/*.jsonl text eol=lf merge=union` |
| `app/data/registry/{region}/line-crosswalk.json`（`{"schema":"jtm-line-crosswalk/1","groups":[…]}`） | 人工审定的 `lp` → `ln` 归属（首次为空；P0 只生成 `line-family-candidate` 报告供审定） |
| `app/data/registry/{region}/index-space-map.json` | 旧 package line id → `lp`、(line id, 区间序号) → `line_stop` 范围；其余索引空间按 §3.8 标为“不映射，留在原 owner”。**任何消费者切换前发布** |
| `app/data/registry/{region}/station-derivation-exceptions.json` | P0 生成的例外报告（只读产物，P1 审定后另存覆写表） |
| `app/data/registry/{region}/excluded-source.json` | 不变量 3 的显式排除清单（人工维护，每条带原因与来源） |
| `app/data/registry/{region}/homonyms.json` | 同名车站组、同名线路组及其自动生成的消歧显示名 |
| `app/scripts/build/rail-database/registry.mjs` | 账本读写（规范化序列化）+ 铸造 + 校验，被 `load.mjs` 调用 |
| `app/scripts/build/mint-registry.mjs` | 唯一允许写账本的入口（`--dry-run` 只出变更摘要）；`build-rail-database.mjs` 只读账本 |
| `app/scripts/build/rail-database/schema.sql` | 新增注册表相关表（§9.4），`meta.schema_version` 3 → 4 |
| `app/scripts/railway/validate-registry.mjs` | §6 不变量的独立校验器 |

不新增 Swift 代码，不改 `stations*.json`、compact-v1 包、display-network、`display-lanes.json`、历史叠加、乘车记录。

### 9.2 账本格式（JSON Lines，规范化序列化）

**目录布局**——按地区、按实体种类分文件，缩小单文件体积与合并冲突面，CN 与其余地区互不干扰：

```
app/data/registry/
  runs.jsonl                      # 每次铸造运行一行
  jp/  op.jsonl ln.jsonl lp.jsonl cx.jsonl st.jsonl ls.jsonl     # 实体（P1 起加 rp.jsonl、fc.jsonl）
       op.ref.jsonl … ls.ref.jsonl                               # 外部编码，与实体同种分文件
       alias.jsonl  events.jsonl
  tw/ hk/ mo/ kr/ cn/  （同上）
```

**核心原则：每一行写入后永不改变。** 所有可变事实（退役、slug 更名、ref 补有效期、`lp` 归入 `ln`）都以新行追加到
`events.jsonl` / `*.ref.jsonl`，因此“只追加”可以简化为一条机器可验的规则：
*基线版本的每一行，在新版本同一文件中逐字节存在，且顺序不变*（即旧文件是新文件的前缀）。
不再需要 `seq` 计数表：下一个序号 = 该文件最大序号 + 1（退役实体的行永不删除，所以序号不会回收）。

**行格式**（示例，实际每条一行）：

```jsonl
{"schema":"jtm-registry/1","region":"jp","kind":"st"}
{"id":"st:jp:5871","parent":"cx:jp:3700","slug":"jr-east/shinjuku","run":1}
{"id":"ls:jp:20311","parent":"st:jp:5871","part":"lp:jp:412","run":1}
{"id":"st:jp:5871","scheme":"n02-station","value":"003701","run":1}
{"id":"lp:jp:412","scheme":"package-line","value":"jp-東日本旅客鉄道-中央線","run":1}
{"id":"lp:jp:412","event":"line","value":"ln:jp:88","why":"line-crosswalk","run":2}
{"id":"st:jp:5871","event":"retire","on":"2027-03-14","why":"N02-26: 移設","run":7}
{"id":"ln:jp:88","event":"slug","value":"jr-east/tokaido","run":3}
{"old":"MTR-SIL-ADM","scheme":"legacy-station-code","id":"st:hk:12","why":"ADR 0010","run":1}
```

**规范化规则**（`mint-registry.mjs` 写出时执行，校验器逐行重序列化比对）：

1. 每文件第一行是 header：`schema`、`region`、`kind`；之后一行一条记录，UTF-8、LF、文件以换行结尾。
2. 紧凑序列化：`JSON.stringify` 无空格；**不转义非 ASCII**（站名、线名保持可读，可 grep）；无尾随空白。
3. 键顺序按种类固定（`id`/`old` 先，`run` 末）；省略 `null`、空串与默认值（如无下界的 `from`）。
4. 实体文件内按序号严格递增，即追加顺序；ref 文件按追加顺序（同一次运行内按 `(id, scheme, value)` 排序，保证首次铸造可复现）。
5. `id` 写全（`st:jp:5871`）而非裸序号：多 8–10 字节，但任何文件、乘车记录、日志里都能直接 grep。
6. `run` 是 `runs.jsonl` 的整数序号，不在每行重复时间戳与工具版本。
7. 单文件上限 25 MB；超限时按序号区间切分为 `ls.0001.jsonl`、`ls.0002.jsonl`（预计只有 CN 的 `ls`/`ls.ref` 可能需要）。

体积估算：约 9.5 万实体行 × ~75 B + 约 15 万 ref 行 × ~65 B ≈ 17 MB（六地区合计，CN 约占一半），
无需 LFS；只追加使 git 增量压缩近乎只存新增行。

**仓库处理**：

- `.gitattributes`：`app/data/registry/**/*.jsonl text eol=lf merge=union`。
  `union` 让两条分支各自追加的行自动并存；若两边铸造了相同序号，合并后的文件会出现重复 `id`，
  校验器必然拒绝——此时丢弃分支一侧的新行，在合并结果上重跑 `mint-registry.mjs`（铸造确定，只是序号顺延）。
  仍建议**常规铸造只在 main 上进行**，union 只是兜底。
- PR 审阅直接看 git diff：新增实体、事件、ref 都是独立新行；任何 `-` 行即违规。
- 写入用临时文件 + rename（ADR 0005 的原子写法），一次运行全部文件写成功后才替换。
- `mint-registry.mjs --dry-run` 只打印将追加的行数与样例，不写文件。

### 9.3 铸造规则（冻结清单之后首次运行即“冻结”）

按依赖顺序，每一步先查账本（按 `refs` 匹配），命中即复用，未命中才追加：

1. **operator**：键 `(region, package operator name)`；`operator_alias` 和乘车记录 `company` 自由文本收集为 `refs(scheme='alias')`。
   报告：乘车记录中解析不到或解析到多个 operator 的 `company` 值。
2. **line_part / line**：每个现有 package line id 一个 `lp`（1:1），旧 id 记入 `refs(scheme='package-line')`，包内区间序号与 part 含义不变。
   `ln` **只按 `line-crosswalk.json` 铸造**：首次运行该文件为空，`lp` 暂无 `ln`。
   P0 生成 `line-family-candidate` 报告（同 operator、去 `-N`/`-pN` 后同名，或同 `railway_identity`），供人工审定后写入 crosswalk；
   `railway_identity` 是运行系统（如 `jp-jr-east-ueno-tokyo-through`）的进 `identity-not-a-railway` 报告，留到 P1 建 `route_pattern`。
   CN 一个 relation 一个 `lp`（暂不归并，§8-3）。
3. **station_complex**：每个 `(region, group_code)` 一个 `cx`；`refs` 记 group code。
4. **station**：每个 `(group_code, operator)` 一个 `st`，`parent = cx`；`refs` 记该组合下全部 N02/TDX/MTR 站码；同时写 `station_operator(role='owner')`。
   这是身份分组，不声明共用站台或物理连接。`station_facility` 不在 P0 铸造，只出候选报告。
5. **line_stop**：每个 `(package line id, station)` 一个 `ls`，`parent = st`，并引用其 `lp`；派生键为 `lp|st`，所以线路改由他社运营时旧 `ls` 退役、在新 `st` 下铸造新 `ls`。

护栏（P0 评审后加入）：
- 解析到已退役实体的输入不铸造、也不在其下铸造子实体，进 `reappeared` 报告，铸造脚本以失败退出。
- 任何退役都需要显式 `--allow-retire`，防止某地区包读取失败时整片退役。
- 多家公司共用的源站码不分配给任何一家，进 `station-code-conflict` 报告（P0 实测：TW `TRA-4080` 嘉義，台铁与阿里山林业铁路共用）。
- 多文件追加先写全部临时文件，再按 ref → 实体 → 事件 → runs 的顺序 rename；每个实体必须恰有一条键 ref，校验器据此发现中断的写入。
- 已知设计限制：operator 以包内公司名为键，公司改名会铸造新 `op` 及其下的 `st`。P1 须加入公司改名映射（为既有 `op` 追加带 `from` 日期的新 `package-operator` ref），使改名只追加名称、不换 id（不变量 1）。

“冻结”含义：账本一经入库，此后重建只能追加；源数据中某实体消失时在 `events.jsonl` 追加 `retire` 事件（附日期与来源），不删除、不复用序号。

### 9.4 `rail.db` 新增表

```sql
registry_entity(id TEXT PRIMARY KEY, kind TEXT, region TEXT, slug TEXT, parent_id TEXT, created TEXT, retired TEXT)
external_ref(entity_id TEXT, scheme TEXT, value TEXT, valid_from TEXT, valid_to TEXT, source TEXT,
             UNIQUE(scheme, value, valid_from))
identity_alias(old_key TEXT, scheme TEXT, entity_id TEXT, reason TEXT)   -- 旧 package line id、旧 HK/MO/KLRT 码等
line_operation(line_id TEXT, operator_id TEXT, role TEXT, valid_from TEXT, valid_to TEXT)
station_operator(station_id TEXT, operator_id TEXT, role TEXT, valid_from TEXT, valid_to TEXT)  -- P0 只有 owner
homonym_group(region TEXT, kind TEXT, norm_name TEXT, entity_id TEXT, display_label TEXT)
registry_exception(region TEXT, rule TEXT, entity_ids TEXT, detail TEXT)
excluded_source(region TEXT, scheme TEXT, value TEXT, reason TEXT, source TEXT)   -- 不变量 3 的显式排除清单
```

这些表由构建器读取 JSONL 账本后写入，并带 `UNIQUE` / 外键 / `STRICT` 约束——每次构建都顺带复核一遍完整性；`rail.db` 仍是可随时重建的派生物。
现有表保持不变，只加 `registry_id` 列的映射视图（`line_registry`、`station_registry`），旧查询继续可用。
`name` 统一表（§3.5）推迟到 P1，P0 不合并名称表。

### 9.5 例外报告应覆盖的规则

所有报告**只列不改**，不直接铸造实体；条目带稳定排序，便于下一轮 diff。

| 规则 | 含义 | 已知样例 |
|---|---|---|
| `line-family-candidate` | 可能属于同一 `ln` 的 `lp`（同 operator 去后缀同名、同 `railway_identity`） | `東海道線` 系列 |
| `same-operator-split-names` | 同站群同公司但站名不同 | 待报告 |
| `same-operator-multi-codes` | 同站群同公司多个站码（多线） | 都営 新宿（新宿線 003708 / 大江戸線 003715） |
| `cross-complex-same-station` | 同公司同名、相距很近却分属不同站群（阈值 500 m，仅作线索） | 待报告 |
| `unmapped-source` | `source_station.station_id IS NULL` | JP 6 行、TW 2 行 |
| `ambiguous-company-text` | 乘车记录 `company` 无法唯一映射 | 待报告 |
| `identity-not-a-railway` | `railway_identity` 是运行系统而非铁路 | `jp-jr-east-ueno-tokyo-through` |
| `history-unmatched` | `rail-history*.json` 中 name+bbox 匹配不到或匹配多个 id | 待报告 |
| `shared-facility-candidate` | 多公司站群里，两家公司车站点位 < 50 m 或共用 N02 站码（仅作线索，审定需来源） | 押上、目黒、中目黒、代々木上原、熱海 |
| `name-line-not-unique` | 同一国家内 `(站名, 线名)` 指向多个站群（§11.4） | JP 3 组（均为 `本線`）、TW 2 组、CN 81 组 |
| `line-label-collision` | 线名在国家内不唯一，需要公司限定标签 | `本線` ×11、`東海道線` ×3 家 |
| `line-alias-is-country-code` | 线路别名/线路记号与受支持国家代码相同（会破坏 §11.2 语法） | 待报告 |

### 9.6 校验（按 `ios/VERIFICATION.md`，只做相关最小检查）

P0：

1. `validate-registry.mjs`：§6 不变量 1–5、8、11（P0 不涉及有效期，不变量 6 留到 P2）。
2. 幂等：同一输入连续运行 `mint-registry.mjs` 两次，账本文件字节完全一致（规范化序列化保证），第二次 `--dry-run` 报告零追加。
3. 只追加：`validate-registry.mjs --base <ref>`（默认 `git merge-base HEAD main`）断言基线中每个账本文件是新文件的前缀；
   规范化：每行重序列化后与原行逐字节相等；无重复 `id`、无重复 `(scheme, value, from)`、`parent`/`part`/事件目标都存在、每个实体至多一次 `retire`。
   用改坏的夹具（改一行、删一行、重排、重复 id、带空格的行）证明校验器会拒绝。
4. 稳定性夹具：手工小夹具模拟“线路改名”“operator 转让”“站被移除”“新站加入”，断言旧 id 不变、新实体追加、移除者标 `retired`。
5. 覆盖率：每个地区 `line_stop` 数 = `line_station` 数；每个 package line id 恰有一个 `lp`；无孤儿 `parent_id`。
6. 保护样例（准备文档 L83–94）作为夹具：样例涉及的 line/station 都有 `lp`/`st` 与正确的 `package-line` / 站码 ref；
   P0 前后这些样例的 compact 包、`display-lanes.json`、历史叠加、修复 authority 与已否决候选文件字节不变。

| 样例 | 保护的事实 |
|---|---|
| 横滨相铁、糸鱼川大糸本线站台 | 共享站 id 不覆盖本线显示端点与进出站方向；邻线不决定路径 |
| 品川／大崎、京叶 shared forks | 共用 supports 与精确 follow ruler；共同段与各自端点保留 |
| 北松江 #6 | 仅删 15/17/19，物理站点与公里不变；target part1 150→0 不改 |
| 渡良濑花轮 #8 | 已删后一组 v5，前一组 v2/v3 仍未决；不能用一个 accepted 标记吞并两组 |
| 宫津 #9/#15 | 同一 authority 保留前次已接受修复，不被后次 export 覆盖 |
| 夷隅 `substitute_bus` | 服务状态与 Main 普通区间绘制保留 |
| 宫福、布崎、西野尻 rejected | 保留否决理由，不迁为 accepted repair 或自动兜底 |
| CN `source_review_id` 与地铁误标 | 源轨道身份与审阅 provenance 不混用 |
| 广州南／沈阳北／攀枝花南、楚雄—丽江 | 返回部件与真实连接缺证分别迁移，不补边 |
| Manyo 旧 23 对与缺失 named plan | 旧作用域验收保留；缺失计划不伪造成新 identity 复核通过 |

7. 修复模块的写前快照守卫（如 `repair-three-reversal-extents.mjs` 的 `applyPreparedWrites`）与 `refreshDependencyReferences` 不被 P0 触及；
   **任何一期**的 schema 或事务改动都必须保留这些更新 owner 与过期写入守卫，也不替换历史证明/重放记录（准备文档 L147）。
8. 不启动原生 App；不重跑全国源数据构建、不跑全量测试，只跑 `build-rail-database.mjs` 与上述校验。

P0 之后各期（准备文档 L96）：

- P1 读取/往返用现有聚焦合同（alias、导入、编码解码测试）。
- 只有 renderer / schema decoder / 资源构建改变时才做一次增量构建。
- 有地理或组合显示变化时，只选一个有代表性的现有 Main 同相机 ON/OFF 对比。
- 一次只跑一个 heavy/native job，复用依赖未变的有效证据；不重建退役矩阵或全树 hash 工作流。
- CN 冻结的 88×2 只在相关行为变化时按既有 owner 执行。
- 归零的 overlay 不能当作“没有地理缺陷”；只替换 region checksum 或 JSON 不能证明 Main 读到了新几何。

### 9.7 完成标准

- 阶段 0 冻结清单完成；JSONL 账本入库（不走 LFS），六个地区 `op`/`lp`/`cx`/`st`/`ls` 全部铸造（`ln` 待 crosswalk 审定），校验全绿，字节级幂等与只追加校验成立。
- 索引空间映射、例外报告与同名报告生成，交由人工审定（P1 输入）。
- `rail.db` 旧表与旧查询无回归（行数与 schema v3 一致）；§9.6-6 的受保护文件字节不变。

## 10. P1 概要（待 P0 报告审定后细化）

1. 根据例外报告填 `station-overrides.{region}.json`（合并/拆分 `st`），重新运行铸造（只追加/标记 `retired`，旧 `st` 进 alias）。
2. 根据审定后的 `line-crosswalk.json` 把 `lp` 归入 `ln`（追加 `event:"line"` 行）；包内 `-N`/`-pN` 不收拢，收拢若需要属于 P5 且在网站仓库。
3. 按 `shared-facility-candidate` 报告，**有来源**的人工审定后才铸造 `station_facility`（含 `manager`）与 `station_link`；
   不从距离、共用代码或站群直接生成；结果追加到 `fc.jsonl` / `events.jsonl`，不改已有 `st`。
4. 新增 `route_pattern` 并收编 `identity-not-a-railway` 条目与 through-service catalog 的引用。
5. 统一名称表 `name`（§3.5），旧名称表改为视图。
6. 由 JSONL 账本导出、打包给 app 的精简身份表 `registry.{region}.json`（派生物，格式在 P1 再定；`st` ↔ 站码、`op` ↔ 别名、`lp` ↔ package line id）。
   乘车记录引用**只经现有 alias/import 路径**（`StationCodeAliases.canonical`、`JourneyCompletion`）升级：新增可选字段 `station_id` / `operator_id`，
   读取时由原码补全、保存时双写，旧字段继续保留；无法唯一升级的旧记录保持原样并报告。
7. 修正 TW 两处站群归属（§11.4）。

P1b（不在身份迁移关键路径上）：§11 的导入语法、解析顺序与界面小字标签。

## 11. 行程导入（所有受支持地区；CN 的唯一性保证在 P3 后）

### 11.1 最少输入

导入一条行程只需要 **日期 + 起点 + 终点**。线路、车次/列车名、时刻、途经站、公司都是可选的；
地区、途经站与路线由解析器和路线求解器（0007、0012）推出。用户永远不需要输入站码、id 或坐标。

支持的输入：

| 形式 | 例 |
|---|---|
| 单行文本 | `2026-07-03 府中 (JP, 京王線) → 新宿` |
| 多段文本（换乘） | `2026-07-03 関西空港 → 新大阪 はるか38号 / 新大阪 → 東京 (JP, 東海道新幹線)` |
| CSV / TSV | 列：`date, from, to[, line][, train][, dep][, arr]` |
| 现有 JSON | stop 可写 `"station": "府中 (JP, 京王線)"`，也可继续写站码 |
| 手动录入 / 粘贴文本（`JourneyTextImport`） | 候选列表使用同一标签（§11.5） |

箭头接受 `→ -> ～ ~ -`；日期接受 `YYYY-MM-DD`、`YYYY/M/D`。

### 11.2 站点引用语法

```
站名
站名 (CC)
站名 (线名)
站名 (CC, 线名)
```

- 括号可用半角 `()` 或全角 `（）`；分隔符可用 `,` `，` `、` `·`；空格可有可无。
- **CC** 是 ISO 3166-1 alpha-2 大写：`JP TW HK MO KR CN`（NA 已退役，`US`/`CA` 不受支持；CN 可用，但 P3 前 `(站名, 线名)` 不保证唯一，歧义按 §11.3 第 6 步拒绝）；输入不区分大小写，`jp` 等地区 slug 也接受。
  括号里只有一个元素时：属于受支持国家代码集合就当作 CC，否则当作线名；有两个元素时，第一个一定是 CC，第二个一定是线名。
  因此与国家代码相同的线路记号（如東京モノレール的 `MO`，与澳门 `MO` 相同）只能写成 `浜松町 (JP, MO)`；`浜松町 (MO)` 表示澳门。
- **线名**可以是该国内任一线路别名：官方名、去掉编号的通称（`丸ノ内線` 对 N02 的 `4号線丸ノ内線`）、
  公司限定名（`京成本線`、`阪神本線`）、英文名、线路记号（`JY`、`M`）、运行系统名（`上野東京ライン` → `route_pattern`）。
  别名来自 §3.5 `name` 表 `form='alias'`，P1 补齐。
  线名可以是该站任一条线，包括直通进来的他社线路名：`代々木上原 (JP, 千代田線)` 与 `代々木上原 (JP, 小田原線)` 都有效，
  分别解析到メトロ与小田急的车站。
  也接受只写公司简称（`押上 (JP, 京成)`），只要在该站群内唯一。
- **站名**可以是任一支持语言的名称或读音（官方名、英文、假名/罗马字、繁简），经 `name` 表匹配。
- 同一行程内，后续站点省略 CC 时继承行程或前一站的国家。

### 11.3 解析顺序（每一步只做筛选，绝不任意挑一个）

1. **国家**：显式 CC → 行程级 CC → 另一端点唯一确定的国家 → 用户默认地区 → 全部受支持地区。
2. **站名候选**：在该国内按名称/别名/读音匹配，且在行程日期有效（0011）。
3. **线名筛选**：给了线名就只保留该线路（或其 `route_pattern`）上的站。
4. **上下文**：保留能与另一端点候选成立的组合（同一线路，或在物理拓扑上可达，换乘只是乘客关系、不是物理连接）；
   列车名/车次/公司映射到 operator 时进一步筛选；时刻与日期校验。
   这一步的可达性筛选**只用于排除不同站群的同名候选**；同一站群内的公司车站之间不做可达性取舍，交给第 5 步。
5. **同站群内的公司车站**：剩余候选若全是同一站群里的不同公司车站（熱海 = JR東日本 / JR東海；押上 = 4 家），
   这不是同名异站，但仍要选出公司车站：只有线路、列车或公司**恰好选出一个**时才自动确定；
   否则**不由求解器代选、不由邻线决定**，进入第 6 步。
6. **仍不唯一 → 拒绝自动选择**，返回候选列表，每个候选都以 §11.5 的完整标签表示（例如
   `府中 (JP, 京王線)`、`府中 (JP, 徳島線)`、`府中 (JP, 福塩線)`、`府中 (JP, 天橋立鋼索鉄道)`；
   同站群时为 `熱海 (JP, 東海道線〔JR東日本〕)` 等），用户点选或直接把标签粘贴回去即可唯一解析。

这替代了现在 `Stations.resolveStationForTrain` 在没有列车上下文时“返回第一个按名称匹配的候选”的行为，
与 0012 的“歧义即拒绝”一致。

### 11.4 唯一性保证（`rail.db` 快照）

**线路标签**：国家内线名唯一时就用线名；不唯一时用公司限定名（`京成本線`、`阪神本線`、`JR東海 東海道線`）。
在此规则下，统计“同一国家内 `(规范化站名, 线名)` 对应多个站群”的组数：

| 地区 | 只用线名 | 用公司限定标签 | 说明 |
|---|---|---|---|
| JP | 3 | **0** | 全是 `本線`：住吉（長崎電軌 / 阪神）、大町（函館市電 / 富山地鉄）、稲荷町（富山地鉄 / 広電） |
| TW | 2 | 2 | `左營 (縱貫線南段)` 混入了 KRTC R16，`苗栗 (臺中線)` 混入了 THSR 苗栗——看起来是站群归属数据错误，进例外报告 |
| HK / MO / KR | 0 | 0 | — |
| CN | 81 | 81 | OSM 方向/分支 relation 造成，P3 归并后重测 |

另有 166 个站名在两个以上国家出现（如中日韩共有的汉字站名），所以只有行程上下文无法确定国家时才需要 CC。
P0 的校验器把这项统计作为 `name-line-not-unique` 报告输出，P1 修正 TW 两处后要求 JP/TW/HK/MO/KR 为 0。

### 11.5 界面显示：括号限定词用小字

标签的规范形式是 `站名 (CC, 线路标签)`，界面显示为两部分：

```
府中 (JP, 京王線)
└┬┘ └─────┬─────┘
 正文    小字（caption 字号、secondary 颜色，括号一并小字）
```

- **显示位置**：站点搜索结果、站点选择器、导入候选与导入复核、行程详情的停靠站列表、统计里的车站列表。
  地图标注不显示（空间不够，靠位置区分）。
- **线路标签取值**（车站常有多家公司、多条线路，按场景取）：
  - 行程停靠站：取这一站实际乘坐的线路——`府中 (JP, 京王線)`。
  - 换乘站：两段线路都显示——`新宿 (JP, 山手線 → 京王線)`；同一公司内换线也一样。
  - 搜索结果 / 站点选择器：一行一个站群，小字列出线路，按“与当前行程相关 → 干线优先(rank) → 名称”排序，最多 2 条再加 `+N`——
    `新宿 (JP, 山手線・京王線 +9)`；同名异站自然被各自的线路区分——`府中 (JP, 京王線)`、`府中 (JP, 徳島線)`。
    展开一行可看到按公司分组的线路（JR東日本：山手線・中央線…；京王：京王線…），选中公司车站时才需要这一步，
    多数情况由另一端点或线路推断（§11.3 第 4–5 步）。
  - 复制 / 导出：始终只写**一条**具体线路，保证粘贴回导入唯一解析。
- **CC**：始终显示，保证同一种格式贯穿各国家；用户只有一个地区的数据时也照样显示，避免切换地区后格式变化。
- **复制 / 分享 / 导出文本**一律输出完整标签 `府中 (JP, 京王線)`，粘贴回导入能唯一解析（往返稳定）。
- 无障碍：VoiceOver 朗读为“府中，日本，京王線”；小字跟随 Dynamic Type，不设固定字号。
- 标签是派生值，不写入乘车记录；乘车记录存 `station_id`（§8-2），显示时按当前名称生成，改名后自动更新。

### 11.6 分期

- **P0**：只做统计和报告（`name-line-not-unique`、`line-label-collision`、`line-alias-is-country-code`），不改导入。
- **P1b**：在 RailCore 实现语法解析与 §11.3 的解析顺序（依赖随 app 打包的身份表与别名）；
  `JourneyTextImport` / CSV / JSON 导入共用现有导入 interface 下的同一个解析器；界面加小字限定词。不阻塞 P1 的乘车记录升级。
- **P3 之后**：CN 归并完成、`name-line-not-unique` 复测为 0 后，CN 才获得与其他地区相同的唯一性保证；此前 CN 的歧义一律拒绝自动选择。
