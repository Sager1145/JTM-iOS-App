# 铁路修复经验 — 2026-10-12

本文件记录既有唯一检查台账中各次修复的原因、失败尝试与可复用经验，不另建执行清单。原始图像、相机、来源和验证结果以各专项 `results.md` 为准。

| 修复 | 原因和采用方法 | 失败尝试或关键经验 | 实际结果与界限 |
|---|---|---|---|
| 木次线南大东 | 以已识别 JR 客运轨道与区域航拍修正显示点及相邻进路 | 移点后的边界出现短垂直台阶；用同轨方向支持和平缓过渡消除，而不是继续平移整个区间 | 5 项定向测试、两个完整区间 24 个最终 native 视点、Main 点/卡/相邻区间与整线检查。最终抽离仅 15% 有效支持，不能据此证明整线测绘精度。见 `kisuki/full-line-review/final-minami-daito` |
| 箱根山崎 | 在完整区间中识别局部弯道，与客运 way 和区域俯瞰依据对应，只修正有界显示段 | 平滑保留错误源位置，不能替代同轨认定；真实折返和林地隧道不随局部修复抹掉 | 12 项定向测试，受改完整区间 7 个 native 视点和 Main 近景/整线。塔之泽及出山的不足证据仍明确保留 |
| 京叶葛西临海公园、江户/荒川桥 | 确认两桥的主客运链与区域航拍，对点和两个完整进路区间修正 | 一次 Main 相机偏离，失败配对不能当正确相机的证据；共享线和两条支臂需要真实 Main 范围检查 | 15 项定向测试、最终 19 个 native 视点、Main 两区间/两桥东西侧/全主线与两臂。地下东京精确线位仍未测绘验收 |
| 京津线上荣町 | 修正局部显示锚点并保留既有大谷来源和滨大津真实 fork | 新旧 OSM tram/rail 标签日期应区分；不能因标签变更就推断乘客拓扑变化 | 5 项定向测试、两个完整受改区间 10 个最终 native 视点、Main 点/卡/两侧检查 |
| 大崎 | 按用户明确指定的局部 JR 代表显示：南侧两条合为一条进站，北侧一条连续出站 | 旧 lead-in 产生北侧碎片；只改站周显示代表关系，逻辑成员与临海线独立身份保持。自有生成阶段须可重复执行，不能据一个阶段重放证明整个历史脚本幂等 | 2 项 JS 和既有 Swift 单项，三个检查 app 的四个完整区间 29 个视点，Main 合流/站点/北侧/成员卡实查 |
| 本乡三丁目 | 丸之内与大江户两个独立公司/层位分别用证实的 stop_position 点位辅助显示 | 同名搜索质心会混合独立平台组；点与其进路同步修正。不要把原有外围弯道误判成新站点接缝 | 5 项定向测试、四个完整区间 17 个视点、Main 两点/成员卡/关联四区间。地下精确轨道仍不宣称测绘精度 |
| 都营三田线 | 全 26 区间 115 张干净底图，识别对应的蓝色地铁示意线；简单结构按底图线路直接对齐。北段实体铁路已近对齐，保留 0–5 | OSM 全线替换在白山弯道偏到另一侧，部分 stop 中点会移动百米，未采用。首次像素拟合每逢 OCR 缺口返回旧源，制造三角折线，未采用。确认同一简单走廊后，用顺向的相邻像素与曲线切线连续衔接。40 米搜索漏掉三田—白金高轮约 55 米弧线差异；按实际范围扩大该区间 | 6 项显示回归与 6 项原生抽离回归通过；全线最终26区间115点均人工复查，三个专用app及Main整线、五个重叠范围、两处近景和成员卡实际验收完成。见 `mita/results.md` |

肥萨线的停运/恢复使用既有日期边界机制；实际切换的七个日期已在 `hisatsu` 留证。日期逻辑与地理线形纠正分别验证。

## 操作与技能维护

大崎接头的后续反馈已重新打开原验收：源共点和线条数量正确，仍会在最终 lane/follow/family 绘制阶段错位。站南215米 ownership 切口受到300米 lane kernel 影响；两方向不同显示 ruler 又在相差8米的南叉之间交接。最终统一方向 family 的代表显示 path/ruler，物理轨道、方向限制和里程保持。仅端点测试曾漏掉中段36像素的 identity-follow 权重稀释；新增每10米全段生产回归，并在 Swift/JS 对完全相同的 geometry follow 省略几何权重、保留 Main coverage 数据。三个专用 app 最终5个完整区间41视点已全部人工复查；Main 实际结果继续记于 `osaki/branch-join-recheck/results.md`，不沿用此前碎线数量验收。旧圆弧/固定fixture测试的失败另行保留，不能写成所有测试通过。

- 三个专用 app 优先检查，完整站间区间包括端点、末尾短段；其单线预览不替代 Main 的 lanes、共享显示、圆点和成员卡。
- 本轮发现 Debug 业务代码实际在 `RailAlignmentInspector.debug.dylib` 中。只复制启动 executable 会继续载入旧界面；同步完整 `Contents/MacOS`、重签并从实际界面确认新模式。
- 相同来源依赖可复用历史证据；几何变化后完整相关范围重新捕捉。采集计数不是人工地理验收。
- 每次修复在本台账添加原因、被否定的方法、采用的变更、保存的不变量和实际结果；只把可复用规则写回全局 `jtm-railway-audit-repair/SKILL.md` 和 `references/lessons-zh.md`。
- 本轮两次定向 Swift 测试曾等待内部只读 `git status`，零 CPU 且无编译。确认具体子进程后结束该只读查询，测试继续并完成；不因等待就启动第二个重叠重型任务。

- 原生成员卡是独立 sheet：明确关闭再退出，重开后确认实际相机和窗口类型。旧 sheet 句柄不能当作新主图，失败截图保留过程证据并重新配对。

Terminal placement: synchronize display station coordinates, adjacent display endpoint and native part/slot/ruler. Review final lane/follow endpoint against the correct Apple station-box centre. A loop seam, fragment endpoint, POI or general building centre is not terminal/platform-centre evidence. User rule recorded in terminal-station-rule-20261012/results.md and global railway skill.

### 2026-10-12 强罗终点：站框中部与认轨中心的交点

强罗常规铁路旧显示终点位于站框北端，原生图与独立目视确认可向南收束约33米。采用 Apple 底图所识别站框的纵向中点（像素 y=391.5），与已支持的常规铁路轨带相交，得到 [139.04835765357217,35.25062244063085]；西侧斜向缆车独立保留。建筑包围框的几何质心不能代替轨道横向中心，未采用偏离轨带的候选。

