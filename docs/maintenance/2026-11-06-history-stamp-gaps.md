# History stamp gaps (2026-11-06)

Guard: `RegressionGuardHistoryStamps` (`ios/RailKit/Tests/RailCoreTests/RegressionGuards/HistoryStampGuardTests.swift`).
Baseline (shrink-only): `ios/RailKit/Tests/RailCoreTests/RegressionGuards/Resources/history-stamp-baseline.json`.
Regenerate it with:

`JTM_REGENERATE_EXPECTATIONS=1 swift test --package-path ios/RailKit --filter RegressionGuardHistoryStamps`

A new violation fails the guard; a baseline entry that stops occurring also fails ("remove it from the baseline").
Events come from `app/scripts/railway/jp-rail-history-events.json`; the stamps are the `retirements` in
`app/data/rail-history.json` (builder: website-side `build-jp-rail-history.py`).

## 1. Restored (Toyama-type regressions, fixed in rail-history.json revision 2026-10-11.3)

The 2026-10-19 rebuild (`2535b4bee`) narrowed these stamps. `2535b4bee~1` (`22b8c6858`, revision 2026-09-28.3) and
`d0b7f77a4`, `aa783e808`, `542e44ed9` stamped every feature of the line; the entries were restored byte-for-byte from
`2535b4bee~1:app/data/rail-history.json`.

| event | line | uncovered before restore (sections / stations) |
| --- | --- | --- |
| jp.opening.sendai-airport | 仙台空港線 | 2 of 8 / 1 of 4 |
| jp.opening.yokohama-green | 4号線 | 4 of 19 / 3 of 10 (22 split stamps replaced by the 2 original) |
| jp.opening.nakanoshima | 中之島線 | 1 of 9 / 1 of 5 |
| jp.opening.mojiko-retro | 門司港レトロ観光線 | 6 of 7 / 3 of 4 |
| jp.opening.tokyu-shin-yokohama | 東急新横浜線 | 1 of 5 / 1 of 3 |
| jp.opening.hokkaido-shinkansen | 北海道新幹線 | 1 of 9 / 1 of 4 |

## 2. Pre-existing gaps (baselined, data not edited)

Each event first appears in the `h2005.h1` rebuild. No checked revision (`d44bdc5cd`, `544ef4566`, `542e44ed9`,
`aa783e808`, `d0b7f77a4`, `2535b4bee~1`) carried a stamp for it, so there is no earlier stamp to restore. They need an
N02-edition review: `new_since_release` may legitimately exclude pre-existing features.

| event | line | uncovered sections | uncovered stations |
| --- | --- | --- | --- |
| jp.h2005.h1.hanshin-namba-extension | 阪神なんば線 | 3 of 9 | 1 of 4 |
| jp.h2005.h1.hokuriku-shinkansen-kanazawa-tsuruga | 北陸新幹線 | 1 of 13 | - |
| jp.h2005.h1.hokuriku-shinkansen-nagano-joetsu | 北陸新幹線 | 1 of 5 | - |
| jp.h2005.h1.kitaosaka-senrichuo-minoh | 南北線 | 1 of 5 | - |
| jp.h2005.h1.kyushu-shinkansen-hakata | 九州新幹線 | 2 of 16 | 1 of 7 |
| jp.h2005.h1.narita-sky-access | 成田空港線 | 4 of 7 | 1 of 2 |
| jp.h2005.h1.osaka-higashi-north | おおさか東線 | 3 of 12 | 1 of 6 |
| jp.h2005.h1.osaka-higashi-south | おおさか東線 | 2 of 14 | 1 of 6 |
| jp.h2005.h1.sotetsu-hazawa-shinyokohama | 相鉄新横浜線 | 1 of 3 | - |
| jp.h2005.h1.tohoku-shinkansen-shinaomori | 東北線 | 1 of 5 | - |

(10 events, 15 baseline entries.) What was checked: stamp coverage per target at each revision above, against the
current `rail-sections.json` and `stations.json` bounds.
