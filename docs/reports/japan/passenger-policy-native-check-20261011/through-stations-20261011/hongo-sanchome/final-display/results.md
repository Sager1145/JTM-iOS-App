# 本乡三丁目显示点修正与原生结果（2026-10-12）

第67条指出本站偏移。丸之内与大江户原物理锚点为独立平台/公司组，不能使用搜索聚合中心139.760393,35.7071575。owning helper repair-hongo-sanchome-display.mjs 与冻结 evidence 对已识别一方向客运隧道way中的同名/ref双向 stop_position 节点取代表中心：M21 [139.7601239,35.70650045]，相对catalog26.50m向南；E08 [139.7605393,35.7075349]，约8.3m向西南。来源版本/完整node链/层位在 primary-sources 和 source-review.md；这是有日期的地下二手显示依据，非地理测绘或平台长度测量。

仅两个line的 displayStationCoordinates/四个displayIntervalCoordinates改变，physical stations/segments/里程、其余653条line精确保留。约140–260m固定支持范围内quintic沿距过渡，外侧点精确保留。M native339顶点anchor72，Oedo loop519顶点anchor407；既有绝对measure引用按未改坐标映射，两个byRegion/五个hub ruler值同步，不引入family/follow。两次replay源与lanes精确一致；四个既有站名source input引用同步，名称内容不变。

JS五项专项回归通过，source drift负例仅首轮错误消息不匹配、补明确physicalStation诊断后通过。root的较宽280m角度探查发现M东南89m已有N02拐点31.37→36.37度，不能用要求所有原拐点<20度的错误阈值抹平真实/既存弯；回归实际限定站点接头与固定taper边界15m范围，生产两倍率无新增接头台阶。独立审查记录该原弯视觉WARNING；本轮未宣称修复了地下实际半径。

原生 build /private/tmp/jtm-hongo-final-build.log BUILD SUCCEEDED，主App及三Inspector compact与源一致并重签。前两个app顺序采集 M区间3/4各4点、Oedo19为5点/20为4点，root实际查看全部17个视点（4完整区间，含末尾/端点），未见新增断口/末端回折。原始native /private/tmp/jtm-hongo-final-evidence，五张contact与coverage在 final-display。

第三app实际进行本站Marunouchi z18抽离：7段候选、像素支持16%、中位2.4m/P9519.3m/max19.8m、0同名Apple车站POI。纯净extract、底图、分析JSON与GeoJSON导出到 final-display/extraction；只比较有像素支持部分，未凭道路/建筑或POI移动源点，低覆盖不表示地下整轨对齐。

主App同before camera35.70715,139.7604,.006配对，M点实际由(801,496)附近移至(796,527)附近，O点西南移至(842,387)附近。两点依各自线路独立显示，实际分别点击card均保留東京都/東京Metro成员；站点两侧连贯，东南原弯仍保留，无新增站内折回。全四区间camera35.704,139.761,.028覆盖后乐园/御茶之水/上野御徒町/春日接续。近景6lines/6overlays、budgetDrops0。有限显示修复完成，地下精确轨位仍证据不足。
