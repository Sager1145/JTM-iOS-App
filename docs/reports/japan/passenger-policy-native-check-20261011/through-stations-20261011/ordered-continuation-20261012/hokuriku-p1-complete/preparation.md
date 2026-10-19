# #33 北陸線-p1 — 准备范围，未开始原生审查

从原列表unique首次lineID顺序核对为#33。冻结当前owning row于source-line.json：敦賀010186→新疋田004256，1完整区间132个源点；两个端点与本线站坐标一致。alignmentOf=jp-西日本旅客鉄道-北陸線，alignmentRole=paired_alignment，alignmentDirection=down，stationOrderDirection=up。这些是source记录；不能因站序方向与单向线形方向不同就倒转/拉直几何，也不能吸到另一方向铁路。真实进站—穿站—出站走向必须沿本线客运轨道及自有蓝色平台组追踪。

定点代码阅读：RailwayDirection.allowedDirections与Web intervalDirections对当前本线的down/up组合均只允许逆stored-order遍历。这不是本轮运行route solve或运营资料验证，单线地图仍需检查自身完整形状、两端接续及邻线独立性。

已准备diagnostic-request.json：统一app alignment/capture，仅exact lineID与intervalIndices[0]，新会话，不接入旧三套receipt。尚未执行，未产生capture/result或像素结论。须先完成#32选择性Main最终检查，并等待集成聊天交还UI/重型任务。无需为本线机械生成三app矩阵。

## Current identity context before native capture

Exact p1 has alignmentOf/railwayIdentity `jp-西日本旅客鉄道-北陸線`, alignmentRole=paired_alignment, alignmentDirection=down, stationOrderDirection=up. Do not infer down-travel direction from its stored station order 敦賀→新疋田. This two-station fragment is not authority to treat either station as a true operating terminus.

Tsuruga010186 has distinct own station coordinates across Hapi-line, Hokuriku Shinkansen and Obama Line. Base Hokuriku and p1 share [136.076639,35.644993]; Shin-Hikida004256 is shared only by base and p1 at [136.10069,35.59421]. Shared anchors alone do not prove platform extent or physical switching. Review the paired alignment's own approach and mountain-body continuation, excluding Hapi/Shinkansen/Obama directions and purple transfer geometry. Scope is only p1; no base-line acceptance transfers automatically.
