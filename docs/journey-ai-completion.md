# Screenshot import and AI completion

The screenshot importer reads Yahoo! 乗換案内 and JR東日本アプリ locally using
Vision, then builds a preview against the Japanese station package. Select
screenshots in journey order. Photos selection now displays selection order;
an unreadable page or failed OCR tile fails the attempt instead of silently
importing an incomplete journey.

The screenshot preview and journey editor expose **AI completion** for drafts
with named endpoints/stops and missing supported fields. The request gate
requires at least one station resolved in a loaded station catalog with a valid
arrival or departure time on that same stop. An unconfirmed station name or a
time belonging only to another, unresolved station is insufficient. Unique
station names/aliases can resolve locally; ambiguous names need station-picker
confirmation. The core prompt's default two-anchor research rule is separate
from this catalog-based app request gate.

For a new journey, enter the date, two station names and their departure/arrival
times, and vehicle type when known; enter the service name for a limited express.
The train number can remain empty while advancing to the date and completion
steps. These details are research clues, not proof that every field is available.
Completion is explicit:

1. Choose **Sign in with ChatGPT subscription**. The app obtains a one-time
   device code directly from OpenAI. Open the authorization page, sign in to
   your own account, enter the displayed code, and return to RailMap.
2. Select a model from the catalog returned for that account. Choose
   **Complete with subscription** to send journey fields and recognized text
   to OpenAI. Screenshot image files are not uploaded.
3. The completed JSON response is validated and shown as proposed additions.
   Check the additions and sources, then apply to the draft.
4. Save the journey or finish the screenshot import to persist it.

The existing share-prompt / paste-JSON workflow remains available below the
subscription controls. It does not require a stored account session.

Existing information is preserved. Suggested stop changes must match both the
stop index and name. Unknown IDs, malformed responses, conflicts and invalid
field values are rejected. Suggestions must supply evidence URLs and an
explanation; URL presence does not independently verify a timetable. The
prompt asks ChatGPT to leave uncertain information unknown.

Completion can insert intermediate **scheduled passenger stops** when supported
by a dated timetable. Each `intermediate_stops` row names an original input gap
with `after_index` and supplies a station name and at least one valid clock.
The merge checks gap bounds and chronological order, including `24:xx` or `+N`
cross-day times. Invalid additions reject the whole response atomically.
When stops are inserted, review displays the complete proposed stop order.
New stops inherit the preceding segment's ride flag; completion does not decide
that a previously unrecorded journey was ridden.

AI responses cannot assign station IDs. After merging, the app resolves unique
names locally and labels unresolved stops for station selection. Existing
station identities remain intact. Completion does not save automatically.
Changing the import date discards completion
suggestions because timetable evidence may no longer apply. Toggling included
legs or ridden status preserves suggestions for the corresponding leg.

## Local timetable lookup and source boundaries

The Japanese new-journey date step offers local timetable matching using the
date, both catalog station identities, origin departure and destination arrival,
plus the supplied service name. It displays supporting source links. A result
with a fully verified route can supply the route; other published results can
supply an editable stop draft without asserting verified physical lines.
When identifying inputs are ready, lookup starts automatically on appearance
or input changes after a 300 ms pause. A new date, service name or endpoint/time
cancels the pending lookup and clears old results. The search button remains
available, and applying a match still requires selecting it. The native UI
continuation implemented this on 2026-09-30. Its focused simulator test passed
in 299.285 seconds, including automatic initial lookup and stale-result
clearing after rapid date and service-name changes.

Subscription completion requests live web search and asks for authoritative
operator/timetable evidence. It does not first query the local timetable
database, and it cannot guarantee that the model will find a usable source.
The copy-prompt workflow likewise asks for research but relies on the selected
ChatGPT session's available tools.

Automatic local matching currently applies to the Japanese new-journey date
step. Screenshot-import and existing-journey completion do not reuse that
lookup automatically. The original minimal-input request is supported by the
completion prompt and merge tests; filling every field still depends on the
available evidence and the supported response schema. Network-researched
results are proposed for the journey draft, not added to the shared timetable
database by the app.

Supported additions are service/public number, English service name, train type,
vehicle type, operator, direction, line names, scheduled clocks, platforms and
evidence-backed intermediate calls. The response schema does not fill the date,
station IDs, actual-operation records or verified physical route identities.
Absent evidence stays unknown. Line names alone do not verify a dated route.

Earlier historical journeys can use direct evidence of the applicable railway
identity and date; the H1 construction range is not a global cutoff. Data outside
the verified span remains available with its limitations. Modern open-ended
line validity is not truncated at the newest source snapshot; future timetables
still need their own evidence. See the [timetable verification report](train-timetable-verification-2026-09-29.md)
for the current evidence gaps. The user's background update preference is weekly;
this documentation continuation creates no schedule.

## Standalone subscription connection

RailMap performs device-code OAuth, token refresh, model discovery and streamed
completion directly on the iOS device. It does not require Codex App Server,
a companion computer, an application backend or an OpenAI API key. Credentials
are stored in the device Keychain, not UserDefaults, source files or logs.
Signing out removes this app's local credentials; it does not revoke other
OpenAI sessions or cancel the subscription.

