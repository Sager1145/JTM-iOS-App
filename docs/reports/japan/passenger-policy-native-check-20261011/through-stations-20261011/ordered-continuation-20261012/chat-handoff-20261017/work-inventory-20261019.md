# 工作完成度与重构前交接

快照日期：2026-10-19。范围：本任务涉及的统一诊断 App、日本逐线检查／显示修复、相关实际接口与数据结构准备；中国真实车次工作和较早架构工作的独立 owner 文档只作交叉索引。本文件不宣称逐函数重新审计全仓库，也不替其它聊天作全国验收。

后续状态继续写 [audit-status](audit-status.md)。[数据结构重构准备](../../../../../../reference/railway-data-overhaul-preparation.md)描述下一阶段，既有 [README](README.md)、[integration-status](integration-status.md)和 results 的旧 pending 记录按后续明确证据解释，不能单读一段历史状态决定当前完成度。

## 状态怎么读

| 状态 | 已证明 | 尚未证明 |
|---|---|---|
| 请求已准备 | 精确输入／范围／设置已形成 | 未必执行，不能计作截图 |
| 可复用 receipt | 当前有关身份、依赖、合同及文件符合复用条件 | 不等于本轮实际看过原图 |
| 已看原图 | 指定 reviewer 实际查看指定PNG／范围 | 不等于平台、物理连接或全线接受 |
| 候选已生成 | 有独立候选和来源／边界说明 | 未必经原生复核、apply 或 Main |
| 已应用修复 | 当前生产显示已采用有证据的最小变化 | 不代表整线或未改位置无问题 |
| 局部 Main 完成 | 指定相机的实际生产资源、ON/OFF与像素问题核对 | 不代表所有缩放、日期、多线组合或性能通过 |
| 已否决／证据不足 | 有明确反证或未证事项，现状保留 | 不能迁为默认修复、兜底几何或自动通过 |

一“对”通常指同视点basemap+smooth；旧多模式报告有三张一组，不能把对数和PNG数直接相加。complete目录名和生成result verdict不是验收结论。

## 已完成：统一诊断 App 与操作流程

- 一个活动 RailDiagnostics target 包含 Alignment、Physical routes、Through history；旧三个源目录保留为内部实现，已知三份旧安装克隆可恢复迁走。Main独立保留。不是全磁盘所有可能副本的扫描证明。
- 人工表单、导入文件、agent请求、workspace动作和标明快捷键的菜单共用DiagnosticRequest/DiagnosticSession。实际人工/agent/键盘、有界错误/暂停续跑/原图查看已观察。[最终重做证据](../../../../../../../ios/auxiliary/RailDiagnostics/Evidence/20261017-remake/README.md)。
- 六项简化已实施：删除旧启动旁路、一次scope准入、capture owner统一统计、进度与证据写入分开、只编码所选PNG、through摘要在文档actor计算。不是待实施建议。
- 后续已经补齐：精确候选包输入及坏路径可见失败；gallery上一/下一共用选择且常显⌃⌘J/K；文件hot-open直接执行请求；单实例声明与实际同PID复用；sharpTurn候选坐标/前后边长；exact viewpointIDs及13项聚焦合同、实际按钮/键盘续拍。见[接口清单](../../../../../../reference/function-interface-map.md)和诊断Evidence目录。
- reviewer notes复用同一DiagnosticReviewLedger。渡良濑3条已实际原生加载3/45；三岐1条lineOffset记录仅保存到磁盘，尚未在退出后的App重新加载。结果仍保留pendingReview，不把capture success改成pass。
- 最新一轮同PID20655串行完成三岐16、北势4、三陆44、三岐近景3，共67视点/134新PNG，全部实际看过、0失败；另21对既有图实际查看。[收据与快捷键AX](../../../../../../../ios/auxiliary/RailDiagnostics/Evidence/20261019-sangi-sanriku-continuation/README.md)。正常退出并核对无本轮原生/构建进程后归还共享窗口；此快照前收到CN也已退出归还的消息，但本任务仅做文档，未重新启动App。

仍未完成：全面无障碍验收、全App性能／内存／泄漏测量、全国像素／物理连接验收；无常驻agent、后台调度或全国自动修复循环。此次文档任务没有新运行构建、测试、截图或生产迁移。

## 已应用显示修复与最终证据

表中的native“采集/重点原图审”与“全部配对已审”刻意分开。它们都不提升为独立测绘或全线验收。

