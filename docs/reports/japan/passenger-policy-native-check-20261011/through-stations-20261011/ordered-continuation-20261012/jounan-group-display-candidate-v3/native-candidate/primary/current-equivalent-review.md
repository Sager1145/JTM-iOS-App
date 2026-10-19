# Primary Inspector — V3 current-equivalent native review

Status: **ACCEPT current-equivalent Inspector scope.** This combines a fresh V3 review for the two changed lines with explicitly reused V1 evidence for four input-equivalent lines.

## Evidence composition

| Provenance | Lines | Intervals | Viewpoints | Panels | Review state |
| --- | --- | ---: | ---: | ---: | --- |
| Fresh V3 | 城南線, 花園線 | 12 | 30 | 90 | manual pixel review accepted |
| Reused V1, current-equivalent inputs | 城北線, 大手町線, 本町線, 連絡線 | 17 | 41 | 123 | V1 complete manual review accepted; Root confirmed current source/display inputs and native rows equal |
| **Current-equivalent total** | six lines | **29** | **71** | **213** | accepted for this Inspector |

The 71 viewpoints are a composition of 30 freshly captured V3 viewpoints and 41 reused V1 viewpoints. They are not 71 fresh V3 viewpoints.

## Exact 29-item inventory

Fresh V3 item IDs (viewpoints in parentheses):

`jp-伊予鉄道-城南線#0` (2), `jp-伊予鉄道-城南線#1` (2), `jp-伊予鉄道-城南線#2` (3), `jp-伊予鉄道-城南線#3` (2), `jp-伊予鉄道-城南線#4` (3), `jp-伊予鉄道-城南線#5` (3), `jp-伊予鉄道-城南線#6` (2), `jp-伊予鉄道-城南線#7` (2), `jp-伊予鉄道-城南線#8` (3), `jp-伊予鉄道-城南線#9` (3), `jp-伊予鉄道-城南線#10` (2), `jp-伊予鉄道-花園線#0` (3).

Reused V1 current-equivalent item IDs (viewpoints in parentheses):

`jp-伊予鉄道-城北線#0` (2), `jp-伊予鉄道-城北線#1` (2), `jp-伊予鉄道-城北線#2` (3), `jp-伊予鉄道-城北線#3` (3), `jp-伊予鉄道-城北線#4` (2), `jp-伊予鉄道-城北線#5` (2), `jp-伊予鉄道-城北線#6` (3), `jp-伊予鉄道-城北線#7` (3), `jp-伊予鉄道-大手町線#0` (2), `jp-伊予鉄道-大手町線#1` (3), `jp-伊予鉄道-大手町線#2` (2), `jp-伊予鉄道-大手町線#3` (3), `jp-伊予鉄道-本町線#0` (2), `jp-伊予鉄道-本町線#1` (2), `jp-伊予鉄道-本町線#2` (2), `jp-伊予鉄道-本町線#3` (3), `jp-伊予鉄道-連絡線#0` (2).

The item list totals 29 intervals, 71 viewpoints, and 213 panels. Fresh captures report 30 captured, 0 pending, and 0 failed. Reuse is limited to the four lines named in `unchanged-four-line-reuse.json`; no V1 Jounan or Hanazono acceptance is carried forward.

## Evidence references and hashes

- Gate-compatible current-equivalent report: `docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/ordered-continuation-20261012/jounan-group-display-candidate-v3/native-candidate/primary/current-equivalent-report.json`, SHA-256 `3ab788a4d6c11ba7e36efb3b69764b0f5eabf5640bcb728bf7464001d79bd57f`. Its top-level `capturedCount: 71` is explicitly composed of 30 fresh V3 captures and 41 reused V1 current-equivalent captures; the 29 interval records retain that provenance individually.
- V3 candidate: `docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/ordered-continuation-20261012/jounan-group-display-candidate-v3/candidate.json`, SHA-256 `e5c87f0e10dfa935f766a39fdd8d2cc87b96bfa521bae4dfbef3c609a100a491`.
- Fresh V3 report: `docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/ordered-continuation-20261012/jounan-group-display-candidate-v3/native-candidate/primary/fresh-report.json`, SHA-256 `f61f1d7c789a0e88fea6e4b3f1002f2695e91a3175c0e50105424b39a675fc6c`.
- Fresh V3 scope receipts: `docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/ordered-continuation-20261012/jounan-group-display-candidate-v3/native-candidate/primary/fresh-scope-receipts.json`, SHA-256 `6b253f181c5fc9c32fc48c9806d6c9cb0c0817a90a0b6ba77be5d7f83ecf7c57`.
- Fresh V3 manual review: `docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/ordered-continuation-20261012/jounan-group-display-candidate-v3/native-candidate/primary/fresh-native-review.md`, SHA-256 `8f21d30e3bfad72c9d83659bfe3ac766a3131554bcaa572c463e2ee0fd14903e`.
- Root-confirmed input-equivalence record: `docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/ordered-continuation-20261012/jounan-group-display-candidate-v3/native-candidate/unchanged-four-line-reuse.json`, SHA-256 `d008250bc60419c1952799bf0bd372e50f08a2d6abcf8eae53e2894e2364b4f3`.
- Reused V1 complete report: `docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/ordered-continuation-20261012/jounan-group-display-candidate-v1/native-candidate/primary/report.json`, SHA-256 `ce49f8067b2c4617f074165c29c12f146699d3c2e64502c4d39ea767edd6579e`.
- Reused V1 complete manual review: `docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/ordered-continuation-20261012/jounan-group-display-candidate-v1/native-candidate/primary/native-review.md`, SHA-256 `3cdd71de8009664a5a36c812055055b23570e2b7b453caf02caf0ef3155f48b9`. Only its 城北線, 大手町線, 本町線, and 連絡線 findings are reused here.

## Boundary

This document is a static Inspector evidence composition. It does not alter the evidence gate or parent ledger, does not convert reused panels into fresh captures, and does not establish Main-app or production-source acceptance. Apple cartographic casing and labels retain the precision limits stated in the underlying manual reviews.

