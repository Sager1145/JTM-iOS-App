# 站场错误直线与折返修复（2026-09-08）

本次修复涵盖 LA 原始报告，以及扩展检查中确认的同类显示、接站数据和分支连接问题。

## 显示几何

- Web 与 iOS 使用一致的生产弯道保护：依据稳定的轨道顶点计算偏移方向，补足线路偏移过渡的采样，并在清理人工折叠时保留站点和真实弯道。紧密内弯的偏移按可用轨道长度收缩，避免数个普通转弯组合成自交。
- 真实折返的两个共享邻接顶点均保留。LA Pacific Surfliner 不再因删除一个邻接顶点而改变站端方向；同一规则也恢复了日本、台湾等真实折返处的邻接顶点。
- 共享端点转角达到 150° 时，两侧使用相同的入站法线，不再沿接近零长度的角平分线放大到 2.5 倍。正常并排偏移保留，额外伸出的站端尖角消除。
- 如果现有轨道空间无法容纳最低圆角半径，保留该处测绘顶点，不延长轨道或跨越弯道来制造圆角。

下表为已确认窗口相对于测绘曲线的最大偏离，单位米。使用相同窗口、缩放和线路偏移参数比较修复前后；剩余偏离包含正常的并排显示距离，不等于线路测绘误差。

| 窗口 | 修复前 | 修复后 |
|---|---:|---:|
| LA Ventura County，z16 | 129.0 | 4.1 |
| Hartford，z16 | 162.7 | 3.6 |
| NYC Adirondack，z16 | 86.9 | 4.9 |
| Chicago Carl Sandburg，z16 | 71.9 | 1.2 |
| Newark NJ Transit NEC，z16 | 72.9 | 3.7 |
| Palmetto 弗吉尼亚窗口，z16 | 46.1 | 1.3 |
| South Shore 芝加哥窗口，z16 | 32.3 | 3.6 |
| NYC C，z16 | 29.2 | 1.2 |
| Aldershot VIA，z13 | 85.7 | 9.6 |
| 南海机场线，z13 | 25.9 | 11.0 |

复验还包括这些线路的其他窗口与 Mendota 站点。TTC 505 和大阪环状线的较大剩余位移与关闭共线替换后的结果一致，属于既有并排显示距离，未据此改动原始轨道。Crescent 的原始错误接站窗口已被下述源数据修复替换，不能再用旧窗口坐标计算显示偏差。

## 接站数据

修复 Acela、Silver Meteor 在费城的错误西侧接站，以及 Crescent、Silver Meteor 在华盛顿的错误北向折返。截图复验还确认 Pennsylvanian 原始 GTFS 进出费城时包含穿越车场的斜直线：单侧直线约 2.308 km，相对正确走廊偏离约 399 m。这两段也已修复，真实折返保留。总计修改十个站间区段、五个站点成员坐标及对应求路区段，重算有关里程。

替换几何全部来自包内已有的已核验 Northeast Regional、Keystone FRA/BTS NTAD 轨道与 Palmetto 官方 GTFS 轨迹；拼接点使用两者原有的相同顶点。未新增估算坐标或直线连接。华盛顿的南向区段通过 First Street Tunnel，费城使用下层贯通站台走廊。

可重复修复脚本、原始/替换窗口及哈希见 [repair-na-station-approaches.py](../app/scripts/railway/repair-na-station-approaches.py) 与 [修复目录](../app/scripts/railway/na-station-approach-repairs.json)。输入窗口变化会要求重新核验；已修复数据再次运行不变。原始下载归档不在工作区内，使用保留数据的来源与局限已明确记录在 [US 数据来源](../app/public/rail/us-2025.sources.md)。

## 服务分支

Jamaica 的 Grand Central—Jamaica 与 Jamaica—Atlantic Terminal 是不同终点分支。新增 [审核边界](../app/public/rail/display-chain-boundaries.json)，禁止仅凭连续 chain 编号把两者做成共同切线接头。两端仍使用同一站点身份；构建过程验证边界编号、站点和坐标，避免数据更新后套用到其他位置。Web 与 iOS 均消费同一份生成结果。

依据为 [MTA 官方时刻表](https://www.mta.info/document/188996)。伊万里的资料能证明站台及服务方向不同，但不足以据此改写整条命名铁路的物理拓扑，因此未新增断开边界。LA、SFO、Exhibition Loop 等真实折返或环线保持原始走向；Rutland、Springfield、Keystone 未在轨道动作证据不足时改写源数据。

## 验证

- JavaScript：13 项测试通过，包含真实城市弯道、站点保留、偏移过渡、共享折返点与圆角采样约束。
- Python：580 项测试通过，包含接站来源顶点、拼接点、站点/里程/求路一致性、重复运行与新分支边界传播。
- 七区域结构预检：0 errors；最后一次 US 修复后复检仍为 0 errors。原 142 个候选警告之外，Pennsylvanian 恢复真实进站折返后新增一条 3.4 km 的 `SELF_OVERLAP`，与 Keystone 相同的共用进站轨道一致，保留。未把候选警告直接当作缺陷，也未把格式检查当作实际几何正确的证明。
- 已重建 `display-lanes.json`、原生显示数据及受影响跨端 fixtures。实际线路中的严格显示选项进入跨端对照，新增 LA 与 Hartford 的多缩放样例。
- 最终完整 `ios/verify.sh` 通过：541 项 Swift 测试、生成数据一致性、跨端契约、原生应用构建及项目静态检查均通过；66 组严格/合成描边样例逐点对照一致。
- iOS 全线路地图截图复验覆盖 LA、华盛顿、费城和 Jamaica。费城最终截图中的 Pennsylvanian 跨车场斜线已消失，沿曲线进入站台；Jamaica 不再形成错误的共享折返接头。截图必须等待线路图层完成加载，仅有底图和站点的冷启动帧不算通过。
