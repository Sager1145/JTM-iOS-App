# JTM 当前工作区代码审查

> 当日后续状态：下列 16 项已完成修复及独立复审。实际针对性检查、调用链整改与未测量边界见 [修复报告](code-review-fixes-2026-10-11.md)。本文件保留初审时的源码证据和覆盖范围。

2026-10-11。检查对象是当前工作区，包括未提交源码与测试，不限于 HEAD 的差异。采用新安装的 code-review、codebase-design 和 improve-codebase-architecture，并按 iOS 指南与仓库约束复核。本次未改变领域模型，因此 domain-modeling 不触发词汇表或 ADR 写入。实现、调试修复、PR、安装和教学类 skill 不属于本次只读检查。

## 覆盖范围

当前代码清单共 **1,672 个文件**；其中 **1,667 个自有源码、测试和工具文件**获得分级检查，5 个第三方/证据/夹具文件明确排除。另外核对了 14 个工程与配置描述文件。覆盖清单没有遗漏的当前代码路径。

| 检查深度 | 自有代码文件数 |
|---|---:|
| 完整阅读或重点调用链深入阅读 | 157 |
| 结构、风险模式或 Python 语法/导入筛查 | 1,510 |
| 合计 | 1,667 |

[逐文件覆盖清单](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/code-review-2026-10-11-coverage.tsv)。881 个 Python 文件全部通过当前 AST 语法解析；其中 5 个做重点逻辑阅读，其他只筛查语法与导入。RailKit、iOS 与 Web 的深入阅读也仅保证清单列出的路径，不等同于大文件每条语句都已审阅。Grok 4.7 的第一轮达到回合上限，同一确切会话收尾成功；我复核了其唯一确认缺陷，并补看显示网络 builder 的历史标记、裁剪、重定向与输出路径。

逐文件静态筛查不是逐函数正确性证明。清单区分完整阅读、重点调用链阅读、结构/风险模式筛查、语法/导入筛查及排除项。第三方 vendor、备份、原始资料缓存和保存的网页证据不作为自有实现审查；测试夹具按其调用关系检查。JSON/SQLite 数据仅对具体问题查询，未逐条认证全国数据。

## Standards

### S1 P1 Web 求解图把乘客换乘关系当成物理铁路连接

位置：[app-route-solver.js](/Users/sager/Documents/GitHub/JTM-iOS-App/app/public/app-route-solver.js:239)。按乘客站组或同名站分组后，仅凭距离把节点接入 adjacency；`RailNetwork.permitsStationConnectorNode` 排除部分不服务的平行线，但不提供物理道岔证据。默认软机构过滤允许这些连接。

这与 [iOS 永久物理拓扑要求](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/AGENTS.md) 所定义的铁路求解合同不一致；该要求作为跨端产品合同核对，而非声称 ios/AGENTS.md 的目录规则会自动管辖所有 Web 文件。对当前天王寺周边 58 条 rail-sections 和 6 条车站归属的局部查询，真实 connector 许可函数仍生成 JR 与大阪 Metro 之间的边，例如 `135.51591,34.6452 → 135.51602,34.64665`。已执行生产图构建局部复现；没有声称已生成某个完整错误行程。应将 reviewed physical junction 与乘客换乘/显示关系分开消费。

### S2 P3 新渲染源码缺少责任归属

位置：[StrokeJunctionIndex.swift](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Rendering/StrokeJunctionIndex.swift:3)。[source-structure.md](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/docs/source-structure.md:41) 要求新增文件加入责任组。当前责任清单有 333 个唯一条目，主应用与 RailKit 有 334 个 Swift 生产文件，唯一未登记的是该文件。SwiftPM 递归发现它，因此这是责任清单遗漏，不是编译缺源证明。

## Spec 与行为合同

没有提供单一功能 issue/spec；以下结论依据源码明确合同、永久产品要求及真实调用方。每项列出具体触发条件，不以代码气味直接判定 bug。

### B1 P1 国家切换失败后可把旧国家行程保存到新国家

位置：[app-country-session.js](/Users/sager/Documents/GitHub/JTM-iOS-App/app/public/app-country-session.js:129)。切换先改 `activeCountry`、持久化 namespace 和 `TRAIN_STORE_API`，再等待新国家数据。若车站数据请求失败，旧 `trainStore` 未替换，finally 却恢复可操作状态。局部执行生产协调器并注入 HTTP 503，结果为国家 `tw`、目标 `train-store-tw`、行程仍为 `jp-old`、busy/recovery 均为 false。下一次普通编辑便可能写错国家。需要会话准备成功后提交，或失败时恢复/保护整个旧快照。

### B2 P2 旧国家 streaming solve 在切换后继续发布

