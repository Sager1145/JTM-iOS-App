# 历史直通线网检查结果与修复队列

本报告由 Catalyst 应用导出，范围 1996-12-31 至 2026-10-10，包含 176 条现有记录与 103 个边界样本。共 852 项：错误 0、待证据 773、复核候选 79。这些数量不是已确认的数据缺陷数量。

完整记录、受影响日期与建议见 [JSON 检查计划](inspection-plan-2026-10-10.json)。对照用的初次报告保留在 inspection-before-repairs-2026-10-10.json；之后检测器补充了反向线路和环线规则，两份报告的总数不能作为同规则改进率。

| 检查层 | 状态 | 发现数量 |
| --- | --- | --- |
| 目录结构与身份 | passed | 0 |
| 半开有效期 | passed | 0 |
| 历史有序路径 | passed | 0 |
| 来源与证据范围 | unknown | 51 |
| 物理锚点与方向 | unknown | 4 |
| 区段连接 | unknown | 542 |
| 时间覆盖 | unknown | 242 |
| 历史几何与身份 | unknown | 1 |
| 外部服务清单完整性 | unknown | 11 |
| 原生应用一致性 | unknown | 1 |

已落实的修复：

- 检测器保留原始坐标，拒绝缺失接缝和错误区间数量，检查反向线路自身几何与方向。
- 环线按确定的方向跨首尾节点；方向未知时明确报告，避免产生错误几何断点候选。
- 无效车站坐标报告结构错误；未知存在性变化与服务启停分开。
- 新宿—沼津「あさぎり」依据小田急官方年表补入 1991-03-16 起点。原 2012-03-17 结束边界保留。
- 三个显示连接补入既有来源与物理连接引用；来源内容和历史适用范围仍需审查。

后续按结果执行的队列：

1. 确认下列四个大阪环线区段的方向与来源，并同步生产读者和辅助工具的显式期间/方向表示；不可从站序猜测。
   - haruka：环线方向未明确，不能唯一选择有序路径。
   - kansai-airport-rapid：环线方向未明确，不能唯一选择有序路径。
   - kishuji-rapid：环线方向未明确，不能唯一选择有序路径。
   - kuroshio：环线方向未明确，不能唯一选择有序路径。
2. 按窗口核实 120 条未明确起点的记录，并检查现有开通约束是否支持同一外侧端点；保留历史运营者变更和停运期间。
3. 将 542 项区段连接发现逐项对应到有日期的物理连接证据；共享站码、当前显示来源或近距离不能替代轨道证据。优先使用已有 physical-rail-junctions.json 中的经审查记录，核对实际端点与期间。
4. 复核 79 项原始几何/连接警告，区分平台点显示吸附与真实源数据错误；有依据后修改拥有该数据的 builder/override。
5. 核查来源内容、发布日与范围，按地区和时期对照外部官方服务清单，补入现有目录未收录的历史直通服务。
6. 补齐历史运营者、几何期间和再分发依据；对真正改变的路由/显示进行定向原生观察。检测计划界面已实际运行，但这不证明全部物理路由。

尚未明确起点的完整记录清单：

| Pattern ID | 名称 |
| --- | --- |
| JK | 京浜東北線・根岸線 |
| JO-sobu-yokosuka | 横須賀線・総武線快速 |
| rinkai-saikyo-kawagoe | りんかい線・埼京線・川越線直通 |
| shinjuku-keio-sagamihara | 都営新宿線・京王相模原線直通 |
| hibiya-tobu-nikko | 日比谷線・東武伊勢崎線・日光線直通 |
| chiyoda-joban-odakyu | 常磐線各駅停車・千代田線・小田急小田原線直通 |
| tozai-toyo | 中央線・東西線・東葉高速線直通 |
| tozai-sobu | 中央線・東西線・総武線各駅停車直通 |
| yurakucho-tobu | 有楽町線・東武東上線直通 |
| fukutoshin-tobu-minatomirai | 東武東上線・副都心線・東横線・みなとみらい直通 |
| fukutoshin-seibu-minatomirai | 西武池袋線・副都心線・東横線・みなとみらい直通 |
| nagoya-tsurumai-toyota | 鶴舞線・名鉄豊田線・三河線直通 |
| nagoya-inuyama-tsurumai | 名鉄犬山線・鶴舞線・豊田線直通 |
| osaka-midosuji-kita | 御堂筋線・北大阪急行直通 |
| osaka-chuo-keihanna | 中央線・近鉄けいはんな線直通 |
| osaka-sakaisuji-senri | 堺筋線・阪急千里線直通 |
| osaka-sakaisuji-kyoto | 堺筋線・阪急京都線直通 |
| fukuoka-kuko-chikuhi | 福岡市地下鉄空港線・筑肥線・唐津線直通 |
| hokkaido-airport-otaru | 快速エアポート・小樽直通 |
| tohoku-senzan-yamagata | 仙山線・山形直通 |
| tohoku-joban-sendai | 常磐線・仙台直通 |
| seto-marine-liner | 快速マリンライナー |
| shikoku-naruto-tokushima | 鳴門線・徳島直通 |
| kyushu-miyazaki-airport | 日豊線・日南線・宮崎空港線直通 |
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
| kobe-hokushin-seishin | 北神線・西神山手線直通 |
| nankai-koya-semboku | 南海高野線・泉北線直通 |
| nankai-main-airport | 南海本線・空港線直通 |
| kintetsu-kyoto-kashihara-shima | 近鉄京都線・橿原線・大阪線・志摩線直通 |
| kansai-airport-rapid | 関空快速 |
| kansai-airport-rapid-jr-namba | 関空快速（JR難波発着） |
| kishuji-rapid | 紀州路快速 |
| haruka | 特急はるか |
| kuroshio | 特急くろしお |
| hashidate | 特急はしだて |
| super-hakuto | 特急スーパーはくと |
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
| odoriko-tokyo-shimoda | 踊り子（東京–伊豆急下田） |
| odoriko-shinjuku-shimoda | 踊り子（池袋・新宿–伊豆急下田） |
| odoriko-tokyo-shuzenji | 踊り子（東京–修善寺） |
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
| ibara-hakubi-fukuen | 井原鉄道・伯備線・福塩線直通 |
| nishikigawa-gantoku | 錦川鉄道・岩徳線直通 |
| wakasa-inbi-tottori | 若桜鉄道・因美線直通 |
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

验证：26 个辅助核心测试、29 个生产直通回归测试通过；最终 arm64 Mac Catalyst 增量构建通过。原生界面显示 logo、176 条记录与 103 个检查日期，并通过应用文件导出器保存本报告。没有运行全国数据重建、全矩阵测试或自动验证流水线。
