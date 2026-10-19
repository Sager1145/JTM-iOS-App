# S3 / S6 功能责任与验证矩阵

> Historical record retained during the 2026-10-10 documentation cleanup. Dates, measurements and unresolved findings below apply to the recorded inputs. Old execution commands are not current instructions; follow [the current verification policy](../../../ios/VERIFICATION.md).

## 第 37 阶段续批（2026-10-09）

核对 Sakura770 新岩国的既有停车→通过修正，修复过时的 marker 总数断言并新增一条精确回归；22项包测试和质量门禁通过，未修改产品数据或 golden。完整验证旧轮在102套通过后因该断言停止，新轮需按171套／1446函数重新验收。全地图直接内核采样仍超过2GiB；Stats、RouteStress、M、完整覆盖率及原性能／泄漏目标继续开放。精确范围见[阶段记录](refactor-phase-commits.md)。

## 第 36 阶段续批（2026-10-09）

使辅助功能容器的形状符合实际工作区视口，修正原始屏幕边界用例；六项原始菜单用例、Debug／双架构 Release 构建及新增 lint 门禁通过，没有新增内存所有者。全地图普通第二轮仍超过2GiB；VM trace 可读不代表内存通过。统计页底部、完整171套／1445函数覆盖率、RouteStress、M 和原始性能／泄漏验收继续开放。精确范围见[阶段记录](refactor-phase-commits.md)。

## 第 35 阶段续批（2026-10-09）

保持根布局的窗口高度，避免键盘展开时改变 resident sheet 的 detent 集合；Compact 内容保持挂载但隐藏，滚动底部含一点评估余量。普通候选三轮共9次菜单原断言、3项编辑、一次日期复核及3项 iPad 检查通过，Debug／双架构 Release 构建和新增 lint 门禁通过。没有新增缓存、监听器或计时器；这些结果不替代全地图 RAM／泄漏及完整性能验收。完整包171套／1445函数覆盖率仍在执行；原始 S0–S6/M 其余门槛继续开放。精确范围见[阶段记录](refactor-phase-commits.md)。

## 第 34 阶段续批（2026-10-09）

Phase33 质量 CI 已通过。Phase34 消除所选日本行程与纽约 DEBUG 相机覆盖同时启动的测试条件冲突，保持原断言及超时；当前版本全部7个相机用例通过，峰值约801MB，未增加生产内存所有者。完整包1445函数／171套件的覆盖率验证仍在执行；全地图2GiB、其余布局／平台及 M 等原始门槛尚未完成。精确范围见[阶段记录](refactor-phase-commits.md)。

## 第 33 阶段续批（2026-10-09）

Phase33 缩小每条普通图边的可选物理接点存储，保持值语义及真实几何。固定日本／台湾 Release 场景三组严格配对通过：稳定内存中位数下降0.65%，峰值下降43.52%；当前 Main32 的双架构构建、原路线／统计测试及零新增 lint 债务通过。保留此前失败样本，稳定占用的小幅变化不外推到全地图。全地图2GiB压力、完整覆盖率、布局／平台及 M 门槛仍开放，整体未完成。精确验证范围见[阶段记录](refactor-phase-commits.md)。

## 第 31 阶段续批（2026-10-09）

Phase30 内存采样 CI 已通过。Phase31 用现有所选记录与 active ticket 的完成状态消除分享导出启用时序问题；原三次串行分享和 Console 全流程、13 查询检查、58 生命周期检查、App 构建及零新增 lint 债务通过。保持批量失败的未知里程展示和重试，未增加持久内存所有者，未放宽原断言。精确范围见[阶段记录](refactor-phase-commits.md)。这是功能收口，不宣称配对 RAM 或零泄漏通过。菜单候选重新展开输入仍失败，未交付；严格内存、完整覆盖率、平台、目录及 M 门槛仍开放，整体未完成。

## 第 29 阶段后的当前验收入口（2026-10-09）

本节覆盖下方历史时点，原始 S0–S6/M 门槛不变。Phase28 `bf70a5ad` 已推送，CI 37950156025 SUCCESS；Phase29 从该基线提取统计线路展示规则到 RailPresentation，保持原数据所有权、顺序、身份和 Double 数值，不增加加载、缓存、任务或持久状态。5 个定向测试 / 8 个用例、六类别旧规则等价、App Debug 构建、281 项生产归属、509 Swift 的 270 旧 findings / 零新增债务及格式检查通过；原统计日历和年度流程通过。分享导出失败已在原 Main28 二进制复现，仍开放；本阶段不声称实测 RAM 减少。

- 内存候选仍未合入：Edge stride 824→184；原 25 项历史包候选通过，实测峰值 686,917,168 B。但双地区 Release 三组配对稳定中位数 438,587,016→517,606,616 B（+18.02%，FAIL），峰值 1,201,524,168→673,287,240 B（-43.96%）。不能以峰值改善抵销稳定占用失败。同一候选 Debug 地图另触及 2,344,833,608 B，原断言与 2 GiB 守卫不放宽；配对时存在其他验证负载，不能作为安静性能验收。
- 当前 Main 包验证：原 1,437 函数 / 169 套插桩清单已确认前 63 套通过；第 64 套原 RailHistoryPackageTests 触及 2,204,289,640 B，被守卫中止。完整包及 Domain/global coverage 未通过；候选历史包成功不替代 Main 或剩余套。先前失败及短套采样缺口保留。
- 后段 iPhone UI 的 24 次原选择运行完成：63 PASS、13 FAIL、11 SKIP，共 87 项，不能称完整 137 项 / 39 类矩阵通过。失败覆盖缩放、菜单布局、压力往返、站点、日期及一次五地区输入选择错误。输入错误保持原失败记录，纠正夹具后同 Main 原五地区公开路线/统计测试通过，112 样本、单 PID、峰值 1,249,725,920 B；不等同于配对 RAM 或泄漏验收。

继续关闭实际内存及功能失败，完成全量覆盖率、责任目录、iPad/Catalyst、启动/首图/stall/增量构建/泄漏及 M；整体仍为**执行中，未完成**。CLI 工作树不包含于本阶段，临时 outputs/tmp 收据的精确摘要以此提交和[阶段记录](refactor-phase-commits.md)为准。

## 第 26 阶段后的当前验收入口（2026-10-09）

此节更新下方第 18 阶段时点的“当前”状态，原始 S0–S6/M 目标及门槛不变。已推送 `main` 为 `922b7541b0e5048ca6f95269437055f726adf7a9`，阶段 20–26 的实现和精确验证见 [阶段交付记录](refactor-phase-commits.md)。并行 CLI 工作树不属于这些提交的验收。

