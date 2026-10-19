# いすみ#10黒原候选：原生原图复核（2026-10-18）

已逐一实际打开 **8/8视点、16张原始basemap/smooth PNG**，未裁切、拼图或改像素。采集目录`/private/tmp/jtm-isumi-kurohara-native-20261018`，标准底图/light/z18/1600×1200。capture-index实际所有view均为精确本线`jp-いすみ鉄道-いすみ線#10`，久我原005236→総元005257。每张PNG的receipt文件大小匹配；named identity plan逐点source45点、display49点和两个站ID均与冻结候选匹配，不重算hash。

`run-status`为evidenceReady、dependenciesVerified true，8/8 scoped captures、0 failed；invocation `0E92F6E1-9855-4B98-8568-356400FF9689`，Debug PID61534，line dependency `ecdb0c1267d3695a6bbfd8cfcf476bfd11a20994d6dbc58e4a9f8b1f2212125a`。完成状态仅证明凭据就绪，下面结论来自实际看图。逐张绝对路径、camera、身份、receipt与观察见`candidate-native-review-manifest-20261018.json`。

## 窄修复结论

**图像支持本次13…34的自有铁路显示弧段修复。** 点3/4中，黒原北侧原先位于Isumi蓝轨带西侧的明显弓出已收回，红线保持本线真实近南北曲率；点2/3覆盖北侧接入，点4/5覆盖自有桥梁及桥后真实西弯，点5/6覆盖南侧接回，未见新增V、直角、回头、断口或极短横腿。没有把真实跨河弯拉直。残留的小幅红蓝差异未量成实际误差，也不据此扩修。

北guard12 `[140.24713,35.24684]`／南guard35 `[140.24273,35.24085]`及窗口外全部控制已由此前源码/候选对照保持精确；本轮只复核这些边界附近的可见效果，不把图像当作guard坐标证明。点0/1的久我原站与上游原有偏移属于窗口外上下文，保持原样；点6/7総元站廊也无新钩，宽填色不足以证明具体站台face/cap。

来源归属仍以已冻结的明确本线双向train route成员链`1236719220→287004073→287004072`为依据；中间way为bridge=yes。三way均无tunnel标签，本窗口无已证明隧道变更；这些标准地图原图也不能认证地下轨道。未使用最近铁路图符、道路桥梁或其他线路拟合。

本8视野只覆盖#10久我原→総元，不包含上総中野的小湊接口，**不能据此认证画面外与Kominato的物理连接**。当前候选源链都是いすみ自有铁路成员，源码数据对照仅改display10、#12及其小湊邻接终点完全未改；这些视野内亦无新邻线跳接。此前#12偏移仍是独立未处理项。

## 服务与验收边界

`serviceStatus=substitute_bus`、`serviceSpans=[[0,13,2]]`和`strokeExcludedByRegion`排除原样保留，native生产parts仍无own行。**Inspector红线可见不代表现行Main应显示该线，也不证明恢复客运。** 本轮不验收Main、多线样式、现行运营、物理拓扑、站台中心或整条线路；不重新导出、不重跑已过测试、不修改源码/几何、不apply、不启动native/build。

## 每张实际查看清单

每行两张原图均已实际打开。根目录：`/private/tmp/jtm-isumi-kurohara-native-20261018/alignment/captures/000000/`；JSON manifest保留16条完整绝对文件路径。

| Point | 原图目录 | 实际观察 |
|---:|---|---|
| 0 | `000000/basemap.png`、`smooth.png` | 久我原站与北端原有进出方向；图中红线与蓝色站廊有保留的西偏，处于本次13…34窗口外，不新增站台修复或认证face/cap。红线连续，无新钩。 |
| 1 | `000001/basemap.png`、`smooth.png` | 久我原南侧第一处跨河及转西南大弯，位于窗口北面的保留上下文；保持同一本线方向，无错接道路或断口。 |
| 2 | `000002/basemap.png`、`smooth.png` | 窗口北边界附近接入：沿本线从东北斜段进入黒原北弧；接缝未见V/直角/极短横腿，大弯保持，原始上游偏移没有扩修。 |
| 3 | `000003/basemap.png`、`smooth.png` | 窗口弧体及北侧接缝：红线沿own north-south弧回到Isumi蓝轨带附近；旧西弓分离明显收回，无独立新V或跳线。 |
| 4 | `000004/basemap.png`、`smooth.png` | 黒原北侧弧体、南侧跨河及桥后真实西转：红线连续沿own rail，原西偏弧已收回；南回接无新折返/直角。 |
| 5 | `000005/basemap.png`、`smooth.png` | 桥梁及桥后向総元弯道，红线维持真实曲线并自然接回保留段；无新增短横腿/断口。 |
| 6 | `000006/basemap.png`、`smooth.png` | 南侧保留段/総元进站：真实大弯及东西向站廊连续；13…34尾端上下文无新钩，余留细小红蓝差不扩修。站台face/cap未证实。 |
| 7 | `000007/basemap.png`、`smooth.png` | 総元站与窗口南侧保留上下文：本线走向连续，无新V/直角/邻线跳接；不能由站体蓝填色推断精确caps。 |
