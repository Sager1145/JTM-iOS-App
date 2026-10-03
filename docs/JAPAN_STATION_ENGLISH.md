# Official station English-name evidence and database

`app/data/station-english-jp.json` covers all 9,041 station **group codes** in
the published `jp-2025.json` network. Each row has the Japanese name, English
display candidate, source, review status, and `translationMayBeWrong` flag.
This legacy catalog is one input to the unified verdict in `station-english.json`;
`rail.db` and its legacy Japan view now use that unified verdict. The app's older
`station-readings.json` is a separate pronunciation table keyed by N02
**platform codes**. Do not copy group-code keys into that table. The runtime
projection `station-names*.json` joins retained readings and this English
catalog using exact `lineId:groupCode` keys, with separate platform aliases.
Japan's `en` and `romaji` fields retain English translation and pronunciation
separately. US/CA continue to use their frozen `station-readings` resources.

The all-region projection is now `app/data/station-english.json`. It covers
Japan, Taiwan, Hong Kong, Macao, Korea, the United States and Canada: 15,398
physical station groups and 19,081 line memberships. The SQLite mirror now
includes all seven regions; previously it omitted the United States and Canada.
English coverage is complete for this shipped inventory. Official verification
uses station-specific source identities and remains incomplete; exact counts are
listed below. `station-english-coverage.json` contains every unresolved group,
every unresolved line membership with its reason, and coverage for every operator.
A successful English-coverage check does not prove official correctness.

## Source and status rules

