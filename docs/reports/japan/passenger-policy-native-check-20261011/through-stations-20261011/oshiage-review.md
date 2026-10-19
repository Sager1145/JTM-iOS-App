# 押上两组直通显示只读审查 — 2026-10-11

范围：只读当前 package、lane、replayer、JS/Swift/native consumer、登记源数据及 capture owner 提供的实际 App PNG/AX；未修改生产几何，未操作 UI，未运行 build/tests，未启动 Grok（本 session 已有 authentication failure）。原有 z16/z19 tangent 失败由父 chat 提供为修改前已复现证据，不能归因于本轮修复。

## 当前精确接缝和身份

| 组 | 两条 line | 共同 display endpoint/station anchor | 押上端 lane | follow/family |
|---|---|---|---|---|
| 半蔵門/東武 | jp-東武鉄道-伊勢崎線-2；jp-東京地下鉄-11号線半蔵門線 | [139.81335,35.71026] | 两条均 0；Tobu lane rows 为空，Metro 最后 300m 为 0 | 四条相关 line 均无 follow 和 family rows |
| 浅草/京成 | jp-京成電鉄-押上線；jp-東京都-1号線浅草線 | [139.81241,35.71022] | 两条最后 300m 为 0 | 同上 |

针对 `app/public/rail/jp-2025.json` 和 `app/public/rail/display-lanes.json` 的只读 Node query 确认以上坐标逐值相等，不是近邻吸附。Metro/Tobu physical station 仍为 [139.813731,35.70847]；Keisei/Toei 原站点就是各自共同 display anchor。两组不可因站码相同而互相合并。

旧 `stationCircleOwnerByCode[003526]` 仍在 Tobu 和 Keisei compact 记录上，但它们与 owner 的公司不同，故 `rail-network.js:4391`、`StationDisplay.swift:229` 和 `build-display-network.py:3234` 的非空同公司及精确同坐标条件使该声明 inert。当前 replayer 已会移除这两条旧跨公司声明。每条线仍有自己的逻辑 station/mark；共点端点不等于整段轨道由两个公司共同运营，不能为“保留不同公司”盲目加全区间平行 offset。遇到明确跨公司共用客运区间才需要按审核窗口保留各公司平行线。

`applyStationLanePins` 在最终 display part 米尺上生成 pin；JS 从 lane row/continuous stroke slot 取实际站点偏移；native builder 保留 laneRows/follows、将 station 定位到连续 chain vertex（1m 范围内），Swift `ContinuousStroke` 执行 offset 和 follow substitution。当前押上两组无 follow，因此 owner 修复不会因隐藏的 follow 再吞掉公司显示线。几何更新后必须同步这几条相关 part rows 和 pin 米数，不能留下旧 complex coordinates。

## 登记源数据与实际图

源登记见 `railway-sources/catalog.json`，抽取几何为 `railway-sources/local/raw/n02/fragments.json`。其 Tobu 原片段为：

```
[139.81415,35.70668] → [139.81395,35.70753]
→ [139.81374,35.70843] → [139.81359,35.70908]
→ [139.81336,35.71012] → [139.81335,35.71026]
```

其中另一原片段 `[139.81336,35.71012] → [139.81378,35.71096] → [139.81437,35.71184]` 属于当前 Tobu 北侧 approach。现 display anchor 是南北片段的北端，不是来源明确证明的“站内中央”。同文件 station record（N02 code003541/group003526）的 display_point 是 [139.81369,35.7086833]。这些点只能作为同组合法候选/原铁路支撑，不能因源点邻近而自动指定中央。

`baseline-2025-20260813/classification/n02-station-network.json` 登记：Metro/Tobu [139.8137313,35.7084677]；Keisei/Toei [139.81241,35.71022]。它明确 `interchanges_are_not_rail_connections=true`，Tobu 押上还标 `isolated_or_unmatched`、rail_neighbor_count=0；这套 contraction 结果不能单独证明/否定实际直通，也不能新增物理连接。

