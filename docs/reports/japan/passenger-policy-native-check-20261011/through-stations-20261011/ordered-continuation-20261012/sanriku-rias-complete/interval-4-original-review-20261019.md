# 三陸リアス線#4 払川→豊間根新原图复核（2026-10-19）

**13/13对、26张原PNG已逐张实际查看。** 精确本线`jp-三陸鉄道-リアス線`，#4 払川000839→豊間根000846。仅看本次新采集的完整#4；没有查看新#1/#2/#3共31对，也未重看旧135对，不宣称179视点整线视觉通过。原图来自capture-index实际目录slot000003，用`functions.view_image`分别打开basemap/smooth，无裁切、拼图或像素修改。

每项view.json引用的精确named immutable plan为`/private/tmp/jtm-sanriku-rias-missing-20261019/alignment/identity-plan-4dee9f3d72b7755d341cf249f1ccca48641467a85e04d1b9aa6210be321e9c7f.json`。仅该#4重新与current source及生产`app/public/rail-network.js`实际decoder得到的display逐点IEEE64bits对照，两列完全相同；station IDs亦相同。source/display各109点。当前自身无display aliases；显示接口与parts调用已在本线source准备时执行，复用仍适用的同一当前输入输出。13项capture-state均captured，78个receipt文件实际bytes匹配，PNG26张包含其中；未重算hash。run-status evidenceReady及完整capture settings/依赖记录于manifest，44/44采集成功不等于44对已被本任务看图。

払川南出先沿SE长段，随后沿津軽石川西岸山脚转南、再向SW走河谷，豊間根北口再转南跨荒川进站。原图上这些长反弯和跨河接续连续，应保留；未见红线独立假V、回头或明显突然接入道路/河道。红线在払川附近略偏西南，河谷中段随曲线在两侧变动，豊間根站段偏蓝色走廊东侧；侧偏未被接受为精确物理中心。

**中段p2–10底图并列存在较西/山侧的较直蓝色线与靠国道侧的蓝色弧线。** 红线沿靠道路侧的连续曲线。底图仍标Yamada Line；这不是另一条必为当前独立乘客铁路的证明，也不能据此猜新旧线/隧道/废线身份。没有当前明确乘客waychain/官方工程归属时，不把西侧更直蓝线作为替换依据，也不把连续真实反弯自动改直。若继续研究，需先确权这两种地图走向。

払川与豊間根宽站符、平台组可见，但本轮没有完整usable caps的地理控制；豊間根红线沿站组东侧不等于特定乘客face已确认。没有新的站点中心、帽位、桥隧轴线或source-ready修复坐标。不提出fallback。未改几何/owner/test/生产或父status，未启动native/build/apply。

## 实际查看清单

每行两张原PNG均已分别打开；完整绝对路径、camera、IEEE身份比较与receipt字节数见`interval-4-viewed-originals-20261019.json`。

| Point | 原图目录（basemap.png / smooth.png均已看） | 观察 |
|---:|---|---|
| 0 | `/private/tmp/jtm-sanriku-rias-missing-20261019/alignment/captures/000003/000000` | 払川站南出沿SE长段，北侧真大弯连续；红线略西/南偏，无孤立V，平台caps未证。 |
| 1 | `/private/tmp/jtm-sanriku-rias-missing-20261019/alignment/captures/000003/000001` | 払川南SE长段连续，红线偏自身蓝带西南侧；不沿东侧国道/河道跳接。 |
| 2 | `/private/tmp/jtm-sanriku-rias-missing-20261019/alignment/captures/000003/000002` | SE长段向南反弯，底图同时有另一较西直蓝线，不能据最近glyph认定乘客线路。 |
| 3 | `/private/tmp/jtm-sanriku-rias-missing-20261019/alignment/captures/000003/000003` | 山脚河西岸真实反弯，红线在弯间由东偏到西偏；无孤立V。 |
| 4 | `/private/tmp/jtm-sanriku-rias-missing-20261019/alignment/captures/000003/000004` | 沿国道西侧山脚真反弯连续，红线局部西偏/鼓出；另一蓝直段归属未核。 |
| 5 | `/private/tmp/jtm-sanriku-rias-missing-20261019/alignment/captures/000003/000005` | 南行后转SW的真实大弯连续，红线接近道路侧蓝带；山内另有较直蓝带，不能猜新旧或运营身份。 |
| 6 | `/private/tmp/jtm-sanriku-rias-missing-20261019/alignment/captures/000003/000006` | 河西岸真SW长弯连续，红线沿较东弧带，另一山侧长直蓝线独立可见但归属未证。 |
| 7 | `/private/tmp/jtm-sanriku-rias-missing-20261019/alignment/captures/000003/000007` | 同一河谷长SW弯/直段，红线连续，无回头；不以山侧蓝直线拉直真曲线。 |
| 8 | `/private/tmp/jtm-sanriku-rias-missing-20261019/alignment/captures/000003/000008` | SW长段至豊間根前南转连续；蓝色双走向仍可辨，红线无孤立V，确权须自身来源。 |
| 9 | `/private/tmp/jtm-sanriku-rias-missing-20261019/alignment/captures/000003/000009` | 豊間根北口由SW转南、跨荒川真实弯连续；红线与自身近旁带接近，另侧蓝折线非删除依据。 |
| 10 | `/private/tmp/jtm-sanriku-rias-missing-20261019/alignment/captures/000003/000010` | 跨荒川与県道290号前后连续，红线局部偏西再向站东偏；不借道路桥走向改线。 |
| 11 | `/private/tmp/jtm-sanriku-rias-missing-20261019/alignment/captures/000003/000011` | 豊間根站北直入，红线在平台组东侧通过，具体face/caps未证。 |
| 12 | `/private/tmp/jtm-sanriku-rias-missing-20261019/alignment/captures/000003/000012` | 豊間根站场及南延伸，红线偏蓝带东侧后随真实SW弯，完整站点中心未确权。 |