- 质量：固定版本复杂度 >15／函数长度 >60 校准已交付；新增 lint 债务硬门禁已接入 CI 并通过，保留 270 条既有全 Swift 清单 findings，不用删除旧债抵扣别处新增。生产代码既有 167 条及通常 ≤10／≤40 目标继续开放；格式检查仍为 advisory。
- 功能：原 Console 分享 composer 流程、两个组名编辑/保存重启、两个本地自动填入/Undo/pending 服务保存重启分别通过。Undo 保留精确草稿相等守卫，先同步派生方向再捕获快照。五活动地区真实行程全部公开路线生成及 All regions 统计检查通过；该次峰值 1,188,285,896 B，只证明预算内正确性，不是五地区配对 RAM 或泄漏验收。
- 当前完整包：全部 1,437 注册函数、169 套的覆盖率插桩清单按套执行中；337 个服务 pattern 的 674 次 required/optional 检查已全通过，实测峰值 1,277,986,616 B。其余套及 Domain/global 导出未完成前，不宣称整套或覆盖率达标。先前失败及短套采样缺口保留。
- 当前设备矩阵：Main26 精确 507 Swift 文件与实际二进制测试清单一致，137 项/39 类；尚未执行的后段功能已继续逐类验证。旧全矩阵失败、当前缩放 150 ms 门槛失败仍开放，不能把独立修复收据累计为当前全平台 PASS；并行验证也不能替代安静环境性能对照。
- 内存：原双地区 Release 三组对照稳定 footprint -0.54%、峰值 -20.43% 的范围不扩大。区域切层/平移仍会超过 2 GiB：稀疏精确 junction 查询和单帧几何缓存候选分别触及 2,251,821,856 / 2,551,501,816 B，均未交付。Main26 DEBUG 诊断第七次全国图构建期间触及 2,205,766,504 B；事件证实 fallback 活动，尚未归因分配者。下一步细分真实构图峰值，铁路源顶点、拓扑、日期及 pending 守卫不变。
- M：同一静态五姿态公开路径检查证实 iOS 默认参考 5,000 顶点及逆 map-point 偏差 0、所有显示 scale 为 3；像素/同步门槛仍未通过。exact 参考控制具有不同实测描边宽度，不能当作等效精度对照。仅保留诊断候选，不进入默认地图。

继续顺序为关闭实际内存/功能失败、完成全部测试与真实覆盖率，再验收责任目录、iPad/Catalyst、启动/首图/stall/增量构建/零确认泄漏和 M。每个独立验收阶段 commit 并 push main，整体状态仍为**执行中，未完成**。本地 `outputs/` 与 `/private/tmp` 收据是执行附件，精确摘要保存在提交内；临时文件不作为可永久克隆的证据。

## 2026-10-09 当前提交验收入口

本节覆盖下文历史“最新”和“未提交”表述。当前已推送生产基线为 `f240ada65564466af2c74de59c2ba98ad32a6b9e`；原计划及目标仍以 [主计划最新核对](full-codebase-refactor-plan.md) 为准，18 阶段的精确实现/收据见 [阶段交付记录](refactor-phase-commits.md)。CLI 的额外工作树改动不包含在这些 Main 结论中。

| 责任链路 | 已交付验证范围 | 当前验收边界 |
| --- | --- | --- |
| Workspace / Share | scoped render key、单重型 permit、不可协作 await 后仍保留 owner、旧 generation 拒绝、预览/导出像素预算；57 native 检查与 Main 分享 UI 定向通过 | 完整分享/播放/视频与设备图像矩阵仍待运行 |
| NewTrip / Application proof | dated/undated 独立证明，匹配日期才 confirmed，pending 保留；22 availability + 3 plumbing 与三条 Main 新建行程 UI 通过 | 完整编辑/保存/重启/用户数据往返矩阵待完成 |
| Route / Display / Statistics | 有界单槽缓存、解码/构图串行、endpoint preflight、carried inputs、图材料化等价；真实 JP/TW 公开 UI 三组 Release 对照全通过 | 双地区稳定 footprint -0.54%、峰值 -20.43%，不能推广到所有地区或零泄漏 |
| History / Physical graph | 原 surveyed geometry/拓扑/golden 未放宽；历史 browser boundary 单套通过，峰值 1,938,131,584 B | 原全量包因峰值 2,286,816,064 B 中止；当前覆盖率构建通过，全部注册测试按套新进程执行中，未宣称整套 PASS |
| Quality / Platforms / M | 固定版本 advisory lint/format CI 与 scoped coverage 工具已交付；定向 Release 双架构构建通过 | 完整 Domain/global coverage、长度/复杂度、全 UI/Catalyst、启动/帧时/增量构建/泄漏仍开放；M frame-leading 实验失败且未交付 |

永久字号 `.xSmall ... .xLarge`、iPhone 竖屏、iPad 方向、北美退役、严格物理连接与单地图遮罩层级保持原合同。旧失败保留原身份；旧局部成功不能替代当前全矩阵。整体状态：**继续执行，尚未收口**。

日期：2026-10-09（本次源码责任更新）；2026-10-03 及此前结果保留为历史记录。状态：**源码链路核对；不是整体验收记录**。

2026-10-09 续跑已核对当前 NewTrip 历史日期批量探测、Share Composer 渲染/导出及选中站点快照 owner，并登记以下已完成的独立收据。其余下文此前的“最新”“本次”及 PASS/FAIL 均属于当时执行记录，不证明当前工作树已通过。当前完整验证仍未完成。

- 当前真实源码抽取的分享 tiny-host harness **34 PASS、零 warnings**，见 `outputs/refactor-20261009-resume/sharing-current.log`；包含 CLI 的预览 canvasSize / 全分辨率导出分离、per-operation reference buffer 立即释放、同 generation 并发导出互不清理、exact completedKey 导出守卫及 view ticket。图形替身不证明 UIKit 视觉或设备表现。
- Core endpoint preflight 在建 graph 前调用真实 helper，并保留仍可用的 fallback；聚焦 **Core 44 + Application 9 PASS**，见 `endpoint-preflight-tests.log`（其中编译曾有两条测试 unused-expression warning，不沿用分享零 warnings 结论）。三条历史夕张测试 **PASS / 38.430s / exit 0**，见 `history-preflight.log`；退役日期和 undated 各 0.001s。这是局部路线检查，不是完整 Core gate。
- `boundaries-current.log`：**280 production Swift sources、7 checker tests 与永久字号范围 PASS**。新 durable app source/resource 快照 `app-input-durable` 与 SHA manifest 记录 **11,890 文件、复制后零变化**；它是输入身份收据，不是构建成功。
- continue 后临时执行状态再次丢失：旧 scratch builds、原自有 simulator 和活动 package sessions 已不存在；未结束的 non-history 测试没有 exit 收据，不能记为 PASS。历史采样在进程退出时收到空记录，性能收据仍为 partial，不能声称完整峰值；采样脚本已修正，尚待新运行。
- 新 cold App build 暴露 `StatisticsShareImage` 并发捕获 options 的别名错误；已改为 await 前复制 CGSize，**编译验证仍待完成**。新自有 simulator 已启动，UI 重试仍等待 App build；`EdgeIndexCache` 有界/串行重构进行中，尚无验收。**M 仍为 NO-GO；full-viewport dim 未实施**。

