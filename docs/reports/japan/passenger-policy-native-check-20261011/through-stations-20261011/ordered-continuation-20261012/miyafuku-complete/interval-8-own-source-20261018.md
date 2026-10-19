# 宫福 #8 公庄西侧：自有来源与有界显示提案（2026-10-18）

**已有明确自有客运轨道支持；建议单一旧解码窗口 v4…v32 作为后续显示修复候选。** 只冻结来源/计算/片段，没有改生产或执行候选，没有 native/build/apply。#12 福知山终站未证实项完全排除。

精确 owner：`jp-WILLER　TRAINS-宮福線#8`，公庄004911→下天津004948。此前全部补采原图已查看；北偏弧段最清楚的是 `/private/tmp/jtm-miyafuku-missing-20261018/alignment/captures/000001/000001/smooth.png`、`000002/smooth.png`、`000003/smooth.png` 及各自 basemap。此次不再把蓝色标签线当作自有轨道归属依据。

## 原始 N02 与当前输入

`app/data/rail-sections.json` 的精确 own feature19849：class12、宮福線、`WILLER　TRAINS`，54个点；它的反向坐标序列与本次 `alignment-geometry.json` 的 #8 display[1…54] **完全一致**。当前56点的首尾是自己的站点锚点，且没有 display override。feature19846为公庄站侧原始片段，一并冻结。故北偏弧段已经存在于自己的 N02 原始表示，不仅是平滑显示制造的偏移。冻结文件 `interval-8-own-source-20261018/raw-n02-and-own-input.json` 同时保留原 feature、当前自有输入与站点身份。

## 归属明确的同一客运链

先从既有 E135N35 缓存中按宫福名称/operator及此局部位置找到已知 own ways，再仅获取下面9个精确 way 的 OSM API full 响应以及44001348的直接 relations。没有新 bbox/Overpass 获取、最近轨道匹配或跨线混合。每条 full 均含当前版本、时间和版本化 node；全部9条当前坐标与2026-08-18缓存完全一致。原始响应、精确URL、对象版本和局部文件SHA保存在 `source-provenance.json`，缓存摘录保存在 `cached-own-ways.json`。

按本线东→西/西南顺序：

| Way | 当前版本 | 特征 |
|---|---:|---|
| [44001348](https://www.openstreetmap.org/way/44001348) |12|宫福客运，非service支线|
| [44001349](https://www.openstreetmap.org/way/44001349) |9|bridge=yes，客运|
| [1137778624](https://www.openstreetmap.org/way/1137778624) |1|客运连接|
| [32055918](https://www.openstreetmap.org/way/32055918) |13|tunnel=yes|
| [1137778621](https://www.openstreetmap.org/way/1137778621) |1|bridge=yes|
| [490130188](https://www.openstreetmap.org/way/490130188) |6|客运连接|
| [1137778623](https://www.openstreetmap.org/way/1137778623) |1|bridge=yes|
| [1137778622](https://www.openstreetmap.org/way/1137778622) |1|客运连接|
| [32055924](https://www.openstreetmap.org/way/32055924) |11|tunnel=yes、layer=-1|

所有way均为 railway=rail、gauge1067、usage=branch、passenger_lines=1，明确标注京都丹後鉄道宮福線及京都丹後鉄道 operator，无 service=siding。相邻 way 的精确端 node ID 相同，按 node 连成一条链，而非坐标近邻推定。

同一9条全部为 [railway relation6014983 v39](https://www.openstreetmap.org/relation/6014983) 的连续成员61…69；亦为明确 [宮津→福知山 train route12018222 v19](https://www.openstreetmap.org/relation/12018222) 连续成员105…113，以及 [福知山→宮津 route12030449 v9](https://www.openstreetmap.org/relation/12030449) 连续反向成员60…68。route-identity.json保留精确成员索引/角色。OSM使用京都丹后铁道品牌；自己的compact使用WILLER身份。这些名称、客运方向、同一连续成员与1067轨道共同支持本宫福走廊归属；不是将邻近JR/宫津线吸附进来。

OSM自身仍标KSJ2/2007来源，**不是独立测量的隧道中线**。隧道部分不应拿表面街道或卫星表面替代；此处只提出有明确自有归属、与原图走廊差异相符的显示参考。

## 唯一建议窗口及护栏

repo `jp-manual-corrections/geo.mjs:projectPointOntoPolyline` 对这条精确自有链作边界投影；haversineM给局部段长，局部lon*cos(lat)向量给转向。完整备选边界计算在 `geometry-comparison.json`；唯一拟采用的片段在 `candidate-fragment.json`，含原物理compact row、两端站点rows、旧56点、替换点和完整候选52点。没有引入新修复框架或ruler mapper。

- **保留 raw0…3**，包括公庄站0和前邻v3 `[135.12774,35.3711]`。
- **替换 raw4…32**：起界原v4 `[135.12726,35.37089]` 投影为 `[135.1272674478895,35.37087982930974]`，偏距1.31721m；终界原v32 `[135.11712,35.3676]` 投影为 `[135.11708989212326,35.36762622783204]`，偏距3.99480m。中间严格使用上述自己的有序源节点。
- **保留 raw33…55**，后邻v33 `[135.11655,35.36721]`及下天津站55不动。其他区间与物理源/站点均不涉及。
- 四个接点/护栏转角：前邻1.61544°、新起点1.09956°、新终点0.28352°、后邻5.31508°。对应新起界前段49.3478m/后段90.7099m；新终界前段203.1221m/后段67.3693m，无为了拼接插入的极短垂直offset腿。全候选最大转向9.55941°，位于自己源节点 `[135.1205131,35.3698988]`。
- 原raw窗口长1027.17065m，源参考替换1040.97397m；整个自有区间haversine长度2311.29187→2324.95375m。这些是局部几何比较，**不是native ruler**；如实施必须仍用现有partRowsForLine及实际metadata审查生成native数据。

最大旧控制到该自有链的差29.12960m在v11附近，与原图公庄西侧北偏弧段对应。建议边界不是硬offset阈值决定：较窄4…24/4…25会分别产生22.4000°/21.7341°的新南接点，4…28仍有12.6335°；到32才在同一明确隧道源段上平顺接回保留后缀。起点推到5/6也更差，保留的旧北偏控制使护栏/起界转向增大。v33已超出此次取得的源链末端，其clamped投影不应被解释成真实偏距证据，因此未扩展到那里。

## 可交付与仍未证实

这个片段足以交给现有单一数据修复authority建立可审查候选：只有#8的4…32显示变化，物理compact/站点/相邻区间冻结。还没有source实现、生产apply或新native图；需要render后确认自己的曲线及两端过渡，不能把源几何的小转角直接当作pixel/Main验收。不得把#12福知山终站问题混入，亦未证明公庄/下天津自有站台中心或任何物理连接。
