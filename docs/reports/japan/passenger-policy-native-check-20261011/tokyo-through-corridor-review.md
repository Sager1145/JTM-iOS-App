# 东京站南北在来线显示接续：只读审查（2026-10-11）

范围：读取当前 compact package、display-lanes、owning repair、网页/Swift/native builder 与相关现有测试；只写本报告。未运行 UI、build、tests 或产物重建。Apple 当前截图由另一个工作单元提供；本报告不作像素/站区中央/底图贴合验收。

## 当前已有的接续

| 显示组/逻辑成员 | 东京代码与代表坐标 WGS84 [lon,lat] | 当前状态 |
|---|---|---|
| 北侧 `jp-東日本旅客鉄道-東北線-2` → 南侧 `jp-東日本旅客鉄道-東海道線` | `003766`, `[139.7671827,35.6811274]` | 完全同点；北侧圆点 owner 明确指向東海道線；同公司；北侧端点 lane=0，display-lanes 北侧末300m为0，南侧前2350m为0 |
| `総武線` / `総武線-3` | `003766`, `[139.765379,35.681726]` | 地下组内部完全同点；总武-3 owner 指向总武；没有并入上述地面在来线 |
| `東北新幹線` | `003766`, display `[139.7676701,35.681109]`；physical `[139.767579,35.68113]` | 独立，无圆点 owner alias；2026-10-12核对补记：旧末端横尾折已修复，显示终点采用既有同轨支持，未改物理站点 |
| JR东海 `東海道新幹線` | `003766`, `[139.768107,35.681116]` | 独立，无圆点 owner alias |
| `京葉線` | `003785`, `[139.765236,35.677692]` | 独立地下组，无 alias |
| 东京地铁丸之内线 | `003766`, `[139.7648,35.681935]` | 独立公司/走廊，无 alias |

`app/public/rail/jp-2025.json` 两条地面在来线均有 `railwayIdentity=jp-jr-east-ueno-tokyo-through`。北线最后 physical segment 11 的末点、南线 segment 0 的首点已经完全相同。`display-lanes.json` 中 groomed part 末/首点也保留同坐标，所以不是仅圆点共享而铁路仍停在不同位置。其相邻点为北侧 `[139.7675242,35.6822222]`、南侧 `[139.7667069,35.6799004]`；以该站纬度的局部比例计算两边方向差约3.265°，是数值方向描述，不能据此宣判真实曲线错误或应拉直。

六个主要 JR 逻辑成员四个圆点的当前设计由 `app/tests/tokyo-platform-approaches.test.mjs:48` 保留；Swift `StationDisplayParityTests.swift:390` 同样保留北线、总武别名的分组和弹窗身份。测试源码是行为约束证据，本次未运行测试。

## 尚未实现/未被证实的部分

东京在来线没有 `displayStationCoordinates[003766]`，两侧东京进出站区间也没有中央锚点 `displayIntervalCoordinates` override。现有共点沿用 physical/source 东京站坐标；没有独立 Apple 蓝色站区中央候选排序或新增 Apple 黑线轨迹证据。因此“南北共用一个点”已实现；“这个点及两侧走廊符合当前 Apple 黑线、站区中央”的要求仍需当前截图判读。不能从数据共点自动推断后者通过。

`through-running-display-joins.json` 当前仅登记押上两对、涩谷两对，不含东京。其120m/20m shared-tangent机制不会对东京自动执行。东京没有 `shared-corridors.json` 明确窗口；`display-lanes` 的相关 follow 仅是总武-3 的6675–7875m跟随東海道線6700–7875m（品川附近），没有东京北线→南线 follow。北/南是端点接续，本来不需要用区间 follow 模拟整个共用走廊。

Sobu 与地面在来线在品川的显示 alias/350m transition 已有专门政策，不应扩大到东京以消除地下组。Keiyo/Shinkansen同样不属于此次北南地面接续。

## 最小 owning builder 与依赖

首选修改 owner 为 `app/scripts/railway/repair-tokyo-platform-approaches.py:43`，不是手改 compact artifact。它已有东京同坐标断言和圆点/lane声明，并负责 bounded Tokyo policy；若截图证明需要移动代表点，应只对北线末区间11、東海道線首区间0设置审核后的 display interval，以及两条线相同的 `displayStationCoordinates[003766]`。保留 stations、segments、distanceKm、站序和物理连接；保持同公司显式 owner/lane pins。新坐标必须来自正确客运平台组的现有/明确审核铁路，不能按 nearest track 自动造物理连接。

若只是需要审核后的切线接缝，可把东京作为明确terminal pair登记给现有 through-running replay（两端均terminal），但它目前断言anchor相等、默认从physical几何重放，并可能覆盖 owning Tokyo display override；须先明确两者重放顺序/单一owner。120m Bézier/20m straight机制不能无条件当成 Apple 黑线复刻；新 smoothing政策要求保留真实非共线小曲线，不建议仅为了达到perfect tangent直接加入registry。