以上日志均位于 `outputs/refactor-20261009-resume/`。本次文档编辑只读取已有收据，没有启动构建、harness 或设备 UI。

本轮清理后 fresh 验证按源码快照分别记录：源码归属271sources/7checks PASS（新增 OperatorIdentity/SearchFold 只登记 inventory）；较早固定脚本 app gate PASS且运行前后源未变，较早native与外补聚焦34tests/4suites PASS，但外补后续仍改源码、铁路数据与四份golden，不沿用为当前全仓最终gate。完整包此前编译版本 Core853 tests/106suites FAIL105issues（全部列车服务目录），Presentation333与Application26 PASS，七项压力检查全部PASS。外补按齐全站码清除用户pending、人工跨线路候选在缺少dated physical proof前写confirmed，以及新TripConnectivity/TripRoutePlanner以直通目录/kind/operator作为接续授权，均有只读review未闭。最新editor修复11条实际全FAIL（8旧新建向导入口被NewTrip替换，3其他诊断）；playback真实AX5三项PASS，修复后末卡间距与紧凑搜索2PASS，统计前次1FAIL已由主机日志证明newtrip-check强制重启打断；16:20单项复测另有真实1FAIL175.732s（loading耗费部分拖动预算，末尾note未揭露），仅改测试ready/flick；新版runner build exit65，外补在构建期间新增共享helper并改8个已有文件，未启动新版UI。地图287条加载/切层/拖动75秒驻留PASS487.011s，最大相机距离两次实际差5358.7m仍FAIL，1000m/2秒断言保留、根因未定位；Tokyo150ms起跑前因外补Swift测试持续约99%CPU未运行，16:26:34设备RELEASE。系统share UIView bounds候选功能PASS、visualFAIL，候选已撤销；M、iPad与最终整套UI未验收。北美备份草稿已上传且服务端SHA/大小一致。未执行最终合并推送。下文原/tmp历史路径在统一清理后已消失，除执行记录明确恢复者外，只作当时观测。


本表依据当前工作树中的 Application、地图、存储、AI 请求、时刻表、站点搜索与分享渲染/导出边界。源码归属以 `source-ownership.json` 和 target 成员检查为准。没有读取用户私人文件或认证凭据；后续物理拓扑验证只读核对了活动地区的源轨道资源。测试文件存在、源码接线成立与测试实际通过是三种不同证据。

北美退役与严格物理拓扑变更前，完整 SwiftPM 为 1,175 项通过（`/tmp/jtm-refactor-completion/swift-full.log`），只作历史基线。最新 native 整套（含新 production component）与 Simulator app/build-for-testing 已通过；RailValidity 三项聚焦回归通过；最新聚焦 SwiftPM 40 项 / 4 suites 通过（`/tmp/jtm-na-retirement/corrected-contracts-final.log`），包含最新 18 项拓扑检查，不重复累计。完整 Swift `/tmp/jtm-na-retirement/swift-full-latest.log` 已结束且整体失败：Presentation 333 与 Application 25 项通过，Core Swift Testing 837 项运行、166 issues（路线 57、History 109）；该次 XCTest 旧缓存/策略失败在源码修正后另行三项聚焦通过，未重写整套结果。History 两个 browser golden 聚焦复跑已失败（10 issues / 419.913s）；返回结果的源顶点、源长度和无 connector 断言通过，原 golden 与生产守卫保留，缺口详见 [物理路线缺口](../routing/physical-route-gaps-2026-10-03.md)。Root 已核验三份归档清单 171 + 21 + 810 = 1,002 个唯一 payload 文件及精确库存覆盖；新增 raw 810 项只证明当前归档 hash 基线，不证明迁移前原件字节一致。四个接续完整日本源图接纳通过。iPhone 8 项、iPad 4 项字号/方向相关检查通过，两台实设系统 AX5 均收到 xLarge；Catalyst 最新构建及实际行程 → 嵌套编辑 → Cancel 无崩溃。七条修复定向 UI 流程已在不同轮次分别通过，包括最终分享 98.148s、四种 Light/Dark map/statistics 图像及日期/地区断言；不是完整 UI suite 通过。最新 sharing build-for-testing 与 Catalyst component build 通过。日志、限制及历史失败见 [执行记录](refactor-execution-2026-10-03.md)；此次文档更新没有启动测试。

最新续跑已修正两个 History 契约测试，原 browser gold 不变，全部 191 条 native 源边/日期检查及 SixRides 通过（929.709s），不是完整 Core 重跑。审查接续目录现为十项；宇多津默认线路偏好的方向偏差已修正，显式／默认、两个分支的八次往返求解通过源边断言；具体道岔允许动作仍未认证。新增两条长行程分享 UI 通过（87.918s），217 行为明确标注的合成待确认记录；生产数据未恢复未经验证的通过站。视频导出三条实际 UI 流程通过（105.856s），三份新 H.264 视频完整解码并核对部分／结束画面；最新 native 整套 gate 通过。校正锚点实验仍有 16–17px 可见偏移，M 保持 NO-GO。以执行记录的最新小节为准，不把历史失败或局部成功改写为整体验收。

最新物理连续性以已验证的前段轨道终点为依据，显示站点锚点不会覆盖它；真实 Azusa 整条站序和 35 项聚焦检查通过。完整 native gate 与 App 测试构建通过。287 条记录的导入、重启、路网切层／拖动和 75 秒驻留实际 UI 已通过（434.600s）。完整服务目录已结束但仍有 105 issues；其余完整包测试随后通过（Core 844、Presentation 333、Application 26、传统 XCTest 48）。完整 frozen-binary iPhone UI 已结束：126 注册、77 PASS、36 FAIL、13 SKIP（不包含另行通过的 287-record dataset case）；六项地图缩放和旋转、四项手机播放布局及三项视频导出包含于该轮。定向修复结果以执行记录后续小节为准，不能倒写整套结果。M 仍未通过。代码已包含于 `a12d072c` checkpoint 与 `9c6856b4`，最终整体验收及推送尚待本轮整合。

