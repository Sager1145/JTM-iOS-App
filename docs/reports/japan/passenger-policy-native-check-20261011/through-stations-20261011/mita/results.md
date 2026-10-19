# 都营三田线显示纠正结果 — 2026-10-12

用户确认范围为西高岛平—目黑，27 站、26 个完整区间。最终按用户指定的简单底图线路对齐目标验收：20 个地下显示区间（6–25）纠正，已近对齐的北端 0–5 保留。物理站点、区间、站序、里程和其它线路保持；目黑注册端点不变，南北线共享跟随及两组 lane 测距按相同站间范围重新映射。

## 依据与被否定的方法

全线 before 的 115 个视点已全部人工查看，8 个新捕捉、107 个严格匹配依赖的既有 native 证据复用；见 `whole-line-before/{coverage.json,north-review.md,south-review.md}`。来源追踪与当前 compiled Main owner/index 排除整线坐标系平移及错误缓存。北段原生实体铁路抽离 86% 支持、中位 2.4m/P95 3.4m；区域航拍保存在 `primary-sources/aerial`。

OSM 两方向客运关系用于确认身份。其整线中点候选在白山弯道偏到另一侧，部分 stop_position 中点与既有站点相距百米，因此该候选未采用。实际采用的 owner 是 `app/scripts/railway/repair-mita-apple-display.mjs`，不是 `repair-mita-display.mjs` 的 OSM 诊断候选。

原生新增独立的「地铁示意线」模式识别蓝色线路，保留实体黑色成对铁轨模式；使用文字遮罩、窄色峰、连续性和竞争候选排除道路、建筑与其它线路。分析快照采用对比度稳定的浅色样式，交互地图样式保留。全线 115 张原有干净快照的宽范围分析原件保存在 `cartography-analysis`，冻结有效样本与来源保存在 `mita-apple-display-evidence.json`。

首版拟合在文字缺口归零到旧 N02，产生三角折线，未采用。最终在同一已确认的简单走廊中由顺向相邻像素控制和切线衔接；较大/竞争缺口保留未确认处理。三田—白金高轮的清晰底图弧线超过 40 米搜索范围，最终该区间允许 80 米窗口，实际最大改正约 54.83 米；其它区间保持 40 米改正上界。旧校园侧切线已消失。

## 完整 native 与主 app 复查

最终 26 个区间重新捕捉 115/115 个 native 视点、失败 0，均人工查看，包括端点及短尾。`whole-line-final/{coverage.json,north-review.md,south-review.md}` 是具体覆盖依据。没有以捕捉计数代替目视结论。

三个专用 app 按顺序检查后进入 Main：第一 app 完成全线新捕捉；第二 app 独立整线预览及白山弯道抽离（76% 有效支持、中位 0.0m/P95 1.9m）；第三 app 三田西侧抽离（51% 有效支持、中位 0.0m/P95 约1.0m），实际原生导出为 `extraction-final/mita-south-native`。这些数值只针对各自有效像素与实际相机，不是整线精度统计，也不与不同相机的 before 指标直接相减。

Main 一次增量构建成功：`/private/tmp/jtm-mita-main-build.log`。实际 bundled compact 与源一致；compiled Mita chunk 身份正确、825 个顶点、27 站，南北线 manifest 仍依赖三田线。三个 Inspector 最终资源与源一致且重签。

`main-final` 保存实际 Network ON/OFF 配对：整线、北端、板桥—巢鸭、中央、日比谷—三田、目黑共享段，加白山同相机近景与三田西侧近景。五个重叠区域覆盖全线；白山卡为都营成员，白金高轮卡保留三田线与南北线。生产共享平行、圆点、站间接续均实际查看，未见新断口或回折。

最终 Main 保持运行，camera `35.6465,139.742,.016`，Network ON，12 lines/12 overlays、budgetDrops 0。正确最终证据为 `main-final/left-running-final-*`。一次旧成员卡窗口被当作最终相机的尝试仅保留为 `mita-west-stale-card-process-*`，明确关闭卡片并重新选定最终实例后完成有效配对，不作验收依据。

## 定向验证与经验

显示 owner 回归 6/6 通过，实体/地铁示意线抽离回归 6/6 通过。覆盖来源/竞争拒绝、原物理数据与其它线路保存、所有站间接缝、共享测距映射、精确重放及白山文字缺口三角折线回归。Swift 与 JavaScript 显示 override 的消费路径、native cache/bundle 身份在 chat 中复查。

验收针对请求的底图显示对齐，不把地下蓝色示意线当作工程测绘。卡片仍显示既有英语标签 `Sanda Line`；这是另一个名称问题，记录待单独纠正，本次不扩大显示几何修复范围。

每次修复经验汇总为 `../repair-lessons-20261012.md`；全局铁路纠正 `SKILL.md` 与中文经验参考已更新。默认全国批次保持停止，旧 receipts/checkpoint 保留，没有新的全国自动检查或提交/推送。
