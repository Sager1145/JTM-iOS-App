# Japan branch display handoffs — 2026-10-01

The reported 総武本線（御茶ノ水支線） gaps reproduce in the derived display
geometry. The compact source already shares the exact 錦糸町 coordinate with
the main line. A missing physical connector is not the cause of this case.
JR East's [Sobu route diagram](https://www.jreast.co.jp/chiba/pdf/soubu.pdf)
and [Kinshicho timetable index](https://timetables.jreast.co.jp/timetable/list0609.html)
distinguish the local and rapid services at this junction.

## Repair

`app/scripts/railway/build-display-lanes.mjs` now applies three rules to Japan:

- A family tenant can be hidden only beyond the complete 300 m follow blend.
  Short follows retain their continuous stroke; joined part ends retain the
  renderer's additional blend guard.
- The final tenant and leader lane profiles must be constant and equal in
  physical screen direction. Reverse digitisation reverses the signed lane.
  Incompatible or changing profiles keep their own continuous ink.
- Follow endpoints use the leader's exact cumulative measure when the source
  endpoint is an identical surveyed coordinate. Nearby platform coordinates
  are never welded by distance alone.

The family boundary is mapped through the follow's affine correspondence.
Station snapping cannot expand it back into the incomplete blend. Full lane
derivation runs this step after collision and hub overrides. The bounded
`--refresh-handoffs` mode changes Japan handoffs without resampling other
regions. North American family derivation retains its previous rules.

No physical intervals, passenger stops, branch identities, routing mileage,
or raw station coordinates were changed by this repair.

## Evidence and verification

The raw shared-station audit checked 46 same-family comparisons: 43 share an
exact source anchor. The separate 岸里玉出 platforms, 大宮 approach and 大阪
underground approach were retained. They are not treated as missing connectors.

Before the fix, 34 family cut boundaries exceeded 1 m. After the fix, the 18
retained tenant windows have 36 boundaries; the greatest tested distance to
the drawn leader is below 0.037 px at zooms 12, 16 and 19 (the existing
geometry tolerance is 0.0625 px). The Sobu branch has no tenant cut and its
錦糸町 endpoint remains exact at each tested zoom.

| Check | Actual result |
| --- | --- |
| `node --test app/tests/japan-branch-handoffs.test.mjs` | 9 passed, including shipped handoff edges and Sobu at three zooms |
| Existing display-parts, Oshiage, Hakodate connections, multi-row matching and Tokyo approach JS tests | 40 passed |
| `python3 -m unittest discover -s app/scripts/railway/tests -p 'test_display_network.py'` | 69 passed |
| `swift test --package-path ios/RailKit --scratch-path /tmp/jtm-branch-swift --filter 'ContinuousStroke\|FamilyWindowParity\|OverlapLanesParity'` | 46 passed in 6 suites |
| Same Swift filter including `StationDisplayParity` | Failed: 127 issues in two station-display tests; geometry and family suites passed |
| Earlier Swift filter including `DisplayPartsParity` | Failed: 4 display-parts snapshot issues |
| Continuous-stroke and family-window fixture `--check` | Current: 69 and 18 cases respectively |
| `build-display-lanes.mjs --refresh-handoffs --check` | Passed; no write |
| `ios/verify.sh --core` | Stopped on timetable/history station-package and source-hash mismatch |

The native display builder completed into `/tmp/jtm-branch-work/native-display`;
no native bundle was installed or published. Its Sobu chunk retains continuous
ink, an empty `familyWindows` list, and the endpoint follow target at 5117.4 m
rather than the approximate 5125 m. The manifest binds to the input hashes
below. The existing builder processes seven regions into that temporary
directory; its non-Japan output was not applied to repository resources.

The full fixture freshness check was interrupted during coordinated resource
freeze after reporting drift in multiple existing fixtures. It is not a pass.
The two targeted fixture checks above passed after generation. No simulator
or MapKit visual sign-off was performed. Some shared-station lane seating
offsets of roughly 1–3 px remain outside this family-cut repair. Conservatively
retaining ink can restore parallel same-colour strokes or duplicate circles;
this report does not claim every Japanese branch junction is fully audited.

## Replay and integration boundary

After the Japan source writers finish, the integration owner can run:

```sh
node app/scripts/railway/build-display-lanes.mjs --refresh-handoffs
node app/scripts/railway/build-display-lanes.mjs --refresh-handoffs --check
node --test app/tests/japan-branch-handoffs.test.mjs
```

Then regenerate the necessary Japan native derivative and parity fixtures from
the final common source snapshot. This task has frozen further shared-resource
generation. It did not stage, commit, merge, push, or operate a simulator.

Observed snapshot SHA-256 values at final verification (not a guarantee that
concurrent source writers have finished):

| File | SHA-256 |
| --- | --- |
| `app/public/rail/jp-2025.json` | `64d81583f3b690e2b3a13685ebfaf59aa52ea646f9f2e1a80e6c5062b921a27a` |
| `app/public/rail/display-lanes.json` | `20800986effcf11ea63784a3da910538fa20ee57aeab746ef7cfdcd778e7a562` |
| `app/scripts/railway/build-display-lanes.mjs` | `646793d6e41bc9c5a5972974ec3093a3c7123308f625ebefc7b8a5b547d11dac` |
| `app/tests/japan-branch-handoffs.test.mjs` | `8803c331a56c07ec3c5c3a19a5d7fb74cad9b6a7bef271e7b3ada6ceca76802f` |
| `port-fixtures/continuous-stroke.json` | `ca96e22e96164bfe4aa00d9cd085e57a946d05f6a9f4453a9241f2b1b49c4cc4` |
| `port-fixtures/family-windows.json` | `5cd8fbde984a7b3bb9381886fa1b2345770e3ebefd201ed54acf71a7f167b4e9` |

Affected tracked files are the lane builder, Japan fields in the shared lane
table, the new regression test, the two fixture generators and their JSON
fixtures, and this report. The shared lane table and fixtures already carried
other work before this task; integration must preserve those edits and their
source binding. The temporary native output is evidence, not a distributable
artifact.
