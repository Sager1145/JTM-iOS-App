# わたらせ渓谷線补采原图复核（2026-10-19）

实际逐对查看 **40/40视点、80张basemap/smooth原始PNG**，用`functions.view_image`分别打开原图，没有裁切、拼图或修改像素。精确本线`jp-わたらせ渓谷鐵道-わたらせ渓谷線`。本轮为7个缺失区间：#0七对、#1五对、#2五对、#5五对、#6十对、#8四对、#14四对。原109个legacy视点本轮实际查看0，不能写成整线149视点视觉通过。

采集根目录`/private/tmp/jtm-watarase-keikoku-missing-20261019`，run-status evidenceReady、dependenciesVerified true、40/40 captured、0 failed；invocation `C092C809-0C5A-4202-A5AA-675E91313A92`。逐视点named identity source/display坐标和from/to station IDs与current own line一致，80个原PNG实际文件大小与receipt一致，未重算hash。capture settings完整保留于manifest；本轮图像为standard/light/z17/1600×1200。凭据成功与实际看图结论分别记录。

**具体尖角线索：#8花轮→中野p0/p1，花轮东北站端红线短向东横肩后再沿NE方向继续，底图自身蓝色铁路线该处更连续。** 父任务提供诊断v3 `[139.30915,36.52161]`、v4 `[139.30938,36.52174]`、v5 `[139.30941,36.52174]`，角度21.14°/35.12°/31.89°，短边4.60/2.68/2.10m（诊断数字归属父任务，本轮未重算）。原图能支持进一步核对这一窄肩；本站有宽站符/平台组，不能仅凭短边长度认定伪点。本轮未建立identified own passenger waychain、raw N02窗口、站尾边界和native依赖，故尚无source-ready直接修复。#8随后真实东行→东北大转弯必须保留；未见回头或接入邻线。

其他明确但较宽的偏移线索：#0p4–6及#1p0–2下新田前红色长弦在自身蓝线弧的NW侧；#5p3–4及#6p0–3本宿前后偏河侧/东南，#6p4–9部分长河谷反弯和水沼南接近偏河侧；#14p0–3通洞—足尾山脚反弯多在蓝线西/北侧，足尾站南一段红色长弦跨过自身弯段。这些不是已确权的单点假V，不能用最近蓝轨符自动替换或删曲线。标准底图位置差尚未用自身来源解释或测量。

方向区分：#0从桐生向西沿両毛共享走廊跨河，再进下新田的自身西/西北分岔；JR両毛西南yard方向独立，上毛线在北侧。#1向相老北转，未沿Tobu南侧支向跳接；#2相老北出走自身北向，Tobu西北分岔、上毛东西跨越均可分开。共站宽蓝填充不能证明各自乘客轨道或平台face。河谷#5/#6、花轮#8和通洞—足尾#14的真实反弯/站端曲线保持连续；未发现可独立确权的假直角、回头或邻线跳接。通洞→足尾并非间藤终点区间，未借此宣称间藤终端验收。

标准地图不证明surveyed物理中心、平台精确端帽、站内道岔连接、隧道或桥梁工程位置。本轮只做自身7区间原图复核，无整线/Main像素验收。

## 实际查看清单

每行两张原PNG均已分别打开；完整绝对路径、camera、named identity与receipt字节数见`missing-viewed-originals-20261019.json`。重复端点视野也独立打开，但不扩大地理覆盖。

