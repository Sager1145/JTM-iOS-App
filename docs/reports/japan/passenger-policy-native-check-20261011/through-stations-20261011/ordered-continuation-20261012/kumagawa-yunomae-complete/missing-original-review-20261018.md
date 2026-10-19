# 湯前線 #2/#10 補采原图复核 — 2026-10-18

**已实际逐张查看13/13对、26张原图；两区间未发现可确权的假 V、孤立尖钩或错走邻线，本次不提出修复候选。** 保留真实河谷/跨河复合弯。细小侧差、站框纵向帽位和代表站台仍未证实，不能由这一结论扩大为全线或 Main 接受。

只读查看 `/private/tmp/jtm-kumagawa-yunomae-missing-20261018/capture-index.json` 实际路径：#2 東多良木009899→多良木009902，p0..6共7对；#10 肥後西村009922→川村009920，p0..5共6对。每张 basemap/smooth PNG 单独按原始 detail 打开，无缩略图/拼图替代，0未看/0缺失。现存 receipt 保持 pending、reviewFresh=false。

## 实际观察

#2 p0..3：东多良木站附近的宽缓曲线与跨支流后的西南斜直线连续，未见孤立 V、回头钩、断口或错入邻近道路/水渠。少量红蓝侧差存在，不能为追蓝而拉直真实曲线。p4..6：多良木站附近红线与图示铁路有侧向差异；站框/轨道上下文不足以核定完整平台帽位及代表客运面，因此不接受站点中心准确性，也不据此移点。p5/6 西南侧还可见相邻区间的一处很轻短肩，位于多良木终点以西南，当前证据不足证明是错误控制；不把相邻上下文强记为#2尖角修复。

#10 p0..5：肥后西村浅弯、球磨川/川边川合流区域跨河大弯、小纱手川附近的弯线和川村前直线连续。p1..4宽缓复合 S 曲线确实存在于本线图示，须保留，不能用直弦删掉。局部红蓝有小侧差，但没有明确新 V、孤立尖钩、错支线或持续离开自身走廊的证据。河上的蓝色铁路 glyph 不能证明桥梁现况、恢复工程或当前列车通过；本次没有相关运营认定。川村小站框的双帽和中心亦未单独核定。

## 身份、代行与证据边界

复用 `preparation-20261018.md`、`existing-evidence-20261018.json` 的 own 身份：14站/13区间，湯前→人吉温泉。旧 named plan 的13区间 source/display/station IDs 与准备时 current input 完全一致；原先79/92旧 receipt 可用，本次只补13缺口。**另79对旧原图本次没有逐张查看**，不把92张/对齐完成视为已全线像素接受；旧 fixed-z17-v2 与本次 render contract 也不同。

只读当前包2025.5.2确认 own `serviceStatus=partial_substitute_bus`、`serviceSpans=[[10,13,2]]`；display-lanes 的 `strokeExcludedByRegion.jp` 仍含 `[ownLineID,"partial_substitute_bus"]`。`partsByRegion.jp` 没有 own 显式行。既有 `byRegion.jp` 两行是 `[ownLineID,0,0,18956,-0.5]`、`[ownLineID,1,0,5850.5,-0.5]`；它们是包中现存 lane 元数据，不据此编造当前 active Main parts 或该停运段的有效列车服务。没有 displayStationCoordinates/displayIntervalCoordinates 覆盖。以上是内部元数据快照，不是最新官方运营状态核查；所有字段保持未改。

人吉温泉位于#12终端，不在这次#2/#10内。没有查看其自有平台原图，也没有把同名/近邻 JR 人吉站理解为同轨、同站台或可共享方向。该终端的独立自有身份、平台帽位与 JR 关系继续是未审范围。

本次实际采集 standard/light/z17，1600×1200，350m spacing，1.5pt isolated centreline。完整 own DisplayParts 平滑后裁切；无生产 lanes/follows/joins/family collapse。PID61534 的 result13/13、0failed只代表采集成功；whole-line render dependency `42e65800ef49bc0dc643bccdcb865382b95e9a64e5b2ae29ebc352649ec95022`。未控制 app/native、build、测试、apply或修改源码/生产数据。