This is an **experimental integration with the Codex subscription protocol**,
following OpenAI's open-source client implementation. It uses the public Codex
OAuth client, so the authorization page identifies **Codex**, not RailMap.
It is not registered RailMap OAuth, a general ChatGPT website API, or an
OpenAI-supported third-party iOS SDK. Model availability, device-code access,
web-search support and rate limits depend on the account and service. Protocol
changes can require an app update. The app reports service errors rather than
silently switching to separately billed API access.

The app never reads an existing Codex installation's credentials or ChatGPT
browser cookies. OAuth uses a new user-initiated device authorization; there is
no password field inside RailMap. Inference uses the returned access token and
account ID with the subscription Responses endpoint. A 401 triggers one token
refresh and retry. Only a completed response can become a preview; interrupted
or failed streams cannot apply partial suggestions.

Protocol references:

- https://github.com/openai/codex/blob/main/codex-rs/login/src/device_code_auth.rs
- https://github.com/openai/codex/blob/main/codex-rs/login/src/server.rs
- https://github.com/openai/codex/blob/main/codex-rs/codex-api/src/endpoint/responses.rs
- https://github.com/openai/codex/blob/main/codex-rs/codex-api/src/endpoint/models.rs
- https://learn.chatgpt.com/docs/auth

## Verification

`JourneyCompletionTests` tests eligibility, unique/ambiguous catalog resolution,
minimal-input prompts, pasted-text drafts, strict decoding, intermediate-stop
insertion/order, cross-day clocks, preservation of existing data and atomic
rejection of invalid responses.
`JourneyCompletionUITests` exercises the new-journey entry point and prevents
applying invalid or empty replies.
`TransferGuideTests` covers screenshot parser regressions using OCR text and
bounding-box fixtures. A device test with actual source screenshots is still
needed to measure end-to-end OCR accuracy; parser fixtures cannot establish a
recognition accuracy percentage.

Current focused verification (2026-09-30): **30 JourneyCompletion tests passed**
with the following isolated command. This validates core request/merge behavior;
the native UI continuation owns simulator verification of intermediate-stop
review, cross-day editing and rapid date/service-name changes.

```sh
cd ios/RailKit
CLANG_MODULE_CACHE_PATH=/tmp/jtm-journey-report-clang-20260930 \
SWIFT_MODULECACHE_PATH=/tmp/jtm-journey-report-module-20260930 \
swift test --disable-sandbox \
  --scratch-path /tmp/jtm-journey-report-20260930 \
  --cache-path /tmp/jtm-journey-report-cache-20260930 \
  --filter JourneyCompletionTests
```

The final 2026-09-30 RailKit gate passed **926 tests**: 611 core tests in
67 suites and 315 presentation tests in 29 suites. `./ios/verify.sh --core`
also passed 35 production editor validation cases, 18 persistence checks,
10 subscription-auth cases and 9 subscription-HTTP cases. The saved logs and
artifact hashes were checked against the persistent validation checkpoint.
This gate does not build or run the iOS app and does not validate the
preview-layer no-op fix or live account access.

The earlier focused core run passed 54 TransferGuide tests and 11
JourneyCompletion tests before intermediate-stop support was added. The earlier
iOS Simulator Debug app build also passed.
The focused new-journey UI test passed on an isolated iOS 27 simulator,
including insufficient-information gating, opening completion, rejecting an
invalid reply, and keeping Apply disabled for an empty/no-op reply.

The native continuation's first focused simulator run on 2026-09-30 passed
2 of 5 checks: advancing without a train number and cross-day stop editing.
The invalid-reply/no-op completion, source-symbol display and sharing checks
failed in that run. The sharing retry then passed all four light/dark map and
statistics previews with Japan and 2026-07-03 retained after dismissal; saved
map previews were also visually inspected. The earlier UI pass above does not
certify this run. That six-method retry finished **1/6 passed** (sharing);
ordered review, endpoint collision, local lookup and source-symbol checks
failed at screen reachability or accessibility selectors, while the no-op
completion check exposed the app defect below. The UI owner corrected those
test interactions and started an isolated five-method retry. Those five
behaviors are tracked separately. The ordered intermediate-stop test passed
in 725.040 seconds: the complete proposed sequence appeared in travel order,
explicit Apply returned to the journey draft, and reopening an inserted stop
preserved its editable name. This fixture verifies preview/apply behavior, not
the truth of a researched timetable or a saved journey. The invalid/empty
reply test then passed in 340.065 seconds, and endpoint-label frame separation
passed in 31.093 seconds. Source-symbol accessible rows passed in 252.349
seconds, checking Hokuto's pass role and Huis Ten Bosch's not-via role. The five-method
bundle finished **4/5 passed**. Automatic lookup produced the expected match,
but editing the clipped date field failed before the result-clearing checks.
The test helper was corrected and the isolated case passed in 299.285 seconds:
initial lookup ran without a search tap, rapid date changes cleared old matches,
a valid date restored them, and an invalid service name cleared them until
the supported name was restored.

