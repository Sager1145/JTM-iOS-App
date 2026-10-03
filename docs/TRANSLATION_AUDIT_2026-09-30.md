# JTM 文案翻译审计

审计日期：2026 年 9 月 30 日，America/Toronto。范围包括 iOS 原生界面、Web 界面、共享语言资源、原生语言表和七个地区的车站名称资源。结论是：**词库的四语言字段覆盖完整，但界面尚未完整本地化**。缺失键、日文或英文硬编码、动态界面没有随语言刷新，以及少量语义错误和简繁混用，仍会影响用户。

本次仅检查和记录，未修改应用源码或译文。优先级 P1 表示整片功能的语言缺口；P2 表示可见漏译或会误导操作的译文；P3 表示局部语言质量问题。静态链路确认与实际运行函数验证分别注明；未完成四语言逐页截图、VoiceOver 或系统弹窗实机验证。

## 词库覆盖和验证结果

| 资源 | 词条数 | 四语言值数 | 结果 |
| --- | ---: | ---: | --- |
| 共享 Web 词库及生成的 Localizable.xcstrings | 498 | 1,992 | 四语言字段齐全；共享目录均为 translated 状态 |
| ShellStrings | 122 | 488 | 字段齐全 |
| DataStrings | 86 | 344 | 字段齐全 |
| EditorStrings | 219 | 876 | 字段齐全 |
| JourneyStrings | 72 | 288 | 字段齐全 |
| TransferGuideStrings | 62 | 248 | 字段齐全 |
| ClockStrings | 17 | 68 | 字段齐全 |
| JourneyCompletionStrings | 54 | 216 | 字段齐全 |
| StatisticsStrings | 88 | 352 | 字段齐全；实际定义在 StatisticsFormatting.swift |
| **合计** | **1,218** | **4,872** | **词条字段完整不代表界面无漏译** |

检查语言为繁中、简中、日文和英文。原生表通过临时 Swift 程序执行实际字典后检查，包含多行文本和字符串拼接；不是仅用正则猜测词条内容。全部词条的 `{placeholder}` 名称和出现次数在四语言间一致；原生表之间、原生表与共享词库之间均无键冲突。

英文 `ios.ticket.unit.rides`、`ios.ticket.unit.stops`、`ios.ticket.unit.operators` 三个值为空是有意设计：英文标签已说明计数对象，票面不再重复打印单位。这三项不算漏译。

Web 检查覆盖 app/public 顶层 57 个 JavaScript 文件和 index.html；137 个 `data-i18n*` 静态属性的键全部存在。运行实际 i18n fixture builder 的只读检查，确认生成的 iOS 词库与 Web 源同步；按生成器的 JSON 序列化方式比较后，i18n 运行时 fixture 也一致。共享词库和原生表共 1,218 个词条均做了四语言语义比对。

## 界面引用的缺失键

以下 **9 个不同键**在共享词库及原生注册表中都不存在，正常界面调用会落到英文 fallback。它们不计入已有 1,218 个词条。

| 优先级 | 键 | 可见结果 | 位置和建议 |
| --- | --- | --- | --- |
| P2 | `ios.networkEra` | Network era | [SettingsView.swift:293](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/SettingsView.swift:293)，补齐四语言 |
| P2 | `ios.networkEra.current` | Current | [SettingsView.swift:299](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/SettingsView.swift:299)，补齐四语言 |
| P2 | `ios.networkEra.rideDate` | Selected ride's date | [SettingsView.swift:301](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/SettingsView.swift:301)，补齐四语言 |
| P2 | `ios.networkEra.overlay` | Historical overlay | [SettingsView.swift:303](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/SettingsView.swift:303)，补齐四语言 |
| P2 | `play.follow` | Follow / Follow the train；包括辅助功能名称 | [PlaybackTransportBar.swift:256](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/PlaybackTransportBar.swift:256)、262，补齐四语言 |
| P2 | `ios.info.usRailTitle` | United States rail network | [MapInfoView.swift:169](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/MapInfoView.swift:169)，已有共享键 `info.usRailTitle` 可复用 |
| P2 | `ios.info.usRailBody` | 整段美国资料来源说明为英文 | [MapInfoView.swift:170](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/MapInfoView.swift:170)，先统一来源说明，再复用 `info.usRailBody` 或新增原生译文 |
| P2 | `ios.info.caRailTitle` | Canadian rail network | [MapInfoView.swift:185](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/MapInfoView.swift:185)，已有共享键 `info.caRailTitle` 可复用 |
| P2 | `ios.info.caRailBody` | 整段加拿大资料来源说明为英文 | [MapInfoView.swift:186](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/MapInfoView.swift:186)，统一内容后复用共享键或新增译文 |

