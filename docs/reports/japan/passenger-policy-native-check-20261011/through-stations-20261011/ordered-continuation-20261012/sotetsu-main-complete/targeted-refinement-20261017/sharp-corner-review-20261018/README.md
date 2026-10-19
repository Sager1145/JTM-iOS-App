# 横浜相鉄终端尖角审查 — 2026-10-18

**两个候选均 rejected / not applied。原 needsRepair 继续开放；没有正式修复或平台中点验收。**

## 来源与原图

当前 `app/public/rail/jp-2025.json` 的相鉄本線没有 displayStationCoordinates 或 displayIntervalCoordinates override。A `[139.620466,35.464424]`、B `[139.62052,35.46423]`、C `[139.61993,35.46359]` 从最早本地 seed `45b5dda5` 已相同，五次相关包提交均未改变。未找到 A 的本仓库人工 Apple 定位修复或 alias 依据。A 属于继承 canonical 锚点，不能称为已验收的 own-platform 中点。

`app/data/rail-sections.json` feature10162 明确属于相模鉄道／相鉄本線，own 源支持为 C→B→`[139.62082,35.46456]`→`[139.62123,35.46481]`。`app/data/stations.json` own station feature4897 的 display_point 为 `[139.62205,35.4657567]`，与 A 不同；不能直接把该旧 N02 点搬成显示站点。

已原尺寸打开 `../unified-session/alignment/captures/000000/{000000,000001}/{basemap,smooth}.png`。当前 source、display、smooth 都有同一个49.67°短钩。可见 own Sotetsu 带未提供对应真实折返依据，但终端完整平台端帽仍被站体/访问填充遮挡。

## 删除 B：拒绝

B 距 A–C 新直弦约14.353m。p0 原始1600×1200中 A≈(800,600)、B≈(820.133,688.804)、C≈(600.165,981.762)；新弦在 B 同高度约(753.515,688.804)，再向西移66.617px。现有线已在标注 Sotetsu 带西侧，删除 B 会增加该处西向偏离；角度下降不代表对齐改善。

父会话本轮新建、尚未实现的删除方案测试已移出 active tests，原样保存在 `proposed-deletion-test.mjs.txt`。它是被拒实验的记录，没有执行，也没有删除既有 working 测试。

## Own-tangent taper：拒绝

原 proposal 保存为 `rejected-own-tangent-taper.json`。用 own B–E 投影得到 P=[139.62061479059932,35.46433426965925]，A–P法向16.786m；沿 own P–B–C 的103.535m，以 quintic 权重把位移退到零，保留 A、C 及所有下游支持。2m采样54点，最大相邻转角约1.019°。

该构造只证明几何连续性。A 未有本线平台证据定位，候选仍向 west 离开 own 蓝轨，不能因曲线平滑而接受。不应用到正式 rail。

## Renderer

该角源于输入，不是 renderer 生成的新直角。Swift `surveyedCornerIndices` 与 JS 对应规则把局部≥30°且邻角明显更小的点分类为 hard corner，最终 fillet 接收 hardCorners 后刻意保留它。全局放宽会影响真实道岔、反曲和折返；本例不支持修改通用 guard 或加相鉄站点特例。

本次仅保存审查和拒绝方案、迁移明确的新实验文件。未改其他源码/生产数据；未运行 native/UI、build 或 test。
