# 北勢線#11補采原图复核（2026-10-19）

实际逐对打开 **4/4视点、8张basemap/smooth原始PNG**；父任务也已实际查看相同八张。使用`functions.view_image`分别打开，未裁切、拼图或改变像素。仅本次`jp-三岐鉄道-北勢線#11` 馬道005798→西桑名005785；**旧71对本轮实际查看0，不计作视觉通过，也不改旧证据结论。**

采集根目录`/private/tmp/jtm-sangi-hokusei-missing-20261019`。逐张view.json实际引用的named immutable plan为`/private/tmp/jtm-sangi-hokusei-missing-20261019/alignment/identity-plan-75a6a028eef0e143ba59dfab11004cfdc5611197fe99fb1ea51f28673d3209b2.json`。重新将current source与生产`app/public/rail-network.js`实际`decodeIntervals`接口所得display转成IEEE754 64bit整数，四项source/display两列逐点bits完全相同；from/to station IDs相同。当前自身无displayIntervalCoordinates/displayStationCoordinates aliases；另调用同生产JS的displayPartsForLine确认自身显示parts，未以canonical decode单独冒充display。source/display各27点。24个receipt记录的文件实际大小匹配；PNG八张包含其中，未做hash campaign。run-status状态及camera完整保留在manifest，采集完成不等于像素验收。

馬道自身铁路先东行，穿过近铁南北走廊后，以真实宽S向北转，再沿近铁名古屋线东侧的独立自身轨带进入西桑名。p0/p1包含馬道东出及完整宽S；p2/p3包含北转后并行段和西桑名终端方向。不能将宽回转拉直，也不能把近铁名古屋线或更西侧JR関西線的轨道/平台当作北势自己的终端。原图显示红线连续，没有孤立V、回头或跳接到近铁的尖角。此处不同铁路在标准地图的跨越并不表示轨道连接。

仍可见持续侧偏：馬道及东西段红线偏自身蓝走廊南侧，转北并行段多偏东侧。这些偏移未由自身原始来源、乘客轨道和有界窗口确权，不能声明精确物理中心已接受；本站宽蓝填充也不能证明完整usable platform caps、平台face、精确站点中心或终端端帽。未发现可直接实施的source-ready修复，本轮不提供修复坐标。

## 实际查看清单

每行两张原PNG均已分别查看；manifest记录完整绝对路径、精确named plan、IEEE比较结果和文件字节数。

| Point | 原图目录（basemap.png / smooth.png均已看） | 范围 |
|---:|---|---|
| 0 | `/private/tmp/jtm-sangi-hokusei-missing-20261019/alignment/captures/000000/000000` | 自身馬道→西桑名宽S/北转/邻线分离上下文，红线连续；侧偏和平台caps未确权。 |
| 1 | `/private/tmp/jtm-sangi-hokusei-missing-20261019/alignment/captures/000000/000001` | 自身馬道→西桑名宽S/北转/邻线分离上下文，红线连续；侧偏和平台caps未确权。 |
| 2 | `/private/tmp/jtm-sangi-hokusei-missing-20261019/alignment/captures/000000/000002` | 自身馬道→西桑名宽S/北转/邻线分离上下文，红线连续；侧偏和平台caps未确权。 |
| 3 | `/private/tmp/jtm-sangi-hokusei-missing-20261019/alignment/captures/000000/000003` | 自身馬道→西桑名宽S/北转/邻线分离上下文，红线连续；侧偏和平台caps未确权。 |

只写本scope报告与viewed manifest。未重看旧71对，未运行native/app/build/tests，未改源码、生产几何或父status。