## 最新产品规则与待办范围（2026-10-03）

以下是用户确认的产品要求与验收标准，不代表实现已完成。核心边界：**候选路线不等于完整路网，车站能换乘也不等于轨道能直通。行程仍须显示推测的通过站。**

| 优先级 / 项目 | 产品规则与销账条件 |
| --- | --- |
| 优先：物理轨道连接 | 每个跨线路连接有可追溯依据；同名、距离接近、相同站点身份或换乘关系本身均不足以证明可直通。候选目录不能充当完整路网。 |
| 起终点与必经站 | 用户选择起终点及可选必经站，软件判断实际铁路区间；只有确认唯一可达且搜索未截断时自动填入区间和通过站。最短候选或列表中只剩一个候选不等于唯一可达。 |
| 多路线选择 | 在地图上点选实际候选路径，并保留与地图选择同步的卡片供 VoiceOver 使用；不能只靠地图点击。 |
| 待确认 | 不确定、搜索截断或没有正确候选时，允许保存“待确认”；不强行连线，不将未确认区间计入精确里程，也不把未知里程表达为已确认的零公里。 |
| 推测通过站 | 行程继续显示所选或已确认物理路径推得的中间站，默认标为“通过、时刻未知”，明确推测来源；不得从物理路径推断实际停车或编造时刻。待确认候选中的站点不能作为已确认路径自动写入。 |
| 直通车展示 | 直通车名称和运行系统继续显示，与轨道连通证据分别建模；服务名不能补出不存在的连接。 |
| 北美 | 已下线；US/CA 枚举、编号/时区、开关和 store split/merge/restore 兼容链已移除，不列保留功能或待办。原始与旧混合资源保存在 `backups/north-america/2026-10-03/`，Root 已核验主清单 171、legacy sources 21、raw 清单 810，共 1,002 个唯一 payload 文件及精确覆盖；raw 清单为当前归档基线，不是迁移前独立字节证明。 |
| iPhone 方向 | Debug/Release 已永久配置仅竖屏，横屏不列为缺失功能；iPad 四种方向仍保留。iPhone 竖屏播放及旋转请求检查通过；iPad 完整方向交互仍待验收。 |
| 字体范围 | scene 根与 UIKit preferred-font 永久限制 `.xSmall ... .xLarge`；这不是临时测试开关。iPhone 8 项、iPad 4 项相关检查通过，两台实设系统 AX5 均保持 xLarge；其他页面与辅助功能组合继续待验。 |
| 底图与遮罩 | 底图不透明度和全屏变暗合并为同一项：底图与铁路之间固定、轻微、覆盖整个地图视口的遮罩，不因此新增透明度滑块。 |
| Web 与其他规格 | Web 后端和 Web 工作区单独列账，不计入 iOS 重构未完成项；设计文档中的其他后续方案须先确认范围，不能自动视为交付承诺。 |

优先修正文档声称已有但实现缺失的冲突，或补齐经确认属于本次范围的实现。路线验收至少覆盖：唯一且完整搜索、多路径、截断后仅剩一个候选、无正确候选、只能换乘不能直通、推测通过站无时刻、待确认保存与精确里程排除，以及地图/VoiceOver 卡片选择一致性。旧测试结果不证明这些新规则已通过。

## 1. 逐链覆盖

### AppShell → Workspace → 地图 / 呈现

- **owner**：`RailMap/AppShell.swift` 中 `ContentView` 为组合根，创建 `ItineraryStore`、`RideLibrary`、`RailMapController`、`RiddenRouteStore`、`MileageStatisticsStore` 和唯一 `PlaybackController`。`RailMap/ContentView.swift` 中 `RailWorkspaceView` 注入和连接这些实例，保留局部搜索、筛选、菜单、草稿和呈现状态。
- **已有边界**：`WorkspaceTabs`、`WorkspacePanelPage`、`WorkspacePanelActions`、`WorkspacePresentations`、`WorkspaceSheetContent`；`WorkspaceDerived` 提供缓存派生结果，`ManualDates` 管理输入日期；`JourneyPresentationResolver` 决定动作/状态优先级。它们已经接入工作区，不能当作未实施模块重新提取。
- **不变量**：单地图和单播放器；列表/详情身份与返回状态；统计过滤与行程列表过滤各有既有作用域；关闭呈现后再执行相关操作。跨区域选择使用 `ItineraryStore.selectedTrainID`，最近查看 ID 保持单独持久化语义。
- **验证入口**：`RailPresentationTests/JourneyPresentationResolverTests.swift`、`WorkspaceJourneyRulesTests.swift`、`JourneySearchMatcherTests.swift`、`LaunchJourneySelectorTests.swift`；`RailMapUITests/RailMapUITests.swift`、`WorkspaceEditingTests.swift`；`tools/verify-layout-ui-smoke.sh`、`verify-reduce-motion-ui.sh`。
- **源码结论**：保留现有组件和状态 owner。工作区仍承载编辑提交、分享与播放等跨区域协调；继续提取必须先说明独立生命周期和输入，不能按成员数切 extension 或创建收齐所有 stores 的 ViewModel。

### Statistics → Passport → 分享 / 回放 / 导出