位置：[app-route-graph.js](/Users/sager/Documents/GitHub/JTM-iOS-App/app/public/app-route-graph.js:848)。reset 增加 generation 并清空缓存，但正在 yield 的 streaming solve 恢复时没有检查会话归属。局部复现中，JP→TW reset 后缓存为 0，旧 solve 继续后出现 `solver:old-jp-key`，matched routes 又包含旧国家行程。生产 stream/commit/reset 被实际执行；图计算使用两个最小结果代替全国求解。每次异步恢复及发布前都应验证同一会话 token。

### B3 P1 保留的静态站点构建入口依赖已删除文件

位置：[build-static-site.mjs](/Users/sager/Documents/GitHub/JTM-iOS-App/app/scripts/build/build-static-site.mjs:9)。要求 `../../server/datasets.js`，当前该文件与 `app/server/` 均不存在。只导入构建模块即退出 1：`MODULE_NOT_FOUND`，尚未开始任何产物写入。`build:static`、`dev:static` 和总 build 仍引用它；start/dev 也指向不存在的 `server.js`。应把仍需要的资源注册表放到保留的构建/共享 owner，并同步退役入口。

### B4 P1 导入发布之后取消会跳过保存

位置：[ItineraryStore.swift](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Journeys/ItineraryStore.swift:401)。JSON 导入已经 `publishWorkingSet(next)`，随后 await 的分组仍检查任务取消。两个 Cancel 控件没有遵守 `canCancel=false`，可取消此阶段；异常进入 ImportFlow 的取消分支，跳过后面的 `library.save`。大导入在这个窗口取消，已发布的内存变更未保存，且未完成正常分组/索引发布；重新启动会读回旧磁盘快照。源码与 UI 调用链已核对，未进行设备时序复现。提交后的保存义务应由操作本身保证，同时让所有取消入口遵守提交点。

### B5 P2 备份 JSON 与元数据可能来自不同一代

位置：[RideStorage.swift](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Infrastructure/Persistence/RideStorage.swift:123)。替换 JSON 后才替换 sidecar，旧 sidecar 一直存在。两步之间终止或第二步失败时，`recoverableBackup` 仍把两份文件当作有效备份；界面显示旧日期/数量，恢复却读新数据。与“失败保留旧备份”的明确注释不符。应发布完整的一代并保留上一代直到成功；单文件原子写不能保证两个文件的一致性。此项为源码错误路径确认，未模拟进程终止。

### B6 P2 截图导入保存失败仍显示成功

位置：[TransferGuideImport.swift](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Import/TransferGuideImport.swift:328)。丢弃 `library.save(...).value` 的 false，随后无条件进入 imported。实际调用方显示绿色成功标记与 Done，不读取保存错误；用户结束导入后，记录可能仅存在内存。JSON 导入已有本次保存错误显示，截图路径应保留并显示同样的保存结果。已核对调用方，未注入磁盘失败。

### B7 P1 物理区段序号与停站区间序号混用

位置：[MileageMatching.swift](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailApplication/Statistics/MileageMatching.swift:90)。已有时刻表回归支持“水戸、上野两个停站；水戸→日暮里、日暮里→上野两个物理区段”，禁止为了线路边界虚构停站。RiddenRouteStore 把物理区段枚举序号传给统计，而 `isRideSegment` 按停站 index/index+1 读取；第二个物理区段需要不存在的第三个停站，于是被判为未乘坐。里程漏计、缺失后段可能被判完整；播放与服务区段标签也复用这个错误序号。源码、既有合法夹具及跨端调用已核对，未运行原生统计/UI 测试。需要 occurrence-aware 的物理区段到真实停站区间映射。

### B8 P2 服务选区编辑修改错误物理区段

位置：[RouteSectionServiceEditing.swift](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Editor/RouteSectionServiceEditing.swift:58)。停站 A,C 与物理 A→B,B→C 时，编辑 A→C 只修改第一个 section；停站 A,C,E 与四个物理区段时，编辑 C→E 却改到 B→C。违反选区外身份保留合同。与 B7 共用缺失映射这一整改方向，但这是独立的用户数据修改症状。

### B9 P2 方向排除缓存 key 没有包含缓存所依赖的坐标

位置：[RouteSolver.swift](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Routing/RouteSolver.swift:2926)。stamp 包含 metadata 和区段端点代码，却不含 `interval.coordinates`；缓存内容由坐标计算。两个同 metadata、不同中间测量顶点的 RouteNetwork 得到相同 key，第二次 supported solve 会取旧排除点。只有容量淘汰能清除该静态缓存。此项是纯 module 两次调用的确定性缓存依赖缺陷；没有证明发布应用在运行时真的替换过这种快照。key 应覆盖完整几何依赖，或让缓存属于不可变资源快照。

### B10 P2 局部线路修正丢失选区外物理约束，Undo 也无法恢复

