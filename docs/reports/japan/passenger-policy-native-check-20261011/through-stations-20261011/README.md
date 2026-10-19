# Through-station native review — 2026-10-11

## 唯一执行检查列表：高风险客运直通站

用户已授权按此列表自动顺序执行；不是定时任务或自动验证流水线。结果和暂停原因直接更新本列表，其他文件仅保存证据。

2026-10-12 最新续查：Mac已由用户解锁。品川山手#0／东海道#6的15个新native视点已全部人工复查；更新后的Main已实际核对完整受改区间、三个南侧分岔范围、大崎站共享进路及南侧总武分岔，未再见共享段碎片或新断口。严格共享ruler修复和四target构建证据沿用；地下／屋盖遮挡等整站限制仍保留，不将局部修复扩大为整站测绘通过。

妙高はねうまライン全9区间／120视点已补齐当前v5采集，101新视点人工复查及Main完整南／中／北区间、二本木折返和两端已完成；最后19个新二本木—新井视点也已人工复核，真实折返及新井进站连续。旧19为v4，只保留历史依据。丰肥线全36区间／476新视点已全部逐段人工检查，未见可见走廊／弯道／断口缺陷；Main全线总览、两侧区域、立野真实折返和熊本／大分终点已实查。多轨站内精确纵向中心仍保留WARNING。土讃线全60区间／655新视点已逐段人工检查，Main全线和两端已实查；近图发现新改／坪尻站点靠近站框端部。新改显示末端39.878米裁剪、坪尻沿现有铁路重分配显示切点均已写入；三个检测实例完成受改全4区间／77新视点，Main同相机圆点／站框／接续、逻辑成员及完整相邻区间after均已实际通过。本次复用既有二进制并成功重建安装生产铁路资源；Xcode工程读取失败与随后修正的签名问题已如实记录。窪川多轨平台精确中心保留WARNING。下一组上越线连同主线、Gala支线与p1／p2方向片段共39区间／600视点继续完整检查。原生receipt正确拒绝了v4→v5的渲染依赖复用，不以旧计数或源相同替代当前图面验收。详情见[本轮记录](ordered-continuation-20261012/results.md)，沿用本唯一清单。

- [x] Chat Pro 查找公开站内图、配线图和可定位站区资料；本地核实来源和日期。
- [x] 确认 B3 客运平台、南北连接和合法中央切点；排除地面东武及浅草／京成组。
- [x] 源几何保形修复偏北显示共点和末端折返／切线；保留 physical 身份、里程和公司显示。
- [x] 运行现有押上及直通的针对性回归，核对 Web／Swift 对应行为。
- [x] 暂停全量采集，完成一次必要增量构建；三个实例统一0.1/build3/v5，已实际重新打开。
- [x] Mac App 对照苹果地图复查中央点、两侧进站和真实拐点；记录可证实结果和剩余限制。
- [x] 更新并实际检查押上生产主地图的公司显示和站内共点；共用区间与仅站内公司接续分开判断。
- [x] 修复押上共点北侧粗采样圆弧被当作硬拐点的问题，并用更新后的生产主图／Inspector高倍率复查。
- [x] 押上京成／浅草线 B1：沿露出的底图黑轨核对代表中心线及站内中央点，调查后修复并原生复查。
- [ ] 京叶西侧共享3.78km及市川盐滨：完成剩余main/Inspector与Apple底图复查，单代表、无断点、真实fork与站点接续；有限fork通过不扩大到全段。
- [ ] 品川：按客运走廊核对站内代表点、北侧分岔与南侧进站弯，调查可证偏移后修复并原生复查。
- [ ] 东京：优先对照Apple Maps新干线专用轨道样式核对东北／东海道独立终到组；再补查南北跨站走廊及独立地下组，调查可证偏移后修复并原生复查。
- [ ] 木次线：出云坂根真实折返、三井野原南侧连续反向弯；保留客运分腿，取得同轨依据后修复偏移并原生复查。
- [ ] 箱根大平台剩余：站区以外长进路、密集弯及上大平台道岔；保留真实折返支线，修复可证源几何偏移。
- [ ] 按现有风险证据检查下一批运营客运直通站及剩余客运范围；包含历史肥萨线偏移、上荣町站点边界待确认，先核对现行运营和已有证据，问题调查、修复后原生复查。

2026-10-11继任历史核对：已逐读51条原prompt与25份历史最终报告，纠正交接对照中押上B3短弧已原生复查的状态及资料索引中京叶source已整合的状态。历史报告01a128a7仍记录肥萨线偏移需要修复、上荣町靠近蓝色站区边界暂不能确认；这些报告未见后续关闭依据，保留在本唯一清单的剩余客运范围。本次仅核对文档，未改变大崎／京叶新source的构建或nativeafter状态。

2026-10-11续查：铁路skill及其关联参考文档已现代化，同步Codex/Claude两个安装副本；先审查变化及依赖、复用有效证据、一个重任务、按具体问题选focused测试/查询/增量构建，历史preflight/旧全量验证不再自动运行。实际文档基线与独立任务审查完成，安装文本和本地引用已核对；quick_validate缺PyYAML未运行成功，不作为通过证据。保留旧脚本和历史报告，不重建自动验证流程。

默认采集已实际暂停24,963/92,216、失败4，给本轮局部调试腾出资源。两个手动实例补查木次三组、箱根两组配对：木次#15 camera133.112456,35.083283标有Kisuki Line的原黑轨与包/显示/平滑共同错位；箱根#6长进路camera139.071031,35.236379也呈共同跨黑轨弓形，不能只改站点或泛用smoothing。木次新GSI参考仅orgGILvl25000、局部仍接近原粗源，不能作独立逐轨测绘；调查资料在kisuki/sources。图面与AX在上级parallel-instance-kisuki-keiyo及parallel-instance-hakone的current-*。尚未改这两段几何或宣布全线通过。

本轮品川／东京已完成局部修复及原生复查。品川总武／横须贺13–15平台组与东海道6–12分开，移除旧西移alias及南侧借道，恢复既有源点和两侧支持；独立东侧圆点已实际出现，屋盖遮挡处尚未接受为精确黑轨中心。保留大崎支线投影与共享tail，移除旧6675–7875m follow，刷新相关measure并加本站两侧300m零偏移窗口。东京东北新干线终点移至既有支持[139.7676701,35.681109]，原生无pin图确认横尾折消失，生产主图确认两个新干线独立圆点及在来线共点保留。末端约214m旧centroid warp重建，5363个上游点保持；physical站点、区间及里程未改。

品川生产卡实查发现总武成员被同geometry renderGroup的东海道吞掉。真实renderGroup回归先失败后通过；现日本popup按公司＋源名称去重，几何group与圆点规则不变，东京同名别名仍合并。三个针对性Swift回归3/3通过，之前几何JS13/13仍适用；主App增量构建已成功，实际重开后点击东侧圆点，成员卡AX确认五行含总武线-3；截图及AX保存为after-popup-fix-production-*。标签仍沿用catalog「総武線」，未引入新运营命名系统。

剩余品川高风险：站点北侧源切线约11m偏差及南侧跨未命名黑轨的斜切，继续待客运认轨依据，不能用泛用圆滑或最近黑轨吸附修复。Chat南侧完整调查已保存为shinagawa/chat-south-final.ax.txt／PNG，要求从13–15平台南端连续识别正常客运上下行。其GSI/历史配线建议尚未独立核实为新坐标。品川与东京整站项目仍未勾选通过。默认检查App重载后无响应，已正常退出；已实际重开并完成加载，恢复仅点击一次。最终暂停按钮可用且记录从24,549增至24,553/92,216、失败4，确认采集运行，证据after-popup-fix-default-resumed。35个旧receipt因输入变化失效；两个手动实例正常保留。

优先处理新增尖角：共点北侧约46.55m的`[139.81336,35.71012]`有32.277°粗采样转角，Web／Swift的同一硬角保护规则阻止它圆滑。生产主图和Inspector的z19 before配对均实见此折角，工程图103和用户确认支持连续成弧；地下底图不足以恢复实测半径。现已在既有重放修复中仅将该显示顶点重建为相切圆弧，相对原两射线偏差≤3m、18段、每段≤2°；保留其他支持点、20m末端射线、共点、公司身份、原physical字段。对旧Inspector包逐条比较仅东武-2的displayIntervalCoordinates改变，physical stations/segments/structure等逐字段不变。新增生产stroke回归先实测失败32.2768°，修复后现有两文件21/21通过。全量采集在18,560/92,217、4失败时暂停供增量构建；最终主包compact与源逐字节相同，编译chunk保留36点（既有lane嵌入七位小数精度）。三个Inspector只刷新同一compact资源，使用原先统一binary/logo版本，未追加全量测试或新的验证脚本。重开后的Inspector同camera overlay/basemap及生产主图配对已实际复查：尖角改为连续短弧，末端共点保留。证据为`oshiage/after-arc-inspector-tobu-north-z19-*`和`after-arc-production-north-z19-*`；生产主图before/after camera略有不同，不宣称精确同camera比较。显示圆弧不宣称为精确测绘半径。

