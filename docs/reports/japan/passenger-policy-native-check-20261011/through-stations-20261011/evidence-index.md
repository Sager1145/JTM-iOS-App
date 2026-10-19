# 本地来源与证据索引

整理日期：2026-10-11。执行状态只维护在 [唯一检查列表](README.md)；本索引用于重用资料，不代表全部线路已通过验收。

## 官方来源

| 资料／本地文件 | 来源与日期 | 可支持的判断／限制 |
| --- | --- | --- |
| [京成押上站内图 PDF](oshiage/sources/keisei-oshiage-station-layout.pdf)、[本地渲染](oshiage/sources/keisei-oshiage-station-layout.png) | [京成原始 PDF](https://www.keisei.co.jp/keisei/tetudou/accessj/assets/pdf/sta_oshiage.pdf)，[车站入口](https://www.keisei.co.jp/keisei/tetudou/accessj/oshiage.php)；图面2021.3.31，本次保存2026-10-11 | B1两个岛式平台、1—4轨道及浅草／京成方向。示意图没有地理坐标，不能直接导出WGS84中心。PNG由原PDF用PDFium重新渲染，已目视确认日文完整。 |
| [半藏门线建设史292页](oshiage/engineering-history-p292.jpg) | [官方原页](https://metroarchive.jp/ebook_hanzomon_oshiage/data/58/322/UOJz6G.jpg)，2004年建设史；本次保存2026-10-11 | B3平台、210m及中心里程。历史工程图，不证明现行全部客运进路。 |
| [建设史441页](oshiage/engineering-history-p441.jpg) | [官方原页](https://metroarchive.jp/ebook_hanzomon_oshiage/data/58/477/j4atY5.jpg)，同上 | 图103／104定位B3与北十间川，B1斜向站区独立；用于层位和地物关系，不能从示意像素猜测精确地下坐标。 |
| [建设史450页](oshiage/engineering-history-p450.jpg) | [官方原页](https://metroarchive.jp/ebook_hanzomon_oshiage/data/58/494/gDzzIy.jpg)，同上 | 北端下穿关系及曳舟连接，不能代替B1中央点定位。 |
| [千代田线建设史626页](ayase/official-history-p626-wiring.jpg) | [官方原页](https://metroarchive.jp/ebook_chiyodasen/data/24/674/nweQt9.jpg)，1983年6月历史资料；本次保存2026-10-11 | 綾瀬缓行平台组、支线／折返及立交结构；须配合现行资料确认运营状态和位置。 |

都营[押上站页面](https://www.kotsu.metro.tokyo.jp/subway/stations/oshiage.html)的站图直接下载返回HTML访问响应，未获得有效图片。[保存的响应](oshiage/sources/toei-oshiage-station-layout-access-response.html)仅记录下载限制，不作为站图证据。

## 本地派生定位

- [GSI地物摘录](oshiage/gsi-station-landmark-reference.geojson)与[中央切点依据](oshiage/central-cut-reference.json)：来自[地物瓦片](https://cyberjapandata.gsi.go.jp/xyz/experimental_bvmap/16/58220/25800.pbf)，保存日期2026-10-11。当地河道交点投影到已有B3客运源段，支持代表显示切点；原始PBF未在本目录归档，派生坐标不是实测平台精度。不得用于B1京成／浅草组。

[B1 显示定位依据](oshiage/b1-display-reference.json)保存西南起弯／跨河黑轨像素、各自AX角点转换和代表中央点。可见段支持来源明确；隐藏接续与从完整东北端面推得的约33°平台切向是局部代表显示构造，不是官方测绘或精确股道分配。

## Apple Maps／原生显示证据

原始PNG与同名AX文本均在各车站目录。AX记录实际camera、所选线路和界面状态；配对内camera一致不意味着不同批次之间一致。

| 范围 | 文件前缀 | 状态与重用条件 |
| --- | --- | --- |
| 押上东武北侧尖角修复 | `oshiage/before-arc-*`、`oshiage/after-arc-inspector-tobu-north-z19-*`、`oshiage/after-arc-production-north-z19-*` | Inspector前后同camera；主图前后camera略不同。显示短弧已复查，地下实测半径未确定。当前修复数据有效时可复用。 |
| 押上京成／浅草B1定位基线 | `oshiage/before-keisei-central-inspector-z18-*`、`z19-*`及`before-keisei-central-production-z19-*` | 旧共点139.81241,35.71022；仅调查基线，未接受为站内中央轨道点。需跟随可见黑轨与站体边缘，不能吸附到B3。 |
| 押上B1两端露轨 | `oshiage/before-keisei-{southwest,northeast}-z19-*`与`before-keisei-southwest-asakusa-z19-*` | 西南黑线直接标注Asakusa Line；浅草线自身overlay在跨河段偏东南。两端camera均另存AX，西南两线路相机一致。东北区分Keisei与地面Tobu；遮挡段尚未接受为精确贴轨。 |
| 押上B1最终修复后 | `oshiage/after-b1-final-asakusa-{central,crossriver,entry}-z19-*`、`after-b1-final-keisei-northeast-z19-*`及`after-b1-final-production-*` PNG／AX | 四组Inspector与生产主图实际复查。实际B1圆点在斜主体内，京成／浅草接续；B3独立。露出黑轨基本重合、连续入站弯保留。前后批次camera略不同，不宣称exact before/after或地下实测精度。`after-b1-*`仅首候选过程证据。 |
| 押上生产设置与公司组成 | `oshiage/production-main-settings-current.*`、`production-main-*` | 实际Current／Apple Maps及公司成员显示。单线路Inspector零lane预览不能替代主产品的公司平行显示判定。 |
| 小竹向原、綾瀬 | `kotake/`、`ayase/`的配对PNG及AX | 高风险进出站／分岔基线；地下精确平台中心仍待确定，未实施位置移动。 |

完整采集数量不是视觉验收数量；失败截图不解释为几何错误。最新进度见上级`review.json`。

品川南侧后续[来源链接索引](shinagawa/sources/south-research-index.json)保存摄影／调查时点与待核实限制；历史南端改造正文已独立读取，不当作2026逐道岔测绘。

## Chat 调查（辅助建议）

[本任务Chat调查](https://chatgpt.com/c/6acb1cea-899c-83ea-81c4-7081e15cf51a)的完整答案保存在`oshiage/chat-final.ax.txt`／PNG及`oshiage/chat-next-risk-final.ax.txt`／PNG（2026-10-11）。前者针对押上B3，后者针对小竹向原／綾瀬。用户已授权发送相关项目资料。Chat建议须通过本地原始来源、数据与原生图面核实；不能单独作为实测坐标或现行客运资格证明。

本次 B1 [Chat 完整答复](oshiage/chat-b1-final.ax.txt)、[截图](oshiage/chat-b1-final.png)及[已发送任务包](oshiage/chat-b1-prompt.txt)已保存（Pro5/5，2026-10-11）。跨图端面定位建议已由本地AX角点与原始PNG核对后采用；站内图不提供地下测绘精度。早期`after-b1-*`是首候选过程证据，最终验收使用`after-b1-final-*`。

小竹向原后续资料：[官方工程资料说明](kotake/sources/source-note.md)，已保存p439、p599原图；2023报告网页正文可读，但本地PDF下载403，未冒充完整原件。现行拓扑需覆盖2016千川侧改造。

小竹千川侧补查：`kotake/yurakucho-senkawa-chord-end-z19-*`与`fukutoshin-senkawa-chord-mid-z19-*`（两组PNG／AX，2026-10-11）。已实际目视，支持总体地下客运走廊走向；无法辨别现行双路线／立体分岔精确位置，无移动依据，保留待现行工程证据核实。

## 品川／东京多线路复核资料

- 品川成员卡修复后：`shinagawa/after-popup-fix-production-eastern-circle.*`与`after-popup-fix-production-station-card-top.*`。主App已实际重新打开，点击独立东侧圆点；完整AX含五条客运成员及总武线-3，卡片top图底部仅露第五行，几何未再次改变。

- [品川官方平台图](shinagawa/sources/jr-east-platform-map.png)、[来源说明](shinagawa/sources/source-note.md)：图面2026年7月，区分横须贺／总武13–15、东海道6–12及新干线21–24平台组。
- [东京官方平台层图](tokyo/sources/jr-east-platform-map.png)、[来源说明](tokyo/sources/source-note.md)：图面2026年9月，保留独立新干线及在来线组。平台示意不直接导出地理坐标；中央既有native证据另见上级tokyo-through-reference。

- [品川独立走廊依据](shinagawa/independent-corridor-reference.json)及`after-repair-yokosuka-{central,north-throat,south-departure}-z19-*`：已实际目视东侧站点与连续进路；站体遮挡的黑轨未验收为逐轨精确居中。南侧z19/z18保留未识别黑轨的交叉疑点，需客运走廊身份调查。
- [东京末端依据](tokyo/terminal-display-reference.json)、`after-repair-tohoku-terminal-no-pin-z19-*`及`after-repair-production-terminals-z19-*`：无pin图确认横尾折消失；生产主图确认东北与东海道新干线独立圆点，在来线共点保留。
- [品川南侧Chat任务](shinagawa/chat-south-prompt.txt)、[发送截图](shinagawa/chat-south-sent.png)及AX：本任务原有Chat页Pro5/5，发送同相机南侧overlay/basemap与官方July2026平台图，2026-10-11。完整答复已保存为 `shinagawa/chat-south-final.ax.txt`／PNG。答复为 NEEDS_CONTEXT：需要从13–15平台南端连续辨认正常客运上下行，不能直接吸附未命名黑轨，也不能将旧源链斜切判为已对齐。其GSI/历史配线分析仍需本地独立核对，不据此猜测新坐标。

重启与最终卡片：`shinagawa/after-popup-fix-production-station-card-bottom.*`五行全部可见；`after-popup-fix-default-loaded.ax.txt`及`after-popup-fix-default-resumed.*`确认正常重开、恢复一次与记录增长，最终AX24,553/92,216、失败4。截图生成时计数继续增长，不当作视觉验收数。

本轮下一线路木次：`../parallel-instance-kisuki-keiyo/current-kisuki14-station-z19-*`、`current-kisuki14-reversal-view3-z18-*`与`current-kisuki15-reverse-bends-view4-z19-*`为实际操作配对；[局部资料索引](kisuki/sources/audit-note.json)与GSI检索记录区分运营、位置和时点依据。箱根长进路新增`../parallel-instance-hakone/current-hakone6-{approach-view2,long-approach-view4}-z19-*`，按同客运腿调查连续曲线位置，保留现有折返支线。采集成功不是对齐通过。

- 箱根长弧修复后：`../parallel-instance-hakone/after-long-arc-{context-z18,detail-z19}-{overlay,basemap}.png`及同名AX；z18camera139.071026,35.236380、z19camera139.071024,35.236381（与before中心误差<1m），原clone资源更新后实际复查。源支持47–54显示改绘、physical及折返stem冻结；不可解读为地下测绘或全线通过。

- 品川正常客运轨道对修复：`shinagawa/sources/passenger-pair-reference-20261011.json`记录OSM普通客运上下行、排除站场支线、GSI大比例铁路及2019影像、13–15平台身份、站点显示中点、北侧轨道对内过渡与精确南接回点；屋盖测绘和当前逐道岔分配不认证。source和测量窗口重放幂等，相关JS15/15通过，单次主App增量构建成功且打包的两条修改记录匹配源；后续after-passenger-pair-*原生图面另记录。

- 品川更新后实际原生：`shinagawa/after-passenger-pair-central-z19-*`、`south-straight-z19-*`、`south-context-z18-*`及`west-bend-z17-*`（均完整after-passenger-pair前缀）；主图`after-passenger-pair-production-central-{network,basemap}.png/.ax.txt`、`production-card.png/.ax.txt`。站内近直、原横折移除、真实西弯保留；生产独立点在蓝站体内、卡片5成员含总武。屋盖精确轨道/南侧Apple聚合黑线逐轨匹配仍未认证。
# 连续矢量与动态加载（2026-10-11）

- 大崎实际站体／南分岔本轮：`osaki/before-station-detail-*`、`before-station-south-east-middle-*`、`before-south-east-fork-detail-*`及成员卡。不同于此前品川西弧，站点旧alias与可见站内走廊有偏离疑点。官方原始PDF、计划图和出处见 `osaki/sources/README.md`；Chat IAB不可用、未发送的说明亦保存，不能称为Chat验证。
- 京叶线用户指出的重复同色区间：`keiyo/before-futamata-minamifunabashi-context-*`及`before-futamata-shared-corridor-detail-*`。已定位主线与东支线同公司共用尾段缺显示归属，source及lane归属修复已整合，既有聚焦回归10/10通过，含旧tail西臂重放遗漏修复；继任已取得下列有限nativeafter，这些before图仍只作基线；fork小折点、主图Minami平台组中心尚待证据。西臂本身的同公司重复风险未在此轮修复。

- `shinagawa/continuous-vectors/current-window-*`：原样network关闭及同camera开启产品层／缩放对照，区分Apple底图铁路短刻度与产品彩线。
- `shinagawa/continuous-vectors/final-continuous-vectors-osaki-{middle,detail}-network.{png,ax.txt}`：最终修复本体中景／近景，已实际查看；可见彩线连续，有限范围未见断口，不作为全国验收。
- `shinagawa/continuous-vectors/final-continuous-vectors-default-progress.json`：原批次恢复的实时checkpoint计数26,944→26,958→27,001，失败4，同planDigest；AX超时不能替代此实际进度。
- 已审查直通关系来源仍为 `app/scripts/railway/through-running-display-joins.json`；主包manifest新增 `displayJoins` 保存四组稳定端点、证据链接和审查日期，供后续查询，不能替代物理拓扑证据。
- 代码／测试／构建及已退役北美fixture错误的范围记录见本目录 `README.md` 末尾“连续矢量显示本轮”及后续结果段。


2026-10-11继任after证据：

- 大崎：`osaki/after-repair-inspector-{station-z18,south-approach-z17,south-fork-z17}-{overlay,basemap}` PNG／AX及`after-repair-main-station-{overlay,basemap}`、`after-repair-main-station-card`已由root实际查看。卡片三逻辑成员为大崎支线／山手线／临海线；同生产Debug binary使用隔离空行程库camera启动，不修改真实库。新旧camera不同，不作exact before/after或屋盖逐轨认证。
- 京叶：`keiyo/after-repair-inspector-{shared-tail-view3-z17,fork-view10-z17,minami-z18}-{overlay,basemap}`及`after-repair-main-shared-context-{overlay,basemap}` PNG／AX已由root实际查看。主图east fork以东single red，独立进路保留；west arm重复仍可见，fork小折点需复核，主图Minami连续单代表已实查但站体中心未通过。`keiyo/sources/user-double-red-lines.png`已root实际查看。
- 资源证据：首build因大崎family缺policy color失败；补`jp-render-groups.json`大崎组既有包颜色#729825/#9acd32后增量build成功，日志`/private/tmp/jtm-osaki-keiyo-build-family-fixed.log`。built compact五条受影响记录精确匹配源，follow/family测量已定向查询。仅Kisuki Keiyo Inspector compact已刷新重签重开；default／Hakone仍before，default暂停29,781/92,216失败4未resume。

2026-10-11南船桥补充实查：root已实际查看`keiyo/after-repair-main-minami-{overlay,basemap}`同camera配对（distance1932m，center35.681665,139.995886）。共享红线单代表且连续入／出南船桥；dot／红线明显靠蓝站体南缘外侧，未记为站体居中通过。保留既有京叶项中的南船桥偏移候选：需官方平台组与底图原客运轨道证据确认站点／走廊中心，physical站点此轮未动，不能凭此图直接移点。当前main开着同生产binary的隔离空行程库、network ON、南船桥camera。

2026-10-11剩余scope补记：大崎生产南尾详细company composition视窗尚未certify，Inspector南进路／南fork配对不能替代该主图验收。后续保留此视窗、京叶fork小折点、南船桥平台组中心定位及west arm重复；完整继任scope亦记于上级review.json的`osakiKeiyoSuccessorReview`。

2026-10-11本继任大崎南部生产补查：Root实际查看并保存`osaki/after-repair-main-south-fork-detail-{overlay,basemap}`（center35.611329,139.725154,distance1562m）和`after-repair-main-south-tail-{overlay,basemap}`（center35.605700,139.722686,distance1933.9m）PNG/AX同camera配对。真实南分岔绿色代表接入共享橙色走廊，南尾到西大井连续且未见旧绿色重复tail；底图蓝分段新干线为独立走廊，不作同线重复。源定向查询确认base/p1直接follow总武线-3，临海线无此family/follow；公司身份不由单色截图推定。该有限视窗关闭“生产南尾详细composition未查看”缺口，屋盖逐轨、全大崎范围及全国验收不扩展。用同生产binary和独立空行程库，无新build/物理变更，default旧批次仍暂停。

2026-10-11京叶西臂共享修复与有限原生复查：canonical主线interval8从fork[139.95346,35.68953]至003870市川塩浜，与west-3 interval0共有35点精确相同，N02 14150 reverse/14152 station-clipped，独立14147进路保留。`repair-keiyo-midcurve.mjs --west --apply`复用既有reviewed西臂尾段到主线，添加同向follow及两family windows；东臂反向follow/ownership保留。仅京叶主线display记录改变、全部physical站点/区间/里程及其他线路定向比较精确不变，source与lane replay均相等。两现有JS测试文件12/12通过（log/private/tmp/jtm-keiyo-west-focused-tests.log），包括旧tail stage replay、未知follow/hub/反向环引用拒绝及altered西臂native ruler拒绝。一次增量build成功（/private/tmp/jtm-keiyo-west-build.log），三京叶compact记录与源精确一致。Kisuki Keiyo Inspector只刷新compact并重签正常重开。
Root实际查看`keiyo/after-west-shared-main-context-overlay`及`main-fork-{overlay,basemap}`、`inspector-fork-view3-{overlay,basemap}`配对；主图西shared段呈单一连续红代表、分岔前独立进路保留，近fork前300m融合段仍可有两路径，不把该接续段当全共享段重复。主图context近旧camera（中心相同，distance6237.3对旧6242.3），非严格exact before/after；source物理不变。该有限scope支持西臂重复修复，不证明整个3.78km逐轨居中或市川塩浜站体。京叶东fork小折点、南船桥platform group中心仍待证；全线未勾选。default/Hakone仍before资源，default旧checkpoint29781/92216失败4暂停未resume，旧receipts保留。
南船桥定向调查：003761点是N02 14127中点；距cache主轨173053163约8.94m、另一主轨173053168约38.62m，内侧1424469770/1424469769标为siding但无platform-number绑定。不能凭tag直接排除客运折返或以两主轨平均猜平台组。官方图下载403未目视，缺平台1–4与地理轨道绑定，不改站点/physical。资料取得状态见`keiyo/sources/minami-platform-source-attempt-20261011.md`。
checkpoint兼容性代码已审查：BatchCaptureController.configure按viewpoint、intervalDependency、lineDependency、referenceDependency及旧immutable identity-plan/receipt验证复用，允许plan变化后仅受改动依赖失效，未要求清空92k。尚未刷新default或执行恢复，不能宣称checkpoint增长。


2026-10-11京叶东侧接缝小折点修复：用户原文「这里确实有一个需要修复的小折点」。缺陷在真实fork以东约122m的display index45，旧N02 alias[139.96244,35.69156]与测绘链入口接合造成+28.45°/-23.66°短折；仅换为同轨way180845361既有端点[139.9623587,35.6916424]（位移11.75m），邻近三转角变为+7.27°/-6.92°/-2.47°。真实fork index40及其余支持点保留，东臂与主线共享显示同步，西臂不改；所有physical身份、站点、区间及里程逐字段比较不变。旧stage→新stage重放、未知reference拒绝及native measure迁移经源审查，独立Sol审查无可操作问题。新增行为回归先RED，修复后两现有JS文件13/13 GREEN（/private/tmp/jtm-keiyo-seam-focused-tests.log）；唯一增量Catalyst构建成功（/private/tmp/jtm-keiyo-seam-build.log），3条京叶compact记录精确匹配源。
Root实际查看before/after-entrance-seam-inspector-{overlay,basemap}同camera配对（35.691562,139.963247,altitude1245,z17）及after-entrance-seam-main-{context,detail}-{overlay,basemap}；生产detail中心35.691636,139.962359,distance1103.9，2 lines/1 overlay/493 vertices/budgetDrops0。原接缝折点消失、真实fork保留，共享尾段连续。Inspector smooth-to-display诊断不作为Apple同轨偏差，生产before/after无exact camera比较；有限局部关闭东侧小折点，不作京叶全线／全国验收。
南船桥官方April2025平台图已通过现有IAB pageAssets取得并实际目视，保存keiyo/sources/jreast-minami-platform-1f-2f.png；此前curl403不再意味着图面未查看。图确认1/2、3/4两个客运岛，内侧折返轨不能凭siding标签排除。缓存没有编号平台地理feature，北内轨oneway方向与官方西向出发不一致，仍缺platform-number与WGS84绑定，不猜平均中心、不移点。
当前主App为本次build，隔离空行程库493399B4-217A-443B-9B43-7981F0736B57，networkON，以上detailcamera，process session97278，log/private/tmp/jtm-keiyo-seam-detail-production-native.log。Kisuki Keiyo Inspector已刷新compact、原v5 binary；default/Hakone仍before资源，default原checkpoint29781/92216 failed4 pending62431暂停，未resume，旧receipts完整保留。无build/solve/capture重任务运行；南船桥定位及唯一README剩余范围继续未关闭。


2026-10-11本继任资料：
- [南船桥地理平台绑定](keiyo/sources/minami-platform-geobinding-20261011.md)及其中原PDF/现场照片，官方两岛＋北高速/南广场地标＋当前native四轨一致支持北→南1/2/3/4。`keiyo/before-geobinding-main-detail-{basemap,overlay}`为root实际同camera原生基线；[局部显示投影依据](keiyo/sources/minami-native-display-reference-20261011.json)另记像素近似及误差边界。
- [其他线路primary调查](remaining-lines-primary-research-20261011.md)：JR九州当前北段停运/南段恢复，木次定位证据缺口，京阪上栄町官方错列月台图。`kamisakaemachi/sources/keihan-station-505.pdf`及PNG已root实际目视。
- 上栄町`kamisakaemachi/current-inspector-station-z18-*`与`current-main-station-detail-*`同camera配对及`current-main-station-card.*`，root实际检查。局部连续、卡片京津线成员确认；站体东侧横向边界/轨道中心仍待证，未改几何。


2026-10-11南船桥最终after：`keiyo/after-passenger-centre-main-detail-*`、`main-context-*`同camera overlay/basemap PNG/AX及`main-station-card.*`，root实际查看；detail匹配before-geobinding camera。最终2/2 focused及增量日志见README结果段，平台绑定／像素近似配准见上条sources。三个Inspector当前资源已重开，默认单次恢复后29,754→29,931，失败4；[实时checkpoint证据](keiyo/after-passenger-centre-default-progress.json)。有限偏南显示缺口关闭，整线／全国不勾选。

## 肥萨线日期接入

[Hisatsu时间记录](hisatsu/README.md)保存官方实际恢复日期、原始吉松边界及聚焦源重放/显示产物/JS/Swift证据。6月28日计划已更正为7月12日实际恢复。没有新增原生日期截图、全线对齐结论或全国重建；历史北段偏移风险仍开。

[Hisatsu原生日期检查](hisatsu/README.md)已完成：native/含7组日期编辑器PNG/AX、构建日志、result.json与Current恢复证据；支持可见区间时间切换，不关闭历史几何风险。

- 2026-10-11区域地图/图像算法：`keiyo/west-long-review/sources/REGIONAL-MAPS.md`（GSI航拍3尺度）、`shiohama-analysis-input.json`与`analysis/{analysis.json,candidates.geojson,review.html,review-browser.png,README.md}`。真实Apple铁路轨迹有图像支持，平台中心未证明，候选非source变更。

- 市川盐滨最终source/native：keiyo/west-long-review/main-shio-final-{detail,boundaries,long}-{basemap,overlay}.png/.ax.txt、main-shio-final-member-card.png、inspector-shio-final-view{17,18}-{overlay,basemap}.png/.ax.txt；sourcehelper/evidence与聚焦结果见analysis/README.md。
- 东京/品川：tokyo-shinagawa/source-review.md、native-review.md、main-{tokyo,shinagawa}-region-{basemap,overlay}.png/.ax.txt；仅记录范围无新缺陷，未新增几何修改。

- 第61条原生抽离：apple-map-extraction/README.md、native/{final-clean.png,final-clean.ax.txt,shiohama-extracted-basemap.png,shiohama-extracted-basemap.ax.txt,zoom-invalidates-result.ax.txt}、native/shiohama-export/{basemap.png,analysis.json,extracted.geojson}；原生真实像素分析与站点搜索/文件导出，不是绘制模拟结果。


第61条最终交付与资源协调（2026-10-11）：Mac Inspector原生抽离/对比/文件导出已实装，三个聚焦Swift回归通过，最终Catalyst增量build成功；实际京叶终点市川盐滨z18抽离72/90支持，2段候选，中位0.48m、P95 2.90m，同名Apple车站POI与构建点7.27m。最终图和原生导出见apple-map-extraction/native，边界见该目录README。京叶窗口保留完成结果，无手动分析运行中；Hakone已更新但未运行。
默认批量当前并非运行：Audit the full iOS codebase（01a12d77-271a-7eb2-a55c-46995376121d）请求暂停重任务，已核实该聊天直接用户授权“Yes, coordinate with that chat”并发送保持状态。默认PID 46271在启动收据校验中SIGSTOP，STAT Ts；captured 73834/failed 6/pending 18376；planDigest 1e616b862b86493543065ce15a1a7c0961f8dbc481124be66005108c9997587a，unavailableIntervalCount 0。内存/计划/历史证据保留，记录/private/tmp/jtm-native-extraction-default-hold.json。等待审查聊天释放资源前不要新build/test/capture；收到释放后先核实PID/executable/debug.dylib是否被替换，再SIGCONT或安全重启。此前“待恢复”状态由本条替代。


资源释放后恢复（2026-10-11）：审查聊天报告全部聚焦job退出、默认产品未覆写。root核实同一PID 46271为原Inspector --batch-all、STAT Ts，只发送一次SIGCONT，随后STAT Us。原checkpoint实际从73834增长到73939，failed 6、pending 18271，planDigest保持不变，unavailableIntervalCount 0。未重启、未删除输出、未另起手动分析或重型检查。本条替代此前hold状态；既有进程未重载审查聊天随后修改的X02共享admission代码。证据apple-map-extraction/native/default-resumed-checkpoint.json。


架构检查后恢复（2026-10-11）：审查聊天报告heavy槽释放、全部job退出且未更换Inspector产品。root核实同一PID46271/--batch-all/STAT Ts后仅一次SIGCONT，实际STAT Rs；checkpoint captured从78146增长至78260、failed从6增至7、pending 13949，原planDigest不变、unavailableIntervalCount 0。新失败保留、不自动重试。未重启/删除输出/并行manual分析；仍为既有载入版本，不作为新Core接口或admission运行证据。证据apple-map-extraction/native/default-architecture-resumed-checkpoint.json。本条替代上一hold状态。


第62–66条当前结果：三个独立检测器串行完整采集15个站间区间116/116视点（含两端及短尾），失败0；root逐一看完全部配对，随后主app四个重叠范围覆盖全区间，加东京/品川.003站内和成员卡。可见代表线连续、实际fork/独立平台走廊与跨公司平行保留，未发现新source修复项。详见tokyo-shinagawa/station-throats/results.md和full-intervals/scope-results.json。地下/屋盖精确位置和新干线平台中心仍证据不足，不勾整站地理通过。主图移动事件配对按实际大崎相机更名；用户已明确由root继续、暂不移动主图。当前三个检测器均idle(42/42/32已捕获本轮)，原默认全国capture进程已不运行，不把旧恢复状态当现况。按第66条继续木次→箱根→其它历史未完项；保持原唯一清单。


2026-10-12第66条完整区间/整线续查：
- Tokyo/Shinagawa15区间116views：tokyo-shinagawa/station-throats/results.md、full-intervals/scope-results.json及Main同camera配对。
- Kisuki17区间262views：kisuki/whole-line-reuse-record.json、full-line-review/review-intervals-*.md及contact页。南大东source/最终24views与Main局部/两侧整区间/全线图：kisuki/full-line-review/minami-daito-source-result.md、final-minami-daito/{coverage.json,extraction-native,main}。
- Hakone10区间59views：hakone/whole-line-reuse-record.json、full-line-review/review.md及review-viewpoint-manifest.csv；山崎source/最终7views/Main局部/全线：yamasaki-display-repair.md、final-yamasaki/{coverage.json,main}。
- Hisatsu27区间394views：hisatsu/full-line-reuse-record.json、full-line-review/{north-review.md,south-review.md,north-coverage.json,south-coverage.json,main}。北273仅历史地理，南121分开；时间机制的既有7日期实际native证据在hisatsu/README.md，仍有效。
- Keishin6区间30views：kamisakaemachi/whole-line-reuse-record.json、full-line-review/{review.md,coverage.json,main,regional-aerial}；原生抽离before32%支持/中位3.4m/P9512.2m、1同名POI8.5m，与轨道认轨及GSI区域影像分开记，未以POI替代平台中心。
- Keiyo19区间183views：keiyo/whole-line-reuse-record.json、full-line-review/{review.md,coverage.csv,identified-passenger-legs.md,regional-aerial,main-before-bridges}；park-bridge-display-repair.md记录main11/12与葛西alias source修复，尚待新包native/Mainafter。

完整视点原件的精确路径由各manifest保存；native复用仅在同line/render依赖、interval identity、viewpoint匹配且configure验证后计入。计数仅证明采集/目视覆盖，不授予地理PASS；原有未知/树林/隧道/地下范围继续留在唯一README。


2026-10-12最终补充：大崎最新碎线before为osaki/latest-fragments-before，最终完整4区间29点contacts/Main与结果为osaki/final-station-representative；本乡三丁目before为hongo-sanchome/main-before，最终4区间17点contacts/Main、真实extract export、结果为hongo-sanchome/final-display。Keishin上荣町after实际dot/card为kamisakaemachi/full-line-review/final-station/main；京叶两桥/全受改区间/主线及两臂/完整3.78km共享与fork为keiyo/full-line-review/final-park-bridge/main。有效荒川西视窗使用arakawa-west-fixed-camera-after（旧arakawa-west-after相机偏离，不验收）。注：早期固定目录闭包误存的Osaki/Hongo/Kasai/Edo主图资料已原样复制至对应目录，保留原始文件。


2026-10-12第69–71条：mita/results.md汇总最终26/115完整native人工覆盖、三app与Main验收。before/final具体视点在mita/whole-line-before及whole-line-final/coverage.json；源身份/OSM诊断未采用候选/区域航拍在primary-sources，115实际蓝色glyph分析在cartography-analysis。最终独立抽离及原生导出在extraction-final；Main完整范围、两个近景、成员卡与正确最终相机在main-final。mita-west-stale-card-process-*不是有效最终配对。repair-lessons-20261012.md汇总每次修复的原因、失败尝试、结果、界限；已写回全局铁路纠正skill。

2026-10-12 prompts 72-74: latest Osaki join results and 5 complete intervals /41 final views: osaki/branch-join-recheck/results.md, final-native/coverage.json, final-native/review.md, main-final. Keiyo same-class follow-up: keiyo/junction-recheck-20261012/results.md, native-review.md, coverage.json, production-join-probe.mjs/out, main. All 4 complete intervals /60 fresh views reviewed; whole-both-arms-endpoints and left-running-final show both southern endpoints unobscured.

Terminal rule and source/render trace: terminal-station-rule-20261012/results.md, nishi-takashimadaira-before-overlay/basemap PNG and AX. Existing endpoint/dot identity is preserved; station-box-centre correction requires reviewed per-platform anchors.

2026-10-12 ordered continuation evidence: ordered-continuation-20261012/results.md and native-review-notes.md. Fresh Main pairs cover all six original remaining groups with reused complete94/1044 scoped baseline. Gora frozen native station-frame evidence is gora-terminal-centre/native-before; source owner repair-hakone-gora-terminal-display.mjs, complete4-view after and actual Main terminal/full interval/whole line/card. Keyboard live AX/PNG for Main/Inspector/Route/Through and ios/README.md menu table; all four final target builds passed, three Inspector clones updated. Shinagawa reopened three legacy forks plus identified Yamanote–Hinkaku separation and four directional Osaki switches traced in source, with a fresh southern-pair Main view; unpromoted then revised candidates in shinagawa-fork-candidate, complete15-view native candidate images/metadata preserved in accepted-native-candidate. The rejected Tokaido59m station hook and corrected200m longitudinal taper are both documented. Final production source/runtime follow-up still pending; candidate acceptance is display cartography only.