仅修正 display station 005231、interval9尾部与native part6 ruler，末端300米lane收束到零；physical站点、区间、里程、折返分腿、前9区间及其它线路不变。新增5项聚焦回归通过，覆盖原生坐标证据、物理字段不变、slot/ruler、z16/18/19生产末端和拒绝未知引用。三个检查 app 已更新数据，完整雕刻之森—强罗4个after视点已采完；Main增量build成功；相同近景、完整受改区间、整线及成员卡已实际查看，终点和圆点共点，缆车独立。单线预览之外保留Main实际证据。

### 品川分岔复查：共点、交叉与分岔分别认轨

三处旧N02代表共点分别对应平行站场、立体交叉和已分离后的品鹤线弯道，不能看到黑轨X就新增switch，也不能把横须贺13–15平台组拉回共用坐标。区域GSI俯瞰图与命名方向ways先确认身份，再在Apple对应轨带确定显示分离。4.19%图像支持不足以自动移点；外部橙色候选须覆盖完整相邻区间，插值／单方向缺口明确标记，完整图对照后决定接受或拒绝。当前候选尚未改生产包。

快捷键经验：scene级commands调用已有动作，availability跟随状态；键盘布局影响方括号时采用⌥⌘箭头。Debug app业务在debug.dylib中，更新clone须复制完整Contents/MacOS并重签。iOS17辅助目标用searchable(isPresented:)实现CmdF，不引入iOS18-only searchFocused。逐target增量构建与实际键盘动作足以验证此低影响变更，不建额外验证流水线。

### 大崎共享段：完整曲线与分岔后的范围都必须检查

品川候选接入前，两个端点检查通过，完整215.48米共享段却在z19出现20.43像素偏差。raw支持与里程对应相同；缺陷来自不同延伸方向的独立平滑以及普通300米follow混合。仅拼接更长raw路径会移动真实分岔，已拒绝。

修复应由同一runtime绘制契约控制：共享段内采用同一已确认路径，区间外不外推影响独立分支。真实共享边界须在owner、canonical、follower的各自米制ruler上同步，并贯穿spline、canonical taper、own taper和fillet；只保护原vertex索引会在平滑重建索引后失效。边界不应增加公开station anchors或slots。canonical taper缓存也必须区分不同硬边界，重叠普通follow不应稀释已确认exact共享段。当前修复仍在聚焦验证与原生集成中；此段记录已复现原因和必要验收范围，不宣称runtime通过。

最终源码聚焦检查通过后，实际built chunk仍重现20.407像素：follow/family的0.1米取整破坏精确ruler。原生builder现只对完整raw严格相同、四端点均唯一支撑顶点的共享段，使用最终7位坐标重新计算精确follow/family里程。近似raw即使round后相同也拒绝；普通插值边界不改。1项针对性builder回归通过；最终实际序列化输入在三个zoom逐10米共享/后300米检查均0偏差。此为算法及built-input证据；Mac锁屏阻断新的UI验收，未宣称像素通过。经验已同步铁路skill两安装副本。

### Current-renderer evidence reuse
Old v4 Hohi24 and Myoko19 receipts cannot certify v5 small-curve preservation even with unchanged geometry and matching viewpoint/identity/file hashes. Actual native dependency restoration correctly rejected them. Preserve historical inputs, recapture every affected complete interval, review all three image stages, then check Main. Do not relax receipt validation or turn capture counts into PASS. Both railway skill installations now record this rule.

### Station midpoint and inset map georeference
Actual Main sidebar insets put the Shingai geographic centre at pixel827/439, not viewport centre605/432. Inverse projection must use AX fullRegion plus complete1211x865 viewport in Mercator; visible corners are a different region. Identify passenger platform longitudinal midpoint and project transversely onto its own rail, excluding forecourt/roof. Shingai trims39.878m displayterminal only; physical/km/main/cusp preserved. Tsubojiri ownership-seam candidate must carry all old support points into the outgoing interval, avoiding a new shortcut. Full adjacent reference comparison precedes apply; actual current native/Main after remains separate. Both installed railway skills record this rule.

### Completed Shingai/Tsubojiri acceptance and scope correction
Both source owners applied; meaningful regressions5/5 and6/6 passed; all77 finalupdated-data nativeviews231panels andMain same-camera station/line/member plusfulladjacentintervalpairs reviewed. Intermediate Tsubojiri is a throughstation: selectedinterval6 endsA/7startsA, but camera-clippedfullpartcontinues southeast. A firstreview calledit423mlongtail; metadataandneighbourview correctedtheverdictwithoutclippingmain. Shingaiindependentspur endsatframecentre. Strictdataonlyresourcebuilder succeeds withpreviouscompiledbinary; Xcodeprojectreadfailed75mustnotbecalledcompilePASS. Initialadhoc/hardenedruntime teammismatch fixedusingexistingconfigureddeveloperteam uniformlyforparent/debugdylib; strictsignatureandactualMainstartupconfirmed, no security protection disabled. Both installed skills include these lessons.


### 2026-10-12：法律线路名称不能决定站台组（Gala支线）

Gala法律上属于上越线，却以新干线车辆进入越后汤泽的新干线设施。compact复用了在来线同stationID坐标，最后120m横切站体。先用区域俯瞰区分西侧新干线长屋顶与东侧常规站场，再用官方运营身份和入站切线判断显示锚点。候选复用已有新干线站内代表点，原来38.16°横向转折变为2.53°纵向延伸；不得由同ID、屋顶中心或这个显示修正推导physical join/follow/family，也不把屋顶下的轨道/具体站台中点说成测绘事实。完整支线外部reference与更新后Main是应用候选的验收门槛，当前此段为候选规则记录。

Gala最终验收补充：完整7候选外部reference和7更新后native视点均全量通过，Main同相机横切折线消失且末点/完整支线/成员保持，owner已apply。GeoJSON referenceLineID必须是接受比较的目标支线；坐标来自另一线路时用独立anchorReferenceLineID保存来源，不能把provenance误当Inspector作用范围。宫内案例同时说明Apple长蓝band与真实航拍站台长度不同，不能把图形中点差异说成物理偏移；只有确认自己的站台组后才改显示中点。

