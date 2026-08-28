# JTM iOS App Documentation Strategy

| Field | Value |
| --- | --- |
| Status | Active |
| Owner | Project maintainers |
| Last reviewed | 2026-08-28 |
| Review cadence | Quarterly and before each public release |

## Purpose

This strategy keeps project documentation accurate, discoverable, and proportional to the code. It assigns one job to each document, identifies the source of truth behind mutable claims, and makes documentation part of the change workflow.

The documentation system follows the Diátaxis distinction:

| Reader need | Document type | Primary artifact |
| --- | --- | --- |
| Learn by doing | Tutorial | Guided first-journey section in `docs/USER_GUIDE.md` |
| Complete a task | How-to guide | `docs/USER_GUIDE.md` and `docs/RUNBOOK.md` |
| Look up exact facts | Reference | `docs/API_REFERENCE.md`, `ios/FEATURES.md`, source and symbol graphs |
| Understand why | Explanation | `ios/README.md`, `ios/PORTING.md`, and ADRs |

Do not combine all four jobs in one page. A short cross-link is better than duplicating a changing fact.

## Information architecture

### Entry point

`README.md` is the front door. It states what the app is, shows the shortest successful setup, explains the architecture at a glance, and routes readers to deeper documents. Keep it concise enough to scan before cloning.

### User documentation

`docs/USER_GUIDE.md` is the current product manual for people using the app. Organize it around goals such as creating, importing, finding, mapping, and backing up journeys. UI names must match the shipping interface.

### Maintainer reference

`docs/API_REFERENCE.md` describes the public API of `ios/RailKit`. Compiler-generated symbol graphs are authoritative for declarations; prose adds contracts, failure behavior, examples, and module boundaries.

`ios/FEATURES.md` is the canonical ledger of implemented product capabilities. Update it when a user-visible feature is added, removed, or materially changed.

### Operations

`docs/RUNBOOK.md` is the executable build and release procedure. `ios/verify.sh`, shared schemes, and CI remain authoritative when prose and automation disagree.

### Architecture and history

`ios/README.md` explains the native port in depth. Its historical sections may preserve implementation context, but current-state claims should link to `ios/FEATURES.md`.

`ios/PORTING.md` owns cross-language parity rules and fixture-driven porting guidance. `ios/AUDIT_PLAN.md` and `ios/PERFORMANCE_OPTIMIZATION_PROMPT.md` are scoped plans, not descriptions of current product behavior.

ADRs under `docs/decisions/` will own durable architecture decisions and their trade-offs.

## Document inventory and action

| Artifact | Type | Audience | Authority | Maintenance action |
| --- | --- | --- | --- | --- |
| `README.md` | Orientation | Everyone | Repository state | Keep brief; link outward |
| `docs/USER_GUIDE.md` | Tutorial/how-to | App users, support | Shipping UI and behavior | Review every visible workflow change |
| `docs/API_REFERENCE.md` | Reference | Swift maintainers | Swift symbol graphs and tests | Review every public API change |
| `docs/RUNBOOK.md` | How-to | Release engineers | `ios/verify.sh`, schemes, CI | Execute before release |
| `docs/DOCUMENTATION_STRATEGY.md` | Explanation/governance | Maintainers | Documentation owners | Review quarterly |
| `ios/FEATURES.md` | Reference | Product and engineering | Shipping feature set | Keep as feature source of truth |
| `ios/README.md` | Explanation/history | Native-port maintainers | Code plus recorded history | Label stale history; avoid feature duplication |
| `ios/PORTING.md` | How-to/explanation | Port maintainers | Fixtures and parity tests | Update with parity rules |
| `ios/AUDIT_PLAN.md` | Plan | Auditors | Audit scope at creation time | Mark completed or superseded work |
| `ios/PERFORMANCE_OPTIMIZATION_PROMPT.md` | Plan | Performance work | Profiling scope at creation time | Preserve as scoped input, not a status page |

## Sources of truth

Never maintain a mutable value in prose when it can be derived reliably.

| Claim | Source of truth | Documentation consumer |
| --- | --- | --- |
| Bundle ID, versions, deployment target | `ios/RailMap.xcodeproj/project.pbxproj` | README, runbook |
| Available products and platforms | `ios/RailKit/Package.swift` | README, API reference |
| Public Swift declarations | Compiler symbol graphs | API reference |
| JavaScript/Swift parity behavior | Fixtures and tests | Porting guide, API notes |
| Quality-gate commands | `ios/verify.sh` | README, runbook |
| CI toolchain and jobs | `.github/workflows/port-parity.yml` | Runbook, contributor guidance |
| Current user features | Shipping code plus `ios/FEATURES.md` | README, user guide |
| Persistence and backup behavior | Storage implementation and tests | User guide, runbook |
| Architecture decisions | Accepted ADRs | Architecture explanations |

