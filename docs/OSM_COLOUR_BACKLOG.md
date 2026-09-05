# OSM colour backlog: the 61 relations, sorted by how the colour can be sourced

Read-only, 2026-09-05. Inputs: `app/public/rail/na-2025-line-review.json` (the 61
lines whose only issue is "OSM colour is not an official colour source"),
`app/scripts/railway/na-feeds.json`, and the 97 GTFS zips cached under
`app/data/raw/na-rail/gtfs/` (checksums from `logs/gtfs-manifest-final.json`).
Every hex below was read from routes.txt in that cache, not from memory.

## A. GTFS route_color available in a registry feed already on disk (16 relations)

Ready to paste into `osmLineColors`. Source strings follow the Montreal template
and avoid the audit's forbidden words.

| Relation | OSM line | Registry feed (mdb key) | route_id | route_color | Note |
|---|---|---|---|---|---|
| 4433102 | CTrail Shore Line East: Stamford <=> New London | shore-line-east (550), http://www.shorelineeast.com/google_transit.zip, sha256 1d1f7329… | SLET "Shore Line East Train" | #EF3E42 | feed has no feed_info; cite the manifest sha256 |
| 1468867 | PATH: Newark → WTC | port-authority-trans-hudson (517), http://data.trilliumtransit.com/gtfs/path-nj-us/path-nj-us.zip, feed_version "UTC: 22-May-2025 18:06" | 862 "Newark - World Trade Center" | #d93a30 | PATH publishes one colour per service; the relation is the NWK–WTC service |
| 4729047 | Silver Line (San Diego MTS) | san-diego-international-airp (13), https://www.sdmts.com/google_transit_files/google_transit.zip, feed_version "Generated on 20260521…" | 550 "Silver / Downtown Loop" | #B4BCC2 | |
| 12330590 | QLine: Grand Boulevard => Congress Street | qline-detroit (802), http://data.trilliumtransit.com/gtfs/qline-mi-us/qline-mi-us.zip, feed_version "UTC: 21-Apr-2025 21:29" | 13578 "QLINE" | #EF4D2E | geometry is a separate session's problem; colour is not |
| 12330591 | QLine: Congress Street => Grand Boulevard | same | 13578 | #EF4D2E | other direction |
| 12331264 | The Hop M-Line: Burns Commons → Intermodal Station | milwaukee-hop (milwaukee-hop-official), https://thehopmke.transloc.com/Secure/Admin/Reports/GTFSDownload.aspx, sha256 ada16c01… | TL-7 "M-Line THE HOP" | #3A81DE | feed types the streetcar as route_type 3; colour is still the operator's |
| 19668643 | REM A1 : Deux-Montagnes → Brossard | rem (tld-6691), https://gtfs.gpmmom.ca/gtfs/gtfs.zip, feed_version 20260520 | S1 | #73A400 | one colour for every branch |
| 19668926 | REM A1 : Anse-à-l'Orme → Brossard | same | S3 | #73A400 | |
| 19669299 | REM A4 : Brossard → Deux-Montagnes | same | S1 | #73A400 | |
| 19672327 | REM A3 : Brossard → Anse-à-l'Orme | same | S3 | #73A400 | |
| 58433 | Ligne verte vers Honoré-Beaugrand | soci-t-de-transport-de-montr (2126), https://www.stm.info/sites/default/files/gtfs/gtfs_stm.zip, feed_version 20260805110000 | 1 | #00B300 | |
| 270251 | Ligne orange vers Montmorency | same | 2 | #D95700 | |
| 270252 | Ligne jaune vers Berri-UQAM | same | 4 | #FFD900 | |
| 270255 | Ligne bleue vers Saint-Michel | same | 5 | #0095E6 | |
| 11558404 | Loop Trolley | loop-trolley (mdb-2035), https://files.looptrolley.com/google_transit.zip, sha256 4c0fd098… | 18869 "Loop Trolley" | #FFFFFF | **published value is white**; passes the audit but is unusable on a map. Needs the operator's brand colour instead (looptrolley.com), so treat as category C in practice |
| 6504062 | WVU PRT: Medical → Walnut | wvu-prt (tld-7068_1), route_color blank | — | #002855 | reuse the WVU brand-blue source string the registry already holds for feed route 1 |

Net: 15 usable hexes plus 1 brand reuse. Loop Trolley's white is the one trap.

## B. Operator has a GTFS feed that is NOT in the registry (4 relations, not verified)

The registry is generated from the MobilityData catalogue and deliberately leaves
some operators out. These four operators are known to publish GTFS, so their
route_color is probably one download away, but nothing is on disk to read:

| Relation | OSM line | Where to look |
|---|---|---|
| 11364343 | NFTA Metro Rail: University → DL&W | NFTA GTFS (metro.nfta.com developer page); Metro Rail is route 55 in past feeds |
| 5936157 | Las Vegas Monorail | Las Vegas Monorail Co. GTFS via MobilityData / RTC Southern Nevada |
| 12741494 | Polar Bear Express: Moosonee => Cochrane | Ontario Northland GTFS (motor coach feed; check whether the train is a route) |
| 2721462 | Skylink (counterclockwise) | DFW Airport; not in the DART feed (152) — probably no GTFS, brand asset likely |

## C. No GTFS anywhere: airport people movers (18 relations)

