# Japanese station English-name catalog

`app/data/station-english-jp.json` covers all 9,041 station **group codes** in
the published `jp-2025.json` network. Each row has the Japanese name, English
display candidate, source, review status, and `translationMayBeWrong` flag.
The catalog is a generated source for `app/data/rail.db`; the app's older
`station-readings.json` is a separate pronunciation table keyed by N02
**platform codes**. Do not copy group-code keys into that table.

## Source and status rules

| Status | Meaning | Warning flag |
| --- | --- | --- |
| `official_verified` | English spelling checked against [JR Central's station layout index](https://global.jr-central.co.jp/en/info/station/) with a reviewed group-code mapping, joined to [Toei's bilingual station-number lists](https://www.kotsu.metro.tokyo.jp/subway/stations/), or paired through an identical official Tokyo Metro page slug / JR East station ID and a unique Japanese-name/operator package mapping | false |
| `official_spelling_candidate` | An official spelling remains provisional because the source needs review or only the Romanized package label establishes a match. Currently this is JR East's published `Shim-Matsudo`, a suspected source typo | true |
| `community_unverified` | Existing package `nameRoma`, derived from the [OSM snapshot documented for the package](../app/public/rail/jp-2025.sources.md); this is **not** proof of an official operator translation | true |
| `manual_unverified` | Provisional name in `jp-station-english-manual.json` where the package has no Romanized/English label | true |

As of the 2026-09-30 source review, 343 names are official verified, 1 is an
official spelling candidate, 8,606 are community sourced, and 91 are manually supplied.
**8,698 candidates may be wrong**. The manual
list especially needs operator review. A later official spelling should replace
the candidate in the official override file, with its exact station group code
and source URL. Rebuild after changing either override file or the package.

The geometry, station identity, Japanese name, coordinates, line membership,
and operator remain owned by the published rail package and the N02 station
table. This catalog does not assert that the 2025 snapshot is a live inventory
of every station currently open in Japan.

The four operator lists are local source snapshots. `--check` verifies that the
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
official verification. The app interface still reads the older pronunciation
table; connecting this catalog to UI is a separate integration task.

## Rebuild and query

```sh
python3 app/scripts/railway/build-jp-station-english.py
python3 app/scripts/railway/build-jp-station-english.py --check
python3 -m unittest discover -s app/scripts/railway/tests -p test_jp_station_english.py -v
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
columns remain `NULL` outside Japan. For Japanese rows, `en` takes the catalog
value so its source and warning describe the value shown. The database build
checks that the catalog is current before loading it. The app interface does
not currently read this catalog or database.
