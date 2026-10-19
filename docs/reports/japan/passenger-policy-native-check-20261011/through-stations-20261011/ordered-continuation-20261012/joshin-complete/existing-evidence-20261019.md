# Queue 85: jp-上信電鉄-上信線

Read-only source/receipt preparation, 2026-10-19. Current package 2025.5.2; 21 stations / 20 intervals; 高崎→下仁田. Canonical identity comes from unique lineID first appearance in the scoped queue, ordinal starts 2.

Legacy plan: 20/20 exact current source/display/station-ID interval identities. Completed captures: 67; matching identity + recorded receipt file presence/byte counts: 67/124; missing/unusable legacy views: 57. No image verdict follows from receipts.

Missing intervals: [0, 1, 2, 3, 4, 5, 6, 7, 19]. One existing-schema request prepared only in /private/tmp, not run: `/private/tmp/jtm-joshin-missing-request.json`.

Current display compared through the actual `app/public/rail-network.js` decoder and own displayPartsForLine; own3 carry no display/station/reversal aliases. All existing package aliases/frame repairs elsewhere are untouched.

| Interval | Stations | Legacy slot | Completed usable / planned | Missing |
|---|---|---:|---:|---:|
| 0 | 高崎→南高崎 | 506 | 0/4 | 4 |
| 1 | 南高崎→佐野のわたし | 507 | 0/5 | 5 |
| 2 | 佐野のわたし→根小屋 | 518 | 0/6 | 6 |
| 3 | 根小屋→高崎商科大学前 | 519 | 0/5 | 5 |
| 4 | 高崎商科大学前→山名 | 520 | 0/5 | 5 |
| 5 | 山名→西山名 | 521 | 0/4 | 4 |
| 6 | 西山名→馬庭 | 522 | 0/8 | 8 |
| 7 | 馬庭→吉井 | 523 | 0/8 | 8 |
| 8 | 吉井→西吉井 | 524 | 6/6 | 0 |
| 9 | 西吉井→上州新屋 | 525 | 5/5 | 0 |
| 10 | 上州新屋→上州福島 | 508 | 7/7 | 0 |
| 11 | 上州福島→東富岡 | 509 | 9/9 | 0 |
| 12 | 東富岡→上州富岡 | 510 | 4/4 | 0 |
| 13 | 上州富岡→西富岡 | 511 | 4/4 | 0 |
| 14 | 西富岡→上州七日市 | 512 | 4/4 | 0 |
| 15 | 上州七日市→上州一ノ宮 | 513 | 5/5 | 0 |
| 16 | 上州一ノ宮→神農原 | 514 | 8/8 | 0 |
| 17 | 神農原→南蛇井 | 515 | 9/9 | 0 |
| 18 | 南蛇井→千平 | 516 | 6/6 | 0 |
| 19 | 千平→下仁田 | 517 | 0/12 | 12 |

## Actual current stations

0: 高崎 (002389), 1: 南高崎 (002409), 2: 佐野のわたし (002422), 3: 根小屋 (002441), 4: 高崎商科大学前 (002445), 5: 山名 (002452), 6: 西山名 (002461), 7: 馬庭 (002465), 8: 吉井 (002479), 9: 西吉井 (002481), 10: 上州新屋 (002480), 11: 上州福島 (002478), 12: 東富岡 (002467), 13: 上州富岡 (002468), 14: 西富岡 (002469), 15: 上州七日市 (002474), 16: 上州一ノ宮 (002485), 17: 神農原 (002497), 18: 南蛇井 (002500), 19: 千平 (002508), 20: 下仁田 (002536)

## Limits

- Availability + exact own source/display/station-ID comparison only; no PNGs visually reviewed in this preparation.
- Recorded byte counts checked; no content hashes recomputed. No native/app/build/tests or production changes.
- Whole-line dependency recorded verbatim, not recomputed; named-plan relevant own interval geometry/station IDs compared directly.
- Request includes only intervals with missing/unusable old evidence; interval-level request may also capture already completed viewpoints within a partially completed interval.

## Next complete short interval review

- #12 東富岡→上州富岡: 4 complete pairs, legacy slot 510.
- #13 上州富岡→西富岡: 4 complete pairs, legacy slot 511.
- #14 西富岡→上州七日市: 4 complete pairs, legacy slot 512.

Actual recorded receipt files checked: 469; stale/bad completed views: 0. This pass actual original image review: 0 pairs / 0 PNGs. No native/build/tests/production/status actions.
