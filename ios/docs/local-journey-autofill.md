# 本地行程自动填入与列车种别

在新建行程的线路步骤，或已有行程的线路区块，选择「起终点自动填入」。起终点可直接从本地车站库选择，无需先填写中间站、车次或时间。选择候选路径后，编辑器保留每个物理区间的线路 ID、区间代码和运营公司，并补齐未填时间的途经站。匹配到的既有车站时间会保留；删除手工填写的车站时会先显示替换确认。未再修改草稿时可撤销整次填入。

日本运营线路和直通系统仍可单独显示和选择名称，但服务目录不再为物理搜索补边。候选路线不等于完整路网，换乘关系、相同站码、同名或邻近都不能单独证明轨道相通。当前 compact-v1 候选搜索没有完整路网覆盖声明，也没有将独立物理连接登记表映射为候选行之间的连接，因此不能宣布唯一可达或自动跨行拼接。底层物理图使用独立的已审核连接登记表；候选搜索与该表的对应关系尚待完成，不能靠运营系统名称恢复跨线路候选。

可添加有序必经站，在地图编号或候选卡片中选择走向；卡片保留 VoiceOver 操作。中间站继续作为推测通过站显示，默认“通过、时刻未知”，不推测实际停车或时刻。搜索结果显式区分截断和路网覆盖未确认；只有两者均完整且唯一可达才允许自动填入。用户明确选择候选仍可应用。

没有正确候选或不确定时选择“保留为待确认路线”，随后正常保存行程。`route_confirmation: pending` 随记录保存，地图求解和精确里程排除该记录；已有服务名称和原始记录保留。全程路径明确选择后标记 confirmed；只修改一部分不能清除整条行程的待确认状态。

「线路列车种别」可浏览全部日本物理线路。列车种别按官方资料的适用区段展示，包含来源链接和证据日期。没有资料的线路显示待核实。日期明确的行程只把在证据日期区间内的种别用于选择。数据库中的时刻片段只展示已确认的日期和车站，空缺时刻保持空缺。

## 代码与数据

- `RailCore/LocalJourneySearch.swift`：有向物理区间搜索，保留重复车站的出现位置，最多返回三个较短候选，限制展开规模并响应取消。
- `RailCore/LocalJourneyAutofill.swift`：将路径变成待确认草稿，保留已有访问身份和时间。
- `RailCore/JapanThroughServices.swift` 和 `Resources/japan-through-services.json`：按区段锚定的运营系统／直通目录。
- `RailCore/LineServiceCatalog.swift` 和 `Resources/line-service-catalog.json`：列车种别、明确运营日期的时刻片段及直通前后班次引用。
- `RailMap/LocalJourneyFillView.swift`：起终点选择、本地候选、线路种别及资料来源。
- `app/data/conventional-timetable/overlays/`：公开官方时刻表的复核扩充输入；JSON 与旁边的 `.sources.md` 一起维护。

该功能读取同一份 `jp-2025.json`；没有增加另一份几何数据。新 JSON 资源由 SwiftPM `Resources` 自动打包。现有特急 SQLite 数据库保持独立。

## 重建与导入

种别目录与 `app/data/conventional-timetable/manifest.json` 中的已复核公开时刻表输入：

```sh
python3 ios/tools/build-line-service-catalog.py
python3 ios/tools/build-line-service-catalog.py --check
```

叠加已复核的公开时刻表输入：

```sh
python3 ios/tools/build-line-service-catalog.py \
  --reviewed-input app/data/conventional-timetable/overlays/kanto-public-reviewed.json
```

多个输入分别传入 `--reviewed-input`。使用同样参数执行 `--check`，校验资源可重现。

ODPT 导出的导入命令：

```sh
python3 ios/tools/import-odpt-line-services.py \
  --export /path/to/licensed-export.json \
  --mapping /path/to/reviewed-identities.json \
  --provenance /path/to/provenance.json \
  --output /path/to/normalized-overlay.json
```

此导入器不访问网络。映射必须明确标出 ODPT 站点、线路、运营公司、列车种别与运营日期，无法确认的身份拒绝导入。原始 `previousTrain`／`nextTrain` 引用保留，以供后续核对跨公司衔接；没有引用的班次不自动推断直通。

## 验证与覆盖边界

旧回归中的跨公司／分段同站自动连接不再属于正确行为；相关断言须改为无证据时拒绝连接。当前验收覆盖搜索截断、覆盖未确认、有序必经站、无证据连接拒绝、推测通过站保留、待确认往返与里程排除。测试文件存在不等于本轮已通过，实际执行结果另行记录。

所有地区均使用本地物理搜索，但已复核的直通目录与时刻表是部分覆盖。来源和剩余资料缺口分别见 `app/data/japan-through-services.sources.md` 与 `app/data/line-service-catalog.sources.md`。未知状态不能解释为没有列车，也不能解释为种别已全部核实。
