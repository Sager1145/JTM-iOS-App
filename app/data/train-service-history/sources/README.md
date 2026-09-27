# Train-service source inventory

This directory records source discovery and review candidates. `source-registry.jsonl`
uses the `source_documents` field names from `schema.sql`. Candidate files are not
canonical database inputs and must not be promoted without source, calendar,
station-reference and license review.

`accessed_at` records the task snapshot date, 2026-09-27. A live page may change
after that date. None of the portal landing pages listed here proves an all-year,
operator-wide limited-express inventory.

## Current official source coverage

| Operator | Registry source | Observed coverage | Effective-date evidence | Reuse/extraction blocker |
| --- | --- | --- | --- | --- |
| JR Hokkaido | `jr-hokkaido-vtime-hokuto-20260927` | A public line table exposes train numbers, names, operation labels and station rows for the selected line/date. | Selected view is dated 2026-09-27; the support page says data is normally loaded monthly through the following two months. | Kotsu Shimbunsha supplies the timetable data; no bulk-reuse grant was found. |
| JR East | `jr-east-timetables-2026` | Official station/train timetable portal with month-specific train pages. | Must be established per train page and month. | No data license or automated-extraction permission was found. |
| JR Central | `jr-central-access-search-2026` | Official search covers JR Central conventional lines and links train names to train timetables. | The page says next-month data is loaded monthly. | Query results are not an inventory export; no data reuse grant was found. The station page was partially unavailable during review. |
| JR West | `jr-west-thunderbird1-20260525` | Exact train-level candidate for Thunderbird 1 (4001M), Osaka-Tsuruga, on 2026-05-25, with all passenger-call arrival/departure times. | Page is based on the June 2026 JR Timetable issue and was queried for 2026-05-25. Only that date is verified by the candidate. | The page explicitly prohibits unauthorized reproduction, copying and processing; candidate promotion is blocked. |
| JR Shikoku | `jr-shikoku-timetable-portal-2026` | Official station timetable, formation and special-train notice entry point. | Must be established per station/train notice. | Station views do not establish complete trips/calendars and no data reuse grant was found. |
| JR Kyushu | `jr-kyushu-yufuin-no-mori-20260314` | Official service page exposes six public train numbers, ordered passenger stops and one displayed time per stop. | Timetable says revised 2026-03-14; page says information updated 2026-08-21. A separate July-September plan exists. | Intermediate arrivals are absent; dates use an image-coded calendar; later operation notices can supersede it; no data reuse grant was found. |

The JR Kyushu current-operation page is a separate evidence layer. It must be
modeled as planned/actual operation and must not silently modify the published
base timetable. The July-September plan must not be extended past its printed
period. Any September 2026 claim still needs the specific revision notice that
applies to the requested service date.

## Historical source coverage

The NDL Research Navi guide is an archive inventory, not proof of facts inside an
issue. It identifies original/reprint runs that can be acquired for deterministic
extraction and page-level review, including:

- Meiji-Taisho selected reprints covering issues from 1894-11 through 1927-01.
- Wartime selected reprints covering issues from 1925-04 through 1945-07.
- Immediate postwar selected reprints covering issues from 1945-09 through 1947-12.
- Original predecessor/JTB timetable holdings beginning in 1948, subject to issue gaps.
- Railway Museum and JTB travel-library holdings for specialist follow-up.

An official 2019 Railway Museum notice states that the first special express
operated on 1912-06-15 and identifies the displayed Shinbashi-Shimonoseki
timetable as revised on that date. This verifies the date and endpoints. It does
not expose the full timetable, so complete calls, times, train number and calendar
still require the original issue or an authorized reproduction.

Official Showakan/MHLW material supports that the last named limited express ended
in April 1944 and limited express service returned in September 1949. At that
precision, the defensible half-open zero-service interval is
`[1944-05-01, 1949-09-01)`. Exact boundary dates sometimes given in secondary
sources remain hypotheses until primary timetable evidence is acquired.

## Candidate review rules

1. Treat every file under `sources/candidates` as unreviewed and non-canonical.
2. Preserve nulls for arrival/departure values the source does not print.
3. Verify every `jp.n02.<sourceCode>` against `app/data/stations.json`.
4. Apply calendars only to the dates explicitly supported by the cited issue or notice.
5. Keep published timetable, later revision, disruption and actual-operation facts in separate layers.
6. Record source terms before extraction; `automated_extraction_allowed: false` means no automated ingestion authorization was established.
