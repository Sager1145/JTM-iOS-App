# Bundled example trips: field conventions and sources

Applies to the sample stores `train-store.json` (jp), `train-store-tw.json`,
`train-store-hk.json`, `train-store-kr.json`, `train-store-mo.json` and
`special-samples/*.json`. The precomputed directories (`sample-data*/`,
`*-data/`) are regenerated from these stores by
`scripts/build/precompute-train-parts.mjs`. The 2026-11-05 normalization was
applied by `scripts/samples/normalize-sample-fields.py`.

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
