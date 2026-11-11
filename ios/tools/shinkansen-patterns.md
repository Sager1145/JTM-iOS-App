# Shinkansen stop-pattern source files

Input format of `ios/tools/build-shinkansen-patterns.py`. One authored JSON file per
timetable revision and line group goes in `app/data/shinkansen-patterns/` (the
directory does not exist yet: no real train-number data is bundled). The script
turns them into the `variants` key of the base records in
`ios/RailKit/Sources/RailCore/Resources/train-service-patterns.json`. Never edit a
`variants` block by hand; the check refuses a bundled file that differs from what the
sources generate.

Design: `docs/maintenance/2026-11-11-shinkansen-database-design.md`. The data model
and lookup are `TrainPatternVariants.swift` and `TrainPatternLookup.swift` in RailCore.

## Ground rule: no number-to-pattern logic

Same-named trains can have different stop patterns, and numbers need not follow any
logic. Therefore:

- Every pattern lists its train numbers explicitly, per direction.
- A range `"101-105"` is shorthand for consecutive numbers 101, 102, 103, 104, 105 that
  were each checked in the cited table. It is never a parity range and never a block.
  The bundled file stores the expanded numbers.
- Lookup is an exact match on (service name, train number, date, day type). It never
  interpolates or infers from neighbouring numbers, number blocks or odd/even parity.
  A number that is not listed is "pattern not known", even if its neighbours are listed.
- Direction (`down` = the base record's stop order, `up` = reverse) is written per
  group of numbers, never derived from parity.
- The same number may appear in different patterns on different days or revisions, if
  the days provably do not intersect (different revisions, disjoint `validFrom` /
  `validUntil` windows on the groups, or `weekdays` against `holidays`). Anything else is an
  error (`numberInTwoPatterns`).
- Odd-down/even-up is a validator warning (`parityConvention`) only.

## File

```json
{
  "schema": 1,
  "lineGroup": "tokaido-sanyo",
  "revision": "<id, normally the start date>",
  "validFrom": "YYYY-MM-DD",
  "validUntil": null,
  "checkedOn": "YYYY-MM-DD",
  "status": "unverified",
  "source": {"type": "operator_timetable", "publisher": "...", "title": "...",
             "locator": "URL, or issue and page", "accessedAt": "YYYY-MM-DD", "license": "..."},
  "verifiedBy": "required only when status is verified",
  "services": [
    {"pattern": "<patternId of a base record in the bundled file>",
     "patterns": [
       {"id": "a",
        "stops": ["東京", "品川", "..."],
        "trains": [
          {"direction": "down", "numbers": [23, "25-27"]},
          {"direction": "up", "numbers": [24], "runs": "weekdays",
           "validFrom": "YYYY-MM-DD", "validUntil": "YYYY-MM-DD"}
        ],
        "coupled": {"service": "<serviceId>", "from": "<station code>", "to": "<station code>", "number": "same"}}
     ]}
  ]
}
```

- `stops`: full station names in running order, as printed in the table, for every call
  of that pattern (the generator derives `from`, `to` and `calls`). Names are resolved
  against the Shinkansen row of the record's corridor, so a same-name conventional
  station is never picked.
- `validUntil` is exclusive; null only for the revision in force. Revisions of one record
  must not overlap and must lie inside the record's own dates.
- `status: verified` needs `source.type` of `operator_timetable` or `printed_timetable`
  and a `verifiedBy` second reader. Any other source type can only be `unverified`.
- `runs`: `daily` (default), `weekdays`, `holidays` (Saturdays, Sundays, public
  holidays) or `extra` (seasonal or extra trains on announced days only).
- `coupled` is optional; the partner service and both stations must exist in the bundled
  file. A partner that does not couple back is a warning.

## Rules checked (`--check`)

New-key rules (always errors, they fail the regression guard): corridor resolvable;
every stop a station of the record's Shinkansen corridor, by the Shinkansen row's
identity; stops strictly increasing along the corridor; every always-served stop between a
pattern's ends present; every other call an optional stop of the record; `order` holds
exactly the always-served and optional stops in corridor order; `allStations` records list
every corridor station between their ends, have no optional stops and no variants;
revisions have a citation, a status and real dates, do not overlap, lie inside the record,
only the last is open; group windows lie inside their revision; numbers are positive,
unique within a group and, across patterns of one service, not shared on overlapping days;
pattern ids unique per revision; `coupled` partners exist; bundled `variants` equal what
the sources generate; no record has `variants` without a source file.

Base-data rules (notes by default, errors with `--strict`): every stop of an existing
Shinkansen base record is a station of its corridor's Shinkansen row (name and code),
`stops` and `optionalStops` are each in corridor order and disjoint. These cover data that
another branch is correcting; the guard switches to `--strict` when it has landed.

Warnings (never fail): `parityConvention`, `coupledNotReciprocal`, `allStationsCandidate`
(a record lists every corridor station as always served but is not flagged `allStations`;
the flag needs a cited source).

## What must not be done

- Do not write a stop list, number or range from memory or general knowledge of a service.
  Transcribe from the cited table of that revision only.
- Do not fill a gap by analogy ("23 probably stops like 25"). A number not read from the
  table is not in the table.
- Do not copy a revision forward to a new date. A new revision is a new source file.
- Do not mark anything `verified` without a second read.
