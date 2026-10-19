# Mac testing shortcuts — 2026-10-13

Main app and all three independent Inspector instances were updated with the compiled shortcut code. Both focused Catalyst builds succeeded; all six existing app bundles retain the latest accepted railway data and pass strict signature verification. RouteWorkbench and ThroughWorkbench keep their existing keyboard commands; their source was not changed in this extension.

## Main app

| Action | Key |
| --- | --- |
| Search / new journey | ⌘F / ⌘N |
| Zoom in / out | ⌘+ or ⌘= / ⌘− |
| Panel size | ⌥⌘S |
| Railway overlay / train routes | ⇧⌘L / ⇧⌘R |
| Station dots / station names | ⇧⌘P / ⌥⇧⌘P |
| Layers / dismiss sheet | ⌥⌘L / Esc |
| North up | ⌘0 |
| Fit selected route / railway network | ⇧⌘F / ⌥⇧⌘F |
| Pan by one quarter of viewport | ⌃⌘← → ↑ ↓ |
| Previous / next date | ⌥⌘← / ⌥⌘→ |
| Add date / all dates | ⇧⌘D / ⌥⌘0 |
| Follow selected date | ⌥⇧⌘D |

Main menu titles use the existing English/Japanese/Simplified/Traditional Chinese localization. New map commands are unavailable during date entry and journey editing; panel commands cannot stack presentations. Esc uses the visible sheet close action, with workspace selection clearing disabled underneath the presentation. The existing date-selection mechanism is reused; no temporal railway rule or data was changed.

## Three Inspectors

| Action | Key |
| --- | --- |
| Search | ⌘F |
| Basemap / package / display / smoothing / overlay / extraction | ⌘1…6 |
| Detail z17 / z18 | ⌘7 / ⌘8 |
| First detailed viewpoint | ⌘Home (Fn⌘← on keyboards without Home) |
| Frame station / interval / line | ⌘9 / ⌘0 / ⇧⌘0 |
| Basemap peek | ⌘B |
| Previous / next viewpoint | ⌥⌘← / ⌥⌘→ |
| Previous / next station | ⌥⇧⌘← / ⌥⇧⌘→ |
| Previous / next pending interval | ⇧⌘P / ⇧⌘N |
| Same-view evidence / viewpoint record | ⌥⌘S / ⇧⌘S |
| Capture complete current interval | ⇧⌘C |
| Extract / export extraction | ⌥⌘E / ⌥⇧⌘E |

Previous/next menu availability is directional, so navigation at a boundary does not reload or invalidate the current analysis. Bare B no longer triggers peek while typing. Export shortcuts open the normal save panel.

## Evidence and limits

Actual Main key observations cover overlay, route/dot/name toggles, layer open/Esc close, date-dialog open/cancel, blocked map key during date entry, and four-way camera movement. Right pan moved longitude 139.764000→139.809604; left returned to 139.764000. Up moved latitude 35.555000→35.581497; down returned to 35.554991, with distance 21946.4 unchanged. Final layers show station dots, station names and routes all on. North-up was invoked with an already north-up camera; selected-route fit had no selected itinerary, and date follow/all-dates were invoked in an all-dates workspace, so these states do not prove a visible transition.

Actual Primary Inspector keys cover z18, first-view, boundary previous, next-view, next/previous station, modes, peek, three framing commands, extraction and same-view export opening its save panel. ⇧⌘C produced every one of the four 京急蒲田→糀谷 viewpoints, zero failures. Secondary and Third instances independently demonstrate detail, station navigation and mode/peek commands. Saved AX observations and key-invocations.json record each invocation; screenshots show actual running applications. This is shortcut verification, not a new acceptance verdict for the airport railway.

Focused build logs: /private/tmp/jtm-mac-keyboard-main-build.log and /private/tmp/jtm-mac-keyboard-inspector-build.log. The initial Inspector sandbox cache denial was resolved using the reviewed existing-cache build permission. Main required narrow Catalyst exclusions for the pre-existing iOS-only hinge observer and toolbar axisBehavior API; iOS branches remain intact.

## Whole-line shortcut follow-up — source only

Added Inspector source command `⌥⇧⌘C` for the complete selected line, retaining the existing current-interval command. Return in Lines search selects exactly one remaining result; Queue mode, zero/multiple results, capture/analysis and import/export modals do not select. Root reviewed the existing `startBatch(selectedLineOnly: true)` scoped API and its batch/capture/analysis guards. This follow-up has not been compiled, installed, or actually key-tested; the earlier delivery evidence does not cover these two new commands. Native continuation is awaiting manual Mac unlock.

## Whole-line shortcut actual delivery and observations

The incremental Catalyst build passed and the same executable was delivered and strictly signed in all three Inspector bundles. Root actually used ⌘F, exact line ID, Return, and ⌥⇧⌘C in each app for all 11 城南線 intervals (27 viewpoints) and the complete 花園線 interval (3 viewpoints). Each app saved 90 panels, with zero failed or pending target views. The selected detail ID was observed after Return. These observations supersede the earlier source-only/pending note; modal negative cases were reviewed in code but not exercised at runtime.