| Own interval | Stations | Point | 原图目录 | 实际观察 |
|---|---|---:|---|---|
| #0 | 桐生→下新田 | 0 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000000/000000` (`basemap.png`, `smooth.png`) | 桐生西出沿共享両毛走廊、跨河后走自身西/西北分岔；下新田前红线有偏NW长弦，未确权；JR西南yard/Jomo北侧走廊独立，无孤立V。 |
| #0 | 桐生→下新田 | 1 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000000/000001` (`basemap.png`, `smooth.png`) | 桐生西出沿共享両毛走廊、跨河后走自身西/西北分岔；下新田前红线有偏NW长弦，未确权；JR西南yard/Jomo北侧走廊独立，无孤立V。 |
| #0 | 桐生→下新田 | 2 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000000/000002` (`basemap.png`, `smooth.png`) | 桐生西出沿共享両毛走廊、跨河后走自身西/西北分岔；下新田前红线有偏NW长弦，未确权；JR西南yard/Jomo北侧走廊独立，无孤立V。 |
| #0 | 桐生→下新田 | 3 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000000/000003` (`basemap.png`, `smooth.png`) | 桐生西出沿共享両毛走廊、跨河后走自身西/西北分岔；下新田前红线有偏NW长弦，未确权；JR西南yard/Jomo北侧走廊独立，无孤立V。 |
| #0 | 桐生→下新田 | 4 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000000/000004` (`basemap.png`, `smooth.png`) | 桐生西出沿共享両毛走廊、跨河后走自身西/西北分岔；下新田前红线有偏NW长弦，未确权；JR西南yard/Jomo北侧走廊独立，无孤立V。 |
| #0 | 桐生→下新田 | 5 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000000/000005` (`basemap.png`, `smooth.png`) | 桐生西出沿共享両毛走廊、跨河后走自身西/西北分岔；下新田前红线有偏NW长弦，未确权；JR西南yard/Jomo北侧走廊独立，无孤立V。 |
| #0 | 桐生→下新田 | 6 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000000/000006` (`basemap.png`, `smooth.png`) | 桐生西出沿共享両毛走廊、跨河后走自身西/西北分岔；下新田前红线有偏NW长弦，未确权；JR西南yard/Jomo北侧走廊独立，无孤立V。 |
| #1 | 下新田→相老 | 0 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000001/000000` (`basemap.png`, `smooth.png`) | 下新田自身弧线转西北后北向相老；红线稍在蓝线北/东侧，真实大弯连续；JR西南支向、Tobu南侧接近但未跳接，精确共站轨道未证明。 |
| #1 | 下新田→相老 | 1 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000001/000001` (`basemap.png`, `smooth.png`) | 下新田自身弧线转西北后北向相老；红线稍在蓝线北/东侧，真实大弯连续；JR西南支向、Tobu南侧接近但未跳接，精确共站轨道未证明。 |
| #1 | 下新田→相老 | 2 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000001/000002` (`basemap.png`, `smooth.png`) | 下新田自身弧线转西北后北向相老；红线稍在蓝线北/东侧，真实大弯连续；JR西南支向、Tobu南侧接近但未跳接，精确共站轨道未证明。 |
| #1 | 下新田→相老 | 3 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000001/000003` (`basemap.png`, `smooth.png`) | 下新田自身弧线转西北后北向相老；红线稍在蓝线北/东侧，真实大弯连续；JR西南支向、Tobu南侧接近但未跳接，精确共站轨道未证明。 |
| #1 | 下新田→相老 | 4 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000001/000004` (`basemap.png`, `smooth.png`) | 下新田自身弧线转西北后北向相老；红线稍在蓝线北/东侧，真实大弯连续；JR西南支向、Tobu南侧接近但未跳接，精确共站轨道未证明。 |
| #2 | 相老→運動公園 | 0 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000003/000000` (`basemap.png`, `smooth.png`) | 相老北出维持自身北向，Tobu西北分岔、Jomo东西跨越均独立；运動公園南接近有西侧偏移但无红线孤立V/回头。 |
| #2 | 相老→運動公園 | 1 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000003/000001` (`basemap.png`, `smooth.png`) | 相老北出维持自身北向，Tobu西北分岔、Jomo东西跨越均独立；运動公園南接近有西侧偏移但无红线孤立V/回头。 |
| #2 | 相老→運動公園 | 2 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000003/000002` (`basemap.png`, `smooth.png`) | 相老北出维持自身北向，Tobu西北分岔、Jomo东西跨越均独立；运動公園南接近有西侧偏移但无红线孤立V/回头。 |
| #2 | 相老→運動公園 | 3 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000003/000003` (`basemap.png`, `smooth.png`) | 相老北出维持自身北向，Tobu西北分岔、Jomo东西跨越均独立；运動公園南接近有西侧偏移但无红线孤立V/回头。 |
| #2 | 相老→運動公園 | 4 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000003/000004` (`basemap.png`, `smooth.png`) | 相老北出维持自身北向，Tobu西北分岔、Jomo东西跨越均独立；运動公園南接近有西侧偏移但无红线孤立V/回头。 |
| #5 | 上神梅→本宿 | 0 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000004/000000` (`basemap.png`, `smooth.png`) | 上神梅北出沿西岸真实S弯向本宿；后半红线偏河侧/东南且部分长弦概化，非孤立V，须自身来源后才可定窗口。 |
| #5 | 上神梅→本宿 | 1 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000004/000001` (`basemap.png`, `smooth.png`) | 上神梅北出沿西岸真实S弯向本宿；后半红线偏河侧/东南且部分长弦概化，非孤立V，须自身来源后才可定窗口。 |
| #5 | 上神梅→本宿 | 2 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000004/000002` (`basemap.png`, `smooth.png`) | 上神梅北出沿西岸真实S弯向本宿；后半红线偏河侧/东南且部分长弦概化，非孤立V，须自身来源后才可定窗口。 |
| #5 | 上神梅→本宿 | 3 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000004/000003` (`basemap.png`, `smooth.png`) | 上神梅北出沿西岸真实S弯向本宿；后半红线偏河侧/东南且部分长弦概化，非孤立V，须自身来源后才可定窗口。 |
| #5 | 上神梅→本宿 | 4 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000004/000004` (`basemap.png`, `smooth.png`) | 上神梅北出沿西岸真实S弯向本宿；后半红线偏河侧/东南且部分长弦概化，非孤立V，须自身来源后才可定窗口。 |
| #6 | 本宿→水沼 | 0 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000005/000000` (`basemap.png`, `smooth.png`) | 本宿向水沼沿西岸真实长反弯；红线部分河侧偏东/南，水沼南接近偏东南，曲线连续无孤立V/错邻线，偏移未确权。 |
| #6 | 本宿→水沼 | 1 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000005/000001` (`basemap.png`, `smooth.png`) | 本宿向水沼沿西岸真实长反弯；红线部分河侧偏东/南，水沼南接近偏东南，曲线连续无孤立V/错邻线，偏移未确权。 |
| #6 | 本宿→水沼 | 2 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000005/000002` (`basemap.png`, `smooth.png`) | 本宿向水沼沿西岸真实长反弯；红线部分河侧偏东/南，水沼南接近偏东南，曲线连续无孤立V/错邻线，偏移未确权。 |
| #6 | 本宿→水沼 | 3 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000005/000003` (`basemap.png`, `smooth.png`) | 本宿向水沼沿西岸真实长反弯；红线部分河侧偏东/南，水沼南接近偏东南，曲线连续无孤立V/错邻线，偏移未确权。 |
| #6 | 本宿→水沼 | 4 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000005/000004` (`basemap.png`, `smooth.png`) | 本宿向水沼沿西岸真实长反弯；红线部分河侧偏东/南，水沼南接近偏东南，曲线连续无孤立V/错邻线，偏移未确权。 |
| #6 | 本宿→水沼 | 5 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000005/000005` (`basemap.png`, `smooth.png`) | 本宿向水沼沿西岸真实长反弯；红线部分河侧偏东/南，水沼南接近偏东南，曲线连续无孤立V/错邻线，偏移未确权。 |
| #6 | 本宿→水沼 | 6 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000005/000006` (`basemap.png`, `smooth.png`) | 本宿向水沼沿西岸真实长反弯；红线部分河侧偏东/南，水沼南接近偏东南，曲线连续无孤立V/错邻线，偏移未确权。 |
| #6 | 本宿→水沼 | 7 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000005/000007` (`basemap.png`, `smooth.png`) | 本宿向水沼沿西岸真实长反弯；红线部分河侧偏东/南，水沼南接近偏东南，曲线连续无孤立V/错邻线，偏移未确权。 |
| #6 | 本宿→水沼 | 8 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000005/000008` (`basemap.png`, `smooth.png`) | 本宿向水沼沿西岸真实长反弯；红线部分河侧偏东/南，水沼南接近偏东南，曲线连续无孤立V/错邻线，偏移未确权。 |
| #6 | 本宿→水沼 | 9 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000005/000009` (`basemap.png`, `smooth.png`) | 本宿向水沼沿西岸真实长反弯；红线部分河侧偏东/南，水沼南接近偏东南，曲线连续无孤立V/错邻线，偏移未确权。 |
| #8 | 花輪→中野 | 0 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000006/000000` (`basemap.png`, `smooth.png`) | 花轮东北站端可见红线短向东横肩再沿NE自身铁路继续，蓝线较连续；对应待核对v3..5，尚非可删点授权。后续真实东行→东北大曲线保留，无回头/邻线跳接。 |
| #8 | 花輪→中野 | 1 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000006/000001` (`basemap.png`, `smooth.png`) | 花轮东北站端可见红线短向东横肩再沿NE自身铁路继续，蓝线较连续；对应待核对v3..5，尚非可删点授权。后续真实东行→东北大曲线保留，无回头/邻线跳接。 |
| #8 | 花輪→中野 | 2 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000006/000002` (`basemap.png`, `smooth.png`) | 花轮东北站端可见红线短向东横肩再沿NE自身铁路继续，蓝线较连续；对应待核对v3..5，尚非可删点授权。后续真实东行→东北大曲线保留，无回头/邻线跳接。 |
| #8 | 花輪→中野 | 3 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000006/000003` (`basemap.png`, `smooth.png`) | 花轮东北站端可见红线短向东横肩再沿NE自身铁路继续，蓝线较连续；对应待核对v3..5，尚非可删点授权。后续真实东行→东北大曲线保留，无回头/邻线跳接。 |
| #14 | 通洞→足尾 | 0 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000002/000000` (`basemap.png`, `smooth.png`) | 通洞北出沿山脚真实反弯至足尾；红线多在蓝线西/北侧并以长弦跨过站南弯段，未见孤立V；yard多轨不能证明乘客平台face/精确站帽。 |
| #14 | 通洞→足尾 | 1 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000002/000001` (`basemap.png`, `smooth.png`) | 通洞北出沿山脚真实反弯至足尾；红线多在蓝线西/北侧并以长弦跨过站南弯段，未见孤立V；yard多轨不能证明乘客平台face/精确站帽。 |
| #14 | 通洞→足尾 | 2 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000002/000002` (`basemap.png`, `smooth.png`) | 通洞北出沿山脚真实反弯至足尾；红线多在蓝线西/北侧并以长弦跨过站南弯段，未见孤立V；yard多轨不能证明乘客平台face/精确站帽。 |
| #14 | 通洞→足尾 | 3 | `/private/tmp/jtm-watarase-keikoku-missing-20261019/alignment/captures/000002/000003` (`basemap.png`, `smooth.png`) | 通洞北出沿山脚真实反弯至足尾；红线多在蓝线西/北侧并以长弦跨过站南弯段，未见孤立V；yard多轨不能证明乘客平台face/精确站帽。 |

仅写本报告与manifest；未启动native/app/build/tests，未改源码、生产几何或其他scope，未继续队列准备。