### 姨舍：竞争的真实站臂与新增控制点（2026-10-12）
Main发现北臂偏移，而单线Inspector前期未判出生产接头问题。Apple抽离最长段可能属于西侧真实站臂，必须沿标注主线、双轨符号与连续区域原图认轨，不能按长度选择；分岔区含真实竞争轨道的run仅作身份线索，几何须人工回投。用Snapshot mapRect/尺寸反投影，补一个宽z17框覆盖两个z18框之间的空隙；将代表分岔投影到保留站臂上，保留真实折返与站点。此处显示分岔距底图汇合区域4.82m，不宣称测量尖轨。新增29个控制点后，old suffix25对应candidate54，原始155点与候选184点分别断言；native part点数允许改变，identity/classification/anchors与既有未受影响的松本measure保持。初始focused测试1/6失败揭露旧索引假设，修正后6/6通过。完整19+25候选四联已逐图通过；生产after/Main尚待完成，不能提前关闭范围。

### 雀田：中心线正确仍可能有错误生产follow（2026-10-12）
两个records全部10区间55个Inspector单线视点通过，但Main两组实际底图配对发现支线晚分岔、跨地块。原因是own0–100m反向借用本线7090.952770183906–7000m，末端相距43.786m，300mblend继续把支线拖向错误本线；零lane单线图不含follow，因此不能证明生产接头。旧49mraw anchor-weld是另一个已被display grooming消除的形状，勿误修source。先复查完整0–400m而非站点/100m单点；移除已证明错误的单条共享映射候选，保持正确ownpath、同code注册站点、全部part/physical/km及其他refs。3项聚焦回归实际通过，候选生产Main验收尚待进行。

### 雀田西曲线：重采样及producer尺依赖（2026-10-12）
正确本线被投影到Apple轨带以北向最多9.87m有界修复，source24–34窗口之外的prefix0–23及注册S保持。7候选四联与两个rawframe实际回投接受只证明候选参考；必须另查应用后真实display/smooth。别从source新增44点推断native也新增44：station-approach groomer实际新增62点，其中18点跨S进入下一站间，故production复查扩到区间4/5全部12三联，最终实际通过。native共同prefix162/suffix71严格保持。曲线缩短累计尺使自动错误follow从old100m变成new75m，25m真实producer采样及S精确snap得出新[7084.0761628133805→7025]；2line实际productionhelper调用验证后，owner只剔除旧/新两精确signature，near miss拒绝，不宽删line所有follow。曲线owner仅协调刷新既有follow证据base.line/nativebase两个slots，保留branch/physical/history所有其他字段；新6+既有3回归9/9。CLI报告应输出实际matchedrow/null而非固定旧row，幂等no-op不能虚报删除。最终Main同相机曲线／分岔、完整两侧＋支线及整组实际配对，card保持JRWest小野田规范身份。居能N02共同长stationfeature与Apple多个蓝平台区域不足以证明唯一专属平台中心，保留WARNING和原点。

### 万叶线：沿轨对齐不能代替站台中点（2026-10-12，首候选被拒绝）

海王丸首候选把原N02站点沿旧chainage北移21.5m投影到实体轨带，完整7个原图/原生参考视点的线路走向已接受，但Main近景发现真正Apple纵向平台在点西侧约140m。仅看线落在轨道上会漏掉站点沿线错位；必须单独在原图标出站框两端、自己的平台组、纵向中点和新点，并在Main同时看到框及点。区域俯瞰确认道路crossing东侧唯一电车平台；revision2沿已接受线路locus重新切分#5/#6，把001817移动136.17m到平台中点。不能为保持旧区间归属让点留在错chainage，也不能把最靠近旧点的轨带投影当站台中心。越之潟的南侧横块和向海路径属于渡船设施，终点用纵向电车平台，不吸附渡船建筑。当前revision2尚待完整native与Main，生产未apply。

六渡寺的两端站也不能把修复线在100m内拉回已确证偏离的旧端点再宣称整个区间通过；应按真实平台中点继续审查完整相邻区间，或明确保持未接受候选。UI搜索框的Value不是选中线路证据：必须确认selected queue item与详情lineID/intervalIndex，导出再核对analysis.json，避免旧选择被搜索文本掩盖。

revision2在Main实际把海王丸放入正确平台，卡片身份保持，但修复西端的东新湊旧guard也位于平台东约35m。站点未变并不能代替站点正确：所有受改范围的内点、保留边界和终点都须逐个按自己平台组检查。修复因实际失败扩到#4/#5/#6完整范围，西端中新湊为双轨之间的岛式平台，代表点不能吸附任一单轨；两侧自然接入同一个平台中点。未accept完整候选前，生产始终不apply。

### 站台填色分量和完整链程复查

万叶线实测说明：蓝色站台框可能被轨道和底图铁路文字分成多个填色连通分量。海王丸实际输出两个分量、零可靠轨道支持；它们不是两座已识别实体站台，不能为提高识别率直接合并或自动定位。保留 unresolved，并区分填色形状检测、客运站台组身份、铁路像素支持与站点写入四件事。算法集成的实际原生输出应与真实 raw/JSON 对照，编译和 fixture 通过不能代替该检查。

相向站台前后交错时，先确认同站客运组，再取整体纵向代表中部；单侧框中点、交通 POI、道路边缘或相邻另一站的框均不能替代。万叶线完整 17/51 高冈 z18 复查显示多个旧 N02 站点沿线差约 13–110 米。正确移动站点必须重分两侧完整显示区间，不能把轨形焊回已知错误旧点。暂未唯一识别的组标明候选与 WARNING，不能借全线已看宣称站台精度通过。

终点须区分本线站台和附近其他铁路：高冈万叶线独立北侧框/屋顶与南方 JR/Ainokaze/Himi 长平台不同，抽离器找出的最近或最大蓝框不能换掉正确的本线终点。保留 physical/ID/km；先做三个专用 app 真实全段，再检查 Main 最终线路与末端。

### 分离站台框不能取路口平均点

万叶线 V4 的完整24/73实际native检查通过线路连续性，但 Main 广小路显示 alias 位于两块沿轨方向分离的紫色站台框之间路口。Root据用户明确要求“站点放在 Apple Maps 车站框中间”拒绝该 alias；native中心线通过不能使错误 station dot 自动通过。新能町、旭丘同类沿轴 gap 也加入 V5 复核。

