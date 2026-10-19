# 历史直通线网续修结果（2026-10-10）

原生 Catalyst 导出的检查范围为 1996-12-31 至 2026-10-10：176 条记录、132 个日期样本。881 项发现中错误 0、未知 796、警告候选 85；这些并非已确认的缺陷数量。

完整日期、记录和建议见 [本次 JSON 报告](inspection-continuation-2026-10-10.json)。旧报告保留为历史证据；检测规则与日期样本已变化，不能用总数比较改进率。

| 检查层 | 状态 | 发现 |
| --- | --- | --- |
| 目录结构与身份 | passed | 0 |
| 半开有效期 | passed | 0 |
| 历史有序路径 | passed | 0 |
| 来源与证据范围 | unknown | 69 |
| 物理锚点与方向 | passed | 0 |
| 区段连接 | unknown | 597 |
| 时间覆盖 | unknown | 202 |
| 历史几何与身份 | unknown | 1 |
| 外部服务清单完整性 | unknown | 11 |
| 原生应用一致性 | unknown | 1 |

已落实：

- 生产读者和服务成员查询共用有来源的环线有序遍历，包含首尾区间；修复四条大阪环线服务误走东侧弧的问题。
- 用共享 legs 和少量索引变体保存副都心线、日比谷线历史路径；显式停运变体与缺失证据期间分开。
- 补充 20 个明确起点或端点开通约束，现在 76 条有起点、100 条未明确。开通约束不等于完整端点在首日已经存在。
- 保留物理连接注册表并核对身份、坐标、来源与有效期；修复 JP/jp 大小写兼容，新增回归通过。

连接匹配实际仍为 0。当前检测只承认相邻直通腿的原始终点/起点精确匹配；例如押上连接证据在轨道内部顶点，而 compact 腿的终点不同。不能把当前平台/线路端点吸附成证据顶点，也不能从零匹配推断不存在物理连接。后续需要沿有来源的 section/轨道路径到达连接点，并与原生路由图的完整身份规则对照。

验证：34 个 Core 回归、38 个生产直通回归通过；最后区域数据修改后另有 12 个定向用例通过。原生发现大小写问题后，新增 1 个回归通过，最终 arm64 Catalyst 增量构建通过。原生日期观察确认 Haruka 在 2023-02-12 为 Inactive。没有执行完整主应用构建或测量性能。

跨 chat：线路求解 chat 负责原始来源迁移、Git 排除及 RouteWorkbench；线路对齐 chat 负责 Tabata/Nihongi 几何与显示；本 chat 负责直通目录、生产读者及 ThroughWorkbench。构建窗口已释放给求解 chat；不触碰它管理的 CLI 进程。

仍需完成全国历史服务清单、缺失起点、历史外侧端点/运营者及物理路径证据。Sunrise 日期冲突、Hashidate 历史边界和 Super Inaba 月级来源仍保留未知。

未明确起点的完整队列：

