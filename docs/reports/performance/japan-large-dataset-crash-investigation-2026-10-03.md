# 日本大数据集地图崩溃调查

> Historical record retained during the 2026-10-10 documentation cleanup. Dates, measurements and unresolved findings below apply to the recorded inputs. Old execution commands are not current instructions; follow [the current verification policy](../../../ios/VERIFICATION.md).

状态：**真机崩溃仍未修复，不能据模拟器通过宣布完成。**

## 已验证的范围

- 通过实际导入按钮加入七组示例，共 287 条：Macao 1、Hong Kong 1、Taiwan 28、South Korea 1、Japan full 201、New Year Grand Loop 39、Tokyo Limited-Express Loop 16。
- 最终绘制代码的模拟器全国/东京五次连续缩放通过；全 287 条在开始缩放前完成加载，原生 display-link 最大间隔分别 147/101 ms，阈值仍为 150 ms，手势期间完整路网重建次数为 0。
- 全 287 条持久化后，真实 24 pt / 40 pt/s 拖动、三轮路网开关及 75 秒驻留通过。首次加载时仍有 201 ms 帧间隔；这个用例的通过仅证明运行/加载正确，不能证明首载完全无卡顿。
- 初始站点整批淡入改用 compositor alpha，避免每帧逐点重绘；无变化 snapshot 不失效；拒绝无站点覆盖的 tile；单次安装最终图层顺序，使用位置索引处理顺序交换。动画、图层顺序、退出清理、几何完整性四组原生产代码回归通过。
- 日本全国/东京静止采样中纹理上传线程已空闲；先前版本相同全国视图在约两分钟后仍有上传栈。这不证明真机崩溃已修复。

## 真机决定性证据

将同一代码安装回原 `com.JRM.RailMap`，保留行程，单次启动日本全国视图并设置 `MTL_DEBUG_LAYER=1`。控制台明确报告 `Metal API Validation Enabled`，约一秒后出现：

`MTLDebugDevice notifyExternalReferencesNonZeroOnDealloc` → `CAMetalLayer Display Drawable` → SIGABRT。

报告 `RailMap-2026-10-03-000139.ips` 的退出线程包含 `MTLDebugTexture dealloc`、`CAMetalDrawable dealloc` 和 Core Animation backbuffer cleanup。不是 jetsam。日志的 `overlays=296` 仅计路网/行程线，不包括站点 overlay，不能把它写成实际 mounted 总数。

原来的 `cpu_resource` 报告是资源诊断，Action taken 为 none，不是崩溃报告。图求解 streaming/lazy 实验没有证明稳定收益，已从 canonical 撤回。

## 真机单变量对照

| 对照 | 结果 |
| --- | --- |
| 隐藏站点，保留路网/行程线，并操作缩放 | 运行超过三分钟，没有相同断言 |
| 全部站点保留，只取消新 station renderer 首次淡入 | 约一秒后相同 SIGABRT |
| 全部站点/动画保留，站点 overlay 用有限地理边界 | 相同 SIGABRT；未采用 |
| 恢复 world 边界，透明合成限制为每个 circle 的 rect | 信号 9 退出，原因尚未确认；未采用 |

下一对照：全部站点合并到单一画布，仅诊断 renderer 数量；若成立，正式实现必须保留每条行程的线/点绘制顺序。

## 可重复证据

隔离构建、冻结资源和测试结果位于 `/private/tmp/jtm-all287`：`final-source-provenance-v8.json`、`all287-v8.xcresult`、`persisted-pan-v9.xcresult`、`original-live-v8-console.log`、`RailMap-2026-10-03-000139.ips` 及各单变量控制台。原模拟器测试设备为本任务专用设备。没有重置真机行程，没有关闭 Metal 校验来避开断言。

真机私人行程导出备份被自动审批拒绝；未执行该导出。独立测试包遇到窗口失联，相关用例失败，不算验收成功。Grok 有界审阅调用超出轮数，没有可用结果或采用的编辑。


## 中断恢复核验（2026-10-03）

当前 HEAD `9c6856b4` 已包含后续共享源码：`installRideStationOverlays` 将所有未选中行程的站点合并到 `all` 单画布，并放在全部行程线之上。上文“下一对照”描述的是中断前状态，不能用于指导覆盖当前实现。当前绘制顺序以新源码及其回归为准。

恢复时 `/private/tmp/jtm-all287`、单画布私有对照和 composite feasibility 临时目录已不存在；上文日志与 xcresult 路径现仅为历史记录，不能作为可重新读取的收据。原专用模拟器亦已删除。未重建或擦除模拟器。

本轮重新执行当前源码的 `verify-ride-station-layering.py` 和 `verify-map-detail-fades.py`，均 PASS。前者覆盖安装顺序、选中清理、复用、透明度与瓦片裁剪；后者覆盖淡入、无变化更新、淡入中离场及动画反转。它们不能代替真机崩溃验收。当前真机构建与新收据保存于 `/private/tmp/jtm-crash-resume`，设备验证仍进行中。


当前源码真机 `build` 与 `build-for-testing` 均成功。覆盖安装保留原数据，单次启动确认 `Metal API Validation Enabled`；当前运行尚未观察到异常退出，但期间有地图缩放/路网切换，且尚未完成隔离存储全部 287 条的自动用例，因此不构成完整验收。最新样本库存复核：七组共 287 条、287 个唯一 ID；大数据集用例通过真实按钮覆盖全部七组。完整自动测试等待手机使用时段确认。
