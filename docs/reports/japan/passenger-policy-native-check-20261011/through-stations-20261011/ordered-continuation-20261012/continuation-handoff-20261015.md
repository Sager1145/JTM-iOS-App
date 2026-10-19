# 铁路逐线复查交接 — 2026-10-15

用户明确要求创建新聊天继续全部工作。旧聊天停止操作 UI；新聊天接管唯一 UI 操作权。直接继续工作，不要求用户重复授权或上传截图。用户此前要求一个聊天独立完成，不启用子代理/Grok/多个聊天并行修复。新聊天替代旧聊天。

## 约束

- 读项目 AGENTS.md、ios/VERIFICATION.md 和 /Users/sager/.codex/skills/jtm-railway-audit-repair/SKILL.md。用户指定指南：/Users/sager/.codex/skills/jtm-railway-audit-repair/references/rail-display-guideline.md。O观察、C现状、R建议分开；地下Transit图不是实际隧道测量。
- 按线路列表顺序、完整区间；先三个实际专用原生检测 app，再实际原始主 app。计数不等于看图，更不等于地理/站台验收。区域俯瞰图优先，不研究站内结构图。保留自己的客运走廊/平台身份，剔除道路建筑、车场扇出和邻线干扰。
- 普通fork不加站珠，核对真正可通行的臂对与接入方向，不能自动补三角或反向大U；投影交叉不证明连接。物理终点结束于自身站点，业务/公司边界不一定物理终点。站点落完整自身乘客平台框中心。
- 每次修复/重要经验记入repair-lessons-20261012.md及铁路skill经验参考。禁止提交/推送/全国验证流水线，使用focused查询/现有测试/增量构建；一次只运行一个重任务。
- 原生UI只用cua_repl，禁止osascript/CGEvent。shell可读取文件、构建和open已安装app。open需require_escalated；沙箱内open可能报误导性kLSNoExecutableErr。所有UI捕获/操作由当前唯一聊天执行。
- 简短中文进度更新，工作时不超过约60秒无更新。保留用户修改，不重置、不清理证据。

## 路径

仓库：/Users/sager/Documents/GitHub/JTM-iOS-App

本文件所在目录记为BASE：docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/ordered-continuation-20261012

经验：BASE/../repair-lessons-20261012.md。

三套 app（全路径绑定，第一套存在重复bundle ID）：

1. /Users/sager/.codex/visualizations/2026/10/11/01a12c88-e8a9-7741-9046-e94472852230/rail-inspector-apps/RailAlignmentInspector.app
2. 同目录/Kisuki Keiyo Inspector.app
3. 同目录/Hakone Inspector.app

原始Main：/Users/sager/Library/Developer/Xcode/DerivedData/RailMap-cysvihgspfvwbzatdiakpqjbxkno/Build/Products/Debug-maccatalyst/RailMap.app，bundleID com.JRM.RailMap，1211×865，日语。Toyama Candidate app不是最终原始Main替代品，目前已退出。

Mac Apple Maps com.apple.Maps此前停在中野新桥/中野坂上的Transit区域。新聊天先用cua.getState或getApp观察，不假定窗口状态。IAB用户地图在松山，ambient URL不是用户选定的任务来源。

## 当前：第27条都营三田线（西高岛平—目黑）

ID jp-東京都-6号線三田線。27站26完整区间。目录BASE/mita-complete。

本轮三套已各捕获115个自身视点，captured115/pending0/failed0，且UI确认均空闲。目录native/{primary,secondary,third}/，每套含report.json、capture-index.json、captures、root-review-sheets/00.jpg..28.jpg。每联系图4个smooth+底图合成视图，最后3个。不要把另存basemap/display也说成全部独立打开。

**旧聊天root实际逐图看过的精确范围：**

- primary：00..28全部，115视图。
- secondary：00..17全部，72视图；需18..28剩余43视图。
- third：尚未逐图打开，需00..28全部115视图。

primary结果：全26区间连续，白山旧三角折线未回归，三田—白金高轮保留北拱替代旧校园侧绕弯；北段0..5保持原客运代表走廊，车场扇出不吸入，JR/东武/Toden等交叉独立。地铁平台框没有本轮新增完整验收。目黑是直通边界，不强制物理截断。旧成果可支持显示对齐，但不是站台工程测量。

