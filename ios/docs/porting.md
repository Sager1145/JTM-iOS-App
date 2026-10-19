# Porting shared behavior

The native app reimplements shared JavaScript domain behavior in Swift. A port
needs an explicit contract, representative inputs and an explanation of any
intentional disagreement. Existing fixtures and production regression tests
remain useful; standalone verification scripts and automatic pipelines were
retired on 2026-10-10.

## Choose the owner and scope

Start with the real JavaScript implementation and its callers. Trace the relevant
Swift counterpart, state owner and bundled station/line/geometry references. Put
new files in the appropriate feature directory rather than assuming a flat target:

- `ios/RailKit/Sources/RailCore/`: domain/data algorithms using Foundation, with
  SQLite3 confined to scoped read-only timetable access.
- `ios/RailKit/Sources/RailPresentation/`: portable display rules depending on RailCore.
- `ios/RailKit/Sources/RailApplication/`: portable use cases depending on RailCore.
- `ios/RailMap/`: SwiftUI, UIKit, MapKit, storage integration and platform effects.

Package products and dependencies are defined in `ios/RailKit/Package.swift`.
Feature directories do not create new module boundaries or relocate Resources.
Keep MapKit, SwiftUI, UIKit and CoreLocation out of portable modules.

Work can involve existing files; the old “three new files, no other edits” recipe
is not a requirement. When independent work is explicitly delegated, assign
clear file ownership and preserve other workers' changes. Coordinate builds and
other heavy jobs instead of running a verification suite per worker.

## Fixtures call the real implementation

Fixture modules live in `app/scripts/build/port-fixtures/` and are discovered
by `build-port-fixtures.mjs`. They export this shape:

```js
export const name = "<name>.json";
export function build({ RailNetwork, AppCore, js, railPackage, APP_DIR }) {
  return { describes: "...", contract: "...", cases: [ /* ... */ ] };
}
```

Call the actual JavaScript, not a pasted reimplementation. Draw representative
cases from relevant shipped inputs and add targeted boundary/failure cases. Keep
expected answers tied to the declared reference behavior. If that behavior needs
correction, make the JavaScript/Swift change explicit and review the fixture diff;
do not silently treat a disagreement as a successful port.

The existing builder supports selecting one fixture. From the repository root,
when regeneration is necessary:

```bash
node app/scripts/build/build-port-fixtures.mjs --only=<name>.json
```

Its `--check` option compares regenerated output without rewriting the fixture.
Use it only for a specific freshness question. Review the selected builder's
resource needs before running it: a targeted fixture can still construct a large
graph. Do not regenerate the whole corpus for a small change. Fixture output lives
in the shared root `port-fixtures/` directory.

## Preserve language semantics

Read implementation comments for the reasons behind behavior. Persisted keys,
ordering, date boundaries and numerical totals can change even when Swift compiles.

| JavaScript behavior | Existing Swift support or review point |
| --- | --- |
| Integral Number string spelling | `JSNumber.string` |
| `Math.round` ties toward positive infinity | `JSNumber.round` |
| UTF-16 string ordering | `JSNumber.stringLessOrEqual` or an explicit UTF-16 comparison |
| `Math.hypot` and `Math.cos` numerical behavior | Review existing `JSMath` and affected parity tests before substituting platform math |
| Exponentiation and arithmetic order | Compare affected outputs; rearrangement may change floating-point results |
| Zero-based months and date parsing | Pin calendar/time zone and review day-before/on-date cases |

Use exact string/ID/vertex comparisons where the contract requires them. For
floating-point parity, use bit patterns where exact equality is expected. If a
platform difference requires tolerance, state the measured ULP bound and its
input scope rather than choosing an unexplained broad epsilon. Historical
measurements do not establish a bound for newly changed code or inputs.

## Review, then select evidence

Use [the current verification policy](../VERIFICATION.md). Begin in chat with the
diff and affected dependencies. Review relevant existing tests under
`ios/RailKit/Tests/`; `RailCoreTests/PortFixtures.swift` reads fixtures and shipped
packages from the repository, so a detached copy of the package lacks those inputs.
Tests use Swift Testing (`@Test`, `#expect`) and `PortFixtures.decode(...)` or
`PortFixtures.package(country:)` where appropriate.

Reuse still-valid results after checking their relevant dependencies. Run a
selected existing test only when execution resolves a concrete uncertainty, for
example this procedure template from the repository root:

```bash
swift test --package-path ios/RailKit \
  --scratch-path /tmp/jtm-railkit \
  --filter '<existing-suite-or-test-name>'
```

Coordinate the reusable scratch path and one heavy job at a time across chats.
This command template was reviewed against the repository layout; it was not
executed during the documentation update. Do not infer success from an interrupted
run. Expand only for an observed failure or concrete dependency, and stop when the
question is answered. There is no `verify.sh` gate or requirement to run every
JavaScript, package and app test for every port.

Record the changed scope, evidence, disagreement or result and remaining
uncertainty in the existing owning ledger. Preserve physical topology and other
[product constraints](../AGENTS.md): equal names, coordinate coincidence and
through-service display are not proof of a physical railway connection.
