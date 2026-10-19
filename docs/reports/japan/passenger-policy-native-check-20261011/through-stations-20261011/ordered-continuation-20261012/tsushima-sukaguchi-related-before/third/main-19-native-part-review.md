# 名古屋本线 #19 Third 原图与 native display-part 审查

日期：2026-10-13  
结论：**REPAIR REQUIRED；不是候选接受凭据**

## 实际审图覆盖

逐张以原分辨率打开了 `captures/002454/000000..000002` 的全部 **3 个视点、9 个面板**：每个视点的 `basemap.png`、`display.png`、`smooth.png`。三组都属于 `jp-名古屋鉄道-名古屋本線#19`（新川橋 `005374` → 二ツ杁 `005377`）。

| 视点 | basemap / display / smooth 观察 |
| --- | --- |
| `000000` | 西端曲线、河川跨越和向东西向直线的方向连续，无 U、折返或跨入别线；cyan 已在长直线南侧，smooth 又向南增加一个浅弧。 |
| `000001` | 缺陷最清楚。Apple 自身名古屋本线蓝色导轨在长直线中段约为 `y=373..378`，cyan 约为 `y=383..385`，smooth 约为 `y=384..386`。例如约 `x=400/500/600/700`，蓝色导轨中心分别约 `373/375/378/375`，cyan 约 `383/384/385/385`，smooth 约 `384/386/386/386`。这不是端点圆点造成的局部钩子。 |
| `000002` | 二ツ杁以西的长直线继续显示相同南侧偏移；cyan 与 smooth 都连续，但都没有回到自身蓝色导轨中心。二ツ杁旧 guard 仍在旧物理点，独立 z18 审查已另证其 own-frame 纵向中点需要移动。 |

蓝色线路导轨只作为 Apple 当前显示框架的 cartographic support，不作为地下/测绘精度声明；这里的缺陷是同一画面内显示线与自身唯一线路导轨之间可重复观察的相对偏移。

## 当前 part 和区间来源追踪

对当前 `app/public/rail/jp-2025.json` 进行只读定点解码，并调用现有 `app/public/rail-network.js` 的 `decodeIntervals` / `displayPartsForLine`：

- 名古屋本线共 59 个解码区间；`displayPartsForLine` 返回 **1 个 part、1486 个顶点**。
- 该唯一 part 中，新清洲、丸ノ内、须ヶ口、新川橋、二ツ杁、西枇杷島分别位于顶点索引 `286/298/307/314/321/329`。
- #19 正好是同一 part 的 `314...321`：新川橋锚点、6 个内部源点、二ツ杁锚点。它不是一个错误选中的末端 part，也没有在二ツ杁提前终止；part 从 #18 连续进入 #19，并继续进入 #20。
- 当前行没有 `displayStationCoordinates`，也没有任何 `displayIntervalCoordinates`。#19 的 `renderedDisplay` 因此就是当前 compact 解码源；三个 `capture-state.json` 的 `displayToDecodedDisplayMaximumMetres` 仅为 `2.3e-9..2.4e-9 m`，即浮点噪声。
- 三个 `view.json` 都记录 `originalDisplayPartIndices=[0]` 与 `originalSmoothPartIndices=[0]`。没有证据支持“取错了另一个 part”或错误 serialization bound。

当前 #19 解码序列为：

```text
[136.85262, 35.19525]       新川橋旧锚点
[136.85318, 35.19496]
[136.85365, 35.19482]
[136.85374, 35.19480]
[136.85411, 35.19473]
[136.85464, 35.19468]
[136.85881, 35.19465]
[136.859706, 35.19466]      二ツ杁旧锚点
```

## 平滑层的责任边界

`renderedSmooth` 由 Inspector 的 `InspectorStrokeGeometry.build` 对这条完整 part 调用 `ContinuousStroke.buildStroke` 产生。它会在站点锚点之间对中心线做曲线采样/圆角，而不是另行读取一份 #19 几何。

三个视点记录的 `smoothToDisplayMaximumMetres` 都是 **1.7819381233 m**。原图中的 smooth 确实比 cyan 再向南约 `0..2 px`，因此平滑会小幅加重弧形；但 `7..11 px` 量级的主要相对偏移已经存在于 cyan/decoded display。不能把整个缺陷归因于 renderer 过度平滑，也不能仅改平滑阈值来掩盖源中心线的南侧偏移。

## 最小修复含义

- #19 需要完整 own-rail `displayIntervalCoordinates[19]`，覆盖新川橋曲线、长东西向直线和二ツ杁进路；不能只移动两个 station alias，继续保留已知偏南的中段。
- 新川橋和二ツ杁若采用已审的 own-frame 读图候选，必须分别同步 #18/#19 与 #19/#20 的完全相同端点。#19 修复必须在新的完整 part 上重新运行平滑并实际复查；旧 `1.78 m` 数值只描述旧源，不是新候选证明。
- 该线只有一个 native display part。实现层应让 interval override 重建同一 part，同时保持 #0...#15、#21...#58 顶点不变，并按既定连续范围实际复核 #16...#20。不得为 #19 新建 branch part、`displayBranchLeadIns`、假 switch 或物理拓扑连接。

本审查没有生成替代坐标、修改生产数据、运行构建/UI，也没有批准 Main/native 候选。