## 精确实际查看清单

同名 `missing-original-review-viewed-manifest-20261018.json` 保存每张绝对路径、相机、实际快照投影、时间、named identity plan、dependency、逐视点观察和未修改的 receipt 状态。下表目录内的 basemap.png、smooth.png 均实际查看。

| 区间/point | 原图目录 | 观察 |
|---|---|---|
|2/0|`/private/tmp/jtm-kumagawa-yunomae-missing-20261018/alignment/captures/000001/000000`|東多良木 station/context and broad eastern curve are continuous. Red lies modestly south of the blue rail in places; no isolated V, gap or wrong corridor. Platform caps/centre unproved.|
|2/1|`/private/tmp/jtm-kumagawa-yunomae-missing-20261018/alignment/captures/000001/000001`|Own shallow bend across the Niwara River tributary context is continuous; no isolated V or short return hook. Preserve the real river/valley bend.|
|2/2|`/private/tmp/jtm-kumagawa-yunomae-missing-20261018/alignment/captures/000001/000002`|Own southwest diagonal and gentle approach curve are continuous, with small lateral cartographic differences; no wrong branch or acute false corner established.|
|2/3|`/private/tmp/jtm-kumagawa-yunomae-missing-20261018/alignment/captures/000001/000003`|Own southwest diagonal continues through road crossings toward Taragi; no gap or isolated V. Road/river crossings do not create inferred passenger junctions.|
|2/4|`/private/tmp/jtm-kumagawa-yunomae-missing-20261018/alignment/captures/000001/000004`|Taragi station approaches remain continuous. Lateral red/blue and station-frame differences are visible but not enough at z17 to establish the representative own face/caps/centre.|
|2/5|`/private/tmp/jtm-kumagawa-yunomae-missing-20261018/alignment/captures/000001/000005`|Taragi station area has a modest north-side difference from the blue rail band. A very slight short shoulder is also visible southwest of the station in neighboring interval context; no confirmed erroneous control or deletion proposed.|
|2/6|`/private/tmp/jtm-kumagawa-yunomae-missing-20261018/alignment/captures/000001/000006`|Taragi endpoint is continuous through its own station context. Full caps/representative face are unverified. The slight shoulder southwest of the endpoint belongs to adjacent context, not established as an interval2 false corner.|
|10/0|`/private/tmp/jtm-kumagawa-yunomae-missing-20261018/alignment/captures/000000/000000`|肥後西村 station/departure and genuine shallow bend are continuous; modest southward cartographic difference remains. No isolated V or wrong corridor.|
|10/1|`/private/tmp/jtm-kumagawa-yunomae-missing-20261018/alignment/captures/000000/000001`|Own broad compound curve toward the Kuma/Kosade river crossings remains continuous; preserve the real S alignment. No acute hook or gap.|
|10/2|`/private/tmp/jtm-kumagawa-yunomae-missing-20261018/alignment/captures/000000/000002`|River-crossing compound curve is continuous, with modest lateral red/blue differences. Map railway across water does not prove bridge condition or current train operation.|
|10/3|`/private/tmp/jtm-kumagawa-yunomae-missing-20261018/alignment/captures/000000/000003`|Own Kuma/Kawabe confluence crossing and turn into the Kawamura straight are continuous. No false V or neighboring railway substitution.|
|10/4|`/private/tmp/jtm-kumagawa-yunomae-missing-20261018/alignment/captures/000000/000004`|Kawamura approach and eastern/southern curve remain continuous. Small rail-band difference does not justify flattening the genuine curve or moving a station from this overview.|
|10/5|`/private/tmp/jtm-kumagawa-yunomae-missing-20261018/alignment/captures/000000/000005`|Kawamura endpoint/straight segment is continuous with the own small station frame. Exact platform caps/centre remain unresolved; no false corner candidate established.|
