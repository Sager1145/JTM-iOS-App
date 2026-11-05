# Bundled example trips: field conventions and sources

Applies to the sample stores `train-store.json` (jp), `train-store-tw.json`,
`train-store-hk.json`, `train-store-kr.json`, `train-store-mo.json` and
`special-samples/*.json`. The precomputed directories (`sample-data*/`,
`*-data/`) are regenerated from these stores by
`scripts/build/precompute-train-parts.mjs`. The 2026-11-05 normalization was
applied by `scripts/samples/normalize-sample-fields.py`.

Ride ids: every bundled ride uses the same id scheme as a ride added in the
app, `journey_` followed by 32 uppercase hex digits (the first 16 bytes of the
SHA-256 of the former descriptive id). The former descriptive id (for example
`20260703_01_haruka`) is kept only in this document, where the tables and lists
below still use it as readable provenance. The full old-to-new map is in
"Ride id map" at the end.

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
| 20260710_02_kodama824 | こだま824号 824A | 317161 | 2026-07 |
| 20260710_05_hikari718 | ひかり718号 718A | 315921 | 2026-07 |
| 20260719_04_sakura770 | さくら770号 770A (徳山 passed) | 318791 | 2026-07 |
| 20260724_07_kodama970 | こだま970号 970A (500系) | 316631 | 2026-08 |
| 20260725_05_hikari706 | ひかり706号 706A | 315511 | 2026-08 |
| 20260726_03_hikari706 | ひかり706号 706A | 315511 | 2026-08 |
| 20260726_06_kodama_atami | こだま841号 841A | 315921 | 2026-08 |
| 20260727_03_hikari702 | ひかり702号 702A | 315491 | 2026-08 |
| 20260727_09_kodama837 | こだま837号 837A | 315901 | 2026-08 |
| 20260728_02_kodama829 | こだま829号 829A | 315861 | 2026-08 |
| 20260728_05_kodama834 | こだま834号 834A | 317041 | 2026-08 |
| 20260729_02_kodama840 | こだま840号 840A | 316851 | 2026-08 |
| 20260729_03_kodama911 | こだま911号 911A | 316061 | 2026-08 |
| 20260703_02_tokaido_shinkansen_hikari_kodama | こだま846号 846A, 名古屋→静岡 only | 317421 | 2026-07 |
| 20260724_01_ishizuchi9 | いしづち9号 1009M (was 9M, which is しおかぜ9号) | 125431 | 2026-08 |
| 20260724_03_tsurugisan6 | 剣山6号 4006D (was 56D) | 76271 | 2026-08 |
| 20260730_03_yakumo22 | やくも22号 1022M | 941 | 2026-08 |

