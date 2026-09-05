# 美加铁路数据优化与交接手册

更新时间：2026-08-31  
适用对象：继续检查、修复或发布美国与加拿大铁路数据的 agent 和维护者。

这份文档是美加铁路工作的入口。它记录当前状态、数据位置、证据等级、提交与拒绝规则，以及已确认的历史故障。逐线路的最终状态以
[`na-2025-line-review.json`](../app/public/rail/na-2025-line-review.json)
为准；本文解释如何正确读取并更新该台账。

> 这是工程上的保守再分发策略，不是法律意见。只要许可范围、来源血缘或线路真实性仍不明确，就保持拒绝，不用“看起来合理”的几何替代。

## 1. 当前结论

美加包采用 fail-closed 发布方式：线路必须同时具备可解释的站序、站点身份、官方颜色和可再分发的合格轨道几何；任一项无法证明就拒绝该线路，而不是用直线、随机颜色或人工猜测补齐。

截至本文更新时，最新严格候选为 `/private/tmp/jtm-na-release-final8-0831`：美国 265 条线、2,767 个站点组、3,497 个区间；加拿大 52 条线、374 个站点组、408 个区间。逐线台账含 317 个 published 与 426 个 blocked 记录。紧凑格式审计为 0 个 `ERROR`，且没有发布 `geometry.deviation`、`geometry.unchecked`、`geometry.spike`、站到站直线、孤儿支线、断裂 seam 或重复站序。该数字不是“全国完整率”，严格完整性门禁仍因大量被拒线路保持关闭。

状态含义如下：

| 状态 | 含义 | 能否进入 `us-2025.json` / `ca-2025.json` |
| --- | --- | --- |
| `published / passed` | 当前候选的站序、身份、颜色、几何和结构门禁均通过 | 可以 |
| `published / warning` | 已发布，但仍有曲率、站内锚点等非阻断复核项 | 可以，必须保留 warning |
| `blocked` | 无合格 alignment、颜色、站序或来源；或审计发现反转、偏移、直线、缺段 | 不可以 |
| `reference-validated` | 发布坐标来自可再分发源，另用受限 GIS 在本机交叉验证 | 可以；包内不得含受限坐标 |
| `station.split.reviewed` | 同一官方站点/换乘综合体的多个站台锚点已逐站审查 | 可以；仅豁免该 station ID 与其专属上限 |
| `superseded / duplicate` | 同一服务由更高优先级官方 feed 提供 | 不重复发布 |

必须同时查看四份材料：

1. [`na-2025-line-review.md`](../app/public/rail/na-2025-line-review.md)：给人阅读的逐线路提交/拒绝表。
2. [`na-2025-line-review.json`](../app/public/rail/na-2025-line-review.json)：给 agent 和测试读取的结构化状态。
3. [`na-2025.acceptance.md`](../app/public/rail/na-2025.acceptance.md)：最近一次候选的数量、哈希、门禁和未完成声明。
4. [`na-2025-build-report.json`](../app/public/rail/na-2025-build-report.json)：逐 feed 的构建数量、拒绝原因、来源选择和构建 note。

`published` 只表示“当前证据下允许提交”，不表示该运营商所有线路都齐全。`blocked` 是正常且优于猜测的结果。

## 2. 数据位置与职责