- **owner**：`MileageStatisticsStore` 拥有加载状态、独立日期/年份/行程组 scope、fingerprint、entry cache、passport-only 与重新按日聚合任务；`RailApplication/MileageMatching.swift` 接受 `Statistics.Train`、digest、canonical 段快照，调用 Core 匹配并返回有序 entries 和当前快照的缓存。`PassportStatistics` 拥有护照分布/排行计算；`StatisticsDashboardContent` 组合卡片。
- **Passport 不是第二个统计系统**：`PassportWorkspaceView` 使用同一个 statistics store 和 `WorkspaceDerived`，消费工作区已计算的 `statisticsScope.trains`。`ContentView.swift` 的 `statisticsScope` / `mapRides` 保证地图和护照引用同一 scope；护照回放调用 shell 的播放器。
- **分享 owner**：旧 `ShareRequestController` / `verify-share-request.py` 已退役。当前统计分享进入 `ShareComposerView` / `ShareComposerModel`；view 的 `.task(id: renderKey)` 拥有预览任务，`ShareCardRenderController`（`ShareCardRendering.swift`）拥有 generation、images、当前 key 的 cache 与 completedKey。`loadKey` 绑定有效 scope、年份、行程组、日期、store generation 及 rides geometry digest；`renderKey` 再绑定统计是否就绪、比例、尺寸、明暗与有序卡片 ID/布局/缩放/种类。key 改变时清理旧图/cache，每张卡片 await 后检查 generation/取消；`cancel()` 使旧请求失效并释放预览/cache 及每个 operation 的 reference buffer；取消/替换在不可协作 snapshot 仍挂起时即可释放已生成的局部像素，不依赖 await 返回。view 独立拥有 exportTask/exportTicket，导出前快照 renderKey，await 后核对取消、ticket 和 key；renderKey 变化及消失均取消导出，消失同时取消 renderer。renderer 使用传入 canvasSize 生成预览；导出要求 completedKey 精确等于请求 key，再以目标 pixelSize 全分辨率重新渲染（不复用预览 cache），按 model 卡片顺序合成。每次 render/export 独立 operation ID 与 reference buffer，清理不干扰同 generation 的其他导出；经 `SharePNGWriter` 写文件后再次检查 generation/取消，再由 view 发布 `StatisticsShareView`。`JourneyShareImage.swift` 保留单旅程分享；护照卡片的文件导出入口打开 Data Library。
- **播放/视频 owner**：`PlaybackController` 拥有播放队列、时间与选中状态；`MapPlaybackLayer` 消费播放快照；`VideoExportFlow` 拥有导出设置和录制流程；`PlaybackVideoExporter` 拥有媒体输出。`VideoExportFlow.abandonRecording` 使用 `clearPlayback: false`，取消录制不能自动杀掉跨页回放。
- **不变量**：同一地区/年份/日期/行程组语义；有效乘坐记录范围；WGS84 统计不读取显示 datum 或屏幕抽稀几何；保持 entries 插入顺序、缓存 index 身份和日期 digest；passport-only 编辑不重新匹配、不清空 mileage；share 快照不能在挂起后跨 scope 发布。
- **验证入口**：`RailApplicationTests/MileageMatchingTests.swift`；`RailCoreTests/StatisticsParityTests.swift`、`TemporalEdgeStatisticsTests.swift`、`PlaybackParityTests.swift`、`PlaybackTrailTests.swift`；`RailPresentationTests/StatisticsDateSelectionTests.swift`、`WorkspaceJourneyRulesTests.swift`；`StatisticsCalendarUITests.swift`、`StatisticsRhythmYearUITests.swift`、`IntegratedSharingUITests.swift`、`JourneySharingUITests.swift`、`PlaybackLayoutTests.swift`、`PlaybackVideoExportTests.swift`；`tools/verify-playback-lifecycle.py`、`verify-playback-video-lifecycle.py`、`verify-share-card-rendering.py`。后者抽取真实 renderer 与 view 导出方法，以 tiny-host 图形替身和故意忽略取消的 snapshot/PNG await 覆盖当前 34 项检查，已在 `outputs/refactor-20261009-resume/sharing-current.log` 全部通过且零 warnings；早期 16 项是历史范围。覆盖缓存复用/释放、有序合成、旧 generation、取消、替换、view export ticket、精确 completedKey 和独立全分辨率导出 buffer；不是 UIKit 视觉、app 构建或设备验收。
- **源码结论**：现有 scope、缓存、匹配与播放 owner 应保留。统计卡片内仍有展示数据整形，工作区仍协调 scope-sensitive 分享；这是可继续分析的具体责任面，不构成必须重写统计算法或整个分享系统的证据。设备图像、导出产物和跨页录制行为仍需实际验收。

### History / Timetable → 编辑候选 / 地图 / 统计

- **owner**：Core 的 `RailHistory` 及其 revision/overlay 值与时刻表模型/匹配承担领域规则；`TrainTimetableDatabase` 保持只读 SQLite 例外。App 的 `RailDisplayNetwork.swift` 读取显示 manifest/几何并进行平台整形；`RiddenRouteStore` 管理求解所需历史状态/缓存，`RailNetworkStore` 管理显示历史、全精度/概览几何及视口激活。
- **目录搜索边界**：`StationPickerSearchController` 拥有 prepared/retired 快照、120 ms debounce、后台 worker、请求身份、加载 token 与取消；`StationPickerView` 保留目录加载和分组 UI，catalog/prepare/retired 三个 await 后均检查取消与 token。搜索保留名称/alias/source code 匹配、历史站仅名称匹配、输入顺序与空查询恢复完整快照。
- **时刻表平台边界**：`TimetableQuickMatchController` 拥有输入变化、300 ms 自动 debounce、手动搜索、requestID、候选和错误；`TimetableQuickMatchLookup` 拥有数据库查询，沿用后台查询和 Core 匹配；`TimetableQuickMatchView` 呈现候选，选中仍走编辑器回调，不由 controller 改写 draft。
- **不变量**：服务日期/跨午夜语义、地区与输入身份、来源文档关联、历史有效期/退役归属、canonical 几何和资源 revision。当前历史是跨求解/显示/统计的领域能力，不复制成独立平行数据源。数据库 artifact 不能因拆分改写或丢失已提交 WAL 内容。
- **验证入口**：`RailCoreTests/RailHistoryTests.swift`、`RailHistoryIdentityTests.swift`、`RailHistoryStationsTests.swift`、`RailHistoryPackageTests.swift`、`TrainTimetableDatabaseTests.swift`、`TimetableServiceDayContextTests.swift`、`TimetableCountryScopeTests.swift`、`TimetableAppFlowTests.swift`、`TimetableQuickMatchReportTests.swift`；UI 的 `TimetableQuickMatchUITests.swift`、`TimetableDiscoveryUITests.swift`、`TrainTimetableUsabilityUITests.swift`、`TimetableCoverageUITests.swift`、`TimetableSymbolUITests.swift`；`tools/verify-train-timetable-artifact.py`、`verify-timetable-quick-match-lifecycle.py`、`verify-station-picker-search-lifecycle.py`。后者七组检查已在 native-final 门禁通过，覆盖真实过滤规则和旧查询/加载晚完成、清空、消失与 debounce 取消。
- **源码结论**：quick-match 和 station-picker 已有独立生命周期及窄输入；保留 Core/SQLite。官方英文名任务绑定 number/date/region，后台返回后检查取消；routeChoice 绑定地区且通过 cancellation handler 取消 worker；inference 检查 draft 快照并在消失时取消；StopEditor 的目录/名称/历史站任务绑定地区、线路、名称或日期，并在 await 后检查取消。这些视图局部 `.task` 已有合适 owner，保留其作用域，无须机械再抽控制器。

