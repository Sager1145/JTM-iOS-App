# 铁路源数据中心

原始下载、标准化输入、候选与审查输入、地图参考集中在 `local/`，仅本地保存。`catalog.json` 标注每组原路径、集中路径、用途、文件数、体积和原先的 Git 跟踪数量；`local/inventory.jsonl` 按文件记录位置与分类。原有下载旁注、来源登记、许可和版本记录随文件保留。缺少来源/版本的条目明确未核实，不补造日期或视为官方依据。

仓库现有输入已迁移为一个实际副本，原路径通过本地符号链接继续供构建器访问。链接同样被忽略。后续恢复源文件到 catalog 指定位置后，可运行：

```sh
python3 app/scripts/railway/link-local-sources.py
```

命令只创建缺失链接，保留已有文件；不会下载、验证全国数据库或触发构建。新 clone 不包含 `local/`，运行应用使用已构建数据库，重建源数据则需要另行恢复对应下载与旁注。

| 集中位置 | 内容与使用边界 |
| --- | --- |
| `local/raw/n02/` | 官方 N02 原始历史版本、2025 基线与提取片段；原始 CRS/许可以 `.prj`、下载旁注和 `local/history/jp/review-inputs/n02-provenance.json` 为准。历史构建器默认读取 `local/raw/n02/history`。 |
| `local/osm/degree-cells/`、`local/raw/osm/jp/` | 已下载 OSM/Overpass 铁路参考缓存与构建提取。degree-cell 缓存保留 fetchedAt、endpoint、bbox；缺少 database timestamp/version/query，不能宣称当前全国完整覆盖。OSM 与官方轨道分别作为证据，不按距离融合成物理连接。 |
| `local/history/jp/` | 历史身份、开闭与候选生成输入；来源登记和人工审查结论保留。 |
| `local/timetable/` | 时刻表来源、标准化实体、候选、审查、构建 manifest 与常规列车 overlay 输入。`derived/` 的 SQLite/投影产物继续留在原发布路径。 |
| `local/station-names/`、`local/station-english/` | 官方页面下载、名字提取、候选与人工审查输入；编译后的站名表继续发布。OpenCC 的发布许可/NOTICE 另保存在 `attribution/OpenCC/`。 |
| `local/apple-maps/` | 网络参考、捕获图片与旁注，供显示对齐使用；不能证明官方铁路拓扑。 |
| `local/china/crtrainroute/` | 固定 CRTrainRoute 版本的中国铁路 JSON 原件与分省候选库；[接收清单](china-crtrainroute.json) 记录历史接收范围。该成品图不直接进入运行时，不能由坐标邻近自动产生连接。 |
| `local/china/osm/`、`local/china/evidence/` | 固定 Geofabrik 原始 PBF、完整节点/轨道/关系提取和官方站名、站序证据。[中国生产清单](china-production.json) 与 [运行时来源说明](../app/public/rail/cn-2025.sources.md) 记录实际接入及覆盖边界。 |

OSM 缓存和 N02 下载从同机器的 Web/builder checkout 复制导入；外部原件保持，未改那个 checkout 的索引。集中目录是本仓库的来源入口。美国/加拿大退役备份及旧构建快照仅在 catalog 中列位置，仍原位保存，不打开、迁移或重新打包。

## 发布边界

`.gitignore` 排除集中数据、原路径兼容链接及原始 GIS 格式。此前跟踪的输入已从 Git 索引移除，实际本地文件保留；未来提交不会带入它们。这个操作不改写历史提交，也不执行 commit/push。

继续发布构建数据库及其必要的运行时结构：`app/public/rail/` 的线路包、display 缓存和归属说明；`app/data/rail.db`、`train_timetable.sqlite3`、`train-service-history/derived/`、`stations*.json`、`rail-sections*.json`、编译后的站名表；已审查的物理拓扑、历史 overlay、直通服务资料和样例行程。JSON solver 图也是构建数据库，不能因含有 N02 来源身份就删掉。构建代码、局部修正规则、生产回归 fixture、来源 URL/许可说明仍保留，以便说明产物和重放修正。

原始数据被忽略不免除构建产物的来源归属和许可要求；公共说明仍保存在 `app/public/rail/*.sources.md`、相关 `.sources.md` 和 `attribution/`。

## 中国候选源复建

2026-10-18 接收的 CRTrainRoute 固定版本为
`d75307df9c812abf1259b86b75202ba7b0048679`。原件位于
`local/china/crtrainroute/<commit>/`，只保留 JSON、README 和 LICENSE；不读取成品 pickle。
归属说明见 [CRTrainRoute attribution](attribution/CRTrainRoute/README.md)，
比较结果与原始 OSM 生产接入依据见 [研究报告](../docs/reports/sources/crtrainroute-study-20261018.md)。

恢复该提交的 `data/geojson/*.geojson`、`data/stations.json`、
`data/station_names.json`、`data/station_lanes.json` 后，在仓库根目录运行：

```sh
python3 app/scripts/railway/import-crtrainroute.py \
  --source-root railway-sources/local/china/crtrainroute/d75307df9c812abf1259b86b75202ba7b0048679 \
  --output /tmp/railmap-cn-candidates \
  --manifest /tmp/railmap-cn-intake.json \
  --source-commit d75307df9c812abf1259b86b75202ba7b0048679 \
  --retrieved-at 2026-10-18
```

输出目录和 manifest 必须是新路径；重建不会覆盖已保存证据。`--retrieved-at`
填写自己的实际取得日期，不是 OSM 现势日期。导入器保留所有轨道类型和原始属性，
不合并 way、不把车站坐标冒充 WGS84、不把别名记录当作物理连接。
缺少原始节点/关系、客运线路站序和站轨归属的记录继续留在候选层。

生产 CN 使用另一条有原始拓扑证据的构建路径，命令见
[CN 来源说明](../app/public/rail/cn-2025.sources.md#rebuild)。香港高铁全段归 CN，
澳门轻轨全段（包括横琴）归 MO，其余香港铁路归 HK；三个数据集不建立跨区图连接。
