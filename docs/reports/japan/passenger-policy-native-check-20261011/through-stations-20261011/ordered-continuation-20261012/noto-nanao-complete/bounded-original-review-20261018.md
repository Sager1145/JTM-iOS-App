# のと鉄道七尾線：前3区间原图复核（2026-10-18）

实际查看 **40/40对、80张basemap/smooth原始PNG**：#0七尾001669→和倉温泉001649共16对，#1→田鶴浜001656共11对，#2→笠師保001648共13对。依区间完整查看，没有随机抽样。原图逐张经`functions.view_image`打开，未裁切、拼图或改像素。其余#3–6共65对本轮未看，105/105旧凭据可用不能写成105视点视觉验收。

使用`existing-evidence-20261018.json`内本线实际receipt路径；前3个区间的named plan source/display和station IDs exact current identity结论仍适用，本轮80张PNG存在且记录字节数重新对照一致，无重hash。camera显示这些保存原图为1024×768、scale1、heading0/pitch0、z17 light；不能把其他新capture的1600×1200设置套用到此证据。

## 本轮结论

**没有已确权可直接修复的孤立假V、直角、回头、断口或错线跳接。** 七尾站场向西北出站、御祓川旁转北、津向/松山反弯和和倉温泉东侧进站弧线连续，均保留实际大方向。七尾南侧扇形yard/侧线仍在背景，红线没有突然折入；但宽站场填色不足以证明自身乘客平台、具体JR共用轨或站帽。和倉温泉向西再向西南出站，在奥原反弯后转西到田鶴浜，方向连续；田鶴浜后沿白浜/深見海岸向西并在大津转北进入笠師保，真实沿海大弯不能因转向明显而拉直。

多段存在持续侧向位置差：#0七尾北西喉、小丸山、松山及石崎口弧段红较蓝色轨符偏西南/弧内；#1奥原/舟尾弧段以及舟尾川直段偏北，田鶴浜站段偏南；#2白浜/深見段偏北，大津北行后到笠師保偏东。这些变化在多帧中连续，未形成可单独删除的尖点。若要修复，需先用本线identified passenger chain、raw N02及保留边界明确单一窗口；本轮仅凭底图位置差不能选择最近的蓝轨、道路或站场侧线。因此source-ready candidate为空，未提出几何改动。

七尾→和倉温泉以本线current ID/station pair确认为审阅对象；底图统一“Nanao Line”标签不能区分JR与のと鉄道运营权、乘客平台或物理共享轨。本轮只区分所见北西出站/西进和倉温泉走廊和yard侧线方向，不把换乘关系、共享站名或宽填色当作物理接线验收。和倉温泉端点、田鶴浜端点在相邻区间各自原图均独立打开，同一地理视野不重复扩大覆盖。

标准地图不证明surveyed centre、工程桥面/地下隧道或精确platform face/caps。#3–6、穴水端及其余65对原图未审阅；本报告不是整线或Main产品运行验收。

## 实际逐张清单

每行两张PNG均实际打开；完整绝对路径、camera、receipt、named身份在`bounded-viewed-originals-20261018.json`。

