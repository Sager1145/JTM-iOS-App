# Screenshot import and AI completion

The screenshot importer reads Yahoo! 乗換案内 and JR東日本アプリ locally using
Vision, then builds a preview against the Japanese station package. Select
screenshots in journey order. Photos selection now displays selection order;
an unreadable page or failed OCR tile fails the attempt instead of silently
importing an incomplete journey.

The screenshot preview and journey editor expose **AI completion** when the
journey has named endpoints/stops and at least two identifying details among
date, time, line, operator, and service information. Completion is explicit:

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

Completion does not insert stops, change station identities, mark travel as
ridden, or save automatically. Changing the import date discards completion
suggestions because timetable evidence may no longer apply. Toggling included
legs or ridden status preserves suggestions for the corresponding leg.

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

`JourneyCompletionTests` tests eligibility, prompt contents, strict decoding,
missing-field merges, preservation of existing data and malformed responses.
`JourneyCompletionUITests` exercises the new-journey entry point and prevents
applying invalid or empty replies.
`TransferGuideTests` covers screenshot parser regressions using OCR text and
bounding-box fixtures. A device test with actual source screenshots is still
needed to measure end-to-end OCR accuracy; parser fixtures cannot establish a
recognition accuracy percentage.

Focused core verification passed: 54 TransferGuide tests and 11
JourneyCompletion tests. The iOS Simulator Debug app build also passed.
The focused new-journey UI test passed on an isolated iOS 27 simulator,
including insufficient-information gating, opening completion, rejecting an
invalid reply, and keeping Apply disabled for an empty/no-op reply.

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
