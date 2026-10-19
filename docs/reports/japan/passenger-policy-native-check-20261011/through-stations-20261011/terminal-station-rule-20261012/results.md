# 终点站显示规则（2026-10-12）

用户要求终点站点位于线路尽头，并在Apple Maps车站框中央设站。“车站矿”按上下文解读为“车站框”。规则已并入既有passenger-representative-display-policy-2026-10-11.md，不另建铁路清单。

拥有者为对应线路的displayStationCoordinates和相邻displayIntervalCoordinates，再经native builder生成parts/slot/显示测距；Swift/JavaScript最终站点必须与最终lane/follow路径末端一起检查。独立平台组分别定中心，终到线路结束不截断同站继续运营的其他线路，环线分片不作终点。只改变显示数据，不改physical坐标、统计里程或通行权限。

实际Main西高岛平近景ON/OFF已保存为nishi-takashimadaira-before-*，相机35.791895,139.645685,.003。对应高架平台框可辨，圆点与终到显示代表位于同一站区；该图是规则检查的原始证据，尚不构成精确框中心全量验收。当前未据屏幕目测批量改坐标。完整三田线26区间115最终视点证据位于mita/whole-line-final，输入未因本规则改动；不重新采集全国线路。

源与消费者复查：西高岛平compact/displayStationCoordinates/part首点均为[139.645685,35.791895]，anchor index 0、lane 0、无follow/family。当前终点圆点与最终线头已重合；底图框视觉中心约25px差异是待复核的输入锚点候选，不是builder centroid或datum偏移。JS rail-network.js建立anchor，rail-stroke.js在follow/lane/fillet后投影到final stroke；Swift RailMapCoordinator使用ContinuousStroke final strokeAnchors，端点合同已存在。本次新增的是明确的框中心取证/修复规则，未改这些正确消费路径。

沿原唯一列表逐站检查：箱根有非零lane、目黑三田/南北线有lane/follow，不能只移动annotation；框中心确认后同步站点与进路，并审查stationLaneByCode=0的终端收束是否符合独立公司/走廊身份。木次/京津端点为零lane且无follow/family，仍须按各自站框核对锚点。东京各独立平台组分别取中心，禁止全局同名站中心吸附。无已审核的框中心坐标时保留候选，不能从Main截图估算经纬度并称精确修复。

Complete-interval follow-up: user reiterated full intervals. Re-reviewed all 4 immutable native views (12 basemap/display/smooth panels) for Mita interval 0, Nishi-Takashimadaira 003104 to Shin-Takashimadaira 003112, including both ends and the final short tail. Current Mita line equals the recorded pre-Osaki package input exactly; no terminal geometry changed in this rule-only update. Reused evidence is disclosed, not counted as fresh captures. Main actual ON/OFF pair for the full interval saved as nishi-takashimadaira-shin-takashimadaira-full-interval-*; both endpoint dots visible, entire intervening corridor continuous. Final camera 35.7911,139.65,.012, network ON, 2 lines/2 overlays, budgetDrops0. The station-box-centre candidate remains pending. Each eventual terminal repair must recheck the full affected adjacent interval and any dependent family owner, not only the station crop.
