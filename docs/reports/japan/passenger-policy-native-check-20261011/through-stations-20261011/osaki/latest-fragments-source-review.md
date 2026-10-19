# 大崎剩余碎线：源与呈现合同审查（2026-10-12）

范围：只读检查当前 jp-2025.json、display-lanes.json、源 builder/helper、Web/Swift 消费路径。用户目标是站南两根独立客运进路在有依据的共同走廊汇为一根进入大崎，站北一根代表线离开。未在本审查运行主图、编译或测试；像素归因须由 root 的最新本体验证。

## 当前数据与根因候选

- JR 大崎支线 base/p1 各有两个 Web display parts：#0 从同一客运 5–8 站台代表点 [139.72790971877015,35.61979469682823] 向南，#1 从两个不同的 source-backed 北岔点分别走 139.36 m／265.94 m 回到该代表点。#1 的首点分别为 [139.727308,35.6209449] 和 [139.7266308,35.6219452]。两条独立北进路本身并非重复点噪声。
- repairOsakiLanes 仅给 #0 配 family 窗口和 follows：p1 在 0–1635.49 m 是 base 的 tenant；两条南尾分别直接 follow 总武线-3，且作为共享尾 tenant。base 在南 body 0–1659.93 m 是 landlord。#1 两行 lane 0，但没有 family window 或 follow，所以 native MapLineGeometry.swift 的无 family 分支完整绘制两个北进路。这是站北多根短碎线的静态源合同候选，不应靠最终渲染器合并近邻去掩盖。
- 两根北 #1 均在站台代表点与南 #0 精确相接，但各自北端止于不同岔点。displayNorthJoin 只存在于 package 元数据，Web stroke exporter/native loader 没有消费该字段；历史 ledger 也明确“北仍两个 parts，metadata 无 consumer”。因此该字段不保证独立 part 的视觉接续，也未提供向北沿山手货物线的单一延伸。repair-tokyo-southern-branches.py 在本轮移除了 displayFreightMainPolicy，而已保存的 source constraints 指定两个北岔点都在 freightMain source 顶点、应将 station-free main part 仅用一次。
- 临海线是不同公司，在同一 5–8 客运站台代表点保留自身成员与圆点，独立自南东方向进入；山手电车线使用另一组站台。临海线 #0 没有 Osaki family/follow，不能仅凭本站坐标相等吞并其公司线，也不能将山手线作为北接续。
- 南尾已有明确 landlord/tenant 抑重复：若最新本体仍在南侧显示碎段，优先核查实际 bundle 的 current compact/lanes 与 #0 family/follows 是否匹配、resident owner fallback 是否切断、主图 zoom/viewport；不能依据这些源行推断已有南侧重复源线。旧 native 截图有限，不证明当前用户观察的完整站区已通过。

## 建议的 owning-layer 修复

优先在 repair-tokyo-southern-branches.py 的显示输入及 repair-shinagawa-display-lanes.mjs --osaki 的对应尺/窗口上完成一根 JR 北代表走廊：从已审查 5–8 站台点沿所选 source-backed 北 lead 到其山手货物线精确岔点，再沿 freightMain 中确属当前客运代表范围的实测连续支持向北。给该代表 owner 的每一段一致的颜色/车道/接点；另一方向 #1 只在有官方站台组和实测共用走廊依据的窗口作为 tenant，必要时保留真实、独立的北岔分离段。用户要的“一根”是站区显示概括，不是删除 physical direction、变更 segment/station/mileage、把两岔点物理焊接，或跨公司合并。若要压下另一方向整段北 lead，须明确记录其显示代表合同，并验证该区域确属同一站台组的代表范围；若两真实岔路在目标 zoom 仍应分开，不能仅为线数强行收敛。

一个较小但不完整的显示候选是对 p1 #1 加审查过的 tenant/follow 到 base #1，并将 base #1 加 landlord；这会消除站体上两根北短线，却仍可能留下 base 北岔处的悬空末端，也可能抹掉两个源岔点之间真实的分离。因此它不能单独作为“北边出去一根”验收，须把 source-backed station-free north continuation 与整段本体观测一并处理。不要直接以近邻 snap、自动合并 displayPartsForLine 或通用 renderer merge 解决。

## 最小回归与验收

1. 扩展现有 app/tests/tokyo-platform-approaches.test.mjs 的 Osaki 行为断言：复放修复后，南部在两条有据岔支外呈两根、共同 JR body 只有一个 landlord/对应 tenant，站台进出代表点一致；北 #1/station-free extension 的可见窗口只产生一个 JR owner，其端点沿实测北源连续，且 p1 没有无主剩余 ink。用实际 Web stroke model 的 parts/window/measure 检查，不能只检查原始 JSON 字段存在。
2. 继续断言 JR stations/segments、方向、northJunction 和真实南 forks 不变；山手与临海各自身份、圆点和独立成员保留。照旧让 helper replay 幂等。
3. 仅在出现 native/Web 语义差异时，使用现有 Swift family/continuity 聚焦回归。root 独占增量 build 与同 camera 的主图 network/basemap 站南合流、站台、站北离开三视窗；Inspector 零 lane 不能替代本体。记录真实 zoom、bundle input 与可见 fragment 数；不推及全站轨道逐根精度。

