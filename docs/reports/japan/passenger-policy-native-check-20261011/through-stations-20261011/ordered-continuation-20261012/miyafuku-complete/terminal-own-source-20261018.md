# 宫福 #12 福知山入口与自有终站来源

2026-10-18。只读研究 `jp-WILLER　TRAINS-宮福線` #12 福知山市民病院口005097→福知山005124。已逐张实际打开 `/private/tmp/jtm-miyafuku-missing-20261018` 中本线p2–5的8张basemap/smooth原图，以及丹铁、JR两张官方构内图；完整路径见 `terminal-own-source/viewed-source-manifest.json`。没有native、build、capture、测试、apply或生产/source实现改动。

**自有客运走廊与丹铁岛式站台已得到明确归属；现有终点明显偏北的疑点有来源支持。但全平台纵向中心未核定，不能直接接受一个终点替换。** 仅替换内部弯线后硬接旧终点，也不构成合理的局部修复。以下坐标是来源比较，不是Apple像素测量或独立survey。

## 官方站台身份与实际原图

[丹铁官方福知山站页](https://trains.willer.co.jp/station/fukuchiyama/)明确说自有站位于JR站台北侧、为1面2线高架岛式站台。已保留HTML及实际查看[官方构内图](https://trains.willer.co.jp/wp-content/uploads/2019/02/fukuchiyama.gif)：上方独立丹铁岛台标1/2，JR站台为另一组编号，专用丹铁入口及JR换乘通道均可区分。官方同时说明特急はしだて使用JR站台；不能据此把宫福普通客运终站轴转移到最近JR轨道。

也实际查看了[JR官方构内图](https://eki.jr-odekake.net/premises?id=0630719)（页面标2022-03-04时点）：上方单独标“京都丹後鉄道ホーム”，与JR1–5区分。两张图都是构内示意图，能证明平台归属、楼层与相对位置，不能转换成GPS轨道测量、精确端帽或中心点。图像分别保留为 `terminal-own-source/official-fukuchiyama-layout.gif`、`official-jr-fukuchiyama-layout-20220304.gif`。

| 本次实际查看原图 | 观察 |
|---|---|
|#12 p2|自身南行段在多轨接近区连续；向东南转弯时红线开始位于图示轨道组北侧。邻近JR/场线只作背景，不拿来确定本线方向。|
|p3|红色入口弯线持续偏在蓝色铁路组北侧，随后直伸入街区一侧；这不是孤立小V，而是较长的来源位置差异。|
|p4/5|红终点 `[135.11767,35.296995]`位于图示车站轨道组北侧；共站蓝色填色不能确定丹铁1/2平台，但官方图及下述自有stop area已能独立区分它和JR站台。|

这些是z17 standard、1600×1200、light原图，line dependency `da3d11ef0066c78912cf2fe9804f22e769db60ce557b4c73d8e44f52b2a427db`。本次只重新查看p2–5；完整#12六对的既有实际审图记录见 `missing-native-review-20261018.md`，不能把本次4对重复记为额外覆盖。

## 显式本线客运链与平台对象

先使用既有缓存 `railway-sources/local/osm/degree-cells/E135N35.json`（2026-08-18T10:31:02.971Z，maps.mail.ru Overpass），再仅抓已识别对象的OSM exact full/parents API。没有大范围最近铁路查询。以下北→南→东南链节点连续，11个way的fresh完整节点坐标均与缓存geometry逐点一致：

| way / version | 起节点→终节点 |
|---|---|
|32055774 v12|359860765→6875954525|
|734230293 v5|6875954525→6875954527|
|734230292 v5|6875954527→359861889|
|734230274 v5|359861889→359861911|
|1009715717 v2|359861911→359861907|
|734230273 v4|359861907→6875846184|
|734230238 v5|6875846184→6875900880|
|375872966 v11|6875900880→6875857737|
|734230239 v5|6875857737→6875954492|
|734230258 v3|6875954492→6875954491|
|734230257 v6|6875954491→359860798|

它们均有自有name京都丹後鉄道宮福線、operator京都丹後鉄道、KSJ2:LIN宮福線、gauge1067；usage=branch不是货场身份。更强的客运证明是[way375872966的父relations](https://api.openstreetmap.org/api/0.6/way/375872966/relations.json)：train12018222 v19（2024-04-19）宮津→福知山，在zero-based149..159连续包含上表11way；反向train12030449 v9同日版本在14..24按相反顺序包含它们。不是仅route=railway/operator标签推断。

own endpoint **node359860798 v10** `[135.1179371,35.2964979]`在way734230257上，railway=stop/public_transport=stop_position/train=yes/operator京都丹後鉄道，两个train route分别把它列作最后/首个stop。[该节点父relations](https://api.openstreetmap.org/api/0.6/node/359860798/relations.json)另有 **stop_area11766818 v1，福知山(京都丹後鉄道宮福線)**：成员同时包含359860798、另一自有客运stop8018056595、**platform way734217344**，由此直接把轨道、停车点与丹铁自有岛台绑定。

platform734217344 v5（2026-07-03）是area=yes/public_transport=platform/railway=platform的10节点闭合polygon。不是根据距离给它猜归属。另一轨道734217345 v4有service=siding，但自身含stop8018056595 `[135.1179528,35.2965656]`，同样train=yes/operator京都丹後鉄道，并在该自有stop_area内，因此不能仅因siding标签把客运平台第二轨排除。它从自身switch6875857741 `[135.1170296,35.296704]`分叉，终至buffer6875857729 `[135.118572,35.2964227]`；第一轨从359860798继续经884808925 v3到buffer6875857745 `[135.1185472,35.2963581]`。两条自有尽端轨与JR through/freight/yard明确区分。OSM未在这两轨上给出可直接对应官方1/2号的独立ref，故不编造“北轨=官方几号”的精确编号绑定。

全部原文、way/node版本、成员与几何保留在 `terminal-own-source/`；`source-inventory.json`列各exact URL及文件，`terminal-source-facts.json`冻结链、原控制和研究值。OSM © contributors/ODbL；rail标签有KSJ2祖源，停车点标source=Bing，这些是来源沿革，不是独立survey保证。

## 原始控制、可限定窗口与终点限制

物理源 `app/data/rail-sections.json` feature19866为宫福线36个原控制，**逐点等于本线decoded1..36**。加两站端点为38 controls，compact原公里1.489。旧弯线/终点没有display override，本次偏移并非新增alias造成。不得改物理轨迹、站ID或里程来修显示。

沿已确权本线链比较：v20 `[135.11108,35.29964]`距该参考9.183m，v27 `[135.11308,35.29819]`30.038m，v35 `[135.11673,35.29723]`48.259m，终点v37到该单轨参考46.740m。应保留真实南转东南大弯，不能只删一个角或拉成直弦。仅从v20以后突然接入会形成约30.22°入口；v17入口约19.19°。本次局部边界比较中，**可研究v12..37**，保留v11 `[135.11016,35.30194]`及此前全部控制：v12投至 `[135.11023534472895,35.30158033386501]`，4.1925m，入口5.1528°、前一guard4.4750°。这是已评估的来源窗口，非全局最小性或native接受证明；终点尚不能冻结成完整可apply候选。

如果只处理横向错位，保持原终点longitude135.11767：自有两轨该经度latitude分别35.29655921319261和35.29661254251012，共同支持的横向轴为 **`[135.11767,35.29658587785136]`**，距旧点45.4924m。该经度靠近自有polygon西端 `[135.1176418,35.2965796]` / `[135.1176483,35.2966028]`，所以**绝不能称为全平台纵向中心**；两停车点平均也不是全平台中心。polygon东端还带不同宽度/台阶，官方示意图不提供精确GPS帽位，本次没有独立影像核定整个usable platform extent。没有任意往东移动或跨JR平台加权平均。

若后续明确只允许same-chainage横向修复，代表轴须在自有switch6875857741以后按上面两条已确权客运轨道共同支持推导。`terminal-source-facts.json`保留“合并两轨经度控制→各轨纬度线性插值→两轨等权中心”的6点来源草图，终止于上述同经度参考；它不是已批准的站台中心或完整渲染候选。不能先沿南侧单轨一直走到末点前3米，再突然连接平台轴，这会人为加入横钩。也不能把更北/更南的最近JR轨拿来扩大pair。

005124在宫福、JR山阴、JR福知山三条线共用，但原坐标不同：宫福 `[135.11767,35.296995]`，两JR线 `[135.118565,35.29657]`。如后续允许显示终点校正，必须是**宫福line-specific alias**，不能按共享ID全局覆盖，更不能用JR坐标代替。也需审视该alias对own terminal DisplayParts/native endpoints的实际依赖；本次没有改native或构造新pipeline。

**处置：** 客运进站方向、own platform归属和明显错位的来源证据已充分到可准备下一步局部候选；仍未证实全平台纵向代表点、精确1/2编号轨绑定和独立物理survey。当前保留生产，不推荐内部曲线单独修后强接旧端点。父会话应先决定端点显示政策/核定自有平台纵向范围，再冻结完整v12..37候选并审图。#8北偏、#0宫村等其他问题保持各自范围，不从这里推断通过。

父决策：先核定完整自有岛台纵向范围，不采用靠西帽的same-chainage点冒充平台中心。父已实际打开两张官方GIF确认丹铁/JR相对归属。已准备 `/private/tmp/jtm-miyafuku-terminal-detail-prepare-request.json`（#12,z19,1600x1200,standard/light,prepare），尚未运行；共享native窗口当前归CN。释放后读取实际plan选终端/两帽视点，再由同一App的exact viewpointIDs补标准/影像原图，保留未解决的帽位。没有新增截图引擎或平台猜测。
