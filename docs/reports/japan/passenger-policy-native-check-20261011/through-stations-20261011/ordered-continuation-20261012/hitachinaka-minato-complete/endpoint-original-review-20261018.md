# 湊線两端完整区间原图复核 — 2026-10-18

**已实际查看#0全部4对、#9全部3对，共7对/14张原图，0漏看。未发现可确权的孤立假 V；终端帽位与胜田自有平台方向仍未证实，不提出坐标或删点候选。** 没有把未看其余区间算作全线通过。

范围仅 `jp-ひたちなか海浜鉄道-湊線` 阿字ヶ浦002298→磯崎002306（#0）、工機前002292→勝田002280（#9）。复用 `preparation-20261018.md` 的53/53旧 receipt 身份/文件准备；本次实际逐张打开#0 p0..3、#9 p0..2 的全部 basemap/smooth 原图，detail=original，没有拼图替代。其余46对未查看。没有为凑覆盖扩展#1/#8；现有证据尚不能支持关联站点方向变更，已看图中的相邻上下文不算完整邻区间覆盖。

## 实际原图发现

**阿字ヶ浦端：** p0自有终端多轨/站框与向南出发可见，红线从站区南部上下文离站；但蓝色长铁路 casing、侧线/缓冲器与窄乘降台面未在 z17 完整分开。完整 own 乘降平台双帽与纵向中心尚未核定，不能把最北可见轨末当平台帽，也不能凭长填色的中点移动站点。当前显示终端中心准确性不接受，但没有从此概览估算新 WGS 点。

p1/2真实东南复合大弯连续，保留了北南→东南→东向→南向的真实走向；没有孤立 V、回头钩或道路替代。磯崎北侧弯线红色比本线图示轨道偏东，p3站位附近也有小东向侧差；曲线和端点保持连续。需要 own 代表轨/平台帽位才能定偏移来源，不能仅删一角拉直真实弯道。p3下方相邻#1上下文可见，但本次未据此变更#1或增加其审图计数。

**工机前—胜田端：** p0保留工机前向北的 own 弯线，与更西侧 JR 常磐线群轨分开，没有直接改走 JR 的尖接。p1/2红色北端进站线持续位于蓝色群轨/站区东侧，部分落在相邻街路/建筑边上下文；它是需要 own 客运轨与短平台绑定的进站/终点对齐线索，而不是已证实可吸附的最近蓝轨。p2旧终点在快照 `(512,384)`，相对群轨东侧和共站大结构偏南；共享车站填色不能作为湊线独立平台框，更未把 JR 长平台拿来充当 own 短平台。没有得出完整 own 胜田站帽位或精确纵向中心。

#9所需下一来源是 **own 湊线客运 way 链/自有胜田短站台及北向进站轨的显式绑定**，然后再检查完整帽位和本区间连接。JR 轨道、旁边道路及共同站名不能作为替代方向。#0则需自有阿字ヶ浦乘降台面与侧线尾段的端限区分。这两项来源缺口不等于整个线路几何已错误，也不使现状获得接受。

## 当前控制与原始来源

只读重新确认当前#0/#9 decoded source/display 坐标 IEEE bits 与每个 receipt 所引用的 named immutable identity plan 一致，站ID也一致；当前 own 无 displayStationCoordinates/displayIntervalCoordinates。因此原图可作这两个当前输入的历史几何观察，仍受旧渲染合同限制。

#0原控制21点，公里0.922：`app/data/rail-sections.json` feature21315（N02_003湊線/N02_004ひたちなか海浜鉄道）反向原坐标逐点等于 decoded1..19。#9原控制9点，公里0.599：feature21329同own属性，反向逐点等于 decoded1..7。两区间首末物理站锚点在compact中另存。JSON保存完整比较范围及原坐标；曲线/进站偏移线索不是本次新加 alias。没有修改物理坐标、站ID、公里、segments或任何显示数据。

共享胜田ID002280的 own 点是 `[140.524367,36.393267]`，JR常磐线点 `[140.524214,36.394073]`，两者不同。将来若 own 显示代表点有充分证据，必须保持 line-specific 范围；不可因共享ID全局替换或把 JR 位置当作 own 中心。

## 原图与渲染限制

原图均 legacy `fixed-z17-v2`，standard/light，1024×768、1.5pt、ownLane0/mainLane0；whole-line render dependency `49112c1b23b07114e7a51f8b6e31c568523a215b49fa2f220d0afe5b650a056d`。几何是 isolated centreline，不证明实际 Main lane/follow/join/family 组合、平台珠位置或当前渲染包通过。原 receipt 仍 pending/reviewFresh=false，时间2026-10-11，原图保持不变。未操作 app/native、build、测试、apply；只新增本报告和 viewed manifest。

`endpoint-original-review-viewed-manifest-20261018.json` 列每张绝对路径、视点、原相机/mapRect、时间、identity-plan、原始控制来源及独立观察。各下列目录中 basemap.png、smooth.png 均实际查看：

| 区间/point | 精确原图目录 | 观察 |
|---|---|---|
|0/0|`/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000275/000000`|Own Ajigaura terminal rail/station group is visible. Red starts toward the southern station-frame context and leaves southward continuously. Full usable passenger-platform longitudinal caps/centre are not established; do not extend to buffer/storage tips.|
|0/1|`/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000275/000001`|Genuine broad southeast compound curve is retained and continuous. Modest red/blue lateral difference, especially toward Isozaki, is visible; no isolated V or neighboring road substitution.|
|0/2|`/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000275/000002`|Own curve into Isozaki is continuous but red lies east of the blue rail in the northern approach; no isolated hook/gap. Actual own representative rail/platform needs attribution before any shift.|
|0/3|`/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000275/000003`|Isozaki station and southward continuation remain continuous with a small eastward difference. Full platform caps/centre unverified; no evidence sufficient for deleting a control or altering adjacent interval1.|
|9/0|`/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000284/000000`|Own Kokimae departure curves north beside the distinct western JR Joban corridor. The own bend is retained; no false V or direct transfer onto the JR rail. Exact rail-band alignment unresolved.|
|9/1|`/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000284/000001`|Own northern approach remains continuous east of the JR multi-track group; red increasingly lies east of depicted railway/station context. Positive own passenger-track/platform binding is required; nearest JR rail is not a valid support.|
|9/2|`/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000284/000002`|Katsuta own endpoint is at frame centre(512,384), east of the multi-track blue band and south of the main shared station structure. Own short platform/rail band is not independently bound in this z17 frame; do not replace it with the nearby JR box or average shared station positions.|
