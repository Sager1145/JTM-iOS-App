# ADR 0013 铁路身份注册表：实施报告（2026-10-19 — 2026-10-20）

本报告记录 [ADR 0013](../../decisions/0013-railway-identity-registry.md) 从方案到实施的全过程：做了什么、为什么这样做、如何验证、还剩什么。决策本身以 ADR 为准；本文是实施记录与交接说明。

## 1. 分支与状态

| 分支 | 最新提交 | 内容 | 状态 |
|---|---|---|---|
| `adr-0013-identity-registry` | `9f0330b94` | P0–P2、P1b、括号站名字段、JP 带来源调研、身份迁移 M1–M5 | 已推送 origin，未合并 main |
| `adr-0013-p3-cn` | 本报告所在提交 | 在上一分支之上：P3 中国大陆（CN）运营者合并、上位运营者、线路、公司身份 | 已推送 origin，未合并 main |

两分支都基于 main `daeae8516`。合并 `adr-0013-p3-cn` 即包含全部工作。

## 2. 目标回顾

为 JP / TW / HK / MO / KR / CN 六个地区的全部铁路建立**不依赖名字的稳定身份**：公司（`op`）、线路（`ln`）、线路分段（`lp`）、站群（`cx`）、公司车站（`st`）、停靠点（`ls`）、运行模式（`rp`）、共用站房（`fc`）。区分不同公司、不同线路与同名不同站；乘车记录引用公司车站层；导入只需最少信息，同名站以 `站名 (CC, 线名)` 区分，括号部分在界面上以小字显示。北美已退役，不在范围内。

## 3. 按阶段的实施记录

| 阶段 | 提交 | 主要内容 |
|---|---|---|
| 0 冻结 | `13e82fcac`、`11d1fe126` | 冻结输入清单、事实 owner、受保护文件（`docs/reference/railway-identity-phase0-freeze.md`、`app/data/registry/phase0-freeze.json`） |
| P0 账本 | `13e82fcac`、`11d1fe126` | 只追加 JSON Lines 账本 `app/data/registry/<region>/*.jsonl`；唯一写入入口 `mint-registry.mjs`；校验器 `validate-registry.mjs`；`rail.db` schema v4 镜像。首次铸造 90,932 个 id |
| P1 | `fd402ac3b` | 运营者改名映射、`rp:jp:1`（上野東京ライン）、统一 `name` 表、app 用注册表 bundle；乘车记录可选 `station_id` / `operator_id`（派生缓存，每次加载/导入/保存重新推导） |
| P1b / P2 / 括号 | `01072a7b4` | `站名 (CC, 线名)` 语法与 fail-closed 解析、小字限定词；历史 crosswalk 与带日期的运营关系；括号站名拆为 base / bracket / position / kind / status（reserved、planned、closed、suspended、historical）独立字段 |
| M1 | `69676356a` | bundle 反向映射（st → 站码、站群、名称、线路；op → 标签、logo、旧身份码）、`RegistryIdentity` facade；覆盖率 JP 1530/1537、TW 470/476 停靠点可唯一解析 |
| M2 | `f4d1cad8f`、`52857ae9f` | 显示、搜索、筛选、品牌改读 id；联运公司用 `operator_ids`；搜索词按子串匹配注册表公司名 |
| M3 | `b575ef10c` | 求解器输入由 `station_id` 取站码；区段加 `from/to_station_id`；运营者提示来自 op id；路线缓存版本 28 |
| M4 | `dc61bbbc1` | 所有站点/公司输入（文字、OCR、换乘指南、JR East、ChatGPT、选择器）经注册表解析；移除旧规则回退 |
| JP 调研 | `47ae5ee7f` | 带来源网络调研：44 条线路、122 个共用站房、86 条换乘 link（非物理）、5 个公司别名、57 项历史覆写 |
| M5 | `45d494fcd`、`3e132ae27`、`9f0330b94` | 注册表状态 ready / pending / unavailable：pending 时等待或保持未解析，settle 后重跑；旧规则只保留在加载/导入升级与求解器代码级图中；后台预加载、内存升级、导入等待 |
| P3 CN | `de616191b`、`f08100024` | 见第 4 节 |

## 4. P3：中国大陆

