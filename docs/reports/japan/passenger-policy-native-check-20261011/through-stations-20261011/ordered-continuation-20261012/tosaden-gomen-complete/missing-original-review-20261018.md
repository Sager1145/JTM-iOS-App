# 後免線補采42対・原图复核 — 2026-10-18

**42/42对、84张原图已实际逐张查看，0未看/0缺失。发现多处持续走廊偏移和后免町终点偏西线索；未冻结任何新坐标或单点删除候选，也不接受全线。** 真实街道、桥头和山脚复合弯应保留，不能为消除侧差而拉直。重点是整段位置/站点代表性，不能把所有问题缩成一个角度阈值。

查看对象为 `/private/tmp/jtm-tosaden-gomen-missing-20261018/capture-index.json` 实际清单，17个缺失区间，共42对：0、5、7、8、10、12、16、18、19、20、21、23、24、25、27、30、31。每对前实际读取 capture-state、确认 captured 及两 PNG/view.json 存在，再分别打开 basemap、smooth 原始1600×1200 PNG，detail=original，无拼图代替。机器清单 `missing-original-review-viewed-manifest-20261018.json` 保存84张绝对路径与逐图观察。

## 可追踪的线索与边界

| 范围 | 实际观察与建议处置 |
|---|---|
|#0 はりまや橋东出发，2对|选对东西向自有电车街道，未走南北交叉线路；真实 S 弯保留。红线稍偏蓝轨南，未见孤立 V。自有站台两帽、平台代表面及实际 Main 路口连接仍未核定。|
|#5 知寄町，2对|连续东西向街道段，红线在自身图示轨道南侧；不是单个尖角，不能用删点消除。|
|#7 葛岛桥，3对；#8 东岸，2对|更明确的持续侧偏：跨桥与东岸斜街红线在 own 蓝轨南侧，部分进入路边/楼地块上下文。桥头真实转东北再向东的弯保留。不是往南侧国道32号或最近道路拟合，也不能未经确权直接追蓝。|
|#10 高须，2对；#12 文珠通→介良通，3对|红线在 own 图示轨道/站框南或东南侧持续平行，真实东北街弯仍存在。需要本线 passenger pair/own rail locus 与站台身份，暂无局部新坐标。|
|#16 田边岛通→鹿児，3对|明显线索：红弧切入本线街道弯南侧绿地，继而位于自有北行轨道东侧。须整弯及两站锚点一起确权；小角度不代表走廊正确。|
|#18 舟户→北浦，3对；#19 北浦→领石通，3对|红线在山脚 own 曲线南侧并切入绿地，北侧 JR 土赞线保持独立。#19宽缓北弓没有被红线充分表示；是连续身体/站点偏移问题，没有一个已确权可删的“坏 V”。|
|#20 领石通→清和学园前，3对|较强线索：红线在 own 北弓南侧以较平的弧/斜弦穿越绿地和建筑上下文，再接近东端；应核对完整 own 原弯和两端站位，不得把真实山脚弯平掉。|
|#21 清和学园前→一条桥，2对|短东行主体连续、局部更接近本线图示。西侧较大偏移仍在相邻上下文中；未将其冒记为#21单点缺陷。|
|#23 明见桥→长崎，2对；#24 长崎→小篭通，3对；#25 小篭通→篠原，3对|持续南偏：红斜段进入 own 街道/铁路南侧空地，随后东西向路段仍在自有蓝轨/站框南侧。保留真实街道转弯，勿取北侧 JR 方向。|
|#27 住吉通→东工业前，2对|自身东西街道段连续但南偏，东端上下文渐近图示。无孤立 V，站框中心不接受。|
|#30 后免中町→后免东町，2对；#31 后免东町→后免町，2对|自有路面电车向东南再向东弯确实存在，红线保留它；未上接从北侧转来的 GomenNahari 轨。#31 p1红终点在快照中心(800,600)，自有小终端填色/站框在其东侧约x830上下文。终点偏西是待核定线索，但 z17 不足完整双帽/rail band/纵向中心，不能直接采用该像素或邻近铁路平台。|

上述“南/东南偏”是实际截图中的本线 cartographic corridor 比较，不是独立物理survey、精准像素距离统计或 datum 诊断。本线 labelled transit glyph 与实轨的位置关系仍须明确；不能将整条线统一平移作为未经来源支持的结论。尤其#16/#18–20的绿地切线与#31终端帽位应优先确权，若进一步修复应先明确 own rail band、乘降台面和来源边界。

