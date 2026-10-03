# 大崎—品川旧格式兼容修复，2026-10-01

本次直接用户要求取代此前“有乐町南侧提前合流”的显示约定。日本
compact-v1 包升至 2025.5.2；仍为 657 条线路记录、9,578 个区间、
10,231 条站点记录。全部原始站点行、区间坐标／公里数和 structure
与本次修改前逐行完全一致，没有改写路由／统计的物理输入。

## 已核实的来源

- [MLIT N02-25](https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N02-2025.html)：
  官方页面于 2026-10-01 复核，基准日 2025-12-31、JGD2011 经纬度、
  CC BY 4.0。重新从保留 ZIP 的 Shift-JIS shapefile 按 cp932 读取，
  保持六码站码及原始精度，没有使用取整后的 UTF-8 副本。源文件为
  旧 Web 仓库 `app/data/raw/railway/jp/N02-25_GML.zip`，SHA256
  `aaf76af133b2e771e538fabc4646d2e443dc1d5a67b221382a28d744e706cc9f`。
  检查范围内 27 条 JR 源区间没有大崎支线的曲线；旧 N02 主干的两处分岔为
  `[139.73762,35.62049]`、`[139.7328,35.61677]`。
- 保留 OSM 2026-08-18 快照，WGS84，© OpenStreetMap contributors，ODbL 1.0。
  `tokyo-southern-branches-overrides.json` 中 69 个 way 的坐标与缓存逐一一致，
  缓存 SHA256 为 `6ab2be77d2c167969da6e1470abe57aa59504eb0e4624236875bb03e32c70b84`。
  两个方向各自保留原始轨道测绘，不能当成官方 N02 几何或互相镜像。
- 东京隧道的已注册证据在旧 Web 仓库
  `app/data/raw/railway/jp/evidence/tokyo-station-platforms.json`，SHA256
  `861a60f2c4b632af005009eeef2d88a5ba0ef3651ab043980b4adac6d9bc742f`。
  东京—新桥 ways 为 759433005、210358354；新桥—品川为 210358354、
  210358355、244134593、852774337、1313812927。原 compact 物理区间
  与证据的 28／65 个重构顶点完全一致；错误出在后加显示覆盖。
- [JRTT 大崎站接续工程图](https://www.jrtt.go.jp/construction/asset/constUtwr-2_03.pdf)
  和 [JR 东日本运营图](https://www.jreast.co.jp/press/2019/20190906_ho01.pdf)
  支持大崎—西大井与品川支线相互独立的拓扑。工程图有历史年代，运营图
  是服务关系证据，均不能作为逐米 WGS84 坐标。保留既有 evidence 中的
  来源、检索日期及使用限制。

## 修复及兼容约定

1. 恢复东京—新桥的原隧道线位，新桥地下圆点使用既有 OSM 轨道接缝，
   距原 N02 点 1.5 米，去除往返小尖刺。品川圆点在显示上沿用旧在来线
   锚点；最后 350 米以明确的 smoothstep 显示端点映射接入，不能将它
   解释成隧道与地面线之间的新物理道岔。品川南侧复用旧 N02 共线段，
   保留大井町方向和目黒川侧的两处分岔。
2. 大崎支线新增车站原有 `jtm_override`、`physical_line_id`、`source`
   属性触发 ADR 0010 的四条格式错误。改为八个标准字段及已存在的可选
   `display_line_id`；来源在证据注册表，重复回放标记为 GeoJSON Feature
   的 foreign member。Point 几何继续合法，未为兼容性伪造站台线段。
3. 配对行继续使用旧 `alignmentOf`／`alignmentRole` 格式，并补齐基线的
   `alignmentPairs` 反向声明；铁路上下行未知，仍为 unassigned。现有
   forward／reverse 限制保留，不推断未知上下行。
4. 移除额外附加的平行山手货物线显示主干。两条北接入段改为复用旧山手
   N02 代表线，南部汇合后复用旧总武／品鹤 N02 尾段；各接点的显示投影
   在 15 米以内。南北源道岔坐标和北接入源几何仍在 metadata/evidence。
   最前／最后 200 米允许显式显示端点映射；原 segments 不变。

## 回放与实际检查

`python3 app/scripts/railway/repair-tokyo-platform-approaches.py` 回放包及
南部兼容显示，`--check` 检查包；车站表由
`repair-tokyo-southern-branches.py:repair_stations()` 回放。两个流程均幂等。
独立原始分支候选仍可用南部脚本输出；需要兼容显示候选时使用
`--legacy-display --output /tmp/candidate.json`。

- `python3 app/scripts/railway/validate-station-tables.py`：PASS，原四条错误消失。
- `python3 -m unittest discover -s app/scripts/railway/tests -p test_tokyo_southern_branches.py -v`：
  PASS，7 项，涵盖源接缝、方向独立、旧属性格式、源输入保持、共享接点和尾段。
- `node --test app/tests/tokyo-platform-approaches.test.mjs app/tests/tokyo-conventional-default.test.mjs`：
  PASS，14 项，涵盖新桥地下路径、品川显示合流、两个旧分岔、JS 最终 displayParts、
  双向 NEX 选择、旧普通车推断和已有大江户线修复。
- 包预检命令：`python3 /Users/sager/.codex/skills/jtm-railway-audit-repair/scripts/audit_jtm_packages.py --repo . --countries jp --json /tmp/jtm-tokyo-after.json --limit 2`。
  0 ERROR；20 个既有全国 WARNING 与修复前 issue 列表完全一致，没有本范围新增警告。
  没有把全国其余警告当作已修复。
- 所有 657 行的物理 stations、segments 和 structure 与修改前逐行一致。
  品川显示接入段没有向北反折，重放不再恢复有乐町合流。
- Swift 测试断言已同步到本次显示约定，尚未编译／运行；不能将 JS 检查
  当成 Swift 或 MapKit 最终渲染的通过。

## 最终整合边界

本 chat 只修改日本源、回放脚本及针对性检查。依用户已授权的联合整合，
最终整合 chat 统一重建受影响的日本 display-lanes、port-fixtures、车站目录、
路由缓存、时间表／数据库及 App 包，并执行最终 Web/iOS 验收。此次没有
启动重 App 编译或 Simulator，没有改动北美数据或任何共享派生输出。
旧派生文件不能用新源 hash 直接重标为已验证。

源格式／JS 定向检查：PASS。最终新旧 lanes 下的像素接入、Swift parity、
新 App 的网络／乘车轨迹／播放及多缩放级别画面：INCOMPLETE，交由唯一
最终整合／原生验收 owner；本报告不宣称两个客户端已完成最终视觉验收。