| 位置 | 数据种类 | 是否提交 Git | 作用 |
| --- | --- | --- | --- |
| [`app/scripts/railway/na-feeds.json`](../app/scripts/railway/na-feeds.json) | feed 注册表、route 级映射/拒绝、官方颜色、站点身份例外 | 是 | 人工审查结论的唯一配置入口 |
| [`app/scripts/railway/build-north-america-rail-package.py`](../app/scripts/railway/build-north-america-rail-package.py) | 构建器、站序/方向/支线/几何选择和 fail-closed 门禁 | 是 | 从源数据生成包；不要手改生成 JSON |
| [`app/scripts/railway/lib/na_provenance.py`](../app/scripts/railway/lib/na_provenance.py) | 可发布官方 GIS 的 publisher、URL、route key 白名单及 SHA 验证 | 是 | 防止错误来源或受限来源伪装成 official geometry |
| [`app/scripts/railway/rebuild-na-official-networks.sh`](../app/scripts/railway/rebuild-na-official-networks.sh) | 可再分发官方 GIS 的可复现下载与标准化入口 | 是 | 重建 `official-networks`；受限 GIS 不得出现在这里 |
| `SOURCE_DIR/gtfs/*.zip` | 运营商 GTFS | 否，本机缓存 | 线路身份、站序、方向、名称、颜色；shape 仍需独立验证 |
| `SOURCE_DIR/official-raw/*` | 允许进入发布链的政府/运营商 GIS 原始文件 | 否，本机缓存 | 记录原始 SHA，生成 route-isolated official network |
| `SOURCE_DIR/official-networks/*.geojson` | 按 route 隔离并带 manifest 的可发布官方几何 | 否，本机构建输入 | 主要线路几何；manifest 必须通过 provenance 校验 |
| `SOURCE_DIR/narn/*.json.gz` | FRA/BTS North American Rail Network | 否，本机缓存 | 美国/加拿大干线铁路的可再分发测绘候选和交叉验证 |
| `SOURCE_DIR/osm-routes/*.json.gz` | OSM relation 缓存 | 否，本机缓存 | 视觉/拓扑交叉检查；当前严格包不直接以 OSM 作为最终几何 |
| `.local/railway-reference-only/` | 许可不允许再分发的官方 GIS | **绝不提交**，已写入 `.gitignore` | 仅在本机比较候选，不能成为包坐标或 official manifest |
| [`app/public/rail/us-2025.json`](../app/public/rail/us-2025.json) / [`ca-2025.json`](../app/public/rail/ca-2025.json) | Web/iOS 实际读取的 compact-v1 线路包 | 是 | 发布物 |
| [`app/public/rail/na-2025-build-report.json`](../app/public/rail/na-2025-build-report.json) | 同次完整构建的 feed/route 接受、拒绝和 note | 是 | 后续 agent 追查 `no usable alignment` 的原始台账 |
| `app/data/stations-{us,ca}.json` | 路径规划站点表 | 是 | 必须与同次包构建同步 |
| `app/data/rail-sections-{us,ca}.json` | 路径规划线段图 | 是 | 几何必须与 compact-v1 解码结果逐点一致 |
| `app/data/station-readings-{us,ca}.json` | 多语言站名读音 | 是 | station code/group code 必须完整 |
| `app/public/rail/{us,ca}-2025.audit.{json,md}` | 国家包审计 | 是 | 发布线路 warning/error 的证据 |

推荐本机 `SOURCE_DIR=/private/tmp/jtm-na-rail`。路径不是协议的一部分；未来 agent 可以使用别的目录，但不得把临时绝对路径写入发布包。

## 3. 逐线路提交与拒绝台账

不要在本文手工维护数百条容易过期的线路。每次完整构建后用同一份包、审计和 build report 生成逐线路台账：

```bash
python3 app/scripts/railway/make-na-line-review.py \
  --package /path/to/candidate/us-2025.json \
  --package /path/to/candidate/ca-2025.json \
  --audit /path/to/candidate/us-2025.audit.json \
  --audit /path/to/candidate/ca-2025.audit.json \
  --build-report /path/to/candidate/build-report.json \
  --output app/public/rail/na-2025-line-review
```

台账每行必须保留：国家、最终 line ID 或原 route ID、feed、线路名、状态、实际几何源、被替代的候选源、官方颜色依据、长度、站数和完整拒绝原因。禁止把多个 route 的理由压成“no usable alignment”。

当前已通过或已确认的代表性项目包括：

- Alaska Fairbanks 与 Whittier 的官方 GTFS 错位已用双源守卫修正；Aurora Winter 的正确量级约 571 km，而不是错误的 1,065 km。但 Alaska 线路若缺官方颜色，仍应整体拒绝。
- Caltrain 使用 Caltrans California Rail Network 中的可再分发线路并按 GTFS route 隔离。
- VIA Ontario 已接受 Toronto–London、Toronto–Sarnia、Toronto–Windsor 三条 ORWN 隔离走廊。
- Ottawa O-Train 2/4 使用 City of Ottawa Stage 2 alignment 与 OC Transpo 官方站序。
- TEXRail 使用 NCTCOG 轨道网络；Empire Builder 使用 FRA/NTAD 路线并通过当前门禁。
- Sounder North 与 Tacoma T Line 的发布坐标只能来自运营商 GTFS shape；Sound Transit 工程 GIS 只可在本机验证，不可进入包或 manifest。

仍应保持拒绝的主要类别包括：