- **运营者**：OSM 数据中 168 组共用 12306 站码的运营者组合经带来源调研（中文维基、百度百科、官方页面），得到 17 项合并（同一法人的不同写法、简称、英文名、繁体写法）与 9 组上位—下属关系（如 `中国铁路` → 18 个铁路局；`北京地铁`、`杭州市地铁集团` → 其运营分公司）。账本新增四类审定输入：`operator-merges.json`、`line-operators.json`、`generic-operators.json`、`official-code-schemes.json`。
- **结果**：共用站码冲突 699 → 184（CN 183 + TW 嘉義 `TRA-4080` 1）。余下组合为调研判定为不同公司或无法核实者，保持报告、不臆断。
- **线路**：按 OSM `route_master`（319 个）及同一 relation 的分支，把 3,348 个 `lp` 归为 434 条 `ln`；每组引用 OSM relation URL。原始数据存于 `app/data/registry/cn/osm-route-masters.json`，可用 `app/scripts/railway/build-cn-line-crosswalk.mjs --check` 复现。
- **公司身份**：`app/scripts/build/build-cn-operator-identities.mjs` 由注册表生成 198 个 CN 运营者身份（法定名为运营者自身写法；拉丁写法入 aliases，繁体入 zhHant），`OperatorIdentityTests` 由 main 上的 434 项失败变为通过。
- **退役 id 可解析**：合并共退役约 1,700 个公司车站与 2,600 个停靠点，全部有 alias；bundle 携带 old → live 映射，RailCore 解析并在加载时改写旧 id。

## 5. 工作方式

- **执行**：先由 Grok（`offload.sh`）执行，Grok 额度用尽后改由 Claude Sonnet 子代理（implementer / verifier / scout）；每个阶段都由不同模型（Claude Opus reviewer）独立评审后再提交，评审发现的阻断问题全部修复后才合入。
- **调研**：每个审定决定都保存实际抓取的来源 URL；无法核实者标为 unverified，不进入账本。
- **验证**（按 `ios/VERIFICATION.md`，只做相关检查）：账本校验器（规范化、只追加、受保护文件）、node 测试、过滤的 Swift 测试、增量 app 构建、模拟器上的 app 测试；P3 后一次完整 RailKit 对比基线。

## 6. 发现并处理的问题（摘要）

- iCloud 同步目录与 git fsmonitor 导致提交挂起 → 对本仓库的 git 命令使用 `-c core.fsmonitor=false`。
- 账本铸造的幂等性缺陷（撤回后恢复的历史运营事件每次重复追加）→ 按事件当前状态折叠修复。
- 合并目标本身为上位运营者时 62 个退役站缺 alias → 修复并由校验器强制“每个非缺席退役都有 alias”。
- 注册表加载中求解返回无路线、导入回退旧规则 → 统一 ready / pending / unavailable 模型。
- 研究工具使用中曾把用户邮箱放进对 overpass-api.de 的 `User-Agent`；此后只用通用标识。

## 7. 未完成与关口

- **P5（网站仓库）**：包的区间上写出注册表 id，再把历史匹配由“名字 + bbox”切换为 id；丸ノ内線未映射站码；TW 左營 / 苗栗站群归属。本仓库不改网站构建器。
- **未决调研项**：见各地区 `app/data/registry/<region>/station-derivation-exceptions.json` 与 `jp/facility-review-report.json`；CN 余下 183 个共用站码冲突。
- **main 上既有的测试失败**（干净的 `daeae8516` 完整运行：26 个套件；P3 修好 `OperatorIdentityTests` 后余 25 个）：列表见 ADR §13。
- **测试缺口**：store 级“最新落地优先”测试未强制时序（需要 store 内测试钩子）。

## 8. 常用命令（在 `app/` 下）

```bash
node scripts/build/build-rail-database.mjs --out /tmp/core.db --quiet
node scripts/build/mint-registry.mjs --db /tmp/core.db --root data/registry --at YYYY-MM-DD --dry-run
node scripts/railway/validate-registry.mjs --root data/registry --db /tmp/core.db --base main --freeze
node scripts/build/export-registry-bundle.mjs --check
node --test scripts/railway/validate-registry.test.mjs
```

任何退役都需显式 `--allow-retire`；账本只追加，不手改已有行。