修订上节及旧skill中“交错平台整体中部”建议：如果两框沿轴不重叠，数学平均点落在道路／路口空隙，不得作为已识别站台框的中心。用一个实际已辨明自有框的纵向中点作为代表，保持物理站点身份；方向框两者都可确定时保留既有代表方向或选择更贴近其物理代表的自有框，不能以距离单独认身份。不要合入灰交通POI、道路curb、邻站框。横向平行轨框同纵向范围或岛台中点是另一情形，不因中间黑轨拆分填色而错杀。重分受影响两侧完整显示区间，保留已正确轨线地理locus；原V4和失败Main pair作为历史证据，生产不写入失败候选。

### 西唐津客运平台和真实接回点

西唐津旧终点位于客运平台东侧约50米，南侧控制点也在客运黑轨东侧约15–30米。先看Main近景，再用区域GSI2022年5月俯瞰图辨明西侧客运平台与东側车辆基地，完整首区间8视点近景确认错误范围。不能只移终点而接回前几个仍错的原控制点。找到了落在可见客运黑轨的原index19[129.96077,33.44912]，替换显示前0–18并保留index19起9个坐标literal一致。其余11区间和全部physical/ID/km保持；native远端494点suffix也保持。实际native全部8/24、Main同相机终点/完整首区间/南咽喉及真实唐津线card通过后才Sourceapply；具体物理平台北端边界与米级精度仍WARNING。

写入工具的输入快照可同时包含UTF-8 JSON和二进制PNG，不能用字符串严格比较Buffer造成同文件误报。修复须逐字节比较binary，保持任何目标写入前完成全部输入及目标快照匹配。实际临时文件回归验证binary或text漂移时所有目标不写；不要删除预检来绕过错误。source输出几何与已验收候选一致时复用有效runtime证据，metadata/资源交付状态须另记录。


### 松本站：物理接轨与站台显示点分别校验

大糸线北松本→松本的物理数据末尾 J→旧站点只有32米，却转约57°并斜跨站台轨带；全局圆角只会把错误变成圆钩。用主App近景、全部四个z18区域底图原图与区域俯瞰图确认自有北侧终端站台。显示保留原0–6控制点，删除末端两条错误显示边，终点放在自有框纵向中点；物理J、站点ID、公里数据、路径身份和其他区间保持。不要把J强塞进display以维持错误横穿站台短尾。

接轨方向按有向进路检查：南松本侧进松本再往北大糸线约0.217°，可同向直通；田泽北侧转往北大糸线约180°，需要松本站内换向，不能在北侧分岔伪造大U形直通。官方JR资料证明换向，区域底图确认真实北侧分岔；上高地线7号站台是独立乘客换乘，不能因同名或同站点ID增加JR物理连接。只调本线display/native末端和已有lane终点量尺，不新增follow/family或改全局平滑阈值。

三个专用检测App分别完整覆盖大糸#30/#31、篠之井#4/#5、上高地#0，每App47视点141张实际面板，再在Main实查站内短尾、真实北侧分岔、共享区间、全部五区间与两端及站点card。约4°的站台轴线方向差支持制图对齐，不等于测量精度；2011航拍与简化乡间底图仍保留精度WARNING。持久记录南侧同向/北侧需换向的回归，并确保apply后仍可重建和hash校验冻结的before fixture。


### 万叶线 V5：自有框落点与完整区间复用

完整native线路连续性通过，不能代替Main站点落点通过。广小路V4点位于沿轨方向分离的两块站台之间道路空隙，必须拒绝。V5分别确认新能町、旭丘、志贵野中学校前、广小路、坂下町的自有实际框，在框内取纵向中点，局部约±30米衔接，保留已正确轨线地理走向，禁止为冻结错误旧点添加回折。三个检测App各实际复查九个完整相邻区间23视点69面板；主App逐一查看五个点、完整受影响范围、整组两记录与三个远端，全部通过后才正式写入。physical/ID/km保持，具体通行方向平台身份与测量精度继续WARNING。

依赖hash因改点而变化，不能据整线hash不同重跑全部已验收视点，也不能无条件沿用旧图。逐项证明未改七个新湊港区间、八个高冈区间的坐标/alias/native地理切片和固定渲染约定一致，实际V4有效49视点，加新V5 23视点，得到当前完整72视点。实际#12计划缩为2视点，不能用旧期望24替代新收据23。极短0.0816米非零边在原分辨率display/smooth核实无尖刺或双端帽，保留具体证据；不要因数字很小自动扩大全局最短边阈值或重跑全国矩阵。

检测App使用已存在快捷键：下一站Cmd+Option+Shift+Right，当前完整区间取证Cmd+Shift+C；每次键盘切换后读实际站名与lineID。菜单或AX超时后先读当前状态/收据，不重复触发同一批次。记录本次经验与主App实际ON/OFF、站点卡，source正式输出与验收候选几何一致时复用有效runtime证据，资源签名交付另记。


### 2026-10-13 Keyboard testing
Expose frequent review actions through native Commands using the same controller/model methods. Guard presented editors/dialogs, disable workspace Esc under sheets, and gate previous/next directions independently at boundaries. Test key-triggered state changes in the real apps, including a complete interval capture; an invoked key or successful build alone is not a visible-state proof. Keep date commands on the established date mechanism. See ordered-continuation-20261012/mac-keyboard-20261013/README.md.


# Reusable lessons from the Keikyu Airport display repair

- **Project the literal source before trusting agreement metrics.** A source seed, constructed sample, and rendered candidate can agree with each other while all three remain visibly displaced from Apple's own railway glyph. Reproject the literal physical/display control points into the exact native snapshot and compare their pixels with the identified own rail band. Source consistency proves reproducibility, not Apple alignment.

- **Choose identity before proximity.** Reject the nearest or most strongly supported extracted path when it belongs to a competing railway, road, building edge, water edge, entrance box, or adjoining operator. At Haneda, the 26–31 m supported extraction was Tokyo Monorail, while the smaller residual to the labelled Keikyu guide was the relevant defect. Record the rejected competitor and the visual identity evidence; do not turn a low residual or support percentage into an automatic pass.

- **Fit curved corridors with normal cross-sections and unique anchors.** A constant translation failed because the clear Keikyu runway guide had a different arc from the source: it crossed the correct glyph in one area and missed it elsewhere. Trace signed normal offsets at unambiguous columns across overlapping georeferenced frames, preserve the measured variation, and blend only at reviewed endpoints. Recheck unique, label-free anchors in more than one frame. Do not average residuals into a global shift.