另有一个低优先级潜在分支：Web [app-modal.js:184](/Users/sager/Documents/GitHub/JTM-iOS-App/app/public/app-modal.js:184) 引用不存在的 `modal.dialog`，辅助功能名称会回退为 `Dialog`。当前常规弹窗有标题或消息，因此没有把它列入上面的正常界面缺失键计数。

## 硬编码和错误反馈

| 优先级 | 问题及用户影响 | 证据 |
| --- | --- | --- |
| P1 | 时刻表详情、运行方案浏览、AI 时刻核对整片功能有日文硬编码；切换中文或英文仍显示日文的按钮、说明、状态、筛选和确认提示 | [ServicePatternPickerView.swift:18](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/ServicePatternPickerView.swift:18)，同文件 37、45、124、133、142、184、201、216、435、452、513、531、590、610、618、690。例如 `運転日`、`掲載時刻を編集用の下書きにする`、`確認済み`。68、557 的 VoiceOver 文案同样固定日文 |
| P2 | 编辑器的运行方案日期警告，以及实际到达/实际出发标签固定日文 | [RideEditorView.swift:813](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/RideEditorView.swift:813)、814、1731、1734，包含 `実着` / `実発` |
| P2 | 每日票面标题固定 `本日乗車`，其余票面可随语言改变 | [StatisticsView.swift:381](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/StatisticsView.swift:381)，经 [PassportTicketFace.swift:602](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/PassportTicketFace.swift:602) 原样绘制 |
| P2 | iOS JSON 导入只翻译标题和位置，校验问题详情直接显示英文；文件过大提示也是英文 | [ImportPreflight.swift:154](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/ImportPreflight.swift:154)、217、241；显示入口 [DataImportView.swift:492](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/DataImportView.swift:492)；[ImportFileReader.swift:13](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/ImportFileReader.swift:13) |
| P2 | AI 登录、订阅、行程补全、时刻表查询错误为英文；调用 `localizedDescription` 不会自动翻译这些自定义错误 | [ChatGPTSubscriptionAuth.swift:581](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/ChatGPTSubscriptionAuth.swift:581)、[ChatGPTSubscriptionService.swift:147](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/ChatGPTSubscriptionService.swift:147)、[JourneyCompletion.swift:22](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/JourneyCompletion.swift:22)、[TrainTimetableDatabase.swift:17](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/TrainTimetableDatabase.swift:17)。显示入口包括 JourneyCompletionView 的 69、310、431，TimetableQuickMatchView 的 145 |
| P2 | 视频编码、编辑资料缺失和恢复备份失败仍有英文错误直达用户 | [PlaybackVideoExporter.swift:443](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/PlaybackVideoExporter.swift:443)、[EditorCatalogLoading.swift:7](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/EditorCatalogLoading.swift:7)、[RideLibrary.swift:571](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/RideLibrary.swift:571) |
| P2 | 系统定位授权说明只定义英文，未找到 InfoPlist.strings 或 InfoPlist.xcstrings | [project.pbxproj:290](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap.xcodeproj/project.pbxproj:290)、321：`Shows where you are on the railway map.`。共享 catalog 作为 raw JSON 复制，不能替代系统权限文案本地化 |
| P2 | Web JSON 校验成功提示固定英文，校验失败信息直接显示英文 | [app-validation.js:39](/Users/sager/Documents/GitHub/JTM-iOS-App/app/public/app-validation.js:39)、43。该文件有 31 处未使用 i18n 的 `new Error`，app-store-ops.js 有 14 处；这些是源码位置数，不是去重错误种类数。VM 已复现成功文案及 `Imported store contains no trains.` |
| P2 | Web 地图缩放按钮、画布和 Popup 关闭按钮的 tooltip/ARIA 保留 MapLibre 的英文默认文本 | [app-map-init.js:587](/Users/sager/Documents/GitHub/JTM-iOS-App/app/public/app-map-init.js:587) 没有 locale 配置；625 创建导航控件；814 创建 Popup。默认为 `Zoom in`、`Zoom out`、`Map`、`Close popup`；没有语言切换更新链路 |