| Status | Meaning | Warning flag |
| --- | --- | --- |
| `official_verified` | English spelling checked against [JR Central's station layout index](https://global.jr-central.co.jp/en/info/station/) with a reviewed group-code mapping, joined to [Toei's bilingual station-number lists](https://www.kotsu.metro.tokyo.jp/subway/stations/), paired through an identical official Tokyo Metro page slug / JR East station ID and a unique Japanese-name/operator package mapping, or joined to JR Kyushu's bilingual station table within the operator | false |
| `official_spelling_candidate` | An official spelling remains provisional because the source needs review or only the Romanized package label establishes a match. Currently this is JR East's published `Shim-Matsudo`, a suspected source typo | true |
| `community_unverified` | Existing package `nameRoma`, derived from the [OSM snapshot documented for the package](../app/public/rail/jp-2025.sources.md); this is **not** proof of an official operator translation | true |
| `manual_unverified` | Provisional name in `jp-station-english-manual.json` where the package has no Romanized/English label | true |

The legacy Japan input alone contains 905 verified names, 1 is an
official spelling candidate, 8,052 are community sourced, and 83 are manually supplied.
These legacy-only counts exclude the newer evidence bundles listed below. The manual
list especially needs operator review. A later official spelling should replace
the candidate in the official override file, with its exact station group code
and source URL. Rebuild after changing either override file or the package.

The geometry, station identity, Japanese name, coordinates, line membership,
and operator remain owned by the published rail package and the N02 station
table. This catalog does not assert that the 2025 snapshot is a live inventory
of every station currently open in Japan.

The operator lists are local source snapshots. `--check` verifies that the
generated catalog still agrees with these snapshots and the packaged network;
it does not check whether an operator has since changed its website or spelling.

## Bilingual identity evidence and remaining review

Tokyo Metro's [Japanese index](https://www.tokyometro.jp/station/index03.html)
and [English index](https://www.tokyometro.jp/lang_en/station/index03.html)
link to the same 144 station-page slugs. The local `byStationId` snapshot
retains both labels and official station numbers. 143 entries have a unique
package mapping; Ikebukuro has two group codes and remains in `identityReview`.
Reviewed variants (`市ケ谷`/`市ヶ谷`, `霞ケ関`/`霞ヶ関`, `麴町`/`麹町`,
`西ケ原`/`西ヶ原`, `南阿佐ケ谷`/`南阿佐ヶ谷`) and bracketed landmark aliases
are recorded explicitly as `packageJa`; the source label is preserved.

JR East's `byEnglishName` snapshot retains 131 English index records and their
numeric station IDs. Japanese labels come from official station links in the
[route/facility indexes](https://www.jreast.co.jp/estation/facility_search.aspx?SearchCategoryCd=3),
with each exact index URL retained. Muikamachi uses the [Japanese ID 1520
detail](https://www.jreast.co.jp/estation/station/info.aspx?StationCd=1520)
paired with its [English page](https://www.jreast.co.jp/e/stations/e1520.html).
The English index mislinks Nagaoka to Nagano ID 1105; the Japanese Joetsu
index and [Nagaoka detail heading](https://www.jreast.co.jp/e/stations/e1085.html)
resolve it to ID 1085. The incorrect index ID and correction remain recorded.
`阿佐ケ谷`/`阿佐ヶ谷`, `市ケ谷`/`市ヶ谷`, and `空港第２ビル`/`空港第2ビル`
are explicit Japanese spelling variants. 128 JR East entries verify uniquely;
counts across operators overlap at shared station groups.

The catalog's `identityReview` ledger retains four source records requiring
review: Metro Ikebukuro, JR East Musashi-Kosugi and Tokyo each have two package
group codes; [JR East ID 884](https://www.jreast.co.jp/e/stations/e884.html)
publishes `Shim-Matsudo` in both its index and detail heading. The latter is
an official spelling candidate with its warning retained. The three ambiguous
records do not verify a group merely by matching its Romanized spelling;
independent sources can still verify a particular group (for example Tokyo).

Promoted Metro/JR East rows retain `identityEvidence` with the original labels,
station ID, English and Japanese URLs, retrieval date, and mapping notes.
The SQL mirror stores the selected spelling, primary source URL and warning;
the full evidence and review ledger remain in the JSON catalog/source files.
Other operators and stations outside these limited official indexes still need
station-specific official evidence. Full English-name coverage is not full
official verification. The app interface now reads the derived `station-names`
table. `station-names-coverage.json` retains each membership's English status,
explicit operator kana evidence and any OpenCC character rendering used to
fill Chinese fields. Character rendering is not an official Chinese translation.

JR Kyushu's [multilingual station table](https://www.jrkyushu.co.jp/english/pdf/howtosearch_tips.pdf)
supplies 562 additional verified group identities. The snapshot retains exact
published labels, PDF pages, source hash, extraction rules and unmatched rows;
display capitalization is an explicit transformation. The [2026–2027 timetable](https://www.jrkyushu.co.jp/english/pdf/timetable_20260314_20270228.pdf)
provides current 江北/Kōhoku and 新大村/Shin-Ōmura bilingual cells on page 5.
JR Kyushu coverage is 562/572 groups; published Japanese typos, stale names,
unmatched variants and absent stations remain in `identityReview` rather than
being matched by similar romanization. `operatorCoverage` inventories all 176
Japanese operators, including those with no verified names.

## Seven-region evidence and identity

| Region | Station groups with English | Official verified groups |
| --- | ---: | ---: |
| JP | 9,041 / 9,041 | 796 |
| TW | 505 / 505 | 19 |
| HK | 282 / 282 | 282 |
| MO | 15 / 15 | 15 |
| KR | 1,097 / 1,097 | 0 |
| US | 3,777 / 3,777 | 0 |
| CA | 681 / 681 | 0 |

A verified group requires official evidence for every operator/line membership.
Different operator-published English labels can both be correct; such a group
uses `multiple_official_names` and retains the line-specific spellings. `official_dataset_candidate` retains existing government/operator
attribution without asserting a newly verified exact source label. The raw
source archives for TW/KR and North America are retained under
`app/data/station-english-sources/`, with original source hashes and retrieval dates.
North America's builder transforms GTFS names, so a broad `stop_name` claim
alone cannot prove every retained spelling is the exact official English label.
French proper names remain operator-published proper names.

Hong Kong and Macao use `hk-mo-station-english-official.json`: bilingual MTR
[railway CSV](https://opendata.mtr.com.hk/data/mtr_lines_and_stations.csv) and
[Light Rail CSV](https://opendata.mtr.com.hk/data/light_rail_routes_and_stops.csv),
paired Hong Kong Tramways government [English stop list](https://static.data.gov.hk/tramways/datasets/tram_stops/summary_tram_stops_en.csv)
and [Chinese stop list](https://static.data.gov.hk/tramways/datasets/tram_stops/summary_tram_stops_tc.csv),
MTR's bilingual map tables for Racecourse, and Macao LRT's
[bilingual route selector](https://www.mlm.com.mo/en/route.html).
Source hashes, extracted records, dates, station codes and reviewed Chinese
variants are retained. Reused tram terminal codes require a unique name and
operator match; Macao's route-selector station indices distinguish station
labels from a contradictory transfer hint on the same page.

Taiwan's 19 formerly blank Alishan English names use reviewed operator
[bilingual station pages](https://afrch.forest.gov.tw/En) in
`tw-station-english-afr-source.json`. The repeatable repair fills 42 code/line
aliases and 18 safe name fallbacks. Names from station-specific headings take
precedence over contradictory homepage spellings; the alternatives and the
explicit 木履寮/木屐寮 alias remain recorded. Generic `Station` suffix removal
is documented. All 559 Taiwan source station codes now have nonblank English.

The newer `station-english-verified-*.json` bundles are derived from retained
operator/government responses by their corresponding `verify-*-station-english.py`
scripts. North America uses source GTFS IDs, with explicit official replacement-feed
or station-page spatial identity evidence where IDs changed. It preserves published
proper names, including French names, and replaces the map builder's shortened labels
with exact publisher labels in the database. Taiwan uses all ten official PTX Station
and StationOfLine APIs; AFR has separate operator-page evidence even at shared Chiayi.
Korea uses bilingual official line tables plus official coordinate corroboration;
operator mismatches, other-city contamination and coordinate conflicts stay unresolved.

Japan now adds operator-owned bilingual masters for Hokkaido and JR Central,
paired station-page IDs for Osaka Metro, full bilingual JR East timetable station IDs,
and the retained official private-railway indices. Source names never propagate to a
different operator merely because both use the same map group code. Official JR Central
English for shared 伊勢市 cannot verify Kintetsu's membership. The legacy Japan SQLite
table and view mirror the unified Japan spelling/status/source, rather than retaining
an older verification verdict.

The unified catalog resolves a line-scoped code before a group code and never
uses a name-only fallback to prove identity. `memberships` and `enVariants`
preserve differently named platforms at transfer complexes (Taipei/Taipei
Main Station, Hsinchu/Liujia, and similar cases). The group summary is a
representative label; use `station_name_wide` for names on a particular line.
Korea contains same-name groups with different city/line identities; those
remain `identity_review` and must not be used as a nationwide name dictionary.
Source input hashes make `--check` reject changes to packages, readings,
reviewed snapshots or feed registry until the projection is regenerated.

```sh
python3 app/scripts/railway/apply-tw-station-english.py --check
python3 app/scripts/railway/build-jp-station-english.py
python3 app/scripts/railway/build-station-english.py
python3 app/scripts/railway/build-station-english.py --check --require-english
# Intentionally fails while the official-evidence ledger is incomplete:
python3 app/scripts/railway/build-station-english.py --check --require-official
python3 -m unittest discover -s app/scripts/railway/tests -p '*station_english*.py' -v
python3 -m unittest discover -s app/scripts/railway/tests -p test_hk_mo_station_english.py -v
```

To re-fetch HK/MO source snapshots, run
`python3 app/scripts/railway/fetch-hk-mo-station-english.py` and review the
identity/source diff before rebuilding the unified catalog. To re-import JR
Kyushu's PDF, run `build-jp-station-english.py --import-jr-kyushu /path/to/howtosearch_tips.pdf`
(requires `pypdf`); normal offline rebuilds need only Python's standard library.

## Rebuild and query

```sh
python3 app/scripts/railway/build-jp-station-english.py
python3 app/scripts/railway/build-jp-station-english.py --check
python3 -m unittest discover -s app/scripts/railway/tests -p test_jp_station_english.py -v
python3 app/scripts/railway/build-station-names.py
cd app && node scripts/build/build-rail-database.mjs
```

In a shared checkout, coordinate the `rail.db` rebuild with its integration and
timetable owners. Validate separately with `node scripts/build/build-rail-database.mjs
--out /tmp/jtm-station-english.db` while those owners are writing generated resources.

`rail.db` is a generated local mirror. `jp_station_detail` joins the English
candidate and its warning to the Japanese name, group code, coordinates, and
line count. `station_line` supplies each station's lines and operators.

```sql
SELECT station_code, name_ja, name_en, en_status,
       translation_may_be_wrong, lon, lat, line_count
FROM jp_station_detail WHERE station_code = '003766';

SELECT line_name, operator FROM station_line
WHERE country_code = 'JP' AND station_code = '003766';
```

`station_name_wide` also exposes `en`, `en_status`,
`en_translation_may_be_wrong`, and `en_source` for each line stop. The warning
columns now apply to every region. For Japanese rows, `en` takes the catalog
value so its source and warning describe the value shown. The database build
checks that the catalog is current before loading it. The app interface
reads the derived name table rather than SQLite. `station_english` and
`line_station_english` retain full evidence JSON. `station_detail` is the
all-region query view; `jp_station_detail` remains compatible with old queries.

```sql
SELECT country_code, station_code, base_name, name_en, en_status,
       translation_may_be_wrong, en_source
FROM station_detail WHERE country_code IN ('HK', 'MO');

SELECT country_code, COUNT(*) AS awaiting_verification
FROM station_detail WHERE translation_may_be_wrong = 1
GROUP BY country_code;
```
