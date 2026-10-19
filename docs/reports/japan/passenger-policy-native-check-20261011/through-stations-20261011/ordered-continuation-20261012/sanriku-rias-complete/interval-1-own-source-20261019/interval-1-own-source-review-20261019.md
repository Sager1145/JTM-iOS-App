# 三陸リアス #1 磯鶏南方 v5–v8 自有来源核查 — 2026-10-19

**结论：保留现状，无充分的最小修复候选。** v6→v7是原N02里两个不同的坐标控制，不是显示覆盖引入，也不是完全重复点。明确本线客运OSM way也保留相近短边，但同样带KSJ2/MLIT来源；因此能确立自身客运身份和来源延续，不能独立证明这是实际锐折，也不能确证错点/应删点。没有为不可见的角度制造修复。

本轮只读核查 #1 v5–v8。此前实际审过的7对z17原图见上一级 `intervals-1-3-original-review-20261019.md`；本轮新增原图/原生操作为0。无native/build/test/owner/生产修改，无其它站间扩展。

## 原始N02逐点

保留 [完整原feature 21711](mlit-n02-feature21711.json)，源文件 `app/data/rail-sections.json`；原属性 `N02_003=リアス線`、`N02_004=三陸鉄道`、`N02_001=12`、`N02_002=5`，54个原控制均未改动。当前#1有56个解码控制，无该站间display override。decoded v1..v53与该feature反向index53..1逐点相同；端点/另一端投影控制与局部短边分开处理。

| 当前decoded | 原feature index | 原坐标 [lon,lat] |
|---|---:|---|
| v5 | 49 | [141.96059,39.62858] |
| v6 | 48 | [141.96055,39.62841] |
| v7 | 47 | [141.96054,39.62840] |
| v8 | 46 | [141.96036,39.62803] |

v6→v7球面距离约 **1.404 m**。它不是零长或完全重复边；其长度相对前后段很短，局部角度易受坐标精度影响。原图在磯鶏南方真实缓弯中未独立显示孤立假V，不能从角度大小推导删点。

## 明确自身客运way和路线身份

先使用既有 degree-cell cache `railway-sources/local/osm/degree-cells/E141N39.json`，fetchedAt `2026-08-18T10:46:38.007Z`，仅按**三陸鉄道リアス線/三陸鉄道明确标签**选取相交自身控制区域的对象，而非最近铁路。保留摘录 [retained-own-cache.json](retained-own-cache.json)。随后只读取已识别exact对象：

- [way24357701/full](https://api.openstreetmap.org/api/0.6/way/24357701/full.json)，way v15 / 2020-10-21，165节点；`name=三陸鉄道リアス線`、`operator=三陸鉄道`、`passenger_lines=1`、`railway=rail`、`usage=branch`、无service侧线标签。
- [连接站区way24357718/full](https://api.openstreetmap.org/api/0.6/way/24357718/full.json)，way v7 / 2020-10-21，2节点；同样明确自身名称/运营者，和24357701共享节点 **264231696**，连接磯鶏站区。
- [24357701实际parents](https://api.openstreetmap.org/api/0.6/way/24357701/relations.json)返回两方向 **route=train**：relation **1934365 v74** `盛=>久慈`与 **5781540 v91** `久慈=>盛`，均operator三陸鉄道、via釜石/宮古。前者own ways成员index261→262为24357701→24357718；后者index234→235反向连续。此处不是只凭route=railway、operator或旧Yamada制图字样赋客运身份。

全部exact JSON响应保留在本目录。way版本日期并不自动固定全部节点的当前几何：fresh长way中另15个节点相对cache已变化，均在本v5–v8局部之外，未用于候选或进一步展开；**局部所列节点与cache逐点相同**。

## 短边来源及独立性

当前v6对应OSM节点 **264237431 v2** `[141.960547,39.628413]`；v7对应 **264237430 v2** `[141.960541,39.628402]`，两者节点时间均2015-05-25。按5位小数舍入，分别**精确等于**N02的v6/v7。OSM中短边也非零长，约 **1.327 m**。相邻节点264237428、264237429有2019年的细化坐标；本短边两节点仍保留早期精度来源。

该way明确带 `source=KSJ2`、`KSJ2:LIN=山田線`及 `National-Land Numerical Information (Railway) 2007, MLIT Japan` note。因此N02与OSM不能当作两份独立测绘；相同小台阶能证明源数据继承，不能证明真实轨道应有尖角。结合约1.4m短边与舍入一致性，**短边/精度使转角被放大是合理解释，但仍只是推断**。未查得能把某一个控制确认为错误/重复的独立自身轨道实测或工程平面控制。

## 停止点与可选更近景

保留物理N02全部原点和当前display，candidate为null。当前只需把v5–v8作为后续来源比较范围，不能把它视为已经批准的修复窗口，也不移动磯鶏或八木沢・宮古短大站点。

若未来需要像素判读，可选 **standard + imagery z19** 同中心 **[141.960545,39.628405]**；上下文至少覆盖 `[141.96015,39.62785]–[141.96085,39.62868]`，让v5/v8及前后切线同框。目的仅是比较**本线实际轨道缓弯**是否连续，不能用蓝色制图圆滑程度作实测证据。这不是采集任务，本轮未生成/运行新native请求。地下/遮挡或轨面不可分时仍应保留未证。

[own-control-proof.json](own-control-proof.json)保存精确raw映射、节点版本、route成员位置、局部cache比较、原source URL与判定。© OpenStreetMap contributors，ODbL 1.0；MLIT N02原属性按仓库原feature保留。
