# Station numbering: a stable identity for North American stations

North American station ids are derived from station names, and names collide.
`us-official-healy` is the Alaska Railroad's Healy and Metra's Healy, 4,531 km
apart, sharing one id. It is not an isolated fault: **70 ids span more than
2 km and 63 span more than 100 km.**

Japan, shipped in this same repository, has none. This document specifies why,
and a scheme that gives North America the same property.

## The evidence

Both systems measured identically — the maximum distance between any two
coordinates carrying one station id.

| spread between coordinates sharing an id | North America | Japan |
| --- | --- | --- |
| more than 250 m | 209 | 36 |
| more than 500 m | 91 | 2 |
| more than 2 km | **70** | **0** |
| more than 100 km | **63** | **0** |
| widest | 4,531 km (`us-official-healy`) | 549 m (新宿) |

Japan's multi-coordinate ids are all one station: platforms of a complex,
median spread 97 m. The widest is Shinjuku, which genuinely sprawls that far.
**549 m is therefore an empirical bound**, taken from the busiest interchange
in the world, for how far apart two points can be and still be one station.
Every North American id beyond it is a collision rather than a complex.

## Why Japan does not collide

Two codes, both issued by the survey authority (MLIT N02), neither derived
from a name:

- **`N02_005c`, the station code** — one per platform feature: a station as one
  operator's one line calls at it. 倶利伽羅 is `001986` on the IR Ishikawa line
  and `001987` on the Ainokaze Toyama line.
- **`N02_005g`, the group code** — the interchange unifier. Both 倶利伽羅 rows
  carry group `001986`. It is a member code promoted, not a separate namespace:
  the group code equals the numerically lowest member code for 8,942 of 9,046
  groups.

They differ for 1,146 of 10,233 platform features. The display package ships
the **group** code; `station-readings.json`'s `byCode` is keyed by the
**station** code. See `app/scripts/build/rail-database/schema.sql:400-405`.

Japan has 425 station names that map to more than one id — 市役所前 appears
eight times. Two 府中 are simply two numbers. Merging is the opposite operation
and is *also* sourced, so the codebase never infers an interchange from
proximity or from a name.

The property that matters is not that the code is numeric. It is that the code
is **assigned rather than derived**, and that something durable remembers the
assignment.

## What North America already has, and what it lacks

It already has the platform-level analogue.
`build-north-america-rail-package.py:4406-4414` mints
`{REGION}-{FEED}-{OPERATOR}-{stopId}-{GROUPCODE}`, which corresponds to
`N02_005c` and is collision-free, because a feed's own stop id is unique
within the feed.

What is missing is the group code. `build_region()`
(`build-north-america-rail-package.py:4148-4156`) mints it as:

```python
base = slugify(normalise_station_name(group['name']) or group['name'], 'stn')
code = f'{region}-official-{base}'
n = 1
while code in used:
    n += 1
    code = f'{region}-official-{base}-{n}'
```

`used` is a per-`build_region()` set — one region, one process, over only the
feeds that build actually built. Three consequences follow, and all three are
observed:

1. **A name collision is an id collision.** Two Healys, one slug.
2. **`-N` carries no meaning.** It records arrival order, not place. Nothing in
   `us-official-broadway-3` says which Broadway.
3. **A scoped build disagrees with a full build.** With fewer feeds present a
   slug is free, so the scoped build hands out the bare form and shifts every
   later `-N`. This is how a TTC-only rebuild took Vancouver's Lansdowne
   (`merge-na-feed-build.py:519-538`).

Everything defending id stability today is a repair pass over a scheme with no
stable key: `station_identity_map()` matches candidate to shipped by coordinate
but only within one operator; `disambiguate_foreign_ids()` catches the
cross-operator case but runs only in the merge path, never in a full build;
`stationComplexes`, `stationIdentityGroups` and `stationSplitExceptions` are all
*keyed by the minted slug*, so they go stale whenever it moves.

## The scheme

A station group id is a region, a fixed tag, and a serial:

```
us-stn-001986      ca-stn-000417
```

