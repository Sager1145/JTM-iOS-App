# 特急 Logo 来源审计（2026-09-30）

以 `train-service-branding.json` 的 221 条日本特急记录为准。43 条已绑定图稿，使用 29 份不同素材；178 条仍由公司标志／默认图标回退，所有已绑定路径均有文件。已纳入文件的原图、作者、许可及处理方式逐一列在[素材清单](../app/public/rail/service-logos/README.md)。`logoPath: null` 表示目前未能确认适合在应用中分发且准确对应该服务的独立图稿，不表示该列车没有标志。文件存在检查不等于许可审查通过：既有 `spacia-x.png`、`hinotori.png`、`shimakaze.png` 的来源未声明开放再分发许可，素材清单保留这一限制。[数据库检查清单](train-service-database-checklist.md)的 Logo 列与统计已按此品牌 JSON 单独同步；时刻表与路线验收保留原有快照。Logo 证据维护由本审计负责，不以更新图稿状态代表全库验收已完成。

## 2026-09-30 新增

新增十张有明确 Commons 许可的标志照片：`laview`、`36-plus-3`、`saphir-odoriko`、`cassiopeia`、`hokutosei`、`ao-no-symphony`、`kyushu-odan-tokkyu`、`akebono`、`hokuriku`、`fuji`。裁切保留实际车身／车头标志，未重绘标志；青の交響曲照片先按 EXIF 方向归正。各文件作者及 CC BY／CC BY-SA／CC0 许可链接见素材清单。

