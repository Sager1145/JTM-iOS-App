# 肥萨线时间区间接入 · 2026-10-11

用户要求停运/营运随日期变化，使用已有机制。新增两条 temporal_events，经现有 source_event_geometry / compile_event / normalize_stamps 定向编译进入 rail-history.json，revision 2026-10-11.1。未改物理几何、compact ID、其他线路时间记录或现有年代设置。

- 八代—吉松：valid_to 2020-07-04；当天及以后不属当前营运网络，之前乘车日期可显示。复用 JR 2020-07-21 灾害公告、2026-06-29 公告确认持续停运。
- 吉松—隼人：营运区间 [无起始限制,2020-07-06)、[2020-07-11,2025-08-07)、[2026-07-12,无结束限制)。国交省记录2020-07-05 15:00停运/07-11 12:20恢复，所以按日机制只排除07-06—10五个全日无车日期；不推断分时刻行程。这不是完整短时停运档案。
- 2026-06-28 是5月27日提出的计划，6月22日延期；6月29日公告改为7月12日，霧島市7月23日更新确认已实际恢复。旧研究记录日期已更正。
- N02-25 吉松站体北端纬度32.01245是原始段边界，整段站体归入可营运南段；48北/20南轨道要素、18北/10南站体各有一个当前时间约束。没有跨界原始要素，没有移动端点。当前compact静态状态保留供无年代界面的网页当前网络使用；原生Current/Selected ride date及双方dated routing使用已有历史覆盖。

## 聚焦证据

1. test_jp_rail_history.py 的 test_shipped_hisatsu_service_timelines_cover_every_current_feature：先缺事件失败，再观察snapshot重放站点内容不一致，改为既有source_event_geometry派生后通过；新增2020全日停运边界先失败后通过。重放全部肥萨线源要素与已发布历史记录完整一致。N02-25原ZIP不在本地缓存；使用已标明N02-25的检查入库section/station测绘字段，不采用显示点作为历史survey几何。
2. [显示历史产物](dated-display-history.json)与[日志](dated-display-build.log)：现有builder只输入真实肥萨线compact/lanes/历史记录，其他地区为空。四个时间stamp均matched，27原始显示区间被边界切成28个带日期显示part；28站体均带正确时间边界。没有全国数据重建。
3. [JS日期结果](javascript-date-boundaries.json)：真实 applyRailHistoryRetirements / railServiceBounds / isRailValid 对68轨道要素与28站体，在10个停运前后、实际恢复及错误计划恢复边界均通过。
4. [Swift网络年代测试](network-era-tests.log)：复用scratch，两jobs，现有DisplayNetworkEraTests 6项通过，增量测试构建1.11秒。覆盖Current、RideDate半开区间与日期缺失回退。
5. 查阅 RiddenRouteStore/RailHistory 的版本及hash进入solve context，revision更新使旧日期求解证据不能被当成新输入复用；未清理任何用户行程。

没有编译/更新当前正在运行的RailMap包，也没有新的日期切换截图或原生实际路线求解；本次结论是源/产物接入和既有过滤机制验证，不声称像素或地图线位已通过。历史矢岳—真幸偏移仍保留未解决，不因当前停运关闭风险。已有主图Minami修复与三个Inspector资产/证据未变。

批量取证协调：默认Inspector在36,842/92,216、失败4暂停；全部聚焦作业结束后单次点击恢复。续跑前既有证据核对导致AX18秒超时，未重复触发。checkpoint增长至36,908，随后AX确认运行中36,935/92,216、失败4；planDigest仍为ca243929d9af5237145ae651192f3d6ecb23530b44a940bb978fe55c6d0db9b7，无取证依赖数据变动。

## 后续：用户要求更新原生应用并实际切换日期

复用同一DerivedData、2jobs完成一次正常RailMap Catalyst增量构建（[build log](native/incremental-native-build.log)），本地调试包临时签名后启动。普通copy阶段派生显示资源，未另跑全国历史源重建。包内rail-history.json与源文件字节一致、revision2026-10-11.1，四个Hisatsu display stamp均matched。此前“未更新运行包/无日期截图”的限制在本次后续已解除。

实际UI选择Settings→Network era→Selected ride’s date。顶部日历只筛列表，不是网络时间输入。使用现有DEBUG入口在隔离测试存储加入一条pending/0stops探针，并打开普通RideEditorView，通过原生日期输入框逐次输入七个日期。新建模式现为NewTripView，没有草稿日期发布，故检查使用编辑模式而非新建模式。真实用户存储未访问或修改；无路线overlay（rides:0），没有将草稿日期写回。结束时取消草稿，隔离探针仍为2026-07-12，设置恢复Current；主应用保持运行。

Root逐张实际目视同camera截图。北段指视点内矢岳/真幸→吉松，南段指吉松→栗野/大隅横川，非全线逐段线位验收。黑色Apple底图铁路不会随营运日期消失；判断产品彩色叠加及可见站点。旧南段时间区间使用既有historical点线样式，实际恢复后的当前段使用实线。切换瞬间AX可能保留上一帧annotation名称（例如07-04仍列真幸、08-07仍列栗野），故不把AX名字存在与否当成像素判断；renderer已改到对应计数，随后截图里旧线/旧点已消隐。

| 实际编辑日期 | 可见北段叠加 | 可见南段叠加 | 证据 |
| --- | --- | --- | --- |
| 2020-07-03 | 显示 | 显示 | [PNG](native/2020-07-03.png) / [AX](native/2020-07-03.ax.txt) |
| 2020-07-04 | 隐藏 | 显示（仅验证北段全日停运边界） | [PNG](native/2020-07-04.png) / [AX](native/2020-07-04.ax.txt) |
| 2025-08-06 | 隐藏 | 显示 | [PNG](native/2025-08-06.png) / [AX](native/2025-08-06.ax.txt) |
| 2025-08-07 | 隐藏 | 隐藏 | [PNG](native/2025-08-07.png) / [AX](native/2025-08-07.ax.txt) |
| 2026-06-28 | 隐藏 | 隐藏，延期未提前恢复 | [PNG](native/2026-06-28.png) / [AX](native/2026-06-28.ax.txt) |
| 2026-07-11 | 隐藏 | 隐藏 | [PNG](native/2026-07-11.png) / [AX](native/2026-07-11.ax.txt) |
| 2026-07-12 | 隐藏 | 恢复显示 | [PNG](native/2026-07-12.png) / [AX](native/2026-07-12.ax.txt) |

[机器记录](native/result.json)保存日期、相机、renderer与实际目视结论。七例同camera32.02/130.744、distance52641.3、viewport1211×865，无budgetDrops。[Current最后状态](native/current-final.png)显示南段、隐藏北段；[恢复设置](native/settings-current-restored.ax.txt)确认Current。历史北段几何风险不关闭；未执行新原生路线求解。

本次取证协调：52,814/92,216、失败6暂停；原生检查结束后恢复，AX确认52,859/92,216运行中，失败仍6、planDigest不变。见native/alignment-batch-resumed.ax.txt。主应用已置前，保留Current肥萨线视点。
