# 北松江線补采原图复核（2026-10-19）

实际逐对查看 **55/55视点、110张basemap/smooth原始PNG**，以`functions.view_image`分别打开原图，未裁切、拼图或改变像素。精确本线`jp-一畑電車-北松江線`。本轮覆盖补采#1六对、#2五对、#4五对、#5五对、#6五对、#7七对、#8七对、#9七对、#11四对、#20四对。旧75个legacy视点本轮实际查看0；不宣称全线130视点已完成视觉验收。

采集根目录`/private/tmp/jtm-ichibata-kitamatsue-missing-20261019`，本次55项capture-state均为captured；run-status evidenceReady、dependenciesVerified true、active false，PID92679，invocation `FE5D8E93-FD4C-47E8-AAE0-BEC2E142866B`。逐视点读取明确命名的immutable identity plan，其source/display坐标及from/to station IDs均与当前自身受影响站间一致；110张原PNG实际文件大小与receipt相符，未运行hash campaign。完整capture settings、camera及文件字节数见manifest。本轮图像为standard/light/z17/1600×1200。采集凭据成功不等同像素验收。

目前没有已建立自身来源及有界接缝、可直接实施的修复。最具体的后续线索为 **#6高ノ宮→津ノ森p1/p2，NE长斜段红线短阶梯**：底图自身铁路较连续，红线有数段短横肩；但不是已确权的大假V，不可仅因小角度或短边删除。**#11湖遊館新駅→布崎p1/p2/p3，布崎前红线北侧S鼓包**也可继续核对原始来源/本站走向；宽蓝填充不能单独证明其错误。#2长直段、#4站东、#7中段尚有更细小肩部，当前z17图像不足以确定改点窗口。

必须保留的真实形状：#1大池/小池湖岸S弯、#2朝日ヶ丘西侧左弯与長江前反弯、#4–7湖岸长反弯、#11平田船川前后SW弯。**#8伊野灘→一畑口向北进入站组，与#9一畑口→園的西臂南出组成真实折返；两臂形成的长尖形不能当成假V直接连接东西两段。** 站组内精确乘客轨道、道岔连接和平台端帽仍未由本次标准底图证明。

#20出雲科学館パークタウン前→電鉄出雲市的自身铁路从NE转SW再向西连续进入北侧终端；JR山陰線在南侧继续向西，不能借用其延长线作为北松江终点。红线局部在自身蓝色走廊北侧，没有孤立V或回头；此侧移未被接受为精确中心。其余站口也存在红/蓝侧移或弦化，未见有充分自身来源支持的邻线误接；这不是平台face或物理中心验收。

标准地图不能证明测绘中心、桥隧工程轴线或精确站台端帽。本轮未研究raw N02/明确乘客waychain与native依赖，故所有肩部/偏移均作为待核对线索，未授权删点或拉直真实曲线。没有运行native/app/build/tests，未改源码、生产几何或父任务status。

## 实际查看清单

每行两张原PNG都已分别打开；完整绝对路径、camera、named identity及receipt字节数见`missing-viewed-originals-20261019.json`。重复端点视野也独立打开，不扩大地理覆盖。

