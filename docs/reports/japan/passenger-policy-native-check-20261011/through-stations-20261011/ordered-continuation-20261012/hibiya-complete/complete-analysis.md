# 第 25 条：日比谷线完整基线分析

2026-10-15，单聊天 root 操作和逐图审阅。按用户指定 rail-display-guideline.md 分开记录观察 O、现状 C 与建议 R。本轮没有修改生产几何、站点、图连接、样式或运行日期，也没有运行构建或测试。

## 范围与证据

- 22 站、21 个完整站间区间；站序与东京 Metro 官方 H01–H22 核对一致：https://www.tokyometro.jp/station/line_hibiya/index.html 。换乘标记不证明轨道相连。
- 三个独立原生检测 app 各 89 个本线视点，均为 captured89/pending0/failed0。root 打开各 00–22 联系图，逐一查看全部 267 个 smooth+底图合成视图。磁盘另外保存 basemap/display，不能把 801 个保存面板说成全部独立打开。
- 原始主 app 实际逐个启动 21 个完整区间和中目黑、北千住 2 个边界区域，保存并查看 23 对、46 张 network ON/OFF 图；actual centre 符合相机计划，预算丢弃为0。各区间全路径及两端可见；07 另打开原尺寸图确认银座端点。不是只检查站点近景，也没有用 inspector 零 lane 预览替代 Main。
- Apple Maps 原生 Transit 实际区域图：apple-maps-transit/nakameguro-regional-transit.png、kitasenju-platform-corridors.png。选择 Tokyo Metro 身份核对自身走廊，未取站内结构图。
- source-line.json 与当前正式 compact 行逐字段相等。五个已安装 app 的 compact 日比谷线行已做相同定点比较；这不等于声明整个 app 二进制或全部派生块完全一致。

## 观察 O

三个检测 app 对中目黑出站、广尾南侧、饭仓、霞关护城河角、筑地、人形町南侧及三之轮—南千住弯道给出可见轮廓差异。它们是待修显示候选，地下 Transit 示意线不提供测量级实际隧道轨道。Main 全区间未观察到明显人为反向 U 或新造跨线连接；这一结论不替代真实道岔通行方向的独立证据。

中目黑的日比谷线出站路径与东横线分离，不能沿红色东横线继续延伸日比谷线来“找终点”。北千住同一大蓝色站场填色中含不同系统/层位；日比谷/东武、千代田、JR、TX 不能平均成一个中心点。南千住车场的扇形轨道不属于所选客运代表线。

22 站的完整本线乘客平台框中心仍未验收；两个端点区域复核也不能替代完整平台框验收。北千住是直通/业务边界，不依赖站序强制截为物理尽头。

## 现状 C 与后续 R

本线无 displayStationCoordinates、displayIntervalCoordinates、follows 或 branch lead-in 覆盖。本轮保留生产数据；先以分离的本线走廊/平台组确认候选，再以显示覆盖修复，物理图和日期规则保持其独立证据要求。完整逐区间观察见 interval-review.json。

## 采集异常与排除

primary interval18 point4 首次 MKErrorDomain2。UI 全局“重试失败”把失败项重置后调用全局 start，从而先运行全局优先队列；暂停后排除102个非本线视图，再用当前线快捷键恢复仅本线剩余1个，最终本线89/0/0。

secondary 初次快捷输入未持久化，仍选山手线；立即暂停，保留并排除70个非本线视图。改为 AX setValue→观察文字→Return→观察选中 lineID/起站→当前线采集。third 无额外视图。所有联系图和计数按精确 lineID 过滤；全局计数191/159不能当作本线通过数。异常记录不表示已经修复工具代码。

## 结论边界

完整基线分析完成，修复/地理及22站平台验收待续。宇品/皆实修复、富山其余13站框、半藏门地理/平台验收及已拒绝的予土方案继续保留待办；没有宣布全部线路查验完成。下一条按原列表为第26条丸之内线。
