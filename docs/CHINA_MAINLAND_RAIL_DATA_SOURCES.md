# 中国大陆铁路数据源调查（`cn` 包可行性）

调查时间：2026-08-31 / 09-01（UTC）
调查者：一个只做**只读调查**的会话，没有改动任何数据或构建器
适用对象：将来真的要做 `cn-2025.json` 的人或 agent

这份文档只记录**这一轮实际测过的东西**：查了哪些源、用什么命令查的、量到什么数字、
据此能不能进本仓库的几何权威阶梯。凡是没有实测的，明确写成"未验证"。

---

## 0. 结论

**能建，但只有一条路线是可执行的**：`OSM 几何 + 12306 客运站名录 + 官方运营数据做清单校验`，
与 `kr` 包的做法同级（`kr` 的几何本来就来自 OSM 而不是官方实测，见
`kr-2025.sources.md`）。中国官方的测绘数据在**精度**（1:100 万）或**授权**
（《地图管理条例》、地图审核）上都不满足本仓库的可再分发要求，进不了阶梯第 1 级。

关键实测结论：

| 问题 | 实测答案 |
| --- | --- |
| OSM 里有没有中国的线路清单？ | 有。`route=railway` 关系 **2,078** 条（京广线、京沪高铁、兰新客专线…），城轨 `route=*` 关系 **1,003** 条 |
| OSM 城轨覆盖是否接近官方清单？ | 接近。OSM `station=subway` 站点 **6,595** 个 vs 中国城市轨道交通协会 2025 年底口径 **6,680** 座 |
| OSM 坐标是不是真 WGS84（没被 GCJ-02 污染）？ | 是。北京 25 条线 502 个站，OSM 与"高德 GCJ-02 反算回 WGS84"的中位差 **30.9 m**、p95 181.5 m |
| 站点身份怎么定？ | 12306 官方码表 3,384 个客运站，**96.7%** 能按中文站名精确命中一个 OSM 站点节点 |
| 干线几何能直接用吗？ | 不能直接用。`route=railway` 关系里**上下行两条线都在**（长度约为官方营业里程的 2 倍），且成员未排序 |
| 线路颜色能从 OSM 取吗？ | 不能当权威。北京 23 条线**没有一条**颜色与高德完全相同（19 条同色系） |

---

## 1. 判定标准（本仓库的硬要求）

来自 `.claude/skills/jtm-railway-audit-repair/SKILL.md` 与
`docs/NORTH_AMERICA_RAIL_OPTIMIZATION.md` 的几何权威阶梯：

1. 复核过的政府/运营商**实测中心线**（publisher + URL + raw/normalized SHA-256，且授权允许再分发）
2. 运营商**自己发布**的 GTFS shapes
3. 国家级测绘路网（FRA/BTS NARN、省级 ORWN 之类）
4. 署名的 OSM/OpenRailwayMap 几何（ODbL）
5. 都拿不到 → 不发布

另外，包本身要求：`compact-v1`、**canonical WGS84**、站点锚点与区间端点**完全重合**、
每条线要有 `id/name/operator/rank/color/nameRoma/stations/segments`、
`geometrySource` 带 `providers`/`license`/`sourceSha256`。
`nameRoma` 和站名罗马字需要一个**可署名的**读音源（日本用 N02，韩国用 data.go.kr）。

坐标基准方面 `cn` 是现成的：`ios/RailMap/AppleMapDatum.swift` 已经实现了公开 GCJ-02 正变换，
目前作用于 `tw, hk, mo, kr`。包内保持 WGS84、显示边界做 GCJ-02 —— 大陆走同一条路，只需把
`"cn"` 加进 `gcj02Countries`。**注意**：中国大陆的 Apple 底图同样是 GCJ-02（高德服务），
所以这不是可选项，不做的话整张网会整体偏移数百米。

---

## 2. 数据源逐项评估

### A. 中国官方 / 政府

