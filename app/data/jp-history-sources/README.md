# Japan railway history source inventories

This directory is the review boundary between official MLIT source rows and
the runtime `rail-history` v1 model. It does not change the runtime schema.

`mlit-openings.json` contains all 121 rows in MLIT's **鉄軌道開業一覧（平成5
年度以降）**, current 2026-04-01. `mlit-closures.json` contains all 78 rows in
MLIT's **鉄軌道の廃止実績（平成5年度以降）**, current 2026-04-01. The
inventories preserve source order, page number, official spellings, interval,
business kilometres, exact-day ISO date, source checksum, and a stable row id.
The checked-in `row_identity_sha256` covers every ordered official cell. The
importer also counts rendered rows containing an era date independently of the
date-column parser. `--check` therefore rejects an omitted row, a same-count row
substitution, or a PDF layout shift that moves dates out of the expected column.

Every imported row starts with `selector.status = "unresolved"`. Publication in
an MLIT table proves the date and the source row; it does not prove which current
N02 identity or geometry is the right selector. A row may be promoted only after
reviewing its operator/line identity, termini, and whether the row describes the
whole current line or one extension. Partial openings must not stamp an entire
current line.

`reviewed-mlit-row-selectors.json` records 67 explicit review decisions (40
opening rows and 27 closure rows). Importing the official PDFs replays this
ledger after creating unresolved rows; `--check` rejects missing, extra or
changed resolved selectors. A canonical link alone does not mark a row as
reviewed. The official-cell fingerprints remain independent of review fields.

The `reviewed-transfer-events-*.json` promotion ledgers retain predecessor
snapshot geometry for operator transfers and isolate each official interval.
The 2015 Toyama/Niigata ledger also records three later station openings, so
current station points cannot silently inherit the earlier transfer date.

`reviewed-transfer-events-myoko.json` records the 2015 transfer together with
the preceding 2014-10-19 脇野田 relocation. Its `historical_periods` select
N02-13 and N02-14 independently. Both shared JR boundary memberships are
reused: 妙高高原 from North Shinano and continuing 直江津 from the current
package. Survey years never define either effective day.

`reviewed-station-openings-shinano-igr.json` promotes five later station
openings with unique current geometry supported by the earliest available
post-opening survey. 巣子 remains withheld because its opening-era paired
platform geometry is incomplete in the current package.

`reviewed-identity-events.json` is a reusable seed ledger for exact-day identity
changes. `reviewed_seed` rows have a reviewed whole-current-identity, isolated
segment, unique current-station or historical-station selector.
`reviewed_source_only` rows preserve reviewed evidence
but remain out of the compiler until their historical alignment, station scope
and required predecessor identities are reviewed. The two-stage 青い森鉄道線 transfers,
1997 しなの鉄道, 2002 IGR and 2001 Nishitetsu line/station changes remain
unresolved. Later stations and alignments prevent whole-current-line backdating;
the Nishitetsu station event also depends on its missing predecessor line graph.
The two IRいしかわ鉄道線 phases now have disjoint reviewed
selectors and an explicit shared predecessor station, rather than one
whole-line date. Snapshot observations record raw old/current N02
spellings; they are identity evidence, not independent proof of the event date.

`reviewed-opening-events.json` contains 25 additional promotion-ready rich
events whose official opening interval is one complete current N02
line/operator identity. The file carries the exact MLIT row id and is checked
against the complete opening inventory for date, termini, business kilometres,
official spelling, and source URL. Its withheld list documents representative
near-matches that are unsafe because the current line was built in stages,
extends beyond the official interval, has a later-added current station, or now
has a different operator.

`reviewed-station-events.json` contains six promotion-ready Keikyu station
rename events effective 2020-03-14. Keikyu's primary announcement supplies the
exact old/current names, date, and stable station numbers KK16, KK17, KK25,
KK30, KK35, and KK53. Each event treats `station_entity_id` and `membership_id`
as first-class stable identities, records the matched current N02 station code,
selects exactly one current N02 station, and includes its old-name N02-19
feature. The importer tests require the N02-19 coordinates to equal the current
feature exactly before these events may use same-alignment identity compilation.