相关依赖：

- `app/public/rail-network.js` 的 `displayLineForCoordinates`/displayParts、circle alias 条件（4391）、railway identity（3561）；网页圆点须显式owner、非空同operator及exact display coordinate。
- Swift `CompactPackage.swift:90` 的display字段，`DisplayParts.swift` 的display station/interval路径，以及 `StationDisplay.swift:229` 同一圆点alias条件。RouteNetwork physical/source 与 mileage仍独立。
- `display-lanes.json` 两条line的 `partsByRegion`、米数、station pins及相关lane rows。修改代表几何后不能保留旧groomed part和旧里程窗口作为“已同步”。只应更新确实依赖变更的记录。
- `build-display-network.py` 读取compact + display-lanes + shared corridors，3234再次按同company/exact anchor决议circle，并保留groupLineKeys。`ios/copy-rail-packages.sh:77` 在构建时生成bundled `rail-display-network`；仓库没有 `ios/RailMap/rail-display-network` 可直接证明已打包状态。因此当前源码/数据状态不能证明已安装app反映最新变更。
- `tokyo-platform-approaches.test.mjs`、`StationDisplayParityTests.swift`、native builder `test_tokyo_station_circles.py` 是现有最近的约束；通过registry扩展才涉及 `through-running-display.test.mjs` 的terminal、source preservation、方向检查。不应启动全套或build，本次仅读。

跨公司接续registry目前只对同公司写owner，跨公司保留每家公司圆点；不能由shared terminal推导整个shared-track区间合并。Tokyo相关 `renderGroupByRegion` 北线与南线目前是不同绘制组，但其package railwayIdentity明确接续；不需要为了共点而全国统一render group。

## 本次结果

已通过targeted JSON reads确认compact与groomed display两条地面线端点共点、lane零保护、Sobu/Keiyo/Shinkansen独立；通过代码审查确认网页/Swift/native builder圆点条件一致。尚缺当前Apple截图中央锚点/正确黑线候选的视觉审查及已安装native产物状态。无生产编辑，无运行时/pixel/performance通过声明。

## 追加：当前 Apple 截图限定观察

已通过 `view_image` 实际查看 `tokyo-through-reference/` 内七张 PNG：中央東海道 overlay/basemap、同camera中央東北 overlay、北喉 overlay/basemap、南喉 overlay/basemap；读取 capture-note 和 AX camera记录。此追加补足上述“尚缺当前截图”的状态，其他未测结论保留。中央三张camera center `[139.767183,35.681127]`、altitude622、pitch/yaw0、corners `[139.764503,35.679624]` 至 `[139.769862,35.682631]` 完全一致；北喉与南喉各自overlay/basemap camera一致。UI标记z18，AX的camera.zoom值19；本报告以文件/UI命名标识证据，不把两套zoom定义混用。

中央画面可见红色东京站pin位于蓝色站区内部、黑色密集站台铁路带内，处于所示平台组中部附近；并非铁路带外的一处道路/建筑锚点。视觉上未出现“北线停在站北端、南线停在站南端”的缺口：東北单线叠加沿画面上方铁路带向下接近pin，東海道单线叠加从同pin向画面下方延出。原始数据与groomed part完全同坐标的读数，给出这两张独立单线画面端点实际共享的数值证据；截图里的同位置pin不能独自证明全产品family合成显示。

中央basemap清楚保留若干平行黑色railway strokes。叠加代表线处于其客运平台走廊范围内；不能仅凭这组画面的视觉宽度，给某一黑色股道命名、证明它属于某一站台，或认定每个叠加像素精准压在同一黑线。北喉截图显示代表进站腿在多根黑色进站铁路组成的带内靠近中央方向进入站区；南喉截图显示代表出站腿沿多轨铁路带向南延伸，黑色股道间有分流/弯曲，叠加腿没有理由仅因其他黑线更近就自动移到其他线路。两腿需各保留本身的审核客运走廊，只在已确认的站内代表点接续；Sobu/Keiyo/Shinkansen不因画面中彼此接近而扩大合并。

这些图足以支持“当前共同点在蓝站区内的平台铁路带中部附近，两条独立北南在来线腿分别向该点接近”的限定判断；不足以确定一个优于现点的新坐标，也没有清楚的走廊外落点、站区外端点或两端错位作为必须移动的证据。因此当前不建议仅凭此截图实际移动东京代表点。若后续指定某条已审核黑色客运铁路及更明确的中央候选，可沿上述owning builder做bounded display修正；不能把这一候选过程变成nearest-track的物理连接生成。

父chat报告已运行existing focused `main Tokyo JR complex elects four circles and retains every platform alias` JS case，结果1/1通过；此为父chat执行证据，不是本工作单元执行。它支持现有四组circle/逻辑alias约束，不能验证Apple像素贴合、完整产品family渲染或安装app的bundle版本。