| Own interval | Stations | Point | 原图目录 | 实际观察 |
|---|---|---:|---|---|
| #1 | 松江イングリッシュガーデン前→朝日ヶ丘 | 0 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000000/000000` (`basemap.png`, `smooth.png`) | 大池/小池岸边S弯及朝日ヶ丘前NW大弯连续；红线局部南/北偏，无孤立V或回头。 |
| #1 | 松江イングリッシュガーデン前→朝日ヶ丘 | 1 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000000/000001` (`basemap.png`, `smooth.png`) | 大池/小池岸边S弯及朝日ヶ丘前NW大弯连续；红线局部南/北偏，无孤立V或回头。 |
| #1 | 松江イングリッシュガーデン前→朝日ヶ丘 | 2 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000000/000002` (`basemap.png`, `smooth.png`) | 大池/小池岸边S弯及朝日ヶ丘前NW大弯连续；红线局部南/北偏，无孤立V或回头。 |
| #1 | 松江イングリッシュガーデン前→朝日ヶ丘 | 3 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000000/000003` (`basemap.png`, `smooth.png`) | 大池/小池岸边S弯及朝日ヶ丘前NW大弯连续；红线局部南/北偏，无孤立V或回头。 |
| #1 | 松江イングリッシュガーデン前→朝日ヶ丘 | 4 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000000/000004` (`basemap.png`, `smooth.png`) | 大池/小池岸边S弯及朝日ヶ丘前NW大弯连续；红线局部南/北偏，无孤立V或回头。 |
| #1 | 松江イングリッシュガーデン前→朝日ヶ丘 | 5 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000000/000005` (`basemap.png`, `smooth.png`) | 大池/小池岸边S弯及朝日ヶ丘前NW大弯连续；红线局部南/北偏，无孤立V或回头。 |
| #2 | 朝日ヶ丘→長江 | 0 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000002/000000` (`basemap.png`, `smooth.png`) | 朝日ヶ丘西出左弯、长WSW直段及長江前S弯连续；长直段红线略偏北、局部细肩未确权。 |
| #2 | 朝日ヶ丘→長江 | 1 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000002/000001` (`basemap.png`, `smooth.png`) | 朝日ヶ丘西出左弯、长WSW直段及長江前S弯连续；长直段红线略偏北、局部细肩未确权。 |
| #2 | 朝日ヶ丘→長江 | 2 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000002/000002` (`basemap.png`, `smooth.png`) | 朝日ヶ丘西出左弯、长WSW直段及長江前S弯连续；长直段红线略偏北、局部细肩未确权。 |
| #2 | 朝日ヶ丘→長江 | 3 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000002/000003` (`basemap.png`, `smooth.png`) | 朝日ヶ丘西出左弯、长WSW直段及長江前S弯连续；长直段红线略偏北、局部细肩未确权。 |
| #2 | 朝日ヶ丘→長江 | 4 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000002/000004` (`basemap.png`, `smooth.png`) | 朝日ヶ丘西出左弯、长WSW直段及長江前S弯连续；长直段红线略偏北、局部细肩未确权。 |
| #4 | 秋鹿町→松江フォーゲルパーク | 0 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000004/000000` (`basemap.png`, `smooth.png`) | 宍道湖岸真实缓S/西南长弯保留；站东长段细小肩部未确权，无孤立V或邻线跳接。 |
| #4 | 秋鹿町→松江フォーゲルパーク | 1 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000004/000001` (`basemap.png`, `smooth.png`) | 宍道湖岸真实缓S/西南长弯保留；站东长段细小肩部未确权，无孤立V或邻线跳接。 |
| #4 | 秋鹿町→松江フォーゲルパーク | 2 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000004/000002` (`basemap.png`, `smooth.png`) | 宍道湖岸真实缓S/西南长弯保留；站东长段细小肩部未确权，无孤立V或邻线跳接。 |
| #4 | 秋鹿町→松江フォーゲルパーク | 3 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000004/000003` (`basemap.png`, `smooth.png`) | 宍道湖岸真实缓S/西南长弯保留；站东长段细小肩部未确权，无孤立V或邻线跳接。 |
| #4 | 秋鹿町→松江フォーゲルパーク | 4 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000004/000004` (`basemap.png`, `smooth.png`) | 宍道湖岸真实缓S/西南长弯保留；站东长段细小肩部未确权，无孤立V或邻线跳接。 |
| #5 | 松江フォーゲルパーク→高ノ宮 | 0 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000005/000000` (`basemap.png`, `smooth.png`) | 松江フォーゲルパーク至高ノ宮湖岸WNW/SW真弯连续；站口有侧移/弦化，未证明平台端帽或错误孤立尖角。 |
| #5 | 松江フォーゲルパーク→高ノ宮 | 1 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000005/000001` (`basemap.png`, `smooth.png`) | 松江フォーゲルパーク至高ノ宮湖岸WNW/SW真弯连续；站口有侧移/弦化，未证明平台端帽或错误孤立尖角。 |
| #5 | 松江フォーゲルパーク→高ノ宮 | 2 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000005/000002` (`basemap.png`, `smooth.png`) | 松江フォーゲルパーク至高ノ宮湖岸WNW/SW真弯连续；站口有侧移/弦化，未证明平台端帽或错误孤立尖角。 |
| #5 | 松江フォーゲルパーク→高ノ宮 | 3 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000005/000003` (`basemap.png`, `smooth.png`) | 松江フォーゲルパーク至高ノ宮湖岸WNW/SW真弯连续；站口有侧移/弦化，未证明平台端帽或错误孤立尖角。 |
| #5 | 松江フォーゲルパーク→高ノ宮 | 4 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000005/000004` (`basemap.png`, `smooth.png`) | 松江フォーゲルパーク至高ノ宮湖岸WNW/SW真弯连续；站口有侧移/弦化，未证明平台端帽或错误孤立尖角。 |
| #6 | 高ノ宮→津ノ森 | 0 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000006/000000` (`basemap.png`, `smooth.png`) | 高ノ宮西南侧长斜段红线有短阶梯，p1/p2较清楚；随后湖岸真实大反弯连续，津ノ森站口偏湖侧。仅来源核对线索。 |
| #6 | 高ノ宮→津ノ森 | 1 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000006/000001` (`basemap.png`, `smooth.png`) | 高ノ宮西南侧长斜段红线有短阶梯，p1/p2较清楚；随后湖岸真实大反弯连续，津ノ森站口偏湖侧。仅来源核对线索。 |
| #6 | 高ノ宮→津ノ森 | 2 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000006/000002` (`basemap.png`, `smooth.png`) | 高ノ宮西南侧长斜段红线有短阶梯，p1/p2较清楚；随后湖岸真实大反弯连续，津ノ森站口偏湖侧。仅来源核对线索。 |
| #6 | 高ノ宮→津ノ森 | 3 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000006/000003` (`basemap.png`, `smooth.png`) | 高ノ宮西南侧长斜段红线有短阶梯，p1/p2较清楚；随后湖岸真实大反弯连续，津ノ森站口偏湖侧。仅来源核对线索。 |
| #6 | 高ノ宮→津ノ森 | 4 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000006/000004` (`basemap.png`, `smooth.png`) | 高ノ宮西南侧长斜段红线有短阶梯，p1/p2较清楚；随后湖岸真实大反弯连续，津ノ森站口偏湖侧。仅来源核对线索。 |
| #7 | 津ノ森→伊野灘 | 0 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000007/000000` (`basemap.png`, `smooth.png`) | 津ノ森至伊野灘沿湖长弯连续；中段道路从北侧接近处红线有小肩/钩，仍需自身来源。伊野灘东口真弯不删。 |
| #7 | 津ノ森→伊野灘 | 1 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000007/000001` (`basemap.png`, `smooth.png`) | 津ノ森至伊野灘沿湖长弯连续；中段道路从北侧接近处红线有小肩/钩，仍需自身来源。伊野灘东口真弯不删。 |
| #7 | 津ノ森→伊野灘 | 2 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000007/000002` (`basemap.png`, `smooth.png`) | 津ノ森至伊野灘沿湖长弯连续；中段道路从北侧接近处红线有小肩/钩，仍需自身来源。伊野灘东口真弯不删。 |
| #7 | 津ノ森→伊野灘 | 3 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000007/000003` (`basemap.png`, `smooth.png`) | 津ノ森至伊野灘沿湖长弯连续；中段道路从北侧接近处红线有小肩/钩，仍需自身来源。伊野灘东口真弯不删。 |
| #7 | 津ノ森→伊野灘 | 4 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000007/000004` (`basemap.png`, `smooth.png`) | 津ノ森至伊野灘沿湖长弯连续；中段道路从北侧接近处红线有小肩/钩，仍需自身来源。伊野灘东口真弯不删。 |
| #7 | 津ノ森→伊野灘 | 5 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000007/000005` (`basemap.png`, `smooth.png`) | 津ノ森至伊野灘沿湖长弯连续；中段道路从北侧接近处红线有小肩/钩，仍需自身来源。伊野灘东口真弯不删。 |
| #7 | 津ノ森→伊野灘 | 6 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000007/000006` (`basemap.png`, `smooth.png`) | 津ノ森至伊野灘沿湖长弯连续；中段道路从北侧接近处红线有小肩/钩，仍需自身来源。伊野灘东口真弯不删。 |
| #8 | 伊野灘→一畑口 | 0 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000008/000000` (`basemap.png`, `smooth.png`) | 伊野灘西行后真实北转进入一畑口；与#9组成实际两臂折返，不是可拉直的假V。站内精确平台/连接未证明。 |
| #8 | 伊野灘→一畑口 | 1 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000008/000001` (`basemap.png`, `smooth.png`) | 伊野灘西行后真实北转进入一畑口；与#9组成实际两臂折返，不是可拉直的假V。站内精确平台/连接未证明。 |
| #8 | 伊野灘→一畑口 | 2 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000008/000002` (`basemap.png`, `smooth.png`) | 伊野灘西行后真实北转进入一畑口；与#9组成实际两臂折返，不是可拉直的假V。站内精确平台/连接未证明。 |
| #8 | 伊野灘→一畑口 | 3 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000008/000003` (`basemap.png`, `smooth.png`) | 伊野灘西行后真实北转进入一畑口；与#9组成实际两臂折返，不是可拉直的假V。站内精确平台/连接未证明。 |
| #8 | 伊野灘→一畑口 | 4 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000008/000004` (`basemap.png`, `smooth.png`) | 伊野灘西行后真实北转进入一畑口；与#9组成实际两臂折返，不是可拉直的假V。站内精确平台/连接未证明。 |
| #8 | 伊野灘→一畑口 | 5 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000008/000005` (`basemap.png`, `smooth.png`) | 伊野灘西行后真实北转进入一畑口；与#9组成实际两臂折返，不是可拉直的假V。站内精确平台/连接未证明。 |
| #8 | 伊野灘→一畑口 | 6 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000008/000006` (`basemap.png`, `smooth.png`) | 伊野灘西行后真实北转进入一畑口；与#9组成实际两臂折返，不是可拉直的假V。站内精确平台/连接未证明。 |
| #9 | 一畑口→園 | 0 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000009/000000` (`basemap.png`, `smooth.png`) | 一畑口自身西臂南出后转SW至園，折返方向须保留；海岸长段细肩及園口侧移未确权，无回头或邻线混接。 |
| #9 | 一畑口→園 | 1 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000009/000001` (`basemap.png`, `smooth.png`) | 一畑口自身西臂南出后转SW至園，折返方向须保留；海岸长段细肩及園口侧移未确权，无回头或邻线混接。 |
| #9 | 一畑口→園 | 2 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000009/000002` (`basemap.png`, `smooth.png`) | 一畑口自身西臂南出后转SW至園，折返方向须保留；海岸长段细肩及園口侧移未确权，无回头或邻线混接。 |
| #9 | 一畑口→園 | 3 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000009/000003` (`basemap.png`, `smooth.png`) | 一畑口自身西臂南出后转SW至園，折返方向须保留；海岸长段细肩及園口侧移未确权，无回头或邻线混接。 |
| #9 | 一畑口→園 | 4 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000009/000004` (`basemap.png`, `smooth.png`) | 一畑口自身西臂南出后转SW至園，折返方向须保留；海岸长段细肩及園口侧移未确权，无回头或邻线混接。 |
| #9 | 一畑口→園 | 5 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000009/000005` (`basemap.png`, `smooth.png`) | 一畑口自身西臂南出后转SW至園，折返方向须保留；海岸长段细肩及園口侧移未确权，无回头或邻线混接。 |
| #9 | 一畑口→園 | 6 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000009/000006` (`basemap.png`, `smooth.png`) | 一畑口自身西臂南出后转SW至園，折返方向须保留；海岸长段细肩及園口侧移未确权，无回头或邻线混接。 |
| #11 | 湖遊館新駅→布崎 | 0 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000001/000000` (`basemap.png`, `smooth.png`) | 湖遊館新駅SW长段后、布崎前红线有可见北侧S鼓包；p1/p2/p3需自身来源核对，非已确权假V。平田船川桥前后真SW弯保留。 |
| #11 | 湖遊館新駅→布崎 | 1 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000001/000001` (`basemap.png`, `smooth.png`) | 湖遊館新駅SW长段后、布崎前红线有可见北侧S鼓包；p1/p2/p3需自身来源核对，非已确权假V。平田船川桥前后真SW弯保留。 |
| #11 | 湖遊館新駅→布崎 | 2 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000001/000002` (`basemap.png`, `smooth.png`) | 湖遊館新駅SW长段后、布崎前红线有可见北侧S鼓包；p1/p2/p3需自身来源核对，非已确权假V。平田船川桥前后真SW弯保留。 |
| #11 | 湖遊館新駅→布崎 | 3 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000001/000003` (`basemap.png`, `smooth.png`) | 湖遊館新駅SW长段后、布崎前红线有可见北侧S鼓包；p1/p2/p3需自身来源核对，非已确权假V。平田船川桥前后真SW弯保留。 |
| #20 | 出雲科学館パークタウン前→電鉄出雲市 | 0 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000003/000000` (`basemap.png`, `smooth.png`) | 出雲科学館パークタウン前向SW再西入電鉄出雲市，红线连续无孤立V；JR山陰線另在南侧继续，未把JR西端当本线终点。红线略北偏、站符宽填充不证明平台端帽。 |
| #20 | 出雲科学館パークタウン前→電鉄出雲市 | 1 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000003/000001` (`basemap.png`, `smooth.png`) | 出雲科学館パークタウン前向SW再西入電鉄出雲市，红线连续无孤立V；JR山陰線另在南侧继续，未把JR西端当本线终点。红线略北偏、站符宽填充不证明平台端帽。 |
| #20 | 出雲科学館パークタウン前→電鉄出雲市 | 2 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000003/000002` (`basemap.png`, `smooth.png`) | 出雲科学館パークタウン前向SW再西入電鉄出雲市，红线连续无孤立V；JR山陰線另在南侧继续，未把JR西端当本线终点。红线略北偏、站符宽填充不证明平台端帽。 |
| #20 | 出雲科学館パークタウン前→電鉄出雲市 | 3 | `/private/tmp/jtm-ichibata-kitamatsue-missing-20261019/alignment/captures/000003/000003` (`basemap.png`, `smooth.png`) | 出雲科学館パークタウン前向SW再西入電鉄出雲市，红线连续无孤立V；JR山陰線另在南侧继续，未把JR西端当本线终点。红线略北偏、站符宽填充不证明平台端帽。 |
