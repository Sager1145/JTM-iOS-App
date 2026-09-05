# North America display review — line by line

Generated 2026-09-04 by `app/scripts/railway/review-na-display.mjs` from the continuous-stroke model both clients draw (rail-network.js + rail-stroke.js). One row per published line; the flags are where a reviewer looks, not verdicts.

Lines: 370. One continuous stroke feature each: 370. Flagged: 86.

Flag key: `withheld` — intervals still absent after the reviewed OSM releases; `osm-confirms-defect` — an interval measured against OSM and found wrong (kept withheld); `seam-jogs` — survey seams the engine redraws as tapers (raw count → residual at z16, which should be 0); `stroke-spikes` — reversals the drawn stroke has that the survey does not (should be 0/0); `reference-warning` — the package kept a provenance-verified centreline over a disagreeing lower-authority reference; `branch-parts` — a line drawn as several real branch strokes.

| flag | lines |
| --- | ---: |
| reference-warning | 49 |
| seam-jogs | 27 |
| withheld | 8 |
| branch-parts | 7 |
| osm-confirms-defect | 4 |

| region | line | kind | km | parts | ref max m / limit | withheld → released | lanes | follows / followed by | jogs (raw → z16) | spikes z13/z16 | beads | flags |
| --- | --- | --- | ---: | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| us | `ace-ace` Altamont Commuter Express | commuter | 136.638 | 1 | 12.43 / 30 | – | -1 -0.5 | 2 / 1 | 0 → 0 | 0/0 | 10/10 | OK |
| us | `mckinney-avenue-trolley-m-line-ob` M-Line ( ) | streetcar | 3.366 | 1 | 7.07 / 20 | – | 0 | 0 / 3 | 0 → 0 | 0/0 | 25/25 | OK |
| us | `mckinney-avenue-trolley-m-line-ob-b1` M-Line ( ) | streetcar | 1.439 | 1 | 6.35 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 7/7 | OK |
| us | `mckinney-avenue-trolley-m-line-ob-b2` M-Line ( ) | streetcar | 1.291 | 1 | 5.99 / 20 | – | 0 | 2 / 0 | 0 → 0 | 0/0 | 9/9 | OK |
| us | `new-orleans-rta-12` St. Charles Streetcar | streetcar | 10.596 | 1 | 10.18 / 20 | – | 0 | 0 / 3 | 0 → 0 | 0/0 | 56/56 | OK |
| us | `new-orleans-rta-12-b1` St. Charles Streetcar | streetcar | 1.435 | 1 | 11.51 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 7/7 | OK |
| us | `new-orleans-rta-12-b2` St. Charles Streetcar | streetcar | 0.516 | 1 | 4.66 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| us | `new-orleans-rta-12-b3` St. Charles Streetcar | streetcar | 0.426 | 1 | 5.45 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| us | `new-orleans-rta-47` Canal Streetcar - Cemeteries | streetcar | 5.85 | 1 | 4.4 / 20 | – | 0.5 | 1 / 0 | 0 → 0 | 0/0 | 25/25 | OK |
| us | `new-orleans-rta-48` Canal Streetcar - City Park | streetcar | 5.927 | 1 | 14.42 / 20 | – | -0.5 | 0 / 1 | 0 → 0 | 0/0 | 25/25 | OK |
| us | `new-orleans-rta-49` Riverfront Streetcar | streetcar | 2.127 | 1 | 5.79 / 20 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 8/8 | OK |
| us | `smart-smart` Main Line | commuter | 77.53 | 1 | 7.94 / 30 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 14/14 | OK |
| us | `amtrak-adirondack-us` Adirondack | intercity | 532.006 | 1 | 61.67 / 50 | 4 → 4 | -0.5 4 | 2 / 1 | 2 → 0 | 0/0 | 16/16 | seam-jogs:2 |
| us | `amtrak-amtrak-cascades-us` Amtrak Cascades | intercity | 638.281 | 1 | 57.57 / 50 | – | -0.5 | 5 / 1 | 2 → 0 | 0/0 | 17/17 | seam-jogs:2 reference-warning:57.57m>50m |
| us | `amtrak-amtrak-hartford-line` Amtrak Hartford Line | intercity | 99.743 | 1 | 17.27 / 50 | – | -0.5 | 1 / 0 | 0 → 0 | 0/0 | 9/9 | OK |
| us | `amtrak-amtrak-mardi-gras-service` Amtrak Mardi Gras Service | intercity | 232.63 | 1 | 25.25 / 50 | – | -0.5 | 0 / 0 | 0 → 0 | 0/0 | 6/6 | OK |
| us | `amtrak-borealis` Borealis | intercity | 658.042 | 1 | 62.33 / 50 | 10 → 10 | -0.5 | 1 / 9 | 1 → 0 | 0/0 | 13/13 | seam-jogs:1 |
| us | `amtrak-capitol-corridor` Capitol Corridor | intercity | 271.456 | 1 | 21.74 / 50 | – | -0.5 | 1 / 0 | 1 → 0 | 0/0 | 18/18 | seam-jogs:1 |
| us | `amtrak-carl-sandburg` Carl Sandburg | intercity | 414.585 | 1 | 30.77 / 50 | – | -1 -0.5 | 3 / 0 | 0 → 0 | 0/0 | 10/10 | OK |
| us | `amtrak-carolinian` Carolinian | intercity | 1126.728 | 1 | 67.26 / 50 | 7,8 → 7,8 | -2 -1.5 -0.5 4 | 3 / 1 | 2 → 0 | 0/0 | 28/28 | seam-jogs:2 |
| us | `amtrak-empire-builder` Empire Builder | intercity | 3516.356 | 1 | 106.68 / 50 | – | -0.5 | 18 / 2 | 4 → 0 | 0/0 | 41/41 | seam-jogs:4 reference-warning:106.68m>50m |
| us | `amtrak-empire-builder-b1` Empire Builder | intercity | 601.992 | 1 | 37.8 / 50 | – | -0.5 | 2 / 0 | 0 → 0 | 0/0 | 6/6 | OK |
| us | `amtrak-empire-service` Empire Service | intercity | 744.706 | 1 | 40.33 / 50 | – | -0.5 4 | 3 / 0 | 3 → 0 | 0/0 | 17/17 | seam-jogs:3 |
| us | `amtrak-ethan-allen-express` Ethan Allen Express | intercity | 497.665 | 2 | 30.75 / 50 | – | -0.5 4 | 2 / 1 | 2 → 0 | 0/0 | 15/15 | branch-parts:2 seam-jogs:2 |
| us | `amtrak-heartland-flyer` Heartland Flyer | intercity | 328.333 | 1 | 27.76 / 50 | – | -0.5 | 0 / 0 | 0 → 0 | 0/0 | 7/7 | OK |
| us | `amtrak-hiawatha-service` Hiawatha Service | intercity | 137.845 | 1 | 27.33 / 50 | – | -1.5 -0.5 | 1 / 3 | 1 → 0 | 0/0 | 5/5 | seam-jogs:1 |
| us | `amtrak-lake-shore-limited` Lake Shore Limited | intercity | 1631.468 | 1 | 71.92 / 50 | 5,9 → 5,9 | -1.5 -0.5 0 1 | 9 / 4 | 0 → 0 | 0/0 | 22/22 | OK |
| us | `amtrak-lake-shore-limited-b1` Lake Shore Limited | intercity | 226.51 | 1 | 82.37 / 50 | 0 → 0 | -0.5 0.5 4 | 1 / 3 | 1 → 0 | 0/0 | 5/5 | seam-jogs:1 |
| us | `amtrak-lincoln-service-missouri-river-runner` Lincoln Service Missouri River Runner | intercity | 898.034 | 1 | 44.37 / 50 | – | -1 -0.5 | 2 / 3 | 1 → 0 | 0/0 | 20/20 | seam-jogs:1 |
| us | `amtrak-missouri-river-runner` Missouri River Runner | intercity | 446.603 | 1 | 29.72 / 50 | – | -0.5 | 2 / 0 | 1 → 0 | 0/0 | 10/10 | seam-jogs:1 |
| us | `amtrak-palmetto` Palmetto | intercity | 1331.482 | 1 | 67.26 / 50 | 5,6,20 → 5,6,20 | -2 -1.5 -0.5 4 | 7 / 4 | 2 → 0 | 0/0 | 23/23 | seam-jogs:2 |
| us | `amtrak-pennsylvanian` Pennsylvanian | intercity | 699.464 | 1 | 297.14 / 50 | 6,12,13 → 6,12 | -0.5 4 | 1 / 0 | 0 → 0 | 0/0 | 17/17 | withheld:13 osm-confirms-defect:13 |
| us | `amtrak-piedmont` Piedmont | intercity | 276.893 | 1 | 28.78 / 50 | – | -0.5 | 1 / 0 | 1 → 0 | 0/0 | 9/9 | seam-jogs:1 |
| us | `amtrak-southwest-chief` Southwest Chief | intercity | 3579.125 | 1 | 72.76 / 50 | 7,9,11,14,17,23,25,28 → 7,9,11,14,17,23,25,28 | -1.5 -1 -0.5 | 6 / 3 | 3 → 0 | 0/0 | 32/32 | seam-jogs:3 |
| us | `amtrak-valley-flyer` Valley Flyer | intercity | 157.655 | 2 | 17.27 / 50 | – | -1.5 -0.5 0.5 | 2 / 2 | 0 → 0 | 0/0 | 12/12 | branch-parts:2 |
| us | `amtrak-vermonter` Vermonter | intercity | 964.701 | 1 | 67.26 / 50 | 1,17,25,26 → 1,17,25,26 | -2 -1.5 -0.5 0.5 4 | 8 / 0 | 1 → 0 | 0/0 | 30/30 | seam-jogs:1 |
| us | `amtrak-wolverine` Wolverine | intercity | 488.276 | 1 | 22.24 / 50 | – | -1 -0.5 | 2 / 0 | 0 → 0 | 0/0 | 15/15 | OK |
| us | `amtrak-shore-line-east` Shore Line East | commuter | 144.399 | 1 | 13.3 / 30 | – | -0.5 | 0 / 7 | 0 → 0 | 0/0 | 11/11 | OK |
| us | `bart-blue` Dublin/Pleasanton to Daly City | metro | 62.657 | 1 | 60.23 / 25 | 9 → 9 | -1 0.5 | 1 / 0 | 0 → 0 | 0/0 | 18/18 | OK |
| us | `bart-green` Berryessa/North San Jose to Daly City | metro | 85.689 | 1 | 60.23 / 25 | 9 → 9 | -1 -0.5 1.5 | 0 / 5 | 0 → 0 | 0/0 | 22/22 | OK |
| us | `bart-grey` Oakland Int'l Airport OAK to Coliseum | metro | 5.136 | 1 | 18.89 / 25 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 2/2 | OK |
| us | `bart-orange` Berryessa/North San Jose to Richmond | metro | 81.379 | 1 | 15.78 / 25 | – | -1.5 -0.5 0.5 1 | 1 / 1 | 0 → 0 | 0/0 | 21/21 | OK |
| us | `bart-red` Richmond to SF Int'l Airport SFO/Millbrae | metro | 60.011 | 2 | 19.99 / 25 | – | -0.5 1 | 3 / 1 | 0 → 0 | 0/0 | 24/24 | branch-parts:2 |
| us | `brightline-trains-llc-blfm` Mainline | highspeed | 376.18 | 1 | 31.51 / 50 | – | -1 | 0 / 0 | 0 → 0 | 0/0 | 6/6 | OK |
| us | `caltrain-local-weekday` Local Weekday | commuter | 123.441 | 1 | 16.07 / 30 | – | -0.5 | 0 / 2 | 0 → 0 | 0/0 | 30/30 | OK |
| us | `capital-metro-550` 550-Metro Rail Red Line | lightrail | 51.143 | 1 | 8.29 / 25 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 10/10 | OK |
| us | `cincinnati-metro-100` Streetcar - OTR - Banks | streetcar | 5.651 | 1 | 4.93 / 20 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 18/18 | OK |
| us | `connecticut-transit-hartford-line` Hartford Line | commuter | 99.783 | 1 | 17.36 / 30 | – | -2.5 -1.5 -0.5 | 1 / 2 | 1 → 0 | 0/0 | 9/9 | seam-jogs:1 |
| us | `cta-blue-line` Blue Line | metro | 44.418 | 1 | 29.38 / 25 | – | 2 | 0 / 0 | 0 → 0 | 0/0 | 33/33 | reference-warning:29.38m>25m |
| us | `cta-brown-line` Brown Line | metro | 17.949 | 1 | 4.18 / 25 | – | -2.5 0.5 1.5 | 4 / 0 | 0 → 0 | 0/0 | 26/26 | OK |
| us | `cta-green-line` Green Line | metro | 30.642 | 1 | 5.18 / 25 | – | 0.5 | 0 / 5 | 0 → 0 | 0/0 | 28/28 | OK |
| us | `cta-green-line-b1` Green Line | metro | 2.667 | 1 | 11.4 / 25 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| us | `cta-orange-line` Orange Line | metro | 19.585 | 1 | 5.08 / 25 | – | -1 2.5 | 2 / 1 | 0 → 0 | 0/0 | 15/15 | OK |
| us | `cta-pink-line` Pink Line | metro | 16.532 | 1 | 5.71 / 25 | – | 1 1.5 | 2 / 0 | 0 → 0 | 0/0 | 21/21 | OK |
| us | `cta-purple-line` Purple Line | metro | 25.772 | 1 | 11.69 / 25 | – | -1.5 -0.5 | 2 / 3 | 0 → 0 | 0/0 | 25/25 | OK |
| us | `cta-red-line` Red Line | metro | 35.229 | 1 | 14.34 / 25 | – | -1 -0.5 | 0 / 2 | 0 → 0 | 0/0 | 33/33 | OK |
| us | `cta-yellow-line` Yellow Line | metro | 7.903 | 1 | 18.78 / 25 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| us | `dallas-area-rapid-transit-da-silver` SILVER LINE | commuter | 44.412 | 1 | 4.99 / 30 | – | -0.5 | 0 / 0 | 0 → 0 | 0/0 | 10/10 | OK |
| us | `dallas-area-rapid-transit-da-tre` TRINITY RAILWAY | commuter | 54.031 | 1 | 5.56 / 30 | – | -1 | 0 / 0 | 0 → 0 | 0/0 | 10/10 | OK |
| us | `dallas-area-rapid-transit-da-blue` DART LIGHT RAIL - BLUE LINE | lightrail | 50.205 | 1 | 25.51 / 25 | – | -1 -0.5 | 1 / 1 | 0 → 0 | 0/0 | 22/22 | reference-warning:25.51m>25m |
| us | `dallas-area-rapid-transit-da-green` DART LIGHT RAIL - GREEN LINE | lightrail | 45.559 | 1 | 8.16 / 25 | – | -1 -0.5 | 1 / 0 | 0 → 0 | 0/0 | 24/24 | OK |
| us | `dallas-area-rapid-transit-da-orange` DART LIGHT RAIL - ORANGE LINE | lightrail | 65.588 | 1 | 25.51 / 25 | – | -0.5 | 0 / 3 | 0 → 0 | 0/0 | 31/31 | reference-warning:25.51m>25m |
| us | `dallas-area-rapid-transit-da-red` DART LIGHT RAIL - RED LINE | lightrail | 44.459 | 1 | 26.27 / 25 | – | -0.5 0.5 | 2 / 0 | 0 → 0 | 0/0 | 25/25 | reference-warning:26.27m>25m |
| us | `dallas-area-rapid-transit-da-620` DALLAS STREETCAR | funicular | 3.714 | 1 | 3.96 / 25 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 6/6 | OK |
| us | `denton-county-transportation-a-train` A-train | commuter | 33.716 | 1 | 17.17 / 30 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 6/6 | OK |
| us | `detroit-people-mover-dpm` Detroit People Mover | streetcar | 4.594 | 1 | 9.04 / 20 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 13/13 | OK |
| us | `florida-department-of-transp-sunrail` SunRail | commuter | 97.614 | 1 | 9.68 / 30 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 17/17 | OK |
| us | `hillsborough-area-regional-t-sky` SkyConnect operated by Tampa International Airport | lightrail | 2.234 | 1 | 13.98 / 25 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| us | `hillsborough-area-regional-t-800` Tampa Historic Streetcar | heritage | 4.201 | 1 | 8.69 / 50 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 11/11 | OK |
| us | `houston-metro-700` METRORAIL RED LINE | lightrail | 20.198 | 1 | 3.76 / 25 | – | 0 | 0 / 1 | 0 → 0 | 0/0 | 25/25 | OK |
| us | `houston-metro-800` METRORAIL GREEN LINE | lightrail | 7.075 | 1 | 3.64 / 25 | – | 0 | 0 / 1 | 0 → 0 | 0/0 | 9/9 | OK |
| us | `houston-metro-900` METRORAIL PURPLE LINE | lightrail | 9.651 | 1 | 6.95 / 25 | – | 0 | 0 / 2 | 0 → 0 | 0/0 | 10/10 | OK |
| us | `houston-metro-700-b1` METRORAIL RED LINE | streetcar | 0.699 | 1 | 3.14 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| us | `houston-metro-800-b1` METRORAIL GREEN LINE | streetcar | 1.664 | 1 | 4.12 / 20 | – | -1 | 1 / 0 | 0 → 0 | 0/0 | 4/4 | OK |
| us | `houston-metro-900-b1` METRORAIL PURPLE LINE | streetcar | 1.85 | 1 | 4.12 / 20 | – | -1 | 2 / 0 | 0 → 0 | 0/0 | 4/4 | OK |
| us | `king-county-metro-first-hill-streetcar` First Hill Streetcar | streetcar | 4.018 | 1 | 10.65 / 20 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 10/10 | OK |
| us | `king-county-metro-south-lake-union-streetcar` South Lake Union Streetcar | streetcar | 1.979 | 1 | 8.29 / 20 | – | 0 | 0 / 2 | 0 → 0 | 0/0 | 7/7 | OK |
| us | `king-county-metro-south-lake-union-streetcar-b1` South Lake Union Streetcar | streetcar | 1.036 | 1 | 7.55 / 20 | – | 0 | 2 / 0 | 0 → 0 | 0/0 | 4/4 | OK |
| us | `los-angeles-county-metropoli-metro-d-line` Metro D Line | metro | 14.164 | 1 | 10.09 / 25 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 11/11 | OK |
| us | `los-angeles-county-metropoli-metro-a-line` Metro A Line | lightrail | 92.474 | 1 | 10.19 / 25 | – | -0.5 0.5 | 0 / 3 | 0 → 0 | 0/0 | 47/47 | OK |
| us | `los-angeles-county-metropoli-metro-a-line-b1` Metro A Line | lightrail | 1.964 | 1 | 3.37 / 25 | – | 0 | 2 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| us | `los-angeles-county-metropoli-metro-c-line` Metro C Line | lightrail | 28.421 | 1 | 9.24 / 25 | – | 0 | 0 / 1 | 0 → 0 | 0/0 | 12/12 | OK |
| us | `los-angeles-county-metropoli-metro-e-line` Metro E Line | lightrail | 35.23 | 1 | 24.32 / 25 | – | 0.5 1.5 | 1 / 0 | 0 → 0 | 0/0 | 29/29 | OK |
| us | `los-angeles-county-metropoli-metro-k-line` Metro K Line | lightrail | 18.521 | 1 | 31.79 / 25 | – | -1 | 1 / 0 | 0 → 0 | 0/0 | 13/13 | reference-warning:31.79m>25m |
| us | `maryland-transit-administrat-brunswick-washington` BRUNSWICK - WASHINGTON | commuter | 117.45 | 1 | 47.31 / 30 | 11,13,15 → 11,13,15 | -0.5 0 0.5 | 2 / 0 | 0 → 0 | 0/0 | 17/17 | OK |
| us | `maryland-transit-administrat-brunswick-washington-b1` BRUNSWICK - WASHINGTON | commuter | 33.32 | 1 | 21.24 / 30 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| us | `maryland-transit-administrat-brunswick-washington-b2` BRUNSWICK - WASHINGTON | commuter | 43.744 | 1 | 21.24 / 30 | – | 0 | 0 / 4 | 0 → 0 | 0/0 | 2/2 | OK |
| us | `maryland-transit-administrat-brunswick-washington-b3` BRUNSWICK - WASHINGTON | commuter | 33.097 | 1 | 21.24 / 30 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 2/2 | OK |
| us | `maryland-transit-administrat-camden-washington` CAMDEN - WASHINGTON | commuter | 59.02 | 1 | 20.85 / 30 | – | -1 -0.5 1 | 2 / 0 | 0 → 0 | 0/0 | 12/12 | OK |
| us | `maryland-transit-administrat-penn-washington` PENN - WASHINGTON | commuter | 122.61 | 1 | 21.5 / 30 | – | -1 -0.5 | 0 / 5 | 0 → 0 | 0/0 | 13/13 | OK |
| us | `maryland-transit-administrat-2-metro-subwaylink` Owings Mills - Johns Hopkins | metro | 23.363 | 1 | 8.94 / 25 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 14/14 | OK |
| us | `mbta-capeflyer` CapeFLYER | commuter | 126.657 | 1 | 24.51 / 30 | – | -0.5 1 | 1 / 3 | 0 → 0 | 0/0 | 8/8 | OK |
| us | `mbta-fairmount-line` Fairmount Line | commuter | 14.673 | 1 | 4.31 / 30 | – | -1 | 1 / 0 | 0 → 0 | 0/0 | 9/9 | OK |
| us | `mbta-fall-river-new-bedford-line` Fall River/New Bedford Line | commuter | 96.451 | 1 | 10.05 / 30 | – | -0.5 1 | 2 / 1 | 0 → 0 | 0/0 | 13/13 | OK |
| us | `mbta-fall-river-new-bedford-line-b1` Fall River/New Bedford Line | commuter | 22.422 | 1 | 9.08 / 30 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| us | `mbta-fitchburg-line` Fitchburg Line | commuter | 85.944 | 1 | 9.62 / 30 | – | 1 | 0 / 1 | 0 → 0 | 0/0 | 18/18 | OK |
| us | `mbta-foxboro-event-service` Foxboro Event Service | commuter | 74.558 | 1 | 9.09 / 30 | – | -1 0.5 | 2 / 0 | 1 → 0 | 0/0 | 8/8 | seam-jogs:1 |
| us | `mbta-framingham-worcester-line` Framingham/Worcester Line | commuter | 71.24 | 1 | 15.32 / 30 | – | -1 0.5 | 1 / 3 | 0 → 0 | 0/0 | 18/18 | OK |
| us | `mbta-greenbush-line` Greenbush Line | commuter | 44.511 | 1 | 4.6 / 30 | – | -1 0.5 | 1 / 0 | 0 → 0 | 0/0 | 10/10 | OK |
| us | `mbta-haverhill-line` Haverhill Line | commuter | 52.934 | 1 | 9.14 / 30 | – | -0.5 1 | 1 / 0 | 0 → 0 | 0/0 | 15/15 | OK |
| us | `mbta-kingston-line` Kingston Line | commuter | 56.481 | 1 | 4.6 / 30 | – | -0.5 1 | 2 / 0 | 0 → 0 | 0/0 | 10/10 | OK |
| us | `mbta-lowell-line` Lowell Line | commuter | 40.582 | 1 | 9.62 / 30 | – | -0.5 1 | 1 / 0 | 0 → 0 | 0/0 | 8/8 | OK |
| us | `mbta-needham-line` Needham Line | commuter | 21.87 | 1 | 5.11 / 30 | – | -1 0.5 | 1 / 0 | 0 → 0 | 0/0 | 12/12 | OK |
| us | `mbta-newburyport-rockport-line` Newburyport/Rockport Line | commuter | 56.652 | 1 | 26.91 / 30 | – | 1 | 1 / 3 | 0 → 0 | 0/0 | 13/13 | OK |
| us | `mbta-newburyport-rockport-line-b1` Newburyport/Rockport Line | commuter | 28.889 | 1 | 7.07 / 30 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 6/6 | OK |
| us | `mbta-orange-line` Orange Line | metro | 17.731 | 1 | 35.8 / 25 | – | -0.5 0 | 0 / 0 | 0 → 0 | 0/0 | 20/20 | reference-warning:35.8m>25m |
| us | `mbta-providence-stoughton-line` Providence/Stoughton Line | commuter | 100.908 | 1 | 11.72 / 30 | – | -1 0.5 | 2 / 6 | 1 → 0 | 0/0 | 16/16 | seam-jogs:1 |
| us | `mbta-providence-stoughton-line-b2` Providence/Stoughton Line | commuter | 6.263 | 1 | 3.58 / 30 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| us | `mbta-providence-stoughton-line-b5` Providence/Stoughton Line | commuter | 18.003 | 1 | 69.99 / 30 | 7 → 7 | -1 | 0 / 6 | 0 → 0 | 0/0 | 9/9 | OK |
| us | `mbta-d` Green Line D | lightrail | 23.164 | 1 | 17.93 / 25 | – | -1 | 0 / 3 | 0 → 0 | 0/0 | 25/25 | OK |
| us | `mbta-e-b1` Green Line | lightrail | 1.682 | 1 | 3.61 / 25 | – | 1 | 1 / 0 | 0 → 0 | 0/0 | 2/2 | OK |
| us | `mbta-b` Green Line B | streetcar | 18.019 | 1 | 7.8 / 20 | – | -1 -0.5 | 1 / 2 | 0 → 0 | 0/0 | 32/32 | OK |
| us | `mbta-c` Green Line C | streetcar | 15.923 | 1 | 7.8 / 20 | – | -1 -0.5 | 2 / 0 | 0 → 0 | 0/0 | 29/29 | OK |
| us | `mbta-e` Green Line | streetcar | 13.804 | 1 | 8.07 / 20 | – | -1 0.5 | 1 / 0 | 0 → 0 | 0/0 | 25/25 | OK |
| us | `mbta-mattapan-line` Mattapan Line | streetcar | 4.078 | 1 | 2.1 / 20 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 8/8 | OK |
| us | `metra-bnsf` Burlington Northern | commuter | 59.437 | 1 | 11.96 / 30 | – | 0 0.5 | 1 / 3 | 0 → 0 | 0/0 | 26/26 | OK |
| us | `metra-me` Metra Electric | commuter | 49.751 | 1 | 19.01 / 30 | – | -1 | 0 / 4 | 0 → 0 | 0/0 | 33/33 | OK |
| us | `metra-me-b1` Metra Electric | commuter | 8.409 | 1 | 12.59 / 30 | – | -1 | 1 / 1 | 0 → 0 | 0/0 | 9/9 | OK |
| us | `metra-me-b2` Metra Electric | commuter | 7.183 | 1 | 9.4 / 30 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 8/8 | OK |
| us | `metra-me-b3` Metra Electric | commuter | 2.818 | 1 | 12.52 / 30 | – | -1 1 | 2 / 0 | 0 → 0 | 0/0 | 2/2 | OK |
| us | `metra-milwaukee` Milwaukee | commuter | 79.993 | 1 | 26.69 / 30 | – | 0.5 1.5 | 1 / 1 | 0 → 0 | 0/0 | 22/22 | OK |
| us | `metra-milwaukee-2` Milwaukee | commuter | 64.275 | 1 | 10.78 / 30 | – | -0.5 0.5 | 1 / 0 | 0 → 0 | 0/0 | 22/22 | OK |
| us | `metra-ncs` North Central Service | commuter | 85.068 | 1 | 14.35 / 30 | – | -1.5 -1 -0.5 | 1 / 2 | 0 → 0 | 0/0 | 18/18 | OK |
| us | `metra-ri` Rock Island | commuter | 65.674 | 1 | 9.64 / 30 | – | 0 | 1 / 1 | 0 → 0 | 0/0 | 24/24 | OK |
| us | `metra-ri-b1` Rock Island | commuter | 9.525 | 1 | 2.64 / 30 | – | 0 | 0 / 2 | 0 → 0 | 0/0 | 4/4 | OK |
| us | `metra-ri-b2` Rock Island | commuter | 12.516 | 1 | 6.84 / 30 | – | 0 | 2 / 0 | 0 → 0 | 0/0 | 2/2 | OK |
| us | `metra-sws` Southwest Service | commuter | 64.595 | 1 | 18.71 / 30 | – | -2 0.5 | 0 / 7 | 0 → 0 | 0/0 | 13/13 | OK |
| us | `metra-union-pacific-2` Union Pacific | commuter | 70.31 | 1 | 15.48 / 30 | – | 0.5 | 0 / 1 | 0 → 0 | 0/0 | 19/19 | OK |
| us | `metra-up-nw` Union Pacific Northwest | commuter | 101.436 | 1 | 12.5 / 30 | – | 0 | 0 / 1 | 0 → 0 | 0/0 | 22/22 | OK |
| us | `metra-up-nw-b1` Union Pacific Northwest | commuter | 13.5 | 1 | 8.52 / 30 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 2/2 | OK |
| us | `metra-hc` Heritage Corridor | heritage | 59.45 | 1 | 14.14 / 50 | – | 0.5 1 | 3 / 0 | 0 → 0 | 0/0 | 7/7 | OK |
| us | `metro-north-railroad-danbury` Danbury | commuter | 103.685 | 1 | 17.42 / 30 | – | -1 -0.5 | 2 / 0 | 1 → 0 | 0/0 | 15/15 | seam-jogs:1 |
| us | `metro-north-railroad-harlem` Harlem | commuter | 131.862 | 1 | 9.51 / 30 | – | 0 | 0 / 3 | 0 → 0 | 0/0 | 38/38 | OK |
| us | `metro-north-railroad-hudson` Hudson | commuter | 116.938 | 1 | 14.39 / 30 | – | -0.5 0.5 | 1 / 1 | 0 → 0 | 0/0 | 29/29 | OK |
| us | `metro-north-railroad-new-canaan` New Canaan | commuter | 65.749 | 1 | 9.51 / 30 | – | 0.5 | 1 / 0 | 0 → 0 | 0/0 | 20/20 | OK |
| us | `metro-north-railroad-new-haven` New Haven | commuter | 116.84 | 1 | 9.51 / 30 | – | -1 -0.5 | 2 / 3 | 0 → 0 | 0/0 | 32/32 | OK |
| us | `metro-north-railroad-waterbury` Waterbury | commuter | 51.027 | 1 | 11.3 / 30 | – | -1 | 1 / 0 | 0 → 0 | 0/0 | 8/8 | OK |
| us | `metro-transit-metro-green-line` METRO Green Line | lightrail | 17.405 | 1 | 14.37 / 25 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 23/23 | OK |
| us | `metro-transit-intercity-tran-s-line` Seattle - Tacoma/Lakewood | commuter | 76.497 | 1 | 33.96 / 30 | – | 0.5 | 0 / 4 | 0 → 0 | 0/0 | 9/9 | reference-warning:33.96m>30m |
| us | `metro-transit-intercity-tran-1-line` Lynnwood - Federal Way | lightrail | 65.096 | 1 | 16.77 / 25 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 26/26 | OK |
| us | `metrolink-91-pv-line` Metrolink 91-Perris Valley Line | commuter | 135.736 | 1 | 11.92 / 30 | – | -0.5 0.5 | 3 / 1 | 0 → 0 | 0/0 | 12/12 | OK |
| us | `metrolink-av-line` Metrolink Antelope Valley Line | commuter | 122.727 | 1 | 10.24 / 30 | – | -0.5 | 0 / 0 | 0 → 0 | 0/0 | 13/13 | OK |
| us | `metrolink-ie-oc-line` Metrolink Inland Empire-Orange County Line | commuter | 162.531 | 1 | 9.77 / 30 | – | -0.5 | 1 / 3 | 0 → 0 | 0/0 | 16/16 | OK |
| us | `metrolink-oc-line` Metrolink Orange County Line | commuter | 139.474 | 1 | 11.92 / 30 | – | -0.5 0.5 | 2 / 2 | 0 → 0 | 0/0 | 15/15 | OK |
| us | `metrolink-sb-line` Metrolink San Bernardino Line | commuter | 106.572 | 1 | 10.8 / 30 | – | -0.5 | 0 / 3 | 0 → 0 | 0/0 | 18/18 | OK |
| us | `metropolitan-atlanta-rapid-t-blue` BLUE | metro | 24.047 | 1 | 45.27 / 25 | – | -0.5 | 0 / 1 | 0 → 0 | 0/0 | 15/15 | reference-warning:45.27m>25m |
| us | `metropolitan-atlanta-rapid-t-gold` GOLD | metro | 35.74 | 1 | 66.77 / 25 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 18/18 | reference-warning:66.77m>25m |
| us | `metropolitan-atlanta-rapid-t-green` GREEN | metro | 9.924 | 1 | 42.45 / 25 | – | 0.5 | 1 / 0 | 0 → 0 | 0/0 | 9/9 | reference-warning:42.45m>25m |
| us | `metropolitan-transit-authori-1` Broadway - 7 Avenue Local | metro | 23.516 | 1 | 13.51 / 25 | – | 0.5 | 1 / 0 | 0 → 0 | 0/0 | 38/38 | OK |
| us | `metropolitan-transit-authori-2` 7 Avenue Express | metro | 40.81 | 1 | 36.08 / 25 | – | 0.5 | 0 / 7 | 0 → 0 | 0/0 | 61/61 | reference-warning:36.08m>25m |
| us | `metropolitan-transit-authori-3` 7 Avenue Express | metro | 29.217 | 1 | 36.08 / 25 | – | -0.5 0.5 | 2 / 0 | 0 → 0 | 0/0 | 37/37 | reference-warning:36.08m>25m |
| us | `metropolitan-transit-authori-4` Lexington Avenue Express | metro | 32.22 | 1 | 40.66 / 25 | – | -0.5 | 2 / 1 | 0 → 0 | 0/0 | 33/33 | reference-warning:40.66m>25m |
| us | `metropolitan-transit-authori-42-st-shuttle` 42 St Shuttle | metro | 0.695 | 1 | 6.8 / 25 | – | -0.5 | 0 / 0 | 0 → 0 | 0/0 | 2/2 | OK |
| us | `metropolitan-transit-authori-5` Lexington Avenue Express | metro | 38.689 | 1 | 40.95 / 25 | – | -1.5 -1 -0.5 | 2 / 2 | 0 → 0 | 0/0 | 36/36 | reference-warning:40.95m>25m |
| us | `metropolitan-transit-authori-5-b1` Lexington Avenue Express | metro | 6.67 | 1 | 9.06 / 25 | – | -0.5 | 1 / 0 | 0 → 0 | 0/0 | 10/10 | OK |
| us | `metropolitan-transit-authori-6` Lexington Avenue Local | metro | 24.052 | 1 | 16.74 / 25 | – | 0 | 1 / 1 | 0 → 0 | 0/0 | 38/38 | OK |
| us | `metropolitan-transit-authori-6x` Pelham Bay Park Express | metro | 24.052 | 1 | 16.74 / 25 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 38/38 | OK |
| us | `metropolitan-transit-authori-7` Flushing Local | metro | 16.537 | 1 | 8.76 / 25 | – | 0 | 0 / 1 | 0 → 0 | 0/0 | 22/22 | OK |
| us | `metropolitan-transit-authori-7x` Flushing Express | metro | 16.533 | 1 | 8.86 / 25 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 18/18 | OK |
| us | `metropolitan-transit-authori-a` 8 Avenue Express | metro | 51.758 | 1 | 25.56 / 25 | – | -0.5 0.5 2 | 0 / 6 | 0 → 0 | 0/0 | 59/59 | reference-warning:25.56m>25m |
| us | `metropolitan-transit-authori-a-b1` 8 Avenue Express | metro | 1.664 | 1 | 4.48 / 25 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 4/4 | OK |
| us | `metropolitan-transit-authori-a-b2` 8 Avenue Express | metro | 4.531 | 1 | 5.01 / 25 | – | 0.5 | 1 / 0 | 0 → 0 | 0/0 | 5/5 | OK |
| us | `metropolitan-transit-authori-b` 6 Avenue Express | metro | 38.801 | 1 | 26.04 / 25 | – | -1 -0.5 | 2 / 0 | 0 → 0 | 0/0 | 37/37 | reference-warning:26.04m>25m |
| us | `metropolitan-transit-authori-c` 8 Avenue Local | metro | 29.862 | 1 | 25.56 / 25 | – | -0.5 2 | 1 / 0 | 0 → 0 | 0/0 | 40/40 | reference-warning:25.56m>25m |
| us | `metropolitan-transit-authori-d` 6 Avenue Express | metro | 41.215 | 1 | 26.04 / 25 | – | 0.5 | 2 / 3 | 0 → 0 | 0/0 | 41/41 | reference-warning:26.04m>25m |
| us | `metropolitan-transit-authori-e` 8 Avenue Local | metro | 24.875 | 1 | 23.56 / 25 | – | -1 -0.5 2 | 2 / 2 | 0 → 0 | 0/0 | 22/22 | OK |
| us | `metropolitan-transit-authori-f` Queens Blvd Express/6 Av Local | metro | 44.202 | 1 | 39.27 / 25 | – | -0.5 0.5 | 0 / 8 | 0 → 0 | 0/0 | 55/55 | reference-warning:39.27m>25m |
| us | `metropolitan-transit-authori-f-b1` Queens Blvd Express/6 Av Local | metro | 8.565 | 1 | 16.56 / 25 | – | 0.5 | 2 / 0 | 0 → 0 | 0/0 | 6/6 | OK |
| us | `metropolitan-transit-authori-f-b2` Queens Blvd Express/6 Av Local | metro | 0.836 | 1 | 1.89 / 25 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 2/2 | OK |
| us | `metropolitan-transit-authori-franklin-avenue-shuttle` Franklin Avenue Shuttle | metro | 2.116 | 1 | 4.73 / 25 | – | -0.5 | 0 / 0 | 0 → 0 | 0/0 | 4/4 | OK |
| us | `metropolitan-transit-authori-fx` Brooklyn F Express | metro | 43.343 | 1 | 40.68 / 25 | – | -0.5 0.5 | 3 / 2 | 0 → 0 | 0/0 | 39/39 | reference-warning:40.68m>25m |
| us | `metropolitan-transit-authori-g` Brooklyn-Queens Crosstown | metro | 16.853 | 1 | 32.78 / 25 | – | -0.5 0.5 | 2 / 0 | 0 → 0 | 0/0 | 21/21 | reference-warning:32.78m>25m |
| us | `metropolitan-transit-authori-j` Nassau St Local | metro | 21.399 | 1 | 12.1 / 25 | – | -0.5 0.5 | 2 / 1 | 0 → 0 | 0/0 | 30/30 | OK |
| us | `metropolitan-transit-authori-l` 14 St-Canarsie Local | metro | 16.295 | 1 | 7.63 / 25 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 24/24 | OK |
| us | `metropolitan-transit-authori-m` Queens Blvd Local/6 Av Local | metro | 29.571 | 1 | 30.25 / 25 | – | -0.5 0.5 1 | 1 / 1 | 0 → 0 | 0/0 | 36/36 | reference-warning:30.25m>25m |
| us | `metropolitan-transit-authori-n` Broadway Local | metro | 32.596 | 1 | 12.93 / 25 | – | -0.5 | 3 / 2 | 0 → 0 | 0/0 | 35/35 | OK |
| us | `metropolitan-transit-authori-n-b1` Broadway Local | metro | 3.776 | 1 | 1.89 / 25 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 7/7 | OK |
| us | `metropolitan-transit-authori-r` Broadway Local | metro | 34.747 | 1 | 13.61 / 25 | – | -1.5 -1 -0.5 | 2 / 3 | 0 → 0 | 0/0 | 45/45 | OK |
| us | `metropolitan-transit-authori-rockaway-park-shuttle` Rockaway Park Shuttle | metro | 13.159 | 1 | 6.25 / 25 | – | -0.5 | 1 / 1 | 0 → 0 | 0/0 | 9/9 | OK |
| us | `metropolitan-transit-authori-sir` Staten Island Railway | commuter | 23.046 | 1 | 3.2 / 30 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 21/21 | OK |
| us | `metropolitan-transit-authori-w` Broadway Local | metro | 15.616 | 1 | 11.31 / 25 | – | 0 | 2 / 0 | 0 → 0 | 0/0 | 23/23 | OK |
| us | `metropolitan-transit-authori-z` Nassau St Express | metro | 21.392 | 1 | 9.53 / 25 | – | -0.5 | 2 / 0 | 0 → 0 | 0/0 | 21/21 | OK |
| us | `miami-dade-transit-2600` REGULAR METRORAIL SERVICE | commuter | 36.158 | 1 | 5.76 / 30 | – | 0 | 0 / 1 | 0 → 0 | 0/0 | 22/22 | OK |
| us | `miami-dade-transit-2600-b1` REGULAR METRORAIL SERVICE | commuter | 4.114 | 1 | 61.48 / 30 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 2/2 | reference-warning:61.48m>30m |
| us | `miami-dade-transit-mmi` METROMOVER INNER LOOP | streetcar | 3.344 | 1 | 4.62 / 20 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 9/9 | OK |
| us | `mta-long-island-rail-road-babylon-branch` Babylon Branch | commuter | 62.407 | 1 | 0 / 30 | – | 3 | 1 / 0 | 0 → 0 | 0/0 | 20/20 | OK |
| us | `mta-long-island-rail-road-city-terminal-zone` City Terminal Zone | commuter | 31.497 | 2 | 0 / 30 | – | -0.5 | 1 / 0 | 0 → 0 | 0/0 | 8/8 | branch-parts:2 |
| us | `mta-long-island-rail-road-far-rockaway-branch` Far Rockaway Branch | commuter | 36.341 | 1 | 0 / 30 | – | 3 | 2 / 0 | 0 → 0 | 0/0 | 16/16 | OK |
| us | `mta-long-island-rail-road-greenport-service` Greenport Service | commuter | 73.475 | 1 | 0 / 30 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 7/7 | OK |
| us | `mta-long-island-rail-road-hempstead-branch` Hempstead Branch | commuter | 33.895 | 1 | 0 / 30 | – | -0.5 | 2 / 0 | 0 → 0 | 0/0 | 15/15 | OK |
| us | `mta-long-island-rail-road-long-beach-branch` Long Beach Branch | commuter | 39.479 | 1 | 0 / 30 | – | 3 | 2 / 1 | 0 → 0 | 0/0 | 15/15 | OK |
| us | `mta-long-island-rail-road-montauk-branch` Montauk Branch | commuter | 189.343 | 1 | 0 / 30 | – | 3 | 0 / 7 | 1 → 0 | 0/0 | 19/19 | seam-jogs:1 |
| us | `mta-long-island-rail-road-oyster-bay-branch` Oyster Bay Branch | commuter | 56.008 | 1 | 0 / 30 | – | 3 | 1 / 0 | 0 → 0 | 0/0 | 13/13 | OK |
| us | `mta-long-island-rail-road-port-jefferson-branch` Port Jefferson Branch | commuter | 95.498 | 1 | 0 / 30 | – | 3 | 1 / 3 | 0 → 0 | 0/0 | 25/25 | OK |
| us | `mta-long-island-rail-road-ronkonkoma-branch` Ronkonkoma Branch | commuter | 81.138 | 1 | 0 / 30 | – | 3 | 1 / 0 | 0 → 0 | 0/0 | 23/23 | OK |
| us | `mta-long-island-rail-road-west-hempstead-branch` West Hempstead Branch | commuter | 36.025 | 1 | 0 / 30 | – | -0.5 | 1 / 2 | 0 → 0 | 0/0 | 10/10 | OK |
| us | `nashville-mta-wego-public-tr-90` WEGO STAR | commuter | 50.006 | 1 | 67 / 30 | 2 → none | 0 | 0 / 0 | 0 → 0 | 0/0 | 7/7 | withheld:2 osm-confirms-defect:2 |
| us | `new-jersey-transit-nj-transi-atlc` Atlantic City Rail Line | commuter | 108.658 | 1 | 9.99 / 30 | – | -0.5 | 0 / 1 | 0 → 0 | 0/0 | 9/9 | OK |
| us | `new-jersey-transit-nj-transi-bntn` Montclair-Boonton Line | commuter | 100.018 | 1 | 8.61 / 30 | – | -1 -0.5 0.5 1 | 3 / 0 | 0 → 0 | 0/0 | 27/27 | OK |
| us | `new-jersey-transit-nj-transi-bntn-b1` Montclair-Boonton Line | commuter | 12.496 | 1 | 3.1 / 30 | – | -2.5 -0.5 | 2 / 0 | 0 → 0 | 0/0 | 2/2 | OK |
| us | `new-jersey-transit-nj-transi-mnbn` Main/Bergen County Line | commuter | 49.293 | 1 | 4.61 / 30 | – | -1.5 -0.5 | 2 / 1 | 0 → 0 | 0/0 | 17/17 | OK |
| us | `new-jersey-transit-nj-transi-mnbn-b1` Main/Bergen County Line | commuter | 26.183 | 1 | 3.63 / 30 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 9/9 | OK |
| us | `new-jersey-transit-nj-transi-mnbnp` Port Jervis Line | commuter | 150.899 | 1 | 5.29 / 30 | – | -1.5 -0.5 | 0 / 7 | 0 → 0 | 0/0 | 25/25 | OK |
| us | `new-jersey-transit-nj-transi-mnbnp-b1` Port Jervis Line | commuter | 27.985 | 1 | 4.61 / 30 | – | 0 | 2 / 0 | 0 → 0 | 0/0 | 9/9 | OK |
| us | `new-jersey-transit-nj-transi-mne` Morris & Essex Line | commuter | 100.417 | 1 | 8.61 / 30 | – | -3 -1.5 -1 -0.5 | 1 / 6 | 0 → 0 | 0/0 | 26/26 | OK |
| us | `new-jersey-transit-nj-transi-mne-b1` Morris & Essex Line | commuter | 12.496 | 1 | 3.1 / 30 | – | -2.5 -1.5 -1 0 3.5 | 2 / 0 | 0 → 0 | 0/0 | 2/2 | OK |
| us | `new-jersey-transit-nj-transi-mneg` Gladstone Branch | commuter | 67.845 | 1 | 4.74 / 30 | – | -2.5 -1.5 -1 -0.5 | 2 / 2 | 0 → 0 | 0/0 | 24/24 | OK |
| us | `new-jersey-transit-nj-transi-mneg-b1` Gladstone Branch | commuter | 21.176 | 1 | 9.54 / 30 | – | -2 -1 -0.5 | 2 / 0 | 0 → 0 | 0/0 | 2/2 | OK |
| us | `new-jersey-transit-nj-transi-mneg-b2` Gladstone Branch | commuter | 28.566 | 1 | 7.34 / 30 | – | -2 -1 -0.5 | 2 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| us | `new-jersey-transit-nj-transi-mrl` Meadowlands Rail Line | commuter | 16.97 | 1 | 7.66 / 30 | – | -2.5 -1 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| us | `new-jersey-transit-nj-transi-nec` Northeast Corridor | commuter | 93.397 | 1 | 5.8 / 30 | – | -4 -2 -1 -0.5 0.5 | 1 / 1 | 0 → 0 | 0/0 | 16/16 | OK |
| us | `new-jersey-transit-nj-transi-njcl` North Jersey Coast Line | commuter | 107.01 | 1 | 5.8 / 30 | – | -3 -1 0.5 1 | 0 / 10 | 0 → 0 | 0/0 | 28/28 | OK |
| us | `new-jersey-transit-nj-transi-pasc` Pascack Valley Line | commuter | 49.391 | 1 | 4.22 / 30 | – | -1.5 -1 0.5 | 1 / 1 | 0 → 0 | 0/0 | 18/18 | OK |
| us | `new-jersey-transit-nj-transi-prin` Princeton Shuttle | commuter | 4.223 | 1 | 5.39 / 30 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 2/2 | OK |
| us | `new-jersey-transit-nj-transi-rarv` Raritan Valley Line | commuter | 89.05 | 1 | 5.8 / 30 | – | 0 2 | 1 / 0 | 0 → 0 | 0/0 | 21/21 | OK |
| us | `new-jersey-transit-nj-transi-rvln` Riverline Light Rail | lightrail | 54.148 | 1 | 3.68 / 25 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 21/21 | OK |
| us | `new-jersey-transit-nj-transi-nlr` Newark Light Rail | streetcar | 9.701 | 2 | 6.36 / 20 | – | 1.5 | 1 / 3 | 0 → 0 | 0/0 | 16/16 | branch-parts:2 |
| us | `new-jersey-transit-nj-transi-nlr-b1` Newark Light Rail | streetcar | 1.119 | 1 | 1.8 / 20 | – | 1.5 | 2 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| us | `north-county-transit-distric-498` COASTER | commuter | 65.435 | 1 | 10.14 / 30 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 8/8 | OK |
| us | `north-county-transit-distric-498-b1` COASTER | commuter | 5.374 | 1 | 3.68 / 30 | – | 0 | 0 / 1 | 0 → 0 | 0/0 | 2/2 | OK |
| us | `north-county-transit-distric-sprinter` SPRINTER | lightrail | 35.244 | 1 | 21.67 / 25 | – | 0 | 0 / 0 | 1 → 0 | 0/0 | 15/15 | seam-jogs:1 |
| us | `patco-speedline-patco` High Speed Line | metro | 22.897 | 1 | 26.57 / 25 | 8 → 8 | -0.5 | 0 / 0 | 0 → 0 | 0/0 | 14/14 | OK |
| us | `port-authority-of-allegheny-blue` BLUE | commuter | 17.687 | 1 | 388.91 / 30 | – | -1 -0.5 | 2 / 0 | 0 → 0 | 0/0 | 24/24 | reference-warning:388.91m>30m |
| us | `port-authority-of-allegheny-red` RED | commuter | 18.183 | 1 | 388.91 / 30 | – | 0 | 2 / 1 | 0 → 0 | 0/0 | 31/31 | reference-warning:388.91m>30m |
| us | `port-authority-of-allegheny-slvr` SILVER LINE | commuter | 22.799 | 1 | 14.06 / 30 | – | -0.5 | 0 / 3 | 0 → 0 | 0/0 | 31/31 | OK |
| us | `port-authority-trans-hudson-hoboken-33rd-street` Hoboken - 33rd Street | commuter | 4.632 | 1 | 22.4 / 30 | – | 1 | 1 / 0 | 0 → 0 | 0/0 | 6/6 | OK |
| us | `port-authority-trans-hudson-hoboken-world-trade-center` Hoboken - World Trade Center | commuter | 4.551 | 1 | 26.99 / 30 | – | 0.5 | 1 / 0 | 0 → 0 | 0/0 | 4/4 | OK |
| us | `port-authority-trans-hudson-journal-square-33rd-street-via-hoboken` Journal Square - 33rd Street (via Hoboken) | commuter | 10.86 | 2 | 22.67 / 30 | – | -3.5 -1 1 | 3 / 1 | 0 → 0 | 0/0 | 9/9 | branch-parts:2 |
| us | `port-authority-trans-hudson-newark-harrison-shuttle-train` Newark - Harrison Shuttle Train | commuter | 0.861 | 1 | 1.83 / 30 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 2/2 | OK |
| us | `port-authority-trans-hudson-world-trade-center-33rd-street` World Trade Center - 33rd Street | commuter | 8.58 | 1 | 9.28 / 30 | – | 0 | 0 / 4 | 1 → 0 | 0/0 | 8/8 | seam-jogs:1 |
| us | `san-francisco-municipal-tran-j-b4` CHURCH | lightrail | 2.834 | 1 | 1.76 / 25 | – | -1.5 2 | 1 / 0 | 0 → 0 | 0/0 | 5/5 | OK |
| us | `san-francisco-municipal-tran-t-b1` THIRD | lightrail | 1.316 | 1 | 9.43 / 25 | – | 0 | 0 / 1 | 0 → 0 | 0/0 | 3/3 | OK |
| us | `san-francisco-municipal-tran-ca` CALIFORNIA STREET CABLE CAR | funicular | 2.299 | 1 | 14.74 / 25 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 18/18 | OK |
| us | `san-francisco-municipal-tran-f` MARKET & WHARVES | streetcar | 8.175 | 1 | 9.99 / 20 | – | 1 2.5 | 1 / 2 | 0 → 0 | 0/0 | 30/30 | OK |
| us | `san-francisco-municipal-tran-f-b1` MARKET & WHARVES | streetcar | 1.718 | 1 | 7.46 / 20 | – | 1 | 1 / 0 | 0 → 0 | 0/0 | 6/6 | OK |
| us | `san-francisco-municipal-tran-f-b2` MARKET & WHARVES | streetcar | 4.369 | 1 | 9.99 / 20 | – | 1 2.5 | 1 / 0 | 0 → 0 | 0/0 | 16/16 | OK |
| us | `san-francisco-municipal-tran-j` CHURCH | streetcar | 10.585 | 1 | 5.99 / 20 | – | -1.5 2 | 1 / 4 | 0 → 0 | 0/0 | 25/25 | OK |
| us | `san-francisco-municipal-tran-j-b1` CHURCH | streetcar | 0.564 | 1 | 1.5 / 20 | – | 2 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| us | `san-francisco-municipal-tran-j-b2` CHURCH | streetcar | 0.248 | 1 | 1.67 / 20 | – | 2 | 1 / 0 | 0 → 0 | 0/0 | 2/2 | OK |
| us | `san-francisco-municipal-tran-j-b3` CHURCH | streetcar | 0.714 | 1 | 1.91 / 20 | – | 2 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| us | `san-francisco-municipal-tran-t` THIRD | streetcar | 10.67 | 1 | 12.56 / 20 | – | -2.5 | 1 / 2 | 0 → 0 | 0/0 | 22/22 | OK |
| us | `san-francisco-municipal-tran-t-b2` THIRD | streetcar | 0.958 | 1 | 3.75 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| us | `san-francisco-municipal-tran-t-b3` THIRD | streetcar | 0.969 | 1 | 4.61 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| us | `santa-clara-valley-transport-orange-line` Mountain View - Alum Rock | lightrail | 28.538 | 1 | 5.47 / 25 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 26/26 | OK |
| us | `septa-b2` Broad Street Line Express | metro | 11.676 | 1 | 25.26 / 25 | 1 → none | 0 | 0 / 1 | 0 → 0 | 0/0 | 8/8 | withheld:1 |
| us | `septa-b3` Broad-Ridge Spur | metro | 10.975 | 1 | 22.89 / 25 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 8/8 | OK |
| us | `septa-m1` Norristown High Speed Line Local | metro | 21.476 | 1 | 4.44 / 25 | – | 0 | 0 / 2 | 0 → 0 | 0/0 | 22/22 | OK |
| us | `septa-m1-b1` Norristown High Speed Line Local | metro | 2.791 | 1 | 1.97 / 25 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| us | `septa-m1-b2` Norristown High Speed Line Local | metro | 0.996 | 1 | 2.24 / 25 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 2/2 | OK |
| us | `septa-d1` Route 101 | streetcar | 13.841 | 1 | 292.42 / 20 | – | 0 | 0 / 1 | 0 → 0 | 0/0 | 35/35 | reference-warning:292.42m>20m |
| us | `septa-d2` Route 102 | streetcar | 8.461 | 1 | 370.36 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 26/26 | reference-warning:370.36m>20m |
| us | `septa-g1` 63rd-Girard to Richmond-Westmorelnd | streetcar | 14.44 | 3 | 357.09 / 20 | 3,4,7,8,48,49,50,51,52,53,54,55,56,57,58,59 → none | 0 | 2 / 10 | 0 → 0 | 0/0 | 61/61 | withheld:3,4,7,8,48,49,50,51,52,53,54,55,56,57,58,59 |
| us | `septa-g1-b1` 63rd-Girard to Richmond-Westmorelnd | streetcar | 0.869 | 1 | 3.78 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 4/4 | OK |
| us | `septa-g1-b2` 63rd-Girard to Richmond-Westmorelnd | streetcar | 0.396 | 1 | 5.36 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| us | `septa-g1-b3` 63rd-Girard to Richmond-Westmorelnd | streetcar | 1.286 | 1 | 357.09 / 20 | 2,3 → none | 0 | 1 / 0 | 0 → 0 | 0/0 | 5/5 | withheld:2,3 |
| us | `septa-g1-b4` 63rd-Girard to Richmond-Westmorelnd | streetcar | 0.483 | 1 | 0 / 20 | 0,1,2 → none | 0 | 2 / 0 | 0 → 0 | 0/0 | 4/4 | withheld:0,1,2 |
| us | `septa-g1-b5` 63rd-Girard to Richmond-Westmorelnd | streetcar | 0.817 | 1 | 4.46 / 20 | – | 0 | 2 / 0 | 0 → 0 | 0/0 | 4/4 | OK |
| us | `septa-g1-b6` 63rd-Girard to Richmond-Westmorelnd | streetcar | 0.161 | 1 | 1.21 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 2/2 | OK |
| us | `septa-t1` 13th St to 63rd-Malvern/Overbrook | streetcar | 9.411 | 1 | 398.98 / 20 | – | 0 | 1 / 5 | 0 → 0 | 0/0 | 39/39 | reference-warning:398.98m>20m |
| us | `septa-t1-b1` 13th St to 63rd-Malvern/Overbrook | streetcar | 1.197 | 1 | 331.81 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 5/5 | reference-warning:331.81m>20m |
| us | `septa-t1-b2` 13th St to 63rd-Malvern/Overbrook | streetcar | 3.251 | 1 | 213.59 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 16/16 | reference-warning:213.59m>20m |
| us | `septa-t1-b3` 13th St to 63rd-Malvern/Overbrook | streetcar | 0.561 | 1 | 1.78 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| us | `septa-t1-b4` 13th St to 63rd-Malvern/Overbrook | streetcar | 0.459 | 1 | 1.45 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| us | `septa-t1-b5` 13th St to 63rd-Malvern/Overbrook | streetcar | 0.368 | 1 | 1.66 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 5/5 | OK |
| us | `septa-t3` 13th St to Yeadon or Darby TC | streetcar | 11.041 | 1 | 396.35 / 20 | – | 0 | 1 / 4 | 0 → 0 | 0/0 | 47/47 | reference-warning:396.35m>20m |
| us | `septa-t3-b1` 13th St to Yeadon or Darby TC | streetcar | 0.593 | 1 | 378.91 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 4/4 | reference-warning:378.91m>20m |
| us | `septa-t3-b2` 13th St to Yeadon or Darby TC | streetcar | 1.318 | 1 | 396.35 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 6/6 | reference-warning:396.35m>20m |
| us | `septa-t3-b5` 13th St to Yeadon or Darby TC | streetcar | 0.169 | 1 | 1.97 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 2/2 | OK |
| us | `septa-t3-b6` 13th St to Yeadon or Darby TC | streetcar | 1.029 | 1 | 386.74 / 20 | – | 0 | 1 / 0 | 1 → 0 | 0/0 | 7/7 | seam-jogs:1 reference-warning:386.74m>20m |
| us | `septa-t4` 13th St to Darby Transit Center | streetcar | 10.7 | 1 | 370.96 / 20 | – | 0 | 1 / 1 | 0 → 0 | 0/0 | 47/47 | reference-warning:370.96m>20m |
| us | `septa-t4-b2` 13th St to Darby Transit Center | streetcar | 0.483 | 1 | 370.96 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | reference-warning:370.96m>20m |
| us | `septa-t4-b3` 13th St to Darby Transit Center | streetcar | 0.384 | 1 | 2.12 / 20 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| us | `septa-t5` 13th St to 80th St/Eastwick | streetcar | 11.316 | 1 | 388.55 / 20 | – | 0 | 0 / 9 | 0 → 0 | 0/0 | 45/45 | reference-warning:388.55m>20m |
| us | `septa-t5-b1` 13th St to 80th St/Eastwick | streetcar | 0.48 | 1 | 115.27 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | reference-warning:115.27m>20m |
| us | `septa-t5-b3` 13th St to 80th St/Eastwick | streetcar | 0.271 | 1 | 208.72 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | reference-warning:208.72m>20m |
| us | `septa-t5-b4` 13th St to 80th St/Eastwick | streetcar | 0.842 | 1 | 360.96 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 5/5 | reference-warning:360.96m>20m |
| us | `septa-t5-b5` 13th St to 80th St/Eastwick | streetcar | 0.578 | 1 | 388.55 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | reference-warning:388.55m>20m |
| us | `septa-t5-b7` 13th St to 80th St/Eastwick | streetcar | 0.384 | 1 | 2.12 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| us | `septa-t5-b8` 13th St to 80th St/Eastwick | streetcar | 0.113 | 1 | 272.1 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 2/2 | reference-warning:272.1m>20m |
| us | `shore-line-east-shore-line-east-train` Shore Line East Train | commuter | 81.514 | 1 | 13.3 / 30 | – | -0.5 0.5 | 1 / 0 | 0 → 0 | 0/0 | 9/9 | OK |
| us | `sound-transit-n-line` Everett - Seattle | commuter | 54.722 | 1 | 44.02 / 30 | 2 → 2 | -0.5 0.5 | 0 / 7 | 0 → 0 | 0/0 | 4/4 | OK |
| us | `sound-transit-t-line` Tacoma Dome - St Joseph | streetcar | 6.163 | 1 | 3.13 / 20 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 12/12 | OK |
| us | `south-florida-regional-trans-dml` Downtown Miami Link | commuter | 14.215 | 1 | 4.26 / 30 | – | -0.5 | 1 / 0 | 1 → 0 | 0/0 | 2/2 | seam-jogs:1 |
| us | `south-florida-regional-trans-mce` MiamiCentral Express | commuter | 117.612 | 1 | 63.17 / 30 | 1 → none | -0.5 | 4 / 1 | 1 → 0 | 0/0 | 5/5 | withheld:1 osm-confirms-defect:1 seam-jogs:1 |
| us | `south-florida-regional-trans-tr` Tri-Rail | commuter | 114.516 | 1 | 11.08 / 30 | – | -0.5 0.5 | 0 / 4 | 0 → 0 | 0/0 | 18/18 | OK |
| us | `south-shore-line-lakeshore` Lakeshore Corridor | commuter | 144.104 | 1 | 49.01 / 30 | 5 → 5 | -0.5 0 0.5 | 1 / 4 | 0 → 0 | 0/0 | 18/18 | OK |
| us | `south-shore-line-monon` Monon Corridor | commuter | 45.571 | 1 | 11.26 / 30 | – | -1 1 | 1 / 0 | 0 → 0 | 0/0 | 9/9 | OK |
| us | `thebus-skyline` SKYLINE | metro | 25.1 | 1 | 4.97 / 25 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 13/13 | OK |
| us | `trimet-portland-streetcar-a` Portland Streetcar - A Loop | streetcar | 9.873 | 1 | 7.43 / 20 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 29/29 | OK |
| us | `trinity-metro-texrail` TEXRail | lightrail | 42.034 | 1 | 5.39 / 25 | – | 0.5 | 0 / 0 | 0 → 0 | 0/0 | 9/9 | OK |
| us | `utah-transit-authority-uta-750` FrontRunner | commuter | 130.899 | 1 | 10.93 / 30 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 16/16 | OK |
| us | `utah-transit-authority-uta-701` Blue Line | lightrail | 19.086 | 1 | 1.67 / 25 | – | -0.5 | 1 / 0 | 0 → 0 | 0/0 | 12/12 | OK |
| us | `utah-transit-authority-uta-703` Red Line | lightrail | 23.086 | 1 | 1.79 / 25 | – | 0.5 | 0 / 1 | 0 → 0 | 0/0 | 14/14 | OK |
| us | `utah-transit-authority-uta-703-b1` Red Line | lightrail | 8.563 | 1 | 3.1 / 25 | – | 0.5 | 1 / 1 | 0 → 0 | 0/0 | 11/11 | OK |
| us | `utah-transit-authority-uta-703-b2` Red Line | lightrail | 1.307 | 1 | 1.24 / 25 | – | 0.5 | 1 / 0 | 0 → 0 | 0/0 | 2/2 | OK |
| us | `utah-transit-authority-uta-704` Green Line | lightrail | 13.85 | 1 | 3.44 / 25 | – | 0 | 0 / 2 | 0 → 0 | 0/0 | 14/14 | OK |
| us | `utah-transit-authority-uta-704-b1` Green Line | lightrail | 5.161 | 1 | 6.71 / 25 | – | 0 | 0 / 0 | 1 → 0 | 0/0 | 4/4 | seam-jogs:1 |
| us | `utah-transit-authority-uta-701-b1` Blue Line | streetcar | 5.585 | 1 | 1.5 / 20 | – | -0.5 | 1 / 0 | 0 → 0 | 0/0 | 11/11 | OK |
| us | `utah-transit-authority-uta-720` S-Line | streetcar | 3.081 | 1 | 0.72 / 20 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 7/7 | OK |
| us | `wmata-blue` Metrorail Blue Line | metro | 47.817 | 1 | 22.45 / 25 | – | -0.5 0.5 | 0 / 2 | 0 → 0 | 0/0 | 28/28 | OK |
| us | `wmata-green` Metrorail Green Line | metro | 36.732 | 1 | 26.18 / 25 | – | 0.5 | 0 / 1 | 0 → 0 | 0/0 | 21/21 | reference-warning:26.18m>25m |
| us | `wmata-orange` Metrorail Orange Line | metro | 41.991 | 1 | 6.41 / 25 | – | -1 0.5 | 1 / 0 | 0 → 0 | 0/0 | 26/26 | OK |
| us | `wmata-red` Metrorail Red Line | metro | 50.685 | 1 | 18.96 / 25 | – | 0.5 2 | 0 / 0 | 0 → 0 | 0/0 | 27/27 | OK |
| us | `wmata-yellow` Metrorail Yellow Line | metro | 17.071 | 1 | 20.54 / 25 | – | -1 0.5 | 2 / 0 | 0 → 0 | 0/0 | 13/13 | OK |
| ca | `go-transit-br` Barrie | commuter | 101.128 | 1 | 10.5 / 30 | – | -2 -1 0 | 1 / 6 | 0 → 0 | 0/0 | 11/11 | OK |
| ca | `go-transit-ki` Kitchener | commuter | 142.144 | 1 | 10.61 / 30 | – | -1.5 -0.5 0 1 | 3 / 2 | 0 → 0 | 0/0 | 14/14 | OK |
| ca | `go-transit-le` Lakeshore | commuter | 50.669 | 1 | 7.42 / 30 | – | -2 -0.5 | 0 / 2 | 0 → 0 | 0/0 | 10/10 | OK |
| ca | `go-transit-lw` Lakeshore | commuter | 132.18 | 1 | 9.72 / 30 | – | -0.5 3 5 | 0 / 6 | 0 → 0 | 0/0 | 15/15 | OK |
| ca | `go-transit-lw-b1` Lakeshore | commuter | 9.108 | 1 | 8.65 / 30 | – | -0.5 | 1 / 0 | 0 → 0 | 0/0 | 2/2 | OK |
| ca | `go-transit-mi` Milton | commuter | 50.363 | 1 | 5.06 / 30 | – | 1 2 | 1 / 3 | 0 → 0 | 0/0 | 9/9 | OK |
| ca | `go-transit-rh` Richmond Hill | commuter | 46.089 | 1 | 8.9 / 30 | – | -3 | 1 / 0 | 0 → 0 | 0/0 | 7/7 | OK |
| ca | `go-transit-st` Stouffville | commuter | 48.479 | 1 | 8.12 / 30 | – | -4 -0.5 | 1 / 0 | 0 → 0 | 0/0 | 10/10 | OK |
| ca | `amtrak-adirondack-ca` Adirondack | intercity | 6.058 | 1 | 8.71 / 50 | – | -0.5 | 2 / 0 | 0 → 0 | 0/0 | 2/2 | OK |
| ca | `edmonton-transit-system-capital` Capital Line | lightrail | 20.163 | 1 | 12.6 / 25 | – | -0.5 | 0 / 1 | 0 → 0 | 0/0 | 15/15 | OK |
| ca | `edmonton-transit-system-metro` Metro Line | lightrail | 15.449 | 1 | 12.6 / 25 | – | 0.5 | 1 / 0 | 0 → 0 | 0/0 | 14/14 | OK |
| ca | `edmonton-transit-system-valley` Valley Line | lightrail | 13.044 | 1 | 6.12 / 25 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 12/12 | OK |
| ca | `exo-ca` 14 - Candiac | commuter | 25.787 | 1 | 5.23 / 30 | – | -1 | 1 / 0 | 0 → 0 | 0/0 | 9/9 | OK |
| ca | `exo-ma` 15 - Mascouche | commuter | 41.543 | 1 | 3.2 / 30 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 11/11 | OK |
| ca | `exo-sh` 13 - Mont-Saint-Hilaire | commuter | 34.367 | 1 | 3.86 / 30 | – | -0.5 | 0 / 2 | 0 → 0 | 0/0 | 7/7 | OK |
| ca | `exo-sj` 12 - Saint-Jérôme | commuter | 61.992 | 1 | 3.61 / 30 | – | -1 | 0 / 2 | 0 → 0 | 0/0 | 14/14 | OK |
| ca | `exo-vh` 11 - Vaudreuil/Hudson | commuter | 51.374 | 1 | 5.13 / 30 | – | -0.5 | 1 / 1 | 0 → 0 | 0/0 | 18/18 | OK |
| ca | `grt-ion-light-rail-301` ION light rail | lightrail | 16.163 | 1 | 18.02 / 25 | – | 0 | 0 / 4 | 0 → 0 | 0/0 | 16/16 | OK |
| ca | `grt-ion-light-rail-301-b2` ION light rail | lightrail | 1.755 | 1 | 6.42 / 25 | – | 0 | 2 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| ca | `grt-ion-light-rail-301-b1` ION light rail | streetcar | 1.503 | 1 | 6.53 / 20 | – | 0 | 2 / 0 | 0 → 0 | 0/0 | 4/4 | OK |
| ca | `ottawa-carleton-regional-tra-1` Blair <> Tunney's Pasture | lightrail | 12.314 | 1 | 4.61 / 25 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 13/13 | OK |
| ca | `ottawa-carleton-regional-tra-2` Bayview <> Limebank | lightrail | 19.018 | 1 | 3.65 / 25 | – | 0 | 0 / 1 | 0 → 0 | 0/0 | 11/11 | OK |
| ca | `ottawa-carleton-regional-tra-4` South Keys <> Airport ~ Aéroport | lightrail | 4.114 | 1 | 4.76 / 25 | – | 1 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| ca | `translink-canada-line` Canada Line | metro | 14.276 | 1 | 21.7 / 25 | – | 0 | 0 / 1 | 0 → 0 | 0/0 | 14/14 | OK |
| ca | `translink-canada-line-b1` Canada Line | metro | 4.012 | 1 | 6.99 / 25 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 4/4 | OK |
| ca | `translink-expo-line` Expo Line | metro | 28.24 | 1 | 9.29 / 25 | – | 0 | 0 / 1 | 0 → 0 | 0/0 | 20/20 | OK |
| ca | `translink-expo-line-b1` Expo Line | metro | 7.488 | 1 | 9.15 / 25 | – | 0 | 2 / 0 | 0 → 0 | 0/0 | 5/5 | OK |
| ca | `translink-millennium-line` Millennium Line | metro | 25.139 | 1 | 6.91 / 25 | – | 0.5 | 0 / 1 | 0 → 0 | 0/0 | 17/17 | OK |
| ca | `translink-wce` West Coast Express | commuter | 67.318 | 1 | 11.77 / 30 | – | -0.5 | 0 / 0 | 0 → 0 | 0/0 | 8/8 | OK |
| ca | `ttc-4` Line 4 (Sheppard) | metro | 5.353 | 1 | 34.45 / 25 | – | 0 | 0 / 2 | 0 → 0 | 0/0 | 5/5 | reference-warning:34.45m>25m |
| ca | `ttc-4-b1` Line 4 (Sheppard) | metro | 1.485 | 1 | 16.46 / 25 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 2/2 | OK |
| ca | `ttc-4-b2` Line 4 (Sheppard) | metro | 0.942 | 1 | 34.12 / 25 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 2/2 | reference-warning:34.12m>25m |
| ca | `ttc-5` Line 5 Eglinton | lightrail | 18.588 | 1 | 34.52 / 25 | 21,22,23 → 21,22,23 | 0 | 0 / 2 | 0 → 0 | 0/0 | 25/25 | OK |
| ca | `ttc-5-b2` Line 5 Eglinton | lightrail | 1.477 | 1 | 3.62 / 25 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| ca | `ttc-6` Line 6 Finch | lightrail | 10.422 | 1 | 12.4 / 25 | – | 0 | 0 / 0 | 0 → 0 | 0/0 | 18/18 | OK |
| ca | `ttc-304` King | streetcar | 12.671 | 1 | 2.78 / 20 | – | -3 | 0 / 8 | 0 → 0 | 0/0 | 51/51 | OK |
| ca | `ttc-304-b1` King | streetcar | 1.842 | 1 | 1.41 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 7/7 | OK |
| ca | `ttc-304-b2` King | streetcar | 1.384 | 1 | 2.82 / 20 | – | -3 | 1 / 1 | 0 → 0 | 0/0 | 7/7 | OK |
| ca | `ttc-304-b3` King | streetcar | 0.394 | 1 | 1.47 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 2/2 | OK |
| ca | `ttc-304-b4` King | streetcar | 0.919 | 1 | 1.59 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 4/4 | OK |
| ca | `ttc-304-b5` King | streetcar | 0.713 | 1 | 1.84 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| ca | `ttc-304-b6` King | streetcar | 0.406 | 1 | 1.34 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 2/2 | OK |
| ca | `ttc-304-b7` King | streetcar | 0.516 | 1 | 2.54 / 20 | – | 0 | 2 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| ca | `ttc-304-b8` King | streetcar | 0.247 | 1 | 1.37 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 2/2 | OK |
| ca | `ttc-306` Carlton | streetcar | 15.444 | 1 | 22.02 / 20 | – | 0 | 0 / 6 | 0 → 0 | 0/0 | 64/64 | reference-warning:22.02m>20m |
| ca | `ttc-306-b2` Carlton | streetcar | 0.767 | 1 | 2.43 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 5/5 | OK |
| ca | `ttc-306-b4` Carlton | streetcar | 0.761 | 1 | 22.02 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | reference-warning:22.02m>20m |
| ca | `ttc-306-b5` Carlton | streetcar | 0.99 | 1 | 2.31 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 4/4 | OK |
| ca | `ttc-306-b6` Carlton | streetcar | 0.555 | 1 | 1.58 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| ca | `ttc-306-b7` Carlton | streetcar | 0.532 | 1 | 8.13 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| ca | `ttc-306-b8` Carlton | streetcar | 0.518 | 1 | 2.96 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| ca | `ttc-310` Spadina | streetcar | 5.309 | 1 | 10.33 / 20 | – | -5 | 0 / 5 | 0 → 0 | 0/0 | 18/18 | OK |
| ca | `ttc-310-b1` Spadina | streetcar | 0.762 | 1 | 1.66 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| ca | `ttc-310-b2` Spadina | streetcar | 0.146 | 1 | 4.07 / 20 | – | 0 | 2 / 0 | 0 → 0 | 0/0 | 2/2 | OK |
| ca | `ttc-310-b3` Spadina | streetcar | 0.286 | 1 | 1.36 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 2/2 | OK |
| ca | `ttc-5-b1` Line 5 Eglinton | streetcar | 1.654 | 1 | 1.81 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 4/4 | OK |
| ca | `ttc-509` Harbourfront | streetcar | 3.937 | 2 | 7.82 / 20 | – | 1 | 3 / 1 | 0 → 0 | 0/0 | 13/13 | branch-parts:2 |
| ca | `ttc-509-b1` Harbourfront | streetcar | 0.312 | 1 | 7.82 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| ca | `ttc-511` Bathurst | streetcar | 4.727 | 1 | 2.87 / 20 | – | 3 | 0 / 4 | 0 → 0 | 0/0 | 17/17 | OK |
| ca | `ttc-511-b1` Bathurst | streetcar | 0.591 | 1 | 1.42 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 3/3 | OK |
| ca | `ttc-511-b2` Bathurst | streetcar | 0.149 | 1 | 1.26 / 20 | – | 0 | 1 / 0 | 0 → 0 | 0/0 | 2/2 | OK |
| ca | `union-pearson-express-up-exp-up` Union Pearson Express | commuter | 24.231 | 1 | 8.62 / 30 | – | -1 -0.5 0.5 2 | 4 / 0 | 0 → 0 | 0/0 | 5/5 | OK |
| ca | `via-ottawa-montr-al` Ottawa - Montréal | intercity | 185.335 | 1 | 313 / 50 | 0 → none | -0.5 0.5 | 2 / 1 | 0 → 0 | 0/0 | 5/5 | withheld:0 osm-confirms-defect:0 |
| ca | `via-toronto-london` Toronto - London | intercity | 184.566 | 1 | 15.4 / 50 | – | -4 0.5 1 | 3 / 0 | 0 → 0 | 0/0 | 5/5 | OK |
| ca | `via-toronto-sarnia` Toronto - Sarnia | intercity | 289.424 | 1 | 14.21 / 50 | – | -4 -1 0.5 1.5 | 4 / 0 | 0 → 0 | 0/0 | 12/12 | OK |
| ca | `via-toronto-windsor` Toronto - Windsor | intercity | 358.552 | 1 | 23.47 / 50 | – | -4 0.5 1 | 2 / 2 | 0 → 0 | 0/0 | 10/10 | OK |