| Interval | Point | 原图目录 | 观察 |
|---|---:|---|---|
| #0 | 0 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000268/000000` (`basemap.png`, `smooth.png`) | 七尾自身站场起点及北西出站喉：红线从站场向西北直出，未折入南侧扇形侧线。自身乘客平台、JR共用轨与yard归属不能仅由宽蓝填色证明。 |
| #0 | 1 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000268/000001` (`basemap.png`, `smooth.png`) | 七尾北西喉与小丸山方向：红线连续向西北，未回头或跳入侧线；红较蓝符西南偏移，源坐标/轨道归属未确权。 |
| #0 | 2 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000268/000002` (`basemap.png`, `smooth.png`) | 小丸山与御祓川旁真实北西→北向缓弯保留，红较蓝符西南，未见孤立V。 |
| #0 | 3 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000268/000003` (`basemap.png`, `smooth.png`) | 御祓川旁北向直段接南侧真弯，红连续，无断口或短横接缝。 |
| #0 | 4 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000268/000004` (`basemap.png`, `smooth.png`) | 小島町北向直段红与蓝符接近，无独立尖角或错误侧向支线。 |
| #0 | 5 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000268/000005` (`basemap.png`, `smooth.png`) | 津向町北向→西北大弯是真实廊道；红较蓝符弧内西南偏移，不能直接删掉整个真弯。 |
| #0 | 6 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000268/000006` (`basemap.png`, `smooth.png`) | 松山/津向町真反弯：红线弧内西南偏移、轻微概化，未形成独立假V；需own source方能修复。 |
| #0 | 7 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000268/000007` (`basemap.png`, `smooth.png`) | 打越→松山大弯与直线过渡连续，红偏西南，未见回头/跳线。 |
| #0 | 8 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000268/000008` (`basemap.png`, `smooth.png`) | 松百町直段向北西，红偏西南，无可分离尖角。 |
| #0 | 9 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000268/000009` (`basemap.png`, `smooth.png`) | 赤浦沼旁北西直段与过水路位置：红平行西南偏移，无突跳；图符不证明桥梁工程中心。 |
| #0 | 10 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000268/000010` (`basemap.png`, `smooth.png`) | 松百町北西直段红持续偏西南，无局部V。 |
| #0 | 11 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000268/000011` (`basemap.png`, `smooth.png`) | 新保町南侧直段红偏西南，未见短折返或错线。 |
| #0 | 12 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000268/000012` (`basemap.png`, `smooth.png`) | 祖浜町长直段和南端缓曲，红连续且略西南偏移，无孤立直角。 |
| #0 | 13 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000268/000013` (`basemap.png`, `smooth.png`) | 祖浜→石崎口由北西转西北偏西的真实弯；红弧内偏西南，非独立V。 |
| #0 | 14 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000268/000014` (`basemap.png`, `smooth.png`) | 和倉温泉东侧石崎口进站真弯与站场接近：红保留方向，略南于蓝符，未跳入道路/其他铁路。 |
| #0 | 15 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000268/000015` (`basemap.png`, `smooth.png`) | 和倉温泉本线进站及向西出口上下文：红沿站场南侧方向连续，西侧真弯保留；具体乘客站台face、JR/本线轨道归属未证实。 |
| #1 | 0 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000269/000000` (`basemap.png`, `smooth.png`) | 和倉温泉同一端点原图独立查看，与#0末端连续，无接缝V；同一地理视野不扩大覆盖。 |
| #1 | 1 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000269/000001` (`basemap.png`, `smooth.png`) | 和倉温泉向西出站真弧：红连续进入西南方向廊道，未折返进站场侧线；宽填色不足以证明具体站台。 |
| #1 | 2 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000269/000002` (`basemap.png`, `smooth.png`) | 奥原东北真弧进入西南直段，红较蓝符偏南/东，无独立V或直角。 |
| #1 | 3 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000269/000003` (`basemap.png`, `smooth.png`) | 奥原西真反弯向西南，红连续；不能把真实S弯抹直。 |
| #1 | 4 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000269/000004` (`basemap.png`, `smooth.png`) | 奥原西→舟尾真弯，红较蓝符偏西北弧内；未见孤立V，侧向位置待own source。 |
| #1 | 5 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000269/000005` (`basemap.png`, `smooth.png`) | 舟尾东北真弯→西行直段，红平行略偏北，无局部断口或错误支线。 |
| #1 | 6 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000269/000006` (`basemap.png`, `smooth.png`) | 舟尾川桥及直缓弯，红稍北于蓝符，未见接缝钩；桥面位置未工程确权。 |
| #1 | 7 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000269/000007` (`basemap.png`, `smooth.png`) | 舟尾川过水路到川尻直段，红稍北偏且连续，未见孤立锐角。 |
| #1 | 8 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000269/000008` (`basemap.png`, `smooth.png`) | 川尻/鷹合川过水路附近自身东西直段，红北偏过渡至南偏，无突然V或错误路线。 |
| #1 | 9 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000269/000009` (`basemap.png`, `smooth.png`) | 田鶴浜东侧进站直段：红平行略南偏，未向邻道路跳接，平台归属未证实。 |
| #1 | 10 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000269/000010` (`basemap.png`, `smooth.png`) | 田鶴浜站场及两侧直段，红较蓝符偏南，保持东西向，无帽端钩；具体平台face/站帽不作验收。 |
| #2 | 0 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000270/000000` (`basemap.png`, `smooth.png`) | 田鶴浜自身起点重复原图独立查看，无与#1接缝V；平台归属不由蓝色宽填色证明。 |
| #2 | 1 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000270/000001` (`basemap.png`, `smooth.png`) | 田鶴浜西出站→沿海真转弯，红连续，未见独立V/回头。 |
| #2 | 2 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000270/000002` (`basemap.png`, `smooth.png`) | 田鶴浜西侧向北西再向西的真实S弯保留，红较蓝符偏北/内弧，未形成孤立V。 |
| #2 | 3 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000270/000003` (`basemap.png`, `smooth.png`) | 白浜町真北西→西向弯，红持续北偏，不能直接删真弧。 |
| #2 | 4 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000270/000004` (`basemap.png`, `smooth.png`) | 白浜町海岸东西向直段与东侧真弯，红稍北偏，无局部跳线。 |
| #2 | 5 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000270/000005` (`basemap.png`, `smooth.png`) | 白浜→深見沿海直段，红持续北偏，无独立角点。 |
| #2 | 6 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000270/000006` (`basemap.png`, `smooth.png`) | 深見川桥及东西缓弯，红平行北偏，未见断口；底图不能精确证明桥面工程位置。 |
| #2 | 7 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000270/000007` (`basemap.png`, `smooth.png`) | 深見真弯入大津大弧，红持续北/内弧偏移，未出现独立V；海岸真曲线必须保留。 |
| #2 | 8 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000270/000008` (`basemap.png`, `smooth.png`) | 大津从东西向转北向的大弧保留，红较蓝符偏内弧东北；非孤立直角。 |
| #2 | 9 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000270/000009` (`basemap.png`, `smooth.png`) | 大津大弧北端及沿海北向直段，红东偏，方向连续，没有回头。 |
| #2 | 10 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000270/000010` (`basemap.png`, `smooth.png`) | 沿海北向直段红东偏，未见局部角点或错线；不借249号道路作轨道。 |
| #2 | 11 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000270/000011` (`basemap.png`, `smooth.png`) | 笠師保南侧真缓弯/沿海直段，红东偏，无孤立V，站台面未证实。 |
| #2 | 12 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000270/000012` (`basemap.png`, `smooth.png`) | 笠師保自身站场及南北进出方向：红连续北行，较蓝符东偏；平台face、caps和精确代表中心未证实。 |

仅写本scope报告和manifest。无native/capture/app/build/tests，无源码、production或其他scope修改。
