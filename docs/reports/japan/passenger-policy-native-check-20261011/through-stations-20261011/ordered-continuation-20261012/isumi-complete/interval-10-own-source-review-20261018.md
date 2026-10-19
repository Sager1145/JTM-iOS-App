# いすみ#10 黒原北侧偏弧：本线来源与单一候选

2026-10-18，仅做本线#10 久我原005236→総元005257的局部来源研究。重新实际查看补采`alignment/captures/000000/000002`、`000003`的basemap/smooth四张原始PNG，确认北侧弧段红线位于蓝色Isumi Line西侧。保留真实大弯和跨河方向；#12独立疑点不纳入。

## 轨道及乘客路由归属

缓存`railway-sources/local/osm/degree-cells/E140N35.json`，fetchedAt `2026-08-18T10:43:41.438Z`，在明确局部范围找到way1236719220。其标签为railway=rail、operator=いすみ鉄道、name=いすみ鉄道 いすみ線、gauge=1067、usage=branch、source=Bing，无service侧线标签。最新[way1236719220/full](https://api.openstreetmap.org/api/0.6/way/1236719220/full.json)为v2、2024-10-08；23个节点的坐标与缓存完全一致。

[该way直接关系](https://api.openstreetmap.org/api/0.6/way/1236719220/relations.json)给出明确乘客铁路归属：train route5748913 v8（大原→上総中野，own member49）与反向16928972 v3（member24），均为いすみ鉄道。铁路relation18138001亦包含它。正向局部链为`1322061008→1236719220→287004073→287004072`，反向顺序一致。候选只采用一条同一路由连续链`1236719220→287004073→287004072`，没有平均或最近蓝轨替代。

为找到自然的南端接缝，读取已被上述train route明确列出的相邻[桥梁way287004073](https://api.openstreetmap.org/api/0.6/way/287004073/full.json)（v3，2020-05-02，bridge=yes）及[后继287004072](https://api.openstreetmap.org/api/0.6/way/287004072/full.json)（v4，2024-01-03）。前者与1236719220共节点1831218899，后者与桥梁共节点1831218897；均带相同本线运营商/名称，fresh几何均与缓存相同。只获取这三个已识别way及第一way的直接关系，未广域搜索。

这些记录证明的是本线既有乘客铁路走廊身份，**不证明当前正在开行列车**。当前package的`serviceStatus=substitute_bus`、`serviceSpans=[[0,13,2]]`保持原样；OSM train关系是2024年记录，不覆盖现行运营状态，也不是测量级中心线证明。

## raw N02与单一冻结窗口

当前raw来源为`app/data/rail-sections.json`零基feature66：N02_001=12、N02_002=5、N02_003=いすみ線、N02_004=いすみ鉄道，43个坐标。反转后与#10的decoded1…43逐点完全相同，前后加站锚得到当前45点；无display override，原始stored mileage为1.47km。raw物理坐标、公里、车站和拓扑全部保留。

推荐仅一个display候选：**替换decoded13…34（22旧点）为26点，得到49点区间**。外侧raw guard12 `[140.24713,35.24684]` 与35 `[140.24273,35.24085]`及所有窗口外点完全保留。片段采用上述同一路由原始支持点，边界由仓库`jp-manual-corrections/geo.mjs::projectPointOntoPolyline`冻结：

- 北边界原13 `[140.24674,35.24659]` → `[140.24673043030057,35.24660063325639]`，距离1.467m。
- 南边界原34 `[140.24292,35.24095]` → `[140.24293593282152,35.240926104492296]`，距离3.026m。

原偏弧20…27相对这条明确自有链的距离约7.13…23.42m，峰值在22；这是**来源坐标差**，不是量得的Apple像素残差或实际误差。窗口延伸到13和34，是为了接缝自然回到保留的真实曲线，而非使用任意距离门槛：19…27候选会在南接缝产生16.59°折角；16…29仍有14.25°；13…32出口8.30°且在斜弯中提前接回。13…34出口4.23°、下一guard0.047°，北guard5.14°/入口0.054°；局部最大7.79°来自自有参考真实曲率。两侧接段长45.00m与20.53m，没有极短横向补腿。延伸到35不会改变局部最大值，却多移动一个已接近来源的原控制点，因此不选。桥梁及后继way仅用于同一局部弯道的自然接回，不更改桥梁物理记录或平台。

## 留存与限制

全部raw N02片段、三份fresh versioned way/full JSON、原始relations响应、各自缓存摘录、接缝计算及唯一`candidate-fragment.json`在`interval-10-own-source-20261018/`。后者冻结原compact row、45点baseline、精确guard、26点fragment和49点候选；不含#12修复。`bounded-source-calculation.json`保存相邻接缝比较摘要。

未实现builder、未审计native part/ruler依赖、未export/apply生产候选，未启动app/native/build/tests。候选没有新原生像素，尚不能称修复通过。后续实现前须具体核对本线native parts和引用owner；渲染须查看弧体和两侧接缝。此次只给出有明确本线train成员身份的显示参考，未宣称surveyed centre、站台face/cap、道岔、当前运营状态或新物理线路。

## 已实现的候选与实际引用审计

后续授权实现于单一`app/scripts/railway/repair-isumi-kurohara-display.mjs`、对应evidence及聚焦test。source字节仅针对已识别四份API文件冻结；way/version/node记录、双向train成员链、raw feature66、原45点、窗口和投影都带严格guard。current own line仅接受原baseline或本候选，其他线路按输入原样保留。

实际`display-lanes.json`中本线parts/byRegion/follows（含作为其他线host）/family/hub/loops/reverse/boundaries/releasedIntervals均无记录；唯一自身记录为`strokeExcludedByRegion.jp=[lineID,"substitute_bus"]`。shared-corridors的corridors/displayLandlords、display-releases及physical-rail-junctions没有本线外部依赖；已按现有具体字段冻结空基线，apply前同时检查这些来源快照。没有猜测或新增native生产行，也不解除服务排除。`repairParts`因此验证自身引用后保持整份lanes语义不变。

复用`partRowsForLine`实际计算的显示接口行（**仅接口，不是当前渲染生产行**）为588点/26944.3m→592点/26937.3m。测试确认`displayPartsForLine`的坐标确实包含49点新片段，而非仅更新vertexCount。Python counterpart3083使用displayIntervalCoordinates，同时3152–3185按既有strokeExcludedByRegion走非continuous分支；未运行Python/nativebuilder或Main。

先观察同一聚焦文件3/3失败，再实现并最终3/3通过（126.75ms），覆盖display窗口与外点/其他线路/物理/替代巴士记录保留和幂等、既有接口真实坐标/ruler与排除行不增、stale来源/route/node/rawguard/投影及所有已审计引用类别拒绝。现有helper`refreshDependencyReferences`只刷新四个既有站名依赖文件；`applyPreparedWrites`保存来源/evidence/raw/外部参考快照。

唯一候选目录`/private/tmp/jtm-isumi-kurohara-candidate-20261018`已export成功。定向数据对照确认其他线路精确相同、本线除display10外全部物理/服务/元数据精确相同、lanes整份语义相同；没有生产apply或新native图片。机器结果见`interval-10-implementation-20261018.json`。

命令：

```sh
node --test app/scripts/railway/tests/isumi-kurohara-display.test.mjs
node app/scripts/railway/repair-isumi-kurohara-display.mjs --candidate-root /private/tmp/jtm-isumi-kurohara-candidate-20261018
```