- 没有第二个独立测绘证据：BART、WMATA、Cleveland、DART、Detroit、Cincinnati、Milwaukee、部分 RTD/SacRT/Valley Metro 等。
- 官方 route layer 断裂、少段或有内部反转：部分 Amtrak、VIA、MTA、SEPTA、MBTA、Metra、VRE、Metrolink、GO/UP Express。
- 上下行共享一个 route ID 但轨道不同，无法安全合成单中心线：例如 SFMTA Powell/Hyde、Powell/Mason 等方向性线路。
- 只有 OSM 或来源明确由 GTFS 派生，不能构成独立验证。
- 缺少运营商发布颜色，或只有随机/默认/推断颜色。
- 主干未通过时的任何支线；支线不得绕过 trunk gate 单独发布。
- Galveston Rail 当前必须拒绝：官方环线由 `Rail-A-OB` 与 `Rail-A-IB` 两个不同半环组成，构建器却只保留一个 shape 并在返程反向复用，产生 89% 自重叠。永久修复必须让合成 cycle 的每条有向边保留自己的 pattern/shape provenance，不能把它改成开放线或拆成两个公开 line ID。

精确 route ID 和原因始终从 line review/build report 读取，不要根据上面的运营商摘要批量放行。

## 4. 受限官方 GIS：如何使用而不再分发

### 4.1 硬规则

受限 GIS 只能回答“另一个可再分发候选是否足够接近真实线路”，不能提供最终坐标。以下操作都禁止：

- 把原始文件、解压文件、标准化 GeoJSON、截图或坐标表提交到 Git/GitHub。
- 把受限线逐点复制、抽稀、平滑、重采样、描摹或切片后写入发布包。
- 在 `na_provenance.SOURCES`、`officialNetworkByRouteId` 或 distributable `official-networks/manifest.json` 中登记受限源。
- 因受限源“看起来最好”而用它替换 GTFS/NARN 的坐标。

上述限制只针对 Git/GitHub 和最终发布物。在 `.local/railway-reference-only/` 内可以自由解压、投影、切片、重采样、建立空间索引、叠加底图、逐点量测或生成临时报告；这些坐标和中间成果必须始终留在被忽略的本机目录中。若某次处理实际把受限几何变成最终线路坐标，那仍属于分发受限数据，不能提交，除非已经取得相应许可。

允许提交的只有不可还原原始几何的审计元数据：publisher、dataset/item ID、许可页面 URL、获取日期、原始 SHA-256、被验证的候选源、采样方法、最大/中位偏差、通过/拒绝结论和审查者说明。

### 4.2 本机目录

```text
.local/railway-reference-only/
├── sound-transit/
├── maricopa-valley-metro/
└── sbcta-redlands/
```

每个目录可在本机保存 `raw/`、临时投影结果和 `receipt.json`；整个根目录已被 `.gitignore` 排除。建议 `receipt.json` 至少含：

```json
{
  "publisher": "...",
  "datasetId": "...",
  "sourceUrl": "...",
  "licenceUrl": "...",
  "retrievedAt": "YYYY-MM-DD",
  "rawSha256": "...",
  "redistribution": "reference-only",
  "notes": "Do not commit coordinates or derived geometry"
}
```

### 4.3 三个已知受限来源

| 来源 | 当前处理 | 发布几何应来自 | 备注 |
| --- | --- | --- | --- |
| Sound Transit `STPublicData.zip` 工程 GIS | reference-only；已从 provenance 白名单与 official-network 重建流程移除 | Sound Transit GTFS shape，且必须通过本机受限 GIS 比较 | Sounder North/T Line 可记录 `referenceValidatedGeometryByRouteId`；1 Line、2 Line、Sounder South 当前仍拒绝 |
| Maricopa County / Valley Metro GIS | reference-only；不得提交原始或派生坐标 | Valley Metro GTFS 或另一个明确允许再分发的政府测绘源 | 当前 MAG/Valley Metro layer 的独立测绘血缘也未证明，A/B/S/SKYT 保持拒绝 |
| SBCTA Redlands Passenger Rail / Arrow GIS | reference-only；permission required | Metrolink/运营商 GTFS、Caltrans/FRA 等可再分发线路 | SBCTA ArcGIS metadata 明示“permission required if planning to use data” |

