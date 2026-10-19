# 北陸線-p1 尖角修复：独立源码审查

审查日期：2026-10-18。对象：`app/scripts/railway/repair-hokuriku-p1-loop-display.mjs`、对应 `tests/hokuriku-p1-loop-display.test.mjs`，及其直接生产解码、parts 与写入依赖。结论：未发现阻止当前候选应用的具体源码问题。

父会话在本轮源码审查后于 2026-10-18 报告已执行生产 `--apply` 成功；应用由父会话执行，非本审查者执行。本审查者仅做源码阅读与有限内存数据查询，未执行修复 CLI、生产写入、测试、构建、原生应用或 UI。父会话的 34/34 candidate 原生配对审图属于独立证据，本记录不把源码阅读当作像素或运行时证明。父会话随后正在执行的 Swift regression 结果不在本记录中预先宣称通过。

## 源码结论

- **同线弧线与接回点**（修复脚本 29–65 行）：限定 owner、完整 owning line 摘要、原 crossing splice、N02 feature 9616 的铁路/公司/完整摘要；采用该 feature 原始完整弧线，再接回原 suffix。未移动两端站锚，未改 canonical segments 或 km。原始前缀中的假折点不再参与显示，未通过圆角掩盖错误走向。
- **旧前缀替代关系**（84–119 行）：删除原 0–3475 m follow 和 0–3175 m family window；保留的 suffix follow/family 界点按新旧显示链总长差平移。此次变化全部位于这些 suffix 界点之前，因此同一地理界点保持不动；末端 family 保留旧 9726.8 m 的舍入界点，没有擅自延长到精确链长。
- **parts**（102 行；`build-display-lanes.mjs:458`）：通过现有 `displayPartsForLine` 与 `partRowsForLine` 生成实际显示链。此例 canonical interval 与 display override 不同，parts 使用既有 complex 行格式保存显示坐标，而非错误引用原 132 点 canonical interval。当前候选为一条 138 点链；同一既有消费者负责解释该格式。
- **方向**（61–62、128–134、153–164 行）：loop 改为 up，base 对应区间改为 down，同时更新方向主源，station order 仍为 up。[JR 西日本官方说明](https://www.westjr.co.jp/company/info/issue/bsignal/26_vol_207/area/) 明确 loop 上行列车从桥上跨过开往敦贺的下行线。该修改会有意改变 `rail-network.js:2405` 的 interval traversal 许可；不能笼统声称所有 routing 行为不变。
- **重复应用与生产写入**（31–39、64–65、105–115、133、147–149、159–163、167–190 行）：接受旧状态或精确已修状态，拒绝未知 owner/override/lanes/provenance；插入新 owner 行后移除旧 owner 行，保留无关行顺序。`applyPreparedWrites` 在任何写入前比较全部读取输入与目标的精确快照（`repair-three-reversal-extents.mjs:233–246`）。这些是当前源码审查结论，不代表此处重新执行过幂等或文件写入测试。

## Canonical 层边界

有限原始数据核对确认：9616 的末点 J `[136.08196,35.61644]` 等于旧 source[41]；下一点 K `[136.08184,35.61634]` 是同公司同线 feature 9644 的反向相邻边。原 suffix 后续边也可在同公司同线 N02 sections 9629、9633、9644、9646 中逐边找到，仅末端站锚接线不是原始 N02 相邻边。但 J 同时也是 9637 与 9640 的端点，坐标相等本身不证明允许换轨；官方说明进一步表明这里存在上下跨越。

这足以支持本轮显示链与方向修正，但不能把它提升为完整 canonical 物理链、站锚接线和里程重新验收。敦贺固定锚至 9616 首点的接线也未在此次证明为原始 feature 相邻边。父会话报告 canonical 存储 km 为 9.718，旧坐标 Haversine 约 9.715906 km，新坐标约 9.798350 km；本脚本的 display ruler 使用既有局部平面距离，其旧/新长度分别约 9726.821587/9809.358256 m，不能混用两种尺来直接覆盖 km。

因此本轮保留 canonical segments/km、修正显示投影是合理的有界处理。物理区间与显示投影在现有系统承担不同职责，不构成重复实现。后续若证明完整 canonical chain、两端站锚接线及 km/section/graph 依赖，再将修正落实 canonical 并去掉不再必要的 override。当前记录不声称 retained southern-loop offsets 或 station platform caps 已验收。