Follow-up screenshot inspection found that Huis Ten Bosch's not-via row was
outside the captured viewport and the expanded search sheet covered the map.
The accessible-row and frame checks remain valid; visible symbol and endpoint
screenshots are being checked with stricter viewport and camera setup. These
stronger visual checks remain pending; automatic result clearing is verified
by the isolated test above.

The invalid-reply retry rejected malformed JSON but found that an empty
`{"trains":[]}` reply enabled Apply: resolving unique station names added IDs
even when the merge made no additions. The native continuation now resolves
identities only for journeys changed by the merge, preserving unchanged input
for a no-op response. Its isolated simulator retry passed: malformed JSON
was rejected and the empty reply kept Apply disabled. The core merge test
pass alone did not catch the preview-layer defect.

Subscription protocol tests run with:

```sh
cd ios/RailKit
swift test --scratch-path /tmp/jtm-subscription-build --filter ChatGPTSubscriptionProtocol
cd ../..
python3 ios/tools/verify-subscription-service.py /tmp/jtm-subscription-build
```

The service harness compiles production request code and supplies URLProtocol
fixtures. It covers successful completion, one-time 401 refresh, repeated 401,
403, 429 and truncated streams without network access or real credentials.
These checks do not establish that a particular live ChatGPT account is eligible.

To inspect actual screenshot recognition, preserve screenshot order and run:

```sh
python3 ios/tools/verify-transfer-screenshots.py /tmp/jtm-subscription-build \
  /absolute/path/page-1.png /absolute/path/page-2.png > /tmp/journey-ocr.json
```

This runs production Vision OCR and parsing, emitting raw text, bounding boxes,
source detection, stations and times for comparison with the originals. No real
Yahoo/JR screenshots were supplied for this change; end-to-end recognition
accuracy remains unverified.

OAuth state and token exchange can be checked without a real account:

```sh
python3 ios/tools/verify-subscription-auth.py
```

The fixtures use synthetic tokens and in-memory credential storage. Actual
Keychain persistence and browser authorization still need a signed device and
the user's own OpenAI account for end-to-end verification.

### Standalone subscription verification (2026-09-23)

- 7 protocol tests passed.
- 8 OAuth fixture cases passed, including sign-out during a delayed token exchange.
- 6 production HTTP fixture cases passed.
- iOS Simulator app build passed; the final auth source also passed Swift 6
  type-checking against the iOS 17 target with Observation macros.
- The updated UI test could not complete: the first run stalled during test
  setup and was cancelled; a serial retry failed because Xcode could not find
  the dedicated simulator destination. The earlier manual-flow UI pass above
  does not validate the new subscription controls.
- No live OpenAI account login or subscription inference was performed.

### Upstream alignment review (2026-09-23)

Checked against `openai/codex` main (`codex-rs/login/src/auth/manager.rs`,
`login/src/oauth/client.rs`, `tools/src/tool_spec.rs`, `core/src/tools/hosted_spec.rs`,
`codex-api/src/sse/responses.rs`, `codex-api/src/api_bridge.rs`,
`protocol/src/openai_models.rs`) and the opencode Codex-auth plugin and LiteLLM
`chatgpt` provider.

- Token refresh posts a JSON body (upstream `TokenEncoding::Json`). The
  authorization-code exchange stays form-encoded. Refresh runs when the access
  token expires within 5 minutes.
- These refresh failures are permanent: 401, 400 `invalid_grant`, or
  `refresh_token_expired|reused|invalidated`. They clear this app's credentials
  and ask the user to sign in again. Other failures are transient.
- Refresh tokens are single-use. A cancelled caller no longer cancels the
  shared refresh, so a rotated token is always persisted. Sign-out still
  discards an in-flight refresh.
- The web search tool is `{"type":"web_search","external_web_access":true}`
  (upstream live mode), because cached results are unsuitable for timetables.
- The reply is the final message item, not every message item joined together.
  An item with `phase == "final_answer"` wins if present; otherwise the last
  non-empty message is used. Preamble or commentary messages are ignored.
- Error bodies are classified:
  - `usage_limit_reached`, including when returned with 404, shows the reset time.
  - `usage_not_included` reports that the subscription does not include this model or tool.
  - Rate limits get their own wording.
  - For any other status, the server's message is shown.
- Deliberate differences from upstream:
  - `originator` stays `JTM-iOS`. The app does not send `codex_cli_rs`,
    to avoid impersonating the official client.
  - The app sends its own short `instructions`. Upstream supports custom base
    instructions, but whether every account and model accepts them is only
    verifiable with a live account.

Verification:
- 34 RailCore tests passed (`ChatGPTSubscriptionProtocol|JourneyCompletion`).
- 10 OAuth fixture cases and 9 service fixture cases passed.
- The iOS Simulator app build passed.
- An independent review accepted the change.
- There was still no live account login or inference.
