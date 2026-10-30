# 铁路检查与修复流程

范围为既有排序输入中的全部 658 条独立线路。顺序继续使用 `ios/refactor-parallel/alignment-passenger-local-recheck-20261010.json` 中 lineID 的首次出现顺序；进度记录在 ordered-continuation 的现有 `chat-handoff-20261017/audit-status.md`，证据放在各线路目录。不另建重复状态库。采集完成、已查原图、证据确认、修复应用和 Main 确认分别记录，不能互相代替。

## 每条线路的操作

1. 先读取本线当前显示输入及既有 receipts。按 receipt 的命名 identity plan 和真实目录映射核对本线几何、站点身份、渲染合同；目录序号不是线路身份。几何仍一致的旧图可以继续人工复核；旧合同不自动升级为当前 renderer 验收。只补缺失视点或发生相关变化的范围。
2. 同一个 Rail Diagnostics 接受一个 `DiagnosticRequest`。限定本线、区间、比例尺和输出模式，通常保留 basemap + smooth。App 自动处理该范围全部 pending 视点；不逐张操作。同一候选生成器列出所选区间转向至少20°的显示顶点及前后段长度，人工列表和 agent JSON 读取同一结果。小于20°的偏移仍由现有 lineOffset 审查覆盖；转角候选不自动删点。需要辨识站台或邻线时直接选择 imagery，不另建影像采集器。精确补拍使用可选 viewpointIDs，取自相同比例尺/视口设置下 prepare/capture-index 的实际 ID，并核对经纬度；zoom变化会改变采样间距，不能沿用旧pointOrdinal推断同一相机。切换设置先prepare，读新plan再选准确视点；仍走既有 start(viewpointIDs:) 路径，captureLimit 在视点选择后生效。该新增请求字段已通过13项聚焦测试，共享Release构建及实际键盘、人工续拍、范围计数验证已完成，证据见诊断App的Evidence/20261018-exact-viewpoints。
3. 已运行 App 可通过 `open -a /absolute/RailDiagnostics.app /absolute/request.json` 提交下一份请求，严格校验后直接执行指定action；**Run ⌘↩**用于当前任务续跑或已选最近任务。人工 **Open task ⇧⌘O**、原生文件打开和 agent 请求使用同一严格请求格式、同一 session。完成数量及 result 路径才是采集结果；不能把 open 命令成功当作完成。此前预览版的热打开成功、错误输入及忙碌拒绝证据保留在 `Evidence/20261018-hot-open`；直接执行路径已通过最新 Debug 原生实测：宫津线请求无需额外 Run 完成28/28、0失败，result/run-status 记录 PID52148、invocation `A0B99B1B-9B1E-4639-B349-CC356793051A`，父会话实际查看了完成 UI；证据见 `ios/auxiliary/RailDiagnostics/Evidence/20261018-direct-dispatch/`。一次已授权的 `open -n` 返回0，随后进程观察只有同一 Debug exe 的52148，实测为保持单进程，并非拒绝错误。此前普通沙箱 open 的-10827仅为受限尝试，不代表真实单实例结果；日常提交仍使用既有 App 的普通 open 路径。
4. 查看原图并确认本线身份。站台、上下行、隧道/高架和进出站证据按实际缺口补齐。邻线位置、共享站名或蓝色图例不能决定本线走向。地下真实曲线不可因折线尖角而拉直；优先找运营商工程资料和明确本线方向的几何。 审查结论直接保存到本session已有的 `review-notes.json`：人工表单与agent共用 `DiagnosticReviewLedger`，沿用当前candidate ID、requestID、dependencies和引用证据。只散列实际引用的证据文件；保留旧记录/history，不改生成任务或把result改成通过。证据不足记 `insufficientEvidence`，已查看范围写在note；重开App后才报告实际加载数量，文件写入不等于已原生加载。
5. 对确认的显示错误，只改必要的本线控制点或显示站点。保持物理站点、ID、里程及 segments；只有独立物理证据才能改变拓扑。复用既有生产 builder 更新受影响 parts、量程和依赖引用；保留其它区间及已确认站口修复。同线后续修复扩展同一 authority，不另造平行脚本。候选与原图统一保存到仓库内被 gitignore 的 `railway-evidence/local/`；完成写入后沿用该 iCloud Documents 目录的系统同步。先核对实际排除/运营状态：夷隅线当前 substitute_bus 没有连续描边 part；既有 Main 构建器仍输出普通分区间几何。保留该路径和运营状态，不虚构连续 part 或解除排除；以实际交付 chunk 和 Main 像素核对，不能从排除名称推断整线不可见。
6. 以源码复核和一个有意义的聚焦回归解决具体问题。候选只采受影响的完整区间及必要相邻咽喉，先复用未改变的外围证据；确认后直接应用，不重复请求例行许可。Main 在一批确认修复后增量构建，针对实际受影响的多线构图查看同视点 ON/OFF；不为每个普通区间重复构建或打开 Main。
7. 用现有线路报告写清改动、来源、真实通过结果和未解决范围，随后进入下一条。证据不足的具体位置保持待证，不能让它阻止其它可确认位置推进，也不能记整线全部通过。