**Main正在进行：** main-original/camera-plan.json保存26个完整区间相机及effectiveCoordinates（已应用display aliases）。仅00已捕获ON/OFF和AX、00-pair.json，尚未root打开Main00像素。其余01..25都尚未捕获。

最后成功操作：从camera-plan cases[1]启动原始Main，camera=[35.7895775,139.65781249999998,0.010734621019452615]，即新高岛平—高岛平区间。**当前Main应该运行在case1，但尚未AX确认/捕获**。先绑定并确认中心/状态。旧Cua变量不会跨聊天保存，重新建立。

临时脚本/private/tmp/mita-launch-original.py等已经被清理，不依赖它们。保存在仓库的相机计划、截图均仍在。直接从计划inline python读取一个case然后subprocess.run：

```
open -n <原始Main路径> --env RAILMAP_UI_TEST_CAMERA=lat,lon,span --env RAILMAP_UI_TEST_LAYERS=network --env RAILMAP_UI_TEST_STAGE=compact --env RAILMAP_UI_TEST_STORAGE_ID=mita-original-main-N
```

通过exec_command require_escalated启动，不要运行全自动26次UI循环。每case启动后，在独立图片审阅期间等待加载，再cua读取状态。原始Main重启后旧Cua绑定可能报cgWindowNotFound，重新cua.getApp(确切全路径)即可。

捕获单case方法：
1. getAXState({disableDiffing:true,emit:false})，查railMapRenderStatus，必须network:rendered、budgetDrops:0、centerLat/Lon与计划±0.00001。
2. 保存NN-on.ax.txt及getScreenshot({emit:false})为NN-on.png。
3. pressKey('super+shift+l')→getAXState→保存off截图/AX，确认network:off。
4. 写pair.json，初始status='captured-awaiting-root-pixel-review'，保留source计划及actualOnStatus/actualOffStatus。
5. toggle回ON→AX→CmdQ退出，启动下一case。
6. root实际打开每对图片，确认完整路径和两端均可见，不能用AX中心代替画面范围证明。必要时只扩大真实被裁的相机并保留初始失败帧。

可用PIL制作2组ON/OFF联系图1600×1250（每面800×600+标题）；只做图集，不用Python改底图。Cua screenshots只能由Cua实际获取。

## 三田既有修复与复用边界

历史成果BASE/../mita/results.md，whole-line-final有50张联系图与coverage.json、north-review.md/south-review.md，覆盖26区间115视点。原/tmp原件已无，但仓库联系图仍在。历史Main main-final五个重叠区域覆盖全线+白山/三田西侧近景；不要把历史第二、三app局部抽离说成当时三套都完整115。本轮已实际三套各115，正在补逐图和Main。

当前source-line.json冻结正式compact行。旧聊天刚做定点查询：import buildCandidate from app/scripts/railway/repair-mita-apple-display.mjs，当前27个displayStationCoordinates与candidate.stationAliases完全相等，26个displayIntervalCoordinates与candidate.intervals完全相等，物理baseline断言通过。未写生产数据。

当前Main native manifest 三田825顶点27站1chain，chunk sha 520764bf42ce6999ab202dfa7eaa19f18d288cc1ef3ac15f8c8bc2ddba48834e；南北线dependsOn三田。manifest位于Main/Contents/Resources/rail-display-network/manifest.json，lines是dict，regions是list，二进制jp.display.bin。不能据此宣称全app资源一致。

当前display-lanes三田两个lane：part0 measures16922.6..20242.8 offset0.5、22683.6..26616.1 offset-0.5；南北跟随row为[jp-東京地下鉄-7号線南北線,0,0,2650,jp-東京都-6号線三田線,0,26616.088285028567,24003.1]。资料owner为repair-mita-apple-display.mjs，不是被否定OSM候选repair-mita-display.mjs。显示别名可能尚有沿站台纵向中点问题，既有底图路径对齐不冒充新完整站台验收。

目前mita-complete只有source-line.json、scope.json、native和Main计划/00对照，**还没有完整分析/interval-review/review-progress**。先按实际完成进度写记录，全部看完再标基线完成。

## 刚完成的第26条丸之内线