| 源 | 内容 | 坐标 | 授权 | 实测 | 判定 |
| --- | --- | --- | --- | --- | --- |
| **全国地理信息资源目录服务系统**（webmap.cn）1:100 万公众版（2021 版，现势性 2019）| 含"标准轨铁路、窄轨铁路、地铁、轻轨"图层，77 幅 | CGCS2000 / 1985 高程 | 免费，但页面明写须"严格执行《地图管理条例》"，公开出版需"依法履行地图审核程序" | 页面已抓取确认（`curl` 被 418 拦，WebFetch 可读） | **不可用作几何**。1:100 万定位误差量级在数百米，画不了地铁；且再分发要过审图 |
| 同上 1:25 万公众版 | 同类图层，816 幅 | CGCS2000 | 同上 | 同上 | 同上，现势性 2015，更旧 |
| **天地图**（tianditu.gov.cn） | 国家级底图服务，WMTS/矢量瓦片 | **CGCS2000，未做 GCJ-02 加密**，与 WGS84 在 web 精度下等价 | 服务条款禁止批量爬取与派生数据分发 | 站点在本机无响应（疑似地域/UA 限制）；坐标系结论来自公开资料，**未实测** | **不能作为可分发数据源**，但它是**唯一未加密的官方底图**，做 WGS84 对位复核时是最好的参照 |
| **12306 车站码表**（`kyfw.12306.cn/otn/resources/js/framework/station_name.js`） | 3,384 个客运车站：中文站名、**三字电报码**（BJP/VAP）、**全拼**、简拼、所属城市 | 无坐标 | 公开 JS 资源，**无明示授权**，法律状态灰色 | 已下载解析，11 字段 × 3,384 条，430 个城市 | **强烈推荐做身份/读音源**（等价于日本 N02 站码、韩国 codePrefix）。但要先解决授权表述 |
| **国家铁路局《2025 年铁道统计公报》** | 全国营业里程 16.5 万 km，高铁 5.0 万 km | — | 政府公开信息 | 检索确认 | **清单校验用**（总里程量级核对），不含线路级几何 |
| **中国城市轨道交通协会（CAMET）统计报告** | 2025-12-31：54 城 / 343 条线 / 11,710.3 km / 6,680 座车站（国标口径）；另一全口径 58 城 / 382 条 / 13,071.58 km | — | 协会公开 PDF | 检索确认，PDF 在 `infosharingp2-oss.camet.org.cn` | **城轨清单的权威基准**。等价于台湾用官方营运里程表核对 |
| **各市公共数据开放平台**（上海 data.sh.gov.cn、深圳 opendata.sz.gov.cn、北京 data.beijing.gov.cn 等） | 深圳"交通运输"域有 141 个数据集 | 通常 GCJ-02 或地方坐标 | 需注册账号；各平台授权条款不一 | `curl` 全部被 WAF 拦（418/412/404）；**是否含线路几何未验证** | **待人工核实**。如果哪个市真的开放了 CGCS2000 中心线 + 明确授权，那条线可以升到阶梯第 1 级 |
| 各地铁运营公司官网 | 线网图、站点列表、首末班车 | 示意图 | 版权保留 | 未逐一验证 | **清单/站序/颜色的官方出处**，但不是几何 |

### B. OpenStreetMap 系

Geofabrik `china-latest.osm.pbf`：**1.59 GB**，`Last-Modified: 2026-08-31`（和 `kr` 走的是同一条路，
只是体量大 10 倍）。以下均通过 Overpass 对 OSM 中国区（area 3600270056，**含港澳**）实测：

```
route=railway 关系            2,078      route=tracks 关系                 9
route=subway 关系               799      route=light_rail 关系            89
route=tram 关系                  75      route=monorail 关系              40
route=train 关系                144
railway=station 节点         17,250      其中 station=subway            6,595
railway=halt 节点               182
way railway=rail usage=main 211,582      way railway=subway           30,105
```

城轨 1,003 条关系的标签完整度：**name 99% / ref 92% / colour 89% / from+to 90% / network 82%**，
`network` 有 64 个不同取值（约 50 个大陆城市网 + 港铁/轻铁/澳门轻轨），
去重后 534 个 `(network, 线名)` 身份。

**几何可用性实测**：

- **城轨**：北京 25 条线，OSM 关系 vs 高德，**20 条站数完全一致**；差异集中在新开段
  （18 号线 OSM 6 站 / 高德 11 站）。502 个同名站点的坐标差 **中位 30.9 m、p95 181.5 m、最大 430 m**。
- **不要走 way 层**：北京 `railway=subway` 的 3,266 条 way 里，**2,250 条是 `service=yard`**，
  144 条 crossover、95 条 siding，且只有 17% 带 name。线路与轨道的绑定只能靠 route 关系。
- **干线**：`京沪线 3,115 km / 官方 1,463`、`京广线 4,545 / 2,324`、`京哈线 2,481 / 1,249`、
  `京沪高铁 2,621 / 1,318` —— 全部约等于 2 倍，说明关系里**上下行两条线都在**；
  成员也未排序（相邻成员端点间出现 600 m–1,140 km 的跳变）。要出单条展示中心线，
  必须先分离上下行、再缝合排序，这正是 `build-korea-track-alignments.py` 那一类工作的加量版。
