# 中村线0–3：独立显示候选交接

状态：candidate only，等待Root统一原生集成与验收。我未操作任何检测app/Main、未启动app、构建、签名、修改安装app、生产app/public/rail或共享owner脚本；未创建验证runner。physical IDs、stations、km、segments、routing未改。

## 交付

- `line-record.json`：Root完整候选中中村线这一条的可合并record，含candidateIntervals0–3及五个边界displayStationCoordinates。它不是可独立运行的完整三owner冻结输入。
- `nakamura-0/1/2/3-coordinates.json`：164 / 360 / 161 / 63点。
- `candidate.json`：所有输入路径、逐幅实际camera/mapRect/尺寸、原图控制点、撤回控制点、明确warnings。
- `review-receipt.json`：实际打开清单、完整overview与原尺寸检查区分、可复用旧证据边界。
- `focused-coordinate-checks.json`：仅坐标端点、共同段、forward direction和控制折角证据，不是native/pixel acceptance。
- `nakamura-N-view-MM.png`：66幅逐原camera回投，红=原source、绿=候选、紫=候选站点端点。原图未覆盖。每幅1024×768；站点seam999×654，由各自view.json反投，不使用固定viewport假设。

## 具体修改及witness

Naka0接续`proposal-own-bodies-v2/nakamura00`。原始0view0显示现有候选在“中村線”标签处由西侧own continuation跳到东侧fan，再跳回，控制index4折角31.139°。本次仅替换indices3–8：`candidate.json/naka0Correction`保留原六坐标，给出原图像素及遮挡前后枕木flanks；459–520标签遮挡用同一西侧rail连续插值，不从文字/RGB持久性推选轨。原图`native/primary/captures/002963/000000/basemap.png`、`naka0-original-grid.png`与`naka0-final-start-crop.png`说明撤回/修复。Kubokawa站台/个别轨归属仍warning，未推断Dosan共code就是同一face。

Naka1逐坐标保留KainaV4的360点：Wakai共同段及真实Kawaoku分向保持原样，不做新RGB分岔拟合。完整29overview，原尺寸9/10/11/17及candidate16，保存区域aerial已打开。实际fork在Naka1view11约[515.819,385.020]，不是右侧NS与loop的画面交叉。共同段末端[133.09360956059015,33.15674556577149]后，Naka下一点[133.09254934244711,33.15667388719591]向西进入保留loop；Yodo下一点[133.09357737408197,33.15673658383143]继续西南。两条forward dot product>0，折角14.673°与0.855°。源物理分岔/图边未改；区域图像只是接续context，不能把画面交叉转成连接。

Naka2保留V4完整body，只把Iyoki北侧尾部接到批准新alias；Naka3同时裁掉旧北端并从同一点沿南側rail接续，原旧点[133.098333,33.105009]不再构成返回弯。Iyoki实际高倍窄face endpoints[515,328]→[508,516]，纵向中点[511.5,422]。批准alias[133.0983224428835,33.10458511013298]反投[497.532,421.331]。实际rail修正pick约[503,328]、[498.3,421.3]、[494,516]，比旧flanks502/497/493约东1px。本次north/south支持使用实际修正rail，批准alias仍保留，约0.8px normal差异处于已声明±1.5px容差，explicit warning保留；不可把旧flank当作本次actual pick。north y220–299有道路遮挡，200与320邻侧rail支持接续，未从暗道路像素强选rail。

Naka3完整body采用旧61点fit中各幅actual ownPixel的字面反投，替代其“距source≤2px则保留source”策略；完整9幅original及最后9幅回投实际打开。该区间的铁路有Nakamura名称/枕木，唯一简单corridor，排除了河流、道路56badge与文字。8处旧fit缺口保留gap metadata，由已识别同band邻点接续；不存在据capture数量宣称对齐。最终末端仍保持TosaSaga physical guard和明确warning。

## 坐标检查结果

|区间|点数|最大控制折角°|>30°|
|---|---:|---:|---:|
|0|164|17.592|0|
|1|360|14.673|0|
|2|161|23.499|0|
|3|63|19.258|0|

Wakai/Yodo0与Naka1的146点前缀逐项一致，前三个sharedcontrols不变。Naka0末7点不变。Wakai incoming→outgoing5.058°、Kaina0.695°、Iyoki2.134°，全部forward。以上来自聚焦坐标查询，不是平滑、lane、Main或运行验收。

## 实际检查范围及待解项

本chat完整overview实际打开Naka0的14、Naka1的29、Naka2的14幅raw和candidate（32张四格sheet，57个原图/57个候选overview panels）。原尺寸raw interval views分别0:[0,1]、1:[9,10,11,17]、2:[12,13]、3:[0–8]，合17幅；原尺寸最终candidate分别0:[0,1]、1:[9,10,11,16,17]、2:[12,13]、3:[0–8]，合18幅。另实际打开Wakai/Kaina/Iyoki/Kubokawa/TosaSaga五幅高倍raw，Iyoki旧display/smooth两panels，四幅站点候选seam/controls和本次focused crops。完整区间3最后全9回投已审；0/1/2未改变的literal body复用regional/mainline及KainaV4交接已记录的原图检查，复用不包含V1 acceptance。

TosaSaga short upper narrow face[503,290]→[503,329]与lower L strip连接建筑形态的身份仍不能辨真face。此chat不平均、不从building-connected fill猜alias；保留[133.101395,33.081189]及最后guard connector的provisional warning。如果Root取得明确own-face证据并确认移动，须补Naka4完整相邻区间再处理两侧。Kubokawa若以后移动alias，须补Dosan59，并独立确认own passenger face/rail assignment。

Root仍需全三Inspectors与Main统一测试最终坐标、station dots、lane/follow、native smoothing、完整区间及owner handoffs；此目录不能声称这些通过。旧V1已经拒绝，本chat未复用其acceptance。Grok查询未认证，未启动Grokworker；GPT5.6low只读提取文件schema/路径/数量，关键值已本地核对。