- **region** — `us` or `ca`, lowercase, as today.
- **`stn`** — a literal, distinguishing the new scheme from `official` at a
  glance and in a grep. An id is self-identifying about which scheme minted it,
  which is what makes a mixed corpus safe during migration.
- **serial** — six digits, zero-padded, per region, assigned once and never
  reassigned.

The uppercased spelling that `n02_station_code` and the saved-journey stores
carry is `US-STN-001986`.

### Why not Japan's bare six digits

Because two call sites read the shape of the string, and both would be wrong:

- `RegionScope.swift:114-129` treats **six bare ASCII digits as Japan**. A
  numeric North American code would be filed as a Japanese ride.
- `app/public/app-stations.js:40-46` and `Train.swift:604-625` classify a code
  as `N02` on `^\d{6}$` and as `TDX` on
  `^[A-Z][A-Z0-9]*-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*$`, and **reject anything
  else**. Saved-journey validation depends on it.

`us-stn-001986` keeps the region head that `regionCode(forStationCode:)` splits
on, and its uppercase form satisfies the TDX pattern. The scheme is Japan's
idea — an assigned serial with a durable registry — in the shape this codebase
can already read.

### The registry

Japan's stability comes from MLIT maintaining the assignment. North America has
no such authority, so the repository becomes one.

`app/data/na-station-registry.json` is committed, append-only, and maps each
serial to the place it names:

```json
{
  "us-stn-001986": {
    "name": "Healy",
    "point": [-148.9689, 63.8636],
    "anchors": ["US-ALASKA-RAILROAD-ALASKA-RAILROAD-HEA"],
    "firstSeen": "2026-09-06",
    "aliasOf": null
  }
}
```

The builder resolves a group to a serial **by its source stop anchors**.

An anchor is the platform code with the group code stripped off the end:

```
US-CALTRAIN-CALTRAIN-sj_diridon        CA-GO-TRANSIT-GO-TRANSIT-AD
```

Region, feed, operator, and *the operator's own stop id*. It is published by
the agency, so it survives every rename we make. Measured on the shipped data:
4,000 anchors across 3,712 US groups and 701 across 682 Canadian ones, all
distinct, and **not one anchor is claimed by two different groups**. It is
already a perfect key; nothing needed inventing.

1. Take the candidate group's anchors.
2. If any anchor is already in the registry, reuse that entry's serial.
3. Otherwise mint the next free serial for the region and append.
4. Never reassign, never renumber, never delete.

Coordinates are a **guard, not the matcher**: if a resolved group's centre is
more than 600 m from the registry entry's point, the build stops and asks for a
human. That catches an agency recycling a stop id for a different place, which
is the one way this can go wrong.

### Why not resolve by coordinate

It was the obvious rule and it is wrong. Measured on the current US data,
**4,059 pairs of distinct stations have centres within 600 m of each other, and
the closest sit at 0 m**:

| distance | one station | another station |
| --- | --- | --- |
| 0 m | `poydras-at-st-charles` | `carondeletst-at-poydras-st` |
| 0 m | `girard-av-frankford-av` | `frankford-av-girard-av-fs` |
| 0 m | `island-av-tanager-st` | `island-av-tanager-st-fs` |

These are street railways: near-side and far-side stops at one intersection,
published by the agency at the same point. 725 pairs sit within 200 m. Any
proximity rule merges them, and single-linkage clustering at 600 m is worse
still — it chains down a dense corridor and collapsed 3,712 US groups into
2,462, merging 1,250 stations that are not the same station.

Japan can group by place because MLIT *publishes* the grouping. North America
has no such authority, so grouping must come from the only other thing that is
both unique and stable: the operator's own stop id. This is the same lesson the
duplicate-identity work reached from the other direction — distance is not the
discriminator.

That rule removes all three consequences above. A name collision is now
irrelevant, because the name is not consulted. `-N` disappears, because two
Healys have different stop ids and so take different serials. And a scoped build
agrees with a full build, because both resolve through the same committed
registry rather than a per-process counter.

