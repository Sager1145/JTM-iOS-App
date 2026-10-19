# 鳩原错误尖角修复 — 2026-10-18

已写入正式 `jp-2025.json` 及对应 display-lanes：北陸線 p1 原先沿直臂到交叉点才突然转入回环，形成59.741°假转角。修复采用本线N02 feature9616全部47个既有支撑，保持敦贺锚点及交叉后的原controls42–131。修复后的交叉处沿东侧弧线连续通过；没有通过放宽全局圆角规则遮掩错误。

## 数据和方向

- Own line：`jp-西日本旅客鉄道-北陸線-p1`；显示138点。删除会将前段重新拉回直臂的0–3475m follow及0–3175m family window。后段follow/family按同一显示尺重基，leader界及原地理位置保持；Main chunk实际含同一138点，只有后段follow。
- [JR西日本官方说明](https://www.westjr.co.jp/company/info/issue/bsignal/26_vol_207/area/)明确回环为上行、下方直线为敦贺方向下行。因此同时修正p1 alignmentDirection、base pair和方向master；存储站序仍为up。上下行行程选择有意改变，不能称routing行为全部不变。
- Canonical coordinates、stations、stored km 9.718及物理graph结构未改。显示投影与物理层保留不同职责；同坐标交叉点不自动证明换轨。独立依据和边界见[source-review.md](source-review.md)。
- 可重放builder：`app/scripts/railway/repair-hokuriku-p1-loop-display.mjs`。正式apply receipt为[jtm-hokuriku-repair-apply.json](jtm-hokuriku-repair-apply.json)；正式own row为[applied-own-line.json](applied-own-line.json)。proposal.json保留当时candidate-only及待验状态，不能覆盖此处实际结果。

## 实际验证

- 统一诊断App读取显式候选compact文件，z17/light/1024×768，完整区间34/34、0失败、0待采；102张三模式PNG尺寸核对。父会话查看全部34组basemap/smooth、9张contact sheet及原始smooth0/11/12。新相机沿候选路径规划，与旧证据比例尺/视口相同；不声称旧新每一帧中心完全相同。
- Main增量Catalyst构建成功。回环全景与交叉近景均实际ON/OFF核对；每组相机中心、距离、视口不变。ON分别3条line/2个overlay、1934和1177顶点；OFF均0。原图、完整AX、实际own chunk与manifest见[main-production](main-production/)。前段follow未把新弧线拉回直臂，原假转角不再出现。
- 6项局部Node回归在正式apply后通过；Swift `hokurikuLoopUsesUpDirection` 在旧数据先失败7项，修复后1/1通过，覆盖上下行route choices及canonical route display选择。日志随目录保留；未运行国家矩阵或重建退休验证管线。
- 显式输入改动own geometry后续跑被native拒绝，原result字节保持，失败另存run-status；见[changed-input-rejected-AX.txt](changed-input-rejected-AX.txt)。随后加载正式包（显示依赖相同），34张既有视图复用、102张PNG字节保持，现native-candidate的result/run-status已恢复正常。只改方向/溯源的metadata不使几何证据失效；此依赖边界已读审。
- 观察已通过UI标明的⌃⌘S保存并被App接纳1/5。结论为insufficientEvidence，明确局部修复成功不等于整条线路或平台验收。

## 保留问题

原南部回环、新疋田附近与底图的偏移未在本轮修正，两站完整平台中心未证明。相铁横滨及大糸线糸鱼川站端短钩仍需独立本线平台证据；横滨删点/任意taper方案未采用。此处只接受已确认的鳩原错误进路/尖角修复，不宣称其余线路、全部658条、物理图或完整像素对齐已验收。

诊断App另修复了本轮实际发现的技术输入自动改写问题：关闭路径/ID的自动纠错与自动大写，最终增量构建成功，原生输入小写japan证据路径后经⌃⌘S保存，落盘路径逐字一致。实现与证据在统一App candidate-package-input-20261018目录。