- **标签质量不均**：`京沪高铁` 关系上既没有 `highspeed=yes` 也没有 `usage=*`。

**OpenRailwayMap / Overture**：两者的中国铁路都派生自 OSM。Overture transportation 主题确实含
`subtype=rail`（class 覆盖 subway/tram/monorail/light rail），但其上游是 OSM + TomTom，
**整个主题按 ODbL 分发** —— 换 Overture 不等于换掉 ODbL 义务，只是换个分发格式。

### C. 商业地图 API（高德 / 百度 / 腾讯）

- **高德地铁数据**（`map.amap.com/service/subway?srhdata={adcode}_drw_{spell}.json`）：
  覆盖 **41 个城市**（含香港）。实测北京返回 27 条线 / 527 条站记录，每站带
  **真实经纬度 `sl`（GCJ-02）**、官方色 `cl`、简繁英三语站名。
  **但线路 `c` 字段是示意图坐标（"861 845"这种），不是地理折线** —— 全文只有 `sl` 一个字段含十进制经纬度。
  → 高德只能提供**站点锚点 + 名称 + 颜色**，提供不了轨道几何。
- **授权**：高德/百度/腾讯的开放平台条款都禁止存储、派生和再分发其数据。
  → **不能进包**。只能作为不入库的一次性对照（本次就是这么用的）。
- 坐标：GCJ-02（百度还叠一层 BD-09）。反算回 WGS84 有公开算法，本次实测中位偏差 30.9 m 说明反算是对的。

### D. GitHub / 社区 / 学术

