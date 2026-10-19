# Queue 62: jp-とさでん交通-後免線

Read-only source/receipt preparation, 2026-10-18. Current package 2025.5.2; 33 stations / 32 intervals; はりまや橋→後免町. Canonical identity comes from unique lineID first appearance in the scoped queue, ordinal starts 2.

Legacy plan: 32/32 exact current source/display/station-ID interval identities. Completed captures: 39; matching identity + recorded receipt file presence/byte counts: 39/81; missing/unusable legacy views: 42. No image verdict follows from receipts.

Missing intervals: [0, 5, 7, 8, 10, 12, 16, 18, 19, 20, 21, 23, 24, 25, 27, 30, 31]. One existing-schema request prepared, not run: `missing-native-request-20261018.json`; scratch copy `/private/tmp/jtm-tosaden-gomen-missing-request.json`.

| Interval | Stations | Legacy slot | Completed usable / planned | Missing |
|---|---|---:|---:|---:|
| 0 | はりまや橋→デンテツターミナルビル前 | 226 | 0/2 | 2 |
| 1 | デンテツターミナルビル前→菜園場町 | 227 | 3/3 | 0 |
| 2 | 菜園場町→宝永町 | 238 | 3/3 | 0 |
| 3 | 宝永町→知寄町一丁目 | 249 | 2/2 | 0 |
| 4 | 知寄町一丁目→知寄町二丁目 | 252 | 2/2 | 0 |
| 5 | 知寄町二丁目→知寄町 | 253 | 0/2 | 2 |
| 6 | 知寄町→知寄町三丁目 | 254 | 3/3 | 0 |
| 7 | 知寄町三丁目→葛島橋東詰 | 255 | 0/3 | 3 |
| 8 | 葛島橋東詰→西高須 | 256 | 0/2 | 2 |
| 9 | 西高須→県立美術館通 | 257 | 2/2 | 0 |
| 10 | 県立美術館通→高須 | 228 | 0/2 | 2 |
| 11 | 高須→文珠通 | 229 | 2/2 | 0 |
| 12 | 文珠通→介良通 | 230 | 0/3 | 3 |
| 13 | 介良通→新木 | 231 | 3/3 | 0 |
| 14 | 新木→東新木 | 232 | 2/2 | 0 |
| 15 | 東新木→田辺島通 | 233 | 3/3 | 0 |
| 16 | 田辺島通→鹿児 | 234 | 0/3 | 3 |
| 17 | 鹿児→舟戸 | 235 | 3/3 | 0 |
| 18 | 舟戸→北浦 | 236 | 0/3 | 3 |
| 19 | 北浦→領石通 | 237 | 0/3 | 3 |
| 20 | 領石通→清和学園前 | 239 | 0/3 | 3 |
| 21 | 清和学園前→一条橋 | 240 | 0/2 | 2 |
| 22 | 一条橋→明見橋 | 241 | 3/3 | 0 |
| 23 | 明見橋→長崎 | 242 | 0/2 | 2 |
| 24 | 長崎→小篭通 | 243 | 0/3 | 3 |
| 25 | 小篭通→篠原 | 244 | 0/3 | 3 |
| 26 | 篠原→住吉通 | 245 | 3/3 | 0 |
| 27 | 住吉通→東工業前 | 246 | 0/2 | 2 |
| 28 | 東工業前→後免西町 | 247 | 3/3 | 0 |
| 29 | 後免西町→後免中町 | 248 | 2/2 | 0 |
| 30 | 後免中町→後免東町 | 250 | 0/2 | 2 |
| 31 | 後免東町→後免町 | 251 | 0/2 | 2 |

## Actual current stations

0: はりまや橋 (009117), 1: デンテツターミナルビル前 (009120), 2: 菜園場町 (009126), 3: 宝永町 (009130), 4: 知寄町一丁目 (009133), 5: 知寄町二丁目 (009135), 6: 知寄町 (009137), 7: 知寄町三丁目 (009139), 8: 葛島橋東詰 (009146), 9: 西高須 (009134), 10: 県立美術館通 (009128), 11: 高須 (009122), 12: 文珠通 (009121), 13: 介良通 (009115), 14: 新木 (009110), 15: 東新木 (009106), 16: 田辺島通 (009101), 17: 鹿児 (009093), 18: 舟戸 (009088), 19: 北浦 (009084), 20: 領石通 (009081), 21: 清和学園前 (009074), 22: 一条橋 (009076), 23: 明見橋 (009075), 24: 長崎 (009073), 25: 小篭通 (009069), 26: 篠原 (009065), 27: 住吉通 (009067), 28: 東工業前 (009068), 29: 後免西町 (009070), 30: 後免中町 (009072), 31: 後免東町 (009078), 32: 後免町 (009077)

## Limits

- Availability + exact own source/display/station-ID comparison only; no PNGs visually reviewed in this preparation.
- Recorded byte counts checked; no content hashes recomputed. No native/app/build/tests or production changes.
- Whole-line dependency recorded verbatim, not recomputed; named-plan relevant own interval geometry/station IDs compared directly.
- Request includes only intervals with missing/unusable old evidence; interval-level request may also capture already completed viewpoints within a partially completed interval.