When a mismatch is found, correct the downstream document and add a regression check when the claim can be automated.

## Change policy

A change is not complete until its documentation impact has been considered.

| Change | Required documentation review |
| --- | --- |
| New or changed user workflow | User guide and feature ledger |
| New or removed public `RailKit` symbol | API reference and symbol graph count |
| Changed JSON schema or import/export behavior | User guide, API reference, porting guide |
| Changed build, test, signing, or release command | README and runbook |
| New supported region, platform, or minimum OS | README, user guide, runbook |
| Changed persistence, backup, privacy, or destructive action | User guide and runbook |
| Durable architecture choice | New or superseding ADR |
| Historical plan completed | Mark the plan complete, obsolete, or superseded |

Pull requests should include a “Documentation impact” note even when the result is “none.” Reviewers should reject instructions that have not been executed or API examples that do not compile against the current declaration.

## ADR practice

Store decisions as `docs/decisions/NNNN-short-title.md`. Number files monotonically; never rewrite an accepted decision to hide history. Supersede it with a new ADR and link both directions.

Use this structure:

```markdown
# NNNN: Decision title

- Status: Proposed | Accepted | Superseded
- Date: YYYY-MM-DD
- Decision owners: names or roles
- Supersedes: optional ADR link

## Context
What problem, constraints, and forces require a decision?

## Decision
What was chosen?

## Consequences
What becomes easier, harder, or intentionally unsupported?

## Alternatives considered
Which credible options were rejected, and why?

## Validation
Which tests, metrics, or review date will show whether the decision still works?
```

### ADR backlog

Create ADRs when the responsible maintainers are ready to confirm the decisions. Suggested first records are:

1. Keep `RailCore` Foundation-only for fixture parity and portability.
2. Use native SwiftUI and MapKit instead of embedding the web UI.
3. Load the five regional railway networks into one native map workspace.
4. Preserve WGS84 in shared data and apply selected GCJ-02 conversion only at the MapKit boundary.
5. Persist the journey library as atomic local JSON with one recovery backup before destructive operations.
6. Render network geometry with batched polylines, level-of-detail selection, viewport culling, and budgets.
7. Surface route-solving failure instead of inventing a straight-line fallback.

## Writing standards

- Write for one named audience and one reader goal per page.
- Lead with the outcome, then prerequisites and steps.
- Use the exact labels shown by the app and exact paths used by the repository.
- Put commands in copyable fenced blocks and state their expected result.
- Use relative links inside repository Markdown.
- Prefer a small verified example over exhaustive hand-written declarations.
- Mark dates, version-specific claims, and historical context explicitly.
- Explain failure and recovery wherever an operation can lose work or block a release.
- Do not document secrets, signing credentials, personal paths, or private account data.

The project documentation is written in English to match source identifiers and existing repository materials. Localized end-user help can be added as separate language variants when there is an owner and a synchronization process.

## Automation

The near-term documentation checks should be lightweight and deterministic:

1. Validate internal Markdown links in CI.
2. Regenerate Swift symbol graphs and report top-level public API drift.
3. Check that commands named in the README still exist in `ios/verify.sh`.
4. Flag stale “last reviewed” dates after the chosen cadence.
5. Require a documentation-impact field in the pull-request template.

Generated output supports review; it does not replace the contract and failure explanations written by maintainers.

## Review cadence and ownership

| Cadence | Review |
| --- | --- |
| Every pull request | Changed behavior, links, examples, and documentation impact |
| Every release candidate | User guide critical path and complete runbook execution |
| Quarterly | Full inventory, stale plans, ADR backlog, ownership, broken links |
| After an incident | Recovery instructions, escalation path, and missing observability |
| After Xcode, Swift, Node, schema, or minimum-OS change | All versioned requirements and commands |

The author of a change owns the initial documentation update. The code owner validates technical accuracy; the product or support owner validates user-facing language; the release engineer validates the runbook.

## Roadmap

### Now

- Keep the five primary documents linked from the root README.
- Treat `ios/FEATURES.md` as the current feature ledger.
- Create the first ADRs from the backlog as decisions are confirmed.

### Next

- Add an internal-link checker and API-drift report to CI.
- Add annotated screenshots only after a stable capture and localization workflow exists.
- Label historical sections in `ios/README.md` that no longer describe current capability.

### Later

- Publish DocC output for `RailCore` and `RailPresentation` if the package becomes a separately consumed library.
- Add localized user-guide variants when translation ownership is established.
- Track documentation search or support-ticket signals if the project gains a public support channel.

## Success criteria

The strategy is working when a new contributor can build the app from the README, a user can complete and recover core journey tasks from the guide, a maintainer can look up the current public API without reading every source file, and a release engineer can execute the runbook without tribal knowledge.