已查看实际 `tobu-central-z18-{overlay,basemap}.png`、`hanzomon-central-z18-overlay.png`：marker 与 current display anchor 对应，蓝色站区沿南北方向延伸到 marker 南侧；当前北端共点不能据此宣称已是站区中央。站区周围黑线包括地面 Tobu 主走廊，不能拿最邻近黑线代替正确地下平台组。

已查看实际 `keisei-central-z18-{overlay,basemap}.png`、`asakusa-central-z18-overlay.png`：两线接入西南—东北蓝色 Asakusa 站区内同一点；没有证据要求把它们移到 Metro 南北平台组，也没有明显理由先改该组 anchor。`tobu-approach-view3-z18-overlay.png` 保留北侧弯曲进路；本图不是中央 marker 图。

官方当前京成页面所链接的[押上站内图](https://www.keisei.co.jp/keisei/tetudou/accessj/assets/pdf/sta_oshiage.pdf)分别列出京成方向、都营浅草线/京急方向及半蔵門换乘，支持正确平台组分离和运营客运用途。PDF自身印有2021.3.31，只能作为当前官方页面仍链接的布局资料，不是2026测绘。另核查[东京Metro押上站内图页面](https://www.tokyometro.jp/station/oshiage/yardmap/index_print.html)及[東武押上页面](https://www.tobu.co.jp/railway/guide/station/info/1120.html)。它们不能直接证明WGS84中央坐标。

## 最小 owning-layer 修复建议

1. 半蔵門/東武组的 owner 是 `repair-oshiage-display.mjs`。审核中央点应从上述合法南北 passenger polyline及实际蓝站区确定，只在同组合法段内插入精确点。北側 Tobu display approach 延伸至该点，南側 Metro display approach 截短/延伸至同一点，并同步两条 `displayStationCoordinates[003526]`。保留 physical stations/segments/structure/distance、真实道岔和北侧独立弯道。
2. 不继续用 `alignThroughPaths` 默认120m Bézier替换合法原有弯道。该函数在切点后重造16段曲线及20m直线，丢弃窗口内原支撑点；它的 shared terminal tangent 意图不能替代新 smoothing policy 所要求的保留真实小曲线。押上应以 reviewed source slice/中央 cut组成代表线，仅清理已证明同向共线的冗余点。中央点确切坐标仍待父 chat 根据正确 platform group 的地图/来源证据裁定，不能在此报告发明。
3. 浅草/京成组当前 anchor 保持不动；如果只改保留曲线方式，其 owner 是 `repair-through-running-display.mjs` 的该 join 分支。此组也应使用合法原approach采样，而非默认120m重新塑形；局部几何必须证明沿正确客运进路。应为该组声明独立中央/approach证据，不能复用Metro anchor。
4. 在 replayer 中维护原有精确共点与公司 marks，清理旧跨公司 owner；只更新上述 affected parts/lane pins，检查同一组两端和站点坐标精确相等、physical记录不变。若实际源合法路径不支持精确 opposing tangent，保留真实弯道优先，不能为旧测试形状约束造连接。

现有 `oshiage-display.test.mjs` 仍硬断言 circles.length=1/Metro owner，违反新跨公司规则，应在实施时改为两条公司 mark且坐标共点。`through-running-display.test.mjs` 已按 operator 数量决定 mark 数，但仍要求z16/19严格 opposing drawn tangent；父 chat已复现的既有失败应记为历史约束/renderer问题，不据此重造真实铁路弯道。本次没有执行这些测试，也未声称像素/运行时验证通过。

## 完整站区补充观察

后续实际 `oshiage/tobu-hanzomon-station-extent-z17-basemap.png` 完整显示南北蓝站区与更北/西侧地面Tobu黑线，AX给出map corners纬度35.707254–35.713265。北端override确实偏蓝站区北侧；不能把地面主线当作地下平台替代。

可提出严格来自原source的合法内部候选 `[139.81359,35.70908]`，不改变经纬度精度或凭近邻吸附。若父chat审核接受该点，最小shape-preserving裁切为：Tobu使用physical北侧approach原采样至 `[139.81336,35.71012]` 后接候选点，丢掉候选以南的旧physical终点仅在display副本；Metro保留原physical采样到 `[139.81374,35.70843]` 后沿已登记原source segment接候选点，删除旧physical末站坐标仅在display副本。两条display station精确设为该candidate，原physical记录不变。这个候选位于合法地下进路和可见蓝站区内，已足够作为坐标候选；它不等于已证实的站台中央。

若要求最中央而非合法站区内部，应先确定官方半蔵門1–4台布局在实际地图上的核心平台范围，排除出口/通道蓝色伸展部分，再在已登记segment `[139.81359,35.70908]–[139.81336,35.71012]` 内审核中央cut。截图本身没有独立平台polygon地理坐标，不能据此发明一个精确midpoint。官方布局支持平台组与方向，但不能直接给WGS84。当前父chat负责修改两条现有测试（follow dependency/adapter及押上不同公司两marks期望）；本报告未改测试，不以未跑测试充当新证据。

## 官方图与 station-specific survey 的进一步核对

`app/data/stations.json` 是独立站点FeatureCollection，source注明由MLIT N02 2025版加工；押上有四条 station feature。Metro code003540及Tobu code003541都是 `group003526`，拥有**完全相同的 station LineString**，坐标就是本报告列出的6点南北片段（起点35.70668、终点35.71026）。京成code003527与都营code003526则各自相同、独立地用 `[139.81158,35.70972]–[139.81324,35.71072]` 表达西南—东北组。这不是按全线选出的nearest fragment。

对南北station LineString按当前纬度的本地米尺作只读长度query：总长约405.157m，半程位于 `[139.81374,35.70843]–[139.81359,35.70908]` 内，坐标约 `[139.8137312902853,35.708467742097106]`，与compact physical anchor六位小数匹配。`display_point=[139.81369,35.7086833]` 则精确匹配6个采样点的经纬度算术平均，不是沿线半程。这个等式核对说明不能把旧display_point冠名“平台长度中点”；也不能仅因station-specific LineString叫站段，就推断405m全段均是实际客运平台。

已从当前[東武押上站内图页](https://www.tobu.co.jp/railway/guide/station/insidemap/1120/)读出它实际引用的[官方图文件](https://www.tobu.co.jp/cms-img/stations/20250908095952nc0hFuPDPC1vFLJPw67vMQ.gif)，并以 `view_image` 检视。文件名含20250908，仅记录文件命名，不推断图的正式修订日期。图确认B3F两座岛式平台、1–4号台，渋谷/中央林間方向一端、東武動物公園方向另一端；上层有同属東武/半蔵門的改札，浅草/京成改札另列。它与actual蓝站区南北地下组一致，不能移到北侧地面Tobu主线。Metro公开站内JPG与2025-05-15官方新闻PDF可在web工具索引读取，但本机HTTP取文件收到403；没有把未实际看到的Metro图像细节列为证据。

将无pitch/yaw、完整蓝站区actual PNG与AX corners对照，南北蓝色主长条的内部中部落在约纬度 **35.7093–35.7096** 的带内；这是手动地图读图的合理中央审核范围，**不是**已地理标定的站台起讫/中心测量。选择该范围的依据是蓝色主体的中段，排除北侧通向浅草组的横向通道、南侧细长出口伸展；不是取整个405m source station segment或所有蓝色结构的bbox平均。

此带完全位于合法原source segment `[139.81359,35.70908]–[139.81336,35.71012]` 内。在线段上精确插值得到范围边界：南端 `[139.81354134615384,35.7093]`；北端 `[139.813475,35.7096]`。小数精度只表示原线段插值结果，不能解释为地图读图精度。此前existing-source candidate `[139.81359,35.70908]` 是合法站区内部点，但偏该中央带南侧，不宜在证据不足时直接定为最终中央。

如果父chat接受“蓝主体中央带内、同组原铁路上的审核代表点”作为本轮显示语义，可以从该带选择明确记录的cut，并沿原source保形完成Tobu/Metro双侧exact join；本审查没有擅自选其中一点。若需要“站台物理中央”的精确坐标，仍需有地理标定的B3F平台起讫（工程平面/地理reference或明确的map station polygon对应），官方立体示意图加当前PNG不能提供该精度。无论选择哪种交付精度，都不能把物理拓扑或里程改到新display cut。