当前：真实RailMap主产品增量构建成功；compact源与当前一致，生产display chunks两侧新点及slot已核对。原生主图及中央近景显示东武北侧、半藏门南侧接入站内共点，独立京成／浅草点保留；站点卡片实际列出四个逻辑成员。四成员不表示四线路都共用一个平台组，也不证明整段相邻区间需要重复绘制。截图保存为`oshiage/production-main-*.png`及AX。默认采集为构建暂停后已恢复，最近实际记录18,850/92,217、4失败；MKErrorDomain error2仅记为采集失败，未重试，不解释成几何错误。完整生产Settings经原生PageDown翻页后实际显示`Network era: Current`及`Apple Maps`，未改变设置，证据为`oshiage/production-main-settings-current.png`和AX；此前缺项是滚动未可靠推进，已解决。

下一批范围为小竹向原003294与綾瀬003214。两个手动Mac实例已保存小竹8图、绫濑10图与对应AX，含中央、真实分岔及绫濑z19四张配对。局部数据/生产chunks审查未发现反向接缝或支持点删除。小竹点位于可见蓝色站体内，地下精确轨道中心仍未测定。绫濑千代田线代表线在站体北侧轨道带，JR在中部；约14m差本身不能证明哪一个正确。本轮未移动这两站的几何。

Chat Pro5/5调查已完整结束，包含授权的相关候选坐标与政策，完整答复在`oshiage/chat-next-risk-final.ax.txt`及PNG。官方建设史p626配线原页已本地目视：常磐缓行共用1—4长平台组，2/3是同一中央轨道的两面，南侧快速线无此平台；东端北绫濑客运支线、折返引上线与缓行下行立交分别处理。旧图只解释结构，精确现状须结合现行平台/运营证据；其中心不能直接换算为WGS84。东京Metro现行站图的直接下载返回403，Chat所报告图面仍需本地独立目视核实。下一步优先核对对应客运轨道组的中心及相邻进出站支持点，不能直接将Metro吸附到JR点或整个铁路用地中央。

用户新增的多轨中心规则已补入同一政策文件：先区分线路种类、公司、共用客运进路与独立走廊；同走廊取代表中心，不同公司的平行显示围绕中心展开。不同层位、快速/缓行、新干线/在来线及独立支线分别取中心，车场/仅货运轨道不参与计算；保留真实小弯和道岔。这是审核要求，本轮未宣称全国几何已重新居中。

