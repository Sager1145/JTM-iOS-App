# 日本大数据集地图崩溃调查

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