| Line / 窄scope | Applied | 既有focused tests | Native证据实际边界 | Main最终状态 | Open项/重要限制 | 准确报告路径 | 既有单一authority |
|---|---|---|---|---|---|---|---|
| 北陸 p1 / 鳩原东弧及方向 | 已apply；138点；loop up/直线 down | Node6/6；Swift direction RED→GREEN1/1 | 完整34/34配对审阅；三模式102PNG尺寸核对 | 全景+交叉近景同镜头ON/OFF | 南环/新疋田侧差、两站caps；canonical完整物理链/km尚未重新确权。方向许可有意改变，不能写routing完全不变。 | [report](../hokuriku-p1-complete/sharp-corner-repair-20261018/README.md) | repair-hokuriku-p1-loop-display.mjs |
| 相铁横滨 #0 own-platform 短钩 | 已apply；只删B，A/C保留；首300m lane0 | Node5/5；imagery设置Swift1/1；reapply幂等 | baseline7/7+candidate7/7采集；parent原图0/1重点审 | 同镜头ON/OFF已看，own row/chunk相符 | 完整usable双帽/hidden rail精度、其它相铁侧偏/大和/海老名等未因此关闭。旧glyph-only拒绝已被own-platform强证据取代。 | [report](../sotetsu-main-complete/platform-proof-20261018/repair-result.md) | repair-yokohama-itoigawa-own-platform-display.mjs |
| JR西日本大糸 / 糸鱼川 #7站尾 | 已apply；guard32后own tail；display anchor移约29.65m | 与横滨同一Node5/5、Swift1/1；无重复计数 | baseline29/29+candidate29/29采集；parent选定approach/platform原图审 | 同镜头ON/OFF已看，own endpoint/alias相符 | 东cap遮挡，reference-assisted位置；不能写全平台测绘中心或全线接受。 | [report](../oito-west-complete/platform-proof-20261018/repair-result.md) | 同上单一authority |
| 田园都市 #3 駒沢大学→桜新町 | 已apply；保留guards/真实compound turn | Node4/4；fixture缺实际Hanzomon owner已修 | baseline14/14+candidate14/14；parent重点6/7原图 | 共享batch同镜头ON/OFF已看 | 地下own参考协助；工程R315/750的方向到轨行映射未建立，不能称独立地下survey。 | [report](../denentoshi-complete/curve3-candidate-status.md) | repair-denentoshi-shimmachi-display.mjs |
| 京叶2 Ebigawa / shared trunk #7 | 已apply；只删[139.98762,35.6851]，两own共享表示一致 | 既有12/12；后续affected1/1；失败snapshot-removal试验已全退回 | candidate20/20采集；parent关键p15与旧原图对照 | 共享batch Ebigawa matched ON/OFF已看 | 不是全20对逐张验收；既有Minami/Shio尾段/共享安排保留，不新造共轨物理关系。 | [report](../keiyo2-ebigawa-proposal-20261018/repair-result.md) | repair-keiyo-midcurve.mjs及既有模块 |
| 京叶3 own west fork #22..34 | 已apply；定向own链替换；保留lower fork/东臂/尾段 | focused2/2；provenance affected1/1 | candidate18/18采集；parent重点3/4/5/6/17及basemap4/5 | 空白首帧未计；重绑后matched OFF/ON已看 | 非全18对survey；自有参考不是独立双轨中轴，physical fork39/display48须分开。 | [report](../keiyo3-fork-proposal-20261018/repair-result.md) | 同既有Keiyo midcurve/Shio单一路径 |
| 山手 / 品川 transverse connector | 已apply；first display+004095 own alias→[139.73845609051148,35.628135] | 原7/8；null-vs-undefined修正后仅失败upgrade1/1过，其它7沿用 | baseline8/8+candidate8/8；原图0/1；imagery仅2/19 | 品川+大崎共享batch matched ON/OFF已看 | same chainage only；whole-platform longitudinal centre未证；JR当前1/3 vs旧OSM ref2标签差异须保留。 | [report](../yamanote-complete/shinagawa-transverse-result.md) | repair-shinagawa-apple-forks-display.mjs |
| 东武伊势崎-2 / 曳舟 own押上支线 | 已apply；display只删C，A/B/D与南弧/B3 cut不变 | 既有Oshiage Node11/11 | baseline/candidate imagery各2/10；限前两视点，原图已审 | 初OFF空白/异镜头未算；后来restored matched ON/OFF完成 | D宽侧差/屋顶hidden rail/完整platform centre未证；不是新alias错误，原N02横边粗糙。 | [report](../tobu-isesaki2-complete/repair-result-20261018.md) | repair-oshiage-display.mjs |
| 总武3 / 中马込 #3 v13..32 | 已apply；own passenger19 interior nodes，guards/物理保留 | Node4/4 | candidate20/20采集；parent候选4..8等选定原图审 | four-repair batch matched ON/OFF已看 | 不等于20对全审或整段侧差关闭；crossing subway/Shinkansen不能定方向。 | [report](../sobu3-complete/nakamagome-repair-result-20261018.md) | repair-sobu-nakamagome-display.mjs |
| IR石川 / 金泽 #3 v1..26 | 已apply；646native控/64396.1m | Node5/5，含RED→GREEN northern guard | 完整13standard pairs+6aerial pairs审；stop+官方站组绑定 | four-repair matched ON/OFF；nativeReview/mainFinalCheck已更新 | 旧withheld报告为history；当前own NW客运continuation可信但非定向双轨中轴、full caps、南118m transition精确survey。 | [report](../ir-ishikawa-complete/production-apply-20261018.json) | repair-ir-kanazawa-display.mjs |
| 城北 / 中小田井 #1 v26..33 | 已apply；own双向passenger pair supports；149native控 | Node5/5，RED→GREEN | 完整candidate13/13pairs26原图已审 | four-repair matched ON/OFF；metadata已更新 | 西侧保留位移、两终端caps、全线侧差仍开；无nearest Meitetsu snap。 | [report](../jr-tokai-johoku-complete/production-apply-20261018.json) | repair-johoku-nakaotai-display.mjs |
| 宫津 #9 与谢野 own shallow dip | 已apply；后续#15 authority保留#9逐点一致 | 初3/3+changed-physical guard1/1；后续同文件4/4 | 完整candidate32/32pairs64原图已审 | four-repair matched ON/OFF已看 | 其它站代表点/caps/whole line未证；实施JSON旧candidate-only非现态。 | [report](../miyazu-complete/interval-9-production-apply-20261018.json) | repair-miyazu-yosano-display.mjs |
| 宫津 #15 own v3..28 | 已apply；同一authority扩展，保留#9 | 既有focused4/4 | 完整11/11pairs22原图已审 | 10-19 three-repair-final matched ON/OFF已看 | 旧apply JSON mainInterval15=pending被后续Main报告取代；西段/tunnel/两站centres及#6北臂仍开。 | [report](../miyazu-complete/interval-15-production-apply-20261018.json) | 同一Miyazu authority，非第二pipeline |
| 夷隅 #10 久我原→総元 | 已apply；own curve/bridge reference | focused3/3 | 完整candidate8/8pairs16原图已审 | 10-19 final matched ON/OFF，ordinary interval ink实际可见 | 保留substitute_bus/service/exclusion；partsByRegion continuous stroke缺失不代表Main普通站间不渲染，更不代表当前铁路运营。 | [report](../isumi-complete/production-apply-20261018.json) | repair-isumi-kurohara-display.mjs |
| 北信浓 #0 only旧v69短阶 | 已apply；v68及其它点不变；665native控 | focused1/1 meaningful RED→GREEN | 完整26/26pairs52原图+旧p14 pair审 | 10-19 final matched ON/OFF已看 | 宽东偏/熊坂弧/hidden tunnel/站台caps保留；旧apply JSON locked/pixels pending已被后续Main关闭。 | [report](../kita-shinano-complete/production-apply-20261018.json) | repair-kita-shinano-step-display.mjs |
| 渡良濑 #8 花轮 B组旧v5 | 已apply；只删[139.30941,36.52174]；1032native控 | focused1/1 RED→GREEN | 完整4z17 pairs+同镜头1z19 pair，10原图审 | 同镜头ON/OFF已看；chunk精确candidate | A组v2/v3微肩未改；宽偏、站台双帽/纵向中心未证。 | [report](../watarase-keikoku-complete/hanawa-step-native-review-20261019.md) | repair-watarase-hanawa-step-display.mjs |
| 北松江 #6 高之宫 三点阶梯 | 已apply；只删v15/17/19；first545控 | focused1/1 RED→GREEN | 完整5z17 pairs+exact同镜头1z19 pair，12原图审 | 同镜头ON/OFF已看；first545/second315共享端去重证实 | 其它肩/宽侧偏未证；self-follow source后缀−3.157196431997794m，target150→0不变。 | [report](../ichibata-kitamatsue-complete/interval-6-native-review-20261019.md) | repair-ichibata-kitamatsue-display.mjs |