Sound Transit 的 Open Transit Data 条款与网站/工程内容条款并不完全相同，因此必须按具体下载项的许可处理，不能把 GTFS 的开放条款自动套到工程 GIS。SBCTA 的公开 GIS 门户允许浏览/下载，并不自动覆盖某个 item metadata 的额外限制。Maricopa/Valley Metro 的具体许可证据应连同原始文件保存在本机 receipt；在许可复核完成前按用户提供的“仅县内部使用”限制执行。

### 4.4 正确比较流程

1. 选择可再分发候选，例如运营商 `shapes.txt`、FRA/NARN、Caltrans CRN 或另一份许可明确的政府线路。
2. 在本机读取受限 GIS，只计算比较指标；不要把它送进 normalizer 的发布输出目录。
3. 检查全线路覆盖、站点锚点、方向/支线拓扑、最大与中位横向偏差，并专门检查隧道、环线、折返和共享走廊。
4. 通过时只把非坐标结论写到 `referenceValidatedGeometryByRouteId`，最终 `geometrySource` 仍必须是可再分发候选。
5. 未通过或候选不完整时写入 `blockedRouteIds` 或 `geometryReviewByRouteId`。构建器把未解决的 `geometryReviewByRouteId` 当作硬拒绝。

Sound Transit 的一次有效使用示例是：受限 GIS 发现 King Street 锚点误差可由候选从约 201 m 降到约 38 m。该结果可以作为选择/拒绝候选的指标，但 38 m 对应的受限线路坐标不能被复制到包中。

## 5. 数据源优先级与证据要求

每条线路只选一个主要几何源，其他来源用于交叉验证。不要把多个来源按视觉效果拼接。

1. 运营商 GTFS：线路身份、官方站序、方向、班次、名称和 `route_color`。
2. 许可允许再分发的运营商/政府 route-specific GIS：首选轨道中心线。
3. FRA/BTS NARN、NTAD、州/省铁路网络：干线候选；必须能覆盖该 passenger route 的完整站序。
4. OSM：视觉与拓扑交叉检查，不作为当前严格包的最终几何。
5. 受限 GIS：只做本机 pass/fail 比较，绝不提供发布坐标。

“官方”不是自动可信。Alaska Railroad 自己的 GTFS 把 Fairbanks 写到 470 多公里外，正是单一官方源失效的实例。反过来，“政府 GIS”若明确从 GTFS 转换，也不是第二个独立证据。

## 6. 必查故障与已建立的门禁

### 站点位置与身份

- 对每个站检查经纬度范围、相邻站距离、到候选轨道的距离，以及同一 station group 在不同线路上的锚点差。
- Alaska `FAIR`、`WHIT` 使用 route/stop 精确 override 和双源证据，禁止全局扩大容差。
- 跨境 Niagara：NFL 是美国 Niagara Falls，NFS 是加拿大 Niagara Falls；不能互换。
- Saint-Lambert / St-Lambert 必须跨包关联为同一物理站，但保留国家语义。
- PATH 33rd Street 与 MTA Herald Square 是两个不同设施；`crossFeedDistinctStopIds` 必须阻止同名近邻误并。
- CTA Roosevelt、MTA/MBTA/NJT/SEPTA/OC Transpo/TTC/TransLink 等换乘综合体只使用 exact stop/parent/transfer IDs 和逐站最大距离例外。

### 线路几何

- 对每个 station-to-station interval 检测：等距共线点、偏离弦线接近零、异常 detour、尖角/内部反转、未覆盖站点和 snapped endpoint 过远。
- 一段即使有 108 个等距点，只要仍是 Eugene–Albany 那种 64 km 直线，也必须拒绝。
- 不允许 `geometrySource` 名称掩盖直线；GTFS、NARN、OSM 和 official GIS 都用同一几何检测。
- 只允许经独立测绘证明真实笔直的区间，并在 `straightIntervals` 中记录采样证据。

### 方向、环线与站序

- `strip_directional` 必须识别 `(In)` / `(Out)`；NORTA Canal 47 应是约 25 站的开放线路，不是 48 站首尾拼接环线。
- 环线除图结构成环外，还必须通过首末站空间邻接检查。
- Hudson、Maple Leaf 等长途线路必须检测长距离折返和“旋转站序”；Grand Central→Beacon、Niagara→Toronto 这类跳跃不能靠平滑掩盖。

### 主干与支线

