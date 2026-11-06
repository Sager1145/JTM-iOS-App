# Bundled example trips: field conventions and sources

Applies to the sample stores `train-store.json` (jp), `train-store-tw.json`,
`train-store-hk.json`, `train-store-kr.json`, `train-store-mo.json` and
`special-samples/*.json`. The precomputed directories (`sample-data*/`,
`*-data/`) are regenerated from these stores by
`scripts/build/precompute-train-parts.mjs`. The 2026-11-05 normalization was
applied by `scripts/samples/normalize-sample-fields.py`.

Ride ids: every bundled ride uses the same id scheme as a ride added in the
app, `journey_` followed by 32 uppercase hex digits. Tables and lists below
name rides by that id.

## Field conventions (match what the iOS ride editor writes)

| Field | Convention |
|---|---|
| `number` | Local service name, then the operating number in full-width brackets when known: `こだま824号（824A）`, `台灣高鐵 165次（台北→台中）`. An endpoint aside is allowed (the title presenter drops it). No romanized gloss and no provenance tags. |
| `number_en` | English service name in the operator's own romanization, without operating numbers: `Kodama 824`, `Keihin-Tōhoku Line Local`, `THSR 165`. Present on every ride. |
| `train_type` | Service class in the local language: `新幹線`, `特急`, `普通`, `區間`, `무궁화호`, `港鐵`, `輕軌`. |
| `vehicle_type` | Set only when the date-valid official timetable page states it, e.g. `N700系`, `N700S`, `500系`. |
| `company` | Short operator name used elsewhere in the app. |
| `direction` | `up` or `down` from RailCore `TravelDirection` (the editor's inference), or the loop word `内回り`/`外回り`. Otherwise omitted, as the editor leaves it empty. `unknown` and terminus names are not used. |
| `date` | `YYYY-MM-DD`. |
| stops | Every stop has `name`, `n02_station_code`, `platform_number` (null when unknown), `arrival`, `departure` (`HH:MM` or null), `stop_type`, `ride_segment`. The origin has no arrival and the destination has no departure. A short stop shown with a departure only keeps `arrival: null`. |
| `notes` | Disclosures that used to be packed into `number`, such as `時刻推定` (times estimated from the trip record) and `車号不明` (train number unknown), plus each ride's verification scope. |

## Timetable evidence rule

Times are filled only from an official source that explicitly covers the
service date: a date parameter, a monthly edition containing the date, or an
edition whose effective period includes the date. Nothing is interpolated, and
no current timetable is projected back onto a past date. Local trains, trams
and metro rides that have no trip identity keep their recorded times and
`null` where nothing was recorded.

## Sources applied (accessed 2026-11-05)

JR西日本 おでかけネット 列車時刻表 (`https://timetable.jr-odekake.net/train-timetable/<id>?date=<service date>`).
The page cites JR時刻表 2026年07月号 or 08月号, and its operating calendar marks the service date:

| Ride | Train | Page id | Edition |
|---|---|---|---|
| journey_D04B2C63CEA86422F386166CABE2A3FB | こだま824号 824A | 317161 | 2026-07 |
| journey_1CB70EB6BDEE3E624E5E990D2B1C00FB | ひかり718号 718A | 315921 | 2026-07 |
| journey_CE6CDD905BB6708E69DD82011EB8182B | さくら770号 770A (徳山 passed) | 318791 | 2026-07 |
| journey_FBC327CBC341BD103BEEAE00FD568C91 | こだま970号 970A (500系) | 316631 | 2026-08 |
| journey_C163CF0702200718E5E57A2BE6C21885 | ひかり706号 706A | 315511 | 2026-08 |
| journey_CD24799CE25B1CF61107969F8A30406F | ひかり706号 706A | 315511 | 2026-08 |
| journey_029F2E79178CF1AA008FB454C06992F7 | こだま841号 841A | 315921 | 2026-08 |
| journey_2634C4C2410DA151187D68ACC14F1201 | ひかり702号 702A | 315491 | 2026-08 |
| journey_21B9459DC7DFD29026EE0E54B15BF121 | こだま837号 837A | 315901 | 2026-08 |
| journey_A4B7BCFE572DCF976943553B301BBF51 | こだま829号 829A | 315861 | 2026-08 |
| journey_D34CC990A1B67E5BE0BA9D9730CA6916 | こだま834号 834A | 317041 | 2026-08 |
| journey_96B2EFFD4EC25479AFA91263963111A2 | こだま840号 840A | 316851 | 2026-08 |
| journey_8C70A9CF2CB598C4C2ABDA2EAABCE0F5 | こだま911号 911A | 316061 | 2026-08 |
| journey_923A26BB27C37BDF1717F1E4F21D5AF2 | こだま846号 846A, 名古屋→静岡 only | 317421 | 2026-07 |
| journey_07E6AD25D8057D28D08088C1D40C2491 | いしづち9号 1009M (was 9M, which is しおかぜ9号) | 125431 | 2026-08 |
| journey_510175D3C325909EF4C88C3A42E1108B | 剣山6号 4006D (was 56D) | 76271 | 2026-08 |
| journey_BB3AD8FEF0D118561F7FC4FA6227A5A6 | やくも22号 1022M | 941 | 2026-08 |

The same pages supply `platform_number` from their のりば column (70 stops on 16 rides,
parsed from the raw page for the ride's date; stops the page leaves blank stay `null`).
剣山6号's page gives no platform for the ride's stops. Page 125431 lists しおかぜ9号 and
いしづち9号 together; 高松 platform 7 is いしづち9号's, as しおかぜ9号 starts at 岡山.

- 南海 ラピートα3号 (20260731_02): `https://www.nankai.co.jp/lib/traffic/express/rapit/pdf/rairt_down.pdf`. The weekday table is effective from 2024-12-21, and no later 南海線 revision was found up to the 2026-07-31 service date. The intermediate departures at 天下茶屋, 泉佐野 and りんくうタウン come from this table; the endpoint times already matched it.
- MTR East Rail Line (HK sample): `https://www.mtr.com.hk/en/customer/services/train_service_index.html`. MTR publishes headways only, so no trip times are entered.
- Macao LRT Taipa Line (MO sample): `https://www.mlm.com.mo/tc/route.html` (updated 2026-09). This gives operating hours and headways only, so no trip times are entered.

## Not verified (left as recorded, disclosed in `notes`)

- journey_A83E8C0CD3219DDE9BDACE75633FE06B and journey_8468CDB2F92CD8F1CB56D7175B261C34 (JR East), plus journey_1C77A10398A5B717F5372522CD764D5F: the July 2026 edition of `timetables.jreast.co.jp` is no longer served (only 2611 is live). The 踊り子 record (熱海 18:00 → 東京 19:15) matches no 踊り子 found and is faster than the usual running time.
- 20260703_02: 846A starts at 名古屋, so the recorded 新大阪—名古屋 leg is probably a different train.
- journey_3741AFAFFD9A67394E057294ACF48B00 (長野電鉄): the only official table is the 2021-03-13 edition, with no stated validity for 2026-07-07.
- KR 경북선: no Korail-published timetable covering 2026-08-11 could be read. Secondary sources (`https://pat.im/1643`, `https://info.koreacharts.com/traintime/10259/10270/contents.html`) show 무궁화호 stopping at 상주 and 함창 and not at 백원 or 어등. 상주 is absent from the bundled `stations-kr.json`, so the stop list cannot be corrected in the sample alone.

## Rolling stock and platforms (research pass, accessed 2026-11-05)

`vehicle_type` is filled only where the source shows a single fleet for that service on the ride date. Values are at series level, e.g. `E233系`, with no 番台. Values from おでかけネット train pages come from that ride's date-specific page (its 車両設備情報 line, e.g. 「Ｎ７００系で運転」).
"Fan" means Japanese, Chinese, Korean or English Wikipedia. It is used only where the operator page was unavailable (jreast.co.jp refused automated fetches) or does not name the stock.

| Vehicle | Source kind | Source | Rides |
|---|---|---|---|
| 1000形 | fan | https://trafficnews.jp/post/685001 | `journey_1B73B253ED48ADAE75E0A27CD5EDD87C`, `journey_FA664788B3F334B952706589201D498B` |
| 1000形 | official | https://www.yui-rail.co.jp/yuirail/about/ | `journey_A04D207B2E4D8CA4B9088FA6DF5BDD29`, `journey_959DFFAA45FED199E0FD06F93A12C93B`, `journey_EE957F00F2B8D8D291D4CD7EB1826810`, `journey_3A264FF820AE17659ADDD22FDDADB270`, `journey_B29C2B434D4A5E393447665740312185`, `journey_311418DF2394CCFFF6AA3C0151F0CB10`, `journey_2DB618BA4041AF100A4FB6C47DA4B27C` |
| 2700系 | official | https://www.jr-shikoku.co.jp/02_information/care/tokkyu_nanpu/ | `journey_2A4BA95A7B92CB19921B27A2D3279C34`, `journey_D2D514AAEA06253635D51310E9C4C06B`, `journey_6322F5578A2F139890D3B028ADDAF45A` |
| 2700系 | official | https://www.jr-shikoku.co.jp/02_information/care/tokkyu_uzushio/ | `journey_771C696806C4705B412A265B953BD9A7` |
| 273系 | official | https://www.jr-odekake.net/railroad/yakumo/ | `journey_9B1957E8CA2CA62A34EEBFC519E64422`, `journey_BB3AD8FEF0D118561F7FC4FA6227A5A6` |
| 285系 | fan | https://ja.wikipedia.org/wiki/サンライズ出雲 | `journey_F29762068C2DDB4CD79CF4AF30B29529` |
| 50000系 | official | https://www.nankai.co.jp/tc_railway/traffic/express/rapit.html | `journey_0DCC26B17610DE9969C200D26CBA75DE` |
| 5000形 | official | https://www.city.sapporo.jp/st/subway/gaiyo/gaiyo.html | `journey_8B59A27F6F916CAE6A525B4F32488204`, `journey_17CC2EDF6C8FBBE0584149B2BADE9D7B`, `journey_B9B2EB9096BA7E1B096FCF563147469F` |
| 7000系 | official | https://www.mhi.com/jp/news/25021201.html | `journey_AEF095A24CF065375213A5A9A0AC163A` |
| 700T型 | fan | https://zh.wikipedia.org/wiki/台灣高速鐵路700T型電聯車 | `journey_E2BA1597EB6DEA75FB126926E564D6CD`, `journey_4D389948FB54DDE74017B2CCFC5B526D`, `journey_5A3C1D43A8E70734A5D5DA40D6D39099` |
| 733系 | fan | https://ja.wikipedia.org/wiki/はこだてライナー | `journey_9D02C3A9C9EC22156727EE34EF3EECD9` |
| 787系 | official | https://www.jrkyushu.co.jp/train/kids/guardian/train_equipment/ | `journey_45E72A351DEC6512AF96B89578A93E9A`, `journey_E9C359F48C7CC40ABC70DBD05B606CFA` |
| 8000形 | official | https://www.city.sapporo.jp/st/subway/gaiyo/gaiyo.html | `journey_97A52E47E661D43859B9236D25ECE603` |
| E131系 | fan | https://ja.wikipedia.org/wiki/相模線 | `journey_1C50841EDDE0B8259BF3CD6982B04968`, `journey_DBB4A436D118AFC963F3D76ACC6D7F5A` |
| E131系 | fan | https://ja.wikipedia.org/wiki/鶴見線 | `journey_73881D4AC6CDEB95F29753E8F861455B` |
| E231系 | fan | https://ja.wikipedia.org/wiki/中央・総武緩行線 | `journey_CBC698EF40ADC4349BF9FE4E96A022BA`, `journey_4D8504078E1EDCDDD6273B29F6C844F1`, `journey_E4ED0EC66250F2E663AEB7ECE1FA8F5A` |
| E233系 | fan | https://ja.wikipedia.org/wiki/中央線快速 | `journey_7E3B5F10D9F6347B6C726AEC1D57BA7A`, `journey_92A88D23E58F169A02F66FA4131F9CF4`, `journey_DA0120B61DAC677C7FE9EFB54CF8F052`, `journey_DAE47A568594FC62E600A5F695EB7365`, `journey_C03AE74555ED48DBCCA3989A84157CB7`, `journey_10321A2FDEF5906E4DCE8DB6986E3C03`, `journey_1F9D3D61F6C18F4BC2B202DC16B92231` |
| E233系 | fan | https://ja.wikipedia.org/wiki/京浜東北線 | `journey_4DCB77A37D44B9E2340421841026E845`, `journey_FD3D0B6540560EA9C1BD526322196797`, `journey_595FE5006ED23F7B331795A1C3A877E9`, `journey_6C38BB258FF7BBA93CB1A6C6284BC9C4`, `journey_5DD4E6CA03675E3FA6AC32063B33E078`, `journey_AEDF22100651041F822E1DFD54EC4653`, `journey_5AB68AB4738C250255A82B17A485CD8E`, `journey_DD359818F2CA9B303F5EF5A05FCDA15D` |
| E233系 | fan | https://ja.wikipedia.org/wiki/南武線 | `journey_D9EE58DC654F79D6E5D9B5AD1EE9222F` |
| E233系 | fan | https://ja.wikipedia.org/wiki/横浜線 | `journey_B1081E3920E5817960D57445107E8518`, `journey_A15A2CDA79EC2AB1DB648F12DECB9CFF`, `journey_1BF192064CE880673A0BB314C77436DB` |
| E235系 | fan | https://ja.wikipedia.org/wiki/山手線 | `journey_5D0B999496F4E95DC91A57FB2FACD2BF`, `journey_2421C1DE7244064D1E03E50A9E4A1707` |
| E235系 | fan | https://ja.wikipedia.org/wiki/横須賀線 | `journey_07159EDCA041241C5F7038F2DF87F3F4` |
| E257系 | fan | https://ja.wikipedia.org/wiki/わかしお_(列車) | `journey_AE4B3D6ECECDF1F02B9D88E33DB71D35` |
| E257系 | fan | https://ja.wikipedia.org/wiki/踊り子_(列車) | `journey_B113D59026AE72C23BC7DCC1E062B3D9` |
| E259系 | fan | https://ja.wikipedia.org/wiki/しおさい_(列車) | `journey_FB378E723A1A1C6D845DDBF2F4EC7B80` |
| E259系 | fan | https://ja.wikipedia.org/wiki/成田エクスプレス | `journey_680A26B9C2D06FDE49DABFF6A02DF17C` |
| E353系 | fan | https://ja.wikipedia.org/wiki/あずさ_(列車) | `journey_868731BF1A9520928B670EC3A3B8566D` |
| E353系 | fan | https://ja.wikipedia.org/wiki/かいじ_(列車) | `journey_3C1174A1740BAC769A067CDF20A0CF5F` |
| E531系 | fan | https://ja.wikipedia.org/wiki/水戸線 | `journey_1F114EC77ED45EB89D68F1C32934755E` |
| E653系 | fan | https://ja.wikipedia.org/wiki/いなほ_(列車) | `journey_03F366E23A32B262DDDA6774510A20D4` |
| E657系 | fan | https://ja.wikipedia.org/wiki/ひたち_(列車) | `journey_1367E2AD44FB1282A603082C6B023451` |
| E6系 | fan | https://ja.wikipedia.org/wiki/こまち_(列車) | `journey_8468CDB2F92CD8F1CB56D7175B261C34` |
| E751系 | fan | https://ja.wikipedia.org/wiki/つがる_(列車) | `journey_290DDF7BAF84271A16574A1D9669181F` |
| E7系 | fan | https://ja.wikipedia.org/wiki/とき_(列車) | `journey_F977C83D37F1F33106F63344B048477F` |
| EMU3000型 | fan | https://zh.wikipedia.org/wiki/台鐵EMU3000型電聯車 | `journey_0A8EC92F75B878119658D0752A71E41F`, `journey_D902105FFF79F2BC91DD69001C1D1752`, `journey_CEB49C47CA401AD978BFE56F3D55F4C7` |
| Hyundai Rotem R-train | fan | https://en.wikipedia.org/wiki/East_Rail_line | `journey_E432976CF3960943D65E32F615830502` |
| N700S | fan | https://ja.wikipedia.org/wiki/かもめ_(列車) | `journey_33CBB95F33F145A44996E104C7110877` |
| N700S | official | https://timetable.jr-odekake.net/train-timetable/163141 | `journey_F57EA63347F47F36D98DF654CBAFDA69` |
| N700S | official | https://timetable.jr-odekake.net/train-timetable/317421 | `journey_923A26BB27C37BDF1717F1E4F21D5AF2` |
| N700系 | fan | https://ja.wikipedia.org/wiki/さくら_(新幹線) | `journey_BDD9F936F447CBF04C5075C26DA76C88` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/104451 | `journey_0488BA679E26E3DF7B20C50B61F5242A` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/163011 | `journey_9409400F1A9EC5DA6CDB7FFBD64EBE2D` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/315521 | `journey_C60F2E6092D87D9F5F85243B93428D5E` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/315571 | `journey_E60A7D258F854777D4460EDFE961AE32` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/315861 | `journey_FB79023EBDF3D810C09FBCE322F2B679` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/316071 | `journey_D67EA61A2C641A02967314209A67C0A5` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/316261 | `journey_969009740BE6241F5DEEE35BD8CAA7BA` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/316431 | `journey_5DDC220B564315ABDE363017D45930D6` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/317141 | `journey_5515D04C2ECC7C28FC099F7E25093E2D` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/317251 | `journey_151F1405ADA1BC7794EB8C44CD7709C2` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/317271 | `journey_5E47ABA2FB7E3A6CC5F14CBCC010472D` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/317301 | `journey_7ED510CE68E0BE81303D118A1B9E3575` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/317471 | `journey_4CB9E326EEC18D85989CEF90ACF970A1` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/317641 | `journey_0D198248AFFDB230E7BBFF14146178C0` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/318401 | `journey_20A4F24136AEE7B83D1AD4A267C4DE85` |
| キハ183系 | fan | https://ja.wikipedia.org/wiki/JR九州キハ183系気動車 | `journey_02C494EB5E72DE2FE0D3E5BC7D303309`, `journey_71102CEF82BE99D98F5C7101CD080E07` |
| キハ185系 | fan | https://ja.wikipedia.org/wiki/剣山_(列車) | `journey_510175D3C325909EF4C88C3A42E1108B` |
| キハ187系 | fan | https://ja.wikipedia.org/wiki/おき_(列車) | `journey_55E89F3BE5BD16BC06291B252CFFA81B` |
| キハ261系 | fan | https://ja.wikipedia.org/wiki/おおぞら_(列車) | `journey_43D90DF84B5E40D6304EC290E8ED4E74`, `journey_F6F27BD3CBEFAA23FC0956F049DED550` |
| キハ261系 | fan | https://ja.wikipedia.org/wiki/北斗_(列車) | `journey_7FDB2E2A33B27404C1C8198B3C2B29F8`, `journey_8BADA44ED18197CDFA42A2D89B3028F1` |
| キハ261系 | fan | https://ja.wikipedia.org/wiki/宗谷_(列車) | `journey_32E525B07148EE19DC4F3B99A36535ED`, `journey_10F4EC2286758F85D709118AAFA6260E` |
| 三菱重工 濱海巡航列車 | fan | https://zh.wikipedia.org/wiki/澳門輕軌 | `journey_E155548B9C8291DA928D5426A9D0134B` |
| 桃園機場捷運 直達車電聯車（201～217編組） | fan | https://zh.wikipedia.org/wiki/桃園機場捷運 | `journey_5C3C741549CF09E20FE4CC4F7389B758` |
| 西門子高運量電聯車 | fan | https://zh.wikipedia.org/wiki/高雄捷運紅線 | `journey_2FDE3816A557FFFB50406D18A131A336`, `journey_F889D3193B98C1B436F80571170668AA`, `journey_927016E22113A45080FBC58092D28EB0`, `journey_10253133B7525E17509D09650522E725`, `journey_392AB4A925F885DE6CD17FA95C36040E`, `journey_BCCC18D524113D54156C5874685CEE29` |

Platforms come from the のりば column of each ride's date-specific JR西日本 おでかけネット train page (`https://timetable.jr-odekake.net/train-timetable/<id>?date=<YYYYMMDD>`, JR時刻表 2026年07/08月号). They were read from the raw page; blank cells stay `null`. Rides filled in this pass:

- `journey_A9554752F257CDA52831A6C0EED248AF`: 天王寺 18, 大阪 24, 新大阪 1
- `journey_4CB9E326EEC18D85989CEF90ACF970A1`: 三島 6, 熱海 7, 小田原 14, 新横浜 2, 品川 21
- `journey_5DDC220B564315ABDE363017D45930D6`: 新横浜 3, 小田原 13, 熱海 6, 三島 5
- `journey_7ED510CE68E0BE81303D118A1B9E3575`: 三島 6, 熱海 7, 小田原 14, 新横浜 2, 品川 21, 東京 17
- `journey_74236A39F500AA7027A8F519567B952B`: 福井 12, 敦賀 12
- `journey_65F43AE4739DB31208BF9295B6539472`: 敦賀 34, 米原 7
- `journey_F57EA63347F47F36D98DF654CBAFDA69`: 米原 12, 岐阜羽島 1, 名古屋 14
- `journey_FB79023EBDF3D810C09FBCE322F2B679`: 名古屋 15, 浜松 5, 静岡 5, 三島 6
- `journey_E60A7D258F854777D4460EDFE961AE32`: 三島 5, 静岡 6, 浜松 6, 名古屋 16, 京都 14
- `journey_80163C1B9EDB32F4644B6CED30B291F5`: 京都 10
- `journey_2C4B34CD53F9E78ECA8875BC1ABCD617`: 京都 10
- `journey_0488BA679E26E3DF7B20C50B61F5242A`: 京都 11, 名古屋 14
- `journey_7A3B8940A7731646F2E0DB38A8C89C21`: 金沢 12, 富山 12, 上越妙高 12, 飯山 11, 長野 13, 高崎 14, 大宮 13
- `journey_D67EA61A2C641A02967314209A67C0A5`: 東京 19, 品川 23, 新横浜 4, 小田原 13, 熱海 6, 三島 5
- `journey_5515D04C2ECC7C28FC099F7E25093E2D`: 三島 6, 熱海 7, 小田原 14, 新横浜 2, 品川 21, 東京 14
- `journey_969009740BE6241F5DEEE35BD8CAA7BA`: 東京 17, 品川 24, 新横浜 3, 小田原 13, 熱海 6, 三島 5
- `journey_9409400F1A9EC5DA6CDB7FFBD64EBE2D`: 三島 5, 静岡 6, 浜松 6, 名古屋 16
- `journey_C60F2E6092D87D9F5F85243B93428D5E`: 名古屋 16, 京都 14, 新大阪 21, 新神戸 1, 西明石 11, 姫路 12, 相生 11, 岡山 21
- `journey_9B1957E8CA2CA62A34EEBFC519E64422`: 岡山 2, 米子 2
- `journey_55E89F3BE5BD16BC06291B252CFFA81B`: 米子 2, 益田 1, 山口 1, 新山口 2
- `journey_4B847D0A569A7FF0DFF0101FF69D5F0A`: 広島 5
- `journey_0D198248AFFDB230E7BBFF14146178C0`: 広島 11, 徳山 7, 小倉 12, 博多 15
- `journey_151F1405ADA1BC7794EB8C44CD7709C2`: 久留米 12, 熊本 13
- `journey_5E47ABA2FB7E3A6CC5F14CBCC010472D`: 熊本 13, 鹿児島中央 14
- `journey_CECE2010BC0D2F1EB19C89BFD5900CAD`: 岡山 6
- `journey_F29762068C2DDB4CD79CF4AF30B29529`: 静岡 4, 浜松 4, 姫路 8, 岡山 8, 米子 2
- `journey_20A4F24136AEE7B83D1AD4A267C4DE85`: 岡山 23, 新大阪 20

Left empty with candidates. Either several types run the service, or the train could not be identified. Candidates with no cited page are unverified.

- `journey_A9554752F257CDA52831A6C0EED248AF`: 271系 / 281系
- `journey_9EBA4C59A5675EBCE17BEBAC846CF2CA`: 京急1000形 / 京急600形 / 都営5500形 / 5300形 / 北総7500形 / 京成3000形 etc.
- `journey_C07243F8AADDB594384BBF1CC16C13EA`: 12-000形 / 12-600形
- `journey_5C3BA9F2C1A8F58936EC22D01F4E22E2`: 都営6500形 / 東急3000/5080系 / 相鉄20000系/21000系
- `journey_09AC64CFCEE12C93E83510873DD6FEC1`: 2000系
- `journey_EAACE466C535944D58A31E97A124CF0C`: E233系 / 東京臨海高速鉄道70-000形
- `journey_F3AE731354D1EAA0C06B45E04BE9F302`: E231系 / E233系
- `journey_9F1B97EDB6DCD7A4DB1908060F60E180`: E233系 — 根岸線は京浜東北線E233系1000番台と横浜線直通E233系6000番台が共に運転
- `journey_2840A4D4E48F45ECA2F36BE4ED5C5E2A`: Y500系 / 東急5050系 / 東京メトロ10000/17000系 / 西武40000系 / 東武50070系
- `journey_588AB2A1A40723D13732520638875B90`: E231系 / E231系
- `journey_B6AC22131D2441B90E2E47880C035680`: 東京メトロ10000系 / 17000系 / 西武 / 東急 / 東武直通車
- `journey_A6900040ECB7DC73804CD885E0C55A77`: 東京メトロ10000系 / 17000系 / 西武 / 東急 / 東武直通車
- `journey_5D02E4142B00032F153A4A2DF85B955D`: E5系 / H5系
- `journey_E7BA8AD080B2F29F785AC451F915075F`: E5系 / H5系
- `journey_B3210B8E26A09DDE4055CBC06E62E202`: E7系 / W7系
- `journey_55DB5F0FE70F752721E67BA029168A20`: E7系 / W7系
- `journey_74236A39F500AA7027A8F519567B952B`: E7系 / W7系
- `journey_65F43AE4739DB31208BF9295B6539472`: 681系 / 683系
- `journey_FD6353765B0036EFBE30A6B9D31CE9D3`: E5系 / E2系
- `journey_1EAE35C4A37558CFA7DD681330411832`: E7系 / W7系
- `journey_7A3B8940A7731646F2E0DB38A8C89C21`: E7系 / W7系
- `journey_0F013B23352B2D55E622E87E2E8E1DB4`: E233系 / 東京臨海高速鉄道70-000形
- `journey_8AD20CEBC2F4E010D786EA9CEE066ABE`: 各系列混在 (2000/6000/9000/20000/30000/40000/新101系)
- `journey_37EBEBB6809CFBA2C08E96855F63306A`: 各系列混在 (2000/6000/9000/20000/30000/40000/新101系)
- `journey_99AFD75780558F89BFB7FC505A282831`: E231系 / 209系
- `journey_F9ABBBD9EF93833A99D5F678570D5898`: 各系列混在 (2000/6000/9000/20000/30000/40000/新101系)
- `journey_025A9A2E73804710C0A0544D46DA840F`: 各系列混在 (2000/6000/9000/20000/30000/40000/新101系)
- `journey_3D6CBC5295CE31F009A715F0A483EDF5`: 各系列混在 (2000/6000/9000/20000/30000/40000/新101系)
- `journey_578784BBC21BEB37C6BCDB3F75623287`: E231系 / 209系
- `journey_4DBADC9CC0B33FDC9F5E0DA527EC5AA0`: E5系 / H5系
- `journey_FF43AD962224E5B60A731748776A27EB`: A1200形 / A1100形 / 3300形 / 8500形 / 8600形 / M100形 / 300形/350形ほか
- `journey_5AB6DC7EDCD13272F4DD08F0EEEDDDB5`: A1200形 / A1100形 / 3300形 / 8500形 / 8600形 / M100形 / 300形/350形ほか
- `journey_A51DFF674B84CF19A725723E186BE42B`: 500形 / 700形 / 800形 / 3000形 / 8000形 / 9600形 / 30形 / ほか
- `journey_0CD36C937D37303F9498C53BF7B42430`: 500形 / 700形 / 800形 / 3000形 / 8000形 / 9600形 / 30形 / ほか
- `journey_915349569139B316338DF97618D6F773`: E5系 / H5系
- `journey_024B5864D9989D220DE5C73F0EAE833F`: E5系 / H5系
- `journey_8B77161CDFB6C2A3CCCE5B7C674FF523`: E5系 / H5系
- `journey_596792300B91ACEAE52DDC2FF9D11D2E`: E5系 / E2系
- `journey_76C5FA48675C931CCDE2EB71E9A05658`: 5000形 / 3900形 / 3800形 / 3700形 / 1000形 / 700形ほか
- `journey_9F86A38C7DD4FAD1DB6894D4FD0118D1`: 5000形 / 3900形 / 3800形 / 3700形 / 1000形 / 700形ほか
- `journey_54E586655BBD3609E653BC7290FA2B34`: 800系 / N700系
- `journey_06EC08904789EE82E214ED3D28758DE5`: 783系 / 787系 / 885系
- `journey_71DD8854E028C292A3A8359556C3866B`: MR-600形 / MR-200形
- `journey_082EA2B0A90F678FE1E8D274B729F9D4`: MR-600形 / MR-200形
- `journey_B1AB45AE6B8B33C3A8CD8BC12BB07D33`: MR-600形 / MR-200形
- `journey_87D92EF0BAE97A00C634BA96DA890A46`: 3000形 / 1200形 / 2000形 / 5000形 / 6000形ほか
- `journey_08B980D1C7CB9F6CAD15CD060A45807F`: 3000形 / 1200形 / 2000形 / 5000形 / 6000形ほか
- `journey_AD59A05EAE440ED38AA3279A20557058`: 3000形 / 1200形 / 2000形 / 5000形 / 6000形ほか
- `journey_C9DEC0495C5FAE492C4FE858535C3E30`: 3000形 / 1200形 / 2000形 / 5000形 / 6000形ほか
- `journey_9E0FE255A29C5BBDEE31480F4AED2BE8`: 787系 / 885系
- `journey_425FC76FB050394D51554A9A2D6B369B`: 9700形 / 9200形 / 0800形 / 1200形 / 8500形ほか
- `journey_8B16C03F0CFAADDD02FD4A3500661E2E`: 9700形 / 9200形 / 0800形 / 1200形 / 8500形ほか
- `journey_FF81EAF940C88B515459211A732AD78C`: 7000形 / 7500形 / 1000形 / 2100形 / 9500形ほか
- `journey_6F379655E47131DD2F854B65A847B9F0`: 883系 / 885系
- `journey_31C35A5D2E003443D5E26D7654555B25`: 787系 / 885系 / 783系
- `journey_4BB3DDFC465CB6E4719AB69741432424`: 2000形 / 3000形 / 5000形
- `journey_FA2577CF26696BE8E3619FBC6FA06440`: 400形 / 500形 / 300形ほか
- `journey_CECE2010BC0D2F1EB19C89BFD5900CAD`: 8000系 / 8600系
- `journey_BEEF6E99345E6E5CD1F5B4AF369AC636`: 8000系 / 8600系
- `journey_07E6AD25D8057D28D08088C1D40C2491`: 8000系 / 8600系
- `journey_350E1BD8273A1E04690813FB31BF720C`: 600形 / 200形 / 700形 / 800形 / 2000形ほか
- `journey_0694D992D0F11AE81676A5DCDFBFD38D`: 600形 / 200形 / 700形 / 800形 / 2000形ほか
- `journey_1C77A10398A5B717F5372522CD764D5F`: E257系 — 列車が特定できず（記録時刻に合う踊り子が見つからない）
- `journey_856C6D19621F1681AAF99048FEEAED8D`: E231系 / E233系
- `journey_A83E8C0CD3219DDE9BDACE75633FE06B`: E2系 / E5系 / E6系 / E8系
- `journey_7296C07F3881D0CAAF2DE8828D443471`: 1000形 / 2000形
- `journey_323ADE1BA38D637024FE37B30449D56E`: 1000形 / 2000形
- `journey_E97B57247FA4FAF2AD7C092FA6C78A0E`: 1000系 / 5000系 / 7000系
- `journey_1066A578B168E8867C0C2526F4C4918A`: 1000系 / 5000系 / 7000系
- `journey_95838C76BAA5FDF356AC92F8B54F802F`: 1000系 / 2000系 / 6000系 / 7000系 / 8000系 / 9000系 / 12000系ほか
- `journey_C409454EC8F3724E2ECD7CD942A27B3D`: 1000系 / 2000系 / 6000系 / 7000系 / 8000系 / 9000系 / 12000系ほか
- `journey_48FE139478368C9C7274289E1D49510A`: C321型 / C341型
- `journey_7F9FEBF55983F06E943C4BF21837CD2E`: C321型 / C341型
- `journey_B34C34D4052B67C1D1F2468F4B8826A4`: C321型 / C341型
- `journey_253013612D5701BF5895AD9C0FC1A850`: EMU800型 / EMU900型 / EMU700型 / EMU600型 / EMU500型
- `journey_85C2F9F935C9A4701208C881737C7ADC`: EMU800型 / EMU900型 / EMU700型 / EMU600型 / EMU500型
- `journey_D6E210E0D14743B7AFE4EF6855ADC7FA`: 阿里山林鐵 柴油機車(多型)
- `journey_214DEC1A58D8A2E683D5E17A47BFCE7F`: 阿里山林鐵 柴油機車(多型)
- `journey_5BADD88C12380B6A886444FB69041F7F`: 阿里山林鐵 柴油機車(多型)
- `journey_D4687FB43F9C1C43E0B0E40017AC9EDC`: 阿里山林鐵 柴油機車(多型)
- `journey_E12389096A2B7F909034258E902F941E`: 阿里山林鐵 柴油機車(多型)
- `journey_DFA582684EEDC99182E6D448F71607F7`: 阿里山林鐵 柴油機車(多型)
- `journey_0960494E1EEF4CBDB6B1E4B1FE90BEB7`: CAF Urbos 3型 / Alstom Citadis 305型
- `journey_701B2439EE7B2E05AF11E637D13B1CB5`: EMU800型 / EMU900型 / EMU700型 / EMU600型 / EMU500型
- `journey_06535A45062A8500166100F9B37C31F1`: EMU800型 / EMU900型 / EMU700型 / EMU600型 / EMU500型
- `journey_C929D1DB4BBEDD1ED71B9C4885026D78`: 10500/10600型客車(電力機車牽引)
- `journey_B7F582C16E904392DA2C9CE339DF6780`: 무궁화호 객차 — 「무궁화호 객차」は車種でなく、機関車・客車形式は未確認
- `journey_7866E65358DB80921D2614D5398FEEE1`: E233系 / 東京メトロ16000系 / 東京メトロ06系
- `journey_B9F7AF6F378531D710C6C4DB8A75FE84`: E531系 / E231系
- `journey_5FAF02A78D0297BD7E6BC7189EEE5479`: 211系 / E231系 / E233系
- `journey_8B370FD51DD05BF218108C28B207147C`: E231系 / E233系
- `journey_C83F01E4FC0FB070B439E1F554DDB2E3`: E233系 / 東京臨海高速鉄道70-000形 / 東京臨海高速鉄道71-000形
- `journey_19E72EF8A279F9BEA3E43507CFD262B8`: E231系 / 209系
- `journey_DC35D009289BDAA8CE95542D519A2D3C`: E231系 / E233系
- `journey_E5271380AA0BE6E27DCB2F8E8D465275`: E127系 / 205系
- `journey_5A7792A36B7AFBF89C4188A3AF6AB319`: E127系 / 205系
- `journey_74A2A9A828B6C4EA8C9EA2D4ACB5E5B1`: E231系 / E233系
- `journey_38D81E63FDF3CA29C2E2058E35C8A761`: E235系
- `journey_56503D37265880A94FA191E1A470173B`: E231系 / E231系 / 209系
- `journey_B39F46D813FA1636ED3CD36C7FA1358D`: E233系 / 東京臨海高速鉄道70-000形 / 東京臨海高速鉄道71-000形
- `journey_D878F62C43D5A7C64B14222B73FD4CD0`: E231系 / E231系 / 209系
- `journey_B3F161407E8E14E91AF8646028705859`: 209系 / E235系 / E233系
- `journey_5F1433ABC14572422C3B891B334CCB7E`: 209系 / 209系 / E131系
- `journey_E3C5A17962C2DDAE1DCC23DDE0AA3C1A`: 209系 — 総武本線 千葉以東の普通は209系とE131系が共に運用
- `journey_8DFA7F87666D8581074D297024482EF1`: 209系 / E233系
- `journey_813F6AB74D714CCD2B098529CC5D7785`: 209系 / E233系
- `journey_1D251A826357268B527F63C503905C1C`: E131系 / 209系
- `journey_0FEE4DC2B4589497ABD4E35742C65942`: E131系 — 内房線 木更津以南はE131系が主力だが専用とは確認できず
- `journey_F3236E4E4DBC6C24A60FCFF8CF8FD52D`: E131系 / E233系 / 209系
- `journey_70220CF57D13FED0E93F34B981914A11`: E233系 / 209系
- `journey_48A839FEAF8AAB049FE99B5BFEB83C01`: E233系 / E235系
- `journey_FDB4DA52F28136A256951A235E9FF713`: E231系 / E531系
- `journey_EA71B8D43807377F6733B3ECD2AF3A39`: E233系 / 東京メトロ16000系
- `journey_FCF5080D6BF57735BD6B550726AEBCC2`: 209系 / E233系
- `journey_8473C35D9B0263A67C1AE3CF2EF35F88`: E231系 / E233系
- `journey_346B51D9286011FC76E1B3066295219B`: E231系 / 209系
- `journey_8EEEEA38327E98645C7007A692CCAD31`: E233系 / 東京臨海高速鉄道70-000形
- `journey_5F07101A177600FAEAB79C27F00916AF`: E657系 / E257系