## 后来的Main证据：覆盖早期pending而非删除历史

- [main-repair-batch-20261018.md](../main-repair-batch-20261018.md)
- [four-repair-main-batch-20261018.md](../four-repair-main-batch-20261018.md)
- [three-applied-repairs-main-batch-20261018.md](../three-applied-repairs-main-batch-20261018.md)
- [three-repair-main-final-20261019.md](../three-repair-main-final-20261019.md)

- Den/Keiyo/Yamanote/Hikifune共享batch：Hikifune最初OFF空白/后来不同camera被明确拒绝，后来`main-restored-pair-20261018/`实际同镜头ON/OFF完成；不能继续把该窄case写成未完成，也不能把旧失败截图算通过。
- Sobu/IR/Johoku/Miyazu#9：four-repair batch完成，相关`production-apply`/`nativeReview.mainFinalCheck`已写bounded composition observed。
- Miyazu#15/Isumi/KitaShinano：`three-applied-repairs-main-batch`只证明build/resource，并在当时明确locked/pixels pending。**2026-10-19 final报告**才关闭三项实际Main像素待办。旧apply JSON仍有pending字面值，不应按顶层字符串倒退状态。
- 北松江parts326记录减11共享端=315控制；IR chunk647减1共享端=646；宫津#9旧chunk1586减17共享端=1569。记录数/唯一控制数不能误报新点、漏点或重复渲染错误。宫津#15后candidate/native1568为后来的不同修复状态，不能覆盖历史#9 receipt的原值。



## 未应用／被否决／必须继续的具体位置

- 宫福#0：候选出现离轨肩部和宫村东侧问题，已否决；#8 own25控制候选在中段隧道与Apple自身轨带不符，短窗口又会形成新钩，未apply；#12福知山完整平台端点遮挡，不以旧端点或stop_position冒充中心。
- 北松江#11布崎：真实浅S保留；窄16..24替换会产生24.37°接头，否决。相邻#12十二对已看，官方单面站台照片/示意图已保留，但无地理可定位的完整caps/中心。#6其它肩部和持续侧偏仍开放。
- 三岐#13西野尻：自身客运6way链已确定，OSM投影却朝可见偏移反方向；z19 p1/3/5表明v9..12仍偏、后段穿蓝并侧差反转，站点v0遮挡。固定v0/v9窄窗口不能成立，不创建authority/candidate。
- 三陆#1：1.404m短边逐点来自ownN02 feature21711；own OSM短边同KSJ2来源，非独立判错证据。保留现状；后续若继续只补准确z19中心[141.960545,39.628405]附近自身轨道证据，不因为角度候选删点。
- Manyo新凑港：既有V4/V5已接受23对范围保留；当前输入精确相等，但本轮未找回其exact namedplan。不能从旧25视点推断当前缺2或伪造新复核。
- 用户点名的南北线、丸之内线、千代田线偏移，以及offset/断点/接缝/误连接仍须按自身具体范围完成；旧候选不是一键修复许可。见 [用户偏移记录](../user-offset-candidates-20261016.md)。
- 下面每条线路尚未看的图、平台caps与侧偏分别保留；“未确证假V”不表示无需后续检查。

## 排序范围及早期工作 #2–44

固定输入为 `ios/refactor-parallel/alignment-passenger-local-recheck-20261010.json`：唯一lineID首次出现，ordinal=索引+2，共658条、9580区间，编号2至659。2026-10-19与当前JP包核对ID集合无差异。队列不是线路新主键，区间序号也不是稳定实体身份。

