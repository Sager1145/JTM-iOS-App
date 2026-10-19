# 仓库目录与文件分类

本页是整个仓库的分类入口。2026-10-10 整理保留正式源码、构建器、数据库、工程引用及其他聊天的活跃路径；完成目录分类和无依赖本地杂项归档，随后按用户要求删除了三份过期提示／交接文档；没有改写 Git 历史。分类不是代码正确性、全国铁路完整性或过期报告有效性的证明。

## 从任务找到目录

| 任务 | 正式位置 | 内容与发布规则 |
| --- | --- | --- |
| iOS 主应用 | `ios/RailMap/` | Swift/SwiftUI 页面、状态接入、原生地图和品牌资源；发布源码。 |
| 共用 Swift 规则 | `ios/RailKit/Sources/` | RailCore 求解/身份/数据、RailPresentation 展示规则、RailApplication 状态；发布源码和包内必要资源。 |
| 生产回归测试 | `ios/RailKit/Tests/`、`ios/RailMapUITests/`、`app/tests/` | 有实际生产行为契约的测试；保留，按具体变更选择运行。 |
| 线路求解检查台 | `ios/auxiliary/RouteWorkbench/` | Mac Catalyst 诊断应用、Logo、详细报告和使用说明；独立容器。 |
| 历史直通检查台 | `ios/auxiliary/ThroughWorkbench/` | 历史服务检查界面、WorkbenchCore、已有报告；报告注明日期和输入边界。 |
| 显示轨道检查台 | `ios/auxiliary/RailAlignmentInspector/` | 几何/支轨/折返显示检查；归显示聊天负责，不能当作物理连接审批。 |
| Xcode/SwiftPM 工程 | `ios/*.xcodeproj/`、各检查台工程、`ios/RailKit/Package.swift` | 目标成员、资源复制和共享 scheme；路径改变需要连同引用集成。 |
| 原生打包资源 | `ios/Resources/` | 主应用需要的字体、品牌和本地资源；依赖 `ios/copy-rail-packages.sh` 的资源保持其合同。 |
| Web 与 JS 对应逻辑 | `app/shared/`、`app/index.html`、`app/package*.json` | Web 入口、共享 JavaScript 和依赖锁；Swift/JS 共同行为改变时核对两端。 |
| 构建器与支持工具 | `app/scripts/`、`ios/tools/`、`tools/apple-maps-rail/` | 数据构建、迁移、fixture 构建、保留的捕获与支持工具；不能恢复已退役的验证流水线。 |
| 发布铁路数据库 | `app/data/` 的正式数据库/编译 JSON、`app/public/rail/` | SQLite、solver JSON、线路包、显示包和来源说明；这些是构建产物，继续发布。 |
| 行程样例 | `app/data/sample-data*/` 的正式无编号目录、特殊样例、`train-store*.json` | 应用与诊断输入，保留行程信息和已提供的路线选择。 |
| Web 静态资源 | `app/public/basemap/`、`styles/`、`vendor/` | 运行所需样式、地图/供应方资源，保留归属说明。 |
| 两端等价 fixture | `port-fixtures/` | 已构建的跨语言生产规则 fixture；不是原始铁路下载，也不是验证通过声明。 |
| 铁路原始资料 | `railway-sources/local/` | 本地原始下载、标准化输入、候选和参考，Git 忽略；来源目录说明见 [源数据中心](../railway-sources/README.md)。 |
| 来源目录与许可 | `railway-sources/catalog.json`、`railway-sources/attribution/` | 可发布的分类、恢复位置、许可/NOTICE；不包含原始轨道载荷。 |
| 设计、决定与使用文档 | `docs/`、`ios/docs/`、`ios/*.md` | 当前手册放 `docs/guides/`，API／数据合同放 `docs/reference/`，维护规则放 `docs/maintenance/`；历史报告按主题放 `docs/reports/`，原生指南放 `ios/docs/`。入口见 [文档目录](README.md)。 |
| 执行计划/设计 | `docs/superpowers/plans/`、`docs/superpowers/specs/`、`docs/superpowers/completed/` | 有日期和范围的工作记录；旧计划不自动授权重新运行退役检查。 |
| 聊天归属/集成记录 | `ios/refactor-parallel/` | 独占文件范围、交接和当前集成状态，见 [聊天归属](../ios/refactor-parallel/task-ownership-20261010.md)。 |
| 本地报告、截图与工作资料 | `outputs/` | 已有忽略规则。保留历史测量/截图和旧构建，注明输入状态；新整理资料放 `outputs/repository-organization/`。 |
| 退役地区备份 | `backups/` | 原位保留，分类时不打开美国/加拿大载荷、不恢复打包；按已有 manifest/restore 说明使用。 |
| 同步冲突/源码备份 | `ios/sync-conflicts/`、`ios/source-backups/`、`backups/empty-numbered-data-dirs/` | 已标为保留副本。空的编号目录只换了位置，没有删除，也不能当作正式样例。 |