位置：[RailwayRouteEditing.swift](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Editor/RailwayRouteEditing.swift:283)。停站 A,C,E，物理链 A→B,B→C,C→D,D→E 时，只修正 C→E 也会先把全部 sections 重建为相邻停站对；找不到单个 A→C section，就丢掉原先 A→B/B→C 的 lineIDs、sectionCodes 和服务身份。只有整车 Undo 才使用完整 originalRouteSections，局部 Undo 仍无法恢复被抹掉的外部源边界。需要在原链上按映射范围 splice；不应先重建全链。

### B11 P3 PNG companion 检查漏报不可解码文件

位置：[rasterize-badge-svgs.swift](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/rasterize-badge-svgs.swift:340)。文件存在但为非图片内容时，existing 非 nil，ImageIO 解码失败使整个 else-if 跳过，既不 stale 也不 failure；最后可能报告匹配。应该把解码或尺寸提取失败归入 stale。只确认这一源码分支，未启动 WebKit 渲染工具。

### B12 P3 视频扫描允许不会前进的帧率

位置：[frames.swift](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/frames.swift:81)。`-30` 是合法 Double 但每轮使 time 变小；对正时长视频，循环条件一直成立。`inf` 使步长为 0。入口应要求 finite 且大于 0。此项为数值/循环条件审查，未启动视频扫描。

### B13 P2 保留的 AFR/Nankai 测试导入已退役模块

位置：[test_reviewed_afr_nankai_evidence.py](/Users/sager/Documents/GitHub/JTM-iOS-App/app/scripts/railway/tests/test_reviewed_afr_nankai_evidence.py:5)。模块顶层调用 `module('tw-afr')` 与 `module('jp-nankai')`，尝试读取已删除的两个 verify 脚本。实际单模块导入得到 `FileNotFoundError`，早于 setUpClass 的 SkipTest；测试无法收集。应按退役政策处理这份专用 helper 测试，或将仍有价值的回归迁到保留的生产/builder interface；不恢复退役流水线。Grok 提供线索，我独立确认实际异常；其初稿关于 spec 返回 None 的解释未采用。

### B14 P2 历史链拆分后的 follow 仍使用旧链距离

位置：[build-display-network.py](/Users/sager/Documents/GitHub/JTM-iOS-App/app/scripts/railway/build-display-network.py:1899)。`_retarget_follow` 改了 canonicalChain，却没有把 canonicalFrom/To 减去新 piece 的 measure_start。旧 canonical 链拆成 `[0,150]` 与 `[150,300]`，follow 引用旧链 150→200 时，当前函数输出新链 1 的 150→200，正确的局部距离应为 0→50。

直接执行该生产 helper 得到 `[[0.0,50.0,'canonical',1,150.0,200.0]]`。Swift 的 `joinedChainCoordinates` 为每条新链从 0 累积距离，MapLineGeometry 把 canonical 距离原样交给 ContinuousStroke，后者 clamp 到新链终点；因此这个支持的拆分输入会采错 canonical 位置。需对目标 piece 同步重基 canonical 距离，兼顾反向 follow。本次确认了 helper 与消费合同的缺陷，未证明当前打包的全国数据必然包含触发该分支的 follow，也未进行像素观测。


## 架构建议

[架构图报告](/private/tmp/architecture-review-jtm-20261011.html) 记录四项有实际缺陷支持的 deepening 候选：记录路径归属映射、国家会话 snapshot、批量变更与本次保存结果、备份代际发布。它们集中 interface 背后的合同，增加 locality 与 leverage；不按文件行数拆分已明确保留完整 owner 的求解器和渲染算法。不新增无实际 adapter 的泛化框架；建议不计入缺陷数量。

## 证据与边界

- 执行了三个轻量诊断：生产国家会话/stream 生命周期隔离、当前天王寺局部连接边查询、静态 builder 仅导入。前两个在内存 sandbox 中，均未修改真实用户存储；没有全国求解/构建。
- Python 另执行了单个测试模块导入、显示网络 retarget helper 的具体距离查询，以及 881 文件 AST 解析。没有执行数据 builder 的 build 函数或自动验证流水线。
- 原生项采用当前源码、调用方与既有测试夹具审查，不把未执行的 native/UI 测试写作通过。
- 第三方依赖、全国数据、设备像素、动画观感、泄漏及性能未获本次认证。
- 不修改产品源码、测试或数据；只保存报告、覆盖清单及既有 scope ledger 的短说明。没有提交、推送或部署。

规范/产品合同轴 2 项，最高 P1 为乘客换乘关系进入物理图；行为合同轴 14 项，最高 P1 涉及跨国家保存、导入提交与漏计真实路径。共 16 项记录，其中区段归属的几项症状共享整改方向；架构建议另列，不计入缺陷。初审时均待修复；当日后续整改状态见上方修复报告。