### Settings / Localization → 展示 / 数据范围

- **owner**：`SettingsView` 组合设置界面，`DisplaySettings` 拥有显示偏好；`AppLocalization` 桥接本地化引擎和地区变体；`AppStrings` 与各 Strings 文件保留文案注册与薄转发。站名读音/站点显示规则继续用既有 Core/展示边界。
- **当前范围**：North America 已下线，数据仅作仓库备份；北美开关、编号和兼容功能不属于保留功能或交付待办。活动地区的数据范围、保存与 network 激活按现有入口核验。
- **不变量**：偏好键、语言/地区编码、身份键与序列化格式不变；文案 fallback 和注册表碰撞检查不变；减少动态效果/透明度/增强对比度/VoiceOver 保持可用。
- **验证入口**：`RailCoreTests/LocalizationParityTests.swift`；`tools/verify-store-ordering.py` 的相关范围/存储路径；`JourneyTranslationUITests.swift`；布局与 reduce-motion 脚本。需要新增或映射现有设备场景来覆盖具体设置操作，不能把翻译测试当作全部 Settings UI 验证。
- **源码结论**：文案注册与显示 owner 已独立，应保留。活动地区的数据管理行为需按实际写入链走存储验收；不恢复已下线的北美开关。

### AI → 编辑候选 → JourneyEditing → 保存

- **owner**：`ChatGPTSubscriptionAuth` 管理认证生命周期/凭据存储适配；`ChatGPTSubscriptionService` 管理网络与响应流；Core `ChatGPTSubscriptionProtocol` / `JourneyCompletion` 管理协议与候选合并规则。`JourneyCompletionRequest` 拥有单请求生命周期，取消后保持 busy 至实际退出，避免新请求与旧 cleanup 重叠。
- **候选采纳**：`JourneyCompletionView` 保留 draft/proposed、人工预览、inputRevision 检查；显式 Apply 调用 `RideEditorView` 的 `onApply`，只修改编辑草稿。最终保存沿用工作区 `commitJourneyEditor` → `JourneyEditing.addAndPersist/replaceAndPersist` → `ItineraryStore` → `RideLibrary` 写入任务。
- **保存 owner**：`JourneyEditing` 将内存变更与一个精确 persistence task 配对；失败 rollback 检查记录是否仍是本次提交结果，避免回滚后续编辑。工作区等待本次 persistence 结果后决定呈现；`RideLibrary` 保留 saveSequence、批次合并与错误发布，`RidePersistenceQueue` 管理操作先后；`RideStorage.swift` 独占磁盘实现。导入仍由 `ImportFlow` 单独拥有备份、preflight generation 和等待保存契约。
- **不变量**：AI 输出是候选，请求结束不等于保存；过期输入和取消不能发布候选；不复制认证状态、不扩大私人数据发送；普通编辑与导入保存确认语义分别保留；saveSequence、删除/备份排序、失败不截断后续写入、未启动批次合并和 store generation 不变。
- **验证入口**：Core 的 `JourneyCompletionTests.swift`、`JourneyThroughCompletionTests.swift`、`JourneyLifecycleTests.swift`；Application 的 `RideDraftValidationTests.swift`、`ImportPreflightTests.swift`、`ImportStagingTests.swift`；`tools/verify-subscription-auth.py`、`verify-subscription-service.py`、`verify-completion-request.py`、`verify-editor-validation.py`、`verify-store-ordering.py`；UI 的 `JourneyCompletionUITests.swift`、`JourneyTranslationUITests.swift`、`JourneySaveUITests.swift`、`WorkspaceEditingTests.swift`、`JourneyGroupUITests.swift`。使用本地替身，源码检查未向外发送真实行程。
- **源码结论**：请求、认证、服务、候选、编辑和写入已经有不同 owner。保留它们；不能把 AI request 提取记为整个编辑器迁移。编辑器保留输入与候选呈现组合；已核对的官方英文名、routeChoice/inference 和 StopEditor 局部任务保留现有 SwiftUI 生命周期；没有源码证据要求全面替换持久化框架或把所有 store 改成 actor。

### NewTrip → 历史可用性 → 草稿保存

- **owner / 调用链**：`NewTripView.planRoute` 拥有 routeIdentity、SwiftUI `.task(id:)` 与候选发布；`RailApplication/TripRouteValidation.validate` 接受不可变候选快照和注入的批量 resolver；App 的 `RiddenRouteStore.routeAvailabilities` 返回按输入顺序的 dated/undated 物理可用性，不写入路线。
- **历史日期契约**：NewTrip 仅在地区有 dated network 且日期不规范或早于最新 validFrom 时做此探测；当日/最新开通后候选不走此过滤。Application 仅将探测用本地副本临时设为 confirmed，以绕开 saved-ride pending 守卫，不改调用者草稿；整批 count 必须匹配才接受位置身份。dated 成功列入 physicallyResolvedIDs；dated 失败而 undated 成功才从 retainedIDs 移除。没有 draft、两者均失败、普通 resolver 错误或数量不匹配均保留候选但不提供物理证明；取消向上传递。NewTrip 在 await 后重新检查取消与 routeIdentity，再发布 retainedIDs 过滤后的候选、日期提示和 physicallyResolvedCorridorIDs；每次重新规划及换区先清空旧证明。
- **当前草稿契约**：`draft(for:)` 使用 `LocalJourneyAutofill.proposal` 后显式覆盖 routeConfirmation，只有 plannedIdentity 与当前 routeIdentity 相同且所选 corridor ID 有 dated 物理证明才设为 confirmed，其余为 pending；retainedIDs 本身不是确认。`stationCountText` 同样只在当前身份的物理证明存在时显示公里数。保持历史日期专用探测意味着当前/未来日期绕过验证的候选也保持 pending；未建立证明不能伪称 confirmed。Application 仅临时提升探测副本，保存仍使用 NewTrip 的最终草稿。此源码修正尚不能代替保存复读、精确里程排除及设备验收。
- **验证入口**：`RailApplicationTests/TripRouteValidationTests.swift`；当前 UI 有 `NewTripUITests` 的空草稿/禁存、多候选选择、通过站保存、取消流程，以及 `LocalJourneyAutofillUITests` 的显式 Keep Pending。测试存在不代表当前运行通过；历史日期批量过滤、身份过期和 NewTrip 未证明候选的 pending 保存状态没有在这些 UI 方法中直接断言。

### Route / Network → 地图挂载 / 发布