## 根目录与隐藏目录

| 位置 | 分类与处理 |
| --- | --- |
| `README.md` | 项目介绍，保留当前内容和其他聊天修改；本页提供更细目录入口。 |
| `AGENTS.md`、`CLAUDE.md` | 仓库工作规则，保持名称和位置以供工具发现。 |
| `docs/specs/` | 原仓库根的两份历史设计/迁移文档。Swift 注释仍用文件名引用，不依赖它们停在根目录。 |
| `.github/` | 仓库托管配置，保留当前退役流水线状态。 |
| `.claude/` | 项目代理配置和已有技能；不更改全局配置、身份或权限。 |
| `.gitattributes`、`.gitignore`、`.node-version` | 发布/LFS/依赖版本合同；由集成聊天持有，未并行改写。 |
| `.git/` | Git 管理目录，作为不展开的内部子树分类，不是待整理的业务资料。 |
| `.build/`、各 `.build/`、`.swiftpm/`、`DerivedData/`、`node_modules/`、`xcuserdata/` | 依赖与机器本地构建状态；已分类但未删除、移动或读取载荷。 |
| `.DS_Store` | 本地文件系统资料，已有忽略规则。 |
| `work/grok/` | 旧空工作目录已按用户要求移除；新临时任务采用已经忽略的 `outputs/<任务>/` 或 `/private/tmp/`，完成后清理无引用的任务草稿。 |
| `tests/` | 退役检查后剩余的空目录；无需填回流水线或为了整齐删除。 |
| `wl.html`、`yk.html` 及旧源数据路径 | 已忽略的兼容符号链接；目标是源数据中心，保留构建兼容关系，清单不跟随重复盘点。 |

## 原始资料、正式产物与副本的边界

`app/data/` 按内容和用途分类，不能整目录一并忽略：正式 `rail-sections*.json`、`stations*.json`、铁路历史/物理连接 JSON、`rail.db` 和时刻表 SQLite 是应用需要的构建数据库。原始 N02、OSM、网页、标准化候选输入已归入 `railway-sources/local/`，旧入口为兼容链接。原始资料被忽略不免除发布产物的来源归属和许可要求。

`sample-data 2`、`new-year-grand-loop-data 2` 等空格编号目录原先是空目录，没有 Git 跟踪文件。它们已原样移到 `backups/empty-numbered-data-dirs/`，没有并入正式样例，也没有删除。`sync-conflicts` 与 `.bak` 仍留在原位。未来若出现带内容的编号副本，先确认 target/manifest 引用和所属聊天，再在一个检查点合并。

历史报告应保持原始日期与适用边界。`outputs/refactor-20261009-resume/`、旧 `.xcresult`/`.trace` 作为历史证据原位分类，不能当作当前代码全部通过的依据。现行检查流程见 [ios/VERIFICATION.md](../ios/VERIFICATION.md)。

## 本次实际迁移

以下两个文件是未跟踪的临时任务提示，先通过同卷重命名整理到忽略区。用户随后明确要求删除不再使用的临时文件；再次确认没有活动代码/构建引用或进程打开它们后，已删除两份提示及其空目录。下表是迁移历史，不是当前文件入口。

| 原位置 | 新位置 |
| --- | --- |
| `grok-share-composer-read.txt` | `outputs/repository-organization/prompts/grok-share-composer-read.txt` |
| `railkit-logo-grok-task.txt` | `outputs/repository-organization/prompts/railkit-logo-grok-task.txt` |

`outputs/` 现有忽略规则已经覆盖这两个文件，本次不需要修改 `.gitignore`，也未改动已交接的铁路来源 Git 索引。

此次清理共删除 10 个已完成任务的临时文件（953,217 字节）和 3 个空工作目录，包括旧提示、源文件路径草稿、一次性分类脚本和空启动日志。逐项记录保存在 `outputs/repository-organization/cleanup-20261010.json`。活动检查台的输入/输出、增量构建、保留的检查报告、原始数据与备份继续保留；其他聊天的临时工作不在本次删除范围内。

## 2026-10-10 文档物理分类

这次把 117 份历史文档从 `docs/` 根移入主题目录，并把两份根目录规格移入 `docs/specs/`。没有删除文件。源码、Xcode 工程、`app/data` 正式库、`port-fixtures/`、`railway-sources/`、`ios/tools/`、`outputs/` 和 `backups/north-america/` 都留在原路径。

