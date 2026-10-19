# 花轮 B 组短肩显示候选（2026-10-19）

**candidate-not-applied**。实际查看父新采集 z19 p0/p1 的全部 2 对／4 张 basemap+smooth 原图后，支持仅将 `jp-わたらせ渓谷鐵道-わたらせ渓谷線#8` 的旧 decoded **v5 `[139.30941,36.52174]`** 从显示链删除。保留更贴近明确自身来源的 v4 `[139.30938,36.52174]`、v6 `[139.30943,36.52175]` 及其余全部点。不是横移、不是物理或站点更正；A 组 v2/v3 明确保留待证。

此为 `hanawa-step-own-source-review-20261019.md` 初次 z17 研究后的新证据；该报告“minimal deletion unresolved”描述旧 z17 阶段，历史保留。新四图及 view 已冻结在同 sourcefolder 的 `detail-p{0,1}-{basemap,smooth}.png` / `detail-p{0,1}-view.json`。完整实际绝对路径及像素定位在 `detail-z19-viewed-originals-and-control-pixels.json`。

相机2 mapPoints/point，约0.239m/point。p1 A v2/v3=(927.193,516.299)/(945.835,511.660)；B v4/v5/v6=(1031.585,451.349)/(1042.770,451.349)/(1050.226,446.710)。p0 B=(1426.349,177.828)/(1437.534,177.828)/(1444.991,173.189)。两图均能区分两组红短肩，自有蓝细轨连续，没有与 B 纯东向腿对应的折台。只删 v5 的几何变化0.647m，保留前后 guards，未顺便抹掉 A 或东北真实弧。此前确认的自身 N02 feature269、OSM24373800v8 /925516063v3、共享花轮 stop264461333 和 railway relation1949287v42 作为归属支撑；不把共源KSJ2 OSM称独立测量，也不从 stop_position 或站点填充改站台中心。

## 单一 authority 与依赖

新增 `app/scripts/railway/repair-watarase-hanawa-step-display.mjs`，唯一 active geometry 是现有 `displayIntervalCoordinates[8]`，等于 frozen 原区间仅去掉索引5；physical segments、stations、km、所有其他区间和其他线路精确保留。旧/已修状态只接受 frozen baseline 或 exact proposed，provenance 有界记录。JSON source bytes、两原相机身份、N02整特征映射、版本及共享自身节点被守卫。

native 复用 `network.displayPartsForLine` 和既有 `partRowsForLine`；原部件为 `station-approach/groomed`，不是 plain range。聚焦回归确认新完整 groomed 坐标链 **恰好只删原 v5**，其余 grooming 逐点不变。native 单 part **1033/44208.7m → 1032/44208.5m**，kind不变，byRegion只有全长终点更新，lane −0.5 不变。

审阅实际 known schemas：parts/byRegion各一条；follows拥有者与被跟随角色均空；family、loops对象、reversed strings、hub成员、strokeExcluded、chainBoundaries、releasedIntervals均空；color/renderGroup/renderGroupPolicy ownMaps null；excluded operator/line未选本线。外部 shared corridors.lineIds/members、displayLandlords tenant/landlord、shared excludedLineIds、display releases.lineId、physical junctions.lineIDs 本线均空，CLI守卫且纳入apply快照。无未知键递归扫描、通用框架或平行 runner。

JS `displayPartsForLine` 通过 `displayLineForCoordinates` 消费现有 displayIntervalCoordinates；Swift `CompactPackage.swift` 的既有 decodeDisplayIntervals 同样消费该字段，物理 decode 保持原线。没有新增客户端渲染例外。

## 许可内聚焦验证及导出

仅执行本次原focused回归：

`node --test app/scripts/railway/tests/watarase-hanawa-step-display.test.mjs`

RED：1/1按预期失败 `B east shoulder remains`，日志 `/private/tmp/jtm-watarase-hanawa-step-red.log`。GREEN：**1/1通过，0failed，143.0ms**，日志 `/private/tmp/jtm-watarase-hanawa-step-green.log`。同一测试覆盖 A/v4及全余点、物理/站点/km不变、groomed chain仅删一坐标、无关行保留、重放、source变更拒绝、实际loop/reverse/family及follows双角色新增依赖拒绝。

导出沿用现有 refreshDependencyReferences + applyPreparedWrites authority 路径：

`node app/scripts/railway/repair-watarase-hanawa-step-display.mjs --candidate-root /private/tmp/jtm-watarase-hanawa-step-candidate-20261019`

导出六个现有package/lane/reference文件；日志 `/private/tmp/jtm-watarase-hanawa-step-export.log`。没有 `--apply`、build、native 或 UI。候选尚待父在实际 native 中检查完整区间和两侧 guards；A、站台面及其他区间不因这次点删除获得接受。