The same pages supply `platform_number` from their のりば column (70 stops on 16 rides,
parsed from the raw page for the ride's date; stops the page leaves blank stay `null`).
剣山6号's page gives no platform for the ride's stops. Page 125431 lists しおかぜ9号 and
いしづち9号 together; 高松 platform 7 is いしづち9号's, as しおかぜ9号 starts at 岡山.

- 南海 ラピートα3号 (20260731_02): `https://www.nankai.co.jp/lib/traffic/express/rapit/pdf/rairt_down.pdf`. The weekday table is effective from 2024-12-21, and no later 南海線 revision was found up to the 2026-07-31 service date. The intermediate departures at 天下茶屋, 泉佐野 and りんくうタウン come from this table; the endpoint times already matched it.
- MTR East Rail Line (HK sample): `https://www.mtr.com.hk/en/customer/services/train_service_index.html`. MTR publishes headways only, so no trip times are entered.
- Macao LRT Taipa Line (MO sample): `https://www.mlm.com.mo/tc/route.html` (updated 2026-09). This gives operating hours and headways only, so no trip times are entered.

## Not verified (left as recorded, disclosed in `notes`)

- 20260727_04_nasuno259 and 20260727_05_komachi (JR East), plus 20260726_07_odoriko: the July 2026 edition of `timetables.jreast.co.jp` is no longer served (only 2611 is live). The 踊り子 record (熱海 18:00 → 東京 19:15) matches no 踊り子 found and is faster than the usual running time.
- 20260703_02: 846A starts at 名古屋, so the recorded 新大阪—名古屋 leg is probably a different train.
- 20260707_06_a_ltdexp (長野電鉄): the only official table is the 2021-03-13 edition, with no stated validity for 2026-07-07.
- KR 경북선: no Korail-published timetable covering 2026-08-11 could be read. Secondary sources (`https://pat.im/1643`, `https://info.koreacharts.com/traintime/10259/10270/contents.html`) show 무궁화호 stopping at 상주 and 함창 and not at 백원 or 어등. 상주 is absent from the bundled `stations-kr.json`, so the stop list cannot be corrected in the sample alone.

## Rolling stock and platforms (research pass, accessed 2026-11-05)

`vehicle_type` is filled only where the source shows a single fleet for that service on the ride date. Values are at series level, e.g. `E233系`, with no 番台. Values from おでかけネット train pages come from that ride's date-specific page (its 車両設備情報 line, e.g. 「Ｎ７００系で運転」).
"Fan" means Japanese, Chinese, Korean or English Wikipedia. It is used only where the operator page was unavailable (jreast.co.jp refused automated fetches) or does not name the stock.

| Vehicle | Source kind | Source | Rides |
|---|---|---|---|
| 1000形 | fan | https://trafficnews.jp/post/685001 | `20260722_12_monorail_kokura_kikugaoka`, `20260722_13_monorail_kikugaoka_kokura` |
| 1000形 | official | https://www.yui-rail.co.jp/yuirail/about/ | `20260731_03_yui_naha_akamine`, `20260731_04_yui_akamine_naha`, `20260731_05_yui_tedako_shuri`, `20260731_06_yui_shuri_miebashi`, `20260731_07_yui_miebashi_naha`, `20260731_08_yui_naha_miebashi`, `20260801_01_yui_miebashi_naha` |
| 2700系 | official | https://www.jr-shikoku.co.jp/02_information/care/tokkyu_nanpu/ | `20260724_02_nanpu9`, `20260724_05_nanpu17`, `20260724_06_nanpu28` |
| 2700系 | official | https://www.jr-shikoku.co.jp/02_information/care/tokkyu_uzushio/ | `20260723_05_uzushio10` |
| 273系 | official | https://www.jr-odekake.net/railroad/yakumo/ | `20260719_02_yakumo11`, `20260730_03_yakumo22` |
| 285系 | fan | https://ja.wikipedia.org/wiki/サンライズ出雲 | `20260729_05_sunrise_izumo` |
| 50000系 | official | https://www.nankai.co.jp/tc_railway/traffic/express/rapit.html | `20260731_02_rapit_alpha3` |
| 5000形 | official | https://www.city.sapporo.jp/st/subway/gaiyo/gaiyo.html | `20260716_01_sapporo_subway_namboku_sapporo_susukino`, `20260716_02_sapporo_subway_namboku_odori_nakajimakoen`, `20260716_06_sapporo_subway_namboku_odori_sapporo` |
| 7000系 | official | https://www.mhi.com/jp/news/25021201.html | `20260720_42_astram_hondori_johoku` |
| 700T型 | fan | https://zh.wikipedia.org/wiki/台灣高速鐵路700T型電聯車 | `20260805_01_thsr_165_taipei_taichung`, `20260812_02_thsr_826_zuoying_taipei`, `20260812_05_thsr_161_nangang_taipei` |
| 733系 | fan | https://ja.wikipedia.org/wiki/はこだてライナー | `20260718_01_hakodate_liner` |
| 787系 | official | https://www.jrkyushu.co.jp/train/kids/guardian/train_equipment/ | `20260722_04_kirishima8`, `20260722_05_nichirin10` |
| 8000形 | official | https://www.city.sapporo.jp/st/subway/gaiyo/gaiyo.html | `20260716_05_sapporo_subway_tozai_nishi11_odori` |
| E131系 | fan | https://ja.wikipedia.org/wiki/相模線 | `new_year_grand_loop_20251231_09`, `tokyo_limited_express_loop_20260529_07` |
| E131系 | fan | https://ja.wikipedia.org/wiki/鶴見線 | `new_year_grand_loop_20251231_12` |
| E231系 | fan | https://ja.wikipedia.org/wiki/中央・総武緩行線 | `new_year_grand_loop_20260101_23`, `new_year_grand_loop_20260101_34`, `tokyo_limited_express_loop_20260529_16` |
| E233系 | fan | https://ja.wikipedia.org/wiki/中央線快速 | `new_year_grand_loop_20251231_18`, `new_year_grand_loop_20260101_36`, `tokyo_limited_express_loop_20260529_10`, `20260705_03_chuo_line`, `20260726_04_chuo_rapid_shinjuku`, `20260726_05_chuo_rapid_tokyo`, `20260726_08_chuo_rapid_shinjuku2` |
| E233系 | fan | https://ja.wikipedia.org/wiki/京浜東北線 | `new_year_grand_loop_20251231_11`, `new_year_grand_loop_20251231_21`, `20260704_11_keihin_tohoku_line`, `20260710_07_keihin_tohoku_local`, `20260711_01_keihin_tohoku_negishi_local`, `20260713_01_keihin_tohoku_negishi_local`, `20260727_06_local_akihabara`, `20260727_07_local_tokyo` |
| E233系 | fan | https://ja.wikipedia.org/wiki/南武線 | `new_year_grand_loop_20251231_17` |
| E233系 | fan | https://ja.wikipedia.org/wiki/横浜線 | `new_year_grand_loop_20251231_08`, `tokyo_limited_express_loop_20260529_08`, `20260704_12_yokohama_line` |
| E235系 | fan | https://ja.wikipedia.org/wiki/山手線 | `new_year_grand_loop_20260101_37`, `20260705_07_yamanote_line` |
| E235系 | fan | https://ja.wikipedia.org/wiki/横須賀線 | `new_year_grand_loop_20260101_33` |
| E257系 | fan | https://ja.wikipedia.org/wiki/わかしお_(列車) | `tokyo_limited_express_loop_20260529_03` |
| E257系 | fan | https://ja.wikipedia.org/wiki/踊り子_(列車) | `tokyo_limited_express_loop_20260529_05` |
| E259系 | fan | https://ja.wikipedia.org/wiki/しおさい_(列車) | `tokyo_limited_express_loop_20260529_01` |
| E259系 | fan | https://ja.wikipedia.org/wiki/成田エクスプレス | `20260727_08_narita_express` |
| E353系 | fan | https://ja.wikipedia.org/wiki/あずさ_(列車) | `tokyo_limited_express_loop_20260529_15` |
| E353系 | fan | https://ja.wikipedia.org/wiki/かいじ_(列車) | `tokyo_limited_express_loop_20260529_09` |
| E531系 | fan | https://ja.wikipedia.org/wiki/水戸線 | `new_year_grand_loop_20251231_03` |
| E653系 | fan | https://ja.wikipedia.org/wiki/いなほ_(列車) | `20260706_03_inaho14` |
| E657系 | fan | https://ja.wikipedia.org/wiki/ひたち_(列車) | `tokyo_limited_express_loop_20260529_04` |
| E6系 | fan | https://ja.wikipedia.org/wiki/こまち_(列車) | `20260727_05_komachi` |
| E751系 | fan | https://ja.wikipedia.org/wiki/つがる_(列車) | `20260706_02_super_tsugaru2` |
| E7系 | fan | https://ja.wikipedia.org/wiki/とき_(列車) | `20260707_01_toki308` |
| EMU3000型 | fan | https://zh.wikipedia.org/wiki/台鐵EMU3000型電聯車 | `20260806_01_tra_tze_chiang_3000_137_taichung_changhua`, `20260808_01_tra_tze_chiang_3000_191_taichung_chiayi`, `20260809_04_tra_tze_chiang_3000_125_chiayi_kaohsiung` |
| Hyundai Rotem R-train | fan | https://en.wikipedia.org/wiki/East_Rail_line | `HK-SAMPLE-EAL-LOW` |
| N700S | fan | https://ja.wikipedia.org/wiki/かもめ_(列車) | `20260721_05_kamome22` |
| N700S | official | https://timetable.jr-odekake.net/train-timetable/163141 | `20260708_03_hikari648` |
| N700S | official | https://timetable.jr-odekake.net/train-timetable/317421 | `20260703_02_tokaido_shinkansen_hikari_kodama` |
| N700系 | fan | https://ja.wikipedia.org/wiki/さくら_(新幹線) | `20260723_01_sakura740` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/104451 | `20260710_01_nozomi252` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/163011 | `20260718_11_hikari659` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/315521 | `20260719_01_hikari703` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/315571 | `20260709_02_hikari713` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/315861 | `20260708_04_hikari706` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/316071 | `20260713_02_kodama801` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/316261 | `20260718_08_kodama839` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/316431 | `20260704_13_kodama915` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/317141 | `20260713_05_kodama816` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/317251 | `20260721_07_sakura749` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/317271 | `20260721_14_sakura767` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/317301 | `20260705_02_kodama802` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/317471 | `20260704_02_kodama918` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/317641 | `20260720_45_sakura753_hiroshima_hakata` |
| N700系 | official | https://timetable.jr-odekake.net/train-timetable/318401 | `20260730_04_sakura762` |
| キハ183系 | fan | https://ja.wikipedia.org/wiki/JR九州キハ183系気動車 | `20260721_08_asoboy3`, `20260721_09_asoboy4` |
| キハ185系 | fan | https://ja.wikipedia.org/wiki/剣山_(列車) | `20260724_03_tsurugisan6` |
| キハ187系 | fan | https://ja.wikipedia.org/wiki/おき_(列車) | `20260719_03_super_oki5` |
| キハ261系 | fan | https://ja.wikipedia.org/wiki/おおぞら_(列車) | `20260714_01_ozora3`, `20260714_04_ozora12` |
| キハ261系 | fan | https://ja.wikipedia.org/wiki/北斗_(列車) | `20260713_07_hokuto21`, `20260716_07_hokuto20` |
| キハ261系 | fan | https://ja.wikipedia.org/wiki/宗谷_(列車) | `20260715_01_soya`, `20260715_02_soya` |
| 三菱重工 濱海巡航列車 | fan | https://zh.wikipedia.org/wiki/澳門輕軌 | `MO-SAMPLE-MLM-TAIPA` |
| 桃園機場捷運 直達車電聯車（201～217編組） | fan | https://zh.wikipedia.org/wiki/桃園機場捷運 | `20260802_01_taoyuan_airport_mrt_express_t2_taipei` |
| 西門子高運量電聯車 | fan | https://zh.wikipedia.org/wiki/高雄捷運紅線 | `20260810_01_krtc_red_kaohsiung_gangshan_station`, `20260810_02_krtc_red_gangshan_station_siaogang`, `20260810_03_krtc_red_siaogang_sanduo`, `20260810_04_krtc_red_sanduo_kaisyuan`, `20260810_06_krtc_red_kaisyuan_kaohsiung`, `20260812_01_krtc_red_kaohsiung_zuoying` |

Platforms come from the のりば column of each ride's date-specific JR西日本 おでかけネット train page (`https://timetable.jr-odekake.net/train-timetable/<id>?date=<YYYYMMDD>`, JR時刻表 2026年07/08月号). They were read from the raw page; blank cells stay `null`. Rides filled in this pass:

- `20260703_01_haruka`: 天王寺 18, 大阪 24, 新大阪 1
- `20260704_02_kodama918`: 三島 6, 熱海 7, 小田原 14, 新横浜 2, 品川 21
- `20260704_13_kodama915`: 新横浜 3, 小田原 13, 熱海 6, 三島 5
- `20260705_02_kodama802`: 三島 6, 熱海 7, 小田原 14, 新横浜 2, 品川 21, 東京 17
- `20260708_01_tsurugi17`: 福井 12, 敦賀 12
- `20260708_02_shirasagi2`: 敦賀 34, 米原 7
- `20260708_03_hikari648`: 米原 12, 岐阜羽島 1, 名古屋 14
- `20260708_04_hikari706`: 名古屋 15, 浜松 5, 静岡 5, 三島 6
- `20260709_02_hikari713`: 三島 5, 静岡 6, 浜松 6, 名古屋 16, 京都 14
- `20260709_03_miyakoji_rapid`: 京都 10
- `20260709_04_d_section_rapid`: 京都 10
- `20260710_01_nozomi252`: 京都 11, 名古屋 14
- `20260711_03_hakutaka560`: 金沢 12, 富山 12, 上越妙高 12, 飯山 11, 長野 13, 高崎 14, 大宮 13
- `20260713_02_kodama801`: 東京 19, 品川 23, 新横浜 4, 小田原 13, 熱海 6, 三島 5
- `20260713_05_kodama816`: 三島 6, 熱海 7, 小田原 14, 新横浜 2, 品川 21, 東京 14
- `20260718_08_kodama839`: 東京 17, 品川 24, 新横浜 3, 小田原 13, 熱海 6, 三島 5
- `20260718_11_hikari659`: 三島 5, 静岡 6, 浜松 6, 名古屋 16
- `20260719_01_hikari703`: 名古屋 16, 京都 14, 新大阪 21, 新神戸 1, 西明石 11, 姫路 12, 相生 11, 岡山 21
- `20260719_02_yakumo11`: 岡山 2, 米子 2
- `20260719_03_super_oki5`: 米子 2, 益田 1, 山口 1, 新山口 2
- `20260720_44_sanyo_local_shininokuchi_hiroshima`: 広島 5
- `20260720_45_sakura753_hiroshima_hakata`: 広島 11, 徳山 7, 小倉 12, 博多 15
- `20260721_07_sakura749`: 久留米 12, 熊本 13
- `20260721_14_sakura767`: 熊本 13, 鹿児島中央 14
- `20260723_02_shiokaze5`: 岡山 6
- `20260729_05_sunrise_izumo`: 静岡 4, 浜松 4, 姫路 8, 岡山 8, 米子 2
- `20260730_04_sakura762`: 岡山 23, 新大阪 20

Left empty with candidates. Either several types run the service, or the train could not be identified. Candidates with no cited page are unverified.

- `20260703_01_haruka`: 271系 / 281系
- `20260704_03_keikyu_asakusa_line`: 京急1000形 / 京急600形 / 都営5500形 / 5300形 / 北総7500形 / 京成3000形 etc.
- `20260704_04_oedo_line`: 12-000形 / 12-600形
- `20260704_05_mita_line`: 都営6500形 / 東急3000/5080系 / 相鉄20000系/21000系
- `20260704_06_marunouchi_line`: 2000系
- `20260704_07_saikyo_line`: E233系 / 東京臨海高速鉄道70-000形
- `20260704_08_shonan_shinjuku_line`: E231系 / E233系
- `20260704_09_negishi_line`: E233系 — 根岸線は京浜東北線E233系1000番台と横浜線直通E233系6000番台が共に運転
- `20260704_10_minatomirai_line`: Y500系 / 東急5050系 / 東京メトロ10000/17000系 / 西武40000系 / 東武50070系
- `20260705_04_chuo_sobu_line`: E231系 / E231系
- `20260705_05_yurakucho_line`: 東京メトロ10000系 / 17000系 / 西武 / 東急 / 東武直通車
- `20260705_06_yurakucho_line`: 東京メトロ10000系 / 17000系 / 西武 / 東急 / 東武直通車
- `20260705_08_hayabusa59`: E5系 / H5系
- `20260706_01_hayabusa11`: E5系 / H5系
- `20260707_02_hakutaka555`: E7系 / W7系
- `20260707_07_hakutaka565`: E7系 / W7系
- `20260708_01_tsurugi17`: E7系 / W7系
- `20260708_02_shirasagi2`: 681系 / 683系
- `20260710_06_yamabiko221`: E5系 / E2系
- `20260711_02_kagayaki501`: E7系 / W7系
- `20260711_03_hakutaka560`: E7系 / W7系
- `20260711_04_saikyo_local`: E233系 / 東京臨海高速鉄道70-000形
- `20260711_05_seibu_ikebukuro_semiexp`: 各系列混在 (2000/6000/9000/20000/30000/40000/新101系)
- `20260711_06_seibu_sayama_local`: 各系列混在 (2000/6000/9000/20000/30000/40000/新101系)
- `20260712_01_musashino_local`: E231系 / 209系
- `20260712_02_seibu_ikebukuro_semiexp`: 各系列混在 (2000/6000/9000/20000/30000/40000/新101系)
- `20260712_03_seibu_sayama_local`: 各系列混在 (2000/6000/9000/20000/30000/40000/新101系)
- `20260712_04_seibu_sayama_ikebukuro_local`: 各系列混在 (2000/6000/9000/20000/30000/40000/新101系)
- `20260712_05_musashino_local`: E231系 / 209系
- `20260713_06_hayabusa27`: E5系 / H5系
- `20260716_03_sapporo_streetcar_nakajimakoendori_susukino`: A1200形 / A1100形 / 3300形 / 8500形 / 8600形 / M100形 / 300形/350形ほか
- `20260716_04_sapporo_streetcar_susukino_chuokuyakushomae`: A1200形 / A1100形 / 3300形 / 8500形 / 8600形 / M100形 / 300形/350形ほか
- `20260717_01_hakodate_tram`: 500形 / 700形 / 800形 / 3000形 / 8000形 / 9600形 / 30形 / ほか
- `20260717_02_hakodate_tram`: 500形 / 700形 / 800形 / 3000形 / 8000形 / 9600形 / 30形 / ほか
- `20260718_02_hayabusa10`: E5系 / H5系
- `20260718_03_hayabusa95`: E5系 / H5系
- `20260718_06_hayabusa`: E5系 / H5系
- `20260718_07_yamabiko`: E5系 / E2系
- `20260720_41_hiroden1_hiroshimaeki_fukuromachi`: 5000形 / 3900形 / 3800形 / 3700形 / 1000形 / 700形ほか
- `20260720_43_hiroden2_kamiyachonishi_shokocenter`: 5000形 / 3900形 / 3800形 / 3700形 / 1000形 / 700形ほか
- `20260720_46_tsubame325_hakata_shintosu`: 800系 / N700系
- `20260720_47_midori35_shintosu_arita`: 783系 / 787系 / 885系
- `20260720_48_mr627d_arita_imari`: MR-600形 / MR-200形
- `20260720_49_mr369d_imari_tabirahiradoguchi`: MR-600形 / MR-200形
- `20260720_50_mr_tabirahiradoguchi_sasebo`: MR-600形 / MR-200形
- `20260721_01_nagasaki_tram3_nagasakieki_heiwakoen`: 3000形 / 1200形 / 2000形 / 5000形 / 6000形ほか
- `20260721_02_nagasaki_tram3_urakamieki_nagasakieki`: 3000形 / 1200形 / 2000形 / 5000形 / 6000形ほか
- `20260721_03_nagasaki_tram1_nagasakieki_dejima`: 3000形 / 1200形 / 2000形 / 5000形 / 6000形ほか
- `20260721_04_nagasaki_tram1_dejima_nagasakieki`: 3000形 / 1200形 / 2000形 / 5000形 / 6000形ほか
- `20260721_06_relay_kamome22`: 787系 / 885系
- `20260721_10_kumamoto_tram_a_kumamotoeki_karashimacho`: 9700形 / 9200形 / 0800形 / 1200形 / 8500形ほか
- `20260721_11_kumamoto_tram_karashimacho_suidocho`: 9700形 / 9200形 / 0800形 / 1200形 / 8500形ほか
- `20260722_03a_kagoshima_tram_kagoshimachuoeki_miyakodori`: 7000形 / 7500形 / 1000形 / 2100形 / 9500形ほか
- `20260722_06_sonic44`: 883系 / 885系
- `20260722_07_kirameki6`: 787系 / 885系 / 783系
- `20260722_09_chikuho_electric_kurosaki_nogata`: 2000形 / 3000形 / 5000形
- `20260722_10_heichiku_ita_nogata_tagawaita`: 400形 / 500形 / 300形ほか
- `20260723_02_shiokaze5`: 8000系 / 8600系
- `20260723_03_ishizuchi10`: 8000系 / 8600系
- `20260724_01_ishizuchi9`: 8000系 / 8600系
- `20260724_08_tosaden_south`: 600形 / 200形 / 700形 / 800形 / 2000形ほか
- `20260724_09_tosaden_north`: 600形 / 200形 / 700形 / 800形 / 2000形ほか
- `20260726_07_odoriko`: E257系 — 列車が特定できず（記録時刻に合う踊り子が見つからない）
- `20260726_09_shonan_shinjuku_yokohama`: E231系 / E233系
- `20260727_04_nasuno259`: E2系 / E5系 / E6系 / E8系
- `20260728_03_entetsu_sukenobu`: 1000形 / 2000形
- `20260728_04_entetsu_return`: 1000形 / 2000形
- `20260730_01_ichibata_taisha`: 1000系 / 5000系 / 7000系
- `20260730_02_ichibata_kitamatsue`: 1000系 / 5000系 / 7000系
- `20260730_07_nankai_sakai`: 1000系 / 2000系 / 6000系 / 7000系 / 8000系 / 9000系 / 12000系ほか
- `20260731_01_nankai_shinimamiya`: 1000系 / 2000系 / 6000系 / 7000系 / 8000系 / 9000系 / 12000系ほか
- `20260802_02_trtc_bl_taipei_main_ximen`: C321型 / C341型
- `20260802_03_trtc_bl_ximen_zhongxiao_fuxing`: C321型 / C341型
- `20260802_04_trtc_bl_zhongxiao_fuxing_ximen`: C321型 / C341型
- `20260805_02_tra_local_3262_xinwuri_taichung`: EMU800型 / EMU900型 / EMU700型 / EMU600型 / EMU500型
- `20260806_02_tra_local_2204_changhua_taichung`: EMU800型 / EMU900型 / EMU700型 / EMU600型 / EMU500型
- `20260808_02_alsr_5_chiayi_alishan`: 阿里山林鐵 柴油機車(多型)
- `20260808_03_alsr_120_alishan_shenmu`: 阿里山林鐵 柴油機車(多型)
- `20260808_04_alsr_121_shenmu_alishan`: 阿里山林鐵 柴油機車(多型)
- `20260809_01_alsr_8_alishan_chiayi`: 阿里山林鐵 柴油機車(多型)
- `20260809_02_alsr_zhushan_observation_alishan_zhushan`: 阿里山林鐵 柴油機車(多型)
- `20260809_03_alsr_zhushan_observation_zhushan_alishan`: 阿里山林鐵 柴油機車(多型)
- `20260810_05_klrt_c3_counterclockwise_loop`: CAF Urbos 3型 / Alstom Citadis 305型
- `20260812_03_tra_local_1208_taipei_keelung`: EMU800型 / EMU900型 / EMU700型 / EMU600型 / EMU500型
- `20260812_04_tra_local_4209_nuannuan_nangang`: EMU800型 / EMU900型 / EMU700型 / EMU600型 / EMU500型
- `20260813_01_star_of_taiwan_round_island_loop`: 10500/10600型客車(電力機車牽引)
- `KR-SAMPLE-GYEONGBUKSEON`: 무궁화호 객차 — 「무궁화호 객차」は車種でなく、機関車・客車形式は未確認
- `new_year_grand_loop_20251231_01`: E233系 / 東京メトロ16000系 / 東京メトロ06系
- `new_year_grand_loop_20251231_02`: E531系 / E231系
- `new_year_grand_loop_20251231_04`: 211系 / E231系 / E233系
- `new_year_grand_loop_20251231_05`: E231系 / E233系
- `new_year_grand_loop_20251231_06`: E233系 / 東京臨海高速鉄道70-000形 / 東京臨海高速鉄道71-000形
- `new_year_grand_loop_20251231_07`: E231系 / 209系
- `new_year_grand_loop_20251231_10`: E231系 / E233系
- `new_year_grand_loop_20251231_13`: E127系 / 205系
- `new_year_grand_loop_20251231_14`: E127系 / 205系
- `new_year_grand_loop_20251231_15`: E231系 / E233系
- `new_year_grand_loop_20251231_16`: E235系
- `new_year_grand_loop_20251231_19`: E231系 / E231系 / 209系
- `new_year_grand_loop_20251231_20`: E233系 / 東京臨海高速鉄道70-000形 / 東京臨海高速鉄道71-000形
- `new_year_grand_loop_20251231_22`: E231系 / E231系 / 209系
- `new_year_grand_loop_20260101_24`: 209系 / E235系 / E233系
- `new_year_grand_loop_20260101_25`: 209系 / 209系 / E131系
- `new_year_grand_loop_20260101_26`: 209系 — 総武本線 千葉以東の普通は209系とE131系が共に運用
- `new_year_grand_loop_20260101_27`: 209系 / E233系
- `new_year_grand_loop_20260101_28`: 209系 / E233系
- `new_year_grand_loop_20260101_29`: E131系 / 209系
- `new_year_grand_loop_20260101_30`: E131系 — 内房線 木更津以南はE131系が主力だが専用とは確認できず
- `new_year_grand_loop_20260101_31`: E131系 / E233系 / 209系
- `new_year_grand_loop_20260101_32`: E233系 / 209系
- `new_year_grand_loop_20260101_35`: E233系 / E235系
- `new_year_grand_loop_20260101_38`: E231系 / E531系
- `new_year_grand_loop_20260101_39`: E233系 / 東京メトロ16000系
- `tokyo_limited_express_loop_20260529_02`: 209系 / E233系
- `tokyo_limited_express_loop_20260529_06`: E231系 / E233系
- `tokyo_limited_express_loop_20260529_11`: E231系 / 209系
- `tokyo_limited_express_loop_20260529_12`: E233系 / 東京臨海高速鉄道70-000形
- `tokyo_limited_express_loop_20260529_13`: E657系 / E257系

## Ride id map

| Old id | Store | Ride id in the bundled store |
|---|---|---|
| `20260703_01_haruka` | `train-store.json` | `journey_A9554752F257CDA52831A6C0EED248AF` |
| `20260703_02_tokaido_shinkansen_hikari_kodama` | `train-store.json` | `journey_923A26BB27C37BDF1717F1E4F21D5AF2` |
| `20260703_03_tokaido_main_local` | `train-store.json` | `journey_A3CFCBD90A222CC4066ACAF20A6C06C2` |
| `20260704_01_local` | `train-store.json` | `journey_D7889CA9349256238A038E0045DE7D0D` |
| `20260704_02_kodama918` | `train-store.json` | `journey_4CB9E326EEC18D85989CEF90ACF970A1` |
| `20260704_03_keikyu_asakusa_line` | `train-store.json` | `journey_9EBA4C59A5675EBCE17BEBAC846CF2CA` |
| `20260704_04_oedo_line` | `train-store.json` | `journey_C07243F8AADDB594384BBF1CC16C13EA` |
| `20260704_05_mita_line` | `train-store.json` | `journey_5C3BA9F2C1A8F58936EC22D01F4E22E2` |
| `20260704_06_marunouchi_line` | `train-store.json` | `journey_09AC64CFCEE12C93E83510873DD6FEC1` |
| `20260704_07_saikyo_line` | `train-store.json` | `journey_EAACE466C535944D58A31E97A124CF0C` |
| `20260704_08_shonan_shinjuku_line` | `train-store.json` | `journey_F3AE731354D1EAA0C06B45E04BE9F302` |
| `20260704_09_negishi_line` | `train-store.json` | `journey_9F1B97EDB6DCD7A4DB1908060F60E180` |
| `20260704_10_minatomirai_line` | `train-store.json` | `journey_2840A4D4E48F45ECA2F36BE4ED5C5E2A` |
| `20260704_11_keihin_tohoku_line` | `train-store.json` | `journey_595FE5006ED23F7B331795A1C3A877E9` |
| `20260704_12_yokohama_line` | `train-store.json` | `journey_1BF192064CE880673A0BB314C77436DB` |
| `20260704_13_kodama915` | `train-store.json` | `journey_5DDC220B564315ABDE363017D45930D6` |
| `20260704_14_local` | `train-store.json` | `journey_A6980FF0C00F952ADEA44DB6724A69A7` |
| `20260705_01_local` | `train-store.json` | `journey_45B9E5DDA1ACD772D91C5332674B66F6` |
| `20260705_02_kodama802` | `train-store.json` | `journey_7ED510CE68E0BE81303D118A1B9E3575` |
| `20260705_03_chuo_line` | `train-store.json` | `journey_DAE47A568594FC62E600A5F695EB7365` |
| `20260705_04_chuo_sobu_line` | `train-store.json` | `journey_588AB2A1A40723D13732520638875B90` |
| `20260705_05_yurakucho_line` | `train-store.json` | `journey_B6AC22131D2441B90E2E47880C035680` |
| `20260705_06_yurakucho_line` | `train-store.json` | `journey_A6900040ECB7DC73804CD885E0C55A77` |
| `20260705_07_yamanote_line` | `train-store.json` | `journey_2421C1DE7244064D1E03E50A9E4A1707` |
| `20260705_08_hayabusa59` | `train-store.json` | `journey_5D02E4142B00032F153A4A2DF85B955D` |
| `20260706_01_hayabusa11` | `train-store.json` | `journey_E7BA8AD080B2F29F785AC451F915075F` |
| `20260706_02_super_tsugaru2` | `train-store.json` | `journey_290DDF7BAF84271A16574A1D9669181F` |
| `20260706_03_inaho14` | `train-store.json` | `journey_03F366E23A32B262DDDA6774510A20D4` |
| `20260707_01_toki308` | `train-store.json` | `journey_F977C83D37F1F33106F63344B048477F` |
| `20260707_02_hakutaka555` | `train-store.json` | `journey_B3210B8E26A09DDE4055CBC06E62E202` |
| `20260707_03_local` | `train-store.json` | `journey_AD986EA2AE199842C86F1FE0C72C1F98` |
| `20260707_04_local` | `train-store.json` | `journey_410D06F4D03FC76877879DC916484BBC` |
| `20260707_05_local` | `train-store.json` | `journey_5214DDD3F5A2C014BA41D682C8847138` |
| `20260707_06_a_ltdexp` | `train-store.json` | `journey_3741AFAFFD9A67394E057294ACF48B00` |
| `20260707_07_hakutaka565` | `train-store.json` | `journey_55DB5F0FE70F752721E67BA029168A20` |
| `20260708_01_tsurugi17` | `train-store.json` | `journey_74236A39F500AA7027A8F519567B952B` |
| `20260708_02_shirasagi2` | `train-store.json` | `journey_65F43AE4739DB31208BF9295B6539472` |
| `20260708_03_hikari648` | `train-store.json` | `journey_F57EA63347F47F36D98DF654CBAFDA69` |
| `20260708_04_hikari706` | `train-store.json` | `journey_FB79023EBDF3D810C09FBCE322F2B679` |
| `20260708_05_local` | `train-store.json` | `journey_059D25F92EEAD0E27416DA75021EFBB2` |
| `20260709_01_local` | `train-store.json` | `journey_DC682B71ACE23212D62D87D4C371A5E1` |
| `20260709_02_hikari713` | `train-store.json` | `journey_E60A7D258F854777D4460EDFE961AE32` |
| `20260709_03_miyakoji_rapid` | `train-store.json` | `journey_80163C1B9EDB32F4644B6CED30B291F5` |
| `20260709_04_d_section_rapid` | `train-store.json` | `journey_2C4B34CD53F9E78ECA8875BC1ABCD617` |
| `20260710_01_nozomi252` | `train-store.json` | `journey_0488BA679E26E3DF7B20C50B61F5242A` |
| `20260710_02_kodama824` | `train-store.json` | `journey_D04B2C63CEA86422F386166CABE2A3FB` |
| `20260710_03_local` | `train-store.json` | `journey_E0ABE3D84C386F12C84C5EBB53E9DB42` |
| `20260710_04_local` | `train-store.json` | `journey_552CE7006F50D9DD20F7EFB7B0B91BA8` |
| `20260710_05_hikari718` | `train-store.json` | `journey_1CB70EB6BDEE3E624E5E990D2B1C00FB` |
| `20260710_06_yamabiko221` | `train-store.json` | `journey_FD6353765B0036EFBE30A6B9D31CE9D3` |
| `20260710_07_keihin_tohoku_local` | `train-store.json` | `journey_6C38BB258FF7BBA93CB1A6C6284BC9C4` |
| `20260711_01_keihin_tohoku_negishi_local` | `train-store.json` | `journey_5DD4E6CA03675E3FA6AC32063B33E078` |
| `20260711_02_kagayaki501` | `train-store.json` | `journey_1EAE35C4A37558CFA7DD681330411832` |
| `20260711_03_hakutaka560` | `train-store.json` | `journey_7A3B8940A7731646F2E0DB38A8C89C21` |
| `20260711_04_saikyo_local` | `train-store.json` | `journey_0F013B23352B2D55E622E87E2E8E1DB4` |
| `20260711_05_seibu_ikebukuro_semiexp` | `train-store.json` | `journey_8AD20CEBC2F4E010D786EA9CEE066ABE` |
| `20260711_06_seibu_sayama_local` | `train-store.json` | `journey_37EBEBB6809CFBA2C08E96855F63306A` |
| `20260712_01_musashino_local` | `train-store.json` | `journey_99AFD75780558F89BFB7FC505A282831` |
| `20260712_02_seibu_ikebukuro_semiexp` | `train-store.json` | `journey_F9ABBBD9EF93833A99D5F678570D5898` |
| `20260712_03_seibu_sayama_local` | `train-store.json` | `journey_025A9A2E73804710C0A0544D46DA840F` |
| `20260712_04_seibu_sayama_ikebukuro_local` | `train-store.json` | `journey_3D6CBC5295CE31F009A715F0A483EDF5` |
| `20260712_05_musashino_local` | `train-store.json` | `journey_578784BBC21BEB37C6BCDB3F75623287` |
| `20260713_01_keihin_tohoku_negishi_local` | `train-store.json` | `journey_AEDF22100651041F822E1DFD54EC4653` |
| `20260713_02_kodama801` | `train-store.json` | `journey_D67EA61A2C641A02967314209A67C0A5` |
| `20260713_03_tokaido_main_local` | `train-store.json` | `journey_660F1956DE6A9A62DB219B218967D58C` |
| `20260713_04_tokaido_main_local` | `train-store.json` | `journey_10CEA8306C1111A9244968C8560B886D` |
| `20260713_05_kodama816` | `train-store.json` | `journey_5515D04C2ECC7C28FC099F7E25093E2D` |
| `20260713_06_hayabusa27` | `train-store.json` | `journey_4DBADC9CC0B33FDC9F5E0DA527EC5AA0` |
| `20260713_07_hokuto21` | `train-store.json` | `journey_7FDB2E2A33B27404C1C8198B3C2B29F8` |
| `20260714_01_ozora3` | `train-store.json` | `journey_43D90DF84B5E40D6304EC290E8ED4E74` |
| `20260714_02_nemuro_main_local` | `train-store.json` | `journey_318CA3E19DF94AF4005322F937025412` |
| `20260714_03_nemuro_main_local` | `train-store.json` | `journey_4404D8979CD787663FD77A73C2572D0C` |
| `20260714_04_ozora12` | `train-store.json` | `journey_F6F27BD3CBEFAA23FC0956F049DED550` |
| `20260715_01_soya` | `train-store.json` | `journey_32E525B07148EE19DC4F3B99A36535ED` |
| `20260715_02_soya` | `train-store.json` | `journey_10F4EC2286758F85D709118AAFA6260E` |
| `20260716_01_sapporo_subway_namboku_sapporo_susukino` | `train-store.json` | `journey_8B59A27F6F916CAE6A525B4F32488204` |
| `20260716_02_sapporo_subway_namboku_odori_nakajimakoen` | `train-store.json` | `journey_17CC2EDF6C8FBBE0584149B2BADE9D7B` |
| `20260716_03_sapporo_streetcar_nakajimakoendori_susukino` | `train-store.json` | `journey_FF43AD962224E5B60A731748776A27EB` |
| `20260716_04_sapporo_streetcar_susukino_chuokuyakushomae` | `train-store.json` | `journey_5AB6DC7EDCD13272F4DD08F0EEEDDDB5` |
| `20260716_05_sapporo_subway_tozai_nishi11_odori` | `train-store.json` | `journey_97A52E47E661D43859B9236D25ECE603` |
| `20260716_06_sapporo_subway_namboku_odori_sapporo` | `train-store.json` | `journey_B9B2EB9096BA7E1B096FCF563147469F` |
| `20260716_07_hokuto20` | `train-store.json` | `journey_8BADA44ED18197CDFA42A2D89B3028F1` |
| `20260717_01_hakodate_tram` | `train-store.json` | `journey_A51DFF674B84CF19A725723E186BE42B` |
| `20260717_02_hakodate_tram` | `train-store.json` | `journey_0CD36C937D37303F9498C53BF7B42430` |
| `20260718_01_hakodate_liner` | `train-store.json` | `journey_9D02C3A9C9EC22156727EE34EF3EECD9` |
| `20260718_02_hayabusa10` | `train-store.json` | `journey_915349569139B316338DF97618D6F773` |
| `20260718_03_hayabusa95` | `train-store.json` | `journey_024B5864D9989D220DE5C73F0EAE833F` |
| `20260718_04_ou_main_local` | `train-store.json` | `journey_440A0D15C84B56D9F16C5EB444C9E5B1` |
| `20260718_05_ou_main_local` | `train-store.json` | `journey_81234AF32797B453C451E437222D2E60` |
| `20260718_06_hayabusa` | `train-store.json` | `journey_8B77161CDFB6C2A3CCCE5B7C674FF523` |
| `20260718_07_yamabiko` | `train-store.json` | `journey_596792300B91ACEAE52DDC2FF9D11D2E` |
| `20260718_08_kodama839` | `train-store.json` | `journey_969009740BE6241F5DEEE35BD8CAA7BA` |
| `20260718_09_tokaido_main_local` | `train-store.json` | `journey_119A68426CA3EE502CDB96C972B317D4` |
| `20260718_10_tokaido_main_local` | `train-store.json` | `journey_DDD0A86A0B072018582A3CED0998B99D` |
| `20260718_11_hikari659` | `train-store.json` | `journey_9409400F1A9EC5DA6CDB7FFBD64EBE2D` |
| `20260719_01_hikari703` | `train-store.json` | `journey_C60F2E6092D87D9F5F85243B93428D5E` |
| `20260719_02_yakumo11` | `train-store.json` | `journey_9B1957E8CA2CA62A34EEBFC519E64422` |
| `20260719_03_super_oki5` | `train-store.json` | `journey_55E89F3BE5BD16BC06291B252CFFA81B` |
| `20260719_04_sakura770` | `train-store.json` | `journey_CE6CDD905BB6708E69DD82011EB8182B` |
| `20260720_41_hiroden1_hiroshimaeki_fukuromachi` | `train-store.json` | `journey_76C5FA48675C931CCDE2EB71E9A05658` |
| `20260720_42_astram_hondori_johoku` | `train-store.json` | `journey_AEF095A24CF065375213A5A9A0AC163A` |
| `20260720_43_hiroden2_kamiyachonishi_shokocenter` | `train-store.json` | `journey_9F86A38C7DD4FAD1DB6894D4FD0118D1` |
| `20260720_44_sanyo_local_shininokuchi_hiroshima` | `train-store.json` | `journey_4B847D0A569A7FF0DFF0101FF69D5F0A` |
| `20260720_45_sakura753_hiroshima_hakata` | `train-store.json` | `journey_0D198248AFFDB230E7BBFF14146178C0` |
| `20260720_46_tsubame325_hakata_shintosu` | `train-store.json` | `journey_54E586655BBD3609E653BC7290FA2B34` |
| `20260720_47_midori35_shintosu_arita` | `train-store.json` | `journey_06EC08904789EE82E214ED3D28758DE5` |
| `20260720_48_mr627d_arita_imari` | `train-store.json` | `journey_71DD8854E028C292A3A8359556C3866B` |
| `20260720_49_mr369d_imari_tabirahiradoguchi` | `train-store.json` | `journey_082EA2B0A90F678FE1E8D274B729F9D4` |
| `20260720_50_mr_tabirahiradoguchi_sasebo` | `train-store.json` | `journey_B1AB45AE6B8B33C3A8CD8BC12BB07D33` |
| `20260720_51_seasideliner3233d_sasebo_nagasaki` | `train-store.json` | `journey_FC8005E13BA7158E6129934006093962` |
| `20260721_01_nagasaki_tram3_nagasakieki_heiwakoen` | `train-store.json` | `journey_87D92EF0BAE97A00C634BA96DA890A46` |
| `20260721_02_nagasaki_tram3_urakamieki_nagasakieki` | `train-store.json` | `journey_08B980D1C7CB9F6CAD15CD060A45807F` |
| `20260721_03_nagasaki_tram1_nagasakieki_dejima` | `train-store.json` | `journey_AD59A05EAE440ED38AA3279A20557058` |
| `20260721_04_nagasaki_tram1_dejima_nagasakieki` | `train-store.json` | `journey_C9DEC0495C5FAE492C4FE858535C3E30` |
| `20260721_05_kamome22` | `train-store.json` | `journey_33CBB95F33F145A44996E104C7110877` |
| `20260721_06_relay_kamome22` | `train-store.json` | `journey_9E0FE255A29C5BBDEE31480F4AED2BE8` |
| `20260721_07_sakura749` | `train-store.json` | `journey_151F1405ADA1BC7794EB8C44CD7709C2` |
| `20260721_08_asoboy3` | `train-store.json` | `journey_02C494EB5E72DE2FE0D3E5BC7D303309` |
| `20260721_09_asoboy4` | `train-store.json` | `journey_71102CEF82BE99D98F5C7101CD080E07` |
| `20260721_10_kumamoto_tram_a_kumamotoeki_karashimacho` | `train-store.json` | `journey_425FC76FB050394D51554A9A2D6B369B` |
| `20260721_11_kumamoto_tram_karashimacho_suidocho` | `train-store.json` | `journey_8B16C03F0CFAADDD02FD4A3500661E2E` |
| `20260721_12_hohi_local1493m_shinsuizenji_musashizuka` | `train-store.json` | `journey_1100C5554DA23F0F99BBBD8F912CC604` |
| `20260721_13_hohi_local1498m_musashizuka_kumamoto` | `train-store.json` | `journey_3B958DB027F701A9AFD801879294548F` |
| `20260721_14_sakura767` | `train-store.json` | `journey_5E47ABA2FB7E3A6CC5F14CBCC010472D` |
| `20260722_01_ibusuki_1321d_kagoshima_yamakawa` | `train-store.json` | `journey_A18C112CF65FF5C2AD464A2C3309FB24` |
| `20260722_02_ibusuki_5321d_yamakawa_nishioyama` | `train-store.json` | `journey_B96A06031B5BCFDD1064C35D950BFB91` |
| `20260722_03_ibusuki_1326d_nishioyama_minamikagoshima` | `train-store.json` | `journey_F497F768F6A74DE792D14B3DA43949F9` |
| `20260722_03a_kagoshima_tram_kagoshimachuoeki_miyakodori` | `train-store.json` | `journey_FF81EAF940C88B515459211A732AD78C` |
| `20260722_03b_nanohana3328d_minamikagoshima_kagoshima` | `train-store.json` | `journey_61F39B7DCD1B8DFFC6688097802C44C8` |
| `20260722_04_kirishima8` | `train-store.json` | `journey_45E72A351DEC6512AF96B89578A93E9A` |
| `20260722_05_nichirin10` | `train-store.json` | `journey_E9C359F48C7CC40ABC70DBD05B606CFA` |
| `20260722_06_sonic44` | `train-store.json` | `journey_6F379655E47131DD2F854B65A847B9F0` |
| `20260722_07_kirameki6` | `train-store.json` | `journey_31C35A5D2E003443D5E26D7654555B25` |
| `20260722_08_sonic54_kokura_kurosaki` | `train-store.json` | `journey_FEDC12334D0F270D498B929602534FA8` |
| `20260722_09_chikuho_electric_kurosaki_nogata` | `train-store.json` | `journey_4BB3DDFC465CB6E4719AB69741432424` |
| `20260722_10_heichiku_ita_nogata_tagawaita` | `train-store.json` | `journey_FA2577CF26696BE8E3619FBC6FA06440` |
| `20260722_11_hitahikosan_986d_tagawaita_kokura` | `train-store.json` | `journey_7DCFF106FEBEC9FBCFCB4EB3109885B8` |
| `20260722_12_monorail_kokura_kikugaoka` | `train-store.json` | `journey_1B73B253ED48ADAE75E0A27CD5EDD87C` |
| `20260722_13_monorail_kikugaoka_kokura` | `train-store.json` | `journey_FA664788B3F334B952706589201D498B` |
| `20260723_01_sakura740` | `train-store.json` | `journey_BDD9F936F447CBF04C5075C26DA76C88` |
| `20260723_02_shiokaze5` | `train-store.json` | `journey_CECE2010BC0D2F1EB19C89BFD5900CAD` |
| `20260723_03_ishizuchi10` | `train-store.json` | `journey_BEEF6E99345E6E5CD1F5B4AF369AC636` |
| `20260723_04_kotoku_local_takamatsu_ritsurin` | `train-store.json` | `journey_DFF892AFBEB679C6AA793A67226FF57C` |
| `20260723_05_uzushio10` | `train-store.json` | `journey_771C696806C4705B412A265B953BD9A7` |
| `20260724_01_ishizuchi9` | `train-store.json` | `journey_07E6AD25D8057D28D08088C1D40C2491` |
| `20260724_02_nanpu9` | `train-store.json` | `journey_2A4BA95A7B92CB19921B27A2D3279C34` |
| `20260724_03_tsurugisan6` | `train-store.json` | `journey_510175D3C325909EF4C88C3A42E1108B` |
| `20260724_04_tokushima_local_463d` | `train-store.json` | `journey_7607A5FC50F4ABA60EDB87451A5E0724` |
| `20260724_05_nanpu17` | `train-store.json` | `journey_D2D514AAEA06253635D51310E9C4C06B` |
| `20260724_06_nanpu28` | `train-store.json` | `journey_6322F5578A2F139890D3B028ADDAF45A` |
| `20260724_07_kodama970` | `train-store.json` | `journey_FBC327CBC341BD103BEEAE00FD568C91` |
| `20260724_08_tosaden_south` | `train-store.json` | `journey_350E1BD8273A1E04690813FB31BF720C` |
| `20260724_09_tosaden_north` | `train-store.json` | `journey_0694D992D0F11AE81676A5DCDFBFD38D` |
| `20260725_05_hikari706` | `train-store.json` | `journey_C163CF0702200718E5E57A2BE6C21885` |
| `20260725_06_local` | `train-store.json` | `journey_E98005859D36F61CDF6C0BEDE09A3258` |
| `20260726_01_local_numazu` | `train-store.json` | `journey_8888515C58457DCC681836C3325CE638` |
| `20260726_02_local_mishima` | `train-store.json` | `journey_DEA753DDFBC0519639A0FECAA3242CC5` |
| `20260726_03_hikari706` | `train-store.json` | `journey_CD24799CE25B1CF61107969F8A30406F` |
| `20260726_04_chuo_rapid_shinjuku` | `train-store.json` | `journey_C03AE74555ED48DBCCA3989A84157CB7` |
| `20260726_05_chuo_rapid_tokyo` | `train-store.json` | `journey_10321A2FDEF5906E4DCE8DB6986E3C03` |
| `20260726_06_kodama_atami` | `train-store.json` | `journey_029F2E79178CF1AA008FB454C06992F7` |
| `20260726_07_odoriko` | `train-store.json` | `journey_1C77A10398A5B717F5372522CD764D5F` |
| `20260726_08_chuo_rapid_shinjuku2` | `train-store.json` | `journey_1F9D3D61F6C18F4BC2B202DC16B92231` |
| `20260726_09_shonan_shinjuku_yokohama` | `train-store.json` | `journey_856C6D19621F1681AAF99048FEEAED8D` |
| `20260727_01_tokaido_through_numazu` | `train-store.json` | `journey_583C80C04E9545A24F3711263868E484` |
| `20260727_02_local_mishima` | `train-store.json` | `journey_2445827DCEE24FDDD9BDAFF031574BF8` |
| `20260727_03_hikari702` | `train-store.json` | `journey_2634C4C2410DA151187D68ACC14F1201` |
| `20260727_04_nasuno259` | `train-store.json` | `journey_A83E8C0CD3219DDE9BDACE75633FE06B` |
| `20260727_05_komachi` | `train-store.json` | `journey_8468CDB2F92CD8F1CB56D7175B261C34` |
| `20260727_06_local_akihabara` | `train-store.json` | `journey_5AB68AB4738C250255A82B17A485CD8E` |
| `20260727_07_local_tokyo` | `train-store.json` | `journey_DD359818F2CA9B303F5EF5A05FCDA15D` |
| `20260727_08_narita_express` | `train-store.json` | `journey_680A26B9C2D06FDE49DABFF6A02DF17C` |
| `20260727_09_kodama837` | `train-store.json` | `journey_21B9459DC7DFD29026EE0E54B15BF121` |
| `20260727_10_local_numazu` | `train-store.json` | `journey_072BD550CC395E21A18FADA5A4255413` |
| `20260728_01_local_mishima` | `train-store.json` | `journey_A50D14E9010F9184B45D3BD166A7488C` |
| `20260728_02_kodama829` | `train-store.json` | `journey_A4B7BCFE572DCF976943553B301BBF51` |
| `20260728_03_entetsu_sukenobu` | `train-store.json` | `journey_7296C07F3881D0CAAF2DE8828D443471` |
| `20260728_04_entetsu_return` | `train-store.json` | `journey_323ADE1BA38D637024FE37B30449D56E` |
| `20260728_05_kodama834` | `train-store.json` | `journey_D34CC990A1B67E5BE0BA9D9730CA6916` |
| `20260728_06_local_numazu` | `train-store.json` | `journey_FD2B8C351E5D802CF873225C04133FB4` |
| `20260729_01_local_mishima` | `train-store.json` | `journey_1539FA6CAEDB8148D507E34ED7D4D897` |
| `20260729_02_kodama840` | `train-store.json` | `journey_96B2EFFD4EC25479AFA91263963111A2` |
| `20260729_03_kodama911` | `train-store.json` | `journey_8C70A9CF2CB598C4C2ABDA2EAABCE0F5` |
| `20260729_04_local_numazu` | `train-store.json` | `journey_C1F3524AE95815918C6C76DA80E813CD` |
| `20260729_05_sunrise_izumo` | `train-store.json` | `journey_F29762068C2DDB4CD79CF4AF30B29529` |
| `20260730_01_ichibata_taisha` | `train-store.json` | `journey_E97B57247FA4FAF2AD7C092FA6C78A0E` |
| `20260730_02_ichibata_kitamatsue` | `train-store.json` | `journey_1066A578B168E8867C0C2526F4C4918A` |
| `20260730_03_yakumo22` | `train-store.json` | `journey_BB3AD8FEF0D118561F7FC4FA6227A5A6` |
| `20260730_04_sakura762` | `train-store.json` | `journey_20A4F24136AEE7B83D1AD4A267C4DE85` |
| `20260730_05_shinkaisoku_osaka` | `train-store.json` | `journey_42081FC544A1354AECB52C9720DA202D` |
| `20260730_06_osaka_loop` | `train-store.json` | `journey_475F1E0ED575D680352459093F852ED6` |
| `20260730_07_nankai_sakai` | `train-store.json` | `journey_95838C76BAA5FDF356AC92F8B54F802F` |
| `20260731_01_nankai_shinimamiya` | `train-store.json` | `journey_C409454EC8F3724E2ECD7CD942A27B3D` |
| `20260731_02_rapit_alpha3` | `train-store.json` | `journey_0DCC26B17610DE9969C200D26CBA75DE` |
| `20260731_03_yui_naha_akamine` | `train-store.json` | `journey_A04D207B2E4D8CA4B9088FA6DF5BDD29` |
| `20260731_04_yui_akamine_naha` | `train-store.json` | `journey_959DFFAA45FED199E0FD06F93A12C93B` |
| `20260731_05_yui_tedako_shuri` | `train-store.json` | `journey_EE957F00F2B8D8D291D4CD7EB1826810` |
| `20260731_06_yui_shuri_miebashi` | `train-store.json` | `journey_3A264FF820AE17659ADDD22FDDADB270` |
| `20260731_07_yui_miebashi_naha` | `train-store.json` | `journey_B29C2B434D4A5E393447665740312185` |
| `20260731_08_yui_naha_miebashi` | `train-store.json` | `journey_311418DF2394CCFFF6AA3C0151F0CB10` |
| `20260801_01_yui_miebashi_naha` | `train-store.json` | `journey_2DB618BA4041AF100A4FB6C47DA4B27C` |
| `20260802_01_taoyuan_airport_mrt_express_t2_taipei` | `train-store-tw.json` | `journey_5C3C741549CF09E20FE4CC4F7389B758` |
| `20260802_02_trtc_bl_taipei_main_ximen` | `train-store-tw.json` | `journey_48FE139478368C9C7274289E1D49510A` |
| `20260802_03_trtc_bl_ximen_zhongxiao_fuxing` | `train-store-tw.json` | `journey_7F9FEBF55983F06E943C4BF21837CD2E` |
| `20260802_04_trtc_bl_zhongxiao_fuxing_ximen` | `train-store-tw.json` | `journey_B34C34D4052B67C1D1F2468F4B8826A4` |
| `20260805_01_thsr_165_taipei_taichung` | `train-store-tw.json` | `journey_E2BA1597EB6DEA75FB126926E564D6CD` |
| `20260805_02_tra_local_3262_xinwuri_taichung` | `train-store-tw.json` | `journey_253013612D5701BF5895AD9C0FC1A850` |
| `20260806_01_tra_tze_chiang_3000_137_taichung_changhua` | `train-store-tw.json` | `journey_0A8EC92F75B878119658D0752A71E41F` |
| `20260806_02_tra_local_2204_changhua_taichung` | `train-store-tw.json` | `journey_85C2F9F935C9A4701208C881737C7ADC` |
| `20260808_01_tra_tze_chiang_3000_191_taichung_chiayi` | `train-store-tw.json` | `journey_D902105FFF79F2BC91DD69001C1D1752` |
| `20260808_02_alsr_5_chiayi_alishan` | `train-store-tw.json` | `journey_D6E210E0D14743B7AFE4EF6855ADC7FA` |
| `20260808_03_alsr_120_alishan_shenmu` | `train-store-tw.json` | `journey_214DEC1A58D8A2E683D5E17A47BFCE7F` |
| `20260808_04_alsr_121_shenmu_alishan` | `train-store-tw.json` | `journey_5BADD88C12380B6A886444FB69041F7F` |
| `20260809_02_alsr_zhushan_observation_alishan_zhushan` | `train-store-tw.json` | `journey_E12389096A2B7F909034258E902F941E` |
| `20260809_03_alsr_zhushan_observation_zhushan_alishan` | `train-store-tw.json` | `journey_DFA582684EEDC99182E6D448F71607F7` |
| `20260809_01_alsr_8_alishan_chiayi` | `train-store-tw.json` | `journey_D4687FB43F9C1C43E0B0E40017AC9EDC` |
| `20260809_04_tra_tze_chiang_3000_125_chiayi_kaohsiung` | `train-store-tw.json` | `journey_CEB49C47CA401AD978BFE56F3D55F4C7` |
| `20260810_01_krtc_red_kaohsiung_gangshan_station` | `train-store-tw.json` | `journey_2FDE3816A557FFFB50406D18A131A336` |
| `20260810_02_krtc_red_gangshan_station_siaogang` | `train-store-tw.json` | `journey_F889D3193B98C1B436F80571170668AA` |
| `20260810_03_krtc_red_siaogang_sanduo` | `train-store-tw.json` | `journey_927016E22113A45080FBC58092D28EB0` |
| `20260810_04_krtc_red_sanduo_kaisyuan` | `train-store-tw.json` | `journey_10253133B7525E17509D09650522E725` |
| `20260810_05_klrt_c3_counterclockwise_loop` | `train-store-tw.json` | `journey_0960494E1EEF4CBDB6B1E4B1FE90BEB7` |
| `20260810_06_krtc_red_kaisyuan_kaohsiung` | `train-store-tw.json` | `journey_392AB4A925F885DE6CD17FA95C36040E` |
| `20260812_01_krtc_red_kaohsiung_zuoying` | `train-store-tw.json` | `journey_BCCC18D524113D54156C5874685CEE29` |
| `20260812_02_thsr_826_zuoying_taipei` | `train-store-tw.json` | `journey_4D389948FB54DDE74017B2CCFC5B526D` |
| `20260812_03_tra_local_1208_taipei_keelung` | `train-store-tw.json` | `journey_701B2439EE7B2E05AF11E637D13B1CB5` |
| `20260812_04_tra_local_4209_nuannuan_nangang` | `train-store-tw.json` | `journey_06535A45062A8500166100F9B37C31F1` |
| `20260812_05_thsr_161_nangang_taipei` | `train-store-tw.json` | `journey_5A3C1D43A8E70734A5D5DA40D6D39099` |
| `20260813_01_star_of_taiwan_round_island_loop` | `train-store-tw.json` | `journey_C929D1DB4BBEDD1ED71B9C4885026D78` |
| `HK-SAMPLE-EAL-LOW` | `train-store-hk.json` | `journey_E432976CF3960943D65E32F615830502` |
| `KR-SAMPLE-GYEONGBUKSEON` | `train-store-kr.json` | `journey_B7F582C16E904392DA2C9CE339DF6780` |
| `MO-SAMPLE-MLM-TAIPA` | `train-store-mo.json` | `journey_E155548B9C8291DA928D5426A9D0134B` |
| `new_year_grand_loop_20251231_01` | `new-year-grand-loop.json` | `journey_7866E65358DB80921D2614D5398FEEE1` |
| `new_year_grand_loop_20251231_02` | `new-year-grand-loop.json` | `journey_B9F7AF6F378531D710C6C4DB8A75FE84` |
| `new_year_grand_loop_20251231_03` | `new-year-grand-loop.json` | `journey_1F114EC77ED45EB89D68F1C32934755E` |
| `new_year_grand_loop_20251231_04` | `new-year-grand-loop.json` | `journey_5FAF02A78D0297BD7E6BC7189EEE5479` |
| `new_year_grand_loop_20251231_05` | `new-year-grand-loop.json` | `journey_8B370FD51DD05BF218108C28B207147C` |
| `new_year_grand_loop_20251231_06` | `new-year-grand-loop.json` | `journey_C83F01E4FC0FB070B439E1F554DDB2E3` |
| `new_year_grand_loop_20251231_07` | `new-year-grand-loop.json` | `journey_19E72EF8A279F9BEA3E43507CFD262B8` |
| `new_year_grand_loop_20251231_08` | `new-year-grand-loop.json` | `journey_B1081E3920E5817960D57445107E8518` |
| `new_year_grand_loop_20251231_09` | `new-year-grand-loop.json` | `journey_1C50841EDDE0B8259BF3CD6982B04968` |
| `new_year_grand_loop_20251231_10` | `new-year-grand-loop.json` | `journey_DC35D009289BDAA8CE95542D519A2D3C` |
| `new_year_grand_loop_20251231_11` | `new-year-grand-loop.json` | `journey_4DCB77A37D44B9E2340421841026E845` |
| `new_year_grand_loop_20251231_12` | `new-year-grand-loop.json` | `journey_73881D4AC6CDEB95F29753E8F861455B` |
| `new_year_grand_loop_20251231_13` | `new-year-grand-loop.json` | `journey_E5271380AA0BE6E27DCB2F8E8D465275` |
| `new_year_grand_loop_20251231_14` | `new-year-grand-loop.json` | `journey_5A7792A36B7AFBF89C4188A3AF6AB319` |
| `new_year_grand_loop_20251231_15` | `new-year-grand-loop.json` | `journey_74A2A9A828B6C4EA8C9EA2D4ACB5E5B1` |
| `new_year_grand_loop_20251231_16` | `new-year-grand-loop.json` | `journey_38D81E63FDF3CA29C2E2058E35C8A761` |
| `new_year_grand_loop_20251231_17` | `new-year-grand-loop.json` | `journey_D9EE58DC654F79D6E5D9B5AD1EE9222F` |
| `new_year_grand_loop_20251231_18` | `new-year-grand-loop.json` | `journey_7E3B5F10D9F6347B6C726AEC1D57BA7A` |
| `new_year_grand_loop_20251231_19` | `new-year-grand-loop.json` | `journey_56503D37265880A94FA191E1A470173B` |
| `new_year_grand_loop_20251231_20` | `new-year-grand-loop.json` | `journey_B39F46D813FA1636ED3CD36C7FA1358D` |
| `new_year_grand_loop_20251231_21` | `new-year-grand-loop.json` | `journey_FD3D0B6540560EA9C1BD526322196797` |
| `new_year_grand_loop_20251231_22` | `new-year-grand-loop.json` | `journey_D878F62C43D5A7C64B14222B73FD4CD0` |
| `new_year_grand_loop_20260101_23` | `new-year-grand-loop.json` | `journey_CBC698EF40ADC4349BF9FE4E96A022BA` |
| `new_year_grand_loop_20260101_24` | `new-year-grand-loop.json` | `journey_B3F161407E8E14E91AF8646028705859` |
| `new_year_grand_loop_20260101_25` | `new-year-grand-loop.json` | `journey_5F1433ABC14572422C3B891B334CCB7E` |
| `new_year_grand_loop_20260101_26` | `new-year-grand-loop.json` | `journey_E3C5A17962C2DDAE1DCC23DDE0AA3C1A` |
| `new_year_grand_loop_20260101_27` | `new-year-grand-loop.json` | `journey_8DFA7F87666D8581074D297024482EF1` |
| `new_year_grand_loop_20260101_28` | `new-year-grand-loop.json` | `journey_813F6AB74D714CCD2B098529CC5D7785` |
| `new_year_grand_loop_20260101_29` | `new-year-grand-loop.json` | `journey_1D251A826357268B527F63C503905C1C` |
| `new_year_grand_loop_20260101_30` | `new-year-grand-loop.json` | `journey_0FEE4DC2B4589497ABD4E35742C65942` |
| `new_year_grand_loop_20260101_31` | `new-year-grand-loop.json` | `journey_F3236E4E4DBC6C24A60FCFF8CF8FD52D` |
| `new_year_grand_loop_20260101_32` | `new-year-grand-loop.json` | `journey_70220CF57D13FED0E93F34B981914A11` |
| `new_year_grand_loop_20260101_33` | `new-year-grand-loop.json` | `journey_07159EDCA041241C5F7038F2DF87F3F4` |
| `new_year_grand_loop_20260101_34` | `new-year-grand-loop.json` | `journey_4D8504078E1EDCDDD6273B29F6C844F1` |
| `new_year_grand_loop_20260101_35` | `new-year-grand-loop.json` | `journey_48A839FEAF8AAB049FE99B5BFEB83C01` |
| `new_year_grand_loop_20260101_36` | `new-year-grand-loop.json` | `journey_92A88D23E58F169A02F66FA4131F9CF4` |
| `new_year_grand_loop_20260101_37` | `new-year-grand-loop.json` | `journey_5D0B999496F4E95DC91A57FB2FACD2BF` |
| `new_year_grand_loop_20260101_38` | `new-year-grand-loop.json` | `journey_FDB4DA52F28136A256951A235E9FF713` |
| `new_year_grand_loop_20260101_39` | `new-year-grand-loop.json` | `journey_EA71B8D43807377F6733B3ECD2AF3A39` |
| `tokyo_limited_express_loop_20260529_01` | `tokyo-limited-express-loop.json` | `journey_FB378E723A1A1C6D845DDBF2F4EC7B80` |
| `tokyo_limited_express_loop_20260529_02` | `tokyo-limited-express-loop.json` | `journey_FCF5080D6BF57735BD6B550726AEBCC2` |
| `tokyo_limited_express_loop_20260529_03` | `tokyo-limited-express-loop.json` | `journey_AE4B3D6ECECDF1F02B9D88E33DB71D35` |
| `tokyo_limited_express_loop_20260529_04` | `tokyo-limited-express-loop.json` | `journey_1367E2AD44FB1282A603082C6B023451` |
| `tokyo_limited_express_loop_20260529_05` | `tokyo-limited-express-loop.json` | `journey_B113D59026AE72C23BC7DCC1E062B3D9` |
| `tokyo_limited_express_loop_20260529_06` | `tokyo-limited-express-loop.json` | `journey_8473C35D9B0263A67C1AE3CF2EF35F88` |
| `tokyo_limited_express_loop_20260529_07` | `tokyo-limited-express-loop.json` | `journey_DBB4A436D118AFC963F3D76ACC6D7F5A` |
| `tokyo_limited_express_loop_20260529_08` | `tokyo-limited-express-loop.json` | `journey_A15A2CDA79EC2AB1DB648F12DECB9CFF` |
| `tokyo_limited_express_loop_20260529_09` | `tokyo-limited-express-loop.json` | `journey_3C1174A1740BAC769A067CDF20A0CF5F` |
| `tokyo_limited_express_loop_20260529_10` | `tokyo-limited-express-loop.json` | `journey_DA0120B61DAC677C7FE9EFB54CF8F052` |
| `tokyo_limited_express_loop_20260529_11` | `tokyo-limited-express-loop.json` | `journey_346B51D9286011FC76E1B3066295219B` |
| `tokyo_limited_express_loop_20260529_12` | `tokyo-limited-express-loop.json` | `journey_8EEEEA38327E98645C7007A692CCAD31` |
| `tokyo_limited_express_loop_20260529_13` | `tokyo-limited-express-loop.json` | `journey_5F07101A177600FAEAB79C27F00916AF` |
| `tokyo_limited_express_loop_20260529_14` | `tokyo-limited-express-loop.json` | `journey_D8755000FA24D4235A8ED889B3A4AA9C` |
| `tokyo_limited_express_loop_20260529_15` | `tokyo-limited-express-loop.json` | `journey_868731BF1A9520928B670EC3A3B8566D` |
| `tokyo_limited_express_loop_20260529_16` | `tokyo-limited-express-loop.json` | `journey_E4ED0EC66250F2E663AEB7ECE1FA8F5A` |