- **owner**：`RiddenRouteStore` 负责渐进路线加载、单旅程 resolve、history、cache 与 MainActor 发布；`RailNetworkStore` 负责地区 manifest、按视口显示网络加载、缓存/淘汰和显示 history。`RailMapController` 负责相机命令；Coordinator 保留 MKMapView 挂载、delegate 和平台应用。
- **当前物理边界**：App 的 GraphStore 显式 `.physicalRailway`，求解显式 `.physicalRail`；站群/同名/距离及 passenger-transfer 不能形成铁路 edge。未知身份按稳定源几何摘要隔离；已有轨道端点只有经证据目录和日期检查才可接续。输出仅使用源轨道顶点，不以显示站点或 continuity anchor 补线；直通服务显示继续使用独立 display-only registry。
- **覆盖证据**：五地区源属性身份清点为 756、共享顶点候选为 829；候选尚未逐条审查，永不自动作为 graph 输入。四个东京接续在完整日本源图均被接纳且拒绝 ID 为空。最新 18 项独立拓扑测试通过（包含于 40 项聚焦检查）不等于全网路线/设备/性能验收；缺少接续依据的路径应保留未解决状态。
- **已有地图边界**：`MapNetworkBuildState`、`MapNetworkGeometryCache`、`MapOverlayInstaller`、`MapLineGeometry`、`MapEndpointLabels`、`MapPlaybackLayer`、`RailMapAnnotations`；`MapInteractionCoordinator`、`MapRenderDiagnostics` 和 `MapStationLabelCoordinator`。各自负责命中缓存/交互、诊断状态和标签选举/调度缓存，不另存权威行程。`MapSelectedStationSnapshotController` 拥有选中旅程的 per-country station snapshot、单个 load task、countryInFlight 和 UUID ticket；Coordinator 注入当前 mount 身份与 didLoad 回调，保留选择、相机 intent、标注刷新/播放和手势期间延迟重建。nil 选择取消在途任务，换未缓存地区取消旧请求，已有缓存地区/同地区在途请求提前返回（已有缓存地区不取消另一地区在途请求）；完成时检查取消、ticket 和当前 MKMapView mount。tearDown 取消并清空 map-lifetime 缓存。
- **不变量**：loadRevision、per-ID ticket、manifest/request 身份、geometry generation/scale key；取消之外仍检查接纳身份；保持优先旅程、部分结果、缺区间真实状态、route cache 优先级、canonical WGS84/显示 datum 边界；保持样式更新与几何 rebuild 区分、builtRect/LOD/顶点预算、车道/连续笔画及播放期间延迟重建。没有直线回退，不通过伪造铁路连接求解；新接续目录必须有独立来源证据。
- **验证入口**：`RailCoreTests/PhysicalTopologyRoutingTests.swift`、`tools/build-physical-rail-topology.py --check`；`tools/verify-route-resolution-cancellation.py`、`verify-route-progress.py`、`verify-route-caches.py`、`verify-map-worker-lifecycle.py`、`verify-map-pan-geometry.py`、`verify-map-detail-fades.py`、`verify-ride-station-layering.py`、`verify-route-projection-performance.py`、`verify-station-lookups.py`、`verify-selected-station-snapshot.py`（真实 owner 配可控异步替身，覆盖复用/换区/清空选择/旧 mount/teardown 的晚完成，本次未运行）；Core 的 route/history/parity suites；UI 的 `MapCameraIntentTests.swift`、`MapLayerToggleTests.swift`、`MapDetailLevelTests.swift`、`MapLargeDatasetTests.swift`、`MapZoomPerformanceTests.swift`、`BasemapRenderingTests.swift`、`StationPresentationTests.swift`、`RouteStressTests.swift`。
- **源码结论**：提取后的地图仍需 Coordinator，不能以文件仍大断言边界无效。标签选举与调度的生命周期/缓存已核对并保留，annotation reconciliation 仍由平台协调器拥有；渲染性能与设备长时间交互需要单独验收。新整屏遮罩/独立铁路面属于计划 M，当前为 NO-GO、未实现，矩阵不宣称其完成。

## 2. 确认保留与剩余结构责任

| 当前事实 | S3 / S6 处理 |
| --- | --- |
| 共享 stores、单地图/播放器、scope 缓存已有权威 owner | 保留，验证实例身份和跨页路径；不再造平行状态 |
| Core parity 算法、SQLite 只读查询、History 已有规则边界 | 保留数值/日期/资源身份；不合并视觉相似的浮点实现 |
| Application 的匹配、导入 staging/preflight、draft validation 已有直接入口 | 记录实际调用方和包测试；不把包测试代替平台接线/保存验收 |
| 地图诊断/命中/标签/选中站点快照、AI 单请求、磁盘存储、quick-match、站点搜索和 Share Composer 渲染/导出已有 owner | 保留原入口单一路径及取消/缓存规则；旧分享请求 owner 已退役，历史 native-final PASS 不证明当前 owner 的完整门禁通过 |
| Workspace 保留跨区域组合；Editor 局部查询/发现任务的 scope/cancel 契约已核对 | 保留已有 SwiftUI 任务 owner；只有独立责任或明确缺陷证据成立时再提取 |
| North America 已下线，数据仅保留仓库备份 | 从保留功能和交付待办中移除北美编号、开关及兼容功能 |
| 统计分享、视频、日期/年份 scope 与设备合成行为互相连接 | 需要端到端设备验收；本次源码核对没有证明 UI 或产物等价 |

以上“剩余”不是未复现缺陷清单，也不自动要求引入新模块。`source-ownership.json` 已结合 target 成员核验当前全部生产 Swift 文件，动态清单数量以检查器输出为准；本表补充功能链覆盖。

## 3. 未完成的 UI 与性能验收

下列为整体验收范围，尚未全部完成；2026-09-07 的历史验收不作当前豁免。本次地图选择、时刻表日期/服务变化、iPad 日期范围/取消日期/分类互斥 UI 已通过，iPad 播放控件命中失败在隔离 HEAD 基线复现。最新 iPhone/iPad 字号及 Catalyst 嵌套编辑取消通过；七条修复定向 UI 流程分别通过，历史失败记录保留，完整 UI suite 尚未销账。具体结果以 [执行记录](refactor-execution-2026-10-03.md) 为准，其余范围不视为通过。