目录BASE/marunouchi-complete，complete-analysis.md、interval-review.json、review-progress.json、scope.json已完整记录；BASE/results.md追加。

主线jp-東京地下鉄-4号線丸ノ内線：24完整段；关联方南町分岐线：3完整段，共28独立站点。三套各121视点（108主线+13支线），root全部363合成视图实际看完。原始Main全部27段+1中野分岔上下文，28对56图均root看过。所有预算0、两端完整可见。

中野新桥向北接入中野坂上有大45°斜切，Apple自身蓝线及MacTransit均为南转东圆弧；朝东方向相符不等于fork/曲线已对。不要自动补南转西连接。车辆基地旁和中野新桥南弯、新宿S弯、国会庭园、东京—银座、日比谷公园、池袋出站轮廓差异保留待修。**本轮没有生产修复**。Main公共新宿点在JR站场，与丸之内东西平台轴不同，需本线完整平台框。

保留既有本乡三丁目003546显示alias=[139.7601239,35.70650045]及interval3/4覆盖。不要因大江户线更近回退旧修复。native Maps证据apple-maps-transit/nakano-junction-regional.png等，官方线序已核对tokyometro.jp/station/line_marunouchi/index.html。

经验“地铁分支大斜切与换乘站公共点（2026-10-15，丸之内线基线）”已追加repo和codex/claude铁路skill的references/lessons-zh.md。没有修改指南或生产代码。

## 本轮较早完成及待办

- 第24半藏门线：13段，三套67各/201合成root全看；candidate及原始Main各13段+2边界，15对30图各全看。完整基线完成，不是14站平台框验收。Oshiage既有alias003526保留，不能吸附浅草/京成斜向平台。目录hanzomon-complete。
- 第25日比谷线：21段，三套89各/267合成root全看；原始Main21段+2边界23对46图全看。7处候选：中目黑出站、广尾南、饭仓、霞关角、筑地、人形町南、三之轮—南千住；22框待验收，无生产修复。目录hibiya-complete。
- 第23宇品线：19段完整基线完成，修复及20框仍待；关联皆实线6段尚未完成整段采集/修复。南町六丁目主线/皆实显示间隙实际确认，不能合并两条独立平台点掩盖缺口。
- 第22富山港线：14段正式走廊复查完成，北端2框已验收，另13框待。此前extractor蓝色B-G≥40、永乐町opening bbox修复及4项focused测试/增量构建有旧证据，不重复运行。
- 第21伊奈线：12段及志久抽离此前正式交付；旧予土被否定方案仍待，不恢复。
- 肥萨线日期显示历史要求保持走既有时间规则；本轮未重新验证，不能把富山2021-03-20/21日期验证冒充肥萨验证。

## 继续列表

原排序取ios/refactor-parallel/alignment-passenger-local-recheck-20261010.json的intervals首次出现的unique lineID，ordinal=index+2；共658条，不能声称剩余只有5条。

27三田当前；28 jp-東日本旅客鉄道-両毛線；29 jp-東日本旅客鉄道-大糸線；30 jp-東日本旅客鉄道-東北線-2；31 jp-東日本旅客鉄道-東海道線；32相鉄本线；之后继续原顺序。不要全国自动启动全待检队列。

## 检测器UI快捷键及已知问题

CmdF搜索、CmdShiftG相机、CmdAltS同视点导出（Save panel）；CmdShiftC当前区间；**CmdAltShiftC当前线路全部区间**；CmdAltShiftLeft/Right前后站；Cmd1..6模式；Cmd7z17/Cmd8z18/CmdShift8z19。

启动专用app可传--args --batch-output <独立目录>，不要--batch-all。选线必须先线路tab→新AX→setValue搜索→观察文本已更新→点精确线路row→新AX验证lineID及起站→单独当前线采集，避免Return未落字后仍采山手。

**不要点全局重试失败**：BatchCaptureController.retryFailed重置失败后start(scope:nil)，会运行全局优先队列。此前日比谷primary误采102、secondary误采70，已保留排除，不能计为本线通过。新三田三套没有这类额外采集。

新聊天若继续UI，第一调用按cua文档规定初始化。不要复制旧聊天的变量/索引。AX每次新读后重新解析索引；截图后索引上下文失效。
