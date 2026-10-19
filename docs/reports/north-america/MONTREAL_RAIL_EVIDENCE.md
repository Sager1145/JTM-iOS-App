# Montreal evidence brief: STM metro and REM geometry and colour provenance

Read-only research, 2026-09-05. No file under `app/data/` or `app/public/rail/` was
touched. Every URL below was fetched on 2026-09-05 unless marked otherwise.
Measurements were made with a scratch matcher (nearest surveyed track segment to
each GTFS shape vertex, resampled every 25 m, with a 150 m perpendicular shifted
control per the project's basemap-comparison rule).

## 0. What is blocking what

| Ledger row | Identity | Gate | Registry key that clears it |
|---|---|---|---|
| STM 1, 2, 4, 5 | feed `soci-t-de-transport-de-montr` routes 1/2/4/5 | `geometryReviewByRouteId` = "published STM shapefile is explicitly converted from GTFS shapes.txt" | `acceptOperatorShapeByRouteId` (with evidence) or an `officialNetworkByRouteId` layer |
| REM S1, S2, S3 | feed `rem` routes S1/S2/S3 | `geometryReviewByRouteId` = "independent surveyed REM centreline unavailable" | same two keys |
| Ligne orange/jaune/bleue/verte | OSM relations 270251, 270252, 270255, 58433 (pseudo-feed `osm-soci-t-de-transport-de-mon`) | `osmLineColors` has no entry for the relation | `osmLineColors[<relation>] = {color, source}` |
| REM A1 ×2, A3, A4 | OSM relations 19668643, 19668926, 19672327, 19669299 (pseudo-feed `osm-pulsar`) | same | same |

Mechanics, from the builder: the registry's top-level `osmLineColors` map is copied per
relation id into each OSM pseudo-feed as `officialColorByRelation`, and `OsmBuild`
drops any relation without a hex plus a non-empty source string. The audit accepts
any source string that does not contain the words random, generated, default or
fallback; `operator GTFS routes.txt route_color` is the pre-approved string.

Two housekeeping facts:

- `osmLineColors` is empty across the whole registry, and its note says 52 verified
  entries are waiting in `/private/tmp/jtm-na-rail/patches/patch-canada2.json`.
  That directory no longer exists on this machine. The 52 entries are lost unless
  another checkout has them.
- STM's OSM relations and STM's feed routes are the same four railways reached by
  two paths. Whichever path is unblocked first, the other should be folded or
  withheld so the metro is not drawn twice. Same for REM (feed S1/S2/S3 vs the four
  osm-pulsar relations).

## 1. Geometry: what surveyed sources actually exist

### 1.1 STM metro lines 1, 2, 4, 5

No independently surveyed geometry exists in any open catalogue. The network is
entirely underground, and no published survey sees it.

| Source | Publisher, licence | Type | Verdict |
|---|---|---|---|
| Tracés des lignes de bus et de métro. Landing https://donnees.montreal.ca/dataset/stm-traces-des-lignes-de-bus-et-de-metro, download https://www.stm.info/sites/default/files/gtfs/stm_sig.zip | STM, CC BY 4.0 (https://www.donneesquebec.ca/licence/#cc-by) | Route centreline, NAD83 MTM 8 | Not independent. The dataset text reads, verbatim: "Les lignes (shapes.txt) et arrêts (stops.txt) contenus dans le fichier GTFS de la STM sont disponibles en format shapefile de façon à faciliter l'intégration dans les systèmes d'information géospatiaux (SIG)." This is the registry's existing block reason, now quoted at source. |
| Voies ferrées 3D, https://donnees.montreal.ca/dataset/voies-ferrees-3d (SHP `voies-ferrees-2020.zip`, GPKG `voies-ferrees-2020.gpkg`) | Ville de Montréal, Division de la géomatique, CC BY 4.0 | Track graph, photogrammetric, NAD83 CSRS MTM 8, ±30–40 cm planimetric, source "Photo aérienne 2020, CMM", 3,493 track features, agglomeration only | Does not see the metro. Only 2 features are typed Tunnel (both at Central Station, "Déduit"). STM GTFS shapes 1/2/4/5 measured against it: 0–2 % of vertices within 15 m, i.e. coincidental crossings only. |
| Réseau ferroviaire, https://www.donneesquebec.ca/recherche/dataset/reseau-ferroviaire (WFS `ms:reseau_chfer_qc`, the layer the project already uses as `quebec-mtq`) | MTMD/MTQ, CC BY 4.0 | Track graph, derived from the federal geobase | No metro features at all (12,653 features fetched; STM shapes match 1–5 %). |
| NRWN QC 2.0, https://ftp.maps.canada.ca/pub/nrcan_rncan/vector/geobase_nrwn_rfn/qc/nrwn_rfn_qc_shp_en.zip | NRCan, Open Government Licence – Canada, dataset last modified 2021-05-19, files dated 2016-06-06 | Track graph, 10,757 QC track segments | No metro (1–2 %). |
| Montreal open-data catalogue searched for métro, STM, REM, ferroviaire (17/8/4/2 hits) | | | Every other hit is CSV statistics, incident logs, or planning schematics (Schéma d'aménagement – Transport; Vision 2050 du réseau structurant). None is a survey. |

Recommendation for STM: this is the exact case the builder's own comment reserves
`acceptOperatorShapeByRouteId` for ("no official or independent survey exists, or is
ever likely to exist, for this specific route"), with the LA Metro route 802 entry as
precedent. Suggested evidence text per route:

> STM GTFS feed (https://www.stm.info/sites/default/files/gtfs/gtfs_stm.zip,
> feed_version 20260805110000); the only published STM geometry
> (donnees.montreal.ca stm-traces-des-lignes-de-bus-et-de-metro) states it is the
> GTFS shapes.txt re-exported as a shapefile, and no independent survey sees the
> tunnels: Ville de Montréal Voies ferrées 3D (2020 photogrammetry), MTQ Réseau
> ferroviaire and NRCan NRWN QC each place 0–5 % of the route's vertices within
> 15 m, checked 2026-09-05. The operator's own shape is accepted as the alignment.

If the OSM relations are preferred instead (the TTC pattern), note there is no
survey to validate them against, so the `osmRelationEvidenceByRouteId` text
cannot quote a fit the way the Toronto entries do.

### 1.2 REM A1 / A3 / A4 (feed routes S2 / S3 / S1)

No complete independent centreline exists, but two independent surveys cover the
re-used Deux-Montagnes corridor and part of the island. Nothing covers the
Champlain Bridge and Brossard segment or the new elevated guideway at the western
end of A3.

Measured 2026-09-05, one GTFS shape per route, 25 m samples, ≤15 m counted as a
match, with the 150 m shifted control in brackets:

| Route | km | vs NRWN QC 2.0 (2016, pre-REM track) | vs Ville de Montréal 2020 photogrammetry |
|---|---|---|---|
| S1 (A4 Deux-Montagnes – A1 Brossard) | 45.7 | median 6 m, 67 % ≤15 m [control 2 %] | median 77 m, 49 % [3 %] |
| S3 (A3 Anse-à-l'Orme – A1 Brossard) | 47.5 | median 8 m, 55 % [2 %] | median 3 m, 62 % [3 %] |
| S2 (Bois-Franc – A1 Brossard) | 16.0 | 13 % [2 %] | 12 % [2 %] |

Reading: the NRWN 2016 layer holds the former exo Deux-Montagnes line including the
Mont-Royal tunnel and the Central Station approach, which REM rebuilt on the same
right-of-way, so two-thirds of S1 has an independent reference at a 6 m median.
The city's 2020 aerial survey caught the corridor mid-conversion: nine features are
tagged "En construction" (the longest, 5.0 km, runs along the Mont-Royal to
Bois-Franc stretch), and the probes at Bois-Franc, Du Ruisseau and Sunnybrooke
found no track within 300 m, so the pre-conversion rails had already been lifted
when the photo was flown. The A3 guideway west of Bois-Franc follows the old CN
Doney spur, which both layers carry. The unmatched remainder is off-island
(Champlain Bridge, Brossard, the Laval and Deux-Montagnes end in the city layer
only) plus the new structures.

Other sources checked and rejected:

- MTQ Réseau ferroviaire: only 54 of its features carry REM/CDPQ Infra attribution,
  all classed Épi/Évitement, état Inexploité, named Doney and St-Francois
  Industrial. They are reassigned freight spurs, not the guideway. The
  Deux-Montagnes corridor itself is absent from the current MTQ layer (0 features
  within 400 m of Deux-Montagnes, Sunnybrooke, Bois-Franc, Du Ruisseau, Mont-Royal).
- REM GTFS shapes.txt (https://gtfs.gpmmom.ca/gtfs/gtfs.zip, feed_version 20260520):
  operator-published, same disqualification as STM.
- rem.info "Cartes" and "Documentation" (https://rem.info/fr/albums/cartes,
  https://rem.info/fr/documentation): illustrative maps, no download, no CRS.
- ARTM Équipements métropolitains (Données Québec): points only.
- BAPE / CDPQ Infra filings: located by title only, not opened; PDF drawings at best.
- CMM Observatoire georeferenced data: HTTP 403 to automated fetch, not verified.

Recommendation for REM: the builder's comment on the review gate describes exactly
this outcome, "a railway drawn from its operator's own alignment, measured against an
independent reference and shipped with the disagreement recorded". Accept the REM
GTFS shapes via `acceptOperatorShapeByRouteId` with the two measurements quoted, and
state that no survey covers Champlain Bridge to Brossard. Suggested text for S1:

> REM GTFS feed (https://gtfs.gpmmom.ca/gtfs/gtfs.zip, feed_version 20260520); the
> S1 shape measured 2026-09-05 at 25 m resample against NRCan NRWN QC 2.0 track (the
> pre-REM Deux-Montagnes line and Mont-Royal tunnel it was rebuilt on): median 6 m,
> 67 % of 1,257 samples within 15 m, a 150 m shifted control returning 2 %; and
> against Ville de Montréal Voies ferrées 3D (2020 photogrammetry, ±30–40 cm):
> 49 % within 15 m, the corridor north of Mont-Royal captured mid-conversion as
> "En construction". No published survey covers the Champlain Bridge and Brossard
> segment; MTQ Réseau ferroviaire carries only reassigned CN spurs under REM.

The S2 numbers are low because that pattern is mostly tunnel plus the bridge; cite
the S1 and S3 fits for the shared trunk.

## 2. Colour: the operator-published values and how to cite them

### 2.1 What the operators publish

GTFS routes.txt, read directly from each operator's own feed on 2026-09-05:

| Line | Feed, feed_version | route_id | route_color |
|---|---|---|---|
| STM Ligne 1 – Verte | https://www.stm.info/sites/default/files/gtfs/gtfs_stm.zip, 20260805110000 | 1 | 00B300 |
| STM Ligne 2 – Orange | same | 2 | D95700 |
| STM Ligne 4 – Jaune | same | 4 | FFD900 |
| STM Ligne 5 – Bleue | same | 5 | 0095E6 |
| REM (all branches) | https://gtfs.gpmmom.ca/gtfs/gtfs.zip, 20260520 | S1, S3 | 73A400 |
| REM (all branches) | same | S2 | 72A300 |

Brand and wayfinding assets, for comparison (retrieved 2026-09-05; STM's live site
serves a bot-challenge page, so STM's own files were read through the Internet
Archive, snapshots 2026-04-12 to 2026-08-14):

| Line | STM site CSS (favourites swatch) | STM sprite PNG | STM plan_reseau.pdf legend | ARTM Plan métropolitain 2025 PDF, line stroke |
|---|---|---|---|---|
| 1 Verte | 008E4F | 009A3E | 009640 | 00A650 |
| 2 Orange | F08123 | EE7D00 | EF7C00 | F5821F |
| 4 Jaune | FFE400 | FFE300 | FFDD00 | FFDD00 |
| 5 Bleue | 0083CA | 009EE2 | 0075BE | 007DC5 |

Assets: STM CSS `https://www.stm.info/sites/default/files/css/css_vkp8_BiVBaJF4STdPFhlsfFulUedIJW3Mo8Ocw1SqGE.css`
(selectors `.form-item-metro-favorites-{green,orange,yellow,blue}-metro-line-is-a-favorite label:before`);
sprites `https://www.stm.info/sites/all/themes/stm/img/ligne_{verte,orange,jaune,bleue}.png`;
map `https://www.stm.info/sites/default/files/media/Stminfo/images/plan_reseau.pdf`;
ARTM `https://www.artm.quebec/wp-content/uploads/2025/12/06_PlanMetropolitain_Noir_2025_36x36_Outlined_2025-12-03-1.pdf`
(linked from https://www.artm.quebec/signaletique-metropolitaine/).

REM: site brand token `#72a300` (`.bg-primary-limeade`, `.bg--primary-base` in
`https://rem.info/sites/default/files/css/css_WEZBwNIPq6uSVq5anwfCTikWIZ9DX1CFsCSMGTS4KXk.css?delta=1&language=fr&theme=ram`);
in-service line trace `#80bc00` in the same CSS (`.partial--live-network-state-map … span.in-service .line-vector path#svg_2{fill:#80bc00}`)
and in `https://rem.info/themes/custom/ram/_assets/images/svg/icon/station/icon-trace-verte-en-service.svg`;
ARTM plan stroke for Ligne A `82C341`. REM draws A1, A2, A3 and A4 in one colour on
its own map and on ARTM's.

Observation that decides the template: outside GTFS, STM's own assets do not agree
with each other on any line (four different greens, four oranges, three blues), and
REM's site uses three greens for three purposes. The GTFS route_color is the one
value each operator publishes explicitly as "this route's colour".

### 2.2 Recommended pattern

Cite the operator's own GTFS routes.txt route_color for the OSM relation, exactly as
the feed-built line of the same operator already does. Three reasons:

1. It is the project's pre-approved source string, so the audit passes without a
   new rule.
2. A railway reached by both paths gets one colour. If the STM feed route and the
   STM OSM relation were coloured from different assets, the same tunnel would
   change colour depending on which builder drew it.
3. It is machine-readable and versioned (feed_version), so the citation is
   reproducible; brand PDFs and CSS are not.

Use a brand or wayfinding asset only when route_color is blank, and then cite the
selector or SVG attribute, as the Alaska Railroad, Seattle Monorail and WVU PRT
entries already do.

### 2.3 Proposed registry entries

Drop-in for `osmLineColors` in `app/scripts/railway/na-feeds.json`. Source strings
avoid the audit's forbidden words.

```json
"osmLineColors": {
  "58433":  {"color": "#00B300", "source": "operator GTFS routes.txt route_color; STM route 1 Ligne 1 - Verte, https://www.stm.info/sites/default/files/gtfs/gtfs_stm.zip, feed_version 20260805110000, retrieved 2026-09-05"},
  "270251": {"color": "#D95700", "source": "operator GTFS routes.txt route_color; STM route 2 Ligne 2 - Orange, https://www.stm.info/sites/default/files/gtfs/gtfs_stm.zip, feed_version 20260805110000, retrieved 2026-09-05"},
  "270252": {"color": "#FFD900", "source": "operator GTFS routes.txt route_color; STM route 4 Ligne 4 - Jaune, https://www.stm.info/sites/default/files/gtfs/gtfs_stm.zip, feed_version 20260805110000, retrieved 2026-09-05"},
  "270255": {"color": "#0095E6", "source": "operator GTFS routes.txt route_color; STM route 5 Ligne 5 - Bleue, https://www.stm.info/sites/default/files/gtfs/gtfs_stm.zip, feed_version 20260805110000, retrieved 2026-09-05"},
  "19668643": {"color": "#73A400", "source": "operator GTFS routes.txt route_color; REM routes S1 and S3 (S2 publishes 72A300, one step off), https://gtfs.gpmmom.ca/gtfs/gtfs.zip, feed_version 20260520, retrieved 2026-09-05; REM draws every branch in one colour on rem.info and on ARTM's Plan métropolitain"},
  "19668926": {"color": "#73A400", "source": "<same as 19668643>"},
  "19669299": {"color": "#73A400", "source": "<same as 19668643>"},
  "19672327": {"color": "#73A400", "source": "<same as 19668643>"}
}
```

Relation to name map: 58433 Ligne verte vers Honoré-Beaugrand; 270251 Ligne orange
vers Montmorency; 270252 Ligne jaune vers Berri-UQAM; 270255 Ligne bleue vers
Saint-Michel; 19668643 REM A1 Deux-Montagnes → Brossard; 19668926 REM A1
Anse-à-l'Orme → Brossard; 19669299 REM A4 Brossard → Deux-Montagnes; 19672327 REM A3
Brossard → Anse-à-l'Orme.

### 2.4 How it reads in ca-2025.sources.md

Suggested paragraph, matching the file's existing voice:

> Route colours come from each operator's own GTFS routes.txt route_color, whether
> the line is built from the feed or from an audited OpenStreetMap relation of the
> same operator; OSM's colour tag is never read. STM metro lines carry the colours
> STM publishes in feed_version 20260805110000 (1 verte 00B300, 2 orange D95700,
> 4 jaune FFD900, 5 bleue 0095E6). REM publishes one colour for every branch
> (73A400, feed_version 20260520), which is also how rem.info and ARTM's Plan
> métropolitain draw it. Where a feed leaves route_color blank the registry names
> the operator asset the colour was read from and the selector or attribute it
> appears in.

### 2.5 Template for the other 81 colour-gated lines

For each blocked relation or route:

1. Open the operator's own GTFS feed (URL and feed_version from the registry entry
   or the MobilityData mirror). If route_color is set, write
   `operator GTFS routes.txt route_color; <operator> route <id> <name>, <feed url>, feed_version <v>, retrieved <date>`.
2. If route_color is blank, read the operator's map SVG/PDF or site CSS and cite the
   file URL plus the selector, path id or legend element; or a government GIS
   renderer's colour attribute with its service URL. Record the retrieval date.
3. Never write random, generated, default or fallback in the source string.
4. Where the same railway also exists as a feed route, use the identical hex so both
   paths draw one colour.

## 3. Uncertainties

- STM live pages and PDFs could not be fetched directly (PerimeterX challenge); the
  STM brand values come from archive.org mirrors of STM's own files. The GTFS feed
  itself was fetched live from stm.info.
- No standalone STM or REM graphic-standards document with Pantone/CMYK values was
  found; existence not verified.
- The CMM georeferenced-data page and the BAPE technical annexes were not opened.
- The MTQ WFS returned 12,653 features here; the earlier agent pass counted 25,306,
  probably multipart parts. The absence findings hold either way.
- The scratch matcher lives in this session's scratchpad (`matcher.py`, `shpprobe.py`)
  and will be wiped; the method is fully described above and the project's
  `validate-ttc-subway-osm.py` implements the same measurement.
