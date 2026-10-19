# Queue 82: jp-三陸鉄道-リアス線

Read-only source/receipt preparation, 2026-10-19. Current package 2025.5.2; 15 stations / 14 intervals; 宮古→釜石. Canonical identity comes from unique lineID first appearance in the scoped queue, ordinal starts 2.

Legacy plan: 14/14 exact current source/display/station-ID interval identities. Completed captures: 135; matching identity + recorded receipt file presence/byte counts: 135/179; missing/unusable legacy views: 44. No image verdict follows from receipts.

Missing intervals: [1, 2, 3, 4]. One existing-schema request prepared only in /private/tmp, not run: `/private/tmp/jtm-sanriku-rias-missing-request.json`.

Current display compared through the actual `app/public/rail-network.js` decoder and own displayPartsForLine; own3 carry no display/station/reversal aliases. All existing package aliases/frame repairs elsewhere are untouched.

| Interval | Stations | Legacy slot | Completed usable / planned | Missing |
|---|---|---:|---:|---:|
| 0 | 宮古→磯鶏 | 466 | 7/7 | 0 |
| 1 | 磯鶏→八木沢・宮古短大 | 467 | 0/7 | 7 |
| 2 | 八木沢・宮古短大→津軽石 | 472 | 0/17 | 17 |
| 3 | 津軽石→払川 | 473 | 0/7 | 7 |
| 4 | 払川→豊間根 | 474 | 0/13 | 13 |
| 5 | 豊間根→陸中山田 | 475 | 33/33 | 0 |
| 6 | 陸中山田→織笠 | 476 | 5/5 | 0 |
| 7 | 織笠→岩手船越 | 477 | 12/12 | 0 |
| 8 | 岩手船越→浪板海岸 | 478 | 20/20 | 0 |
| 9 | 浪板海岸→吉里吉里 | 479 | 7/7 | 0 |
| 10 | 吉里吉里→大槌 | 468 | 11/11 | 0 |
| 11 | 大槌→鵜住居 | 469 | 13/13 | 0 |
| 12 | 鵜住居→両石 | 470 | 8/8 | 0 |
| 13 | 両石→釜石 | 471 | 19/19 | 0 |

## Actual current stations

0: 宮古 (000814), 1: 磯鶏 (000819), 2: 八木沢・宮古短大 (000826), 3: 津軽石 (000835), 4: 払川 (000839), 5: 豊間根 (000846), 6: 陸中山田 (000856), 7: 織笠 (000857), 8: 岩手船越 (000860), 9: 浪板海岸 (000870), 10: 吉里吉里 (000872), 11: 大槌 (000876), 12: 鵜住居 (000884), 13: 両石 (000897), 14: 釜石 (000919)

## Limits

- Availability + exact own source/display/station-ID comparison only; no PNGs visually reviewed in this preparation.
- Recorded byte counts checked; no content hashes recomputed. No native/app/build/tests or production changes.
- Whole-line dependency recorded verbatim, not recomputed; named-plan relevant own interval geometry/station IDs compared directly.
- Request includes only intervals with missing/unusable old evidence; interval-level request may also capture already completed viewpoints within a partially completed interval.

## Next complete short interval review

- #6 陸中山田→織笠: 5 complete pairs, legacy slot 476.
- #0 宮古→磯鶏: 7 complete pairs, legacy slot 466.
- #9 浪板海岸→吉里吉里: 7 complete pairs, legacy slot 479.

Actual recorded receipt files checked: 945; stale/bad completed views: 0. No original pixels viewed or accepted.