## 站点与轨道同时贴合（2026-10-20 用户明确要求）

站点仅落在蓝色站台框内，不算对齐。先隐藏产品图层，辨识 Apple Maps 上实际可见的本线轨道及本线站台组；显示站点应落在该轨道上，并在轨道允许的范围内尽量接近站台框的纵向中央。不能为追求框的几何中心把点放到轨道旁，也不能吸附到邻线。终点同样按本线框的纵向中点投影到已辨识轨道，显示线须准确结束在点上。 双股道之间可能是岛式站台或屋顶，不能把两条不同运行轨道的平均位置当作一条轨道；先辨认每条轨道的自身双轨/枕木符号，再选择本线的一条实际运行轨道。标准图与影像各自使用实际返回投影；相机和比例尺一致也不代表底图内容已按轨宽精度配准。像素控制点需保留原尺寸：工具返回图像时使用 `image(image_url, "original")`，仅给 `view_image` 设置 original 仍可能在转发时缩小；记录裁剪时保留原图原点和未缩放比例。

蓝色站台填充的描边也可能与铁路同色。选点前须区分运行轨道、站台/屋顶填充边界和文字；不能仅凭蓝色峰值认定新增股道。沿候选两侧查看轨枕或同一轨道符号的连续性，并核对弱描边是否恰为均匀填充色与背景的分界。标签遮住中部时，用两侧已确认的同一股轨道约束参考中心，并明确标为参考推定；不得为声称“原点可见”而选站台边缘。退回错误股道提议时同时撤回其进出站控制点，保留原提议历史，重新建立真实合流证据。

每个新增控制点须同时检查未缩放局部与较宽的连续轨段；可用 nearest 放大辅助阅读，但坐标始终取自原图。局部没出现轨枕不证明它是平台边界，须扩大到能判断重复横线和分合轨的位置。文字覆盖的点不能列为直接可见轨道见证；改选相邻清晰符号，或明确保留参考推定。先做这些检查，再组装候选，避免把投影换算正确误作轨道身份正确。

修复范围同时包含站点显示别名、两侧完整站间及实际 lane/follow 后的最终描边，核对共享端点、原生 station slot 和显示量程；不能只挪站点留下折角，也不能只删局部凹折就宣称侧偏已消除。保留物理站点、拓扑和里程。最终在 Main 同镜头 ON/OFF 原图中分别确认贴轨、框内纵向位置和进出站连续性，三者分别记录；轨道或框端被遮挡时，写明具体缺口，不以“框内”替代通过。

高崎商科大学前首次实际Main对照确认站点/描边侧偏，随后已按本线轨道与蓝框纵向位置应用显示站点及相邻#3/#4修复；最终Main确认见该线station-track-native-review-20261020，未接受的外侧站喉保持明确。局部中间支持点修复本身不代表该站通过。

## 串行窗口与效率约束

持续优化比较流程，但以实际瓶颈为依据。2026-10-20接续复用三条线完整的命名plan/原图，只补86缺失视点；上信微小支持点先prepare高倍率plan，再只拍有重叠的2/12准确视点，而非重拍整线。保留完整区间上下文、具体未决范围和失败输入。注册表升级后，诊断启动须安装同一身份provider；车站请求按本线`lp`成员选择公司车站及其源码，不能把共享显示站群码当成本公司站台码（高崎上信002393与显示站群002389不同）。新增流程改进继续沿用统一App的人工、agent和标注快捷键入口，不另建采集器或自动验证循环。 像素换算优先使用每张原图实际返回的snapshotProjection，不以请求zoom替代实测：高崎商科大学前imagery请求z20但实际返回z19，而standard返回z20。准备后改变viewpointIDs须使用新的独立session，保留身份保护拒绝记录，不覆盖旧证据。

跨聊天共享一个 heavy/native 窗口，通过现有 audit-status 和 architecture-coverage 明确借出/归还。窗口被占用时继续有界源码、证据和原图研究。Mac 锁定时继续这些独立工作，UI 验证等待解锁。

不重建全国验证流水线、完整矩阵、自动交付循环、全树哈希或常驻守护程序。全部线路通过逐线工作推进；App 内保留自动范围采集和运行时校验。无需错误修复的线路记录实际检查范围，避免为了“全部修复”制造改动。

持续侧偏先检查两端保留点，再生成候选。2026-10-19三岐线西野尻的z19近景表明，旧v9..12也偏离自身蓝轨，随后红蓝交叉、侧差反转；仅改v1..8会把问题留在接缝。自身OSM链虽已确认客运归属，坐标却朝截图偏差的反方向，不能直接替换。先prepare新比例尺计划，再选有重叠的视点核对实际边界；边界不足就记录具体缺口，继续其它线路，不进入无依据的候选、构建和Main检查。