- **Treat station-frame placement and track-locus fit as one continuous scope.** Moving only the terminal dot exposed wrong intermediate frame anchors and adjacent track locus. The acceptance gate therefore covered all six Airport intervals and all seven station frames, with literal shared endpoint tuples between adjacent display intervals. Preserve physical station rows, IDs, kilometres, routing, and the unchanged Kamata shared endpoint; allow display aliases and display geometry to differ where the Apple cartographic representation requires it.

- **Carry the complete scope through candidate, native, and Main review.** Freeze the candidate arrays, all interval GeoJSONs, every raw reprojection, and a manifest before runtime review. Review every complete interval and both endpoint/tail views in each affected Inspector, then review every station close-up plus full-line continuity in Main. Internal lane counts, source-to-display distances, capture counters, or zero failures do not replace pixel review.

- **Label pixels are not rail supports.** Text and station labels can produce diagonal strokes that look like track fragments. Mask label regions when extracting, inspect the underlying basemap at neighboring columns, and discard manual samples that land on characters. In this repair, contaminated Terminal-area draft samples were explicitly excluded rather than blended into the final trace.

- **Keep candidate history when a visual hypothesis fails.** Freeze rejected revisions instead of overwriting them. Record why each failed: the interval-1 building/frame-edge hump, retained south source locus, south residual, and north overshoot. Tests should bind the accepted revision hash and reject earlier hashes so a later rebuild cannot silently restore a visually rejected geometry.

- **Verify packaging against the builder's actual optional inputs.** A missing optional regional/render-group file is not itself a build failure when the current builder and source root do not require or provide it. Use the successful builder manifest as the authority: confirm its recorded package/lane input hashes, required render-group input hash, target vertex/station/chain counts, and zero dangling group IDs. Do not invent an absent `na-render-groups` requirement from an older candidate-root convention.

- **Use narrow ownership checks.** The final compact comparison should show only the reviewed line's display fields and its override metadata changing. Strip those fields and require the physical line to equal production exactly; require every other line and all non-owning lane/follow/family/group/measured-reference structures to remain exact. Regenerate only the owning native part and established dependency references.

- **State the representation limit.** Apple basemap station frames and underground rail glyphs are cartographic display evidence. Acceptance means the product display follows the identified Apple representation continuously; it does not establish surveyed track, turnout, or platform geometry.

### Jounan related guard review — provisional candidate corrections, 2026-10-13

Complete regional raw review exposed an identity error that source-consistency checks missed: the diagonal Heiwadori 1-chome frame was first attributed to Kamiichiman. Exact georeferenced physical station projection and the full Johoku/Renraku interval directions corrected that attribution. Johoku departs the same diagonal Heiwa frame northwest and Renraku southeast; their own frame may be shared. Thin blue transit-route casing/labels on the EW rail are not proof of a separate Heiwa platform. In contrast, Honmachi 6-chome NS terminal and Johoku EW crossing require independent own-frame representatives.

A candidate platform-body midpoint also needs its longitudinal chainage projected normally to the identified own rail band. Do not add a short connector from an off-rail body axis; that connector creates the very hook being repaired. Shared station ID proves neither sameness nor separation of the station frames: establish identity and line-oriented continuity first. Keep rejected candidates frozen and distinguish raw acceptance from all-three/Main acceptance. Jounan group production apply remains pending.

### 2026-10-13 — station-face endpoints do not prove rail continuity

Main full six-line Jounan review found a real ~29.8m gap from Hanazono’s own south Minamihoribata frame to the visible north junction on Jounan. Both line-scoped station aliases are correct and must stay separate; the original physical station identity 008768 is already shared. Missing follow/lane metadata means no display coupling exists, not that the physical rail is disconnected. Root rejected the initial full-network ACCEPT while retaining reviewed interval geometry as historical evidence. Existing JS/Swift `displayBranchLeadIns` supports a separate display-only rail continuation without changing station dots, interval endpoints or physical topology.

Do not join to a merely nearest existing vertex: the nearest Jounan vertex was4.05m away, and its segment projection was2.24m south of the literal thin Apple rail junction. Root opened the original regional raw and rejected this preservation-first shortcut. The bounded V2 scope includes Hanazono’s connector plus Jounan interval2’s own EW approach; no global translation or artificial return hook. Proposal/native/Main replay is still pending at this note.

- **曲线须跟随铁路本体，不能沿道路／护城河路缘拟合。** 市役所前 V2 的弓形来自错误路缘；在三个原始区域视点中逐点确认带枕木的黑色铁轨后，V3重绘真实浅弯及圆弧，并在三个检测 app 中完成受改整线复查。Main整组仍待完成。
- **绘制状态不能代替实际首帧。** Main启动时，AX在截图之后才更新为rendered，前一个像素帧仍只有底图。先收起面板，实际观察轨道／站点已经绘出，再取得同相机ON/OFF；不把绘制计数当成像素通过。

城南组V3修复验收完成：上述站框到真实分岔的displaylead、真铁轨与路缘辨别经验已通过三个检测app完整受改范围以及Main全29区间验收；正式应用/六app交付完成。未变renderinputs可复用已验收nativepayloads，但源摘要必须与正式JP匹配，并记录没有freshbuilder。

### 2026-10-13 Tsushima raw rejection and terminal keyboard fix
Narrow real platform fill, broad rail casing, building footprint and label fragments are different evidence. V4 stretched two station faces beyond actual fill and selected casing normal; Root rejected. Identify actual longitudinal endpoints, select an evidenced own face if opposing faces are longitudinally staggered, then project its midpoint normally onto own rail. Correct dotchainage requires repartitioning both complete adjacent intervals. Native terminal same-view export must not require currentInput: true terminal has no outgoing interval. Model/button/Command shared admission fixed; actual Alt+Command+S at Tsushima005420 saved nilinterval records in all3 apps. No intervalcompletion credit from terminalcapture. Grey Main startup despite renderedAX required actualpixel observation/restart before baseline saving. Railway candidate nativeacceptance pending.


### 2026-10-13 — overlapping-view order, lane dots and history delivery

Main #20 confirmed that independently correct own-glyph controls can form a wrong path when appended in capture order across overlapping cameras. Reproject supports into a common exact raw frame and order them by the identified passenger direction; inspect control triples and cross-view joins for reversal. Here swapping indices9/10 removes a13.331m control backtrack without changing any support coordinate or station alias. Keep rejected V1 frozen; V2's focused regression/helper invariants prove only candidate construction, not native acceptance. Use actual derived native measures: raw control-polyline length reduction is not the downstream reference delta after existing cleanup/smoothing.

