# Yufu 1–5 route and operator evidence gap — 2026-09-30

## Scope and decision

This note reviews the five already normalized, exact-day `ゆふ` trips. Their ordered passenger calls are supported by JR Kyushu's 2026-09-30 timetable pages in the individual batch reports. The physical line sequence and ordered operating-company segments remain **unknown** in the normalized records. Do not promote the candidate route below into `route_lines` or `operator` solely from this note.

## Sources and dates

| Source | What it establishes | Temporal limit |
| --- | --- | --- |
| [JR Kyushu Yufu 1 timetable](https://www.jrkyushu-timetable.jp/jr-k_time/2610/0016/00167101.html?c=28283&ym=202609&d=30) and the trip-specific pages cited in the [Yufu 2](train-timetable-kyushu-2026-09-30-yufu2-batch.md), [Yufu 3](train-timetable-kyushu-2026-09-30-yufu3-batch.md), [Yufu 4](train-timetable-kyushu-2026-09-30-yufu4-batch.md), and [Yufu 5](train-timetable-kyushu-2026-09-30-yufu5-batch.md) reports | Ordered passenger calls for 2026-09-30 | A trip table does not identify every traversed infrastructure line or prove operator boundaries. See the [Yufu 1 batch report](train-timetable-kyushu-2026-09-30-kasasagi101-yufu1-batch.md) for its exact-day extraction. |
| JR Kyushu 2026-09-30 station departures: [博多・鹿児島本線 toward 鳥栖](https://www.jrkyushu-timetable.jp/cgi-bin/sp/sp-tt_dep.cgi/2828302e/), [久留米・久大本線 toward 大分](https://www.jrkyushu-timetable.jp/cgi-bin/sp/sp-tt_dep.cgi/2814404/), [大分・日豊本線 toward 別府](https://www.jrkyushu-timetable.jp/cgi-bin/sp/sp-tt_dep.cgi/2874200e/), [別府・日豊本線 toward 大分](https://www.jrkyushu-timetable.jp/cgi-bin/sp/sp-tt_dep.cgi/2880501e/), [大分・久大本線 toward 久留米](https://www.jrkyushu-timetable.jp/cgi-bin/sp/sp-tt_dep.cgi/2874202/), and [久留米・鹿児島本線 toward 博多](https://www.jrkyushu-timetable.jp/cgi-bin/sp/sp-tt_dep.cgi/2814402/) | The browser-rendered date is 2026-09-30. The first two headings list ゆふ1/3/5; the third lists ゆふ1/3; the fourth lists ゆふ4; and the last two list ゆふ2/4. These are train-specific planned departure-line labels at the displayed stations. | A station heading is not a complete train-path trace, an infrastructure inventory, or an operating-company boundary. The pages select a date dynamically, so verify the displayed date rather than inferring it from the URL or retrieval time. |
| [JR Kyushu FY2026 securities report, p. 38, railway tracks and electrical facilities](https://www.jrkyushu.co.jp/company/ir/news/__icsFiles/afieldfile/2026/06/19/9142.FY2026.securities_report.pdf) | The company lists 鹿児島本線 as 門司港–八代 and 川内–鹿児島, 久大本線 as (久留米)–(大分), and 日豊本線 as (小倉)–大分–(鹿児島), under `鉄道線路及び電路施設`. Filed 2026-06-19; the facilities table states **2026-03-31**. | Company facilities and their formal names are documented for March 2026, not an effective-period guarantee through 2026-09-30 or proof that each Yufu train traversed every candidate segment. Parentheses in the table are its endpoint/railway-station counting notation, not evidence of an absent junction. |
| [MLIT National Land Numerical Information N02, 2025 edition](https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N02-2025.html) | Railway-section line names (`N02_003`), operating companies (`N02_004`), and station-line associations. The local `app/public/rail/jp-2025.json` is the corresponding snapshot used for candidate matching. | MLIT gives **2025-12-31** as its reference date. The 2026-04 publication update is not a 2026-09-30 effective date. The page does not provide per-line daily validity intervals. |
| [JR Kyushu route map](https://www.jrkyushu.co.jp/railway/routemap/routemap2601.pdf), linked from its [route-map page](https://www.jrkyushu.co.jp/railway/routemap/) | The visually inspected PDF prints `2026年1月現在`. It depicts 鹿児島本線 through 博多・鳥栖・久留米, 久大本線 from 久留米 via 日田・由布院 to 大分, and 日豊本線 through 別府・大分. Both candidate change points are visible. | This is an as-of-January network map, not a Yufu 1–5 timetable or a stated validity interval through 2026-09-30. Its PDF metadata creation date is 2026-01-15; the printed label is the public as-of date. |
| [JR Kyushu QR ticketless launch notice](https://www.jrkyushu.co.jp/news/__icsFiles/afieldfile/2024/09/20/240920_qr_ticketless_service.pdf), appendix 1 | Explicitly lists `ゆふいんの森・ゆふ` operating lines as 鹿児島本線, 久大本線, 日豊本線, with service geography 博多–由布院–大分・別府. Its ticketless area lists 鹿児島本線 門司港–久留米 and 久大本線 久留米–大分, and excludes 九州新幹線. This directly supports the conventional 博多–久留米 candidate and the 久留米 change point. | The notice launched a ticketing service in 2024. Its service-family table is not dated to the five 2026-09-30 occurrences, and ticketing scope does not establish operating-company segments. |
| [JR Kyushu line-section report](https://www.jrkyushu.co.jp/news/__icsFiles/afieldfile/2026/01/27/240820_2023_senkubetsu_1.pdf) | Lists 久大本線 as 久留米–大分, 141.5 km. | Its stated basis is the end of fiscal 2023, despite the later hosted URL. It is corroboration of an older endpoint definition, not exact-day proof. |
| [JR Kyushu 2026-06-24 service plan](https://www.jrkyushu.co.jp/common/inc/emergency/__icsFiles/afieldfile/2026/06/24/20260624_train_plan.pdf) | Separately describes `ゆふ` service geography (博多–大分・別府) and 久大本線 geography (久留米–日田–庄内–大分). | Applies to a June disruption plan, not 2026-09-30 operations or route validity. |

Search-engine snapshots of the reverse-direction pages displayed **2026-09-29**. A subsequent direct browser inspection displayed **2026-09-30**, with ゆふ2/4 in the corresponding departure lists. This difference is caused by the dynamic date shown by the page; cite the visible day with any later use of these links.

## Candidate alignment from the 2025 N02 snapshot

After station-identity reconciliation, the local N02-derived package places the Yufu stops on `jp-九州旅客鉄道-鹿児島線` between 博多 and 久留米, `jp-九州旅客鉄道-久大線` between 久留米 and 大分, and `jp-九州旅客鉄道-日豊線` between 大分 and 別府. The package uses `鹿児島線` / `久大線` / `日豊線`; JR Kyushu's public labels use `鹿児島本線` / `久大本線` / `日豊本線`. The local package is processed from N02 for railway geometry, with station display-name attributes separately enriched from OSM; its display spellings are not literal MLIT raw fields. The official page spells 天ケ瀬 while the local station array spells 天ヶ瀬; both map to station code `009457`. The JR Kyushu train-family notice, January network map, and March facilities table independently corroborate the three public line names and the conventional 博多–久留米 route. The following is still a **candidate exact-day alignment**, since none of those sources certifies every physical segment of each September 30 occurrence. The package also associates 博多 and 久留米 with 九州新幹線; automatic station-overlap matching must choose the conventional line explicitly and carry the JR notice as evidence.

| Trip | Exact-day passenger endpoints | Candidate ordered line segments and change points |
| --- | --- | --- |
| ゆふ1 | 博多 → 別府 | 鹿児島線 博多 → 久留米; 久大線 久留米 → 大分; 日豊線 大分 → 別府 |
| ゆふ2 | 大分 → 博多 | 久大線 大分 → 久留米; 鹿児島線 久留米 → 博多 |
| ゆふ3 | 博多 → 別府 | 鹿児島線 博多 → 久留米; 久大線 久留米 → 大分; 日豊線 大分 → 別府 |
| ゆふ4 | 別府 → 博多 | 日豊線 別府 → 大分; 久大線 大分 → 久留米; 鹿児島線 久留米 → 博多 |
| ゆふ5 | 博多 → 大分 | 鹿児島線 博多 → 久留米; 久大線 久留米 → 大分 |

For the same three N02 line identities, the snapshot's operating-company field is `九州旅客鉄道`. The 2026-03-31 JR Kyushu facilities table is later evidence that all three lines belong to its reported network. Neither that table nor the train-family notice identifies the ordered operating-company segments for Yufu 1–5 on 2026-09-30, so those segments remain unresolved.

## Evidence needed before normalization

1. Obtain an official JR Kyushu or MLIT source with a stated effective period covering 2026-09-30 that confirms the ordered physical line identities, including the conventional 博多–久留米 segment and the 大分–別府 segment.
2. Confirm the change points at 久留米 and 大分 against that dated source, including any unlisted passenger stations or route deviations between calls.
3. Obtain day-applicable operating-company boundary evidence for the entire traversed route and map it to the normalized operator-segment representation.
4. Reconcile official line labels with the stable local N02 IDs and record source provenance before adding `route_lines` or operator segments.

Until then, retain `route_lines` and ordered `operator` completeness as `unknown`/open for all five trips. This review adds no suffix normalizer and changes no shared rebuild, SQLite output, or master report.