| 项目 | 内容 | 判定 |
| --- | --- | --- |
| [`Ivysauro/CNRT`](https://github.com/Ivysauro/CNRT)（267★，GPL-3.0，2026-07 更新） | 中国轨道交通"非技术类"数据库（线路、开通日期等） | **清单交叉校验候选**，非几何；GPL-3.0 对数据再分发是个需要想清楚的问题 |
| [`NinaNaganohara/china-railway-map`](https://github.com/NinaNaganohara/china-railway-map)（2026-08 更新） | MapLibre + Flask + PostGIS 的中国铁路地图，含 12306 码表（与官方文件字节数完全一致：168,160 B） | **最接近的先例**，值得读它的 `map.js`；但线路/站点 GeoJSON 存在数据库里、仓库内不含数据，来源未标注 |
| [`scuzzk/AmapMetro`](https://github.com/scuzzk/AmapMetro) | 清洗高德地铁数据成 SHP/GeoJSON，覆盖大湾区 4 市（2024-09） | 上游是高德 → **授权不可用**；且它自己说明需人工逐条采集 |
| [`KevinJohnMulligan/AmapSubwayData`](https://github.com/KevinJohnMulligan/AmapSubwayData)（MIT） | 抓高德地铁 polyline + 中英站名 | 同上，MIT 只覆盖代码不覆盖上游数据 |
| [`GZUPA/subway-traffic-data-set`](https://github.com/GZUPA/subway-traffic-data-set) | 截至 2020-12-31 的大陆地铁数据集 | 太旧（五年前），只能做历史对照 |
| CSDN / 知乎流传的"全国铁路 shp" | 大量 2020 版"全国铁路矢量" | **一律不可用**：无出处、无授权、无现势性说明。本仓库的规矩是"来源声明是可检验的断言" |
| Nature *Scientific Data* 高铁网络数据集（2022） | 列车运行记录 + **相邻车站里程表** | **里程校验候选**（类似台湾 AFR 营业里程表的用法），需核对许可与现势性；本次未下载 |

### E. 跨界参考

- **Wikidata**（CC0）：中国铁路车站带坐标 **12,529** 个、地铁站带坐标 **6,706** 个、铁路线 **1,487** 条。
  地铁站数与 OSM 的 6,595 相互印证。**但**：中文维基的中国 POI 坐标历史上存在 GCJ-02 污染，
  用作锚点前必须先跟 OSM 做偏差分布检验（本次未做）。
- **Natural Earth 10m railroads**（public domain）：量级太粗，只够做国家级 sanity check。

---

## 3. 建议的 `cn` 权威阶梯

```
1. 政府/运营商实测中心线 …… 目前【空】。1:100万太粗、天地图不可再分发、
                            市级开放平台是否有中心线未验证 → 这一级要靠人工核实去填
2. 运营商自发布 GTFS ……… 目前【空】。大陆基本没有公开 GTFS（Transitland/Mobility
                            Database 均需 API key，本次未能验证；按已知情况视为无）
3. 国家级测绘路网 ………… 目前【空】（1:100万不够精度，不算数）
4. 署名的 OSM 几何（ODbL）… 【唯一可用】，与 kr 同级，必须在 sources.md 里明说
                            "几何非官方实测"
5. 都拿不到 → 不发布
```

配套的非几何数据：

- **客运站身份 / 罗马字**：12306 码表（三字码 + 全拼）→ `nameRoma` / `romaSource` / 站码前缀
- **城轨清单基准**：CAMET 年度统计（城市数 / 线路数 / 里程 / 车站数）
- **干线清单基准**：国家铁路局统计公报 + 各线官方通车公告
- **线路颜色**：必须建一张**注册表**（对应 NA 的 `osmLineColors`），逐城引用运营方线网图/VI；
  OSM 的 89% 颜色只能当占位，**实测 0/23 与高德一致**

## 4. 已知会咬人的地方

1. **站名重名**。12306 的 3,384 个名字里有 **252 个**能命中多于一个 OSM 节点，其中 **146 个**
   彼此相距超过 2 km（福田、花桥、青龙、合肥西…），必须用 12306 自带的"所属城市"消歧。
   地铁更严重：**491 个站名被多个节点使用**，奥体中心 ×15、会展中心 ×13、人民广场 ×10 ——
   这就是韩国 `중앙로` 那个坑，直接沿用 `kr` 的数字后缀方案。
2. **两套车站编码**。OSM 有 2,690 个节点带 `railway:ref`，但那是 5 位数字站码（北京 10001、济南 16295），
   **与 12306 三字电报码零重叠**。选一套做持久 ID，另一套只做别名，别混。
3. **新疆/西藏覆盖薄**。96.7% 命中率的那 112 个漏网站点高度集中在新疆
   （额敏、且末、莎车、阿拉山口、库尔勒、塔城、阿克陶、阿图什、策勒…）。这与"私自测绘在
   新疆西藏执法更严"的公开说法一致。这些走廊要单独立台账，不要拿直弦糊过去。
4. **`route=railway` ≠ 一条展示线**。它是整条走廊的轨道口袋：上下行、站线、联络线都在里面。
5. **上位法与上架风险**。私自测绘在大陆自 2002 年起违法；OSM 的中国数据在当地的法律地位本身是
   有争议的，而向中国大陆分发含中国地图的 App 通常涉及审图号问题。**这是产品决策，不是数据问题**，
   必须由人决定，不能由构建器"默认发布"。

## 5. 复现命令

```bash
# 全国 OSM 计数（各 1–4 分钟）
curl -s -X POST --data-binary @overpass-cn-count.ql https://overpass-api.de/api/interpreter
# 12306 码表
curl -s https://kyfw.12306.cn/otn/resources/js/framework/station_name.js
# 高德地铁（北京；仅作一次性对照，不入库）
curl -s "http://map.amap.com/service/subway?_1469083453978&srhdata=1100_drw_beijing.json"
# 中国 OSM 抽取
curl -I https://download.geofabrik.de/asia/china-latest.osm.pbf   # 1.59 GB, 2026-08-31
```

本轮的 Overpass 查询文件与中间结果留在会话 scratchpad
（`overpass-cn-count.ql`、`overpass-cn-2.ql`、`cn-subway-tags.ql`、`cn-stations.ql`、
`bj-full.ql`、`mainline.ql`），未落进仓库。

## 6. 未验证清单（下一步该做的）

- [ ] 上海/深圳/北京/广州公共数据开放平台注册后，逐个确认是否存在**带坐标的轨道交通线路中心线**
      及其授权条款 —— 这是唯一可能把 `cn` 的几何抬到阶梯第 1 级的路
- [ ] Wikidata 中国车站坐标与 OSM 的偏差分布（检验 GCJ-02 污染）
- [ ] 是否存在任何大陆城市的公开 GTFS（Transitland / Mobility Database 需 API key）
- [ ] Nature *Scientific Data* 高铁相邻站里程表的许可与现势性
- [ ] `NinaNaganohara/china-railway-map` 的线路 GeoJSON 到底来自哪里
- [ ] 12306 码表的授权表述怎么写才站得住
- [ ] 审图号 / App Store 中国区的合规结论（产品侧）
