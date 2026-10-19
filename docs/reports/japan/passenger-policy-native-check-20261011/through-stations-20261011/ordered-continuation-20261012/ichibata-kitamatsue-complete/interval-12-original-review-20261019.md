# 北松江#12 布崎→雲州平田完整旧原图复核（2026-10-19）

**完整12/12视点、24张basemap/smooth原PNG已逐张实际查看。** 精确本线`jp-一畑電車-北松江線`，#12 布崎004678→雲州平田004727。来源为既有scope `existing-evidence-20261019.json`中的legacy slot000370，p0..11；本次没有新采集。每张用`functions.view_image`分别打开原始PNG，无裁切、拼图或像素改动。仅覆盖本完整站间。

逐视点重新读取其明确命名immutable identity plan，source65点、display65点和两端station IDs与current own line完全相同；各receipt记录的实际文件大小均匹配，24张原PNG包含其中，未重算hash或做全树扫描。每视点的精确plan路径、camera、原图绝对路径和字节数在`interval-12-viewed-originals-20261019.json`。

## 布崎西口、跨河与完整进站方向

p0/p1显示布崎自东向西经浅S，西口真实转SW后跨平田船川；铁路桥同其西北侧道路桥分开，不能借道路桥方向拉直铁路。本站当前红线偏平台南侧，站东鼓包与西侧跨河曲线是连续问题；p0站符仍小，不能从旧z17补出本站地理端帽。

p1–3显示跨平田船川后继续SW，穿过湯谷川，再转向WSW；长曲线保持连续。p3–6沿湯谷川南侧与三ノ川北侧的自身铁路长走廊前进，红线部分偏北且有轻微肩部/弦化。未见可独立确权的假V、回头或邻线跳接；桥和两河位置关系支持真曲线应保留，不证明工程测绘轴。

p7–9的雲州平田东北进站大弯真实存在，红线在自身蓝色铁路北/西侧，随后沿近直走廊进入站场。p9–11显示雲州平田多轨站场和宽填充，当前红线偏站场西侧贯通；它不是本站具体乘客face、站台轴或精准guard已被确认的证据。不能仅取最近多股轨或站场宽填充中心替换。

## usable caps与站点中心结论

已读父任务冻结的`interval-11-own-source-20261019/official-platform-review.md`及其来源说明：官方布崎站页明确ホーム照片和type1示意支持**自身single platform face**。这是本站乘客身份补强；示意没有地理方向/尺度，照片没有WGS84控制，不能据此认定usable caps或其地理中点。

本完整#12旧z17、结合先前实看#11新z19，仅能辨认布崎平台组在自身细轨南侧、本站西出真弯及跨河接续。**仍未获得两端完整usable caps的地理控制、平台中心向自身轨道的可靠投影，因此未证明当前布崎站点中心应移动到何处。** 雲州平田端同样没有具体乘客轨道/平台face归属，不从yard宽度推中心。

完整#12复核补齐了相邻站间方向证据，但没有解除#11窄窗口尾接缝问题，也未为站帽移动提供坐标。不给fallback坐标，不将本站/外端guard侧移当作已接受；需要明确平台两端的地理控制及自身乘客轨道归属才可进一步定案。没有改owner/test/native/生产几何，未运行build或apply。

## 实际查看清单

每行的basemap.png与smooth.png均分别打开；manifest记录两张完整绝对路径。

| Point | 原图目录（两模式均已看） | 观察 |
|---:|---|---|
| 0 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000370/000000` (`basemap.png`, `smooth.png`) | 布崎西口向SW跨平田船川真实弯连续；站东大S鼓包与本站南偏仍可见。平台符小且宽，不能定usable caps。 |
| 1 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000370/000001` (`basemap.png`, `smooth.png`) | 平田船川铁路桥从布崎西弯沿自身SW长走向跨河，独立于西北侧道路桥；红线略偏SE，未见孤立V。 |
| 2 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000370/000002` (`basemap.png`, `smooth.png`) | 桥后SW长直段跨湯谷川，再沿真实缓弯转WSW；红线略在自身蓝线NW侧，无回头或跨邻线。 |
| 3 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000370/000003` (`basemap.png`, `smooth.png`) | 桥后向WSW真实长曲线连续；局部小肩与北侧偏移可见，未确权单点修复。 |
| 4 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000370/000004` (`basemap.png`, `smooth.png`) | 田野内长WSW直段及东北端真曲线连续；红线偏自身走廊北侧，未见孤立V。 |
| 5 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000370/000005` (`basemap.png`, `smooth.png`) | 长WSW直段在湯谷川与三ノ川之间，铁路同两河/道路可区分；红线略偏北，未见跳接。 |
| 6 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000370/000006` (`basemap.png`, `smooth.png`) | 长直段向雲州平田前弯接近，红线偏北并有弦化；不是已证伪的真曲线。 |
| 7 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000370/000007` (`basemap.png`, `smooth.png`) | 雲州平田东北真实大SW弯，红线在自身蓝线北/西侧；并未跳到北侧道路或河道。 |
| 8 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000370/000008` (`basemap.png`, `smooth.png`) | 东北进站前真弯连续，红线仍偏北/西；没有孤立V/回头，不以侧移自动改线。 |
| 9 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000370/000009` (`basemap.png`, `smooth.png`) | 雲州平田东北直入站场，红线走站场西侧延伸；多股轨与宽填充不能识别乘客face或本站精确guard。 |
| 10 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000370/000010` (`basemap.png`, `smooth.png`) | 完整雲州平田站场及两端主走廊可见，红线沿西侧近直贯通；无法从z17认定具体乘客轨道和平台caps。 |
| 11 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000370/000011` (`basemap.png`, `smooth.png`) | 雲州平田终端视点重复站场，两端连续但多股轨归属未证；保留本站guard，不推算新的站点中心。 |