1. iPhone（仅竖屏）：搜索/日期/行程组 → 详情/编辑 → 返回，选择、滚动和菜单状态保留；错误保存仍展示准确结果。
2. wide iPad：多列布局/横竖屏/面板拖动/地图交互，重测历史地图 toggle hittability；Mac Catalyst 分别记录构建和实际交互。
3. Passport：地区/年份/日期/行程组切换，地图与卡片/回放队列一致；旅程删除/重命名/运营商修改后校验 passport-only 路径和内容。
4. 分享：明暗统计与地图图像、旅程分享、系统分享取消；生成过程中切 scope/删记录/离开页面；检查实际文件和无障碍说明。
5. 播放/视频：跨 tab 继续播放；取消录制保持播放；启动、取消、失败、完成与再次导出；减少动态效果；检查视频时长/内容和资源释放。
6. 编辑/导入/AI：使用替身验证输入变化/取消后旧候选不覆盖 draft；显式 Apply 后才进入普通保存；保存失败与后续编辑交错；导入 preflight 后 store 改变、备份挂起和取消；活动地区的数据管理与写入交错。
7. History/Timetable：当前/历史日期与不同地区输入，午夜服务日、自动/手动查询、快速更改输入、选中后取消；候选回到编辑器并保存后复读。
8. 设置/本地化：永久 `.xSmall ... .xLarge` 范围内布局、偏好持久性、文案 fallback、读音、主题、减少透明度/增强对比度/VoiceOver；显示改变不改身份键或序列化数字。
9. 地图：相同固定输入的 geometry/style/hit，连续 pan/zoom/旋转/重挂载、播放时选择/切层、低/高 LOD、站点标签避让和大数据范围；M 的整屏遮罩与相机同步另列验收。
10. 性能：同工具链/设备/资源 revision/缓存条件记录重复基线；冷/热启动、首条可用路线、求解、matching、发布/安装、帧时 p50/p95/p99、峰值内存和反复进入/退出保留量。用 `RailSignpost`、`ios/tools/bench`、地图/route 性能入口；阈值在候选结果前冻结。匹配提取本身未获得性能提升证明。

## 4. S6 销账条件

最终报告应把源码所有权、包/生产 harness 测试、app/Catalyst 构建、设备 UI、性能和资源往返分别登记。每条链至少填写当前入口、关键错误/取消路径、实际执行命令、结果和未验原因。检查工具的路径型契约随 owner 等价迁移，不能删检查换取通过；用户数据执行旧读→新编辑保存→旧读回退验证。临时适配列清单并删除或说明长期理由。

本次矩阵区分源码责任、独立测试和当前未收口的完整验证；**不宣称 S3 全部迁移、S6 整体验收或 M 渲染替换完成**。


### 2026-10-09 本次继续执行的最终收据

统计索引完成一个 country/merged/scoped 共享缓存槽、独立单 permit、构建任务内发布、携带 N02 分母计数，以及日本裁剪后释放完整结果的改造。7 组真实 actor 生命周期检查通过；ready 接口已适配缓存归属。固定 host 合成负载的结束 footprint 从 38,846,992 bytes 降至 12,681,720 bytes（67.35%），125,000 边与总里程一致；不是整 App/Release 峰值，不与其他缓存降幅相加。

分享保留 CLI 新增预览/完整导出行为，34 项生命周期检查通过。设备复跑先发现 Japan 分区菜单操作变化，再复现挂载前读取本地化环境导致的票面崩溃；已让票面在正常 View body 中渲染。地区、日期、票面和导出路径复跑通过（48.329s）。此前四条 NewTrip 与地图选择通过，六条定向流程分轮都有通过收据；完整 UI suite 未通过验收。

当前 App 构建无 RailMap 源码 warnings，bundle 契约、源码/字号边界及 10 组当前 native 契约通过。聚焦包 9 Core + 9 Application 通过，完整采样峰值 218,202,832 bytes。非历史整包在真实历史日本图查询中触及 2 GiB 运行保护线（2,152,876,456 bytes），已终止仅本任务的 runner/子进程，不记为通过。保护器已修正为阻止 SwiftPM 接着启动未受保护的测试二进制。

详见执行记录及 `outputs/refactor-20261009-resume/`。Release 整 App 内存对照、大负载整套测试、资源干净/增量身份复验与回退读写验收继续未销账；M 仍 NO-GO，全屏 dimming 未实现。不得标记全部重构完成。

#### 2026-10-09 资源与 Release 实测续接

资源干净／增量重复已通过：1,086 个打包文件逐字节相同，输入摘要及几何载荷保留，构建时间信息移至构建日志。证据：`outputs/refactor-20261009-resume/resource-clean-incremental-final.json`。Release 基线已构建通过；独立模拟器的真实五地区统计内存对照正在执行，预先规定三次新进程中位数稳定内存必须下降、峰值中位数不得上升。此项在全部设备测试及采样完成前保持待验证；完整大资料测试及 S6 仍未通过。

#### Release 内存对照通过（合并分配优化后）

独立模拟器上的真实五地区统计工作流，基线／改造各三次新进程、全部六次 Release UI 测试通过。稳定 footprint 中位数 **327.5 → 239.5 MB，降低 26.9%**；进程峰值中位数 **376.4 → 311.4 MB，降低 17.3%**。预先声明的稳定内存下降、峰值不得上升门禁通过。`release-merge-allocation/` 保留逐次采样、输入摘要、协议和结果包；只对该统计工作流与该设备／运行时成立，未外推到所有页面／实机。首次缓存生命周期版峰值门禁失败收据保留，之后通过实际合并临时分配优化再测，未修改门限。两份 Release 包也与干净／增量资源基准 1,086 文件逐字节一致。

#### 有界编译缓存与回滚合同续接

图的 `.bounded` 策略同时清除超过节点预算的编译顶点表，且在站点增强前释放；`.standard` 保持旧行为。26 项图／物理拓扑／端点检查通过，新增真实 surveyed 夹具的释放后再次构建检查也通过，完整节点、元资料、网格、有序邻接和拒绝原因相同。同策略宿主对照驻留 25.2 → 7.6 MB（-70.1%），返回节点／边／摘要相同；不与 Release App 百分比相加。全国历史单例仍在约 2.24 GiB 被预算监测停止，完整大资料验收仍未通过。

固定仓库基线 `14d294653fa11e87b6fbfbe3b4eba43f40b65225` 的真实存储代码独立编译后，当前写入 → 基线读取写入 → 当前读取全部通过，五地区身份、已乘坐标记、路线待确认及最终标准 JSON 字节不变。只验证该仓库基线，未外推到未测试的 App Store 版本。当前 Release 整合复核正在进行。

最新整合 Release（包括编译备忘释放）构建通过，五地区公共统计页复核 19.592 秒通过，最终包资源 1,086 个文件再次与基准一致。当前生产来源 280 文件与永久字体范围检查通过。总状态收据为 `outputs/refactor-20261009-resume/current-validation-summary.json`；S6／整份路线图仍不标记完成。