ATL SkyTrain 8863388; LAS Green 17583000, Blue 17583003, Red 9728924; DEN AGTS
14910916; DTW ExpressTram 8438646; IAH Skyway 14909564; IAD AeroTrain 19017835;
ORD ATS 9452035; MCO Gate Link 13466609, 13471238, 15048396, 15048399 and Terminal
Link 15048456; TPA Airside A 12560197; EWR AirTrain Newark 7638917; SFO AirTrain
Blue 6043603, Red 6043605. Source will be each airport authority's terminal map
SVG/PDF or wayfinding page (LAS, MCO and SFO name their lines by colour, which is
the easy half).

## D. No GTFS anywhere: heritage and tourist railways (20 relations)

Andrews Valley 16215780; Astoria Riverfront Trolley 6183627; Lookout Mountain
Incline 1608273; Tsal'alh Seton Train 8244952; Platte Valley Trolley 8652421;
High Level Bridge Streetcar 7699146; Electric City Trolley 18070836; Fillmore &
Western 6804311; Great Smoky Mountains 16215777, 16215779; Keewatin 13055367;
Lowell NPS Trolley 8251687; Niles Canyon 6142178; Roaring Camp 3487689; Sacramento
River Train 6142319; Strasburg 7592251, 7592252; Grapevine Vintage 6762509;
Tshiuetin 13055512; MATA Trolley Riverfront 278701, Main Street 278703, Madison
8417679 (the MATA feed tld-1655 carries buses only; the trolley routes are absent).
Source will be the operator's own map or brand asset, per the Alaska Railroad and
Seattle Monorail precedents (logo fill or map legend, with the asset URL and the
element it was read from). Some may be better withheld than coloured.

Count check: 16 + 4 + 18 + 23 = 61. (Category D is 23 with the three MATA rows.)

## Against the handoff's "28 of 53 were GTFS"

The heritage agent's 53 presumably counted feeds outside the registry and airport
or heritage operators with any feed at all. What is verifiable on this machine
today is the 15 hexes in A. Categories B–D are the re-research; B is cheap.

## Drop-in JSON for category A

```json
"osmLineColors": {
  "4433102": {"color": "#EF3E42", "source": "operator GTFS routes.txt route_color; Shore Line East route SLET Shore Line East Train, http://www.shorelineeast.com/google_transit.zip (sha256 1d1f7329…, cached 2026-09-04), retrieved 2026-09-05"},
  "1468867": {"color": "#D93A30", "source": "operator GTFS routes.txt route_color; PATH route 862 Newark - World Trade Center, http://data.trilliumtransit.com/gtfs/path-nj-us/path-nj-us.zip, feed_version UTC: 22-May-2025 18:06, retrieved 2026-09-05"},
  "4729047": {"color": "#B4BCC2", "source": "operator GTFS routes.txt route_color; San Diego MTS route 550 Silver Downtown Loop, https://www.sdmts.com/google_transit_files/google_transit.zip, feed_version Generated on 20260521 @ 1307142, retrieved 2026-09-05"},
  "12330590": {"color": "#EF4D2E", "source": "operator GTFS routes.txt route_color; QLINE Detroit route 13578, http://data.trilliumtransit.com/gtfs/qline-mi-us/qline-mi-us.zip, feed_version UTC: 21-Apr-2025 21:29, retrieved 2026-09-05"},
  "12330591": {"color": "#EF4D2E", "source": "<same as 12330590>"},
  "12331264": {"color": "#3A81DE", "source": "operator GTFS routes.txt route_color; The Hop route TL-7 M-Line THE HOP, City of Milwaukee, https://thehopmke.transloc.com/Secure/Admin/Reports/GTFSDownload.aspx (sha256 ada16c01…, cached 2026-09-04), retrieved 2026-09-05"},
  "19668643": {"color": "#73A400", "source": "operator GTFS routes.txt route_color; REM routes S1 and S3 (S2 publishes 72A300), https://gtfs.gpmmom.ca/gtfs/gtfs.zip, feed_version 20260520, retrieved 2026-09-05; REM draws every branch in one colour"},
  "19668926": {"color": "#73A400", "source": "<same as 19668643>"},
  "19669299": {"color": "#73A400", "source": "<same as 19668643>"},
  "19672327": {"color": "#73A400", "source": "<same as 19668643>"},
  "58433":  {"color": "#00B300", "source": "operator GTFS routes.txt route_color; STM route 1 Ligne 1 - Verte, https://www.stm.info/sites/default/files/gtfs/gtfs_stm.zip, feed_version 20260805110000, retrieved 2026-09-05"},
  "270251": {"color": "#D95700", "source": "operator GTFS routes.txt route_color; STM route 2 Ligne 2 - Orange, <same feed>"},
  "270252": {"color": "#FFD900", "source": "operator GTFS routes.txt route_color; STM route 4 Ligne 4 - Jaune, <same feed>"},
  "270255": {"color": "#0095E6", "source": "operator GTFS routes.txt route_color; STM route 5 Ligne 5 - Bleue, <same feed>"},
  "6504062": {"color": "#002855", "source": "<copy the wvu-prt officialColorSourceByRouteId['1'] string>"}
}
```

Loop Trolley 11558404 is deliberately left out of the JSON.