- trunk 未发布时，所有 `branchOf` 子线一并拒绝。
- 检查分支是否连接主干、是否只有残段、是否重复上下行。
- St. Charles、TTC 301/306/507、SEPTA Broad Street、NYC 5 等历史“孤儿支线”案例必须保留回归测试。

### 颜色与显示

- 优先使用运营商 GTFS `routes.txt route_color`；缺失时只能使用注册表中带官方 URL 的精确 palette。
- random/default/generated/fallback 颜色是发布错误。
- WebUI 的底图、样式和 overlap lanes 是显示参考，兄弟仓库通常位于 `/Users/sager/Documents/GitHub/Japan-Train-Map`。
- `railmap-basemap.js`、`railmap-style.js`、`app-overlap-lanes.js`、`rail-network.js`、`railmap-geometry.js` 及 basemap assets 必须与 WebUI 保持 byte parity。
- Web 与 iOS 的线帽/线连接保持圆角；修线路时不要把原有 `round` cap/join 改成折角。

### 显示渲染（2026-09-02 起）

美加两个包在两个客户端上都以**每条链一条连续曲线**绘制，不再按车道切片：
`app/public/rail-stroke.js`（Web）与 `ios/RailKit/Sources/RailCore/ContinuousStroke.swift`（iOS）
是同一套引擎，由 `port-fixtures/continuous-stroke.json` 逐点对账。引擎在当前缩放级别的像素
空间里依次做：去重顶点 → 走廊 follow（把线画到 canonical 中心线上）→ 接缝 Z 形折线抹平
（150 m 渐变）→ 车道偏移（三角核平滑的车道剖面，任何变道都是 S 曲线）→ 清理偏移折叠 →
圆角（`strokeCornerRadiusPx`）。站点圆点取自己所在顶点的偏移位置。

- 车道与 follow 都来自 `app/public/rail/display-lanes.json`（`byRegion` / `followsByRegion`），
  由 `app/scripts/railway/build-display-lanes.mjs` 推导。follow 的判定：与同一轨道家族、
  provenance 更高（运营商自有中心线 > NARN > GTFS shape；metro/commuter 的本地运营商 >
  intercity）的另一条线在 ≥1 km 的平滑区间内中位横向距离 ≤ 25 m。它们是**推导出的候选**，
  错了改推导规则或 `na-render-groups.json`，不要手改表。
- 被扣留区间仍然切断链（那是对齐门禁的裁决）；扣留线路的车道/follow 按 Web 的 display part
  编号，与 iOS 的链一一对应。
- 改引擎：两种语言同改，然后 `cd app && node scripts/build/build-port-fixtures.mjs`，
  `cd ios/RailKit && swift test --filter ContinuousStrokeParityTests`。
- 改车道/走廊：`cd app && node scripts/railway/build-display-lanes.mjs`，再跑
  `python3 -m unittest scripts.railway.tests.test_display_network`。
- 目视核对：Web 端见 `.claude/launch.json` 的 `jtm-static`；iOS 端用
  `SIMCTL_CHILD_RAILMAP_UI_TEST_CAMERA="lat,lon,span"`、`SIMCTL_CHILD_RAILMAP_UI_TEST_LAYERS=network`
  启动模拟器构建。

## 7. 标准生成、分步检查与提交

### 7.1 先跑铁路 Skill 预检

```bash
python3 .claude/skills/jtm-railway-audit-repair/scripts/audit_jtm_packages.py \
  --countries us,ca \
  --json /private/tmp/jtm-na-skill-audit.json \
  --limit 40
```

预检用于定位问题层，不代表线路正确。先判断是源数据、拓扑、Web 显示还是 iOS 消费问题，再改最早可复现的那层。

### 7.2 重建可发布 official networks

```bash
app/scripts/railway/rebuild-na-official-networks.sh \
  --source-dir /private/tmp/jtm-na-rail
```

该脚本只处理 `na_provenance.py` 白名单中的可发布源。受限源不得加回脚本。

### 7.3 构建候选

```bash
python3 app/scripts/railway/build-north-america-rail-package.py \
  --source-dir /private/tmp/jtm-na-rail \
  --registry app/scripts/railway/na-feeds.json \
  --output-dir /private/tmp/jtm-na-candidate/public \
  --data-dir /private/tmp/jtm-na-candidate/data \
  --cache-dir /private/tmp/jtm-na-candidate/cache \
  --osm-routes /private/tmp/jtm-na-rail/osm-routes \
  --report /private/tmp/jtm-na-candidate/build-report.json
```

