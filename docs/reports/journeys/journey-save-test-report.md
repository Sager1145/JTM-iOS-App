# 添加行程与保存：自动化测试报告

测试计划：[journey-save-test-plan.md](journey-save-test-plan.md)。测试环境为 Xcode 27.0（27A266a），使用临时构建目录及隔离模拟器/存储目录。

最终 UI 回归使用 `/tmp/jtm-journey-save-validation`：基于 `f9d560a` 的隔离 Git 检出，叠加本次 UI 用例和修复。该提交包含构建所需的品牌 API 依赖。并行工作加入的 `JourneyCompletionView.swift` 当时缺失对应类型，阻止原工作区构建；未改动该未完成功能。

## 已验证结果

| 测试层 | 结果 | 范围 |
| --- | --- | --- |
| RailKit 基线 | 656 通过，0 失败 | RailPresentation 258；RailCore 398 |
| 新增行程生命周期 | 6 通过，0 失败 | 添加 ID 冲突、复制、同日期多记录、编辑身份、无效导入原子性、导出与重新导入 |
| 生产编辑校验器 | 33 通过 | 必填输入、站点、日期、线路段、路线策略、颜色、重复 ID 警告及错误修复 |
| 原生存储回归 | 16 通过 | 队列/导出 6 组；真实隔离磁盘 5 组；新增/替换及拒绝操作 3 组；生产窗口保存回调 1 组；路线重建保存边界 1 组 |
| Web 车辆字段兼容 | 3 通过，0 失败 | `vehicle_type` 保留、缺失字段保持缺失、类型拒绝 |
| 既有编辑 UI | 16 通过，0 未解决失败 | 搜索返回、回放、导入取消重开、空白新建、站点建议、车型输入、日期/线路搜索、向导前后切换、删除撤销、详情编辑等 |
| 新增端到端 UI | 2 通过，0 失败 | 保存后重启保留起终点/车辆字段；继续编辑及放弃后重启不生成记录 |

共 18 个独立 UI 用例分批通过，未将其描述为一次完整套件运行。最后的回放重测用时 16.699 秒，结果为 `/tmp/jtm-editor-ui-remaining-results/02-playback-rerun.xcresult`；其余后续批次结果位于 `/tmp/jtm-editor-ui-remaining-results/`。新增用例结果：`/tmp/jtm-editor-ui-isolated-focused6.xcresult`，总测试时间 103.449 秒。

## 修复

`JourneyEditing.replace` 曾在 `.notFound` 或 `.refusedImportRunning` 时仍提交未变化的快照。这样的额外写入还可能清除先前的保存错误。修复后，仅 `.saved` 和 `.savedKeepingID` 触发持久化；回归检查拒绝操作不增加保存次数，也不清除既有错误。

该回归用例在修复前因保存次数增加而失败，修复后通过。保存与编辑校验脚本已接入 `ios/verify.sh`。

继续检查调用方发现：后台导入允许用户离开导入界面，而编辑回调无论保存结果如何都关闭窗口。已调整工作区和详情页编辑回调，只有成功保存才关闭编辑器，拒绝保存时保留草稿。

路线重建也存在相同的额外写入问题：未找到记录或导入占用时返回 `nil`，但仍触发保存。新增回归在修复前失败，修复后验证拒绝操作不写盘、有效的零路线段结果仍正常保存。

UI 自动化也进行了修正：详情滚动明确定位到 `rideDetailScrollView`，避免全屏手势操作到外层面板；取消测试按系统实际的确认框行为执行，并等待行程库/搜索加载完成后再判断未保存；车辆字段按实际合并后的辅助功能标签读取。详情编辑用例由最初约 408 秒超时，恢复为约 24 秒通过。回放用例的示例行程日期已早于测试当天，默认“即将出发”列表为空；已将测试启动筛选显式设为全部行程，避免日期变化使测试夹具失效。

存储覆盖连续 100 次保存、保存合并及顺序、删除屏障、正在执行的快照不被修改、失败后继续保存、备份恢复、北美地区文件分区，以及五个既有示例的缓存导出、Unicode、重排、删除与重新加入。

## 复现命令

在 `ios/RailKit` 目录运行：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/jtm-railkit-core-rules-20260922/module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/jtm-railkit-core-rules-20260922/module-cache \
swift test --disable-sandbox --scratch-path /tmp/jtm-railkit-core-rules-20260922
```

新增生命周期测试可追加 `--filter JourneyLifecycleTests`。从仓库根目录运行：

```sh
python3 ios/tools/verify-editor-validation.py /tmp/jtm-railkit-core-rules-20260922
python3 ios/tools/verify-store-ordering.py /tmp/jtm-railkit-core-rules-20260922
node --test app/tests/train-vehicle-type.test.mjs
```

UI 测试从隔离检出根目录运行（本次使用 iPhone 16 Pro / iOS 26.5）：

```sh
xcodebuild test -project ios/RailMap.xcodeproj -scheme 'RailMap Debug' \
  -destination 'platform=iOS Simulator,id=837A6C47-198E-4612-BBA6-697C85342528' \
  -derivedDataPath /tmp/jtm-editor-ui-isolated-derived \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 240 \
  -maximum-test-execution-time-allowance 300 \
  -only-testing:RailMapUITests/WorkspaceEditingTests \
  -only-testing:RailMapUITests/JourneySaveUITests
```

本次 UI 用例分批运行并分别保留结果；上面命令提供完整的功能回归选择范围。项目日常入口 `ios/tools/verify-layout-ui-smoke.sh iphone` 也已包含新增用例。

## 范围与约定

- 共享日期模型明确保留旧版的日期滚动兼容规则，例如接受 `2027-02-29`；本次未将它改为严格公历校验。
- RailKit 全套结果是新增生命周期用例前的基线；新增 6 项单独运行通过，未把二者描述为一次 662 项全量运行。
- 测试期间存在其他并行工作的品牌与地图改动；本次后续提交只包含测试、对应修复和报告。
- 存储脚本编译生产保存队列、磁盘实现和导出器；地区目录等依赖使用测试替身。编辑边界测试编译生产修改方法，省略显示与导入专用部分，不能等同于整套应用集成测试。
- UI 持久化用例在保存后等待一秒再结束进程，验证正常保存后的重启恢复，不声称覆盖点击保存同一瞬间的强制终止。
- 自动化结果不代表所有真实设备、系统版本及极端断电时机均已覆盖。

## 分步提交

- `702d084`：测试计划。
- `1739acb`、`3f1c6d3`：编辑校验及行程生命周期自动化。
- `c418b8f`：替换成功才持久化，加入原生存储回归。
- `9eef1e5`：工作区保存被拒绝时保留草稿。
- `c81eb39`：路线重建被拒绝时不写盘。
- `9f9b0d6`：详情编辑草稿保留、重启持久化 UI 回归及烟测入口。
- `dfe8883`：回放测试使用全部行程，消除示例日期过期导致的失败。

此前按要求先将工作区已有行程、存储及构建改动分步提交；其他并行任务的提交不计入本次修复清单。