| 目录 | 内容 |
| --- | --- |
| `docs/` 根 | 用户指南、API、运行手册、文档策略、本页、铁路史、车站编号、在用的列车服务说明，以及两份仍有未提交修改的日本调查记录。 |
| `docs/reports/timetable/` | 时刻表批次报告与审计。 |
| `docs/reports/japan/` | 日本线路、东京和英文站名的日期调查。 |
| `docs/reports/north-america/` | 退役前的北美调查。`docs/reports/north-america/rail-optimization.md` 仍留在根上，因为构建脚本和 README 按这个路径引用。 |
| `docs/reports/stations/` | 站名、翻译和站位几何报告。 |
| `docs/reports/journeys/` | 行程补全与保存测试记录。 |
| `docs/reports/map-display/` | 显示网络、缩放和并行轨道验证。 |
| `docs/reports/integration/` | 集成与发布 JSON 台账。台账里的内容哈希仍是移动前字节的记录。 |
| `docs/decisions/`、`docs/superpowers/` | 决定记录和当日计划，位置不变。 |
| `docs/specs/` | `JRM_FLIGHTY_UI_REFACTOR_SPEC.md`、`REFACTOR_FOR_SWIFT_FORK_PROMPT.md`。 |

`ios/*.md` 留在 `ios/` 根。README、文档策略和进行中的重构记录按这些路径引用。`ios/tools/` 根上的规范化脚本保持平铺：它们以脚本所在目录为模块路径，互相 `import train_timetable`。移进子目录会断开这批脚本和 100 多处路径引用。

引用已跟着新路径改过，包括两份直接打开报告文件的 Python 测试。`backups/` 里的历史副本没有改写。

## 分类清单与以后文件的归属

本地逐路径清单：`outputs/repository-organization/inventory.json`。记录路径、类别、文件/目录/兼容链接/不展开子树、文件体积和当前跟踪状态。它包含仓库本地结构，继续留在忽略区。铁路源文件的既有逐文件清单位于 `railway-sources/local/inventory.jsonl`。

本次对普通文件/目录逐路径分类；Git、依赖、构建、原始源中心、历史产物与退役备份分类到整个子树，不递归展开其内容。符号链接只记录目标，不重复读取。没有进行全树内容哈希或建立新的自动检查运行器。

新增文件按用途直接放入上表的位置：生产代码靠近所属模块，生产回归靠近对应 Tests，正式产物使用构建器规定的发布路径，原始参考进入源数据中心，临时任务/日志进入 `outputs/<任务>/`，设计/结果说明进入所属文档或检查台。需要改变工程、正式数据、其他聊天文件路径时，按归属表在集成检查点执行；不能用分类整理顺带改变业务行为。

## Markdown 整理记录（2026-10-10）

盘点仓库可见文档和隐藏代理说明；构建依赖、原始资料缓存、输出和备份中的副本保持原位。37 份文档移入对应手册、参考、报告、已完成计划或源码审查目录，保留历史日期、测量、来源与未解决问题。相邻数据来源／许可 README、代理规则和活跃聊天范围账本继续原位保留。

删除以下已被现行文档替代的指令，不删除它们关联的性能或交付证据：

| 删除的旧文件 | 当前入口 |
| --- | --- |
| `ios/REFACTOR_PROMPT.md` | [源码结构](../ios/docs/source-structure.md)与[当前验证政策](../ios/VERIFICATION.md) |
| `ios/PERFORMANCE_OPTIMIZATION_PROMPT.md` | [性能范围账本](../ios/refactor-parallel/performance-m.md) |
| `ios/REFACTOR_PARALLEL_HANDOFF_20261009.md` | [2026-10-10 聊天归属](../ios/refactor-parallel/task-ownership-20261010.md) |

当前使用指南改为五个支持地区；API 文档修正三模块与只读 SQLite 合同；运行／移植指南移除自动全量检查要求。历史 feature ledger 和旧重构计划保留为报告，不能作为今日通过声明。检查仅限内容与引用；没有运行构建或测试。

## Markdown 精简（2026-10-15）

删除 7 份已完成且结论已有现行入口的执行清单：ThroughWorkbench 初始实现与检查计划、Xcode 目录整理计划，以及架构深化、iOS 审计修复、16 项审查修复、架构跟进的执行计划。

对应结果仍保留在 ThroughWorkbench 的 README／REPAIR_LEDGER、原生源码结构指南／architecture-coverage 台账，以及 integration 下的 architecture-deepening-2026-10-12、full-ios-code-audit-fixes-2026-10-12、code-review-fixes-2026-10-11、architecture-review-follow-through-2026-10-11 报告。具有独有测量记录的 completed 文档、活动计划、来源许可和铁路证据不在删除范围。

检查限于清单完成状态、替代文档内容及引用；7 个被删文件名没有其他 Markdown 入链。没有运行构建或测试，也没有改写现有 Git 索引。
