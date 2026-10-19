# 北松江#11布崎前自身来源复核（2026-10-19）

**结论：真实浅S应保留；红色鼓包确有过量偏移，但本轮尚未找到无需牵涉本站guard、且不制造新折角的明确最小实施窗口。** 不能将整段拉直，也不能仅因边界投影小于某距离便接受拼接。仅冻结研究计算，没有builder、test、native或apply。

实际分别打开新z19两视点的四张原始PNG（无裁切/拼图/像素改动）：

| Point | 实际查看 basemap 原图 | 实际查看 smooth 原图 |
|---|---|---|
| p5 | `/private/tmp/jtm-ichibata-kitamatsue-nunozaki-detail-20261019/alignment/captures/000000/000005/basemap.png` | `/private/tmp/jtm-ichibata-kitamatsue-nunozaki-detail-20261019/alignment/captures/000000/000005/smooth.png` |
| p6 | `/private/tmp/jtm-ichibata-kitamatsue-nunozaki-detail-20261019/alignment/captures/000000/000006/basemap.png` | `/private/tmp/jtm-ichibata-kitamatsue-nunozaki-detail-20261019/alignment/captures/000000/000006/smooth.png` |

p5的自身蓝铁路有浅反弯，不是直线。红线在东段先落于自身蓝线南侧，之后向北鼓起，再向本站南侧端点靠拢；p6同时揭示站口南偏，不能把它归为孤立中段假V。蓝色宽站符不证明乘客平台轴或准确帽位。

## 明确自身来源与相关性

冻结原响应在同scope的`interval-11-own-source-20261019/`：`osm-way-30414303-full.json`、`osm-way-30414303-relations.json`、`mlit-n02-feature725.json`。way30414303 v8（2025-03-08）标记一畑電車北松江線、operator一畑電車、railway=rail、passenger_lines=1、gauge1067。明确属于自身railway relation1950436 v22及正反乘客train relations11989798 v9 /11996016 v3，不是取最近轨符或邻线。

缓存`railway-sources/local/osm/degree-cells/E132N35.json` fetchedAt2026-08-18的同一way坐标与fresh full响应逐点完全一致。fresh提供node ID/version及当前明确train membership；没有发现一次新OSM几何变更。way仍有KSJ2/MLIT2007来源标记，因此不是独立测绘轴证据；自身乘客身份明确与精确测绘中心是两件事。

当前#11共29个decoded controls。N02 feature725属性为北松江線/一畑電車，27点reverse严格等于decoded1..27；0及28为自身站间端点。#11湖遊館新駅004673 `[132.862145,35.452685]`→布崎004678 `[132.855005,35.450235]`。当前source形状本身含鼓包，不是仅平滑器凭空生成。

按repo `jp-manual-corrections/geo.mjs` 的`projectPointOntoPolyline`，相对于上述明确自身way，decoded16..19偏南，17约5.276m；21..24偏北，其中22约7.598m、23约6.835m、24约6.330m。25靠近双方交会（1.159m），26/27及本站28又偏南，分别约4.595/6.947/6.632m。完整projection与版本化node记录在`interval-11-own-source-calculations-20261019.json`。这些是来源之间距离，未将标准底图认作测绘中心。

## 被接缝否决的窄窗口

研究最小双向偏移窗口：保留raw15 `[132.85838,35.45062]`和raw25 `[132.85583,35.45039]`，仅替换16..24，内部按同一明确way反向连续节点12644779352→335655278→12644779351→335655277→335655255→335655254→335655256→335655251→12644779364→335655249，保留浅S，不取平均线或直弦。raw14、26及26..28站尾、完整#12全部冻结。

raw15投影距离0.716m、raw25投影1.159m，开头内角175.582°→176.052°，但**尾接缝内角174.558°→155.629°，出现新的24.371°折角**。原因是最后自身node→保留raw25先偏北，raw25→26再转向未解决的本站南偏。把投影点额外插入又会产生短横向连接，不能作为修复。窗口长236.580m→234.752m不证明其正确。计算json保留完整研究fragment及精确guards以可复核，明确标为REJECTED，不能拿作已批准候选。

若要移动25以后、站尾28或平台轴，必须先取得并审阅完整#12、布崎自身平台/帽位及相关连接证据，不能用宽蓝填充或相邻铁路方向补齐。本轮没有建立该证据，也未审计native parts/ruler依赖；不建议先做站尾fallback或扩大窗口。当前真正有把握的是保留自身浅S、明确原N02过量摆动及其与站尾南偏连续的关系。

## Later operator-platform supplement

Parent retained and viewed the operator-linked one-face Type1 access schematic and explicitly labelled platform photo. See interval-11-own-source-20261019/official-platform-review.md and source index. This strengthens own platform identity, not geographic caps/centre; the rejected narrow-window finding and no-candidate disposition remain unchanged.