## 当前执行实例

- 横滨、糸鱼川：本线站台和进出站方向证据已补齐，正式显示修复应用；5 项聚焦回归通过，Main 构建及实际 ON/OFF 对照完成。
- 田园都市线：120 张有效历史视点继续使用；3 个缺失区间仅补采 13 张。区间 3 的真实复合转弯有官方工程证据，14/14 候选采集及原图复核后已应用修复；4 项聚焦回归通过，保留真实弯道。
- 京叶线海老川：20/20 候选采集后已删除一个错误显示点，同步既有共享区段；原有站口修复保留。西侧分岔已按明确本线客运 route14656632 修复，18/18 原生候选采集后应用，下方共享段及盐滨站尾保留。
- 山手线品川：只补失效区间，8/8 候选采集后已修复显示端点横向拼接折角；保留原纵向位置，整座站台的纵向中心仍待核实。
- 曳舟：本线双轨及高倍率影像确认短横向折返，删除一个显示点，11项回归通过；物理源、里程和押上B3端点保留。
- 丰桥东田本线：只补采缺失28视点，全部56张原图已复核；真实路口转弯保留，未发现有证据支持的错误走廊修复。精确站台中心仍待证。
- 总武线西大井—武藏小杉：中马込偏移已按新鲜本线来源修复，4项聚焦回归通过，20/20原生候选采集并复核关键原图后应用；局部Main同镜头ON/OFF已完成。
- 长崎电气轨道本线：新增53/53视点的106张原图全部复核，无已确认假尖角；真实街道转弯保留，浜口局部横向差异继续待本线来源。
- IR石川金泽：本线假V和北侧弦化已修复；5项聚焦回归及后续1项实测引用保护回归通过，13对标准图与6对影像已审阅，本线客运停靠节点和官方站台组补足归属。已应用并完成局部Main同镜头ON/OFF，不借用东南新干线；整线及精确站台中心仍未验收。
- 城北线：既有40对原图已审阅；中小田井弦化按明确双向本线客运轨道修复，5项回归通过，13对候选原图及局部Main对照完成。西侧保留偏移及精确站台仍待证。
- 宫津线：第9区间假凹折已应用，32对候选原图及局部Main对照完成；第15区间自有连续客运链扩展同一authority，4项回归及11对原图复核通过后已应用，2026-10-19已完成Main同镜头ON/OFF；第9区间证据保留。
- 上述四处新修复已共用一次Main构建，各同镜头ON/OFF原图与实际交付资源已核对；详情见ordered-continuation的four-repair-main-batch-20261018.md。后续线路沿用既有队列，未检查范围保持明确。

- 2026-10-19续检：宫津15、夷隅10、北信浓单点横跳均完成实际Main同镜头ON/OFF，6张原图已查看，复用既有构建和相关回归。海鸥线仅补8视点，渡良濑溪谷线仅补40视点，同一进程87042均0失败；全图人工复核单独记录，不据数量判整线通过。

- 2026-10-19花轮：已有agent ledger通过带标注的⌘↩原生加载3/45；近景确认后只删后一组旧v5，保留前一组和真实弧线。一个有意义回归RED→GREEN；完整站间4对+近景1对原图复核后应用，同一Main增量构建及局部ON/OFF完成，物理/站点/里程不变。北松江55缺失视点继续使用同一自动请求实现，未增加入口。

- 2026-10-19北松江高之宫：本线来源与准确z19近景确认交替三点阶梯，只删旧v15/17/19，不整体平移走廊。既有自身follow来源后缀同步约−3.16m，目标片段保持；1项RED→GREEN、完整站间5对+近景1对及Main同镜头ON/OFF完成。布崎前窄窗口会造新24.37°接缝，已否决，真浅S及站点暂保留。

## Local evidence storage (2026-10-20)

Use `railway-evidence/local/diagnostics/sessions/` for new diagnostic sessions,
`local/requests/` for explicit requests, `local/candidates/` for repair candidates
and `local/build-logs/` for focused build receipts. These paths are Git ignored.
The existing iCloud Documents location supplies automatic closed-file sync;
remote upload completion remains a system state, not a capture verdict.
Historical raw evidence was moved by same-volume rename with old-path symlinks;
reuse unchanged source/pixel evidence through those links, preserving immutable
requests and file hashes. Do not recapture because only the storage path changed.
[Storage layout](../../railway-evidence/README.md) describes the local receipts.

When a q4 support touches lettering or a pale blue casing, reframe or reuse an applicable q2 original for a visible control. A deepest blue pixel alone can belong to text, a sleeper or one rail edge. Resolve continuous same-track thin edges and transverse sleepers in a wide crop before choosing its centre; preserve reference-assisted aliases under labels as such. A new collar must also be ordered against the first retained body point: the diagnostic sharp-turn candidate can expose a small backtrack even when public grooming later hides it.