参考：JRTT 工事誌 PDF p207（本地 sources/README.md）：临海线在南侧约 800m 插入大崎支线上下行之间，新增 2 面 4 线与埼京直通，山手电车线独立。它证明历史构型，不单独证明每条当下岔线运营状态。当前客运身份另见 JR 大崎站官方页面和时刻表（同索引）。

## 2026-10-12 主图反馈后的具体映射与修正方案

Root 现时主图观察：桥附近有两根短绿线独立终止，旁边另有一根长的山手线绿线持续向北。当前共享目录中的最新截图文件在本审查 host 尚未出现；下述像素位置依据 root 的直接观察，几何 ID 映射由当前 package 定向查询支持，尚非本审查亲自看图的像素认证。

目标窗口里，短绿线分别是大崎支线 base#1（北端 [139.727308,35.6209449]，长度 139.36m）与 p1#1（北端 [139.7266308,35.6219452]，长度 265.94m）；均从共同 JR 5–8 显示点 [139.72790971877015,35.61979469682823] 延出，彼此没有 family/follow。长绿线是山手线 #0，站点原顶点 [139.728245,35.619945]，其南北邻点 [139.72888,35.61912] / [139.72761,35.62077]，穿过站区且在该窗口 lane=0。两根南进路在当前视窗对应山手 #0 南段与大崎支线的共享代表 base#0；p1#0 是已有 tenant，不应再作为第三根 JR 南墨线。临海线独立公司另计、保持其线和圆点。

用户这次明确指定本地 JR 呈现为“南 2 →站前汇 1→北 1”，因此此前提议恢复一条独立山手货物线北延会制造第二根北 JR 线，不能作为本次默认方案。具体 owner 应选已完整向北连续的山手 #0。呈现层把 base#0 在站前一个**有明示坐标和长度的显示汇合窗口**渐入山手 #0，终点落在山手已有 source 顶点/受保护区间；从汇合点经大崎至北侧只画山手 owner。大崎支线 base/p1 两条 #1 北 lead 在显示部分全部退役，保留原 physical northLeadInGeometry、direction、northJunction 与拓扑资料供路径求解/审计，不把它们继续生成可画 station-free part。该处理是用户要求的 local schematic 共用代表线；必须明示它跨过原 1–4 与 5–8 平台走廊约数十米，不可把像素贴合称为实际共轨或物理交叉。

选定汇合点不能按“最近一根轨”自动 snap。可审查的起始候选为山手已有站南顶点 [139.72888,35.61912]（当前山手 ruler 约 1974.82m，站点 [139.728245,35.619945] 约 2083.03m，站北邻点约 2191.25m）。大崎支线 body 从站南的 [139.7279953783,35.6196828891]、[139.7283045524,35.6193129888]、[139.7284955252,35.6191000156] 沿 source approach 向南；应由保存的官方站区图和同 camera basemap 决定在哪个已审查支持点开始向山手南段过渡。其后 branch #0 的站端 0..joinMeasure 成为山手 #0 的 tenant/follow（reverse measure mapping 要与 branch 从站向南的方向相反）；山手在对应南段..站点..北段是唯一可见 owner。若沿用 branch 5–8 站点作为逻辑 member，则站点圆点 owner 可给山手，branch 的 displayStationCoordinates 需与实际绘制的 tenant 端点一致，卡片仍列 branch；Rinkai 的跨公司 displayStationCoordinates、lineID、原 lane/profile 与圆点保持原状。不能只删 #1 而让 branch #0 在原 5–8 点封口；那会留下 30m 级站内断口/短 stub。

实现范围首选源 builder 中大崎专用显示 override（physical rows 不动）与 repairOsakiLanes 对新 #0 ruler、reverse follow 和 same-JR family 窗口的派生修复；必要时明确删除不再使用的 displayNorthJoin 元数据。不要改通用 renderer 去按距离合并，也不要借 stationCircleOwner 隐藏仍在画的 line。当前 Osaki focused JS 测试把两条 #1 均存在固定为旧合同，需改成验证**成品 visible stroke**：在站南分支窗口正好两个 JR component 进入已审查汇合点；汇合点到大崎站点再向北跨桥范围只有一条连续 JR owner；无 #1 绿 cap、无 branch 站脚 stub、所有边界有同一显示坐标与 lane=0。可以调用现有 Web stroke model/renderer 可见区间接口或当前 Swift ContinuousStroke 成品切片作聚焦测试；仅检查 parts/family 元数据并不足够。另断言 physical 双方向及两 northJunction、南真 fork、Rinkai 公司身份、各逻辑成员及所选日期不变。成品主图同 camera network/basemap 验证由 root 负责。

风险与依赖：山手原站点源点和大崎支线 5–8 代表点是不同平台组。局部汇合需要用户本次明确的简图合同支持，资料中的 JRTT 站图说明它是显示概括而非轨道连接。先由 root 用实际主图截图确认汇合点/窗口与当前 basemap 的视觉关系，再改源；并按当前 bundle 确认南侧已有 tenant/owner 真正在运行。