| Pattern ID | 名称 |
| --- | --- | --- |
| JK | 京浜東北線・根岸線 |
| JO-sobu-yokosuka | 横須賀線・総武線快速 |
| shinjuku-keio-sagamihara | 都営新宿線・京王相模原線直通 |
| chiyoda-joban-odakyu | 常磐線各駅停車・千代田線・小田急小田原線直通 |
| yurakucho-tobu | 有楽町線・東武東上線直通 |
| osaka-midosuji-kita | 御堂筋線・北大阪急行直通 |
| osaka-chuo-keihanna | 中央線・近鉄けいはんな線直通 |
| osaka-sakaisuji-senri | 堺筋線・阪急千里線直通 |
| osaka-sakaisuji-kyoto | 堺筋線・阪急京都線直通 |
| hokkaido-airport-otaru | 快速エアポート・小樽直通 |
| tohoku-senzan-yamagata | 仙山線・山形直通 |
| tohoku-joban-sendai | 常磐線・仙台直通 |
| shikoku-naruto-tokushima | 鳴門線・徳島直通 |
| jr-ise-mie | 快速みえ（関西線・伊勢鉄道・紀勢線・参宮線） |
| jr-ise-nanki | 特急南紀（関西線・伊勢鉄道・紀勢線） |
| jr-tokai-tokaido-maibara | 東海道線名古屋・米原（関ヶ原回り） |
| jr-shirasagi | 特急しらさぎ（東海道線・北陸線） |
| jr-hida-nagoya-toyama | 特急ひだ（東海道線・高山線） |
| jr-shinano | 特急しなの（中央線・篠ノ井線・信越線） |
| jr-iida-tatsuno | 飯田線・中央線直通（辰野） |
| shinano-jr-shinetsu | しなの鉄道線・JR信越線・北しなの線直通 |
| hokuetsu-echigo-yuzawa | 北越急行・上越線・信越線直通 |
| hakutaka-wakura | 特急はくたか（金沢・和倉温泉） |
| noto-jr-wakura | JR七尾線・のと鉄道直通（和倉温泉） |
| kintetsu-osaka-nagoya | 近鉄大阪線・名古屋線特急 |
| kintetsu-osaka-shima | 近鉄大阪線・山田線・鳥羽線・志摩線直通 |
| kintetsu-nagoya-shima | 近鉄名古屋線・山田線・鳥羽線・志摩線直通 |
| hankyu-kobe-kosoku | 阪急神戸線・神戸高速線直通 |
| sanyo-hankyu-sannomiya | 山陽・阪急三宮直通 |
| kintetsu-kyoto-kashihara-shima | 近鉄京都線・橿原線・大阪線・志摩線直通 |
| kansai-airport-rapid | 関空快速 |
| kansai-airport-rapid-jr-namba | 関空快速（JR難波発着） |
| kishuji-rapid | 紀州路快速 |
| haruka | 特急はるか |
| kuroshio | 特急くろしお |
| hashidate | 特急はしだて |
| super-inaba | 特急スーパーいなば |
| musashino-keiyo-tokyo | 武蔵野線・京葉線（東京方面） |
| musashino-keiyo-makuhari | 武蔵野線・京葉線（海浜幕張方面） |
| jo-narita-airport | 横須賀・総武快速・成田空港 |
| jo-kashima-jingu | 横須賀・総武快速・成田線・鹿島線 |
| narita-abiko-joban | 成田線我孫子支線・常磐線 |
| narita-abiko-chiba | 成田線（我孫子–成田–佐倉–千葉） |
| nex-shinjuku-narita | 成田エクスプレス（新宿・大宮–成田空港） |
| nex-chuo-narita | 成田エクスプレス（中央線高尾・八王子–成田空港） |
| chuo-sobu-local | 中央・総武線各駅停車 |
| chuo-ome | 中央線・青梅線直通 |
| chuo-ome-itsukaichi | 中央線・青梅線・五日市線直通 |
| hachiko-kawagoe | 八高線・川越線直通 |
| yokohama-negishi | 横浜線・根岸線直通 |
| keiyo-sotobo | 京葉線・外房線直通 |
| keiyo-uchibo | 京葉線・内房線直通 |
| sobu-sotobo | 総武線・外房線直通 |
| sobu-uchibo | 総武線・外房線・内房線直通 |
| tobu-yagan-aizu-tajima | 東武・野岩鉄道・会津鉄道直通（浅草–会津田島） |
| aizu-mount-express | 快速AIZUマウントエクスプレス（鬼怒川温泉–会津若松） |
| jr-east-gotemba-tokyo | 東海道線・御殿場線直通（東京–御殿場） |
| odakyu-hakone-yumoto | 小田急・箱根登山鉄道直通（新宿–箱根湯本） |
| jr-fujikyu-kawaguchiko | 中央線・富士急行線直通（新宿–河口湖） |
| odoriko-shinjuku-shimoda | 踊り子（池袋・新宿–伊豆急下田） |
| odoriko-shinjuku-shuzenji | 踊り子（新宿–修善寺） |
| kashima-rinkai-jingu | 鹿島臨海鉄道・JR鹿島線直通 |
| asakusa-keisei-kurihama | 京成本線・都営浅草線・京急久里浜線直通 |
| asakusa-keisei-uraga | 京成本線・都営浅草線・京急浦賀直通 |
| asakusa-keisei-zushi | 京成本線・都営浅草線・京急逗子線直通 |
| hokuso-asakusa-haneda | 北総線・都営浅草線・京急空港線直通 |
| hokuso-asakusa-kurihama | 北総線・都営浅草線・京急久里浜線直通 |
| hokuso-asakusa-uraga | 北総線・都営浅草線・京急浦賀直通 |
| shibayama-asakusa-haneda | 芝山鉄道・京成・都営浅草線・京急直通 |
| shinjuku-keio-hachioji | 都営新宿線・京王線京王八王子直通 |
| shinjuku-keio-takao | 都営新宿線・京王高尾線直通 |
| chiyoda-joban-odakyu-tama | 常磐線各駅停車・千代田線・小田急多摩線直通 |
| seibu-sayama-ikebukuro | 西武狭山線・池袋線直通 |
| igr-aoimori-hachinohe | IGRいわて銀河鉄道・青い森鉄道直通 |
| hanawa-igr-morioka | JR花輪線・IGRいわて銀河鉄道直通 |
| hanawa-igr-hizume | JR花輪線・東北線日詰直通 |
| kamaishi-igr-kozuya | 釜石線・IGR好摩直通 |
| ominato-aoimori-hachinohe | JR大湊線・青い森鉄道八戸直通 |
| ominato-aoimori-aomori | JR大湊線・青い森鉄道青森直通 |
| aoimori-hachinohe-same | 青い森鉄道・JR八戸線鮫直通 |
| abukuma-jr-sendai | 阿武隈急行・JR東北線仙台直通 |
| yamagata-shinkansen-tsubasa | 山形新幹線つばさ |
| aizu-tadami-wakamatsu | 会津鉄道・JR只見線会津若松直通 |
| hokkaido-hokuto | 特急北斗・函館札幌直通 |
| hokkaido-ozora-kushiro | 特急おおぞら・とかち |
| hokkaido-okhotsk | 特急オホーツク・大雪 |
| hokkaido-sassho-sapporo | 札沼線・函館線札幌直通 |
| seto-shiokaze | 特急しおかぜ |
| seto-nanpu | 特急南風 |
| sunrise-seto | サンライズ瀬戸 |
| chizu-super-hakuto | スーパーはくと |
| chizu-super-inaba | スーパーいなば |
| kanmon-sanyo | 山陽本線関門直通 |
| tosa-kuroshio-nakamura | 土讃線・土佐くろしお中村線・宿毛線直通 |
| tosa-kuroshio-gomen-nahari | 土讃線・土佐くろしお阿佐線直通 |
| tosa-kuroshio-yodo | 予土線・土佐くろしお中村線直通 |
| hiroden-miyajima | 広島電鉄宮島線・本線直通 |
| hisatsu-orange-kumamoto | 肥薩おれんじ鉄道・鹿児島線新八代直通 |
| hisatsu-orange-kagoshima | 肥薩おれんじ鉄道・鹿児島線川内直通 |
| seibu-chichibu-through | 西武鉄道・秩父鉄道直通 |
