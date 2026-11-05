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