## 原控制与来源：不是新增 alias 的假弯

只读当前 own compact：33站/32区间，kind=tram，无 displayStationCoordinates、无 displayIntervalCoordinates。17个捕获区间的 sourceCoordinates 与当前 decoded 输入长度一致，快照往返最大数值差仅约8.53e−14度（JSON保存每区间值），此比较使用明确容差，未冒称 IEEE bits 完全相同。连续 compact 行按 continuesFromPrevious 补回前段末点。

对5个已识别控制片段做原始 N02 逐点列表相等比较：

| 区间 | app/data/rail-sections.json feature | 方向 | 原 compact segment 坐标索引 | 对应 decoded 控制 |
|---|---:|---|---|---|
|7|11286|反向|0..8|1..9|
|16|11283|反向|0..8|1..9|
|19|11299|正向|0..7|1..8|
|20|11293|正向|0..13|1..14|
|31|11320|反向|0..4|1..5|

上述 source properties 均 N02_003=後免線、N02_004=とさでん交通；JSON保存各片段原坐标和匹配范围。只证明所列内部控制来自原 N02，其他控制及物理站锚点没有被冒称属于同一feature。这些偏移/简化不是本次新加显示覆盖造成，不能先删显示别名“修复”。没有修改任何物理站、站ID、里程、segments、服务状态或 native ruler。

## 复用范围与渲染限制

原 `preparation-20261018.md` 记录旧81个计划视点、39个可用旧 receipt、42缺口及32区间 own 身份。本次只看42补采；**另39对旧图本次未看**，不能把81个 receipt 算成全线像素完成。若相邻区间共享同一站点相机而原图几乎相同，本清单仍按实际不同 viewpoint ID 逐张打开，覆盖不累加为额外物理范围。

本次 standard/light/z17，1600×1200，ownLane0/mainLane0，isolated centreline；完整 DisplayParts 平滑后裁切，无实际 lanes/follows/joins/family collapse。PID61534，42/42、0failed为采集完成；whole-line render dependency `d2bde76e3ac24f236ee7e4ff00b9e5365a7f96140665432462f1f6a25f6ec04a`，当前receipt pending/reviewFresh=false未改。未运行 native/app、build、测试、apply或生产改动。

后免町必须保留 road tram 自有终端身份，与更北/东北的 GomenNahari 铁路平台和北侧 JR 土赞线独立。看见近邻同名站或线路相交，不构成同轨/接入/站台中心证明。本报告不提供候选坐标；只提交可定位的源/像素线索供后续本线确权。

## 全部实际查看的原图目录

各目录内 basemap.png、smooth.png 两张均实际查看；JSON有完整文件路径、相机、snapshotProjection、view.json、capture-state、时间、identity-plan和逐视点观察。

| 区间/point | 原图目录 |
|---|---|
|0/0|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000000/000000`|
|0/1|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000000/000001`|
|5/0|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000014/000000`|
|5/1|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000014/000001`|
|7/0|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000015/000000`|
|7/1|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000015/000001`|
|7/2|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000015/000002`|
|8/0|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000016/000000`|
|8/1|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000016/000001`|
|10/0|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000001/000000`|
|10/1|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000001/000001`|
|12/0|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000002/000000`|
|12/1|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000002/000001`|
|12/2|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000002/000002`|
|16/0|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000003/000000`|
|16/1|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000003/000001`|
|16/2|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000003/000002`|
|18/0|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000004/000000`|
|18/1|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000004/000001`|
|18/2|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000004/000002`|
|19/0|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000005/000000`|
|19/1|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000005/000001`|
|19/2|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000005/000002`|
|20/0|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000006/000000`|
|20/1|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000006/000001`|
|20/2|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000006/000002`|
|21/0|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000007/000000`|
|21/1|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000007/000001`|
|23/0|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000008/000000`|
|23/1|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000008/000001`|
|24/0|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000009/000000`|
|24/1|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000009/000001`|
|24/2|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000009/000002`|
|25/0|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000010/000000`|
|25/1|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000010/000001`|
|25/2|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000010/000002`|
|27/0|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000011/000000`|
|27/1|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000011/000001`|
|30/0|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000012/000000`|
|30/1|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000012/000001`|
|31/0|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000013/000000`|
|31/1|`/private/tmp/jtm-tosaden-gomen-missing-20261018/alignment/captures/000013/000001`|
