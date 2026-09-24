# 列车品牌与跨线行程

列车列表、选中行程卡片和详情页共用 `JourneyBranding`。特急列车先查询列车品牌数据库；没有专属图稿时，退回列车运营公司的 logo；运营公司也没有 logo 时显示默认列车图标。任何情况下都不能使用线路 logo。车站中的线路标识不受此规则影响。

数据库位于 `ios/RailKit/Sources/RailCore/Resources/train-service-branding.json`，通过 Swift Package 资源随应用打包。每项包含稳定的 `id`、`region`、日文／英文别名 `names` 和可空的 `logoPath`。匹配使用列车名称及 `number_en`，兼容全角字符、大小写和车次后缀；较长名称优先，避免「サフィール踊り子」匹配成「踊り子」。未收录的列车仍可通过「特急」或 “Limited Express” 等明确类型使用默认图标；「特快」只在台湾／香港／澳门计入特急，日本的「特快」是「特別快速」的简称（如中央特快），不属于特急。以拉丁字母开头的品牌名（如 Haruka）还需要车次上下文——匹配前不能紧跟字母、数字或连字符，匹配后（去除空白后）需为空、以数字、「号」、“no.”／“no ” 或左括号开头，否则视为无关名称（如车站名 Kinosaki-Onsen）中的巧合子串。

专属图稿放在 `app/public/rail/service-logos/`，来源与署名见该目录的 `README.md`。当前使用 iOS 可直接解码的 PNG；新增图稿后，将对应条目的 `logoPath` 设为 `/rail/service-logos/<filename>.png`。没有合适图稿时保留 `null`，交由运营公司 logo 或默认图标兜底，不填线路 logo 或车身照片。车辆品牌只匹配明确写出的品牌名称，不将某一车型标志套给所有可能使用该车型的列车。

跨线识别接受特急／快速等类型、明确的直通或跨线描述，以及已记录的不同线路或运营公司。普通单线列车不会因为共用轨道而改变线路身份。这类跨线证据只来自已记录的行程区段（`routeSections`），路线策略候选线路和 `train.company` 都不计入，因为它们可能从未真正乘坐过。识别尚不完整时保留已记录区段中识别未覆盖到的线路（按去除空白、NFKC 归一化并把「〜本线」等价于「〜线」的规范形式比较），补充识别出的线路和运营公司。

验证：`SCRATCH=/private/tmp/jtm-service-verify ios/verify.sh --swift`。单元测试覆盖名称匹配、默认标识回退和跨线信息；构建检查还会验证数据库中所有非空图片路径都已打包。

匹配前会剔除「（宇都宮→日光）」这类带箭头或「行／方面」的方向括号，避免站名（日光、北斗、富士、有明）误判成特急。运营公司 logo 查询接受短名（JR東日本）、法定全名（東日本旅客鉄道）以及「/」连写的联合运营；候选顺序为已记录区段的运营公司、`company` 字段、路线策略、最后才是识别出的运营公司。资料库已收录 JR 六社 2010 年以来的现行及停运特急，以及小田急／京成／西武／東武／近鉄／南海／名鉄／阪急／富士山麓／長野電鉄／京都丹後鉄道的有名称特急（停运列车保留以辨识历史行程）。假名开头的列车名若紧接在其他假名之后（如「ゆりかもめ」中的「かもめ」）不视为匹配；更长的目录名（リレーかもめ）优先匹配。

## 特急停靠站模式

`TrainServicePatterns` 读取 `ios/RailKit/Sources/RailCore/Resources/train-service-patterns.json`，为每条特急路线记录一份停靠站清单，供编辑行程时一键套用。每项包含 `patternId`、关联的品牌 `serviceId`、日文名称 `name`、以「/」连写的法定运营公司 `company`（经 `OperatorBranding.companyLabel` 转换为短名）、说明用 `label`、起讫站 `origin`／`destination`、带固定 `sourceCode` 的必停站对象 `stops`、以及同样带代码的 `optionalStops`／`via`／`confidence`／`source` 等参考信息。套用一个模式时，`stops` 中的所有车站都写成 `passenger_stop`（首末两站除外），`optionalStops` 记录的「一部停車」车站不会自动插入，而是留给使用者按需添加。同一品牌名称但不同路线的列车——例如サンライズ出雲与サンライズ瀬戸共用「サンライズ」品牌、共同从東京始发，却分别开往出雲市与高松——各自登记为独立的 `patternId`，不合并成一条记录。单元测试会核对每个必停和一部停站的 `sourceCode` 在紧凑站点包中存在且名称一致；`via` 名称仍与 `app/data/stations.json` 核对。运行 `python3 ios/tools/build-train-service-station-refs.py --check` 可对全部引用进行消歧复核。`confidence` 标注数据可信度（如 `medium`），提醒尚未逐条核对到官方时刻表的条目。

### v2 字段：运行方案、生效日期、经由线路与完整度

2026-09-23 起每条模式还带有：`lines`（按顺序列出经由线路，名称与 `app/data/rail-sections.json` 的 `N02_003` 一致，保留「本線」，测试按 `canonicalLineName` 折叠比较）、`validFrom`／`validUntil`（ISO 日期，`[validFrom, validUntil)`；`validUntil` 为排他的失效首日，空边界表示资料未定或开放边界，不保证现行）、`completeness`（`stops`／`lines`／`validity` 三项各取 `complete`／`partial`／`missing`，表示该项资料是否完整）、`notes`（旧线名、暂停期、临时列车等说明）以及可选的 `unsolvableLegs`（逐条列出现行路网或现行求解器无法求解的相邻站区间，`notes` 必须说明原因，例如轨道已消失；路线测试仍会求解并单独计数，原因消除后应移除。求解器对 JR 列车回避三セク区间的问题已由 `institution_unpenalised_soft_fallback` 最终回退解决——所有带机构偏好的尝试都失败时，以不加机构罚分的方式再求解一次，はくたか／北越 糸魚川〜魚津因此不再登记；同时求解器对无 N02 代码的端点加入同名站合理性守卫，某次尝试若落到比另一同名候选远两倍以上的站（如 糸魚川〜泊 落到山陰線的泊）会被拒绝并交给更宽松的尝试，路线测试也按同一规则断言）。同一列车名在不同时期的运行方案分别登记（例如サンダーバード 大阪〜金沢 的 `validUntil` 为 2024-03-16、大阪〜敦賀的 `validFrom` 为 2024-03-16），`label` 中注明时期。主库目标为 2010 年以后全国 JR 与私铁的有名称特急；停运列车保留并标注 `validUntil`。v3 解码要求站点对象包含 `name` 和 `sourceCode`；旧字符串停站条目会被拒绝。

编辑器的「特急から駅を入力」选择器提供三个筛选：运行状态（すべて／運行中／廃止・終了，默认運行中）、运营公司、经由线路；文本搜索同时匹配线路名与停靠站名。行内显示生效期间、「廃止」与「資料不完全」标记及经由线路。

检查清单由 `ios/tools/train-service-checklist.py` 生成：

```bash
TRAIN_PATTERN_ROUTE_REPORT=/tmp/route.json TRAIN_CATALOG_CHECK_REPORT=/tmp/catalog.json swift test --build-path /private/tmp/railkit-build-scratch --filter 'TrainServicePatternRoute|TrainServiceCatalogChecklist'
python3 ios/tools/train-service-checklist.py --route-report /tmp/route.json --catalog-report /tmp/catalog.json --out docs/train-service-database-checklist.md
```