| Ordinal | Exact lineID | 已做/应用状态 | 文档证据（相对BASE） | 未完成/边界 |
|---:|---|---|---|---|
| 2 | `jp-西日本旅客鉄道-木次線` | 既有局部修复保留；本次无新apply | results.md开头；../README.md木次条目 | switchback、三井野原有界曲线修复保留；森林/坡道完整曲线独立支持不足。具体最初apply receipt此盘点未定位，不能新增全线accept。 |
| 3 | `jp-えちごトキめき鉄道-妙高はねうまライン` | 仅完整基线/当前v5复核 | [results.md](../results.md)：Myoko current-v5完成段 | 9区间120视点已记录人工复核及Main南中北/二本木/两端。无新源修复；妙高高原/直江津独立平台中心、遮挡精度开放。旧v4的19视点已被新v5替代。 |
| 4 | `jp-九州旅客鉄道-肥薩線` | 日期策略与既有范围复查；非新几何apply | results.md开头及Hisatsu七日期repeat段；[continuation-handoff-20261015.md](../continuation-handoff-20261015.md) | 沿用时间规则，七实际日期切换记录；南段初始grid不计pass。不得据此声称全线平台/当前精确运营或新几何修复完成。 |
| 5 | `jp-九州旅客鉄道-豊肥線` | 仅完整基线 | [results.md](../results.md)：Hohi full current-render manual coverage | 36区间476新v5视点/1428面板记录全阅，Main俯瞰/立野折返/熊本大分。无因站框不透明而修改；精确平台中点/隐线唯一性WARNING。旧v4失效不可复用作v5。 |
| 6 | `jp-四国旅客鉄道-土讃線` | 确证局部APPLIED+Main AFTER | [results.md](../results.md)：Dosan final applied-data AFTER；dosan-station-candidates/ | 新改spur与坪尻display站中心/ownership seam修复；4受改区间77新视点231面板及Main邻接范围。长线655基线未改处复用；工程/完整平台精度仍限。Xcode exit75不能写成新编译成功。 |
| 7 | `jp-東日本旅客鉄道-上越線-p1` | 仅本own记录基线；关联Gala另有apply | [results.md](../results.md)：Joetsu fullgroup；joetsu-gala-station-candidate/ | 整组39区间600视点包括p1一段23视点；不把Gala另一lineID的端点修复算成本p1已修。隧道/逐平台WARNING。 |
| 8 | `jp-東日本旅客鉄道-上越線-p2` | 仅本own记录基线；关联Gala另有apply | [results.md](../results.md)：Joetsu fullgroup；joetsu-gala-station-candidate/ | p2三段66视点纳入整组实际覆盖；不能把Gala或base线的局部结果自动赋此lineID。地下/平台精度仍开放。 |
| 9 | `jp-東日本旅客鉄道-篠ノ井線` | 确证局部APPLIED；后续松本仅关联线改动 | [results.md](../results.md) Shinonoi/Obasute；matsumoto-direction-review-20261013/；[../README.md](../../README.md) | 姨舍北臂/代表分岔display已apply及Main/受改44视点。松本后来实际修的是JR东大糸31/alias，篠ノ井自身保持。地下/尖轨/自身平台精度WARNING。 |
| 10 | `jp-西日本旅客鉄道-小野田線-2` | 确证局部APPLIED；相关base另修 | [results.md](../results.md)：Suzumeda follow FINAL / Onoda westerncurve FINAL | 小野田-2雀田错误follow移除已apply；西base曲线是关联record，保留两owner界限。整组10区间55基线及changed AFTER范围记录；居能自有平台唯一归属仍WARNING。 |
| 11 | `jp-小田急箱根-鉄道線` | 确证局部APPLIED+Main | results.md开头Gora；../README.md箱根 | 山崎/大平台真折返既有修复保留；强罗display终点已修，interval9四视点AFTER及Main全段/整线/成员卡。缆车独立，不能等同所有平台或测绘中心。 |
| 12 | `jp-一般社団法人札幌市交通事業振興公社-山鼻西線` | 仅完整关联组基线 | [results.md](../results.md)：札幌電車关联整组完整复查 | 四法律记录24区间64视点192面板及Main已记录；无札幌几何修改。北侧4–7m/东南6–10m差异来源不足，平台/独立轨道中心未证。 |
| 13 | `jp-万葉線-高岡軌道線` | 确证V5 APPLIED+交付 | [results.md](../results.md) Manyo V5 final；manyo-complete-display-candidate-v5/ | 高冈及关联新凑组候选旧V1–V4有明确拒绝；最终V5九受改High区间与精确复用、三Inspector及Main7对交付。行车方向平台身份/测绘精度WARNING，不将旧拒绝候选当正式。 |
| 14 | `jp-九州旅客鉄道-唐津線` | 确证西唐津局部APPLIED+交付 | [results.md](../results.md) KaratsuWestfinalaccepted/applied；karatsu-nishi-display-candidate/ | interval0 own西平台修复、native693/42502.5m；8视点及Main终点/咽喉/完整区间。其余11区间复用；久保田多线自有平台分配、地下/精度WARNING。 |
| 15 | `jp-京浜急行電鉄-空港線` | 确证V5 formal APPLIED；历史README冲突已注明 | [results.md](../results.md) ordinal15 V5 formal repair；keikyu-airport-complete-display-candidate-v5/ | 6区间三Inspector27视点各+Main7站/全线，六display dots/own glyph accepted。V5目录README仍写V2/V3 candidate-only，属陈旧标题/状态；以明确较后formal apply记录为历史证据。最新全app交付receipt此盘点未补查；地下测绘不证明。 |
| 16 | `jp-伊予鉄道-城南線` | 确证六线组V3 APPLIED+交付 | [results.md](../results.md) ordinal16 formally accepted/applied/delivered；[jounan-group-display-candidate-v3/formal-delivery.json](../jounan-group-display-candidate-v3/formal-delivery.json) | 29区间71视点各/fresh30+复用41及Main29段/60面板；Minamihoribata literaljunction/Han29.8m lead，旧V1/V2失败保留。完整测绘或全方向平台不扩称。 |
| 17 | `jp-名古屋市-1号線東山線` | 仅完整基线 | [results.md](../results.md) ordinal17 COMPLETE manualdisplay review | 21区间90视点各/三套及Main21区间+全线44面板；无确证owning修复。地下蓝guide不是隧道测量，藤丘/高畑纵向平台中心WARNING。 |
| 18 | `jp-名古屋鉄道-津島線` | 确证组合V2 APPLIED+交付 | [results.md](../results.md)：accepted V2 formal apply；tsushima-combined-candidate-v2/ | 津岛7段与名古屋本线关联16..20（后来扩8Main段）有界修复；V1本线support顺序被拒，V2生产accepted-all-three-main，shipped控制顺序回归。精确客运框/测绘非全国验收。 |
| 19 | `jp-四国旅客鉄道-予土線` | 候选/拒绝；未证实APPLIED，其他聊天后续UNKNOWN | [yodo-complete/repair-handoff-mainline.md](../yodo-complete/repair-handoff-mainline.md)；repair-handoff-regional.md；[results.md](../results.md) Yodo rejection | V1 native拒绝未apply；全19段/20站与Nakamura/Yosan邻接范围扩大，最小29/30段guard仍待裁决。2026-10-14safe-stop为candidate only；不能冒认独立聊天之后结果。 |
| 20 | `jp-土佐くろしお鉄道-阿佐線` | 确证V4 formal交付 | [results.md](../results.md) 2026-10-14 Asa V4 formal delivery；asa-complete/ | 20段各3Inspector153whole+9detail及Main20whole+9detail，五站补充完成。物理/里程保留；本盘点不重新推断全部平台或测绘精度。 |
| 21 | `jp-埼玉新都市交通-伊奈線` | 确证APPLIED+交付 | [results.md](../results.md) Ina ordinal21 applied/delivered | 12display区间+13aliases，三Inspector全线V1及端点V2重采、Main。大宫为reference-assisted occlusion，非Apple直接抽取；内宿完整frame证据另记。旧失败prototype历史保留。 |
| 22 | `jp-富山地方鉄道-富山港線` | 确证APPLIED+交付；13平台框仍待 | [toyama-port-complete/review-progress.json](../toyama-port-complete/review-progress.json)；[results.md](../results.md) Toyama Port corridor delivery | 14段走廊，V3竞轮wholeframe细修及三Inspector/Main；岩濑浜/竞轮两frame已验，另13aliases仅法向投影/旧chainage，不可称13wholeframes已accept。 |
| 23 | `jp-広島電鉄-宇品線` | 仅完整基线，repair required | [ujina-complete/complete-analysis.md](../ujina-complete/complete-analysis.md)；[results.md](../results.md) ordinal23 | 19段三Inspector44各、Main19段、20站detail；南町六丁目主/皆实显示gap及dot/frame缺陷、终点遮挡未修。关联皆实6段并未被此基线等同完成。 |
| 24 | `jp-東京地下鉄-11号線半蔵門線` | 本轮仅完整基线；既有押上alias保留 | [hanzomon-complete/complete-analysis.md](../hanzomon-complete/complete-analysis.md)；[results.md](../results.md) ordinal24 | 13段67各、三Inspector及Main/候选Main13+2局部；九段下阶梯、河底示意差异、14平台框开放。押上003526既有alias非新修复/不可借邻浅草或京成框。 |
| 25 | `jp-東京地下鉄-2号線日比谷線` | 仅完整基线 | [hibiya-complete/complete-analysis.md](../hibiya-complete/complete-analysis.md)；[results.md](../results.md) ordinal25 | 21段89各/267合成；Main23对46帧；七候选及22平台框开放。误采其他线路102/70视点排除。无本轮生产修复。 |
| 26 | `jp-東京地下鉄-4号線丸ノ内線` | 本轮仅完整基线；既有本乡alias保留 | [marunouchi-complete/complete-analysis.md](../marunouchi-complete/complete-analysis.md)；[continuation-handoff-20261015.md](../continuation-handoff-20261015.md) | 主24+支3段121各/363合成、Main28对；中野45°斜切、新宿S、国会等待修。既有本乡三丁目003546及3/4覆盖保留；不可称整个owner无历史修复。 |
| 27 | `jp-東京都-6号線三田線` | 本轮仅完整基线；既有Hakusan/Mita修复保留 | [mita-complete/complete-analysis.md](../mita-complete/complete-analysis.md)；[results.md](../results.md) ordinal27；[continuation-handoff-20261015.md](../continuation-handoff-20261015.md) | 26段115各/345合成、Main26有效对52帧；旧handoff尚缺部分审阅已被较后complete-analysis supersede。多处Transit轮廓/27平台框开放；own authority为repair-mita-apple-display，不是被否定OSM候选。 |
| 28 | `jp-東日本旅客鉄道-両毛線` | 仅完整基线 | [ryomo-complete/complete-analysis.md](../ryomo-complete/complete-analysis.md)；[results.md](../results.md) ordinal28 | 18段268各/804合成，Main18对36帧；伊势崎JR/东武方向、栃木/岩舟、前桥利根川待研究，19平台框开放；无production repair。 |
| 29 | `jp-東日本旅客鉄道-大糸線` | 整线本轮基线；松本31另有确证APPLIED | [oito-complete/complete-analysis.md](../oito-complete/complete-analysis.md)；[results.md](../results.md) Matsumoto accepted/applied | 32段247各/741合成、Main32对；松本31/002506有界尾段修复已apply并实际native/Main，非其他31段都已修。青木湖/信浓大町/梓川等候选及33平台框开放。 |
| 30 | `jp-東日本旅客鉄道-東北線-2` | 仅完整基线 | [tohoku-2-complete/complete-analysis.md](../tohoku-2-complete/complete-analysis.md)；[results.md](../results.md) ordinal30 | 赤羽→东京12段/13站，三套165视点，Main12对；赤羽短钩/局部偏移及共享站场own锚点、13平台框开放。无本轮生产改动。 |
| 31 | `jp-東日本旅客鉄道-東海道線` | 整线本轮基线；品川既有bounded修复保留 | [tokaido-complete/complete-analysis.md](../tokaido-complete/complete-analysis.md)；[results.md](../results.md) ordinal31/品川段 | 32段348各/1044合成及Main32对；品川真实客运走廊/分岔已有apply，不是这次整线全修。相模川/平塚–二宫/海岸隧道候选、33平台框开放。 |
| 32 | `jp-相模鉄道-相鉄本線` | 确证横滨局部APPLIED+Main；全线未关闭 | [sotetsu-main-complete/platform-proof-20261018/repair-result.md](../sotetsu-main-complete/platform-proof-20261018/repair-result.md)；retained-station-seam-review/ | 17段历史93各；后续横滨删除B保留A/C、lane0前300m，7baseline+7candidate及Main，own-platform证据优于早期standard-only拒绝。南部偏移/平台、西谷/二俣川分支、大和/海老名组合疑问不由局部apply一并关闭。 |
| 33 | `jp-西日本旅客鉄道-北陸線-p1` | 鳩原东弧及上／下行方向修复已APPLIED，局部Main完成 | [hokuriku-p1-complete/sharp-corner-repair-20261018/README.md](../hokuriku-p1-complete/sharp-corner-repair-20261018/README.md)；source-review.md | 后来明确apply取代observations的旧candidate-only状态；34配对已审、Node6/6与Swift方向1/1、Main全景/交叉近景已记录；南部回环/新疋田偏移和两站caps仍未证。 |
| 34 | `jp-西日本旅客鉄道-大糸線` | 确证糸鱼川末端局部APPLIED+Main | [oito-west-complete/platform-proof-20261018/repair-result.md](../oito-west-complete/platform-proof-20261018/repair-result.md)；observations.md | 8段133基线；interval7 guard32后own bay tail与display station001666修复，29baseline+29candidate、Main。东cap遮挡为reference-assisted，不是完整hidden平台抽取；小滝等其余山地shape差异未修。 |
| 35 | `jp-京阪電気鉄道-京津線` | 既有有界修复保留+当前证据补齐 | [keishin-current-complete/README.md](../keishin-current-complete/README.md)；scope.md；results.md开头 | 大谷/上荣町旧警告被既有修复/历史Main supersede；当前#4/5补11视点全看，#0–3旧20只在geometry可复用范围。地下平台中心/新Main组合本README未验收，不能以31组合视点称全线平台完成。 |
| 36 | `jp-京成電鉄-押上線` | 仅保留基线审阅 | [oshiage-complete/README.md](../oshiage-complete/README.md)；observations.md | 5段25旧视点全部pairs及6站pairs历史审阅、当前own identity复用；荒川桥、立石/曳舟候选开放，6平台框/Main lane/dot未验。不把Tobu另一owner#44修复算Keisei本线完成。 |
| 37 | `jp-東京地下鉄-13号線副都心線` | 仅保留基线审阅 | [fukutoshin-complete/README.md](../fukutoshin-complete/README.md)；retained-review/ | 10段51视角/102面板及10原对历史审阅；池袋#6、北参道–新宿三丁目#2候选身份不足；平台/Main组合未验。不借JR站框。 |
| 38 | `jp-東急電鉄-東横線` | 证据组合补齐；无明确新repair | [toyoko-complete/README.md](../toyoko-complete/README.md)；observations.md | 20段102视点=96保留+妙莲寺–白乐#16新6（不同旧plan不能冒充5）；未发现粗大hook/gap修复证据。own平台框/Main多线站珠组合未验。 |
| 39 | `jp-東急電鉄-田園都市線` | 确证新町#3局部APPLIED+Main batch | [denentoshi-complete/curve3-candidate-status.md](../denentoshi-complete/curve3-candidate-status.md)；[main-repair-batch-20261018.md](../main-repair-batch-20261018.md) | 26段历史120+缺段新13证据，不把capture完成当全阅；#3 falseV已apply/14candidate capture，父只记录部分originals局部审图及Main。R315/750与方向row对应不足明确保留；二子玉川/中央林间/高津–沟之口开放。 |
| 40 | `jp-東日本旅客鉄道-京葉線-2` | 确证海老川局部APPLIED+Main batch | [keiyo2-ebigawa-proposal-20261018/repair-result.md](../keiyo2-ebigawa-proposal-20261018/repair-result.md)；[main-repair-batch-20261018.md](../main-repair-batch-20261018.md) | 删own1436589310两guard间单点；共享trunk7同步同删，物理/站/km/盐滨/南船桥尾保留。20candidate capture，父局部original对照/Main；不是20对全线像素accept。 |
| 41 | `jp-東日本旅客鉄道-京葉線-3` | 确证西臂局部APPLIED+Main batch | [keiyo3-fork-proposal-20261018/repair-result.md](../keiyo3-fork-proposal-20261018/repair-result.md)；[main-repair-batch-20261018.md](../main-repair-batch-20261018.md) | own22..34按明确西向route替换，东臂/lowerfork/盐滨tails保留，96/5906.9native。18candidate capture而只记录selected originals审阅；平台纵向精度、全线路未关闭。 |
| 42 | `jp-東日本旅客鉄道-山手線` | 确证品川局部APPLIED+Main；其他open | [yamanote-complete/shinagawa-transverse-result.md](../yamanote-complete/shinagawa-transverse-result.md)；komagome-own-approach-research-20261018.md；[main-repair-batch-20261018.md](../main-repair-batch-20261018.md) | 品川仅首display点+004095 alias去7.1399m横接，后续全保留；8standard+2imagery受限审图/Main。整平台纵向中点未证；驹込own approach研究不是已apply。 |
| 43 | `jp-東日本旅客鉄道-総武線-3` | 确证中马込局部APPLIED+最终Main | [sobu3-complete/nakamagome-repair-result-20261018.md](../sobu3-complete/nakamagome-repair-result-20261018.md)；[four-repair-main-batch-20261018.md](../four-repair-main-batch-20261018.md) | interval3原13..32内部19个own365183512v18节点，原guards/物理保留；347/24425native，4focused历史证据。20capture但部分原图实际看，后续Main supersede earlier pending；其余地下/平台非全验。 |
| 44 | `jp-東武鉄道-伊勢崎線-2` | 确证曳舟局部APPLIED+补足matched Main | [tobu-isesaki2-complete/repair-result-20261018.md](../tobu-isesaki2-complete/repair-result-20261018.md)；[main-repair-batch-20261018.md](../main-repair-batch-20261018.md) | 仅删crosswiseC，保留A/B/D与余点，自有押上方向不同浅草；35/1038.4native。只2/10baseline+2/10candidate imagery局部审图；早期Main OFF空白/错相机不算pass，后续restored matched pair已记录。 |