错误文本建议由错误代码、翻译键和参数表示，在界面层翻译。资料标题、原始 OCR 文本和外部返回内容应保留来源；应用自己写出的提示则需进入语言表。

## 语言切换与系统区域设置

| 优先级 | 问题 | 检查结论和证据 |
| --- | --- | --- |
| P2 | Web 已打开的视频选项、生成后的下载链接和完成横幅不会全部随语言刷新 | [app-playback-video.js:360](/Users/sager/Documents/GitHub/JTM-iOS-App/app/public/app-playback-video.js:360) 仅在打开时填充动态选项；624、642 仅在生成时填充下载文案和完成提示。该模块没有 onChange；[app-events.js:1234](/Users/sager/Documents/GitHub/JTM-iOS-App/app/public/app-events.js:1234) 的切换回调也不刷新这些内容。已确认源码链路，未作浏览器交互复现 |
| P2 | 已打开的点击弹窗，以及停留在同一站点的 hover 弹窗，可保留旧语言 | [app-map-init.js:814](/Users/sager/Documents/GitHub/JTM-iOS-App/app/public/app-map-init.js:814) 一次性生成 HTML；[railmap-interactions.js:685](/Users/sager/Documents/GitHub/JTM-iOS-App/app/public/railmap-interactions.js:685) 的缓存键仅包含 station/line，不含语言。语言切换回调不刷新/关闭这两类弹窗。已确认源码链路，未作浏览器交互复现 |
| P2 | 日期选择器所在附加 sheet 没有完整继承应用自选 Locale | [WorkspaceTabs.swift:34](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/WorkspaceTabs.swift:34)、53 的 Locale 只覆盖 tab 子树；[WorkspacePresentations.swift:47](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/WorkspacePresentations.swift:47) 只传入本地化对象。EditorDateTimeFields 的 28、129、151 的 DatePicker 无单独 Locale。环境缺口已确认，具体系统控件表现仍需设备验证 |
| P3 | 数字、文件大小等部分格式化调用使用设备 Locale，可能与应用自选语言不一致 | [StatisticsFormatting.swift:30](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/StatisticsFormatting.swift:30)、33；StatisticsView 的 378、587、1295；VideoExportOptionsView 的 76、152。普通 `.formatted()` 不会自动读取 AppLocalization.locale |

## 已有译文中的含义和语言错误

