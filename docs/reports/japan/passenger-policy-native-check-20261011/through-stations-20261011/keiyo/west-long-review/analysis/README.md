# Apple Maps走廊分析：市川盐滨

已实现可复用库 `app/scripts/railway/lib/apple_map_corridor.py` 和产物构建器 `app/scripts/railway/analyze-apple-map-corridor.py`。输入见上级 `shiohama-analysis-input.json`。无需网络或原生构建；需要NumPy/Pillow。

```sh
python3 app/scripts/railway/analyze-apple-map-corridor.py docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/keiyo/west-long-review/shiohama-analysis-input.json --output /private/tmp/shiohama-analysis
```

输出 `analysis.json`、`candidates.geojson`、可切换叠加的独立 `review.html`（嵌入未修改原图）。算法用Mercator映射像素与WGS84，沿粗略走廊采样法向剖面，寻找细暗线对，动态规划约束轴线与符号间距的连续性，报告对比度、支持率与竞争路径歧义。遮挡/不支持区间不会写进GeoJSON铁路线段。铁路符号间距不等于轨距；粗略seed用于走廊身份选择，最终位置从图像得出。

站台分支检查邻近铁路、沿铁路伸长且独立有界的蓝色足迹，拒绝无边界连续铁路底色或不明确的组件。当前只针对north-up/pitch=0、深色Explore标准地图；该palette检测不能证明物理平台身份，也尚未在多个真实站台样本上验证。输入图像范围须与fullRegion对应；Inspector的地图ROI不能直接套用全窗口像素范围。非零heading/pitch拒绝使用平面映射。

## 实测结果（2026-10-11）

市川盐滨原生Apple底图：147个剖面，145个有图像支持（98.64%）；中位对比度26.34，中位竞争比0.0052，约0.409m/px。已实际打开HTML查看并切换叠加：候选沿铁路、未跟随西侧公路。浏览器截图为 `review-browser.png`。

原点[139.923651,35.666478] → 横向对齐候选[139.9235689842168,35.66650455364835]，相对地图约7.98m向西北。保留原纵向位置，这是站点横向对齐建议，不是平台中心或测量坐标。平台分支返回 `independent_platform_bounds_not_resolved`；区域图返回分辨率不足。未据此修改source站点或铁路。

聚焦7项测试通过（1.116s）：真实图片的独立铁路像素带、区域图平台拒绝、蓝色建筑拒绝、遮挡铁路、有限平台足迹候选、Mercator映射、倾斜/旋转拒绝。有限平台正例是受控图形，不代表真实平台检出率；真实平台中心能力尚待更多清楚的俯瞰样本。没有运行全国验证或构建。

区域研究改用国土地理院区域航拍，详见上级sources/REGIONAL-MAPS.md；其z15/z17/z18图像已实际查看。它们支持人工确认仓库、道路及站区关系，不输入Apple标准地图颜色算法。

## 后续实际应用与原生验收

图像候选已用在最外层 `keiyo-shio-transverse-display` 显示修正：003870 main/west3相同alias，main8/9、west3#0接续一致；原站点与物理segments保持。北保留边界422.012m，南为等长canonical窗，图像覆盖纬度内全修正、两端渐变到原接点。此举修正横向代表位置，不声明平台纵向中心。

组合Minami2+Shio1回归3/3GREEN47.696s、最终Shio边界/旧段/重放断言1/1GREEN27.691s。root确认retainedcandidate等于当前raw、physical未改，guarded写入package/lanes及4既有引用。一次增量build成功 `/private/tmp/jtm-shio-native-build.log`；构建包的三条京叶记录与source完全相同。

已实际查看更新主图 .003近景、.008两端区域、.035完整共享段（main-shio-final-*.png/.ax.txt）和成员卡（main-shio-final-member-card.png）；站点在Apple铁路符号中央，连续单红，无新增断点，成员卡一条京叶线。刷新三个检查器jp-2025资源并签名，实际复查更新KisukiKeiyo view17/18配对（inspector-shio-final-view*.png），局部接头连续；更北面未改动的view6/8/9/12/13/15旧证据仍适用。不是平台中心识别认证或物理轨距测量。
