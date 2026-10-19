# Mac检测器：Apple Maps铁路与车站抽离（第61条）

已接入RailAlignmentInspector，而非仅独立Python产物。操作：选择线路/详细视点或站点近景 → 点击“抽离铁路与车站” → “抽离”页对比。关闭“显示底图”只保留绿色像素铁路候选、青色构建中心线、黄色Apple车站POI、粉色构建站点；“构建线”可切换。导出抽离结果生成原图、analysis.json、extracted.geojson。批量运行期间按钮禁用，手动分析不触发全国检测、不自动改source。

## 实现与边界

InspectionKit/Sources/RailInspection/AppleMapRailExtractor.swift：Foundation/Swift像素分析，细暗符号线对、剖面与纵向持续性、动态规划连续性、竞争候选歧义、明确缺口；宽道路边缘不作为兜底。Sources/AppleMapAnalysisService.swift：同视点无产品叠加MKMapSnapshotter，point(for:)校准像素/WGS84；Vision文字框使剖面无效而非涂黑制造轨道；后台计算，主线程发布；Apple publicTransport同名（含罗马字）站点搜索。站点POI匹配限定当前可见所选铁路，最多3个站；不是从构建坐标复制输出，也不是平台中心。道路/建筑干扰通过细符号/连续/竞争约束排除，但不可保证所有地图样式/干扰都已分类正确。

抽离视图固定展示其自身快照，不因隐藏地图布局变化清除结果。实际选站/视点/缩放/普通地图移动使结果过期；异步任务使用取消与generation检查。抽离模式禁止普通同视点证据导出，避免导出隐藏地图的新范围；使用独立抽离导出。终点站无下一区间时仍可分析，metadata关联进入站的区间；没有详细视点则显示“站点视图”，不显示1/0。

## 真实原生验证

2026-10-11更新三个Inspector代码（启动文件及实际debug.dylib均复制、临时签名），KisukiKeiyo实际运行最终版本。单独增量构建成功；先后修复实际发现的结果面板引发过期和终点站标签问题，没有重跑全国检查。

市川盐滨：选择京叶-3终点站003870、z18；原生导出999×661像素、0.483540m/px。90剖面/72支持（80%），两段候选；中位横向距离0.483540m、P95/最大2.901242m。仅对可见站前约170m的构建平滑中心线、获得支持的采样计算，未证明全区间/全部轨道的精度。一次实际同名车站搜索返回Ichikawashiohama Station，[139.923583,35.6665689]，与构建点距离7.266m；POI不代表平台中心。未修改铁路或站点source数据。

实际亲自查看纯净与恢复底图画面：候选沿铁路，未跟随西侧高速/站前公路或东侧仓库轮廓；不支持处留空。原生文件导出成功并读取内容（native/shiohama-export）。最终UI图为native/final-clean.png/.ax.txt；配对底图图为native/shiohama-extracted-basemap.png/.ax.txt。实际点击z17后回到叠加对照并禁用旧结果导出，记录native/zoom-invalidates-result.ax.txt；再z18重新抽离返回最终展示。

聚焦Swift生产回归3项通过：独立8m像素位移、道路宽带拒绝、文字遮罩、竞争平行线拒绝、真实市川盐滨像素及缺口。算法未改动后复用此证据；后续集成改动以增量编译和真实UI验证。车站POI与铁路制图候选是两类证据；本版未实现可靠的真实平台足迹自动识别、物理轨道数恢复或新干线各样式识别率，不能把低支持或缺口算对齐。

聚焦执行命令：`CLANG_MODULE_CACHE_PATH=/private/tmp/jtm-rail-alignment-inspector/clang-module-cache swift test --disable-sandbox --package-path ios/auxiliary/RailAlignmentInspector/InspectionKit --scratch-path /private/tmp/jtm-rail-alignment-inspector/InspectionKit-build --jobs 2 --filter appleRail`。执行代理提供实际exit 0输出：3 tests passed，0.550秒；三个名称为appleRailEqualParallelGlyphRivalsStayUnresolved、appleRailExistingShiohamaPixelsProvidePartialGlyphEvidence、appleRailPixelsDetermineOffsetAndBroadRoadHasNoFallback。最终Catalyst增量build exit 0，日志`/private/tmp/jtm-native-extraction-terminal-build.log`。

资源协调最终状态：收到“Audit the full iOS codebase”聊天的暂停请求，并核实其用户授权“Yes, coordinate with that chat”。默认Inspector新版本在启动收据校验时通过SIGSTOP保持，PID 46271、STAT Ts，checkpoint captured 73834、failed 6、pending 18376，planDigest 1e616b862b86493543065ce15a1a7c0961f8dbc481124be66005108c9997587a，unavailableIntervalCount 0。保持记录`/private/tmp/jtm-native-extraction-default-hold.json`；已向审查聊天01a12d77-271a-7eb2-a55c-46995376121d报告，等待其释放重任务资源。当前不要启动新的build/test/capture；释放后先核实PID/文件是否更换再决定SIGCONT或安全重启。京叶窗口保留完成的抽离画面，无手动分析运行中；Hakone资源已更新但未运行。


资源释放后恢复（2026-10-11）：审查聊天报告全部聚焦job退出、默认产品未覆写。root核实同一PID 46271为原Inspector --batch-all、STAT Ts，只发送一次SIGCONT，随后STAT Us。原checkpoint实际从73834增长到73939，failed 6、pending 18271，planDigest保持不变，unavailableIntervalCount 0。未重启、未删除输出、未另起手动分析或重型检查。本条替代此前hold状态；既有进程未重载审查聊天随后修改的X02共享admission代码。证据apple-map-extraction/native/default-resumed-checkpoint.json。


架构检查后恢复（2026-10-11）：审查聊天报告heavy槽释放、全部job退出且未更换Inspector产品。root核实同一PID46271/--batch-all/STAT Ts后仅一次SIGCONT，实际STAT Rs；checkpoint captured从78146增长至78260、failed从6增至7、pending 13949，原planDigest不变、unavailableIntervalCount 0。新失败保留、不自动重试。未重启/删除输出/并行manual分析；仍为既有载入版本，不作为新Core接口或admission运行证据。证据apple-map-extraction/native/default-architecture-resumed-checkpoint.json。本条替代上一hold状态。