修门禁、注册表或方向/支线逻辑后必须使用新 cache 目录，避免旧 per-feed cache 掩盖行为变化。

### 7.4 分国家审计

```bash
python3 app/scripts/railway/audit-na-package.py \
  --package /private/tmp/jtm-na-candidate/public/us-2025.json \
  --registry app/scripts/railway/na-feeds.json \
  --out /private/tmp/jtm-na-candidate/us-2025.audit.json

python3 app/scripts/railway/audit-na-package.py \
  --package /private/tmp/jtm-na-candidate/public/ca-2025.json \
  --registry app/scripts/railway/na-feeds.json \
  --out /private/tmp/jtm-na-candidate/ca-2025.audit.json
```

发布前硬条件：0 `ERROR`、0 `geometry.deviation`、0 `geometry.unchecked`、0 `geometry.spike`、0 未经 survey 的 `interval.straight`、0 `line.orphanBranch`、0 `interval.seam`、0 `station.repeat`。

### 7.5 回归与客户端

```bash
PYTHONPYCACHEPREFIX=/private/tmp/jtm-pycache \
python3 -m unittest discover \
  -s app/scripts/railway/tests -p 'test_*.py'

./ios/verify.sh --core
```

最后再生成 line review 与 acceptance，复制同一次候选的六个发布/solver 文件和审计文件。不要只复制 `us-2025.json`/`ca-2025.json`。

## 8. 多 agent 协作规则

按区域或运营商拆任务，而不是让多个 agent 同时修改同一套通用门禁。推荐分组：

- 东北/纽约/新英格兰：MTA、LIRR、MNR、PATH、NJT、MBTA、SEPTA。
- 西部/山地：California、Pacific Northwest、UTA、RTD、Arizona。
- 南部/中西部：NORTA、Texas、Florida、Atlanta、Chicago、Ohio/Michigan。
- 加拿大：VIA/GO/UP、TTC/OC Transpo、Québec、Calgary/Edmonton/TransLink。
- 独立身份审查：跨 feed station identity、跨境站点、官方颜色和许可。

每个 agent 交付时必须写明：修改的 route IDs、两个独立证据、源 URL 与 SHA、几何来源、拒绝/通过理由、局部测试、完整测试影响和仍未解决的项目。不要用“已修复北美线路”这种无法复核的总结。

共享工作树可能同时出现其他 agent 的改动。合并前先检查 `git diff`，不要 reset、checkout 或覆盖不属于本任务的修改。通用 builder 语义只由一个 agent 修改；区域 agent 主要提交 normalizer、registry 条目和 route-specific 测试。

## 9. 后续 agent 的最短检查清单

1. 阅读本文件、项目 railway Skill 和最新 line review。
2. 用 `git status` 区分已有改动；不要清理别人的工作。
3. 从 line review 选择一个明确的 `blocked` route，不要按运营商一次性放行。
4. 找两个独立来源，先核许可，再保存 URL、日期、SHA 和 source lineage。
5. 对 GTFS 检查站序、方向、分支、颜色和 station parent/transfer；对 GIS 检查完整覆盖与 route isolation。
6. 修 normalizer/registry/builder 的最早错误层，并新增会在旧行为下失败的 route-specific 测试。
7. 使用全新 cache 做隔离构建，再做完整构建。
8. 检查结构、几何、站点、颜色、WebUI parity 与 iOS core。
9. 更新 line review、acceptance 和本文件的快照；如仍不确定，保持拒绝并写清下一份所需证据。

## 10. 官方许可参考

- Sound Transit Open Transit Data 条款：<https://www.soundtransit.org/help-contacts/business-information/open-transit-data-otd/transit-data-terms-use>
- Sound Transit 网站内容条款：<https://www.soundtransit.org/help-contacts/business-information/terms-use>
- SBCTA Redlands Passenger Rail item metadata：<https://www.arcgis.com/sharing/rest/content/items/e87f93d1d8e9441f8593be26a80d4f99/info/metadata/metadata.xml?format=default&output=html>
- SBCTA GIS portal：<https://www.gosbcta.com/gis/>

许可会变化。每次重新下载前都应复核具体 dataset/item 的条款，并更新本机 receipt；不能只依据门户首页或这份文档的旧结论。
