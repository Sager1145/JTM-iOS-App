# Identified Keiyo park and river main-track legs

Read-only bounded research2026-10-12. Coverage review is `review.md`; exact183camera manifest is `coverage.csv`. Current source snapshots and owning native part saved in `source-ownership.json`. Retained main passenger cache E139N35 fetched2026-08-18T10:37:59.411Z. Thirteen known-way OSM primary/full reads saved in `identified-primary-sources`; every primary node-coordinate sequence equals retained cache geometry. Thus these are identified connected chains, not tracks chosen merely by proximity. Primary original JSON preserves tags/version/node identities. `identified-passenger-chains.json` records both chains and exact joint nodes; `identified-source-reference.geojson` overlays them against decoded intervals11/12.

## Ownership

Package `app/public/rail/jp-2025.json`, exact line `jp-東日本旅客鉄道-京葉線`. Display overrides exist only intervals6,7,8,9; intervals11/12 therefore still use decoded physical geometry. Native `app/public/rail/display-lanes.json` has one Keiyo main part0,436supports, classification complex, carrying whole main line. Native Inspector viewport records original display/smooth part0. These viewports contain neighboring intervals too; ownership was established using the explicit decoded interval arrays, not inferred from the selected camera title.

Interval11 owns source chord[139.87176,35.64048]→[139.86614,35.64247] under main11 ordinal4. Interval12 owns[139.85457,35.64589]→[139.84976,35.64622] and[139.84928,35.64625]→[139.84172,35.6467] under main12 ordinal2/4. Decoded source and rendered display are aligned; this discrepancy cannot be resolved by changing smoothing alone.

## Same railway connected legs

Both chains have railway=rail, usage=main, JR Keiyo name, JR East operator,1067gauge,1500V electrification, viaduct/bridge tags, without siding/depot service. They retain the double-track corridor across Kyu-Edogawa, Kasai park, Arakawa and Shinkiba approach. Orienting east→west, chainA:

239710436→node1031594386→1241339785→node1031591437→22717984→node1031592140→239710437→node243658932→174040363→node243658933→174040360.

ChainB reverses individual source ways as needed to orient east→west:

239710447→node2474861809→239710443→node1031593673→1242538093→node2474861812→88877992→node1031593916→22717737→node31330099→680252570→node6369384000→239712148.

No node connector is invented. ChainA uses exact primary endpoint identities; chainB has the same explicit shared-node continuity. Preserve both physical track legs and identified bridges; no station floorplan research was performed.

## Strong cameras and bounded comparisons

| Selected view | Camera latitude,longitude | Owning source latitude at camera longitude | Identified trackA northward latitude difference | TrackB northward difference |
|---|---|---|---:|---:|
| Main11 ordinal4 / UIview5 |35.64126025959366,139.86955657402575|35.641260216670595|29.70m (1241339785)|34.47m (239710443)|
| Main12 ordinal2 / UIview3 |35.64592057920277,139.8541244037734|35.645920571050894|18.86m (239710437)|23.20m (22717737)|
| Main12 ordinal4 / UIview5 |35.6464213465975,139.84640232273316|35.646421290313505|13.00m (174040363)|18.19m (680252570)|

Comparisons interpolate latitude on the already identified chain edge at identical longitude and multiply latitude difference by111320m/degree. They describe northward components, not perpendicular surveyed error, nor screen-to-metre acceptance. Both parallel main tracks are north of retained source at all three cameras. This agrees with the observed Apple corridor separation and distinguishes the railway from roads/park paths. Arakawa bridgeA174040363 and bridgeB680252570 are each retained two-support straight spans; their exact bridge nodes connect their respective viaduct approaches.

## Decision boundary

Root GSI regional aerial corroboration remains needed before correction. Retained OSM and freshly retrieved primary objects corroborate each other, but are the same source ancestry, not two independent surveys. A supported bounded repair should affect only display through the identified park/bridge window, preserve decoded physical mileage/topology and station endpoints, retain adjacent guards, taper along the same railway without perpendicular join connectors, and refresh the owning main native part. Select a passenger representative between these explicitly identified paired tracks only after aerial review; do not replace with nearest track/road or extend a correction into unrelated interval/underground Tokyo. No source change, build, UI, test or broad verification occurred here.