### 历史冲突与保护边界

- #15 V5 README仍是旧candidate标题/正文，但results.md有较后明确V5 formal修复；#19 safe-stop只确认候选/拒绝，其他chat后续不冒认。#27旧handoff审阅未完成，被较后complete-analysis接续完成；#32 results.md停在未关闭基线，横滨局部apply由较后own-platform result证明。#34 baseline原无override被后续糸鱼川own-platform bounded修复替代。#39/40/41/42/43/44早期Main pending或失败由各later batch实际记录局部supersede，非全线验收。
- #7/#8 Joetsu directional IDs不能继承Gala另一ID的已应用结果；#9不能继承大糸松本站尾的几何修改；#10 branch跟随修复与关联base西曲线区分；#36 Keisei押上不能继承#44 Tobu曳舟修复。
- Data overhaul可保留：各既有单owner、frozen old/new几何、canonical不变约束、parts/follows/family/hub等实际依赖与逐scope原证据。不得由本库存重置已apply修复、重新采用被拒候选或抹掉未证站台。
- 本库存未建立全43条当前source版本一致性或最终bundled一致性；不把历史图重新验收，后续只因具体dependency变更核对受影响范围。其余队列45–87由父既有summaries负责，88+与全国658完成状态不在本库存。

早期表的证据路径均相对本目录的上一层（ordered-continuation）；这是文档时序盘点，未重新核对这43条当前全部bundled资源或重看历史PNG。#33的旧candidate-only观察明确由较后sharp-corner-repair正式记录取代。


