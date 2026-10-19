# 北松江 #6 主阶梯显示候选（2026-10-19）

**candidate-not-applied**；只有 `jp-一畑電車-北松江線#6` 旧 decoded **v15、v17、v19** 删除。当前原区间实际 **61 点→58 点**。保留 v14/v16/v18、更远两侧 guards、其他全部坐标、站点、物理 segments/km，不新增坐标、不横移、不拉平后方真实湖岸弯。#11 不在本次 active 方案内；以后有证明时应扩展同一 authority。

## 后续近景实证

`interval-6-own-source-review-20261019.md` 为早期来源审查；其后父采集了准确新plan的 z19 p3/p4。此次实际逐张打开这4张原图：

- `/private/tmp/jtm-ichibata-kitamatsue-takanomiya-detail-20261019/alignment/captures/000000/000003/basemap.png`
- 同目录 `smooth.png`
- `/private/tmp/jtm-ichibata-kitamatsue-takanomiya-detail-20261019/alignment/captures/000000/000004/basemap.png`
- 同目录 `smooth.png`

两相机原 PNG/view 冻结于 `interval-6-own-source-20261019/detail-p{3,4}-{basemap.png,smooth.png,view.json}`。绝对路径、实际已看记录与逐点像素在 `detail-p3-p4-viewed-originals-and-control-pixels.json`。加上前阶段z17五对与z19新p1/p2两对，本任务实际已看9对／18张，不扩称全线。

p3/p4 自有明确标签蓝细轨斜向连续，红线主窗口有三次交替向南短阶。三处低点与正面自有来源相符的较高保留点相比偏向南，未有蓝轨对应台阶；删这些低点即可接回既有点，保留周围持续侧偏。

| 删除旧点 | [经度,纬度] | 到新仅删点链的最大点偏移m |
|---|---|---|
|15|[132.92675,35.47012]|1.732357|
|17|[132.92665,35.47007]|2.494396|
|19|[132.92657,35.47004]|1.895230|

新保留 v14/v16/v18 转角为0°/1.527327°/2.925039°，v20 11.094820°。数字只说明新支撑接续，没有以角度自动选点；选择依据是实际自有蓝细轨无阶梯、明确 own passenger chain 及保留邻点。v10/11和v24/25小肩、3–5m的宽范围偏移、随后v29..46真大弯均原样留待其自身证据。

## 唯一 authority 与真实依赖

新增 `app/scripts/railway/repair-ichibata-kitamatsue-display.mjs`、`ichibata-kitamatsue-display-evidence.json`、`tests/ichibata-kitamatsue-display.test.mjs`。复用花轮模式：geometry authority为现有 displayIntervalCoordinates[6]，严格 frozen baseline/已修 geometry 与 provenance 幂等；原始 N02 feature700反向=decoded1..59，原始源文件、Apple原图/view、own OSM版本/relations由既有字段与字节证据守卫，无邻轨snap。

当前 native 有两个parts，而非一条plain ruler：

- part0 `station-approach/groomed`：**548点/16321.2m→545点/16318.1m**。复用 network.displayPartsForLine + partRowsForLine；聚焦回归验证完整groomed坐标链仅删除上述3点，grooming其余点逐点一致。
- part1 plain interval9..20：**315点/17621.2m**，整行保持不变。
- byRegion本线为空，保持为空，不增加lane或station pin。

实际唯一 follows row 为 `[LINE,0,16150,16321.235570460749,LINE,1,150,0]`。source part0整个follow位于删除窗口以后的精确保留尾段（实现检查旧v20实际native位置和其链长早于16150）；target为未动part1。用现有native equirectangular米公式只算三组删前/后腿差，**δ=-3.157196431997794m**；新的source范围为 **16146.842803568003→16318.078374028752**，target `part1,150→0`不变。没有通用ruler mapper、按最近点映射或改折返拓扑。

follows拥有/被拥有两角色都按实际基线守卫；任何新入/出引用拒绝。实际family、loops对象、reverse字符串、hubmembers、stroke exclusions、chain boundaries、releasedIntervals为空；ownMaps color/renderGroup/renderGroupPolicy为null；excludedLine/operator未选本线。shared corridors.lineIds/members、displayLandlords tenant/landlord、shared exclusion、display releases.lineId、physical junction.lineIDs本线引用均空，CLI作known-schema守卫并纳入apply快照。不扫描未知键或整JSON兜底。

JS现有displayLineForCoordinates/displayPartsForLine与Swift CompactPackage.decodeDisplayIntervals都消费现有displayIntervalCoordinates；物理decode不变，无新增渲染例外。主geometry在同一owner中，未新建扫描/导出/验证框架。

## 聚焦 RED→GREEN、候选与限制

只执行了同一个meaningful回归，先以未修返回值确认 RED，再实现后 GREEN：

`node --test app/scripts/railway/tests/ichibata-kitamatsue-display.test.mjs`

RED 1/1按预期失败 `three isolated red stair lows remain`，`/private/tmp/jtm-ichibata-kitamatsue-display-red.log`；GREEN **1/1通过、0failed、94.015ms**，`/private/tmp/jtm-ichibata-kitamatsue-display-green.log`。同case覆盖精确删3点、全部其余display/物理/站点/km不变、groomed链仅删3点、第二part不变、self-follow仅source后缀更新、无关行保留、旧/已修重放、source/baseline变更拒绝、真实loop/reverse/follows双角色新增依赖拒绝。没有第二测试文件或更多测试执行。

导出命令：

`node app/scripts/railway/repair-ichibata-kitamatsue-display.mjs --candidate-root /private/tmp/jtm-ichibata-kitamatsue-candidate-20261019`

成功生成六个现有package/lane/reference文件，沿用 refreshDependencyReferences + applyPreparedWrites 路径；日志 `/private/tmp/jtm-ichibata-kitamatsue-display-export.log`。没有 --apply、native或build。后续由父检查完整#6候选和相同p3/p4近景，解锁前不再继续native。native/Main实证可另补nativeReview字段，保持本次status/provenance不变，以维持重放。站台caps、物理测绘中心、全线侧偏以及#11没有因此被接受。

## Parent integration review

Parent read the authority and focused GREEN log, then compared generated candidate to current production: precisely3 display controls removed, canonicalsegments/stations and all other own-line attributes preserved; all otherline records exact; byRegion exact; other-lineparts/follows exact. Production lacks thisoverride and remains unapplied. Full#6z17 request retained as interval-6-candidate-request-20261019.json; not executed because Maclocked. NoMainbuild or newcapture after lock.