| 优先级 | 键或文本 | 当前问题 | 建议 |
| --- | --- | --- | --- |
| P2 | `disp.mapOpacity`、`disp.riddenOpacity` | 日文和两种中文把 opacity 写成透明度，与滑块值越大越不透明相反 | 日文 `不透明度`，中文 `不透明度`。共享 catalog 的 [2510](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/Resources/Localizable.xcstrings:2510)、2742；底图覆盖层使用 `1 - basemapOpacity`，线路直接使用 riddenOpacity |
| P2 | `ios.note.riddenOpacity`、`ios.note.dimOpacity` | 中文说明也使用透明度，日文说明已正确 | 将中文改为不透明度；[ShellStrings.swift:397](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/ShellStrings.swift:397)、403 |
| P2 | `field.company` 繁中 | `車輛公司` 容易被理解为车辆制造或所有公司，而字段是运营方 | `營運公司`；[Localizable.xcstrings:3218](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/Resources/Localizable.xcstrings:3218) |
| P2 | `field.trainType` 两种中文 | `车辆类型` / `車輛類型` 与车种类别混淆，字段值是特急、普通、新干线等 | `列车类别` / `列車類別` 或统一用列车种别；[Localizable.xcstrings:3415](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/Resources/Localizable.xcstrings:3415) |
| P2 | `stats.retiredKm`、`stats.retiredLines` 及同名原生 `ios.stats.*` | retired / 廃止被译成停运，和暂时停止运营混淆 | `已乘废止路网` / `已乘廢止路網`、`已乘废止线路` / `已乘廢止路線`；[Localizable.xcstrings:11100](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/Resources/Localizable.xcstrings:11100)、11129；[StatisticsFormatting.swift:320](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/StatisticsFormatting.swift:320)、332 |
| P3 | `field.numberEn` 简中 | 实际输出 `英文名稱` | `英文名称`；[i18n-strings.js:562](/Users/sager/Documents/GitHub/JTM-iOS-App/app/public/i18n-strings.js:562)。转换表缺 `稱→称`，生成的 iOS catalog 同受影响 |
| P3 | `stats.historicalKm` 简中 | 实际输出 `歷史区间已乘里程` | `历史区间已乘里程`；[i18n-strings.js:520](/Users/sager/Documents/GitHub/JTM-iOS-App/app/public/i18n-strings.js:520)。转换表缺 `歷→历`；原生 `ios.stats.historicalKm` 已正确 |
| P2 | `ios.ai.eligible` 中文 | 将 train number 写作车号/車號，容易与车辆编号混淆 | 使用车次/車次；[JourneyCompletionStrings.swift:31](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/JourneyCompletionStrings.swift:31) |
| P2 | `ios.guide.plannedNote` | 引导去找 `即将出发` / `即將出發` / `これから`，和实际导航名不同 | 与实际 `nav.upcoming` 或短 tab 名保持一致；[TransferGuideStrings.swift:185](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/TransferGuideStrings.swift:185) |
| P3 | `ios.editor.branchService` 日文 | `分割運転の車次` 混入中文术语車次 | `分割運転の列車情報`，该区块包含车次和显示名；[EditorStrings.swift:966](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/EditorStrings.swift:966) |
| P3 | `ios.ticket.kind.history` 中文 | 两种中文都写日文 `乗車記録`，且英文已做本地化 | 建议 `乘车记录` / `乘車紀錄`。如果票面设计要求固定日文，应明确这是特殊显示政策；[StatisticsFormatting.swift:118](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/StatisticsFormatting.swift:118) |
| P3 | `stat.ltdexp` 中文 | 使用日文式 `有料特急`，收费含义对中文用户不够直接 | `需另付费的特急` / `需另付費的特急`，作为术语润色；[Localizable.xcstrings:9853](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/Resources/Localizable.xcstrings:9853) |

共享简中文案由繁中转换生成。因此应修正 Web 源词条或转换表，再重新生成 iOS catalog；直接改 xcstrings 会与生成器冲突。

## 车站名称覆盖

下表统计地图包的**线路站点出现次数**，不是去重后的实际车站数。同一车站经过多条线路会重复计入。

| 地区 | 站点出现次数 | 找不到名称表行 | 名称或读音缺项 |
| --- | ---: | ---: | --- |
| 日本 | 10,227 | 8,899，87.0% | 缺 kana 8,901，缺 romaji 8,899；默认保留日文原名，读音只覆盖一部分 |
| 台湾 | 586 | 0 | 缺日文 372，缺英文 23；两种中文均非空 |
| 香港 | 453 | 0 | 日文全部为空；英文及两种中文均非空 |
| 澳门 | 17 | 0 | 日文全部为空；英文及两种中文均非空 |
| 韩国 | 1,412 | 0 | 日文全部为空；两种中文各缺 534；英文无缺项 |
| 美国 | 5,521 | 0 | 中日文全部为空；英文无缺项 |
| 加拿大 | 865 | 0 | 中日文全部为空；英文无缺项 |

