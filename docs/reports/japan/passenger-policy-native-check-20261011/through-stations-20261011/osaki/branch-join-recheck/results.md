# 大崎支线接头复查（2026-10-12）

用户第72–74条要求继续原唯一列表、完整区间检查，并重新报告大崎支线连接错位及同类问题。此前站区碎线数量验收重新打开；本次生产接头结果以本页为准。

用户进一步确认：站南两线合流与南侧总武／横须贺分岔两处都有问题，均列入本次范围。

## 原因与采用变更

站南 ownership 在215.48米交接，但 branch lane 从300米起的三角渐变已提前渗入，最终接头相差约0.348px。lane 过渡移到站南合流与南叉中点，保留两端缓冲。

p1 此前以不同显示测距跟随 base，并在两个相距8.12米的南叉点间切 canonical；原生产 p1 在z18/19的接头偏移约16.75/33.47px。两方向现在采用同一已复查 JR 代表显示路径和测距，原始 physical 方向轨、junction、stations、segments、里程和通行权限保持。

仅令路径相同仍不足：identity body follow 在重叠的300米 blend 中稀释直接 Yamanote/Sobu 跟随，完整每10米 probe 在中段发现z19约36.06px偏移。Swift/JavaScript 现只在对应边界、完整 points 和 measures 全部精确相同的情况下略过冗余几何替换；原 follow 数据保留给 Main family coverage，避免删除后 fallback 重复出线。

Owning files 为 repair-tokyo-southern-branches.py、repair-shinagawa-display-lanes.mjs、rail-stroke.js 及 ContinuousStroke.swift。package 实际只有 p1 显示字段及本修复归属说明变化，所有物理 stations/segments 和其他线路保留；仅四个既有名称产物的 inputSha256 依赖引用刷新。

## 失败尝试与回归

新 JS 生产回归先重现站南 lane 接头失败；改 lane 后又重现 p1 南叉失败。仅检查端点的路径统一候选曾通过，但新增每10米整段回归在120米处失败；加入双端一致的 identity filter 后三项 Osaki 回归通过。真实 dense 对比 p1/base 全线最大约7.45e-8px；这是生产数学路径对比，不是 Apple 地理精度。

删除 p1→base follow 会让 Main 缺少 family coverage 映射而重新绘制 tenant，故没有采用。缩短 follow 并缩小 tenant 会暴露第二条西侧方向轨，不符合既定代表显示要求。没有增加 schema 或重建全国验证流程。

## 完整 before 检查

三个专用 Mac app 串行取证：base 完整9点、p1 完整9点、品川→大崎7点、大崎→五反田4点、品川→西大井12点，共5完整区间41视点。全部人工查看三联底图/显示/平滑，未见中心线层面断口、回折或走错交叉。该结果未包括 production lanes，不能替代本次 Main 验收。

原始证据：`/private/tmp/jtm-osaki-branch-join-evidence`、`jtm-osaki-branch-join-pair-evidence`、`jtm-osaki-branch-join-owner-evidence`；三联页在本目录。owner 的005034来自搜索#1误匹配#15的6个额外过程点，不计请求范围；实际所求005028已另行选择站对并完整查看4点。后续稳定 ID 搜索须再核对实际起讫站，不能把子串结果当精确键。

Main before 同相机35.6176,139.729,.008的ON/OFF证据保存在 station-merge-*；一次拖图惯性移动到另一地区，已正常重开指定相机，未用错误视野作验收。

## 最终原生验收

已完成本次两处接头修复与实际验收。三个专用 Mac app 更新后串行重新采集相同5个完整区间41视点（base9、p1 9、Yamanote两区间7+4、Sobu品川→西大井12），失败0；final-native/review.md记录41/41、123面板全部人工查看。零lane Inspector用于地理和中心线检查，最终接头以Main证据及production回归为准。

Main与Inspector增量构建成功，三个独立Inspector的完整二进制/dylib及compact已同步并重签。Main实际包compact与源一致，编译display payload两方向75顶点一致，family coverage依赖保留。Main已实查站南合流35.6183,139.7295,.004、南侧Sobu分岔35.60885,139.725408,.004及五区间整体35.6155,139.732,.04；main-final保存ON/OFF截图/AX。南二线平顺汇入站内一条JR代表，北侧一条保留；南叉连续接入Sobu代表，没有重新打开p1碎线。实际大崎成员卡保留大崎支线、山手、临海三成员。三视野budgetDrops均0；未测量运行/跟车性能。

JS Osaki三个聚焦回归通过；新Swift exactIdentity回归通过。旧测试失败如下，未以局部通过声称整套全绿。

原生新回归 `exactIdentityFollowDoesNotDiluteOverlappingAlignment` 已通过；同一 `ContinuousStrokeParityTests` 文件19项运行有166 issues，涉及旧 fixture parity/fillet radius/sampling，不能记为全文件通过。现有57个 fixture 中没有任何 exact identity follow；最先的圆弧失败无 follows，最先总武-2 parity case 的 bounds/points/measures 都不同，新 filter 对这些 case 不改变执行路径。JS既有 geometry 文件的 well-formed 单项通过、旧 rounded sampling 单项失败。保留完整日志，不改旧圆弧逻辑或重生 fixtures。首次默认 `.build` 因资源 Finder/signing detritus 失败，使用既有 `/private/tmp/jtm-inspection-kit-tests` 完成同一聚焦检查。
