# 修复与新增原生测试复审

范围：原审查 S1、S2、B1–B14 的本次修复，以及原生导入取消、磁盘写入失败、保存重试的新增测试。使用 code-review 的 Standards / Spec 两轴独立复审，结合 iOS、Swift 并发与测试指南；Grok 4.7 xhigh 只读复核 OCR 测试生命周期。对照修复前的局部副本、原报告和当前调用链，保留同仓库其他聊天改动。

## Standards

发现一项 P2：新原生测试虽使用临时文件目录，仍通过 ItineraryStore 与 RideLibrary 写入 UserDefaults.standard，影响迁移、导航和样本标记。已将偏好依赖以生产默认 `.standard` 注入，测试使用独立 suite 并清理；现有 Debug UI 测试 UUID 分支也传递独立偏好。

其他受审源码的物理区段映射、资源责任登记、共享注册表、测试 bundle 单一包实现与 Debug hosted-test 启动边界未发现新的实质违规。未引入通用验证框架或恢复旧流水线。

## Spec

发现两项 P2：

- Web 源指纹遗漏固定坐标下的站名、线路、运营者、分组、机构与有效期变化，旧求解结果仍可能被接受。已按求解器现有双 schema accessor 纳入有效输入；显示备注不改变指纹。
- 删除完成等待刷新后无条件清空保存错误，可能覆盖随后保存的失败。已使用删除 revision 和保存 sequence 限制错误发布归属；同一成功发布 guard 也包住样本标记清理，防止旧删除完成清掉较晚保存关联的标记。失败仍抛出本次错误，保留样本标记。

原生取消测试另有等待缺口：识别器返回和空 MainActor 任务不能证明导入任务完成。已返回已有 read 任务并等待其 value，再检查迟到结果，保留立即取消的断言；失败退出时取消并释放挂起识别器。

## 针对性证据

- Web：仅 `node --test app/tests/web-route-publication.test.mjs`。修复前 9 项中 2 项按预期失败；修复后 9/9 通过、0 跳过、exit 0。真实两站求解验证站点退役修正拒绝旧回退并移除 raw 正缓存；元数据测试验证等效源字段与显示备注边界。
- 原生共享 Catalyst `build-for-testing` exit 0。首次仅执行 `NativeImportPersistenceTests`：15 个测试函数中 13 个通过，包含偏好隔离、OCR 取消、startup、提交取消、实际写入失败／重试、截图重试、备份和恢复；并发聊天新增的删除与 Undo 两函数共 3 个断言失败。失败日志和 bundle 保留，未把整体执行记为通过。重型槽由“Audit the full iOS codebase”聊天管理，本聊天不重复启动构建或测试。
- 失败源于新增测试的比较基准：删除测试混用了写入返回的 `Date()` 与刷新读取的文件 mtime（相差 89 微秒），且两测试将 canonical 解码后对象与原始可选字段对象直接比较。已由原修改聊天修正：删除前先刷新实际元数据并取文件字节；Undo 前先保存原始快照，Undo 后比较原 canonical 字节并检查重载 notes。受影响测试 bundle 增量重编译 exit 0；只重跑这两函数，实际 Swift Testing **2/2 通过、exit 0**。
- 第一次两函数筛选漏了 Swift Testing 函数名尾部 `()`，命令 exit 0 但实际选中 0 项；父任务从完整日志发现并要求仅 `test-without-building` 修正筛选重跑，不增加构建，不将零执行记为通过。
- 先前原生 12 场景证据按其依赖复用；涉及这次修改的偏好和 OCR oracle 将采用新的定向结果。原运行并不能单独证明修正后的迟到任务断言。

局部源副本、两轴报告、Grok 咨询和 Web 红绿日志保留于 `/private/tmp/jtm-rereview-20261011/`。Grok 已写出咨询结果，但 CLI 到达 turn cap；采用的是父任务核实的源码分析，不宣称 CLI 正常完成或执行测试。

共享原生证据：`/private/tmp/jtm-fixes-native-build.log`、`jtm-fixes-native-tests.log`、`jtm-fixes-native.xcresult`（首轮失败）、`jtm-fixes-native-rebuild.log`、`jtm-fixes-native-two-selected.log`、`jtm-fixes-native-two-selected.xcresult`（两例通过）。父任务独立读取完整结果行及实际筛选命令。15 个函数均有通过证据（含参数化场景，首轮 13 个加重跑 2 个），不将首轮整体失败改称整体通过，也不重复运行其他有效场景。既有资源构建阶段仍运行；宿主系统 AppIntents/辅助服务日志不视为产品验证结论。

按 `ios/VERIFICATION.md` 进行源码和直接依赖复审及必要定向检查；不跑完整矩阵、不重建全国数据、不生成全树指纹。并发聊天的其他 UI/数据修复不由本报告认证。像素、性能、泄漏、真实硬件掉电和 OCR 准确率未测量。

两轴初审计数：Standards 1 项 P2（测试偏好污染）；Spec 2 项 P2（站点依赖指纹、旧删除完成发布）；另补强 1 处异步测试完成断言。全部已修复。最终独立源码复审未发现范围内剩余实质问题；共享运行观察到的两个新增测试 oracle 问题也已修正，并有实际定向通过证据。