## 续检 #45–87：逐线范围与未完成项

表中“旧图本轮未看”不抹去早期审阅；明确当前交接可据何种证据继续。receipt可复用与像素已审分列在文字中。

| 队号／精确lineID | 已有工作／实际审阅范围 | 未完成或修复边界 | 证据目录 |
|---|---|---|---|
| 45 `jp-豊橋鉄道-東田本線` | 新28对全看 | 未确证假V；站台中心待证 | [toyohashi-complete](../toyohashi-complete/) |
| 46 `jp-長崎電気軌道-本線` | 新53对+既有2对，全新图已看 | 真实街道弯保留；持续偏移待本线证据 | [nagasaki-complete](../nagasaki-complete/) |
| 47 `jp-IRいしかわ鉄道-IRいしかわ鉄道線` | 候选13标准+6影像；局部Main完成 | 金泽#3修复已应用；整线/平台精确中心未验收 | [ir-ishikawa-complete](../ir-ishikawa-complete/) |
| 48 `jp-JR東海交通事業-城北線` | 既有40对+候选13；局部Main完成 | 中小田井#1已应用；西侧偏移及平台待证 | [jr-tokai-johoku-complete](../jr-tokai-johoku-complete/) |
| 49 `jp-WILLER　TRAINS-宮津線` | #9候选32、#15候选11；Main完成 | 两次修复复用同一authority；其它区间未据此全部验收 | [miyazu-complete](../miyazu-complete/) |
| 50 `jp-WILLER　TRAINS-宮福線` | 新14对；#8候选11对；#12站台取证 | 未apply；#0已否决，#8像素不合，#12平台caps遮挡 | [miyafuku-complete](../miyafuku-complete/) |
| 51 `jp-あいの風とやま鉄道-あいの風とやま鉄道線` | 15/317对有界查看 | 302对未看，整线未完成 | [ai-no-kaze-complete](../ai-no-kaze-complete/) |
| 52 `jp-いすみ鉄道-いすみ線` | 新22对全看；#10候选8+Main | #10已应用；substitute_bus保留，整线未接受 | [isumi-complete](../isumi-complete/) |
| 53 `jp-えちごトキめき鉄道-日本海ひすいライン` | 10/187对 | 177对未看；区分在来线、大糸及新干线 | [nihonkai-hisui-complete](../nihonkai-hisui-complete/) |
| 54 `jp-えちごトキめき鉄道-日本海ひすいライン-p1` | 7/17对 | 10对未看；保留内陆真实走向 | [nihonkai-hisui-p1-complete](../nihonkai-hisui-p1-complete/) |
| 55 `jp-えちぜん鉄道-三国芦原線` | 既有95对+新8对；新图全看 | 旧95本轮未复看；福井口真实转弯保留 | [mikuni-awara-complete](../mikuni-awara-complete/) |
| 56 `jp-えちぜん鉄道-勝山永平寺線` | 既有101对+新11对；新图全看 | #6 own弯可定位，站台caps/#7 chainage未证；无apply | [katsuyama-eiheiji-complete](../katsuyama-eiheiji-complete/) |
| 57 `jp-くま川鉄道-湯前線` | 既有79对+新13对；新图全看 | partial_substitute_bus及[[10,13,2]]保留；无apply | [kumagawa-yunomae-complete](../kumagawa-yunomae-complete/) |
| 58 `jp-こうべ未来都市機構-摩耶ケーブル線` | 4对全看 | 无确证假V；平台端点未测 | [maya-cable-complete](../maya-cable-complete/) |
| 59 `jp-しなの鉄道-しなの鉄道線` | 7/214对 | 207对未看 | [shinano-railway-complete](../shinano-railway-complete/) |
| 60 `jp-しなの鉄道-北しなの線` | 既有5/118有界查看；#0候选26+Main | #0单点横跳已修；其它旧图/平台仍未全审 | [kita-shinano-complete](../kita-shinano-complete/) |
| 61 `jp-とさでん交通-伊野線` | 新38对全看 | 河流真实弯保留；无source-ready新修复 | [tosaden-ino-complete](../tosaden-ino-complete/) |
| 62 `jp-とさでん交通-後免線` | 新42对全看 | 持续偏移与#31终端chainage未证 | [tosaden-gomen-complete](../tosaden-gomen-complete/) |
| 63 `jp-とさでん交通-桟橋線` | 全部17对已看 | 播磨屋桥自身南臂；无确证假V，caps未证 | [tosaden-sanbashi-complete](../tosaden-sanbashi-complete/) |
| 64 `jp-とさでん交通-駅前線` | 全部6对已看 | 南北本线与JR/东西电车分开；caps未证 | [tosaden-ekimae-complete](../tosaden-ekimae-complete/) |
| 65 `jp-のと鉄道-七尾線` | 前3区间40/105对 | 65对未看 | [noto-nanao-complete](../noto-nanao-complete/) |
| 66 `jp-ひたちなか海浜鉄道-湊線` | 端点#0/#9共7/53对 | 46对未看；胜田自身乘降面不能用共享JR站ID代替 | [hitachinaka-minato-complete](../hitachinaka-minato-complete/) |
| 67 `jp-ゆりかもめ-東京臨海新交通臨海線` | 既有58对+新8对；新图全看 | 旧58本轮未看，包括Rainbow13对；真实复合弯保留 | [yurikamome-complete](../yurikamome-complete/) |
| 68 `jp-わたらせ渓谷鐵道-わたらせ渓谷線` | 既有109对+新40对全看；#8候选4+detail1+Main | 花轮B组已apply；A组、#0/#5/#6/#14偏移仍开放 | [watarase-keikoku-complete](../watarase-keikoku-complete/) |
| 69 `jp-アイジーアールいわて銀河鉄道-いわて銀河鉄道線` | 两端完整#0/#16共23/260对 | 237对未看；实际顺序目时→盛冈 | [igr-iwate-ginga-complete](../igr-iwate-ginga-complete/) |
| 70 `jp-アルピコ交通-上高地線` | 既有56对+新#1四对全看 | 旧56本轮未重复看；无确证假V，caps未证 | [alpico-kamikochi-complete](../alpico-kamikochi-complete/) |
| 71 `jp-ハピラインふくい-ハピラインふくい線` | 完整#0敦贺→南今庄49/268对 | 219对未看；山内画线不等于隧道测量 | [hapi-fukui-complete](../hapi-fukui-complete/) |
| 72 `jp-ラクテンチ-別府ラクテンチケーブル線` | 2对全看 | 自身缆车基图轨道未独立分辨，不借邻近游乐场环线 | [beppu-rakutenchi-cable-complete](../beppu-rakutenchi-cable-complete/) |
| 73 `jp-一畑電車-北松江線` | 既有75对+新55对全看；#6候选6对+Main；#12十二对 | #6三点阶梯已apply；#11窄替换否决，平台caps待证；旧75中#12十二对已看，其余63对本轮未看 | [ichibata-kitamatsue-complete](../ichibata-kitamatsue-complete/) |
| 74 `jp-一畑電車-大社線` | 全部30对全看 | 川迹自身西支明确；终段侧偏与终端caps待证 | [ichibata-taisha-complete](../ichibata-taisha-complete/) |
| 75 `jp-一般社団法人札幌市交通事業振興公社-1条線` | 全部9对全看 | 西15丁目真实街弯保留；其它支线/Main组合/平台未接受 | [sapporo-ichijo-complete](../sapporo-ichijo-complete/) |
| 76 `jp-一般社団法人札幌市交通事業振興公社-山鼻線` | 全部28对全看 | 真实街弯保留；中央图书馆前端点不等于车库连接验收 | [sapporo-yamahana-complete](../sapporo-yamahana-complete/) |
| 77 `jp-一般社団法人札幌市交通事業振興公社-都心線` | 旧#0两对+新#1两对，全部4对已看 | 旧#1 missing named plan未接受，已只补#1；caps/Main未接受 | [sapporo-toshin-complete](../sapporo-toshin-complete/) |
| 78 `jp-一般財団法人青函トンネル記念館-青函トンネル竜飛斜坑線` | 全部2对全看 | 自身地下斜坑/平台未独立可见，不向北海道新干线吸附 | [seikan-tappi-cable-complete](../seikan-tappi-cable-complete/) |
| 79 `jp-万葉線-新湊港線` | 先前V4/V5已接受23对范围；当前显示/8alias与旧输入精确相等 | 本次未恢复exact namedplan；不伪造新计划复核、缺失数或补拍请求 | [manyo-shinminato-complete](../manyo-shinminato-complete/) |
| 80 `jp-三岐鉄道-三岐線` | 旧82/98可用；缺16对已补且全看；#13 z19三对全看 | 6way自身客运链明确；OSM方向反证，v0/v9边界不闭合；无候选/apply | [sangi-sangi-complete](../sangi-sangi-complete/) |
| 81 `jp-三岐鉄道-北勢線` | 旧71/75可用；缺#11四对已补且全看 | 自身宽S与近铁东侧北上保留；侧偏与caps未证 | [sangi-hokusei-complete](../sangi-hokusei-complete/) |
| 82 `jp-三陸鉄道-リアス線` | 旧135/179可用；缺#1–4共44对补齐全看 | #1短边同N02/OSM KSJ2非独立判错；#2偏移/#4并列蓝线待证 | [sanriku-rias-complete](../sanriku-rias-complete/) |
| 83 `jp-三陸鉄道-北リアス線` | 228/228 receipts可复用；完整#12三对已看 | 225对本轮未看；自身站台caps未证 | [sanriku-kita-rias-complete](../sanriku-kita-rias-complete/) |
| 84 `jp-三陸鉄道-南リアス線` | 118/118 receipts可复用；完整#3八对已看 | 110对本轮未看；桥隧/完整平台未证 | [sanriku-minami-rias-complete](../sanriku-minami-rias-complete/) |
| 85 `jp-上信電鉄-上信線` | 67/124 receipts可复用；#12四对已看；缺57请求已准备未运行 | 其余保留63对未看；#0–7/#19共57视点待采 | [joshin-complete](../joshin-complete/) |
| 86 `jp-上毛電気鉄道-上毛線` | 75/104 receipts可复用；#1三对已看；缺29请求已准备未运行 | 其余保留72对未看；#0/#2/#3/#8/#19–21共29视点待采 | [jomo-complete](../jomo-complete/) |
| 87 `jp-上田電鉄-別所線` | 53/53 receipts可复用；#1三对已看 | 50对未看；自身缓弯保留，东南/南侧偏及caps未证 | [ueda-bessho-complete](../ueda-bessho-complete/) |

