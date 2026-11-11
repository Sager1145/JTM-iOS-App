# 0014: The app-wide text-size cap at Extra Large is a feature

- Status: Accepted
- Date: 2026-11-11
- Decision owner: the user (stated in chat on 2026-11-11: "keep this as a feature … this should never be discovered as a problem ever again")
- Code: `ios/RailMap/Design/AppTypographyPolicy.swift` (`maximumSize = .xLarge`), applied at the scene root in `ios/RailMap/App/RailMapApp.swift` and on every window.

## Decision

The app follows the reader's text-size setting up to **Extra Large** and no further, on every screen. Sizes above it, including the five accessibility sizes, are deliberately ignored. This is intended product behaviour.

## Why

Extra Large is the largest size at which the densest screens still lay out: the resident sheet's header row, the History/Upcoming journey rows and the Stats ticket. Above it those rows wrap into the next row or truncate station names. One cap for the whole app keeps every screen the same size relative to the others.

## Rules for audits, reviews and agents

- Do **not** report the cap as an accessibility defect, a Dynamic Type bug, or a finding of any severity. Do not propose lifting it, narrowing it to some screens, or adding a setting for it.
- Do **not** report "does not support accessibility text sizes" for any screen. Layout only has to work from Extra Small to Extra Large.
- Layout branches that test `isAccessibilitySize` cannot run under the cap. They are harmless leftovers. They may be listed as dead code in a code-cleanup audit, but removing them is optional and must not change the cap.
- The cap may be changed only when the user asks for that in their own words. If it is ever changed, update this record first.

## History

The UI audit of 2026-11-11 (`docs/maintenance/2026-11-11-ui-audit.md`, finding H1) reported the cap as a High problem. The user rejected the finding and asked for this record.
