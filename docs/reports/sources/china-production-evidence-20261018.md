# China passenger identity and Guangzhou–Shenzhen–Hong Kong evidence

Evidence acquired 2026-10-18. Source records are in
`railway-sources/local/china/evidence/official-20261018/`.
This note records facts and reviewed joins; it does not certify unpublished national line memberships.

## Official national station identities

The current official [12306 station resource](https://kyfw.12306.cn/otn/resources/js/framework/station_name.js)
contains **3,404 records**. The fetched official [station-query page](https://kyfw.12306.cn/otn/czxx/init/)
loads this exact resource (its station-version query string is 1.9376).
`12306-national-stations.json` retains every raw field and extracts the source's
Chinese name, three-letter telecode, pinyin and initials. The raw JS is retained;
it has not been evaluated as code. There are no coordinates in this publication.
Being offered in the passenger interface is identity evidence, not a per-line
station-order table or proof that every selectable item is currently served.

## Complete Guangzhou–Shenzhen–Hong Kong HSR passenger sequence

The retained [MTR English passenger guide, page 2](https://www.highspeed.mtr.com.hk/res/pdf/Service_Guide_EN.pdf)
shows the seven-station short-haul corridor in the reverse order to this table.
The page was visually inspected; `mtr-service-guide-en-page2.png` is a local
render of the actual downloaded PDF page. The PDF is image/vector based and
`pypdf` text extraction yields empty page text. Search-engine extraction had
an older 96-destination count; the actual retained page says 114. The relevant
station sequence agrees, but cached search text is not the retained publication.

| Sequence | Current official name | Official telecode | Original OSM station node | WGS84 longitude | WGS84 latitude |
|---:|---|---|---:|---:|---:|
| 1 | 广州南 / Guangzhounan | IZQ | 3677030154 | 113.2640375 | 22.9914143 |
| 2 | 南沙北 / Nanshabei | QSQ | 8385846445 | 113.4852438 | 22.8687149 |
| 3 | 虎门 / Humen | IUQ | 7063297019 | 113.6682891 | 22.8632157 |
| 4 | 光明城 / Guangmingcheng | IMQ | 7103617869 | 113.9499003 | 22.7355800 |
| 5 | 深圳北 / Shenzhenbei | IOQ | 5369745039 | 114.0239469 | 22.6120365 |
| 6 | 福田 / Futian | NZQ | 2310688619 | 114.0511799 | 22.5413178 |
| 7 | 香港西九龙 / Hong Kong West Kowloon | XJA | 7919700008 | 114.1649267 | 22.3036814 |

The table's telecodes and simplified Chinese names are copied from the official
12306 identity records. Order and English labels come from the MTR guide.
`guangzhou-shenzhen-hongkong-stations.json` holds the normalized records and
source references. This is the complete passenger-station sequence of that
corridor; the MTR guide's second route via Dongguannan/Changping/Dongguan/
Guangzhouxintang to Guangzhoudong is a different route, not intermediate
stations to insert between these seven.

The [Guangzhou Transport Bureau notice dated 2025-10-14](https://jtj.gz.gov.cn/xwdt/gzdt/content/post_10483759.html)
states that 庆盛 became 南沙北 on **2025-10-11**. It separately records 新塘
becoming 广州新塘. QSQ therefore retains the current 南沙北 identity; 庆盛 is an
old name, not a second station. The neighboring Guangzhou Metro station is still
named 庆盛 and must not be substituted for the national-rail station.

## Coordinate evidence and identity review

`osm-corridor-stations.json` is an original Overpass response with node IDs,
versions, edit timestamps and untouched tags/coordinates. Its OSM snapshot is
**2026-07-28T02:16:18Z**, although fetched on 2026-10-18. The query and endpoint
are retained in `osm-corridor-stations-query.txt`. The first endpoint TLS failed
and two mirrors rejected POST; a read-only GET to
`https://overpass.private.coffee/api/interpreter` succeeded.

The seven selected objects are `railway=station`, `train=yes`. Each is a reviewed
name identity in this one bounded corridor, not a proximity join. 香港西九龙
matches the OSM `name:zh-Hans`; the other six match the native `name` directly.
The raw response also retains the adjacent metro/intercity objects deliberately
excluded: Guangzhou South metro platforms, Shenzhen North metro platforms,
Futian metro, Humen metro, Humenbei, Humendong, Qingsheng metro, and Guangmingcheng
metro. Several OSM nodes have a five-digit `railway:ref`; these are preserved
but are **not** misinterpreted as the three-letter 12306 telecodes.

Coordinates are original [OSM WGS84 data](https://wiki.openstreetmap.org/wiki/Converting_to_WGS84),
with [OpenStreetMap attribution and ODbL](https://www.openstreetmap.org/copyright).
No commercial-map coordinates, inverse-GCJ approximations or CRTrainRoute
12306 positions enter these records. These are station positions useful for
datum probes and identity review; they are not claims about a platform or track
center. The physical builder must derive its track anchors and actual ordered
geometry from original connected OSM ways/nodes. The national PBF may be newer
than this response; preserve that source distinction.

## Operating status, boundary and ownership

The current [MTR destination page](https://www.highspeed.mtr.com.hk/en/ticket/destination.html)
documents active service, MTR Vibrant Express and Mainland-operated trains.
Its retained page states that its information is effective 2026-09-27. This
supports passenger operation and shared service operators; it does not establish
one sole legal infrastructure operator for the whole cross-boundary corridor.

The [Hong Kong Highways Department project record](https://www.hyd.gov.hk/en/our_projects/railway_projects/xrl/index.html)
describes a dedicated underground corridor of about **26 km**, West Kowloon to
the national network through Futian, opened to passengers **2018-09-23**.
The [MTR introduction](https://www.highspeed.mtr.com.hk/en/about/hsr-intro.html)
independently describes the 26 km Hong Kong section. Do not use 26 km for the
entire seven-station Guangzhou–Hong Kong corridor. No surveyed boundary point
or exact whole-corridor distance is asserted by this record.

User partition rule: **the whole HSR corridor, including the Hong Kong section
and XJA, belongs exclusively to CN**. This is a product region partition, not
a claim that the Hong Kong section is geographically outside Hong Kong. Other
Hong Kong rail remains HK, and Macau LRT, including Hengqin, remains MO.

## Existing HK duplication check

A targeted read of `app/public/rail/hk-2025.json` found 28 lines: Airport Express,
Disneyland, three East Rail branches, Island, Kwun Tong, eleven light rail
services, South Island, Tung Chung, two Tseung Kwan O branches, Tuen Ma, Tsuen Wan,
and four tram services. None is XRL/HSR. A targeted term search for 西九/高鐵/
高速/West Kowloon/XRL/hkwest in that compact file and `app/data/rail-sections-hk.json`,
`stations-hk.json`, `station-readings-hk.json`, `station-names-hk.json` returned
no matching records. Austin and Kowloon remain separate HK local-rail identities;
[MTR describes the connections as pedestrian links](https://www.highspeed.mtr.com.hk/en/guide/wek.html),
which cannot authorize a track junction or shared station ID with XJA.

## Focused verification result

Reviewed the downloaded official station-query page's resource link; parsed
3,404 raw records without executing JS; checked the exact seven official
telecodes; visually checked the MTR seven-station sequence; inspected every
selected OSM object and excluded neighboring metro/intercity objects; searched
the relevant existing HK solver/display inputs. `manifest.json` records source
URLs, byte counts and digests for these retained evidence files only. No app
build, full data matrix, retired verifier or upstream pickle execution was run.


## Further national passenger-order source investigation

The official station-query page loads
[`czxxcx_js.js`](https://kyfw.12306.cn/otn/resources/merged/czxxcx_js.js?scriptVersion=1.95054).
The retained source implements `czxx/query` for station/day passenger trains and
`czxx/queryByTrainNo` for their ordered stops (`station_no`, `station_name`,
arrival/departure times). The explicit request fields are preserved in that
source. Two focused public `czxx/query` requests for XJA and IZQ on 2026-10-18
returned HTTP 404; they supplied no operating records. No authentication or
captcha bypass was attempted.

The official static
[`train_list.js`](https://kyfw.12306.cn/otn/resources/js/query/train_list.js)
is still publicly downloadable, but the **actual retained contents are dated
2022-08/09**. It contains train-number/internal-ID/endpoints, not every stop.
It is retained as evidence of this rejected discovery route and must not be
promoted to a 2026 timetable or national station-order authority. The national
3404-row station identity publication is current (including the 2025 Nanshabei
rename); it remains useful independently of the stale train list. National
physical line station-order and passenger eligibility still require the PBF's
original route/rail infrastructure identities plus appropriate operator facts,
rather than inheriting a 2022 service list or treating timetable shortest paths
as railway topology.


## 2026-10-19 续修

正式CN资源与数据库镜像已更新至3,991条路径、17,594区间、21,573站点成员、2,715官方代码；原始同节点连接3,690条，另有两条原始轨道审核连接，其他地区203条原值保留。四项站点版本／关系审核见`railway-sources/china-reviewed-stations.json`，原始证据、未接通原因及完整176项回放见[真实车次报告](china-real-train-paths-20261018/README.md)。没有放宽站轨吸附、原始节点或跨地区约束。


### 2026-10-19：三处联络路径正式接入

通过既有 N02 物理区段契约接入六段原始路径（372 条相邻边、四个新增独立轨道身份），包括京沈联络线及京哈原身份引入段、昆明南联络线及单独命名的南昆—昆玉渡线、新会—江门及江海—江门东遗漏主线。未增加虚构客运站，既有站序和严格站轨源锚点不变。九个新增接点全部共享同一原始 OSM 节点；203 条其他地区接点保持一致。运营者、客运用途和原始关系成员证据见 [复核记录](china-real-train-paths-20261018/three-connectors-source-review.json)。昆明渡线运营者为明确标注的官方资料复核推断，不冒充源 way 标签或法律所有权。广州南尚无原始连续证据的跨站台路径继续拒绝接入。真实88车次重放结果以该目录 README 最新章节为准。

最终同批88车次×两模式重放于2026-10-19T07:44:15Z完成：完整候选13→14/88，强制停站返回几何538→542/1,010；原仓库仍为49/88与756/1,010。C293已完整，G101与G6045虽返回全部区段几何，仍分别保留沈阳北、广州南站台边界断点。源身份显示与CN缓存修复消除昆明地铁误标；551个旧源几何部件坐标完全保留。0结构失败、704项审阅不等于全部路径认证。聚焦回归及最终独立输出复核通过，串行窗口已归还。详见[最终报告](china-real-train-paths-20261018/README.md)。


### 2026-10-19：平台边界继续取证与 D271 正式补齐

新增八段有原始关系、逐边版本及运营者／客运用途证据的物理补段和三个真实站点绑定，保留全部旧站点及紧凑客运库；原始补充路径现为14段／2414相邻边。D271达到14/14段几何、13/14内部连续（原仓库9/14），D239为6/7几何、5/7内部连续（原仓库3/7）；攀枝花南缺证边界仍保留。广通北自身客运way前三边已正式接回。广州南、沈阳北缺证连接没有降低标准接入；沈阳北扩展追查在哈牡线遇到无原始关系成员归属的way，也未用新契约绕过。

最终同批176项于2026-10-19T08:50:40Z完成，强制停站几何542→552/1010、内部499→507、完整候选14/88不变；原仓库仍756/1010与49/88。0结构失败、714项审阅。旧556部件零丢失，554坐标数组完全一致，另两部件仅增加原始前缀／同节点重复点、保留全部旧坐标。21项聚焦回归及独立实际输出复核通过，运行窗口已归还。局部覆盖改善不构成总体更优结论。详见[最终结果与源证据](china-real-train-paths-20261018/README.md)。
