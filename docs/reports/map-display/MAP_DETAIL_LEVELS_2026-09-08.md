# 铁路缩放层级调整 · 2026-09-08

本次调整 iOS「全部铁路」的缩放显示，不修改七个地区的铁路源数据或 Web 可见性规则。

## 显示规则

- 铁路细节等级按视口归一化：将短边归一到 390 pt（iOS）/ 390 CSS px（Web）的手机参考视口，调整量为
  `clamp(log2(390 / 视口短边), -1.5, +0.5)`，加到相机缩放上再查细节阈值；Web 与 iOS 使用同一公式与常量。
  手机（390–440 pt）调整量约为 0；iPad 11 英寸（834 pt）为 −1.10；iPad 13 英寸（1024 pt）为 −1.39；
  1400×900 桌面浏览器为 −1.21；1920×1080 为 −1.47（触顶 −1.5）；320 px 嵌入为 +0.29。此规则适用于 Web 与
  iOS 两端。
- 最远视角保留高速骨干：日本 9 个新干线条目、台湾高铁、韩国 3 条高速线、美国 2 条 rank-0 线路。短高速支线也保留；普通支线仍按层级出现。
- 普通线路按完整可见性分组长度与等级共同筛选：应用 z4/5/6/7 的长度门槛分别为 300/120/50/20 km，z8 所有线路均具备显示资格。屏外剔除和顶点预算仍约束实际绘制。
- 车站同时满足自身密度门槛和所属线路门槛，最远视角不显示车站点。
- 地区懒加载、预生成几何的线路和车站、原始数据解码使用同一套原生阈值，避免地区加载层仍按旧阈值阻止显示。
- 比例尺由屏幕中心短线段投影得到，处理日期变更线环绕；旋转地图不会再通过经纬度包围框误触发铁路缩放层级。几何缓存也使用同一比例尺。
- 无行程时关闭全部铁路只移除铁路覆盖层，保留底图透明度覆盖层，并发布明确的关闭状态。

MapKit 的可视区域是地图矩形，不是公开的整数铁路细节表。本应用以 MapKit 实际投影比例尺定义 256 点瓦片缩放约定，再集中转换旧 512 点 MapLibre 阈值。
参考：[Apple MKMapView](https://developer.apple.com/documentation/mapkit/mkmapview)、[Apple visibleMapRect](https://developer.apple.com/documentation/mapkit/mkmapview/visiblemaprect)。这些层级是本应用的铁路显示策略，并非声称复刻 Apple Maps 内部未公开的阈值。

## 修改位置

- `ios/RailKit/Sources/RailPresentation/NetworkVisibilityPolicy.swift`：原生层级与高速骨干规则。
- `ios/RailMap/NetworkLOD.swift`：调用统一阈值，继续负责空间筛选和预算。
- `ios/RailMap/RailDisplayNetwork.swift`、`RailNetworkStore.swift`：地区加载及预生成/原始数据路径统一。
- `ios/RailMap/MapProjection.swift`、`RailMapView.swift`：方向独立的比例尺、几何缓存和空网络关闭状态。
- `NetworkVisibilityPolicyTests.swift`、`MapDetailLevelTests.swift`、`MapLayerToggleTests.swift`：分组阈值、双向缩放、大屏、最大视角、旋转和图层恢复回归。

## 验证

- `SCRATCH=/tmp/jtm-zoom-detail-core ./ios/verify.sh --swift`：542 项 Swift 测试、代码约束及 iOS 构建通过。后续空网络关闭状态的小改动通过最终 UI 测试构建验证。
- 七地区数据测试检查线路集合随放大单调增加、z8 全部具备显示资格、高速骨干数量和跨窗口一致性。
- iPhone 首轮最大视角：camera/lod 均为 2.00，13 条高速线路（21 个绘制条目），364 个顶点，0 个网络车站，0 个预算丢弃；实际截图可见东亚高速主网。
- iPhone 首轮旋转测试通过，旋转后 camera/lod 均为 12.20。

- iPad Pro 13-inch (M5), iOS 27：最终 `MapDetailLevelTests` 2 项通过。关闭行程路线后，最远视角仍有 13 条高速线路、609 个顶点、0 个网络车站及预算丢弃，camera/lod 均为 3.01；确认铁路关闭状态后重新开启，恢复相同线路集合。旋转测试同样通过。
- iPhone 17 Pro, iOS 27：最终 5 项 UI 测试全部通过，覆盖最大视角及图层关闭/恢复、旋转、横竖屏比例尺、日本连续双向缩放。连续缩放的最终状态有 84 个绘制条目，预算丢弃为 0、手势中重建为 0。这里只作为模拟器功能回归证据，不外推真机帧率。
- 最终构建/测试日志：`/tmp/jtm-detail-phone-final.log`、`/tmp/jtm-detail-ipad-final.log`。结果包：`/tmp/jtm-detail-phone-final.xcresult`、`/tmp/jtm-detail-ipad-final.xcresult`。
- 已目视检查 [iPad 最大缩小截图](/Users/sager/.codex/visualizations/2026/09/08/01a082b4-f83f-7da2-9523-ab2e1583df28/map-detail/ipad-overview.png)，行程路线已关闭，东亚高速铁路细线可见。

## 检查边界

本次视觉检查针对原生地图的铁路层级；未改动源数据，不重新声称线路库存、测绘形状、Web 全面审计通过。现有播放期间的图层更新延后刷新机制是独立问题：直接开关仍可能等播放结束才更新，涉及播放快照和异步几何提交，本次未改动。