## 未进入本轮续检的队列

#88 `jp-丹後海陸交通-天橋立鋼索鉄道`至#659，共572条，尚未在本次续检中建立逐线完成结论。精确ID及顺序直接读固定输入，不复制另一份不断漂移的队列。这里的“未进入”不表示这些线路从未有过历史修复，也不将既有仓库数据记成空白。全国658条未完成，不能以推进到#87表述为已验收86条。

已准备未执行的下一采集：上信57（#0–7/#19），上毛29（#0/#2/#3/#8/#19–21），合计86视点。请求在/private/tmp/jtm-joshin-missing-request.json与jtm-jomo-missing-request.json；持久scope existing-evidence-20261019.json/md记录输入和缺失，scratch丢失时按记录重建当前请求，不照抄失效session。

## 并行工作索引：不要沿用过时统计

中国来源、CRTrainRoute研究和原生正式接入由另一聊天负责，权威报告为[真实车次报告](../../../../../sources/china-real-train-paths-20261018/README.md)。本次读其最新已完成2026-10-19T08:50:40Z的176项重放：固定88公开车次×两模式，Railmap强制停站552/1010几何、507/1010内部连续、14/88完整候选；原仓库756/1010、49/88完整候选。D271为14/14几何、13/14内部连续；D239为6/7几何、5/7内部连续。广州南、沈阳北、攀枝花南边界以及楚雄—丽江仍未补齐。0结构失败与714审阅记录不是路径全部认证。最新攀枝花南原始15边候选和direct identity接入工作不应被当作已正式接入／完成新176重放；其owner因本次文档任务已停止执行。

较早全应用架构工作见[实际接口表](../../../../../../reference/function-interface-map.md)与[架构追踪](../../../../../../reports/integration/function-interface-architecture-2026-10-15.md)。T8已实施／有界验证与T14源码收敛不同：T14报告只确认18文件parse通过，明确聚焦行为检查和Main编译待执行；本次没有重跑，也不将parse当类型检查或行为通过。其它聊天的历史提交/发布授权不转移为本任务授权。

## 重构已经准备了什么、还没做什么

本次交付工作清单、当前interface追踪、稳定身份/几何/provenance/证据的迁移不变量、既有ADR关系、分期实施及代表失败保护样例。详见重构准备文档。

尚未实现ADR0013的P0账本与mint入口，未升级rail.db schema、CompactPackage、Swift/JS读取、display chunks、history、cache keys、DiagnosticRequest或乘车记录schema；未重新铸造ID、改站点、重测公里、归并CN relation或导入NA。未删除原始证据/失败候选/用户代码，未commit/push/publish。重构性能收益尚未测量。