此前押上公开[Chat Pro 调查](https://chatgpt.com/c/6acb1cea-899c-83ea-81c4-7081e15cf51a)的完整答复及截图在`oshiage/chat-final.ax.txt`和`oshiage/chat-final.png`。当时自动审批拒绝详细项目资料；用户随后明确授权向Chat发送相关项目内容，本轮两站咨询已成功发送候选坐标和政策，不再沿用此前未发送的状态。

官方2004年建设史292/441页标出210m平台及中心16K910，对应京成桥以西北十间川横断处；450页确认北侧下穿京成／浅草与地面东武后接往曳舟。现代官方站内图与有日期配线调查支持外侧1/4贯通、内侧2/3北端终止及南侧折返连接。没有加入各站台线、车场或货运线。

一张GSI地物瓦片的两岸交点定位河道中间，并投到原客运源段，得到显示共点`[139.81345102105016,35.70970842655579]`。这是有出处的代表显示切点，数值精度不等于实测平台精度。`oshiage/central-cut-reference.json`和工程原页保存证据。保留原两侧支持点，在同一源段内保留约20m末端支持点；移除人工回折和120m Bézier。物理站点、里程、结构、公司身份与其余线路逐字段比较未改；京成／浅草组保持独立。Metro原有末端300m零偏移范围随新measure更新；公司逻辑标识仍分别显示。

现有两个测试文件20/20通过（含z12/16/19切线）；Swift读取display坐标、末端支持点和同公司owner判定已审查，实际native像素结论等待下一项。默认沙箱构建因Xcode缓存权限失败；同一增量构建使用系统缓存权限成功。全量采集在12,991/92,218、0失败时暂停；重新载入后仅复用依赖未变的receipt，不把旧计数当成修复后验收。

押上B1已完成显示修复及最终原生复查：西南黑轨有Asakusa Line标注，源包原显示线距跨河所取参考点14.444m；现用实际黑轨起弯／跨河支持构建显示线，保留从西向东北的真实连续入站弯。官方京成2021.3.31 PDF已正确渲染目视，B1两岛式主体与B2步行附属部分分开。Chat Pro跨图补足被中央视口裁掉的东北端，SW主体端面中央图约(392,510)、NE主体端面东北图约(611,370)／换回中央图约(957,146)，取代表中央约(675,330)，反投影得到[139.8125322,35.7104587]。京成站内SE支持点在display中改接完整NE主体中央，再与浅草共享20m／10m共线末端射线；B3共点和地面东武不动。隐藏段是局部代表连接，不宣称地下测绘线位、具体股道或道岔尖轨精度。

初始新回归分别因跨河偏移与旧共点不在中央主体范围而失败；首次修复z19末端切向偏差0.442px，增加既有20m射线上的10m支持后通过。最终23/23（两个现有文件，包含生产stroke起弯／跨河、B1共点、z12/16/19接续与重放）通过。与修复前Inspector逐字段比较仅京成／浅草两条显示记录改变，physical站点／区间／结构／身份／里程未改；source provenance已更新。两个既有300m零slot窗口随display长度更新，禁止泛用120m重放覆盖此组。源与最终主compact逐字节相同，两个生产chunks均接到最终共点。三次顺序增量仅由实际新几何／零窗口／完整平台端面证据触发，未并行重任务或运行全量测试。

首候选`after-b1-*`已实际检查起弯和跨河、站内点，露出黑轨基本重合，连续弯曲、无回折；最终验收改用`after-b1-final-*`，首候选只作为过程证据保存。默认全量在22,057/92,217、4失败暂停，改动两线路失效25张旧receipt后22,032；这些计数不是验收数量。最终四组Inspector overlay/basemap已复查：中央、起弯、跨河和京成东北入口，连续入站弯保留，无新尖角／回折。生产主图after-b1-final-production-central-z19配对同camera139.812001,35.710434、altitude390，实际红／紫共同圆点位于斜B1主体内，鼠标已移至toolbar；点击圆点打开after-b1-final-production-station-card，含京成／東京都逻辑成员。after-b1-final-production-context配对显示独立B3圆点；站点卡四成员不表示B1/B3几何合并。最终点、完整东北端及公司接续已实际确认，默认采集已实际恢复，最近22,092/92,217、4失败，证据after-b1-final-default-resumed及review.json；计数不表示视觉通过。

后续小竹向原已归档官方p439/p599与资料说明；p439站中心6K450M000及学校地物、p599道路／铁路层位须与现代底图配准。2016千川侧改造覆盖旧平交，2023报告网页正文仅作现行选路证据，PDF下载403未伪装原件；本次未改小竹几何。当前Swift／JS follow与lane复核未发现旧平交交叉、回折或支持点删除：有乐町线区间5和副都心线区间9反向共用代表线，数字化方向使相同lane分居两侧。千川侧139.68182,35.74228→139.68545,35.74063约375.5m代表弦尚未被原中央视野覆盖，已用两个手动Mac实例补看弦中段和末端z19 overlay/basemap配对（yurakucho-senkawa-chord-end及fukutoshin-senkawa-chord-mid）。底图细黑Fukutoshin线只支持441号走廊总体走向，不足以辨别2016双路线立体分岔与精确地下分离位置；未见可证锐角／回折，未移动几何。两个手动实例已停止本处操作，默认采集继续，最近22,799/92,217、4失败；不能从历史四轨横断面强制增加四根显示线。

本地资料入口：[来源与证据索引](evidence-index.md)。索引仅整理可复用依据，不增加执行检查列表。

## 历史基线（以下证据早于本次押上修复）

2026-10-11 接续交接：大崎/京叶本轮display source及native rulers已整合，physical站点/区间/里程未改；大崎9Python+2JS、京叶10JS聚焦通过，独立review发现的Keiyo旧tail西臂重放遗漏已修。此次新source尚未build/nativeafter，不勾为图面通过。default真实暂停29,781/92,216失败4，全部旧receipt保留。用户要求过长另开chat，已整理51条完整原prompt、逐项完成对照、25历史最终报告及当前安全状态，见本目录handoff-20261011-*.md；唯一执行清单仍是本README，交接表不是第二份检查清单。

Two isolated manual Mac Inspector instances were operated by one capture owner. Two analysis workers reviewed source, official passenger platform evidence and the native screenshots in parallel. The default instance alone continued the full capture. No production geometry was relocated in this batch.

| Station | Native images | Scoped result |
| --- | ---: | --- |
| Oshiage | 13 | Two separate passenger through groups remain. Tobu/Hanzomon point appears north of the visible station body; exact underground platform/black-track central placement remains unresolved. Keisei/Asakusa has no demonstrated relocation defect. |
| Shibuya | 12 | B3 DT/Z and B5 TY/F stay separate; shared centreline endpoints and broad approach curves observed. No justified coordinate move from these images. |
| Meguro | 10 | Three operator centreline endpoints share the registered station-segment midpoint; JR remains separate. North turn and south approach retained. Namboku/Mita opposite-direction lane rows and no family suppression support parallel company identity in data, not a final main-map pixel verdict. |

All central/throat overlay and basemap pairs retain matching reported cameras, PNG and AX context. Some scale-bar labels disagree with reported zoom after stable observations; they were not used to measure distance. Underground original black track artwork is insufficiently legible for exact alignment acceptance. Single-line zero-lane Inspector previews do not certify final main-map company offsets or complete station footprint containment.

Repaired the existing through test's missing canonical dependencies/follow resolution and Oshiage's obsolete one-company mark expectation. Also repaired `repairLanes` moving the existing terminal lane row to the end on replay. Existing Oshiage tests: 5/5 pass. Through-running tests: 11/13 pass, with the previously observed Oshiage z16/z19 rendered tangent failures retained. No geometry assertions were relaxed and no umbrella test/build was run. Runtime package inputs are unchanged, so the existing native bundle remains the inspected source; the builder ordering correction does not require a runtime rebuild.

Current high-risk remainder: investigate a source-bound central cut for Oshiage without replacing real supports with a default 120m cubic, establish underground platform position before relocation, and check final main-map cross-company composition separately. The manually estimated blue-body central range is a proposal, not a certified physical platform coordinate.

Latest default capture snapshot: 8,361/92,218, zero capture failures. Capture counts are not accepted alignments; nationwide capture and visual review are incomplete. See the three station review reports and their `capture-note.md` files for source details and evidence limitations.

箱根长弧局部修复：同一客运隧道way242460442的显示支持47–54改为已校准Apple原黑轨描绘，两端及外部支持精确保留。原OSM节点连续性证明未放宽，地下实测线位不作认证。定向RED测得9.38m/4.76m描绘偏移；修复后PassengerStationApproachTests及HakoneSourceReversalTests共4测试通过（站点测试3参数案例）。当前仅箱根显示线路及相关测量引用变化，physical坐标/区间/里程、两条独立折返stem未改，重放幂等。Mac更新后复查仍待完成，本项未全线勾选。

箱根长弧更新后Mac实查完成：原clone正常退出、只更新compact资源并重签后实际重开。Root已查看after-long-arc-context-z18-overlay.png及detail-z19-overlay.png，连续长弧跟随可见原黑轨，西端原弯保留；对应无overlay底图及AX亦保存。此为特定长弧描绘验收，箱根剩余整线项目仍不勾选。RouteWorkbench仅复用physical输入未变的有效证据，没有新增全批次求解／性能结论。

品川正常客运走廊有限修复已应用：已识别正常上下行轨道中点139.73965305042694,35.629035作为13–15平台组的显示代表点；physical站点139.739427,35.629035不变。北端精确保留139.7396393,35.6297092，南段沿已识别客运轨道对中央经过真实西弯，接回原支持139.73205,35.61655，之外源支持全部保留，大崎实际分岔不变。未采用站场siding853189601或nearest黑轨吸附。站内屋盖缺逐轨测绘证据，代表点由两条正常轨道与官方平台组身份支持，不声称精确站台测量。新版显示先于大崎分岔派生重放；本站±300m零偏移窗口重算，下游follow按精确保留tail的measure差更新，只删旧喉区诊断。核心偏移24.16m和旧站点缺midpoint的定向RED先失败；15项现有文件回归全部GREEN，source/lanes重放幂等。主App增量构建及Mac实查仍待完成；整站未勾选。

后续主App唯一增量构建已成功，源与打包的两条修改记录一致。用户追加要求站内尽量直顺着月台通过：Root实际查看更新后的after-passenger-pair-central-z19-overlay、south-straight-z19-overlay及south-context-z18-overlay，站内沿纵向近直、旧横折已去，南侧连贯，没有为此新增泛用平滑改动。源段站内方位约南偏西1.7–2.1°，北过渡局部转角最大3.71°、离端点直线最大1.70m。屋盖和南侧未完整描绘单条横须贺轨道，不能把旁边Tokaido聚合黑轨当同轨认证；准确逐轨Apple线位仍有证据边界。生产圆点与北侧、真实西弯和默认恢复继续原生复查中。

品川有限原生复查完成：Inspector真实西弯z17完整连续保留，Root已查看；更新主App实际重开，production-central-network与同camera纯底图已保存。东侧总武／横须贺代表点在蓝色站体内，站内近直通过、两端平滑，独立于西侧在来线及东侧新干线；点击新点卡片仍5成员含总武线。原屋盖逐轨位置和南侧Apple聚合描绘不能作精确测量，整站与东京广范围项目继续待查。三个Inspector已统一当前compact，恢复同一默认批次的实际状态另记；没有新增全批次RouteWorkbench求解。

默认批次末次状态：三个Inspector正常重开且统一当前资源。原BatchEvidence加载24,911/92,216、失败4，相对24,963有52条受修改依赖影响的receipt失效，未清空整批证据。仅点击一次恢复；之后AX和截图读取超时，无法核实恢复后计数或运行状态。保留当前进程，没有重复启动或forcequit，不能写为已确认继续采集。loaded AX为shinagawa/after-passenger-pair-default-loaded.ax.txt；批次状态记resume_requested_actual_progress_confirmation_pending。全国检查尚未完成。

新干线对标规则已加入客运policy和Codex/Claude skill：隐藏产品叠加，按底图新干线专用样式、标签及官方平台组识别对应轨道，不拿在来线黑轨替代。Root已查看品川after-passenger-pair-production-central-basemap及东京after-repair-production-terminals-z19-basemap/network，当前暗色底图为蓝色分段样式；两条新干线记录与原生证据时输入未变，复用原图。东京站内代表线相对专用样式轴线存在可疑偏移，升级为原东京未完成项的优先任务。尚未根据聚合描绘改变坐标或认定平台中心错误，需区分底图轴线与多轨平台组。本轮为规则更新及已有像素审查，没有启动新重任务。

连续矢量显示本轮：用户指出当前窗口所有线路破碎。唯一原生操作代理先保留原样，实际读到network off、rides 0；同camera开启JTM并缩放一档后，有限范围内产品橙／绿／青线连续，Apple底图本身有规律短刻度。Root已查看current-window-network-on.png；z17诊断为15 lines／10 overlays／4799 vertices、budgetDrops 0。该范围没有复现产品断口，不作为全国通过。证据保存于shinagawa/continuous-vectors/current-window-*。

实现设计沿用整条主线／真实支线的稳定chain身份，不把几何交叉当可通行连接：builder保留overview精确接头顶点，并补显式共线owner及已审查直通对的加载依赖；native缓存记录精确接头所读取的邻线内容版本；共线owner未实际画出时，仅补其未覆盖的tenant窗口，并把潜在补线成本计入预算。已审查直通关系单独保存display-only标注，不新增物理路由边。三个builder行为回归已实测RED；native生产接口提取与定向回归进行中。默认全量采集已实际暂停26,944/92,216、失败4，保留原批次，供唯一重任务使用；未另建检查清单。

连续性定向证据：native先以旧依赖行为／旧不补绘行为实测8项、6项预期失败；修复后共线覆盖（含反向follow）、精确接头缓存、既有曲线及family parity共23项／4 suites通过。builder三个新行为回归及两个既有follow基础回归通过；对当前主包直接查询四个已审查直通对，均有唯一精确terminal端点。额外四个历史overview／family测试写死已退役us region，因当前REGIONS不包含us而报StopIteration／KeyError，未恢复NA输入或将其算通过。移除调试启动时先解码每个地区首条线路的await，当前视图可直接请求；实际请求chunk仍原位校验。不宣称已测得冷启动速度改善。native完整增量构建和修复后本体观察继续进行中。

独立代码审查发现并修复补绘预算边界：385顶点的原窗口只提交128–256这一个129顶点chunk，按部分覆盖重新切分会变成两个chunk共258顶点。补绘现保留原chunk的measure边界，viewport同时过滤polyline及其真实覆盖窗口；预算按相关owner实际chunk数量计入切口余量。首次准备tenant时只缓存显式follow关联、同family且相交的resident owner stroke，后续平移复用，避免owner迟到时旧预算不足。移除无消费者的重复family坐标数组。两项新增回归及共线／接头共12项通过，既有未改曲线与parity结果复用；独立唯一Swift回归累计25项通过。overview原测试增强为删除中间点后仍以slot指向同一站点坐标，已通过。首候选本体构建成功且四组直通依赖实际打包核对；大崎中景／近景network与basemap对照未见同线断口，保存after-continuous-vectors-*。预算修正后的最终增量构建及实查待完成，不把首候选当最终验收。firstNetworkMs会随图层切换变化，不能据其宣称冷启动提升。

最终源审查无剩余可操作问题，配对measure元数据在同步／异步materialization及viewport裁剪中保持一致。预算修正版增量Catalyst构建成功（/private/tmp/jtm-continuous-vectors-final-build.log）；最终本体原生实查与同批次采集恢复正在进行。displayJoins是本地可检索的已审查直通显示关系及来源索引，已由主包解码保存；本轮没有增加图上可通行标记，也不由显示关系新增物理路由边。真实分岔／通行仍采用原有有证据的物理拓扑，客运范围和不同公司显示策略未改。

最终本体实查完成：正常重开最终binary后加载完成，品川／大崎中景与近景final-continuous-vectors-osaki-{middle,detail}-network.png／AX已保存，Root实际查看两图；有限可见彩线连续，真实西弯保留，纯底图规律蓝／黑短刻度不计产品断口。中景17 lines／12 overlays／4913 vertices、budgetDrops 0、buildMs 20；这不是总加载性能基准，不扩展为全国无断点。产品network层保持开启供用户继续观察。默认同一批次仅请求恢复一次，实际后续计数待原生操作代理确认。

原批次恢复已实际确认：实时checkpoint从暂停26,944增长至26,958，再至27,001/92,216，失败4，pending65,211，planDigest不变；证据final-continuous-vectors-default-progress.json。AX恢复后仍超时，未重复点击、未以旧mtime作进度，也未新建批次或清空证据。最终主图network ON，用户后来移动到东京范围，未强制回原camera。全量底图采集继续；全国高风险人工判断仍按本唯一清单，不能把27,001张采集量称为通过数量。

2026-10-11继任大崎／京叶有限结果：首增量build因大崎新family缺policy color失败，root给jp-render-groups.json的base/p1独立大崎组补既有包颜色#729825/#9acd32，第二增量build成功（/private/tmp/jtm-osaki-keiyo-build-family-fixed.log）。built compact五条受影响记录精确匹配源，follow/family测量已定向查询。Kisuki Keiyo Inspector仅刷新jp-2025.json、重签正常重开，default及Hakone仍before资源；default保持29,781/92,216失败4暂停，未resume，当前soleUIowner为root，没有build重任务。

root实际查看大崎after-repair-inspector站点z18／南进路z17／南fork z17的overlay/basemap及main station配对／station-card，卡片含支线、山手线、临海线三逻辑成员。主图使用同生产Debug binary和隔离空行程库camera启动，未修改真实库；新旧camera不同，未认证屋盖逐轨精度。京叶Inspector shared-tail-view3-z17／fork-view10-z17／minami-z18配对及main shared-context配对已root实际查看：east fork以东single red、独立进路保留；west arm重复仍可见，fork小折点需复核，主图Minami单代表连续已实查，但dot／红线靠蓝站体南缘外侧、平台组中心待证。用户原PNG已实际查看。仅更新以上有限scope，不勾整线或全国通过；after证据见现有evidence-index，下一步按本唯一清单解决具体剩余问题。

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


2026-10-11本继任其他线路已开始：官方JR九州现行公告及2026-05-27发布确认八代—吉松持续停运、吉松—隼人自2026-07-12实际恢复（6月28日计划后延期）；历史矢岳—真幸偏移属于停运北段，保留历史风险，不作为当前运营客运对齐验收。木次14/15仍有客运及真实折返依据，但无新增独立精确线位，不猜改。京阪上栄町2024-10-11官方站图原PDF/渲染已root实际目视：两侧月台沿曲线前后错开、两处道口及独立入口，不能平均蓝站体或要求点位落入单个月台。Root已操作既有Inspector保存同camera35.00518/135.86019、altitude628、z18配对；同生产seam binary的主图保存固定camera同中心/distance658.3叠加及纯底图、实际点击站点卡确认京津线/京阪成员。可见进出站连续，生产代表线/点仍靠蓝站体东侧及黑轨外侧，边界候选未关闭、未移动坐标；不同月台错列解释纵向位置，但不证明横向居中。该scope见remaining-lines-primary-research-20261011.md及kamisakaemachi/current-*；未新增build/求解、未作整线或全国通过。


2026-10-11南船桥平台定位及有限修复完成：JR East April2025官方两岛图、2020-03现场照片（2022-04发表）、北高速／南IKEA地标与原生四轨共同确认北→南平台1/2/3/4对应way173053168/1424469769/1424469770/173053163。内侧siding标签不排除客运平台。原显示点[139.9957,35.681665]在四轨南侧；新显示代表点[139.995806,35.68186196884773]位于两岛中央客运带，纵向由同camera像素近似配准支持，不宣称实测WGS84平台坐标。
只改变主线及east-2显示站点与两侧局部曲线，西边界[139.9932124,35.6830748]、东边界[139.99978,35.67963]及之外支持精确保留；采用两条外客运轨道支持经度并集，保留真实fork、前轮survey入口及west-3进路。全部physical站点／区间／里程和其他线路字段定向比较精确不变。两逻辑成员共享精确代表路径，parts/follows/family引用同步，旧midcurve/west/tail重放保留最终stage，未知引用拒绝。新增回归先RED，最终2项Minami定向回归2/2 GREEN（/private/tmp/jtm-minami-green.log）；较早shared完整文件的8项既有案例通过，未宣称最终完整套件重跑。独立review指出遗漏小支持点，已补齐并重跑两项；首build后因此执行最终增量，成功（/private/tmp/jtm-minami-passenger-centre-final-build.log）。三条京叶built compact匹配源，两受改chunk站点和slot核对，几何保留既有六位小数精度。
Root实际查看`keiyo/after-passenger-centre-main-detail-{overlay,basemap}`同camera配对（35.681665/139.995886,distance438.9），匹配before-geobinding：圆点／单一红代表进入两岛中央带，站内近直连续。实际点击新点，station-card确认南船桥／京叶／JR East；UI同公司同名合为一行，两逻辑成员仍在source和chunk。`main-context-{overlay,basemap}`（35.681665/139.9964,distance1755.7）已实际查看，两侧过渡连续，未见新增尖角或回折。有限scope关闭南船桥偏南显示缺口，不证明全京叶逐轨精度或全国通过。最终主App使用隔离空行程库493399B4-217A-443B-9B43-7981F0736B57，network ON，contextcamera，session32329。
三个Inspector只刷新compact、重签原v5 binary并正常重开，两个手动实例idle。默认原BatchEvidence、旧receipts及immutable plans保留；载入29,754/92,216、失败4，较暂停29,781有27受改依赖失效。仅恢复一次，configure验证receipts期间AX超时，未重复点击；真实checkpoint随后增长29,931，失败仍4，pending62,281，当前planDigest ca243929d9af5237145ae651192f3d6ecb23530b44a940bb978fe55c6d0db9b7。见keiyo/after-passenger-centre-default-progress.json；采集量不是视觉通过数量。其余未完成项继续本唯一清单。

2026-10-11肥萨线时间机制继任：已接入既有temporal_events/rail-history/DisplayNetworkEra与dated routing。北段2020-07-04起停运；南段2020-07-06—10、2025-08-07—2026-07-11全日停运，2026-07-12恢复。吉松站体归南段；68轨道/28站体及单线路显示builder匹配通过，源重放/JS边界/Swift年代6测试通过。当前运行原生包未更新，无新的日期像素/实际求解证据；历史北段线位风险不关闭。详见[时间接入记录](hisatsu/README.md)。

2026-10-11肥萨线原生日期后续：已按用户要求增量构建并启动history rev2026-10-11.1。普通原生编辑日期控件完成7次同camera切换，实际目视确认可见北段2020-07-04起隐藏、南段2025-08-07隐藏/2026-07-12恢复、6月28日延期未提前显示；Current恢复并保持主应用运行。隔离pending探针、无rides overlay、草稿已取消，真实行程未触及。日期native证据见[Hisatsu记录](hisatsu/README.md)。历史线位风险仍开。

2026-10-11累计第57条执行接管：当前chat01a12c88继续京叶西侧剩余长段及市川盐滨，随后查东京/品川共享走廊重复、断口与站点接续；保留独立平台/快慢层位/新干线/地下总武京叶与跨公司平行。源/已构建资源继续前轮Minami及Hisatsu版本，无新几何变化前不重复build。Sol只读审查与root唯一UI操作并行；只在具体问题需要时选focused检查。

### 2026-10-11 区域俯瞰分析算法实施范围（第60条）

研究优先区域俯瞰地图及空中照片。站内结构图仅补充复杂客运拓扑，不作为单线站坐标依据。输入为无自绘线路的Apple Maps标准俯视截图、实际fullRegion、地图viewport、粗略走廊及站点seed、遮挡mask。`lib/apple_map_corridor.py`负责Mercator像素映射、横断面暗线双峰候选、连续性动态规划及有边界的站台识别；`analyze-apple-map-corridor.py`只生成GeoJSON/原图SVG叠加HTML。先以真实市川盐滨近景与区域图做聚焦回归，偏置seed不得直接成为结果；检查平台不能由仓库或无尽轨道底色替代。源几何修复须另经候选/原生图审查。此处是唯一清单中的实施说明，不另建验收流水线；东京/品川待京叶西侧闭环后继续。

2026-10-11第60条结果：图像分析库及GeoJSON/交互叠加产物已实现，7项聚焦测试通过，实际HTML目视轨迹沿铁路；市川盐滨横向候选约7.98m西北，独立平台边界仍未解析，因此未移动source点线。区域航拍z15/z17/z18已查阅保存。第57条京叶长共享段单红/连续/fork已有配对图，但站点居中修复验收仍未关闭；东京/品川后续检查保持待办。详见keiyo/west-long-review/analysis/README.md。

2026-10-11后续闭环：市川盐滨横向display stage已应用；组合3/3、final1/1聚焦回归GREEN，单次增量build成功，主图/Inspector实际配对通过。京叶西共享3.78km当前显示单代表、真实fork保留、站点接续一致；只关闭此显示范围，平台纵向中心识别仍未证明。东京/品川区域source审查与真实主图配对已执行，在记录可见范围无新增重复代表/断口；地下/独立新干线组保留。详见tokyo-shinagawa/{source-review.md,native-review.md}及keiyo/west-long-review/analysis/README.md。默认采集从73615暂停后刷新资源，正在重新加载原检查点；尚不能声称恢复采集成功。

恢复状态补记：默认Inspector完成首次加载，73449/92216、失败6、新planDigest1e616b862b86493543065ce15a1a7c0961f8dbc481124be66005108c9997587a；较暂停前73615差166，由变更依赖失效转pending，旧图片保留。root仅点击一次自动检查全部区间；startBatch会再次configure验证旧receipts，当前尚待计数增长，不能重复click或宣称已恢复。CUA曾超时reset，绑定已重建，默认Inspector最新binding可用。3个临时IABtab已关闭，server36487已CtrlC退出。主App仍运行在品川Current/NetworkON/isolatedstore，KisukiInspector idle京叶-3 view17/overlayOFF，Hakone正常退出资源已更新。

### 第61条原生检测器实施计划

在已有RailAlignmentInspector手动当前视点流程增加“抽离铁路与车站”及纯净抽离视图。RailInspection内纯Swift像素提取器从无产品叠加的MKMapSnapshotter图像分析窄铁路符号对/连续性/竞争候选，拒绝道路宽边缘、建筑及局部文字干扰；构建几何只作搜索走廊，并单独计算有支持采样的偏移分布。Snapshot.point(for:)提供同图像像素投影，避免相机框/屏幕遮挡误差。车站搜索使用Apple publicTransport POI，明确与平台轮廓区分；未呈现平台不能宣称自动平台中心。原生UI显示绿色抽离候选/青色构建线/站点对比，底图可隐藏，JSON及GeoJSON/快照可导出。选择/视点/窗口变化使结果过期，后台分析不能覆盖新视点。只按按钮分析，不扩展全量采集或自动source写入。复用当前源和唯一清单，先聚焦Swift回归，再一轮增量Inspector构建和真实市川盐滨含道路/仓库的UI检查；一项重任务运行期间暂停原批量任务并最终恢复。

第61条结果：原生“抽离铁路与车站”/纯净对比/JSON与GeoJSON导出已接入三个检测app并在KisukiKeiyo终点站实际执行；80%支持、0.5m中位/2.9mP95，1同名Apple POI7.3m，原生导出及过期导航实测通过。候选在所测视点过滤附近道路/仓库；平台中心和全样式识别率未证明，不自动写source。详见apple-map-extraction/README.md。原批量此前实际恢复到73834后为此次唯一重任务暂停，证据保留；须更新默认进程并恢复。


第61条最终交付与资源协调（2026-10-11）：Mac Inspector原生抽离/对比/文件导出已实装，三个聚焦Swift回归通过，最终Catalyst增量build成功；实际京叶终点市川盐滨z18抽离72/90支持，2段候选，中位0.48m、P95 2.90m，同名Apple车站POI与构建点7.27m。最终图和原生导出见apple-map-extraction/native，边界见该目录README。京叶窗口保留完成结果，无手动分析运行中；Hakone已更新但未运行。
默认批量当前并非运行：Audit the full iOS codebase（01a12d77-271a-7eb2-a55c-46995376121d）请求暂停重任务，已核实该聊天直接用户授权“Yes, coordinate with that chat”并发送保持状态。默认PID 46271在启动收据校验中SIGSTOP，STAT Ts；captured 73834/failed 6/pending 18376；planDigest 1e616b862b86493543065ce15a1a7c0961f8dbc481124be66005108c9997587a，unavailableIntervalCount 0。内存/计划/历史证据保留，记录/private/tmp/jtm-native-extraction-default-hold.json。等待审查聊天释放资源前不要新build/test/capture；收到释放后先核实PID/executable/debug.dylib是否被替换，再SIGCONT或安全重启。此前“待恢复”状态由本条替代。


资源释放后恢复（2026-10-11）：审查聊天报告全部聚焦job退出、默认产品未覆写。root核实同一PID 46271为原Inspector --batch-all、STAT Ts，只发送一次SIGCONT，随后STAT Us。原checkpoint实际从73834增长到73939，failed 6、pending 18271，planDigest保持不变，unavailableIntervalCount 0。未重启、未删除输出、未另起手动分析或重型检查。本条替代此前hold状态；既有进程未重载审查聊天随后修改的X02共享admission代码。证据apple-map-extraction/native/default-resumed-checkpoint.json。


架构聚焦检查资源保持（2026-10-11）：审查聊天01a12d77-271a-7eb2-a55c-46995376121d请求继续占用heavy槽进行乘车解析/physicalwalk状态owner/统一AI资格的聚焦测试及Main增量编译，声明不更换Inspector产品或采集/geo数据。沿用已核实用户协调授权，root核实同一PID 46271后SIGSTOP，实际STAT Ts。checkpoint captured 78146、failed 6、pending 14064、planDigest 1e616b862b86493543065ce15a1a7c0961f8dbc481124be66005108c9997587a、unavailableIntervalCount 0。记录/private/tmp/jtm-native-extraction-default-hold.json及apple-map-extraction/native/default-architecture-hold-checkpoint.json。原进程/输出保留，未重启或另起分析；等待审查聊天释放资源后核实身份并SIGCONT恢复同一计划。此条替代此前running状态。


架构检查后恢复（2026-10-11）：审查聊天报告heavy槽释放、全部job退出且未更换Inspector产品。root核实同一PID46271/--batch-all/STAT Ts后仅一次SIGCONT，实际STAT Rs；checkpoint captured从78146增长至78260、failed从6增至7、pending 13949，原planDigest不变、unavailableIntervalCount 0。新失败保留、不自动重试。未重启/删除输出/并行manual分析；仍为既有载入版本，不作为新Core接口或admission运行证据。证据apple-map-extraction/native/default-architecture-resumed-checkpoint.json。本条替代上一hold状态。


第62–64条当前执行范围更新：用户要求三个独立检测app优先并完成整个站间区间，之后主app完整生产复查。不以此前区域/站点单图替代全区间。使用现有Inspector current-interval功能串行采集每个350m详细视点，逐图复核、保留失败；本轮无全国自动采集。当前源码归属复查12记录/11follows无新增冲突，但不能证明像素。主app初步东京近景已保存后退出；后续需回主app完成生产显示验收。


第62–66条当前结果：三个独立检测器串行完整采集15个站间区间116/116视点（含两端及短尾），失败0；root逐一看完全部配对，随后主app四个重叠范围覆盖全区间，加东京/品川.003站内和成员卡。可见代表线连续、实际fork/独立平台走廊与跨公司平行保留，未发现新source修复项。详见tokyo-shinagawa/station-throats/results.md和full-intervals/scope-results.json。地下/屋盖精确位置和新干线平台中心仍证据不足，不勾整站地理通过。主图移动事件配对按实际大崎相机更名；用户已明确由root继续、暂不移动主图。当前三个检测器均idle(42/42/32已捕获本轮)，原默认全国capture进程已不运行，不把旧恢复状态当现况。按第66条继续木次→箱根→其它历史未完项；保持原唯一清单。


### 第66条全线路顺序检查续记（2026-10-12）

木次线17个完整区间262个视点已全部人工查看（0–8为121点、9–13/16为103点、14/15为38点），含端点和最后短尾段。依赖严格相同的237点从既有native证据复用，另有首区间12点及缺失区间12的13点实际新采集；复用记录见kisuki/whole-line-reuse-record.json。采集量不表示对齐通过。原生南大东抽离17%像素支持，中位18.0m/P9526.7m；区域航拍与确证的JR木次主客运node链支持调查。来源与纯净抽离/native导出见kisuki/full-line-review。

南大东005094显示alias及区间4/5有界approach首候选已写入owning outer stage，4项定向回归通过；physical、既有三井野原和折返parts保持。一次Main增量build成功，三个Inspector compact资源已刷新。重新采集并实际查看区间4/5全部24点时，root发现区间5边界13.22m垂直小台阶，正在修正，首候选不验收、不关闭木次清单。before整线与首after均保留，不覆盖历史资料。

箱根鉄道線10个完整区间59个视点已全部人工查看basemap/smooth/display，含小田原端、强罗终尾与两处折返（新采集35点，依赖相同复用24点）。59/59、failed0/pending0仅为native采集证据；见hakone/full-line-review/review.md及whole-line-reuse-record.json。山崎曲线偏移待航拍同轨核实；塔之泽view4实为相邻区间5的两node隧道，归为隧道描绘不一致、物理线位证据不足；出山真实stem与南侧进路有既存GSI参考，不能直接Apple吸附。箱根项仍未整线地理验收。

root保存油木南侧、备后落合北侧、出云三成与云之原四处区域航拍；树林阴影/积雪及KSJ共同源使南部OSM链不能单独证明真实轨道偏移。三成station局部有较清晰独立影像，候选正在调查。后续仍按本唯一清单继续，不另造全量验证流水线。


第66条后续：肥萨线27区间394视点已全人工查看basemap/display/smooth，北段273历史视点、南段121视点，所有端点/短尾段覆盖。原生新采集首南段23及缺失45，326点按native依赖/identity/viewpoints匹配复用并经configure校验；见hisatsu/full-line-reuse-record.json及full-line-review/{north,south}-review.md。北段渡附近#12/6–8、南段#19/16–17、#21/5–7、#25/7–9保留偏移候选，树林/隧道/平行道路处不吸附；大畑环线和真幸折返保留。当前/历史运营显示仍由既有时间机制控制，与geography检查分开。

京津线6区间30视点已全人工查看：上荣町连续接续，御陵地下不足，大谷#3/4–5和#4/0–1待同轨源依据。6点actual新采集、24点native依赖相同复用并已configure校验。主线/Metro公司身份及滨大津fork保留。见kamisakaemachi/full-line-review/review.md。

京叶main17区间148点、east2整区间17点、west3整区间18点共183点已全人工查看，端点/短尾段覆盖；main13+两臂35actual新采集，其余main135复用native相同依赖并经configure校验。葛西临海公园至荒川桥附近main11/12发现实际display/smooth都偏南，正在同主客运桥梁源认轨调查；分支fork/南船桥/市川盐滨Inspector接续连续，地下东京仍不足。见keiyo/full-line-review/review.md。此处未据Inspector宣布生产folding验收。

南大东边界小台阶已纠正：仍在原受改window内120m沿已确证同轨的位移过渡及retained tangent guard；新增productionstroke回归先RED复现90°，最终5/5GREEN。root已实际查看final24native点，两边短垂直连接消失、未见新增断口/回折。箱根山崎interval3有界同轨display修复及nativepart1/extent更新，12项聚焦回归通过；root已actual查看最终整个区间7点，原山崎偏移改善，外侧接续连续。两个owning outer stages/source、cachedparts及references经过独立审查，无可操作缺陷；physical/mileage/其他parts不变。合并Main增量build成功/private/tmp/jtm-kisuki-hakone-final-build.log；Main及3Inspector compact与源匹配，已重签。最终after目录kisuki/full-line-review/final-minami-daito与hakone/full-line-review/final-yamasaki。

南大东native最终抽离15%支持、中位2.9m/P954.4m。before17%/18m/P9526.7m与after相机随显示anchor改变，不宣称逐像素同camera/同样本beforeafter；仅支持此片段的偏移改善，Apple0同名POI也不证明平台中心。主Appactual station配对1line/1overlay/budgetDrops0，新点接入连续木次线，实际点击卡片确认JR West木次成员；整个相邻区间配对连续且站点接续保持，随后继续主App整线范围/其余线路检查。


### 第66–68条最终范围结果（2026-10-12）

本轮原顺序范围完整人工检查94个区间1044视点：东京/品川选定15/116、木次17/262、箱根10/59、肥萨27/394、京津6/30、京叶19/183。端点与最后尾段均包括；旧native证据仅按已核对依赖复用，不把全国92k采集计数当成通过。区域航拍认轨后已完成南大东、箱根山崎、葛西临海公园/两桥、上荣町四个owning显示修复与各自完整受改native范围重查，更新主App。南大东/山崎整线Main范围已实查；上荣町after同camera点/两侧及实际card已保存；京叶新木场至舞滨两个完整区间、江户桥/荒川桥东西侧、全主线与两臂、整个西侧3.78km共享及两fork的主App配对已实查。共享红代表连续、真实fork与南船桥/盐滨成员保持。荒川西首次相机偏离(35.643347,139.839959)，只作过程资料；有效最终 fixed-camera-after35.646421,139.846402。精确地下东京与树林/隧道偏移候选继续WARNING，不据整线宽图勾全部精度通过。

新增67本乡三丁目、68大崎已优先并入同一工作：大崎局部南二/站一/北一JR显示修复完成，三个专用app4完整区间29点+Main近景/南合流/全关联区间实际复查，卡保留全部名称；见osaki/final-station-representative/results.md。Hongo两公司独立显示锚点/四个有界进路完成修正，三个app4完整区间17点与extract+Main两dot/card/完整四区间已实查；见hongo-sanchome/final-display/results.md。所有physical身份/里程保留。两专项JS共7项、既有Osaki Swift单项通过；实际最终构建成功。地下锚点按明确次级源有限修复，不宣称地理测绘。

当前默认全国批次没有恢复运行，三个专用app在检查完成后正常退出，原checkpoint/receipts保留。首轮scope1044与新增29/17可能有线路范围重叠，不合并声称独立唯一总数。未解决地理候选继续留在原风险项，唯一清单不另增一份。

最终实际留在主App：camera35.6188,139.728,.012，network rendered，12lines/10overlays、budgetDrops0，截图/AX为osaki/final-station-representative/main/left-running-final-*。三个专用Inspector正常退出，无新的默认自动采集。


### 第69–71条三田线与经验维护（2026-10-12）

都营三田线西高岛平—目黑 26 个完整区间、115 个 before 与115 个最终 native 视点已全部人工复查。北端0–5保留；地下6–25按已确认的Apple蓝色线路对齐，三田—白金高轮约55米旧偏差纠正。三个专用app顺序完成全线捕捉/整线/重点独立抽离后，Main一次增量build成功并实际查看整线+五个重叠区域、白山同相机和三田西侧近景、白山与白金高轮成员卡；共享南北线身份与逻辑成员保持。显示与抽离各6项定向测试通过。结果与精确证据在mita/results.md，不能把局部支持指标当整线精度统计。

当前Main停在camera35.6465,139.742,.016，Network ON、12lines/12overlays、budgetDrops0；有效最终相机为mita/main-final/left-running-final-*。一次旧成员卡窗口误作最终相机仅保留process证据，明确关卡后重新选中最终实例完成正确配对。三个Inspector正常退出且资源与最终源一致，默认全国批次保持停止，旧receipts未删除。

用户最新明确简单底图直接按对应线路对齐。被否定的OSM整线候选、OCR缺口归零三角、40米窗口漏掉55米弧线，以及Debug代码在dylib/成员卡窗口选择问题均已记录到repair-lessons-20261012.md，并更新全局jtm-railway-audit-repair/SKILL.md及中文经验参考。现有英语标签Sanda Line仍为独立名称问题，列入本唯一台账，未扩大几何范围。

### 2026-10-12 大崎支线接头复查（已完成两处修复）

最终补充：用户答复“两处都有”的站南合流及南侧Sobu分岔均已修复。5完整区间41最终native视点全部人工复核，Main两处及五区间整体、成员卡已实查，结果为osaki/branch-join-recheck/results.md。Osaki JS3项和新增Swift回归通过；旧圆弧/fixture测试仍失败，结果页如实保留。下文调查叙述为过程记录，以本段最终补充为准。

同类京叶4完整区间60新native视点及Main两接头近景、中段、区域/两臂全范围已实查，普通network连续，选中arm曲线及亚像素接头残差保留WARNING；详见keiyo/junction-recheck-20261012/results.md。当前Main留在35.68,139.975,.08，network ON、15lines/13overlays、budgetDrops0。三个Inspector正常退出。原唯一清单地下/树林/平台精度项仍未关闭，本轮完成不代表全国所有铁路精度通过。

用户要求继续唯一列表顺序检查全部铁路，且每条必须完整站间范围；新增报告大崎支线连接依然错位，同类合流/分岔接头也须检查。大崎此前碎线数量验收不关闭本次接头位置问题：重新打开站南合流和南侧总武/横须贺接入。先实际Main同相机ON/OFF复现，再三个专用Inspector串行检查base/p1完整区间和相关owner完整区间；检查production lanes/follows/family边界，不能以零lane单线预览代替接头验收。当前为调查中，尚无新修复或通过结论。证据入口osaki/branch-join-recheck。后续沿原清单逐线检查同类接头，不创建第二套检查列表。

同类京叶 east/west 共享接头已做有界源及最终 RailStroke 检查，两臂完整长度每10米、z10–19，均 finite；两臂各只有一个非 identity follow，本次通用过滤不会改变它们。east 当前 family 边界的0.1米取整产生约0.062米的映射不一致（z19约0.544px）；west z14 mapped 残差约0.376px，属局部曲线/LOD而非取整。共站端点为0或浮点量级。普通 network shared span 由 trunk 绘制，选中 arm/ride 的局部曲线峰保留 WARNING；不能把两臂中心线历史通过扩展成所有 production 路径通过。接下来在 Main 实查这些具体位置及完整两臂，按本唯一列表继续。scratch 具体坐标与量化在 `/private/tmp/jtm-keiyo-join-probe.{mjs,out}`。

2026-10-12 terminal placement rule: ending railway stroke and station dot share the exact display anchor at the centre of the identified Apple Maps station box. Correct group identity first; preserve other through railways and physical data. Policy and global repair skill updated; actual Nishi-Takashimadaira ON/OFF evidence and limitations in terminal-station-rule-20261012/results.md. This is an adopted rule, not a claim of nationwide terminal corrections.

2026-10-12顺序续查：原六组剩余范围按顺序完成当前依赖复核和新的Main范围配对，复用未改94区间1044视点的完整人工证据，不扩大为全国通过。新发现强罗显示终点偏北约33m，已按Apple常规铁路站框纵向中点与认轨带交点修复，physical/里程/折返不变；5项聚焦回归通过，完整受改区间4个after视点全部三图人工复查，三个Inspector资源更新，Main增量build成功，实际终点／成员卡／完整区间及整线配对已查看。证据 ordered-continuation-20261012/results.md。用户新增：给Main及三个Inspector加入快捷键；品川南侧分岔和附近三个分岔须按Apple同点对齐，已重新打开原品川项，三个实际同视点配对保存，不能复用此前“无新增问题”来关闭此次反馈。继续按唯一列表，完整区间包括两端与短尾。

2026-10-12上越整组续查：4个记录39完整区间600当前v5视点1800面板已全量人工查看；可见地面范围未发现主线/方向线具体缺陷，长隧道与地下站台保留WARNING。Gala支线越后汤泽端发现约120m横切站体的display错接，已在Main复现，GSI2022区域俯瞰与官方运营身份说明确认应进入西侧新干线设施组。仅display站点/末点复用现有新干线锚点的候选正在处理，尚未apply/验收。原唯一台账继续开放，不据600采集数或整线宽图宣布全国完成。详情ordered-continuation-20261012/results.md。

上越整组最终补充：39区间600视点全量人工覆盖，Gala末端显示错接已按独立完整7候选/7生产after复核修正，Main同相机末端／成员卡及全支线已实查。6项聚焦回归通过，所有原生资源更新；物理/里程/前24点保留。宫内俯瞰与N02共同站体证据否定了35–40m物理偏移解释，保留现点和专属站台精度WARNING。长隧道／地下站台WARNING仍在，未宣布全国完成。下一原风险序列为篠ノ井线完整14区间。

篠ノ井线完整14区间212视点636面板已人工复查，Main整线、双端、松本完整lane及姨舍折返实查。Main发现姨舍北臂偏移，四组Apple区域原图回投与完整冠着—姨舍19/姨舍—稻荷山25候选视点均已独立人工ACCEPT；正在修复owning脚本的新增点索引假设，再做生产after与Main完整相邻区间验收。地下／精确站台位置WARNING保留，当前尚不关闭篠ノ井生产修复项。

篠ノ井最终补充：姨舍北臂及代表分岔display修复已apply，6项聚焦测试通过，生产builder及6现有原生bundle资源更新重签完成；44个受改after视点132面板已逐组人工PASS。Main实际同相机分岔、北臂、站点折返及完整冠着—姨舍—稻荷山配对通过；原完整14区间212视点中的未改范围依已核对局部依赖复用。地下／精确尖轨／专属平台精度继续WARNING，物理/里程/身份保留。经验已记录并更新两份全局铁路skill。按原风险序列继续小野田本线及本山支线全部10区间55视点。

小野田整组最终补充：本线8区间45视点与本山支线2区间10视点已全量人工查看。Main发现雀田错误共享映射与西侧曲线偏移，分别有界修复；3项follow及6项curve聚焦回归共9项通过。曲线经全7候选四联接受，再全两个受影响区间12生产after三联人工PASS，Main同相机曲线／分岔、完整关联区间、整组所有线路与雀田成员卡实际通过。原生6bundle资源更新重签，物理/里程/支线/站点身份保留，精确新75m错误producer签名被owningstage持续剔除。居能Apple多平台归属仍WARNING，未盲移点。详情ordered-continuation-20261012/results.md。继续原risk序列，木次/箱根既有完整范围及未改v5依赖复用后下一札幌电车关联整组，不宣布全国完成。


札幌電車关联整组完整复查：1条線3区间9视点、山鼻線11/28、山鼻西線8/23、都心線2/4，合计24完整区间64当前v5视点192面板，均实际人工查看，含所有端点与短尾。永久原生证据sapporo-complete-native-before/scope-receipts.json。Main完整四记录环线及西15丁目、西4丁目、すすきの、中央图书馆前四处接续和东南转弯实际ON/OFF配对已查看，均network:rendered、budgetDrops0，无可见碎片/断口。四个法律记录边界不是运营终点，未套用终点截断规则。都心线按官方2015-12-20开通的路侧轨道保留西侧走向，不吸附道路中心。北侧约4–7m Apple电车导引差异与东南弯道约6–10m形状差异仍WARNING：GSI2020年8–9月两张区域俯瞰实际查看，阴影/车道标线遮住细轨，不能唯一定位代表轨道中心；不能据薄蓝导引或采集计数宣称精度通过。无札幌几何修改。继续原风险顺序万葉線高岡軌道線及相关新湊港線完整组。


Manyo whole-group actual manual review complete: Takaoka17intervals51triples153panels + Shinminato7/25/75 =24completeintervals76views228panels, allcurrentv5. Permanentbefore manyo-complete-native-before/scope-receipts.json maps actual metadata identities, never directoryordinal alone. Main whole group, Rokudoji/bridge and bothremote termini pairs viewedloaded0budgetDrops. Concreteoffsets identified at both#0/Rokudoji/Shogawabridge, Takaoka#2-4 nearYoshihisa/Yonejima and Shinminato#5-6. Regional GSI2024 Rokudoji/Yoshihisa and2021 Takaoka/Koshinokata/Kaiwomaru used to identify rails; notroadcentre/thinblueguide. Group notaccepted.
EastfirstcandidateMainKaiwomaru stationcentre REJECTED, notapplied; Rokudoji repairs/Takaoka#2-4 remainunderreview. Details ordered-continuation-20261012/results.md.

Manyo 高冈全17/51近景抽离已补齐，实际analysis ID/index核对记录ordered-continuation-20261012/manyo-takaoka-complete-z18-scope-receipts.json。两记录24/76完整候选回投复查完成，尚待统一native/Main候选验收；001845/001851/001861站台组归属警告保留，生产未写入。三个专用Inspector已更新站台形状算法并实际运行，海王丸两个填色分量零定位支持，不宣称自动站点通过。

原列表下一条唐津线全12/140原生视点、420面板已实际人工查看，完整资料karatsu-complete-native-before。Main全线/西唐津终点/久保田共用端点/多久两侧整段已对照。西唐津端点明确偏到东侧车场外，own西侧平台修复待完成；久保田平台归属及仅蓝导引处保持WARNING，唐津线未关闭。全国列表仍未完成。

唐津线西唐津显示修复已正式写入：整线12/140原生人工覆盖保持，受改首区间8/24候选native、Main同相机终点/完整区间/南客运咽喉/真实JR九州唐津card通过。208显示点、693 native点，guard19及后9坐标和remote494 native点保持，其他11区间/physical/IDs/km不改；postapply5/5通过。具体物理平台边界、久保田共享平台及蓝导引处仍WARNING。正式6app资源交付正在进行，不能将此勾为全部站台测量精度通过。

万叶线V4原生24/73线路连续性通过，但Main拒绝广小路道路gap点；五点/九完整邻段V5正在native/Main验收流程。原列表序号15京急空港线全6/27原生取证已完成，人工查看进行中，地下段不可用其他线/道路补齐。

2026-10-13 priority repair: Matsumoto Oito terminal sharp tail is formally repaired. All five related complete intervals were reviewed in each of the three dedicated Inspectors (47 views / 141 panels each), followed by actual Main station, real north fork, shared span and all five complete intervals/endpoints. Physical junction, IDs/km/routes and independent Alpico track remain unchanged; source-derived direction regression distinguishes south Shinonoi→north Oito direct movement from Tazawa→Oito station reversal. Post-apply 6/6 focused tests passed. Evidence: [Matsumoto scoped repair](ordered-continuation-20261012/matsumoto-direction-review-20261013/primary-native-candidate-review/RESULT.md). Simplified basemap/survey precision warnings remain. Manyo V5 and Airport Main are still pending; continue the original ordered list after those, without a nationwide completion claim.

Manyo V5 is now formally applied (2026-10-13): five own-frame station representatives passed actual Main close checks; nine complete changed intervals passed in all three Inspectors (23views/69panels each). Exact unchanged local V4 evidence supplies49views; current whole two-record scope72views. Main full changed range and whole group including allthree remote boundaries passed,0budgetDrops. Postapply5/5PASS; all6app resource/signaturedelivery complete, Matsumoto/West preserved. Travel-direction platform identity and surveyed precision remain WARNING. Evidence: [V5 complete scope](ordered-continuation-20261012/manyo-complete-display-candidate-v5/manyo-v5-v4-reuse-proof.md). Continue original Airport Main then Jounan/Higashiyama/Tsushima; list remains open.


2026-10-13 continued after Mac shortcut update: Airport full-line Main and independent endpoint intervals now inspected; terminal004368 is outside the required longitudinal frame midpoint, so ordinal15 remains pending bounded display repair. Jounan ordinal16 full11interval27views/81panels and Main full/West/Dogo inspected; western tram-band offset and multi-arm legal-record serialization remain pending. No acceptance from capture counts. See [current chronological findings](ordered-continuation-20261012/results.md).


2026-10-13 Airport ordinal15 V5 formal repair accepted: all six complete intervals captured separately in each of three Inspectors (27 views /81 actual reviewed panels each;243total). Main seven own-station close ON/OFF pairs plus full-line pair actually inspected; six display dots moved to own Keikyu frame midpoints, terminal ends at dot, Kamata shared anchor preserved. Rejected V1 hump, V2 constant runway translation, V3/V4 residual offsets; V5 unique own-glyph normal tracing accepted. Physical IDs/km/segments/source/routing unchanged; all other657 lines and lane/reference structures preserved. Formal arrays/native parts exactly equal accepted candidate; focused postapply5/5PASS. Runtime evidence keikyu-airport-complete-display-candidate-v5. Underground cartographic reference is not surveyed tunnel proof. App formal delivery in progress. Next ordinal16 Jounan: whole6associated-record group29interval70views reviewed (Jounan27 +associated43), west ~15m horizontal north /~6m NS west defect remains repair pending; no completed-list claim.

Airport V5 formal delivery completed: all six app resource signatures verified; formal Main terminal ON/OFF observed at the same camera, correct own-frame midpoint and terminal-end dot,0budgetDrops. Both global rail skills updated with own-glyph/normal-trace/label-contamination lessons. Continuing original ordinal16 Jounan.

2026-10-13 latest V3 continuation: rejected V2 City Hall approach because it followed the road/moat curb rather than the tied black tram rail. V3 freezes literal Minamihoribata junction [132.76179812,33.83934635] in Jounan #2 and a separate 29.8m Hanazono platform-to-switch display lead, preserving all 35 aliases and physical topology. All three Inspectors actually newly captured and pixel-reviewed complete Jounan11 + Hanazono1 scopes (12 intervals/30 views/90 panels each). The unchanged four-line source/native inputs equal V1, so reviewed17 intervals/41 views/123 panels per app are explicitly reused; current-equivalent total29/71/213 per app, not71 fresh. Main V3 actual complete Jounan11 ON/OFF pairs22panels saved; remaining18 intervals and full group context pending. Main startup first frame did not draw custom rails despite subsequent rendered AX; invalid #0/#2 early pairs were overwritten with steady visible rails/dots and reviewed anew. No production apply or full-group Main acceptance. Whole-line shortcuts Return + Option-Shift-Command-C actually used successfully in all three Inspectors. Shared heavy window released at safe stop (all apps exited) for coordinated Duo cases; static review continues.

2026-10-13 ordinal16 Jounan six-line group formally accepted/applied/delivered: all29 intervals/71views/213panels per Inspector (fresh30 + input-equivalent reused41 explicitly accounted), all3 manually reviewed; Main29 complete ON/OFF pairs +full context,60 actual panels reviewed. V3 repaired actual west corridor/frame dots, Johoku Kaya frame, Otemachi curves, Honmachi own NS faces, Renraku own shared Heiwa/Kami faces, Jounan tied-black CityHall curve and literal Minamihoribata q with Han29.8m display lead. AllphysicalIDs/km/segments/route graph preserved. Formal all658line objects andnativeparts equal acceptedV3;10/10focusedpostapplyPASS. Sixexisting app resources andstrictdeep signaturesPASS. Builder chunks/stations reused because onlyunconsumed manualOverrides acceptance metadata changed; formalmanifest JPsourceSHArefreshed; no newbuilderrunclaimed. RootactualformalMain J2+whole context reconfirmed,12lines7overlays3472vertices0drops. Evidence jounan-group-display-candidate-v3/formal-delivery.json. Next originalordinal17 Higashiyama21interval90views, then18Tsushima7/44; scopesprepared, no actual17/18pixelacceptance yet. Entire railwaylist remainsopen.

2026-10-13 originalordinal17 Higashiyama COMPLETE manualdisplay review: each3Inspectors actual21interval90views270panels independently reviewed,0targetpending/failed; Mainall21completeintervalON/OFFpairs+full-linecontext44actualpanels reviewed. Fullgoldroute continuous, #14Nagoya→Kamejima correctnorth/NWthenwest andnoJRyardborrow; alltail/endpoints covered. No concrete owningrepairestablished. UndergroundAppleblueguide≠survey tunnelcentreline andFujigaoka/Takabata exactstationframe longitudinalmidpoints remainWARNING. WideMain476annotationAXpagination requiredtemporarydotsoffdiagnosticprobe; restoredbefore actualON/OFFimages andcameraunchanged,actualboundsalllinepointsinside,notfaked dots-ONstatus. No source geometrychange/test/build needed. Scope-result.json preserves actualreceipts. Continue originalordinal18 Tsushima7intervals44views +bothrealconnectioncontexts; notnationalcompletion.