日本读音缺项是当前资源覆盖限制，不等于所有原始日文站名都应替换。台湾、香港和澳门的数据说明保留官方可用译名，没有提供的译名为空；韩国资源主要提供韩文原名、汉字和英文。美国、加拿大的数据说明明确不编造运营方没有发布的中日文名称，界面回退到官方名称。这些空字段不应机械算成普通 UI 漏译。

现有 station-readings 审计工具默认只查前五个地区；本次使用相同逻辑在临时副本中补查美国、加拿大。北美样例行程的名称表命中为美国 54/55、加拿大 1/73；这是该工具按原代码/原名匹配的结果，需结合实际站点解析再判断，未当作普通译文缺失。

### 确认的车站简繁混用

对七个站名资源的全部非空 `zh_Hans` 值和原生简中表执行 Foundation/ICU Traditional→Simplified 对比，人工复核 27 个转换候选，排除日文专名、应用品牌名称及不应机械转换的地名。确认以下三种站名有错误，各自同时存在于 operator code、network code 和 byName，合计 9 个资源值：

| 资源和键 | 当前简中 | 建议简中 |
| --- | --- | --- |
| [station-readings-tw.json](/Users/sager/Documents/GitHub/JTM-iOS-App/app/data/station-readings-tw.json)，`byCode/NTMC-LB02`、`byCode/tw-ntmetro-lb:tw-official-ntmc-lb02`、`byName/媽祖田` 的 `zh_Hans` | 媽祖田 | 妈祖田 |
| 同资源，`byCode/NTMC-LB06`、`byCode/tw-ntmetro-lb:tw-official-ntmc-lb06`、`byName/三峽` 的 `zh_Hans` | 三峽 | 三峡 |
| [station-readings-mo.json](/Users/sager/Documents/GitHub/JTM-iOS-App/app/data/station-readings-mo.json)，`byCode/MLM-STADIUM`、`byCode/mo-mlm-taipa:mo-official-mlm-stadium`、`byName/運動場` 的 `zh_Hans` | 运動场 | 运动场 |

ICU 还会建议把大阪改成大坂、把澳门地名中的氹改成凼，或改写日文 App 名称。这些未列为确定缺陷，不能全盘套用字符转换结果。

### 名称显示政策的一致性

Web [app-render.js:329](/Users/sager/Documents/GitHub/JTM-iOS-App/app/public/app-render.js:329)、330 的列表起终站直接显示原始主名称；[app-playback.js:1178](/Users/sager/Documents/GitHub/JTM-iOS-App/app/public/app-playback.js:1178)、1287 的视频字幕和播放栏也使用原始名称。地图弹窗则会使用地区名称表。在有官方英文站名的台湾/香港等地区，可能同屏出现来源中文名与英文站名。

代码明确写有列表保留原始主名称的策略，因此这项是需要统一的产品显示政策，而不是将所有官方专名判为漏译。可选择保留原名并加译名，或让这些地区的列表与地图统一使用 `stationName`。

## 修复顺序和剩余验证

1. 先补齐 9 个引用键，并把时刻表和编辑器的活动日文提示接入语言表。
2. 再统一应用自写错误的翻译链路，补系统授权及地图控件的语言文案。
3. 修正不透明度、运营公司、列车类别、废止线路等含义错误，以及简繁混用。
4. 让视频面板和地图弹窗跟随语言变化，并将应用 Locale 传入 sheet 和数值格式化。
5. 完成四语言逐页与 VoiceOver 检查，覆盖时刻表详情/AI 核对、编辑器日期、导入失败、每日和历史票面、视频选项和导出完成提示、点击及 hover 弹窗。

已执行的检查是只读词库同步、真实 i18n fixture 生成结果比较、实际 Swift 字典检查、Web 校验函数 VM 验证、站名资源覆盖及简繁转换复核。未执行全应用构建或界面截图测试；报告中的所有“源码确认”不代表布局截断、系统控件或外部底图也已通过实际设备检查。文件名带 ` 2` 的重复副本、测试提示、纯日志/调试文本和数据来源的原文不纳入活动 UI 漏译计数。

结构化检查摘要见 [TRANSLATION_AUDIT_2026-09-30.json](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/TRANSLATION_AUDIT_2026-09-30.json)。