The inventories were generated with:

```sh
python3 app/scripts/railway/history/import-mlit-history.py \
  --openings-pdf /path/to/001884569.pdf \
  --closures-pdf /path/to/001737586.pdf \
  --retrieved-at 2026-09-27
python3 app/scripts/railway/history/import-mlit-history.py --check
```

Official sources:

- MLIT railway statistics index:
  <https://www.mlit.go.jp/statistics/details/tetsudo_list.html>
- Opening table PDF:
  <https://www.mlit.go.jp/statistics/details/content/001884569.pdf>
- Closure table PDF:
  <https://www.mlit.go.jp/statistics/details/content/001737586.pdf>
- Keikyu six-station rename announcement (effective 2020-03-14):
  <https://www.keikyu.co.jp/assets/pdf/20191216HP_19166TS.pdf>
- N02-19 archive used for pre-rename station identities and geometry:
  <https://nlftp.mlit.go.jp/ksj/gml/data/N02/N02-19/N02-19_GML.zip>
- MLIT website terms (PDL 1.0, attribution and modification disclosure):
  <https://www.mlit.go.jp/link.html>

The two PDFs are retrieval inputs and are not committed. Their SHA-256 values
are recorded in the generated files, so a changed upstream PDF cannot be
mistaken for the reviewed extraction.

## Geometry evidence and licence boundary

The legacy N02 page offers two nationwide packages labelled **平成7年**, with a
metadata publication/reference date of **1996-12-31**:

- Tokyo Datum, v1.0:
  <https://nlftp.mlit.go.jp/ksj/old/data/N02/N02-07L/N02-07L-48-01.0.zip>
- JGD2000, v1.0a:
  <https://nlftp.mlit.go.jp/ksj/old/data/N02/N02-07L/N02-07L-48-01.1a.zip>
- Landing page:
  <https://nlftp.mlit.go.jp/ksj/old/datalist/old_KsjTmplt-N02.html>
- JGD2000 metadata:
  <https://nlftp.mlit.go.jp/ksj/old/meta/N02/N02-07L/KS-META-N02-07L-2K.htm>

These are legacy unified-format text packages. Their metadata requires the
National Land Numerical Information terms, and the old page does not label them
CC BY 4.0. The current N02 page's licence must not be projected backwards onto
this package. The importer records the URLs but does not bundle the archives.
See MLIT's [old terms](https://nlftp.mlit.go.jp/ksj/other/agreement_02.html) and
[FAQ Q9](https://nlftp.mlit.go.jp/ksj/other/faq.html).

N05 railway time-series data is also excluded. MLIT labels it **noncommercial**
and explains that JTB's `停車場変遷大辞典Ⅰ・Ⅱ` is an underlying source. It is a
useful private cross-check, but it cannot be shipped in this app or treated as
the provenance of redistributed runtime geometry. See the
[N05 page](https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N05-2025.html).

`source-registry.json` keeps these URLs and decisions machine-readable.

The partial-opening ledger selects complete current section features with a bbox
and an explicit new-station allow-list. Existing boundary platforms are excluded.
A reviewed opening may name `predecessor_event_ids` to intersect matching old
operator variants with its opening day; every selected geometry must match exactly.
The 2019 station-rename ledger uses N02-18 for Hankyu/Hanshin Umeda memberships
that already carry their new name in N02-19, and keeps each line membership explicit.
The service-correction ledger distinguishes Sassho’s last service on 2020-04-17
from its legal closure on 2020-05-07. Nose’s conflicting official-table date and
Nemuro’s measured geometry gap remain unresolved.

Five further partial openings cover Kyoto, Sapporo and Nagoya extensions. Their
post-opening N02 comparisons remain corroboration only. The 1994 Sakuradori
opening is withheld until 瑞穂運動場→瑞穂運動場西 historical name/geometry lineage
is reviewed; coarse 1996 geometry is not shipped. The Kyoto N02-08 西大路池 label
and platform split are recorded as source anomalies, with N02-11/current alignment
checked independently.