Sako: independently establish the narrow own-frame longitudinal midpoint and normal rail projection. Compare that raw alias with the product's lane/follow/render contract before calling a transverse Main dot displacement a frame error. Main lane−3 intentionally offsets the final dot/stroke; do not move the raw alias to cancel that presentation or substitute the broad attached building/access footprint. Actual frame, own rail and complete station joins remain separate evidence.

Native history is an explicit resource-builder dependency. For the reviewed candidate root, pass `--history-dir app/data` and confirm the manifest's named `historyFile` and actual input hash before delivery. A successful geometry build or a template without history does not establish date correctness. Root's seven repeated actual Hisatsu date views passed visible Yoshimatsu north/south filtering after corrected history delivery; Settings Current restored. The receipt is ordered-continuation-20261012/tsushima-combined-candidate-v1/main/hisatsu-date-repeat/result.json; it grants no full-line geometry credit. V1 Main #20 remains rejected and V2 native/formal acceptance pending.


Accepted Tsushima/Main V2 follow-through: after Root's all-three/Main acceptance and formal apply, the Main #20 forward-order/no-sharp-reversal regression was changed to consume shipped JP `displayIntervalCoordinates[20]`. One named test passed against formal production. A production regression must guard the shipped owning geometry, not merely a preserved candidate report; keep candidate-specific evidence frozen separately. Root explicitly records fresh Main eight-interval evidence versus unchanged Tsushima slice reuse. Scope acceptance, resource signatures and retained history do not imply completion of the ordered railway list; final native delivery confirmation is the parent's separate step.

## 予土线 V1 退回与外侧边界（2026-10-14，修正版尚未验收）

第一版共享站点候选虽然通过 native helper，完整原生像素复查仍发现保留的予土18主体偏离自身铁轨；第二独立检测器又发现8/9等非相邻主体偏移。因此不能只审改过的接缝、把其余source/display一致当Apple对齐。Root补齐20站真实高倍底图并实际打开原图；相邻伊与喜、高光、宇和岛的Main同相机ON/OFF也证实旧站心不在窄face纵向中间。伊与喜与高光修正必须纳入两侧完整区间，新外侧伊予吉田又有明确移位，范围按事实延伸。多轨窪川与土佐佐贺连接fill辨认不足时，不由同stationID、旧点在大footprint里或成功计数推导新alias。

每幅pixel pick使用本幅view.json实际尺寸和mapRect逆映射；999×654站图不能套1024×768批量图参数。铁路提取必须排除381公路牌与河流文字，并检查跨视点控制次序和自身曲线。实际候选复投图里仍出现30–45度尖角时，先在原图判定错误保留点/标签误采，做有像素支持的局部删除，不能全局平滑消除数值。全数capture≠全数pixel review，复查receipt须区分实际打开的面板、未审面板、警告、退回候选和已验收。此条是已观察失败经验，予土修正版与全国线路列表未完成。

## 2026-10-14 阿佐线：实体铁路与线路示意的辨认

五站证据补齐，V4仍为候选，未正式应用或原生验收。Apple底图可同时绘制带名称的简化线路与独立实体铁道。区间10的巨大偏离判断经原始像素与深色底图撤回；吉川V2误沿S形示意，区域航照支持原本平顺铁道，V4恢复实体控制点。自身站框纵向中点须正常投影到已辨认的自身轨道，两侧完整区间同步重分。48张区间7–11的原始视口候选对照已逐张查看；不能据此宣称全部原生渲染通过。

同视点证据采用light/scale1，实际界面可保持dark；导出camera/viewport为配准依据，手动拖动失败截图单独排除。CmdShiftG坐标导航减少拖动与惯性误差，需核对真实导出相机。Catalyst Debug更新应同步exe和debug dylib，再观察实际新UI。

### 阿佐 V4 正式交付 · 2026-10-14

三个检测 app 的 459 个全区间视点、27 个站点和连接近景，及 Main 的 29 组 ON/OFF 已完成实际人工复核。五站显示点投影至自身客运轨道，后免和安芸站端维持可顺向通行的走势，奈半利在本站框中点截断为终点。`repair-asa-complete-display.mjs` 保存 20 区间／21 别名的可重放修复；针对性查询确认物理解码和其他线路不变、重放幂等、正式几何等于验收候选。当前主 app 实际启动确认安芸结果。视觉通过仅表示所存比例尺下的人工底图对照，不等于零像素残差或运营行车仿真。

### GSI 区域截图实际比例与加载时序 · 2026-10-14

伊奈线补查实际发现 URL z19／z20 对应 DOM 瓦片 z18，另有志久 URL 已更新而画面仍为丸山，以及航拍淡入未完成的截图。改为等待目标中心瓦片 loaded 且 opacity=1，记录 actual DOM bounds／瓦片列行号，并由 `lib/gsi_tile_georeference.py` 换算，显式校对实际中心与目标。两项真实失效回归已先失败后通过。六站瓦片中心配准通过，几何与平台身份结论仍需人工复核。已排除错位／淡入截图，禁止用 URL 单独推导照片比例。

之前阿佐的 URL 缩放推算航拍叠加，不能再当定量配准证据。阿佐已完成的三个 Inspector 和 Main Apple 底图完整区间及站点对照仍有效，V4 保留与原生可见实体轨道相符的吉川连续走势；正式交付不依赖未经瓦片标定的航拍叠加。

### 2026-10-14 伊奈线志久：真实文字缺口回归优先于形态分段

Root 在真实 z19 检测 app 中执行抽离并保存 `ina-complete/stations-supplemental-20261014/09-shiku-extraction-z19`：站台颜色连通分量被拟合为约120m，支持轨道为0，不能用于站点。窄连接开运算及外包络宽度分段均把倾斜的 Ina 标签误当作边界；真实截图回归失败，3项既有站台测试通过仍不足以验收。两版实验已保存在报告中并撤回运行时源码。后续必须识别文本遮挡与实际站台端帽，不能通过放宽中心点断言或只依靠长度阈值获得通过。南侧乘客屋顶与入口楼梯分界优先以已校准区域俯瞰图 corroborate；屋顶端点不能自动等同完整站台端帽。伊奈正式数据仍未应用，三个检测 app/Main 修改后验收未完成。

### Shiku actual-fill separation and native resource pairing (root, 2026-10-14)

