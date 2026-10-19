# 福知山・宮福自有终站完整帽位原图复核 — 2026-10-18

**结论：自有北侧尽端轨组可辨，旧终点明显偏北；完整岛台双帽与纵向中心仍未独立证实，本次不给出 WGS84 中心估计或候选 alias。** 不能用同经度近西帽点、屋顶中点、缓冲器中点或 JR 共站填色代替完整自有平台中心。

实际逐张打开了两次会话各 p12/p13 的 basemap、smooth 原图，共4对/8张；原始文件保持原样。父先前查看的4张 basemap 与本次查看范围重合，不重复计为额外覆盖。没有控制 native、重新采集、build、测试、apply，亦未修改修复 owner/evidence 或生产。

## 原图中能证实什么

- **standard p13：** 北侧两条自有尽端细轨和终端短横符号可与南侧 JR 继续轨区分。它们约在画面右中下方终止；短横符号是 rail/buffer cap，不是岛台 usable platform cap。浅蓝大面积车站填色跨多个轨道/站台组，不能作为宫福单独的完整站框。标注“Miyafuku Line”也出现在多个轨迹上下文，不能仅按标注选择 JR 平台填色。
- **standard p12：** 自西北入站的连续方向更清楚，但终端东侧靠近画面右边；不能补出 p13 未明确显示的自有平台东帽。个别圆头蓝色窄条与周围车站填色/轨线竞争，当前无法独立将一条完整 cap-to-cap 窄条绑定为官方丹铁岛台。
- **imagery p13：** 位置最北的终站轨/站台屋顶组与更南的 JR 长站台组可区分，符合官方“JR 北侧、独立岛式1面2线”身份。可见西侧接近轨、站台/屋顶边缘和东部屋顶/连接区域；但整段可用岛台边缘被屋顶、接入结构和阴影遮住。屋顶西端、东端不能直接认作完整 usable platform 双帽，图上缓冲器/轨末也不能取代帽位。高架屋顶影像有视差可能，本次未校正。
- **imagery p12：** 西侧进站方向与轨组层次可见；终端东部延至右缘，没有提供新的无遮蔽完整双帽。不存在仅增加一个纵向平移便可从此图自动接受的全平台中心。
- **smooth p13（两模式）：** 旧终点 `[135.11767,35.296995]` 正好位于快照像素 `(800,600)`，实际画面为铁路北侧楼/停车地块；红线并未到达自有北侧终站 pair。p12 红尾段同样持续位于自身轨组北侧。这证明现状需修正，但不证明任一替代中心。

## 自有身份与既有来源比较

复用 `terminal-own-source-20261018.md` 与 `terminal-own-source/` 既有原文，不新抓大范围铁路。丹铁[官方站页](https://trains.willer.co.jp/station/fukuchiyama/)及[官方构内图](https://trains.willer.co.jp/wp-content/uploads/2019/02/fukuchiyama.gif)确定北侧独立丹铁岛台1/2；[JR 官方图](https://eki.jr-odekake.net/premises?id=0630719)亦单独标京都丹後鉄道ホーム。既有 own train routes12018222v19/12030449v9、stop_area11766818v1、stop359860798/8018056595 和 platform734217344v5 共同绑定本线站台及两条尽端轨。它们不是最近轨猜测；官方构内示意图仍不提供可测 GPS 帽位。

既有 own platform polygon734217344v5 的西侧两点投至 p13 `(789.49,789.76)` / `(791.91,779.16)`；两条 own 客运 rail 分别在附近经过。东部 polygon 有分段台阶：约 `(1130.40,897.70)` / `(1133.61,888.61)` 与 `(1140.20,872.12)` / `(1143.30,862.71)`，再延至 `(1230.09,885.64)` / `(1220.40,922.23)`。这表明“取 polygon 最东最西两端”本身仍需要解释东延区域究竟是可乘降台面还是连接/访问空间。此次影像被屋顶遮挡，不能独立确认；也不把整个 polygon 的几何质心称为完整平台中心。

两个源 buffer 投影约为北轨 `(1136.29,861.43)`、南轨 `(1127.04,890.94)`，可辅助识别自有终端 rail band，与平台 polygon 更东延伸并非同一个纵向端限。原始铁路标签有 KSJ2 祖源，stop 点有 Bing 来源；不将其包装为独立实测。两轨与官方1/2编号的逐轨映射仍未给出，不猜北轨具体号。

之前同经度 own-pair 横向参考 `[135.11767,35.29658587785136]` 投至 p13 `(800,786.9)` 附近，确实靠 polygon 西端而非全平台纵向中心。相对旧点约45.49m南移是旧来源比较值，不是此次平台中心测量。此参考继续拒绝作为终站 centre。

## 实际投影与精确清单

两种 basemap 的 p13 使用完全相同的平面北向快照：mapRect `(x=234967165.11140978,y=106054661.66577925,width=3200,height=2400)`，1600×1200 PNG，displayScale1。`snapshotProjection` 是 MKMapSnapshotter 实际返回点映射：X scale2.0000000000000004、Y scale1.9999999999503295 mapPoints/point，中心约 `(800,600)`；不是从名义 z19 单独猜比例。中心米/point约0.2428693657。WGS84→MapKit Web Mercator world2^28→减 mapRect 原点→除各向实际 scale 的公式、全部源节点投影和各原图路径均保留在同名 JSON。没有反推出一个不具备双帽证据的 WGS 中心。

读取了每个视点的 `view.json` 和 `capture-state.json`：两会话的 intervalDependency 均为 `e425a3d73a57c49d7d1bf9c2c961a822ffed67d9de1aa336b53b4c0a24a5689b`；standard 与 imagery 的 whole-line render dependency 不同，完整值留 JSON。两 result 均 PID61534、2/2、0failed；这只是采集完成，不是对齐接受。现存 receipt 的 pending/reviewFresh 状态未修改。

| 模式/point | 实际查看的原图目录（各 basemap.png、smooth.png） |
|---|---|
|standard/12|`/private/tmp/jtm-miyafuku-terminal-detail-20261018/alignment/captures/000000/000012`|
|standard/13|`/private/tmp/jtm-miyafuku-terminal-detail-20261018/alignment/captures/000000/000013`|
|imagery/12|`/private/tmp/jtm-miyafuku-terminal-imagery-20261018/alignment/captures/000000/000012`|
|imagery/13|`/private/tmp/jtm-miyafuku-terminal-imagery-20261018/alignment/captures/000000/000013`|

只读结论保持：先核定完整 own 乘降台面两帽及其与北侧 rail band 的关系，才能按终站显示政策决定代表点。需要的缺口是可解释的东部台阶/连接区边界与屋顶下可用平台端限，不是再向最近 JR 轨或同经度参考靠拢。本次没有冻结替代端点，也没有声称修复已准备可 apply。