`spacia-nikko` 与 `spacia-kinugawa` 复用现有 `spacia.png`。[东武官方车辆说明](https://www.tobu.co.jp/railway/special_express/vehicle/spacia/)明确将这两个名称列为 SPACIA 的 JR 直通服务。普通 `nikko`、`kinugawa`、`kegon`、`kinu` 保留回退，不将 SPACIA 车型图稿扩展到所有同名车次。

车型或服务专用照片只绑定明确的对应品牌：Laview 不套给所有「ちちぶ／むさし」，36ぷらす3 不套给其他 787 系服务，青の交響曲不套给其他近铁特急，Cassiopeia 不套给其他寝台列车。

寝台特急あけぼの、北陸与富士使用各自的常规车头牌照片；あけぼの来源是保存车头牌的近照。`fuji.jpg` 只绑定原寝台特急「富士」，不用于富士回遊、富士山或富士山ビュー特急。

本轮验证：仅修改 12 个条目的 `logoPath`，名称、ID、条目顺序与其他字段保持原值。`TrainServiceBrandingTests`、`TrainServiceCatalogChecklistTests` 与 `JourneyRouteIdentityTests` 共 40 个测试通过，其中全库检查覆盖 221 条服务。ImageIO 成功解码全部 29 张素材；`ios/copy-rail-packages.sh` 在独立临时目录执行成功，43 条绑定路径的打包文件与源文件逐字节一致。未执行 Xcode／模拟器 UI 验证。

本轮品牌 JSON 的 SHA-256：`f7bf617978f15c0c6d78490aa3a7f672ab713c04e2e3088e16de6bb6308a9924`。这只是 Logo 绑定快照，不替代时刻表或路线证据。

## 已检索的资料库

- [Wikimedia Commons：日本列车标志分类](https://commons.wikimedia.org/wiki/Category:Logos_of_trains_of_Japan)列有 190 个文件。核查了与本库服务同名的图像、作者与许可；其中不少是整车照片、车型标志、纪念版标志或新干线车种标志，不能作为另一服务的通用标志。
- [小田急 Romancecar 时刻表](https://www.odakyu.jp/romancecar/timetable/doc/260314/weekday_up2026.pdf)与[历史服务名公告](https://www.odakyu.jp/program/info/data.info/8701_5820170_.pdf)用于确认 `romancecar.png` 所覆盖的 13 个名称。
- [JR 西日本 WEST EXPRESS 銀河发布资料](https://www.westjr.co.jp/global/en/pdf/press_20190319.pdf)、[名铁 μ-SKY 车辆页](https://www.meitetsu.co.jp/library/rolling_stock/detail_exp/2000.html)用于确认图稿所属服务。

## 有官方图稿，但尚未取得可分发许可

以下是继续补图可核查的具体来源。目前页面展示图稿不等于许可将图稿收入公开仓库。部分运营方的[JR 东日本网站条款](https://www.jreast.co.jp/site/rules.html)、[JR 西日本网站注意事项](https://www.jr-odekake.net/i/odekake/about_odekake/attention.html)和[JR 四国网站政策](https://www.jr-shikoku.co.jp/site_policy/jrshikoku_sitepolicy.pdf)限制复制或再分发，因此本次没有复制这些候选图片。

| 服务 ID | 可核查来源 | 当前处理 |
| --- | --- | --- |
| `skyliner` | [京成 Skyliner 设计页](https://www.keisei.co.jp/keisei/tetudou/skyliner/jp/skyliner/design.php) | 有专用设计说明，未取得独立图稿再分发许可。 |
| `rapit`, `rapit-beta` | [南海 rapi:t 官方页](https://www.nankai.co.jp/traffic/express/rapit.html) | 页面有列车照片，未确认可分发的独立标志。 |
| `twilight-express-mizukaze` | [JR 西日本 瑞風官方页](https://www.twilightexpress-mizukaze.jp/) | 与已纳入的旧「トワイライトエクスプレス」标志不同。 |
| `shikoku-mannaka-sennen-monogatari`, `shikoku-tosa-jidai-no-yoake`, `iyonada-monogatari` | [JR 四国观光列车](https://www.jr-shikoku.co.jp/01_trainbus/event_train/) | 有各自的官方品牌图；未确认再分发许可。 |
| `futatsuboshi-4047`, `aru-ressha`, `kanpachi-ichiroku`, `asoboy`, `yufuin-no-mori`, `a-ressha-de-iko`, `kawasemi-yamasemi`, `ibusuki-no-tamatebako`, `umisachi-yamasachi` | [JR 九州观光列车总览](https://www.jrkyushu.co.jp/trains/) | 可逐车查官方设计，未确认图稿再分发许可。 |

## 检查后未套用的图像

| 服务 ID | 候选来源 | 未绑定原因 |
| --- | --- | --- |
| `sonic` | [885 系 Sonic 徽章](https://commons.wikimedia.org/wiki/File:JR_Kyushu_885_Sonic_emblem.png) | 图中明确写 885，不能覆盖该名称下所有车型与时期。 |
| `kamome` | [西九州新干线 Kamome 2022 标志](https://commons.wikimedia.org/wiki/File:Shinkansen_Kamome_graphic_logo_2022.jpg) | 与数据库中的旧线特急「かもめ」不是同一服务。 |
| `thunderbird` | [683-4000 系徽章](https://commons.wikimedia.org/wiki/File:Series683-4000_Thunder-emblem.jpg) | 指向特定车辆；目录服务涵盖更多车型。 |
| `urban-liner` | [UL Next 标志](https://commons.wikimedia.org/wiki/File:KINTETSU21020_next%E3%83%9E%E3%83%BC%E3%82%AF.JPG) | 只对应 Next 子车型。 |
| `haruka` | [30 周年纪念标志](https://commons.wikimedia.org/wiki/File:Limited_Express_HARUKA_30th_Anniversary_Logo.jpg) | 使用了非纪念版的常规徽章。 |
| `kegon`, `kinu` | [SPACIA 标志](https://commons.wikimedia.org/wiki/File:Spacia_logo.jpg) | 运营列车可能不是 SPACIA，不能按车次名称统一套用。 |
| `southern` | [Southern Premium 车身字样](https://commons.wikimedia.org/wiki/File:Nankai_12000_series_side_logo_%22Southern_Premium%22.jpg) | 只覆盖 Premium 车型，并非所有 Southern 班次。 |
| `huis-ten-bosch` | [783 系车身徽章照片](https://commons.wikimedia.org/wiki/File:JRK_783_series_Huis_Ten_Bosch_logo.JPG) | 照片大部分为整车车侧，缩略展示时徽章很小；待取得更合适的近照。 |
| `semboku-liner` | [泉北 12000 系徽章](https://commons.wikimedia.org/wiki/File:SembokuLiner_Emblem.jpg) | 当前候选与具体车型相关，尚未确认能覆盖所有泉北ライナー使用车辆及年代。 |
| `hanayome-noren` | [同名电视剧图稿](https://commons.wikimedia.org/wiki/File:Hanayome_noren.png) | 来源是东海电视台电视剧，与列车无关。 |
| `sunrise-izumo`, `sunrise-seto` | [Sunrise 公司 Logo](https://commons.wikimedia.org/wiki/File:Sunrise_logo.jpg) | 描述明确是「サンライズ社」，不是寝台特急服务。 |

其余未绑定条目目前没有通过「名称、对应服务范围、可用图像质量、来源与许可」全部检查。补充素材时应先核对它是否为对应时期的服务标志，再记录作者、许可及文件转换方式。
