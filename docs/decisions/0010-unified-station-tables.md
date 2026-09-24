# ADR 0010 — One station-table schema and one code grammar per region

Date: 2026-09-23. Status: accepted.

## Context

The four Greater-China/Japan station tables under `app/data/` served the same readers with two
schemas and four code grammars:

| region | file | property keys | platform code shape (examples) |
|---|---|---|---|
| jp | `stations.json` | `N02_001 … N02_005g` | `003700` (uniform) |
| tw | `stations-tw.json` | neutral (`railway_class_code` …) | `TRA-0920`, `TRTC-R22`, `AFR-Q0000001651` (uniform `OP-ID`) |
| hk | `stations-hk.json` | neutral | `AEL-MTR-HOK`, `TKL-POA-MTR-NOP`, `LR-505-LR-100`, `TRAM-HV-105` (six shapes) |
| mo | `stations-mo.json` | neutral | `MLM-TAIPA-MLM-BARRA` |

Both iOS (`Stations.swift`) and the web port read `neutral || N02_*`, so the jp table was the only
one still shipping the raw MLIT key names. HK and MO codes embedded the *line* in the station
code, so one station carried a different code on every line (金鐘: `SIL-MTR-ADM`, `ISL-MTR-ADM`,
`TWL-MTR-ADM`, `EAL-LOW-MTR-ADM`), unlike jp and tw where the station code is the same on every
line and the group code carries the interchange complex. Readings rows also had two shapes
(jp `{name,kana,katakana,romaji,zh_Hant,zh_Hans}`; tw/hk/mo `{name,zh_Hant,zh_Hans,ja,en}`).

Station codes are persisted in saved rides (`n02_station_code` on every stop), so any change of
value needs a read-time alias; the shipped packages key stations by the *group* code, which is
unchanged.

## Decision

1. **One property schema for all four tables**, the neutral one the Taiwan builder documents:
   `railway_class_code, institution_type_code, line_name, operator, station_name,
   n02_station_code, n02_group_code, display_point` (+ optional `display_line_id`). The jp table
   is converted in place; values are untouched. Readers keep the `N02_*` fallback for old
   payloads but nothing shipped uses it any more.
2. **One platform-code grammar per region**, the station identity being the same on every line:
   jp `^\d{6}$`; tw `^[A-Z]+-[A-Za-z0-9]+$`; hk `^(MTR|LR|TRAM)-[A-Z0-9]+$`; mo `^MLM-[A-Z]+$`.
   HK/MO codes become `{OPERATOR}-{STOP}` — exactly the tail of the existing group code
   (`hk-official-mtr-adm` → `MTR-ADM`), which was verified unique (hk 282, mo 15) and identical for
   every line through a station. Taiwan's one three-part family, the Kaohsiung light rail
   (`KLRT-NETWORK-C1`, a TDX route artefact), drops the `NETWORK` segment (`KLRT-C1`). Group codes
   are unchanged everywhere, including `tw-official-klrt-network-c1`.
3. **Legacy codes stay readable.** `StationCodeAliases.canonical(_:)` (RailCore) and the web
   twin map the six old HK shapes, the MO shape and the KLRT shape to the new one by rule (last
   two segments when the second-last is `MTR|LR|MLM`; `TRAM-{last}` for trams; drop a `NETWORK`
   second segment); it is applied where persisted
   rides are decoded and where a code is looked up, so old saves resolve and re-save with the
   new code.
4. **One readings row shape**: every row carries `name, zh_Hant, zh_Hans, en, ja, kana, katakana,
   romaji` (empty string when the region has no such reading). `byCode` bare keys follow the
   platform-code grammar; the `lineId:groupCode` composite keys are unchanged.
5. `app/scripts/railway/validate-station-tables.py` asserts 1, 2 and 4 for all four regions and
   is part of `ios/verify.sh`. The web-repo builders (`build-hong-kong-rail-package.py`,
   `build-macao-rail-package.py`) emit the new grammar so a rebuild does not regress it; the jp
   table has no builder and is maintained in place.

## Consequences

- Readers, packages, display-network chunks, identity tables and the manual-corrections manifest
  are untouched (they key on group codes or on names).
- Sample rides (`train-store-hk/mo.json`, `StoreOperations.swift`, `app-store-ops.js`) and the
  hard-coded legacy codes in `RegionScope.swift`, `RegionCatalog.swift`, `StationNaming.swift`,
  `MergedStore.swift` are rewritten to the new grammar.
- `stationCodeSystem` still classifies `MTR-ADM` as the TDX-style shape; the label it prints is
  cosmetic.
- KR and NA tables are out of scope here; the validator only covers the four regions above.