A connected-component-only width profile failed at the rotated Ina label. The successful profile retains an immutable full classified fill mask and measures fill islands inside the same component-oriented normal band. This repairs text holes in the width envelope without combining adjacent platform bands. The actual Shiku baseline image regression now preserves the central passenger frame and splits both narrow approach connections. Constricted candidates remain unresolved even with plausible parallel rail support; splitting is evidence, not permission to write an alias. Three actual inspector exports confirm three candidates and zero automatic placements.

A compact JP binary and its JP per-line catalog offsets must travel together. Updating only the region checksum creates a Main loading failure despite valid inspector geometry. Replace that region’s catalog and joins from the same build and preserve other regions. Candidate app identities must be unique to avoid keyboard routing to another running Main. Validate the actual render status and observed camera before saving each ON/OFF pair.

### Occluded terminals are not visible railway stubs — Ina delivery, 2026-10-14

A whole-corridor capture proves neither passenger platform extent nor the end of an occluded railway. The Ina V1 Omiya endpoint at the last visible Apple glyph and Uchijuku endpoint at the SE glyph stub were rejected after full captures. Reframe both platform caps at the same scale; retain raw extraction ambiguity. At Uchijuku, a centred z20 frame plus georeferenced regional roof/stair evidence separated the passenger platform from its SE approach. At Omiya, the Apple frame and railway remain hidden under building/rail coverage. The delivered endpoint is explicitly reference-assisted, using operator loop/NS01 identity, regional aerial context and independently associated public stop-area platform extent; it is not an Apple pixel extraction success or a surveyed alignment claim. Record the hidden extent and sources in the scoped result rather than labelling it pixel-aligned. Never generalize this manual exception into automatic gap filling or nearest parallel-rail snapping.

After an endpoint-only revision, preserve the earlier full-interval evidence as historical. Recapture both affected complete intervals in all three inspectors and Main; reuse other intervals only after verifying their coordinates and relevant renderer dependencies are unchanged. Refresh the installed native region catalog and resource revision as well as the compact binary, then actually inspect the delivered original Main.

## 2026-10-15 Toyama: cyan roadside false selection

The generic blue/cyan extractor selected a cyan roadside line west of the owning railway in the actual Shimookui z17 raw. The fixed-image regression initially failed both the <4m median and the own-rail x>475 assertions (generic median about16.2m). An explicit blue-railway palette now requires B-G>=40 at candidate centres, preserving the default blue/cyan and physical-pair modes. Colour filters candidates; root still identifies the railway from actual pixels. The actual-image regression and3 existing transit tests passed. One incremental Catalyst build succeeded; all3 dedicated apps were updated and deep/strict signed. Cmd+Option+Shift+B actually enabled the option in all3. Actual same-camera native exports agree:71% support,1.9m median/P95,2.9m maximum;2 platform candidates stay unresolved.

All3x42 continuous baseline views across14 Toyama intervals have been manually opened. All15 station z18 exports have checked identities, exact requested centres and zoom. Broad transit coverage can join stairs, station buildings and legacy platform remains; neither a roof bar nor the entire blue footprint proves the current whole passenger face. Northern station positions are proposals only: formal Toyama geometry is unchanged and Main full-line review is pending. The hotel-front z19 attempt has a changed actual camera; it cannot inherit the requested centred-camera calibration. Any future use requires its actual camera and independently visible complete bounds.

