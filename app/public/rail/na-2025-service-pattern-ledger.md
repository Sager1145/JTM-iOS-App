# North America service-pattern display-rule ledger — 2026-09-09

Every line in `us-2025.json` and `ca-2025.json` was checked against (a) the station sequences, loop flags and branch/direction notes of the four rail-transit analysis datasets (20 + 11 + 18 + 4 cities) and (b) package-only rules: open loop, duplicate-coordinate stations, branch disconnected from its trunk, station set that is a strict subset of a same-colour sibling, repeated station names, consecutive stops under 60 m.
Third batch (2026-09-09, after downloading the four feeds' GTFS + official networks and rebuilding them in a scratch dir): 57 of the 65 lines of MBTA/MTA/Miami-Dade/TriMet are identical between the corrected registry build and the shipped package; the D 155 St removal was reverted and "Avenue N" restored (see rows).

Verdicts: CORRECTED = fixed by `na-service-pattern-repairs.json` (see `servicePatternRepair` in the package); LEDGER = real finding not fixable without source geometry; bundle-diff verdicts: naming_noise / bundle_partial_frame / bundle_stale_or_wrong = dataset differences that are not app defects; G-rule notes explain flagged-but-acceptable cases.

435 lines. Columns: line, stations/segments, verdict.


## US

| line | operator | st/seg | verdict |
|---|---|---|---|
| ace-ace | Altamont Corridor Express | 10/9 | bundle match consistent; generic rules pass |
| mckinney-avenue-trolley-m-line-ob | McKinney Avenue Transit Authority (M-Line) | 23/22 | CORRECTED(mergeStations,mergeStations) / bundle-diff: bundle_partial_frame — bundle asserts only mline_north_circuit (n=14, cov_pat 0.83); the 25-station app line spans both north+south circuits/branches, so bundle is not full-line evide / G7: CityPlace & McKinney->Cole & West Village:59m — merged |
| mckinney-avenue-trolley-m-line-ob-b1 | McKinney Avenue Transit Authority (M-Line) | 7/6 | bundle-diff: bundle_partial_frame — bundle covers only 42% of pattern (cov_pat 0.42); branch is a directional segment of a larger circuit the single bundle can't fully describe. |
| mckinney-avenue-trolley-m-line-ob-b2 | McKinney Avenue Transit Authority (M-Line) | 9/8 | bundle-diff: bundle_partial_frame — bundle covers only 38% of pattern (cov_pat 0.38); same circuit/branch structure issue as ob-b1. |
| new-orleans-rta-12 | NORTA | 56/55 | bundle-diff: bundle_partial_frame — bundle complete=False, western_visible_anchors n=6 only, cov_app 0.12 — explicitly partial reference. |
| new-orleans-rta-12-b1 | NORTA | 7/6 | bundle match consistent; generic rules pass |
| new-orleans-rta-12-b2 | NORTA | 3/2 | no bundle assertions; generic rules pass |
| new-orleans-rta-12-b3 | NORTA | 3/2 | no bundle assertions; generic rules pass |
| new-orleans-rta-47 | NORTA | 25/24 | bundle-diff: bundle_partial_frame — bundle complete=False, canal_anchors n=4 only. |
| new-orleans-rta-48 | NORTA | 25/24 | bundle-diff: bundle_partial_frame — bundle complete=False, canal_anchors n=4 only. |
| new-orleans-rta-49 | NORTA | 8/7 | bundle match consistent; generic rules pass |
| smart-smart | Sonoma-Marin Area Rail Transit | 14/13 | no bundle assertions; generic rules pass |
| amtrak-acela | Amtrak | 14/13 | CORRECTED(renameStation,renameStation) / bundle-diff: naming_noise — After renaming the two 'Boston' rows to South Station / Back Bay, remaining 'extra' stations (New York Penn Station, Philadelphia, Wilmington, Newark...) are th / G4: station set ⊂ same-colour sibling (service variant; one render group) — OK |
| amtrak-adirondack-us | Amtrak | 16/15 | no bundle assertions; generic rules pass |
| amtrak-amtrak-cascades-us | Amtrak | 17/16 | bundle match consistent; generic rules pass |
| amtrak-amtrak-hartford-line | Amtrak | 9/8 | CORRECTED(renameStation) / bundle-diff: naming_noise — App has two generically-named 'New Haven' stations; bundle nhv:hartford:full shows they are 'Union Station' and 'New Haven–State Street', two distinct real stat / G4: station set ⊂ same-colour sibling (service variant; one render group) — OK |
| amtrak-amtrak-mardi-gras-service | Amtrak | 6/5 | no bundle assertions; generic rules pass |
| amtrak-borealis | Amtrak | 13/12 | no bundle assertions; generic rules pass |
| amtrak-capitol-corridor | Amtrak | 18/17 | bundle match consistent; generic rules pass |
| amtrak-cardinal | Amtrak | 32/31 | bundle match consistent; generic rules pass |
| amtrak-carl-sandburg | Amtrak | 10/9 | bundle match consistent; generic rules pass |
| amtrak-carolinian | Amtrak | 28/27 | bundle match consistent; generic rules pass |
| amtrak-city-of-new-orleans | Amtrak | 20/19 | bundle match consistent; generic rules pass |
| amtrak-crescent | Amtrak | 35/34 | bundle match consistent; generic rules pass |
| amtrak-lincoln-service | Amtrak | 11/10 | G4: station set ⊂ same-colour sibling (service variant; one render group) — OK |
| amtrak-southwest-chief | Amtrak | 32/31 | bundle match consistent; generic rules pass |
| amtrak-empire-builder | Amtrak | 41/40 | bundle match consistent; generic rules pass |
| amtrak-empire-builder-b1 | Amtrak | 6/5 | no bundle assertions; generic rules pass |
| amtrak-empire-service | Amtrak | 17/16 | no bundle assertions; generic rules pass |
| amtrak-ethan-allen-express | Amtrak | 15/14 | no bundle assertions; generic rules pass |
| amtrak-heartland-flyer | Amtrak | 7/6 | no bundle assertions; generic rules pass |
| amtrak-hiawatha-service | Amtrak | 5/4 | G4: station set ⊂ same-colour sibling (service variant; one render group) — OK |
| amtrak-keystone-service | Amtrak | 21/20 | no bundle assertions; generic rules pass |
| amtrak-lake-shore-limited | Amtrak | 22/21 | CORRECTED(renameStation,renameStation) / bundle-diff: bundle_partial_frame — Buffalo bundle patterns for this line are 'single-in-image-station' (n=1, complete=False) per city; extras are the app's real Boston-Chicago stations outside ea |
| amtrak-lake-shore-limited-b1 | Amtrak | 5/4 | no bundle assertions; generic rules pass |
| amtrak-lincoln-service-missouri-river-runner | Amtrak | 20/19 | bundle match consistent; generic rules pass |
| amtrak-missouri-river-runner | Amtrak | 10/9 | G4: station set ⊂ same-colour sibling (service variant; one render group) — OK |
| amtrak-northeast-regional | Amtrak | 37/36 | CORRECTED(renameStation,renameStation) / bundle-diff: naming_noise — Bundle frames (Hartford Line / Boston fragments) cover only a short part of the 37-station route; extras are outside the frame or spelled differently (Richmond  |
| amtrak-northeast-regional-b1 | Amtrak | 3/2 | no bundle assertions; generic rules pass |
| amtrak-northeast-regional-b2 | Amtrak | 9/8 | CORRECTED(renameStation) / bundle-diff: naming_noise — Same New Haven Union Station / State Street naming collapse as hartford-line. |
| amtrak-northeast-regional-b3 | Amtrak | 7/6 | no bundle assertions; generic rules pass |
| amtrak-pacific-surfliner | Amtrak | 29/28 | no bundle assertions; generic rules pass |
| amtrak-palmetto | Amtrak | 23/22 | bundle match consistent; generic rules pass |
| amtrak-pennsylvanian | Amtrak | 17/16 | no bundle assertions; generic rules pass |
| amtrak-piedmont | Amtrak | 9/8 | G4: station set ⊂ same-colour sibling (service variant; one render group) — OK |
| amtrak-silver-meteor | Amtrak | 33/32 | bundle match consistent; generic rules pass |
| amtrak-valley-flyer | Amtrak | 12/11 | CORRECTED(renameStation) / bundle-diff: bundle_partial_frame — Bundle nhv:hartford:full (9 stops, New Haven-Springfield) is shorter than the real Valley Flyer route which extends to Holyoke/Northampton/Greenfield; extras ar |
| amtrak-vermonter | Amtrak | 30/29 | bundle-diff: bundle_partial_frame — Same nhv:hartford:full short trunk vs the much longer real Vermonter (NYC-St. Albans); extras are legitimate stations beyond the bundle frame. |
| amtrak-wolverine | Amtrak | 15/14 | bundle match consistent; generic rules pass |
| amtrak-shore-line-east | Shore Line East | 11/10 | CORRECTED(renameStation) / bundle-diff: naming_noise — Same New Haven duplicate-name issue; bundle nhv:sle:full names the two stops Union Station and New Haven–State Street. |
| bart-blue | Bay Area Rapid Transit | 18/17 | bundle match consistent; generic rules pass |
| bart-green | Bay Area Rapid Transit | 22/21 | bundle match consistent; generic rules pass |
| bart-grey | Bay Area Rapid Transit | 2/1 | bundle-diff: bundle_partial_frame — app's 2-station OAK Airport Connector shuttle (Coliseum-OAK) was matched against the full BART Blue Line pattern (n=18); wrong-scope bundle, not evidence agains |
| bart-orange | Bay Area Rapid Transit | 21/20 | bundle match consistent; generic rules pass |
| bart-red | Bay Area Rapid Transit | 24/23 | bundle match consistent; generic rules pass |
| bart-yellow | Bay Area Rapid Transit | 28/27 | bundle-diff: bundle_stale_or_wrong — BART's own line is officially named Antioch - SFO/Millbrae; Millbrae is a real alternating terminus the bundle (n=27) omits. |
| brightline-trains-llc-blfm | Brightline | 6/5 | bundle match consistent; generic rules pass |
| caltrain-local-weekday | Caltrain | 30/29 | bundle-diff: bundle_partial_frame — bundle complete=False, only 3 named anchors, cov_app 0.13. |
| capital-metro-550 | Capital Metro | 10/9 | no bundle assertions; generic rules pass |
| cincinnati-metro-100 | METRO | 18/18 loop | bundle-diff: naming_noise — app_extra/app_missing are the same 5-6 physical stops under full official names (e.g. 'WASHINGTON PARK Station - 12th & Race' vs 'Washington Park', 'FOUNTAIN SQ |
| connecticut-transit-hartford-line | Conn DOT | 9/8 | CORRECTED(renameStation) / bundle-diff: naming_noise — Same New Haven duplicate-name issue as amtrak hartford-line. |
| cta-blue-line | Chicago Transit Authority | 33/32 | bundle-diff: bundle_partial_frame — Bundle pattern chicago.pattern.blue_reference has only 19 of ~33 real stations (named '_reference'); extras are real O'Hare/Forest Park branch stations. |
| cta-brown-line | Chicago Transit Authority | 26/25 | bundle-diff: bundle_partial_frame — Bundle pattern is a partial 'brown_loop' set; extras are real Brown Line stations (Kimball branch, shared Belmont/Purple stations) outside the frame. |
| cta-green-line | Chicago Transit Authority | 28/27 | bundle-diff: bundle_partial_frame — Bundle 'green_common' + tiny branch fragments; extras are real Lake/Ashland-63rd branch stations. |
| cta-green-line-b1 | Chicago Transit Authority | 3/2 | bundle match consistent; generic rules pass |
| cta-orange-line | Chicago Transit Authority | 15/14 | bundle-diff: bundle_partial_frame — Bundle 'orange_stem'+'orange_loop' partial (cov_pat=1.0 but bundle itself short); extras are real Loop-served stations. |
| cta-pink-line | Chicago Transit Authority | 21/20 | bundle-diff: bundle_partial_frame — Bundle 'pink_branch_reference'+'pink_loop' partial fragments; extras are real shared Green/Loop stations. |
| cta-purple-line | Chicago Transit Authority | 25/24 | bundle-diff: bundle_partial_frame — Bundle 'purple_express_loop' (n=12) omits the full Evanston branch/Brown-shared segment; extras are real Purple Line stations. |
| cta-red-line | Chicago Transit Authority | 33/32 | bundle-diff: bundle_partial_frame — Bundle 'red_mosaic' (n=17) is a partial sample vs the real ~33-station Red Line; extras are real stations. |
| cta-yellow-line | Chicago Transit Authority | 3/2 | no bundle assertions; generic rules pass |
| dallas-area-rapid-transit-da-silver | Dallas Area Rapid Transit | 10/9 | no bundle assertions; generic rules pass |
| dallas-area-rapid-transit-da-tre | Dallas Area Rapid Transit | 10/9 | bundle-diff: bundle_partial_frame — bundle tre_dallas has only 2 endpoint anchors; app_extra are the 8 real intermediate TRE stations. |
| dallas-area-rapid-transit-da-blue | Dallas Area Rapid Transit | 22/21 | bundle-diff: bundle_partial_frame — bundle is a 7-station common-trunk anchor set, cov_app 0.27; not a full-line pattern. |
| dallas-area-rapid-transit-da-green | Dallas Area Rapid Transit | 24/23 | bundle-diff: bundle_partial_frame — bundle green_cbd_northwest n=10 anchor set, cov_app 0.42. |
| dallas-area-rapid-transit-da-orange | Dallas Area Rapid Transit | 31/30 | bundle-diff: bundle_partial_frame — bundle orange_cbd_northwest n=7 anchor set, cov_app 0.23. |
| dallas-area-rapid-transit-da-red | Dallas Area Rapid Transit | 25/24 | bundle-diff: bundle_partial_frame — bundle red common-trunk n=7 anchor set, cov_app 0.24. |
| dallas-area-rapid-transit-da-620 | Dallas Area Rapid Transit | 6/5 | bundle match consistent; generic rules pass |
| denton-county-transportation-a-train | Denton County Transportation Authority | 6/5 | no bundle assertions; generic rules pass |
| detroit-people-mover-dpm | Detroit Transportation Corporation | 13/13 loop | bundle-diff: naming_noise — App already contains 'Michigan' station (us-official-michigan) verified in current us-2025.json; the B2_APP_MISSING flag is a stale/loop-rotation matching artif |
| florida-department-of-transp-sunrail | Florida Department of Transportation | 17/16 | bundle match consistent; generic rules pass |
| hillsborough-area-regional-t-sky | Tampa International Airport | 3/2 | no bundle assertions; generic rules pass |
| hillsborough-area-regional-t-800 | Hillsborough Area Regional Transit | 11/10 | bundle match consistent; generic rules pass |
| houston-metro-700 | Metropolitan Transit Authority of Harris County | 25/24 | bundle-diff: bundle_partial_frame — bundle red_visible n=10 anchor set (complete=True but cov_app 0.4); full Red Line has 25 real stations. |
| houston-metro-800 | Metropolitan Transit Authority of Harris County | 9/8 | bundle-diff: bundle_partial_frame — bundle green_eastbound n=4 anchor set, cov_app 0.44. |
| houston-metro-900 | Metropolitan Transit Authority of Harris County | 10/9 | bundle-diff: bundle_partial_frame — bundle (mismatched to green_westbound) n=4 anchor set, cov_app 0.4. |
| houston-metro-800-b1 | Metropolitan Transit Authority of Harris County | 4/3 | bundle match consistent; generic rules pass |
| houston-metro-900-b1 | Metropolitan Transit Authority of Harris County | 4/3 | bundle match consistent; generic rules pass |
| king-county-metro-first-hill-streetcar | City of Seattle | 10/9 | bundle-diff: naming_noise — 'Broadway & Pike-Pine' vs 'Broadway & Pike–Pine' (dash variant) and 'Capitol Hill' vs 'Broadway & Denny' are the same northern terminus under neighborhood vs st |
| king-county-metro-south-lake-union-streetcar | City of Seattle | 7/6 | bundle match consistent; generic rules pass |
| king-county-metro-south-lake-union-streetcar-b1 | City of Seattle | 4/3 | bundle match consistent; generic rules pass |
| los-angeles-county-metropoli-metro-b-line | Metro - Los Angeles | 14/13 | bundle-diff: bundle_partial_frame — bundle b_downtown n=3 anchor set, cov_app 0.21. |
| los-angeles-county-metropoli-metro-d-line | Metro - Los Angeles | 11/10 | bundle-diff: bundle_partial_frame — bundle b_downtown n=3 anchor set (shared trunk w/ B line), cov_app 0.27. |
| los-angeles-county-metropoli-metro-a-line | Metro - Los Angeles | 47/46 | bundle-diff: bundle_partial_frame — bundle a_connector n=3 anchor set, cov_app 0.06 (line has 47 real stations). |
| los-angeles-county-metropoli-metro-a-line-b1 | Metro - Los Angeles | 3/2 | no bundle assertions; generic rules pass |
| los-angeles-county-metropoli-metro-c-line | Metro - Los Angeles | 12/11 | no bundle assertions; generic rules pass |
| los-angeles-county-metropoli-metro-e-line | Metro - Los Angeles | 29/28 | bundle-diff: bundle_partial_frame — bundle e_east n=5 anchor set, cov_app 0.21. |
| los-angeles-county-metropoli-metro-k-line | Metro - Los Angeles | 13/12 | no bundle assertions; generic rules pass |
| maryland-transit-administrat-brunswick-washington | Maryland Transit Administration | 17/16 | bundle match consistent; generic rules pass |
| maryland-transit-administrat-brunswick-washington-b1 | Maryland Transit Administration | 3/2 | no bundle assertions; generic rules pass |
| maryland-transit-administrat-brunswick-washington-b2 | Maryland Transit Administration | 2/1 | no bundle assertions; generic rules pass |
| maryland-transit-administrat-brunswick-washington-b3 | Maryland Transit Administration | 2/1 | no bundle assertions; generic rules pass |
| maryland-transit-administrat-camden-washington | Maryland Transit Administration | 12/11 | no bundle assertions; generic rules pass |
| maryland-transit-administrat-penn-washington | Maryland Transit Administration | 13/12 | no bundle assertions; generic rules pass |
| maryland-transit-administrat-2-metro-subwaylink | Maryland Transit Administration | 14/13 | bundle match consistent; generic rules pass |
| mbta-blue-line | MBTA | 12/11 | bundle match consistent; generic rules pass |
| mbta-capeflyer | Cape Cod Regional Transit Authority | 8/7 | bundle match consistent; generic rules pass |
| mbta-fairmount-line | MBTA | 9/8 | bundle match consistent; generic rules pass |
| mbta-fall-river-new-bedford-line | MBTA | 13/12 | bundle match consistent; generic rules pass |
| mbta-fall-river-new-bedford-line-b1 | MBTA | 3/2 | bundle match consistent; generic rules pass |
| mbta-fitchburg-line | MBTA | 18/17 | bundle-diff: bundle_partial_frame — bundle complete=False (n=17); 1 extra stop ('Silver Hill') not evidence of defect. |
| mbta-foxboro-event-service | MBTA | 8/7 | bundle match consistent; generic rules pass |
| mbta-framingham-worcester-line | MBTA | 18/17 | bundle match consistent; generic rules pass |
| mbta-greenbush-line | MBTA | 10/9 | bundle match consistent; generic rules pass |
| mbta-haverhill-line | MBTA | 15/14 | bundle match consistent; generic rules pass |
| mbta-kingston-line | MBTA | 10/9 | bundle match consistent; generic rules pass |
| mbta-lowell-line | MBTA | 8/7 | bundle match consistent; generic rules pass |
| mbta-needham-line | MBTA | 12/11 | bundle match consistent; generic rules pass |
| mbta-newburyport-rockport-line | MBTA | 13/12 | bundle match consistent; generic rules pass |
| mbta-newburyport-rockport-line-b1 | MBTA | 6/5 | bundle match consistent; generic rules pass |
| mbta-orange-line | MBTA | 20/19 | bundle match consistent; generic rules pass |
| mbta-providence-stoughton-line | MBTA | 14/13 | CORRECTED(dropStations) / bundle match consistent; generic rules pass |
| mbta-providence-stoughton-line-b2 | MBTA | 3/2 | bundle match consistent; generic rules pass |
| mbta-red-line | MBTA | 18/17 | bundle match consistent; generic rules pass |
| mbta-red-line-b1 | MBTA | 5/4 | bundle match consistent; generic rules pass |
| mbta-d | MBTA | 25/24 | bundle match consistent; generic rules pass |
| mbta-e-b1 | MBTA | 2/1 | bundle match consistent; generic rules pass |
| mbta-b | MBTA | 23/22 | CORRECTED(truncateAfter) / bundle-diff: already_repaired — repaired=truncateAfter; remaining extra stop 'Packard's Corner' is a real Green Line B station; bundle complete=None (not asserted complete). |
| mbta-c | MBTA | 20/19 | CORRECTED(truncateAfter) / bundle-diff: already_repaired — repaired=truncateAfter; remaining extra stop 'Saint Mary's Street' is a real Green Line C station; bundle complete=None. |
| mbta-e | MBTA | 25/24 | bundle match consistent; generic rules pass |
| mbta-mattapan-line | MBTA | 8/7 | bundle match consistent; generic rules pass |
| metra-bnsf | Metra | 26/25 | bundle match consistent; generic rules pass |
| metra-me | Metra | 33/32 | bundle-diff: bundle_partial_frame — Bundle splits Metra Electric into 5 short branch fragments (north/south_chicago/mid/blue_island/university_park); extras are real ME stations outside each fragm |
| metra-me-b1 | Metra | 9/8 | bundle-diff: naming_noise — App uses short forms '83rd St.'/'87th St.' for the same physical stations the bundle names '83rd Street-South Chicago'/'87th Street-South Chicago'. |
| metra-me-b2 | Metra | 8/7 | bundle match consistent; generic rules pass |
| metra-me-b3 | Metra | 2/1 | no bundle assertions; generic rules pass |
| metra-milwaukee | Metra | 22/21 | bundle match consistent; generic rules pass |
| metra-milwaukee-2 | Metra | 22/21 | bundle match consistent; generic rules pass |
| metra-ncs | Metra | 18/17 | bundle match consistent; generic rules pass |
| metra-ri | Metra | 24/23 | bundle-diff: bundle_partial_frame — Bundle splits Rock Island into short north/main/beverly/south fragments; extras are real RI stations outside each fragment. |
| metra-ri-b1 | Metra | 4/3 | bundle match consistent; generic rules pass |
| metra-ri-b2 | Metra | 2/1 | no bundle assertions; generic rules pass |
| metra-sws | Metra | 13/12 | bundle-diff: naming_noise — Ledger artifact: 'Palos Park' is present verbatim in app/data/rail/us-2025.json for metra-sws (matches chicago.pattern.sws_reference exactly); no real discrepan |
| metra-union-pacific | Metra | 28/27 | bundle match consistent; generic rules pass |
| metra-union-pacific-2 | Metra | 19/18 | bundle match consistent; generic rules pass |
| metra-up-nw | Metra | 22/21 | bundle match consistent; generic rules pass |
| metra-up-nw-b1 | Metra | 2/1 | no bundle assertions; generic rules pass |
| metra-hc | Metra | 7/6 | bundle match consistent; generic rules pass |
| metro-north-railroad-danbury | Metro-North Railroad | 15/14 | bundle match consistent; generic rules pass |
| metro-north-railroad-harlem | Metro-North Railroad | 38/37 | bundle match consistent; generic rules pass |
| metro-north-railroad-hudson | Metro-North Railroad | 29/28 | bundle match consistent; generic rules pass |
| metro-north-railroad-new-canaan | Metro-North Railroad | 20/19 | bundle match consistent; generic rules pass |
| metro-north-railroad-new-haven | Metro-North Railroad | 32/31 | CORRECTED(renameStation) / bundle match consistent; generic rules pass |
| metro-north-railroad-waterbury | Metro-North Railroad | 8/7 | no bundle assertions; generic rules pass |
| metro-transit-metro-green-line | Metro Transit | 23/22 | bundle match consistent; generic rules pass |
| metro-transit-intercity-tran-s-line | Sound Transit | 9/8 | bundle-diff: naming_noise — 'Seattle' (app) vs 'King Street' (bundle) is the same Seattle Sounder terminus, officially King Street Station. |
| metro-transit-intercity-tran-1-line | Sound Transit | 26/25 | bundle-diff: naming_noise — '5th & Jackson'/'Tukwila Int'l Blvd' are the same physical stations as 'International District/Chinatown'/'Tukwila International Boulevard' under different labe |
| metrolink-91-pv-line | Metrolink Trains | 12/11 | bundle match consistent; generic rules pass |
| metrolink-av-line | Metrolink Trains | 13/12 | no bundle assertions; generic rules pass |
| metrolink-ie-oc-line | Metrolink Trains | 16/15 | no bundle assertions; generic rules pass |
| metrolink-oc-line | Metrolink Trains | 15/14 | no bundle assertions; generic rules pass |
| metrolink-sb-line | Metrolink Trains | 18/17 | no bundle assertions; generic rules pass |
| metrolink-vc-line | Metrolink Trains | 12/11 | no bundle assertions; generic rules pass |
| metropolitan-atlanta-rapid-t-blue | Metropolitan Atlanta Rapid Transit Authority | 15/14 | bundle match consistent; generic rules pass |
| metropolitan-atlanta-rapid-t-gold | Metropolitan Atlanta Rapid Transit Authority | 18/17 | bundle match consistent; generic rules pass |
| metropolitan-atlanta-rapid-t-green | Metropolitan Atlanta Rapid Transit Authority | 9/8 | no bundle assertions; generic rules pass |
| metropolitan-transit-authori-1 | MTA New York City Transit | 38/37 | bundle-diff: bundle_partial_frame — Bundle nyc:pattern:1:7av_local has only 8 of the real ~38 stations; extras are real 1-train stations along Broadway-7Av. |
| metropolitan-transit-authori-2 | MTA New York City Transit | 49/48 | CORRECTED(dropStations) / bundle match consistent; generic rules pass |
| metropolitan-transit-authori-3 | MTA New York City Transit | 34/33 | CORRECTED(dropStations) / bundle match consistent; generic rules pass |
| metropolitan-transit-authori-4 | MTA New York City Transit | 28/27 | CORRECTED(dropStations) / no bundle assertions; generic rules pass |
| metropolitan-transit-authori-42-st-shuttle | MTA New York City Transit | 2/1 | no bundle assertions; generic rules pass |
| metropolitan-transit-authori-5 | MTA New York City Transit | 36/35 | bundle match consistent; generic rules pass |
| metropolitan-transit-authori-5-b2 | MTA New York City Transit | 10/9 | no bundle assertions; generic rules pass |
| metropolitan-transit-authori-6 | MTA New York City Transit | 38/37 | bundle-diff: bundle_partial_frame — Bundle nyc:pattern:6:lex_local has 6 of the real ~38 stations; extras are real Lexington Av Local stations. |
| metropolitan-transit-authori-6x | MTA New York City Transit | 29/28 | bundle-diff: bundle_partial_frame — Same short Lex bundle fragment as line 6; extras are real stations, app's full station list also verified consistent with the 6 line. / G4: station set ⊂ same-colour sibling (service variant; one render group) — OK |
| metropolitan-transit-authori-7 | MTA New York City Transit | 22/21 | bundle match consistent; generic rules pass |
| metropolitan-transit-authori-7x | MTA New York City Transit | 13/12 | CORRECTED(dropStations) / G4: station set ⊂ same-colour sibling (service variant; one render group) — OK / GTFS 2026-09-09 check: current construction-period <7> trips call at 33/40/46 St (100%) and 52/69 St (39%); the permanent express pattern (13 stations) is kept, registry excludes those five |
| metropolitan-transit-authori-a | MTA New York City Transit | 37/36 | CORRECTED(dropStations) / bundle match consistent; generic rules pass |
| metropolitan-transit-authori-a-b1 | MTA New York City Transit | 4/3 | no bundle assertions; generic rules pass |
| metropolitan-transit-authori-a-b2 | MTA New York City Transit | 5/4 | no bundle assertions; generic rules pass |
| metropolitan-transit-authori-b | MTA New York City Transit | 37/36 | bundle-diff: bundle_partial_frame — Verified app's B line (Bedford Park Blvd Bronx Concourse -> 145 St -> 6 Av -> Brighton Beach) matches the real NYC B train route; bundle fragment is just short, / G5: 7 Av — legit distinct stations with identical official names |
| metropolitan-transit-authori-c | MTA New York City Transit | 40/39 | bundle match consistent; generic rules pass |
| metropolitan-transit-authori-d | MTA New York City Transit | 36/35 | CORRECTED(dropStations) / bundle match consistent; generic rules pass / third batch: 155 St restored (82% weekday-daytime call share; only peak-direction rush express skips it) — earlier removal was an error; late-night 4 Av and CPW locals stay excluded |
| metropolitan-transit-authori-e | MTA New York City Transit | 22/21 | bundle-diff: bundle_partial_frame — Bundle nyc:pattern:E:8av_local (n=5) is a short fragment of the real ~28 station E train; extras are real stations. |
| metropolitan-transit-authori-f | MTA New York City Transit | 45/44 | CORRECTED(dropStations) — fourth batch: the 10 Queens Blvd local stations (36 St … 67 Av) are late-night-only (3% weekday-daytime call share, MTA GTFS 2026-09-09); registry excludes G09–G20; the via-53 St branch f-b1 is the current majority routing and stays |
| metropolitan-transit-authori-f-b1 | MTA New York City Transit | 6/5 | LEDGER: via 53 St pattern; keep until GTFS typicality verified / bundle-diff: bundle_partial_frame — Alt F pattern fragment, same partial-frame nature as metropolitan-transit-authori-f. |
| metropolitan-transit-authori-f-b2 | MTA New York City Transit | — | CORRECTED(dropLine) — fourth batch: Queens Plaza–36 St stub existed only through the late-night local pattern |
| metropolitan-transit-authori-franklin-avenue-shuttle | MTA New York City Transit | 4/3 | no bundle assertions; generic rules pass |
| metropolitan-transit-authori-fx | MTA New York City Transit | 39/38 | checked; FX (Culver express, 16 trips/direction) shares the F's current via-53 St routing; "Avenue N" restored |
| metropolitan-transit-authori-g | MTA New York City Transit | 21/20 | bundle match consistent; generic rules pass |
| metropolitan-transit-authori-j | MTA New York City Transit | 30/29 | no bundle assertions; generic rules pass |
| metropolitan-transit-authori-l | MTA New York City Transit | 24/23 | CORRECTED(renameStation,renameStation) / bundle-diff: bundle_partial_frame — Bundle nyc:pattern:L:14th_street (n=5) is a short fragment vs the real ~24 station L train; extras are real Canarsie Line stations. |
| metropolitan-transit-authori-m | MTA New York City Transit | 36/35 | bundle match consistent; generic rules pass |
| metropolitan-transit-authori-n | MTA New York City Transit | 35/34 | bundle-diff: bundle_partial_frame — Bundle N fragments (broadway_express n=3, astoria n=2) are short vs the real ~30 station N route; extras are real stations. / G5: 59 St — renamed: Manhattan row is MTA "Lexington Av/59 St" (R11), Brooklyn row "59 St" (R41) |
| metropolitan-transit-authori-n-b1 | MTA New York City Transit | 7/6 | bundle match consistent; generic rules pass |
| metropolitan-transit-authori-q | MTA New York City Transit | 29/28 | CORRECTED(dropStations) / bundle match consistent; generic rules pass |
| metropolitan-transit-authori-r | MTA New York City Transit | 45/44 | bundle-diff: bundle_partial_frame — Bundle R fragments (broadway_local n=6, queens_blvd_local n=2) are short vs the real ~40 station R route; extras are real stations. / G5: 59 St;36 St — renamed: Manhattan row is MTA "Lexington Av/59 St" (R11), Brooklyn row "59 St" (R41) |
| metropolitan-transit-authori-rockaway-park-shuttle | MTA New York City Transit | 9/8 | no bundle assertions; generic rules pass |
| metropolitan-transit-authori-sir | MTA New York City Transit | 21/20 | bundle match consistent; generic rules pass |
| metropolitan-transit-authori-w | MTA New York City Transit | 23/22 | bundle-diff: bundle_partial_frame — Bundle W fragments (broadway_local n=6, astoria n=2) are short vs the real ~24 station W route; extras are real stations. / third batch: Lexington Av/59 St renamed for consistency with N/R (same station id) |
| metropolitan-transit-authori-z | MTA New York City Transit | 21/20 | G4: station set ⊂ same-colour sibling (service variant; one render group) — OK |
| miami-dade-transit-2600 | Miami-Dade Transit | 22/21 | bundle-diff: bundle_partial_frame — bundle green_gap_infill n=3 anchor set, cov_app 0.14 against a 22-station full Metrorail line. |
| miami-dade-transit-2600-b1 | Miami-Dade Transit | 2/1 | bundle match consistent; generic rules pass |
| miami-dade-transit-mmi | Miami-Dade Transit | 8/8 loop | CORRECTED(closeLoop) / bundle-diff: already_repaired — repaired=closeLoop; the app's 8-stop closed loop vs bundle's 9 (which repeats Government Center to close the loop) is a loop-representation difference, not a re |
| mta-long-island-rail-road-babylon-branch | Long Island Rail Road | 20/19 | no bundle assertions; generic rules pass |
| mta-long-island-rail-road-city-terminal-zone | Long Island Rail Road | 8/7 | bundle match consistent; generic rules pass |
| mta-long-island-rail-road-far-rockaway-branch | Long Island Rail Road | 16/15 | bundle match consistent; generic rules pass |
| mta-long-island-rail-road-greenport-service | Long Island Rail Road | 7/6 | no bundle assertions; generic rules pass |
| mta-long-island-rail-road-hempstead-branch | Long Island Rail Road | 15/14 | bundle match consistent; generic rules pass |
| mta-long-island-rail-road-long-beach-branch | Long Island Rail Road | 15/14 | no bundle assertions; generic rules pass |
| mta-long-island-rail-road-montauk-branch | Long Island Rail Road | 19/18 | no bundle assertions; generic rules pass |
| mta-long-island-rail-road-oyster-bay-branch | Long Island Rail Road | 13/12 | bundle match consistent; generic rules pass |
| mta-long-island-rail-road-port-jefferson-branch | Long Island Rail Road | 25/24 | bundle match consistent; generic rules pass |
| mta-long-island-rail-road-ronkonkoma-branch | Long Island Rail Road | 23/22 | no bundle assertions; generic rules pass |
| mta-long-island-rail-road-west-hempstead-branch | Long Island Rail Road | 10/9 | bundle match consistent; generic rules pass |
| nashville-mta-wego-public-tr-90 | WeGo Public Transit | 7/6 | bundle match consistent; generic rules pass |
| new-jersey-transit-nj-transi-atlc | NJ Transit Rail | 9/8 | no bundle assertions; generic rules pass |
| new-jersey-transit-nj-transi-bntn | NJ Transit Rail | 27/26 | bundle match consistent; generic rules pass |
| new-jersey-transit-nj-transi-bntn-b1 | NJ Transit Rail | 2/1 | no bundle assertions; generic rules pass |
| new-jersey-transit-nj-transi-mnbn | NJ Transit Rail | 17/16 | no bundle assertions; generic rules pass |
| new-jersey-transit-nj-transi-mnbn-b1 | NJ Transit Rail | 9/8 | no bundle assertions; generic rules pass |
| new-jersey-transit-nj-transi-mnbnp | NJ Transit Rail | 25/24 | no bundle assertions; generic rules pass |
| new-jersey-transit-nj-transi-mnbnp-b1 | NJ Transit Rail | 9/8 | no bundle assertions; generic rules pass |
| new-jersey-transit-nj-transi-mne | NJ Transit Rail | 26/25 | bundle match consistent; generic rules pass |
| new-jersey-transit-nj-transi-mne-b1 | NJ Transit Rail | 2/1 | no bundle assertions; generic rules pass |
| new-jersey-transit-nj-transi-mneg | NJ Transit Rail | 24/23 | bundle match consistent; generic rules pass |
| new-jersey-transit-nj-transi-mneg-b1 | NJ Transit Rail | 2/1 | no bundle assertions; generic rules pass |
| new-jersey-transit-nj-transi-mneg-b2 | NJ Transit Rail | 3/2 | no bundle assertions; generic rules pass |
| new-jersey-transit-nj-transi-mrl | NJ Transit Rail | 3/2 | no bundle assertions; generic rules pass |
| new-jersey-transit-nj-transi-nec | NJ Transit Rail | 16/15 | bundle match consistent; generic rules pass |
| new-jersey-transit-nj-transi-njcl | NJ Transit Rail | 28/27 | no bundle assertions; generic rules pass |
| new-jersey-transit-nj-transi-pasc | NJ Transit Rail | 18/17 | no bundle assertions; generic rules pass |
| new-jersey-transit-nj-transi-prin | NJ Transit Rail | 2/1 | no bundle assertions; generic rules pass |
| new-jersey-transit-nj-transi-rarv | NJ Transit Rail | 21/20 | bundle match consistent; generic rules pass |
| new-jersey-transit-nj-transi-hblr | NJ Transit Rail | 21/20 | bundle-diff: bundle_partial_frame — Bundle nyc:hblr:visible_anchors is explicitly complete=False, n=2; extras are the real ~24 HBLR stations outside the tiny anchor frame. |
| new-jersey-transit-nj-transi-hblr-b1 | NJ Transit Rail | 4/3 | no bundle assertions; generic rules pass |
| new-jersey-transit-nj-transi-rvln | NJ Transit Rail | 21/20 | bundle match consistent; generic rules pass |
| new-jersey-transit-nj-transi-nlr | NJ Transit Rail | 16/15 | bundle match consistent; generic rules pass |
| new-jersey-transit-nj-transi-nlr-b1 | NJ Transit Rail | 3/2 | no bundle assertions; generic rules pass |
| north-county-transit-distric-498 | North County Transit District | 8/7 | bundle match consistent; generic rules pass |
| north-county-transit-distric-sprinter | North County Transit District | 15/14 | bundle match consistent; generic rules pass |
| patco-speedline-patco | Port Authority Transit Corporation | 14/13 | bundle-diff: naming_noise — App's generic 'City Hall' is the same physical station the bundle (phl:patco:full) names 'City Hall (Camden)'. |
| port-authority-of-allegheny-blue | Pittsburgh Regional Transit | 24/23 | bundle-diff: bundle_partial_frame — bundle common_trunk (Red Line) n=8 anchor set, cov_app 0.38. |
| port-authority-of-allegheny-red | Pittsburgh Regional Transit | 31/30 | bundle-diff: bundle_partial_frame — bundle common_trunk n=8 anchor set, cov_app 0.29. |
| port-authority-of-allegheny-slvr | Pittsburgh Regional Transit | 31/30 | bundle-diff: bundle_partial_frame — bundle common_trunk (mismatched to Red Line label) n=8 anchor set, cov_app 0.29. |
| port-authority-trans-hudson-hoboken-33rd-street | Port Authority Trans-Hudson Corporation | 6/5 | bundle-diff: bundle_partial_frame — Bundle nyc:path:hoboken pattern is a single-station anchor (n=1); extra 'Hoboken' is a real PATH stop outside the frame. |
| port-authority-trans-hudson-hoboken-world-trade-center | Port Authority Trans-Hudson Corporation | 4/3 | no bundle assertions; generic rules pass |
| port-authority-trans-hudson-journal-square-33rd-street-via-hoboken | Port Authority Trans-Hudson Corporation | 9/8 | bundle-diff: bundle_partial_frame — Bundle nyc:path:uptown_manhattan/hoboken anchors (n=5/1) are short vs the real 13-station JSQ-33rd route; extras are real PATH stations. |
| port-authority-trans-hudson-newark-harrison-shuttle-train | Port Authority Trans-Hudson Corporation | 2/1 | no bundle assertions; generic rules pass |
| port-authority-trans-hudson-world-trade-center-33rd-street | Port Authority Trans-Hudson Corporation | 8/7 | bundle-diff: bundle_partial_frame — Same short PATH anchor bundle fragments; extras (Newport, Exchange Place, WTC) are real stations. |
| san-francisco-municipal-tran-j-b4 | San Francisco Municipal Transportation Agency | 5/4 | bundle-diff: naming_noise — 'Metro Civic Center Station/Downtn' vs 'Civic Center/UN Plaza' is the same station. |
| san-francisco-municipal-tran-n-b3 | San Francisco Municipal Transportation Agency | 3/2 | no bundle assertions; generic rules pass |
| san-francisco-municipal-tran-n-b4 | San Francisco Municipal Transportation Agency | 5/4 | bundle-diff: naming_noise — 'Metro Civic Center Station/Outbd' vs 'Civic Center/UN Plaza' is the same station. |
| san-francisco-municipal-tran-t-b1 | San Francisco Municipal Transportation Agency | 3/2 | bundle-diff: bundle_partial_frame — 3-station branch fragment matched against full 22-station T Third pattern, cov_pat 0.09; not full-line evidence, main T line assessed separately. |
| san-francisco-municipal-tran-ca | San Francisco Municipal Transportation Agency | 18/17 | bundle-diff: bundle_partial_frame — bundle_match is Chicago 'Pink Line' (pink_branch_reference) — a cross-city mismatched bundle entirely unrelated to the California St Cable Car; not usable evide |
| san-francisco-municipal-tran-f | San Francisco Municipal Transportation Agency | 30/29 | bundle-diff: bundle_partial_frame — bundle toward_castro (dir=forward) n=15 covers only one direction/partial frame of the F line, cov_app 0.5. |
| san-francisco-municipal-tran-f-b1 | San Francisco Municipal Transportation Agency | 6/5 | bundle match consistent; generic rules pass |
| san-francisco-municipal-tran-f-b2 | San Francisco Municipal Transportation Agency | 16/15 | bundle-diff: bundle_partial_frame — bundle_match is Dallas 'Orange Line' — a cross-city mismatched bundle, not usable evidence. |
| san-francisco-municipal-tran-j | San Francisco Municipal Transportation Agency | 25/24 | bundle match consistent; generic rules pass |
| san-francisco-municipal-tran-j-b1 | San Francisco Municipal Transportation Agency | 3/2 | bundle match consistent; generic rules pass |
| san-francisco-municipal-tran-j-b2 | San Francisco Municipal Transportation Agency | 2/1 | bundle match consistent; generic rules pass |
| san-francisco-municipal-tran-j-b3 | San Francisco Municipal Transportation Agency | 3/2 | no bundle assertions; generic rules pass |
| san-francisco-municipal-tran-n | San Francisco Municipal Transportation Agency | 32/31 | bundle-diff: bundle_partial_frame — bundle waterfront n=5 anchor set, cov_app 0.16 against a 32-station full N Judah line. |
| san-francisco-municipal-tran-n-b1 | San Francisco Municipal Transportation Agency | 5/4 | no bundle assertions; generic rules pass |
| san-francisco-municipal-tran-n-b2 | San Francisco Municipal Transportation Agency | 5/4 | bundle match consistent; generic rules pass |
| san-francisco-municipal-tran-ph | San Francisco Municipal Transportation Agency | 28/27 | CORRECTED(mergeStations) / bundle-diff: bundle_partial_frame — bundle is inbound-only direction (dir=forward, p_inbound_visible_section); app_extra Hyde St stations belong to the other direction/segment. |
| san-francisco-municipal-tran-ph-b1 | San Francisco Municipal Transportation Agency | 8/7 | bundle-diff: bundle_partial_frame — branch b1 covers only 44% of the outbound bundle pattern; shared Powell St corridor stations likely already represented in the trunk 'ph' line rather than truly |
| san-francisco-municipal-tran-pm | San Francisco Municipal Transportation Agency | 24/23 | bundle-diff: bundle_partial_frame — bundle is inbound-only direction (dir=forward), cov_app 0.58; extra Mason St stops are the other leg. |
| san-francisco-municipal-tran-pm-b1 | San Francisco Municipal Transportation Agency | 2/1 | CORRECTED(mergeStations) / no bundle assertions; generic rules pass |
| san-francisco-municipal-tran-pm-b2 | San Francisco Municipal Transportation Agency | 3/2 | bundle-diff: bundle_partial_frame — branch covers only 21% of outbound bundle pattern; Powell St stations likely already on trunk 'pm' line. |
| san-francisco-municipal-tran-pm-b3 | San Francisco Municipal Transportation Agency | 2/1 | bundle-diff: bundle_partial_frame — G3_BRANCH_DISCONNECTED_FROM_TRUNK plus only 14% pattern coverage; small disconnected fragment, not full-line evidence. / G3: branch endpoints within 50 m of trunk geometry (directional stub) — OK |
| san-francisco-municipal-tran-t | San Francisco Municipal Transportation Agency | 22/21 | bundle-diff: naming_noise — 'Fourth Street & Brannan' vs '4th & Brannan' and 'Chinatown - Rose Pak Station' vs 'Chinatown–Rose Pak' are dash/format variants of the same stations; coverage  |
| san-francisco-municipal-tran-t-b2 | San Francisco Municipal Transportation Agency | 3/2 | bundle-diff: bundle_partial_frame — 3-station fragment vs full 22-station T pattern, cov_pat 0.14. |
| san-francisco-municipal-tran-t-b3 | San Francisco Municipal Transportation Agency | 3/2 | bundle-diff: bundle_partial_frame — 3-station fragment vs full 22-station T pattern, cov_pat 0.14. |
| santa-clara-valley-transport-orange-line | VTA | 26/25 | no bundle assertions; generic rules pass |
| septa-b1 | SEPTA | 22/21 | bundle match consistent; generic rules pass |
| septa-b2 | SEPTA | 9/8 | G4: station set ⊂ same-colour sibling (service variant; one render group) — OK |
| septa-b3 | SEPTA | 8/7 | bundle-diff: bundle_partial_frame — Bundle phl:pattern:B:ridge_spur (n=3: Fairmount, Chinatown, 8th&Market) is a short connector fragment; extras (Fern Rock, Olney, Erie, N.Phila, Broad-Girard) ar |
| septa-l1 | SEPTA | 27/26 | bundle-diff: bundle_partial_frame — Bundle phl:pattern:L:visible (n=12) is a partial sample of the real ~28-station Market-Frankford Line; extras are real ML stations. |
| septa-m1 | SEPTA | 22/21 | no bundle assertions; generic rules pass |
| septa-d1 | SEPTA | 35/34 | bundle match consistent; generic rules pass |
| septa-d2 | SEPTA | 26/25 | bundle match consistent; generic rules pass |
| septa-g1 | SEPTA | 59/58 | CORRECTED(mergeStations,mergeStations) / bundle-diff: bundle_stale_or_wrong — Missing-station list (Fairmount, Spring Garden, Race-Vine, City Hall, Walnut-Locust, Lombard-South) exactly matches phl:pattern:B:main_local (Broad Street Line) |
| septa-g1-b1 | SEPTA | 4/3 | bundle-diff: bundle_stale_or_wrong — Same Broad-St-Line-vs-Girard-trolley bundle mismatch as septa-g1. |
| septa-g1-b2 | SEPTA | 3/2 | bundle-diff: bundle_stale_or_wrong — Same Broad-St-Line-vs-Girard-trolley bundle mismatch as septa-g1. |
| septa-g1-b3 | SEPTA | 5/4 | bundle-diff: bundle_stale_or_wrong — Same Broad-St-Line-vs-Girard-trolley bundle mismatch as septa-g1. |
| septa-g1-b4 | SEPTA | 4/3 | bundle-diff: bundle_stale_or_wrong — Same Broad-St-Line-vs-Girard-trolley bundle mismatch as septa-g1. |
| septa-g1-b5 | SEPTA | 4/3 | no bundle assertions; generic rules pass |
| septa-g1-b6 | SEPTA | 2/1 | no bundle assertions; generic rules pass |
| septa-t1 | SEPTA | 39/38 | bundle-diff: bundle_partial_frame — Bundle phl:pattern:T1:common_tunnel (n=6) + lancaster_anchors (complete=False,n=9) are short trolley-tunnel fragments; extras are the real street-running Lancas |
| septa-t1-b1 | SEPTA | 5/4 | bundle-diff: bundle_stale_or_wrong — Missing list (Stony Island, Bryn Mawr, South Shore, Windsor Park, Cheltenham, 83rd/87th/93rd Street-South Chicago) are NICTD South Shore Line station names, not |
| septa-t1-b2 | SEPTA | 16/15 | G7: 41st St & Baring St->41st St & Powelton Av:56m — directional stop pair >26 m, left as is |
| septa-t1-b3 | SEPTA | 3/2 | bundle match consistent; generic rules pass |
| septa-t1-b4 | SEPTA | 3/2 | bundle-diff: bundle_stale_or_wrong — Missing station '21st Street–Queensbridge' is an NYC F-train station, not a SEPTA T1 trolley stop — bundle mismatched to the wrong city/line. |
| septa-t1-b5 | SEPTA | 5/4 | bundle-diff: bundle_stale_or_wrong — Missing list (60th/56th/52nd/46th/34th St, Drexel Station at 30th St, 15th/13th/11th St, 8th&Market, 5th St/Independence Hall) are Market-Frankford Line (L) sta / G3: branch endpoints within 50 m of trunk geometry (directional stub) — OK |
| septa-t3 | SEPTA | 47/46 | bundle-diff: bundle_partial_frame — Bundle phl:pattern:T3 tunnel/university fragments (n=6/4) are short vs the real ~39-stop Route 13 trolley; extras are real street-running stops. |
| septa-t3-b1 | SEPTA | 4/3 | bundle match consistent; generic rules pass |
| septa-t3-b2 | SEPTA | 6/5 | bundle match consistent; generic rules pass |
| septa-t3-b5 | SEPTA | 2/1 | no bundle assertions; generic rules pass |
| septa-t3-b6 | SEPTA | 7/6 | bundle match consistent; generic rules pass |
| septa-t4 | SEPTA | 47/46 | bundle match consistent; generic rules pass |
| septa-t4-b2 | SEPTA | 3/2 | bundle-diff: bundle_stale_or_wrong — Missing list (Burnett Transit Center/Casa de Amigos, UH-Downtown, Preston, Central Station Main, Bell, Downtown Transit Center, McGowen, Ensemble/HCC, Wheeler)  |
| septa-t4-b3 | SEPTA | 3/2 | G3: branch endpoints within 50 m of trunk geometry (directional stub) — OK |
| septa-t5 | SEPTA | 43/42 | bundle-diff: bundle_partial_frame — Bundle phl:pattern:T5 tunnel/university fragments (n=6/4) are short vs the real ~40-stop Route 36 trolley; extras are real street-running Elmwood Av stops. |
| septa-t5-b2 | SEPTA | 3/2 | bundle match consistent; generic rules pass |
| septa-t5-b3 | SEPTA | 3/2 | no bundle assertions; generic rules pass |
| septa-t5-b4 | SEPTA | 6/5 | no bundle assertions; generic rules pass |
| septa-t5-b6 | SEPTA | 3/2 | G3: branch endpoints within 50 m of trunk geometry (directional stub) — OK |
| septa-t5-b7 | SEPTA | 2/1 | no bundle assertions; generic rules pass |
| shore-line-east-shore-line-east-train | Shore Line East | 9/8 | CORRECTED(renameStation) / bundle-diff: naming_noise — Same New Haven duplicate-name issue. |
| sound-transit-n-line | Sound Transit | 4/3 | bundle-diff: naming_noise — 'Seattle' (app) vs 'King Street' (bundle) is the same Sounder N Line terminus, officially King Street Station. |
| sound-transit-t-line | Sound Transit | 12/11 | bundle match consistent; generic rules pass |
| south-florida-regional-trans-dml | Tri-Rail | 2/1 | bundle match consistent; generic rules pass |
| south-florida-regional-trans-mce | Tri-Rail | 5/4 | bundle-diff: bundle_partial_frame — bundle downtown_link n=2 anchor set, cov_app 0.4 against a 5-station MiamiCentral Express line. |
| south-florida-regional-trans-tr | Tri-Rail | 18/17 | bundle match consistent; generic rules pass |
| south-shore-line-lakeshore | Northern Indiana Commuter Transportation District | 18/17 | bundle match consistent; generic rules pass |
| south-shore-line-monon | Northern Indiana Commuter Transportation District | 9/8 | bundle-diff: bundle_stale_or_wrong — Bundle south_bend__lakeshore full station inventory (Millennium Station to South Bend Airport) is the correct list for the separate app line 'south-shore-line-l |
| thebus-skyline | DTS | 13/12 | no bundle assertions; generic rules pass |
| trimet-portland-streetcar-a | Portland Streetcar | 28/28 loop | CORRECTED(closeLoopDroppingLeadIn) / bundle match consistent; generic rules pass |
| trinity-metro-texrail | Trinity Metro | 9/8 | no bundle assertions; generic rules pass |
| utah-transit-authority-uta-750 | Utah Transit Authority | 16/15 | bundle match consistent; generic rules pass |
| utah-transit-authority-uta-701 | Utah Transit Authority | 25/24 | CORRECTED(feed merge) — fourth batch: rebuilt from the current UTA GTFS and UGRC Utah Railroads layer (composite TRAX division tags); Ballpark–Central Pointe–Millcreek–Meadowbrook trunk and the Central Pointe junction restored; shipped stubs -701-b1/-703-b2/-704-b1 replaced by continuous lines; the only branch left is the University South Campus pattern |
| utah-transit-authority-uta-703 | Utah Transit Authority | 27/26 | CORRECTED(feed merge) — fourth batch: rebuilt from the current UTA GTFS and UGRC Utah Railroads layer (composite TRAX division tags); Ballpark–Central Pointe–Millcreek–Meadowbrook trunk and the Central Pointe junction restored; shipped stubs -701-b1/-703-b2/-704-b1 replaced by continuous lines; the only branch left is the University South Campus pattern |
| utah-transit-authority-uta-703-b1 | Utah Transit Authority | 3/2 | CORRECTED(feed merge) — fourth batch: rebuilt from the current UTA GTFS and UGRC Utah Railroads layer (composite TRAX division tags); Ballpark–Central Pointe–Millcreek–Meadowbrook trunk and the Central Pointe junction restored; shipped stubs -701-b1/-703-b2/-704-b1 replaced by continuous lines; the only branch left is the University South Campus pattern |
| utah-transit-authority-uta-703-b2 | Utah Transit Authority | — | REMOVED — fourth batch: disconnected stub superseded by the continuous UTA rebuild |
| utah-transit-authority-uta-704 | Utah Transit Authority | 19/18 | CORRECTED(feed merge) — fourth batch: rebuilt from the current UTA GTFS and UGRC Utah Railroads layer (composite TRAX division tags); Ballpark–Central Pointe–Millcreek–Meadowbrook trunk and the Central Pointe junction restored; shipped stubs -701-b1/-703-b2/-704-b1 replaced by continuous lines; the only branch left is the University South Campus pattern |
| utah-transit-authority-uta-704-b1 | Utah Transit Authority | — | REMOVED — fourth batch: disconnected stub superseded by the continuous UTA rebuild |
| utah-transit-authority-uta-701-b1 | Utah Transit Authority | — | REMOVED — fourth batch: disconnected stub superseded by the continuous UTA rebuild |
| utah-transit-authority-uta-720 | Utah Transit Authority | 7/6 | bundle match consistent; generic rules pass |
| wmata-blue | WMATA | 28/27 | bundle-diff: naming_noise — app_extra/app_missing pairs are formatting variants (e.g. 'L'enfant Plaza' vs 'L'Enfant Plaza', 'Metro Center Metrorail Station' vs 'Metro Center', straight vs  |
| wmata-green | WMATA | 21/20 | bundle-diff: naming_noise — same station pairs differ only by 'Metrorail Station' suffix and dash style (e.g. 'Gallery Place Metrorail Station' vs 'Gallery Place–Chinatown'). |
| wmata-orange | WMATA | 26/25 | bundle-diff: naming_noise — same station pairs differ only by 'Metrorail Station' suffix and dash/apostrophe style. |
| wmata-red | WMATA | 27/26 | bundle-diff: naming_noise — same station pairs differ only by 'Metrorail Station' suffix and dash/apostrophe style (e.g. 'Grosvenor-strathmore' vs 'Grosvenor–Strathmore'). |
| wmata-silver | WMATA | 34/33 | bundle-diff: naming_noise — same station pairs differ only by 'Metrorail Station' suffix and dash/apostrophe style. |
| wmata-yellow | WMATA | 13/12 | bundle match consistent; generic rules pass |
| metro-transit-intercity-tran-monorail | Seattle Center Monorail | 2/1 | bundle match consistent; generic rules pass |
| alaska-railroad-aurora-winter | Alaska Railroad | 14/13 | no bundle assertions; generic rules pass |
| alaska-railroad-coastal-classic | Alaska Railroad | 3/2 | no bundle assertions; generic rules pass |
| alaska-railroad-denali-star | Alaska Railroad | 5/4 | G4: station set ⊂ same-colour sibling (service variant; one render group) — OK |
| alaska-railroad-hurricane-turn | Alaska Railroad | 10/9 | no bundle assertions; generic rules pass |
| septa-regional-rail-air | SEPTA | 10/9 | bundle-diff: bundle_partial_frame — Bundle phl:regional:center_city (n=3, 'unresolved shared family' trunk) is a deliberate common-trunk fragment shared by all SEPTA Regional Rail lines; extras ar |
| septa-regional-rail-che | SEPTA | 14/13 | bundle-diff: bundle_partial_frame — Same shared 3-stop Center City trunk bundle; extras are real Chestnut Hill East stations. |
| septa-regional-rail-chw | SEPTA | 14/13 | bundle-diff: bundle_partial_frame — Same shared trunk bundle; extras are real Chestnut Hill West stations. |
| septa-regional-rail-cyn | SEPTA | 5/4 | bundle-diff: bundle_partial_frame — Same shared trunk bundle (matched via phl:media pattern too); extras (Cynwyd, Bala, Wynnefield Av) are real Cynwyd Line stations. |
| septa-regional-rail-fox | SEPTA | 10/9 | bundle-diff: bundle_partial_frame — Same shared trunk bundle; extras are real Fox Chase Line stations. |
| septa-regional-rail-lan | SEPTA | 29/28 | bundle-diff: bundle_partial_frame — Same shared trunk bundle; extras are real Lansdale/Doylestown Line stations. |
| septa-regional-rail-med | SEPTA | 20/19 | bundle-diff: bundle_partial_frame — Same shared trunk bundle; extras are real Media/Wawa Line stations. |
| septa-regional-rail-nor | SEPTA | 17/16 | bundle-diff: bundle_partial_frame — Same shared trunk bundle; extras are real Manayunk/Norristown Line stations. |
| septa-regional-rail-pao | SEPTA | 26/25 | bundle-diff: bundle_partial_frame — Same shared trunk bundle; extras are real Paoli/Thorndale Line stations. |
| septa-regional-rail-tre | SEPTA | 15/14 | bundle-diff: bundle_partial_frame — Same shared trunk bundle; extras are real Trenton Line stations. |
| septa-regional-rail-war | SEPTA | 16/15 | bundle-diff: bundle_partial_frame — Same shared trunk bundle; extras are real Warminster Line stations. |
| septa-regional-rail-wil | SEPTA | 22/21 | bundle-diff: bundle_partial_frame — Same shared trunk bundle; extras are real Wilmington/Newark Line stations. |
| septa-regional-rail-wtr | SEPTA | 21/20 | bundle-diff: bundle_partial_frame — Same shared trunk bundle; extras are real West Trenton Line stations. |

## CA

| line | operator | st/seg | verdict |
|---|---|---|---|
| go-transit-br | GO Transit | 11/10 | bundle match consistent; generic rules pass |
| go-transit-ki | GO Transit | 14/13 | bundle-diff: bundle_partial_frame — Bundle is UP Express (n=5), a subset corridor of the much longer GO Kitchener line (14 stns); extras (Malton, Bramalea, Georgetown, Acton, Guelph, Kitchener, St |
| go-transit-le | GO Transit | 10/9 | bundle match consistent; generic rules pass |
| go-transit-lw | GO Transit | 15/14 | no bundle assertions; generic rules pass |
| go-transit-lw-b1 | GO Transit | 2/1 | no bundle assertions; generic rules pass |
| go-transit-mi | GO Transit | 9/8 | no bundle assertions; generic rules pass |
| go-transit-rh | GO Transit | 7/6 | bundle match consistent; generic rules pass |
| go-transit-st | GO Transit | 10/9 | bundle match consistent; generic rules pass |
| amtrak-adirondack-ca | Amtrak | 2/1 | no bundle assertions; generic rules pass |
| edmonton-transit-system-capital | Edmonton Transit Service | 15/14 | bundle-diff: bundle_partial_frame — Bundle is the Capital/Metro shared-trunk pattern (n=8), far shorter than Capital Line's 15 stns; extras (Century Park, Southgate, Stadium, Coliseum, Belvedere,  |
| edmonton-transit-system-metro | Edmonton Transit Service | 14/13 | bundle-diff: bundle_partial_frame — Matched to the Capital-Line shared-trunk bundle (n=8), not a Metro-specific bundle; extras (MacEwan, Kingsway RAH, NAIT-Blatchford Market) are real Metro Line s |
| edmonton-transit-system-valley | Edmonton Transit Service | 12/11 | bundle-diff: bundle_partial_frame — Bundle is 'valley_visible' partial-visibility subset (n=8) vs app's 12; extras (Mill Woods, Grey Nuns, Millbourne/Woodvale, Davies) are real Valley Line SE stop |
| exo-ca | exo-Réseau de transport métropolitain | 9/8 | bundle match consistent; generic rules pass |
| exo-ma | exo-Réseau de transport métropolitain | 11/10 | no bundle assertions; generic rules pass |
| exo-sh | exo-Réseau de transport métropolitain | 7/6 | no bundle assertions; generic rules pass |
| exo-sj | exo-Réseau de transport métropolitain | 14/13 | bundle match consistent; generic rules pass |
| exo-vh | exo-Réseau de transport métropolitain | 18/17 | no bundle assertions; generic rules pass |
| grt-ion-light-rail-301 | Grand River Transit | 16/15 | bundle-diff: bundle_partial_frame — Bundle 'ion_northbound' anchors only 8 of ~19 ION stops; extras (Fairway, Block Line, Borden, R&T Park, Northfield, Conestoga, etc.) are real ION stations outsi |
| grt-ion-light-rail-301-b2 | Grand River Transit | 3/2 | bundle-diff: bundle_partial_frame — Direction-specific branch record for southbound ION; builder emits it as a partial branch stub, bundle not comparable evidence per branch-record rule. |
| grt-ion-light-rail-301-b1 | Grand River Transit | 4/3 | bundle-diff: bundle_partial_frame — Same as -b2: southbound ION branch stub, bundle not evidence against it. |
| ottawa-carleton-regional-tra-1 | OC Transpo | 13/12 | bundle-diff: naming_noise — Extra 'Tunney's Pasture' vs missing 'Tunney's Pasture' differ only by curly vs straight apostrophe glyph; same station. |
| ottawa-carleton-regional-tra-2 | OC Transpo | 11/10 | bundle-diff: naming_noise — "Mooney's BAY"/"Dow's LAKE ~ LAC DOW" (bilingual/caps app strings) vs "Mooney's Bay"/"Dow's Lake" (clean bundle names) are the same stations, formatting differs |
| ottawa-carleton-regional-tra-4 | OC Transpo | 3/2 | no bundle assertions; generic rules pass |
| translink-canada-line | TransLink | 14/13 | bundle-diff: naming_noise — App uses 'Station' suffix + ASCII hyphen (e.g. 'Yaletown-Roundhouse Station'); bundle uses en-dash, no suffix ('Yaletown–Roundhouse'). Same stations. |
| translink-canada-line-b1 | TransLink | 4/3 | bundle-diff: bundle_partial_frame — Verified in app JSON: real YVR-Airport branch (Bridgeport, Templeton, Sea Island Centre, YVR-Airport) matches TransLink's actual Canada Line airport branch; dir |
| translink-expo-line | TransLink | 20/19 | bundle-diff: naming_noise — Same hyphen/en-dash + 'Station' suffix formatting difference as Canada Line (Stadium-Chinatown, Commercial-Broadway, Joyce-Collingwood). |
| translink-expo-line-b1 | TransLink | 5/4 | bundle-diff: bundle_partial_frame — Verified in app JSON: real Production Way-University branch (Columbia, Sapperton, Braid, Lougheed Town Centre, Production Way-University) matches TransLink's ac |
| translink-millennium-line | TransLink | 17/16 | bundle-diff: naming_noise — Same hyphen/en-dash + 'Station' suffix formatting difference (VCC-Clark, Commercial-Broadway, Sperling-Burnaby Lake, Production Way-University, Lafarge Lake-Dou |
| translink-wce | TransLink | 8/7 | bundle match consistent; generic rules pass |
| ttc-1 | TTC | 38/37 | bundle-diff: naming_noise — App's 'Bloor Station' vs bundle's 'Bloor–Yonge' and app's 'Sheppard-Yonge Station' vs bundle's 'Sheppard–Yonge' are the same interchange stations under abbrevia |
| ttc-2 | TTC | 31/30 | bundle-diff: naming_noise — App's 'Yonge Station' vs bundle's 'Bloor–Yonge' is the same interchange station (Line 2 side of the same Bloor-Yonge complex). |
| ttc-4 | TTC | 5/4 | no bundle assertions; generic rules pass |
| ttc-5 | TTC | 25/24 | bundle match consistent; generic rules pass |
| ttc-6 | TTC | 18/17 | bundle match consistent; generic rules pass |
| ttc-501 | TTC | 63/62 | bundle-diff: bundle_partial_frame — Bundle is a westbound diversion pattern (n=5, complete=False), vs app's 63-stop full Queen line; extras are real street-stop anchors outside that cropped divers |
| ttc-501-b1 | TTC | 5/4 | no bundle assertions; generic rules pass |
| ttc-501-b2 | TTC | 3/2 | no bundle assertions; generic rules pass |
| ttc-501-b3 | TTC | 3/2 | no bundle assertions; generic rules pass |
| ttc-501-b4 | TTC | 5/4 | bundle-diff: bundle_partial_frame — Bundle is the eastbound diversion pattern (n=5, complete=False); this is a direction-specific branch record, not evidence. |
| ttc-501-b5 | TTC | 3/2 | no bundle assertions; generic rules pass |
| ttc-501-b6 | TTC | 4/3 | no bundle assertions; generic rules pass |
| ttc-501-b7 | TTC | 3/2 | no bundle assertions; generic rules pass |
| ttc-501-b8 | TTC | 5/4 | no bundle assertions; generic rules pass |
| ttc-504 | TTC | 51/50 | bundle-diff: bundle_partial_frame — Bundle is a 7-anchor incomplete King-line pattern vs app's 51 stops; extras are real street-stop anchors outside the cropped frame. / G7: Cherry St at Front St->King St East at Sackville St:30m;King St West at Queen St->Roncesvalles Ave at Queen St:56m — directional stop pair >26 m, left as is |
| ttc-504-b1 | TTC | 7/6 | bundle match consistent; generic rules pass |
| ttc-504-b2 | TTC | 7/6 | G7: Dufferin St at Springhurst Ave->Dufferin Gate Loop:55m — directional stop pair >26 m, left as is |
| ttc-504-b3 | TTC | 2/1 | no bundle assertions; generic rules pass |
| ttc-504-b4 | TTC | 4/3 | no bundle assertions; generic rules pass |
| ttc-504-b5 | TTC | 3/2 | no bundle assertions; generic rules pass |
| ttc-504-b6 | TTC | 2/1 | no bundle assertions; generic rules pass |
| ttc-504-b7 | TTC | 3/2 | bundle-diff: bundle_partial_frame — Branch record matched to an unrelated bundle (Line 2 Bloor-Danforth subway); per branch-record rule this mismatch is not evidence. |
| ttc-504-b8 | TTC | 2/1 | bundle-diff: bundle_partial_frame — Same mismatch as -b7 (matched to Line 2 subway bundle); branch record, not evidence. |
| ttc-505 | TTC | 42/41 | CORRECTED(mergeStations) / bundle-diff: bundle_partial_frame — Matched to an unrelated bundle (Line 2 Bloor-Danforth subway) instead of any Dundas streetcar pattern; entirely wrong-line bundle, not evidence for this streetc |
| ttc-505-b1 | TTC | 3/2 | no bundle assertions; generic rules pass |
| ttc-505-b2 | TTC | 3/2 | no bundle assertions; generic rules pass |
| ttc-505-b3 | TTC | 3/2 | bundle-diff: bundle_partial_frame — Branch record matched to the same unrelated Line 2 subway bundle; not evidence. |
| ttc-505-b4 | TTC | 3/2 | G7: Dundas St West at Bloor St->Edna Ave at Dundas St:55m;Edna Ave at Dundas St->Dundas West Station:38m — directional stop pair >26 m, left as is |
| ttc-505-b5 | TTC | 2/1 | no bundle assertions; generic rules pass |
| ttc-506 | TTC | 64/63 | bundle-diff: bundle_partial_frame — Matched to the wrong route's bundle (505 Dundas anchors, n=8, complete=False) instead of a 506 Carlton pattern; cropped and mismatched, not evidence. |
| ttc-506-b1 | TTC | 3/2 | bundle-diff: bundle_partial_frame — Branch record matched to an entirely unrelated bundle (Houston Red Line, a different city/operator); not evidence. |
| ttc-506-b2 | TTC | 4/3 | no bundle assertions; generic rules pass |
| ttc-506-b3 | TTC | 3/2 | bundle-diff: bundle_partial_frame — Branch record matched to unrelated Line 2 Bloor-Danforth subway bundle; not evidence. |
| ttc-506-b4 | TTC | 3/2 | no bundle assertions; generic rules pass |
| ttc-506-b5 | TTC | 7/6 | bundle match consistent; generic rules pass |
| ttc-506-b6 | TTC | 4/3 | bundle match consistent; generic rules pass |
| ttc-506-b7 | TTC | 5/4 | bundle match consistent; generic rules pass |
| ttc-506-b8 | TTC | 3/2 | no bundle assertions; generic rules pass |
| ttc-509 | TTC | 13/12 | bundle-diff: bundle_partial_frame — Bundle is a 5-anchor incomplete pattern vs app's 13 stops; extras are real stops outside the cropped frame. / G7: Exhibition Loop->Exhibition Loop at Manitoba Dr:57m — directional stop pair >26 m, left as is |
| ttc-509-b1 | TTC | 3/2 | no bundle assertions; generic rules pass |
| ttc-510 | TTC | 18/17 | bundle-diff: bundle_partial_frame — Bundle is a 5-stop 'central_southbound' subset vs app's full 18-stop Spadina line; extras (Union Station, Queens Quay/Ferry Docks, Harbourfront Centre, etc.) ar |
| ttc-510-b1 | TTC | 3/2 | bundle match consistent; generic rules pass |
| ttc-510-b2 | TTC | 2/1 | bundle match consistent; generic rules pass |
| ttc-510-b3 | TTC | 2/1 | bundle match consistent; generic rules pass |
| ttc-511 | TTC | 17/16 | bundle-diff: bundle_partial_frame — Bundle n=17 but complete=False; 2 extra street-stop anchors fall outside the incomplete frame, not evidence. |
| ttc-511-b1 | TTC | 3/2 | bundle match consistent; generic rules pass |
| ttc-511-b2 | TTC | 2/1 | bundle match consistent; generic rules pass |
| ttc-512 | TTC | 21/20 | bundle-diff: bundle_partial_frame — Matched to an entirely unrelated bundle (Line 1 Yonge-University subway) instead of any St Clair streetcar pattern; not evidence for this streetcar. |
| ttc-512-b1 | TTC | 2/1 | bundle-diff: bundle_partial_frame — Branch record matched to the same unrelated Line 1 subway bundle; not evidence. |
| union-pearson-express-up-exp-up | UP Express | 5/4 | bundle match consistent; generic rules pass |
| via-ottawa-montr-al | Via Rail Canada | 5/4 | no bundle assertions; generic rules pass |
| via-toronto-london | Via Rail Canada | 5/4 | G4: station set ⊂ same-colour sibling (service variant; one render group) — OK |
| via-toronto-sarnia | Via Rail Canada | 12/11 | bundle match consistent; generic rules pass |
| via-toronto-windsor | Via Rail Canada | 10/9 | bundle match consistent; generic rules pass |

## Analysis-dataset lines with no shipped counterpart (coverage, not display)

74 lines with stop lists in the four datasets have no line in us/ca-2025.json. These are coverage gaps for the builder (feeds not yet in na-feeds.json or blocked), not display-rule violations of shipped lines.

| dataset/city | lines |
|---|---|
| 11c/san_diego | UC San Diego Blue Line (32 stops); Green Line (24 stops); Orange Line (18 stops); Silver Line / Vintage Trolley (9 stops) |
| 11c/san_francisco_bay | VTA Blue Line (9 stops); VTA Green Line (9 stops) |
| 11c/san_juan | Tren Urbano (16 stops) |
| 11c/seattle | Link 2 Line (25 stops) |
| 11c/st_louis | MetroLink Red Line (29 stops); MetroLink Blue Line (25 stops) |
| 11c/tucson | Sun Link Streetcar (23 stops) |
| 11c/washington | Yellow Line (22 stops) |
| 18c/mgw | WVU Personal Rapid Transit (5 stops) |
| 18c/min | METRO Blue Line (19 stops) |
| 18c/mtl | Ligne 1 — Verte (27 stops); Ligne 2 — Orange (31 stops); Ligne 4 — Jaune (3 stops); Ligne 5 — Bleue (12 stops); Réseau express métropolitain (23 stops); exo 13 — Mont-Saint-Hilaire (1 stops) |
| 18c/nol | Rampart–Loyola (4 stops) |
| 18c/nyc | New York City Subway 2 (3 stops); New York City Subway 3 (3 stops); New York City Subway 7 (9 stops); New York City Subway A (4 stops); New York City Subway C (5 stops); New York City Subway B (4 stops); New York City Subway D (4 stops); New York City Subway F (9 stops); New York City Subway M (8 stops); New York City Subway G (3 stops); New York City Subway N (5 stops); New York City Subway Q (3 stops) |
| 18c/okc | Downtown Loop (22 stops); Bricktown Loop (9 stops) |
| 18c/orf | The Tide (11 stops) |
| 18c/pdx | MAX Blue Line (14 stops); MAX Red Line (14 stops); MAX Green Line (19 stops); MAX Yellow Line (10 stops); MAX Orange Line (11 stops); Portland Streetcar North/South Line (7 stops); Portland Streetcar B Loop (13 stops) |
| 18c/phl | Broad Street Line / B (9 stops) |
| 18c/phx | PHX Sky Train (6 stops) |
| 18c/pit | Duquesne Incline (2 stops); Monongahela Incline (2 stops) |
| 18c/sac | Blue Line (9 stops); Gold Line (7 stops); Green Line (7 stops) |
| 20c/cleveland | Red Line (5 stops); Blue Line (6 stops); Green Line (6 stops) |
| 20c/denver | C Line (5 stops); E Line (5 stops); W Line (6 stops); A Line (3 stops) |
| 20c/detroit | QLINE (6 stops) |
| 20c/el_paso | Figure Eight Loop (27 stops); Downtown Loop (10 stops) |
| 20c/honolulu | Skyline (2 stops) |
| 20c/jacksonville | Skyway (8 stops) |
| 20c/kansas_city | KC Streetcar (8 stops) |
| 20c/kenosha | Kenosha Electric Streetcar (6 stops) |
| 20c/las_vegas | Las Vegas Monorail (3 stops) |
| 20c/little_rock | METRO Streetcar Blue Line (12 stops) |
| 20c/milwaukee | M-Line (10 stops); L-Line (6 stops) |
| 4c/boston | Franklin/Foxboro Line (15 stops) |
| 4c/buffalo | Metro Rail (14 stops) |
| 4c/calgary | Red Line (28 stops); Blue Line (25 stops) |
| 4c/charlotte | LYNX Blue Line (26 stops); CityLYNX Gold Line (17 stops) |