### Genesis ordering

The first assignment is the only one that can be ordered, so it should be. Sort
every existing group by region, then latitude, then longitude, and issue
serials in that order. The initial block is then geographically coherent —
`us-stn-000001` onward runs roughly south to north — which makes a range of
serials readable at a glance and diffs local.

After genesis, ordering is abandoned on purpose. A station added in 2027 takes
the next free serial wherever it is. **Stability beats tidiness**: renumbering
to keep the sequence geographic would break every saved journey that cites a
later id, which is precisely the failure this scheme exists to prevent.

Leave a gap between the regions — US from `000001`, Canada from `500001` — so a
serial is recognisable without its prefix in a log line.

## Migration

The blast radius is 4,394 ids, of which 208 carry a `-N` suffix.

**Saved journeys are the constraint that decides the order.** They are keyed by
station code in `app/public/app-store-ops.js:114,158-159` and in
`train-store-{us,ca}.json`, and the export strips names. A renamed id does not
degrade a saved route — it fails to resolve and the route disappears with no
error and nothing to recover it from. 128 distinct codes are embedded in the two
shipped stores today.

So the alias map is not a migration convenience, it is a precondition:

1. **Registry genesis.** Build the registry from the current packages by
   coordinate, recording every existing slug as an `aliasOf`. Nothing else
   changes; the packages still ship the old ids. This commit is inert and
   reviewable on its own.
2. **Alias resolution at import.** Teach `app-store-ops.js` (~400-427) and
   `Train.swift` (~1019-1025) to resolve an unknown station code through the
   alias map before failing. Old saved journeys keep working *before* any id
   moves. This is the commit that makes the rest safe.
3. **Cut over the builder.** `build_region()` resolves through the registry.
   Packages, `stations-*.json`, `station-readings-*.json` and the port fixtures
   regenerate together — they must move in one commit or the fixtures assert
   ids the packages no longer carry.
4. **Re-key the registries.** `na-feeds.json`'s 69 id-keyed entries (66
   `stationSplitExceptions`, 3 `stationComplexes`), `shared-corridors.json`'s
   126, and the hardcoded ids in 9 test files.
5. **Retire the `-N` parser.** `merge-na-feed-build.py:568-570` strips a
   trailing `-\d+` to allocate the next free suffix; against `us-stn-001986` it
   would strip the serial. It must be removed in the same commit as step 3, not
   left to be discovered.

Steps 1 and 2 are safe in any order and safe to ship alone. Nothing after step 2
should land until step 2 has.

## Invariants

Each is a test, and each fails closed:

- **No two coordinates sharing a serial are more than 600 m apart.** This is the
  property North America lacks today and Japan has. Japan measures 0 above 2 km;
  the bound is Shinjuku's 549 m rounded up. It is checked *after* resolution, as
  a guard against a recycled stop id — never used to decide grouping.
- **No anchor belongs to two serials.** True of the shipped data today (4,000 US
  and 701 Canadian anchors, none shared), and the property the whole scheme
  rests on.
- **No two distinct groups are merged by proximity.** 4,059 pairs of real US
  stations sit within 600 m and 725 within 200 m; a build that reduces the group
  count without an explicit registry edit has merged something it should not.
- **A serial is never reused.** The registry is append-only; a commit that
  removes or repoints an entry fails.
- **A scoped build and a full build assign the same serial** to the same place.
  This is the regression that produced the Vancouver Lansdowne collision.
- **Every id in a shipped package resolves in the registry.**
- **Every alias resolves to a live serial**, so no saved journey can point at
  nothing.
- **No id matches `^\d{6}$`**, which would be filed as Japan.

## What this does not do

It does not merge stations that *should* be one complex and are currently two —
that is `stationComplexes`' job and stays evidence-driven. It does not split a
complex that is wrongly merged. It does not touch the platform-level code, which
is already sound. And it does not rename anything a user sees: the popup shows
the station's name, and `app/public/app-ui-utils.js:76` shows the group code as
a technical field, where a serial reads no worse than a slug and lies less.