Evidence: ordered-continuation-20261012/toyama-port-complete/native-palette-update/change-result.json; station-details/*-own-blue-native-z17; review-progress.json; root-candidate-v1/northern-station-proposals.json. This completes an extractor repair, not Toyama geometry acceptance.

## 2026-10-15 Toyama corridor and date boundary repair

The V1 local box-median normal-offset proposal introduced new short reversals (up to159.6degrees) at southern bends and was rejected before native installation. V2 uses a12m Gaussian along-chain support window and a16m tangent, retaining source geometry in unsupported gaps. All14 complete intervals were reviewed in all3inspectors (42views each) and Main (14actual ON/OFF pairs). Startup camera parameters alone did not prove visible coverage: southern horizontal intervals were widened and recaptured; one northern startup mismatch was resolved with the native zoom shortcut and its actual camera recorded.

Keirin V2 used the shorter west platform fragment. Complete east passenger-frame caps required a further roughly2m south correction; V3 changes only station001843 and endpoints of intervals12/13. All3inspectors recaptured those2complete intervals (6views each) and Main recaptured both pairs and the close station pair. All18new inspector views and all Main pairs were manually opened. Iwasehama ends at its full-frame midpoint with no outgoing stub. Other13station aliases retain source longitudinal chainage with only normal projection; their whole passenger-frame midpoints remain pending and must not inherit the corridor verdict.

The groomed whole-chain display row changed14history fragment matches to1; that is granularity, not proof of date loss. A real regression was Eirakucho's slightly shifted display point falling outside its extremely thin existing2021opening bbox. Extend only that existing rule to include its display alias; preserve the2021-03-21date and verify both the Web whole-feature selector and native display-point selector still hit only001921. Main's existing Selected ride date mode was actually switched2021-03-20to21: hotel-front and Eirakucho dots absent before, present on opening day, with corridor retained. Reuse that boundary evidence after the unrelated northern-only change, whose history bytes are unchanged. Do not add a line-specific date-rendering exception.

Formal corridor replay: app/scripts/railway/repair-toyama-port-corridor-display.mjs and toyama-port-corridor-display-evidence.json. This is corridor/northern-frame acceptance with other station-frame centres still pending; original Main delivery is recorded separately in the scope ledger.

## 2026-10-15 — Native Transit junction cartography

Actual macOS Maps Transit views at Kamiyacho, Dobashi and Toyama Marunouchi show different junction simplifications. Kamiyacho has a through EW trunk and two independently positioned south-turn curves; Dobashi shows an NS trunk and only the west→north curve. Do not force all arms into a common Y vertex or manufacture an all-pairs triangle. Multiple coloured route badges can share one green operator corridor. Astram crossings remain independent. Toyama’s angular schematic is an observed variation, not authority to introduce a physical cusp. Preserve own-corridor identity and verify legal movement using the regional aerial/official service evidence; retain real curves. Source/display/data changes and complete interval acceptance are still pending for Ujina; these research pixels do not grant them. See ordered-continuation-20261012/ujina-complete/apple-maps-transit-style/observations.md.

## 地铁并行身份、直通边界与完整画面（2026-10-15，半藏门线基线）

原生 Apple Maps Transit 青山一丁目区域实际显示：紫色半藏门位于橙色银座北侧。不要把预览线偏离最近蓝线直接判错或吸附；先通过有名称/编号的区域 Transit 轨迹确认自身走廊。九段下并行新宿与纵向东西线也不能按交叉位置添加连接。河底段底图仅画岸边示意弧时，记录显示差异，不能以俯瞰道路、河岸或文字推断地下真实轨道。

涩谷/押上作为命名线和运营边界，不是全部平台的物理终点：检查已确认共同平台上的直通连续性，其他平台组保持独立。同站ID不能强制汇点，未审完整乘客框不能继承走廊连续性的通过结论。

Main相机中心、zoom、rendered与0 budgetDrops不证明完整区间可见。半藏门候选首轮7个区间东侧端点/弯道被裁切，保留原图、放宽视野、逐对查看后才记录完整覆盖。三个检测app各67视点及候选/正式Main各13整段+2直通局部已在root实际查看；这是完整基线分析，九段下台阶、河底示意差异、14站框中心仍待验收，未改生产数据。记录实际查看的smooth合成视图数，不把另存的basemap/display/smooth面板总数冒充逐张精审数量。

## 本线采集范围与地下示意差异（2026-10-15，日比谷线基线）

日比谷线22站/21区间在三个原生检测app各89个本线视图及原始Main全部21区间+2边界区域已由root逐图查看。广尾、饭仓、护城河角、筑地等地下段红色预览与Apple自身示意轮廓有差异，只列显示候选；不能沿道路角点、最近其他蓝轨或车场扇出修正隧道。中目黑日比谷线出站与东横分离，北千住多平台/多层大填色须分本线身份，22站完整框仍待验收。

检测app全局“重试失败”会把失败项重置，再以nil scope启动全局剩余优先队列，并非仅抓失败视图。日比谷primary发生MKErrorDomain2后误采102个非本线视图；暂停后用已确认当前线scope恢复1个本线视图。不要用该全局按钮重试单线；代码尚未修复时明确保留此工具缺陷。

原生搜索输入与快捷键不能靠尝试次数确认成功：AX setValue后查看实际文字，再Return，重新观察选中lineID和起站，最后单独触发当前线采集。secondary未持久化输入导致70个山手线视图误采，已排除；third按上述顺序无误采。精确lineID过滤后的本线计数/像素审阅才可写入本线结果，不能用全局计数冒充覆盖，误采图不能顺便算其他线通过。完整区间连续性与完整本线乘客框验收分开记录。

## 地铁分支大斜切与换乘站公共点（2026-10-15，丸之内线基线）

- 检查命名主线时纳入会影响junction的关联支线完整区间。丸之内主线24段与方南町支线3段合计27段；中野坂上区域近景不能替代支线全段。
- 方向正确仍可能有fork位置及曲线错误。中野新桥北接中野坂上的预览有明显45度大斜切，而自身Apple蓝线及Mac Transit显示南转东圆弧；先核实自身弧线和实际可行臂对，不移动fork求圆角，不自动补南转西连接。
- 同一大换乘站的公共canonical点可能属于JR大站场，不能用它验收独立地铁东西平台。Main新宿公共点与丸之内轴线分离，需本线完整乘客框；池袋、四谷、东京、荻洼也先分辨身份。站点验收与路径连续分开记录。
- 保留已有自身显示alias及相邻区间覆盖。本乡三丁目003546及interval3/4不因更近的大江户蓝线而回退。地下示意差异仅作显示候选，不能冒充工程坐标。
- 本轮三个检测app各121视点（108主线+13支线），root全部363个smooth合成视图已看；Main27完整段+1junction上下文28对56图已看。各自保存的另外两个面板不计作全部独立看图。没有新增生产修复或完整站台框验收。

## 2026-10-15 - Mita: rendered status can coexist with blank basemap pixels

Original Main case00 had network:rendered and budgetDrops:0 while both actual ON/OFF frames showed only an empty grid. Preserve these rejected receipts, observe loaded regional pixels, then recapture the same plan camera. AX and counters prove state only. All26 complete Mita intervals were then actually viewed in Main (26 valid pairs/52 frames), alongside115 views per dedicated app (345 composites; prior primary and secondary00..17 review reused explicitly). This completes baseline analysis, not platform acceptance or new production repair. Keep local Transit contour candidates visible at Sengoku, Suidobashi, Otemachi, Hibiya, Mita, Shirokanetakanawa and Meguro. Matching27 aliases/26 owner arrays does not establish own-frame longitudinal midpoints. Numeric-key dictionaries and arrays need per-key comparison, not raw container stringify.

### Ryomo complete baseline: shared-station ownership and camera margins

Three native apps repeat the south-side Isesaki bridge/platform departure, but an adjacent Tobu glyph is not sufficient to declare a wrong JR route: resolve the JR passenger frame and its longitudinal midpoint first. Retain variable local offsets at river bends rather than translating the entire line. At Kiryu and Shin-Maebashi, branch crossings and yard fans are separate from the representative passenger corridor. Original Main cameras must expose both endpoints outside controls; preserve tight first attempts and review the wider replacements. Network rendered/zero budget drops does not establish basemap pixels or geographic acceptance.

## 2026-10-16 Oito complete baseline

Three actual inspectors247 views each and original Main32 complete interval pairs reviewed by sole root. Lake Aoki shoreline offset changes through north turn and eastern straight: local repair candidate, not a whole-line translation. Keep Sanosaka S, independent yards, Miyabuchi fork and earlier Matsumoto display tail/alias correction. Original Main renderer-ready status can precede real basemap tiles: blank-grid ON18/20 rejected, retained and recaptured. Capture camera precondition blocked live drift24 before writing evidence. These checks establish baseline review only; all33 whole-line own-platform midpoints remain open.

## 2026-10-16 · 東北線-2 第30条基线

MapKit 单点失败不可触发全量重试；保留原54成功/1失败，在新目录只补首区间6/6。三套165视点和原始Main24帧完整复核仍只证明覆盖。赤羽88°短钩、田端客运/货场分离以及上野/东京本线平台身份须单独处理；共享ID和宽站场不能代替纵向中点验收。没有生产变更。

## 東海道線完整基线续记

三套348视点/套及Main32对实际逐图审阅。相模川桥南偏与平塚—二宮北偏不能归纳为全线平移；坂木、白糸川北、岩川北、湯河原隧道先辨本线身份。品川既有54点显示修复保留，未扩大平台验收。蓝色自身站台为纵向参考，紫色换乘通道排除。AX rendered不能证明有底图：空白00/18保留，Main9/31相机前置校验拒绝后重采。
