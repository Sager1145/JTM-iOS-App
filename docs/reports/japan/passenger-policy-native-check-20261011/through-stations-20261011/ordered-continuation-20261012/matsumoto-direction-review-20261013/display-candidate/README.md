# Matsumoto Oito display candidate

This candidate owns only `jp-東日本旅客鉄道-大糸線` display interval 31 and the optional display alias for station `002506`. It does not change physical source geometry, junctions, route direction, IDs, kilometre data, measured rows, or the independent Alpico transfer platform.

## Fit

- Retain physical source coordinates through index 6: `[137.9635, 36.23249]`.
- Replace the display-only physical-junction/tail pair with the exact native-frame midpoint of the manually identified western Oito platform-6 glyph: `[137.96367165960635, 36.231672714998382]`.
- Omit physical junction `matsumoto-east-56` from display ink. It remains unchanged in physical source and the registry.
- Candidate terminal bearing: `170.3841182341639°`.
- Reviewed platform axis bearing: `166.37713183529672°`.
- Acute axis difference: `4.006986398867184°`.
- Maximum candidate turn: `12.809713579853565°`; the candidate guard is `13°`.

The exact platform frame is view 3, candidate index 0. The eastern unresolved platform candidate and the Apple station POI are rejected. JR East's current Matsumoto 1F plan identifies the west terminal island as Oito platform 6 and the opposite side as Alpico platform 7: <https://www.jreast.co.jp/estation/stations/img/floormap/1444_1f.png>.

## Files

- `candidate.json`: schema-aligned display candidate
- `candidate.json.sha256`: candidate digest
- `reprojection-review.json`: all-four native-frame reprojection values
- `all4-candidate-reprojection.png`: red physical source versus cyan candidate contact sheet
- `view0-candidate-reprojection.png` through `view3-candidate-reprojection.png`: individual frame reviews
- `validate-candidate.mjs`: independent dependency, topology, lane, geometry, and evidence guard

## Verification

Both checks pass:

```sh
MATSUMOTO_CANDIDATE=/private/tmp/jtm-matsumoto-oito-display-candidate/candidate.json \
  node --test /private/tmp/jtm-matsumoto-display-owner-contract/matsumoto-display-owner.test.mjs

node /private/tmp/jtm-matsumoto-oito-display-candidate/validate-candidate.mjs \
  /private/tmp/jtm-matsumoto-oito-display-candidate/candidate.json \
  /Users/sager/Documents/GitHub/JTM-iOS-App
```

The owner contract passes 4/4. The independent validator reports eight display points, no topology change, and all candidate guards passed. Runtime acceptance remains pending temporary-resource review in the three Inspectors and Main ON/OFF.
