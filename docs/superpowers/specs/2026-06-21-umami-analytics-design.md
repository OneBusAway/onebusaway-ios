# Umami Analytics Support — Design

**Issue:** [#1162](https://github.com/OneBusAway/onebusaway-ios/issues/1162)
**Date:** 2026-06-21
**Branch:** `umami`

## Summary

Add Umami analytics as a third, additive fan-out backend in OBAKit. OBACloud now
runs a centralized self-hosted Umami server and publishes per-region discovery
info in the existing region feed. There is no JavaScript tracker; each client
emits events by POSTing directly to Umami's ingestion endpoint.

This work adds Umami **alongside** the existing Plausible and Firebase backends —
nothing is removed. View-controller call sites do not change: the orchestrator
forwards the events the app already reports to Umami in fire-and-forget tasks,
exactly as it does for Plausible today.

## Decisions

- **Coexistence:** additive fan-out. Plausible and Firebase remain untouched.
- **Taxonomy:** mirror the existing `Analytics` calls (`reportEvent`,
  `reportSearchQuery`, `reportStopViewed`). No new event call sites in view
  controllers.
- **User-Agent:** send an explicit `OneBusAway/<appVersion> (iOS <systemVersion>;
  <deviceModel>)` header so Umami's `isbot` check passes. Build it from existing
  repo helpers — `Bundle.main.appVersion` (`CFBundleShortVersionString`),
  `UIDevice.current.systemVersion`, and `UIDevice.current.modelName` (the `uname`
  identifier, e.g. `iPhone14,5`) — **not** `UIDevice.current.model`, which returns
  a generic `"iPhone"` that risks the bot filter.
- **`updateServer` signature:** change from
  `updateServer(defaultDomainURL:analyticsServerURL:)` to `updateServer(region:)`
  so the orchestrator reads both the Plausible URL and the Umami config from a
  single source. Both call sites already hold the `Region`.
- **Naming:** the region-feed config model is `UmamiAnalytics` (mirrors the
  `umamiAnalytics` JSON key); the HTTP emitter is `UmamiAnalytics`.

## Discovery contract (region feed)

Each region entry carries (or omits) a nested object:

```json
"umamiAnalytics": { "url": "https://analytics.onebusawaycloud.com", "id": "<website-uuid>" }
```

- `url` — Umami host to POST events to.
- `id` — Umami website UUID events are keyed/routed by.
- The whole object is `null` (or absent) when analytics is not configured for the
  region. Treat that as **disabled → never emit**.

## Emission contract

`POST <url>/api/send`, `Content-Type: application/json`:

```json
{
  "type": "event",
  "payload": {
    "website": "<id>",
    "hostname": "<region host>",
    "url": "/screen-or-path",
    "name": "event_name",
    "data": { "anyCustom": "props" }
  }
}
```

- Omit `name` ⇒ pageview; include `name` ⇒ custom event.
- Ingestion is unauthenticated — keyed only by the website UUID. No API key.
- Sessions are attributed server-side from client IP + User-Agent.

### Critical gotcha — the User-Agent

Umami runs every request through `isbot`. A missing or bot-like User-Agent makes
Umami **silently drop the event and return HTTP 200 with body `{"beep":"boop"}`**.
A successful ingest returns a body containing `cache`/`sessionId`/`visitId`. The
emitter must send a real device-like UA and must treat a `beep`/`boop` body as a
failure.

## Components

### 1. Region model (`OBAKitCore/Models/Region.swift`)

Add a nested config type mirroring the JSON shape. Use a **plain Swift `struct`**
— `Region` is persisted via `Codable` (PropertyList/JSON), not `NSCoding`, and
nothing reads this sub-model from Objective-C, so `@objc`/`NSObject` buys nothing.
A `struct` gets `Equatable`, `Hashable`, and `Codable` synthesized for free,
which is what `Region.isEqual`/`hash` need:

```swift
public struct UmamiAnalytics: Codable, Equatable, Hashable {
    public let url: URL
    public let id: String
}
```

(The existing `Open311Server` is `NSObject`-based for historical reasons; we are
not following that here. If a later check finds `Region` is NSCoding-archived
somewhere, revisit — but it is not today.)

On `Region`:

- Property: `public let umamiAnalytics: UmamiAnalytics?`
- `CodingKeys`: `case umamiAnalytics`
- Decoder: `umamiAnalytics = try? container.decodeIfPresent(UmamiAnalytics.self, forKey: .umamiAnalytics)`
  — `null` / missing key / malformed entry all resolve to `nil` (disabled,
  never fails the surrounding region decode). Follows the existing
  `plausibleAnalyticsServerURL` pattern.
- Encoder: `try container.encodeIfPresent(umamiAnalytics, forKey: .umamiAnalytics)`
- Custom user-region `init`: `umamiAnalytics = nil`
- `isEqual` and `hash`: **must** include `umamiAnalytics` (the hand-rolled
  `isEqual`/`hash` on lines ~329–392 do not pick it up automatically — without
  this, two regions differing only in Umami config compare equal). The struct's
  synthesized `==`/`hashValue` compose directly:
  `umamiAnalytics == rhs.umamiAnalytics` and `hasher.combine(umamiAnalytics)`.

### 2. Emitter — `UmamiAnalytics` (`OBAKit/Analytics/UmamiAnalytics.swift`)

Placed in OBAKit (alongside the `Analytics` protocol) so it is reachable by
`OBAKitTests`. Modeled on `PlausibleAnalytics`, but builds the request by hand
(no SDK).

- **Init:** `init(serverURL: URL, websiteID: String, hostname: String, dataLoader: URLDataLoader = UmamiAnalytics.makeDefaultSession())`.
  Inject the existing **`URLDataLoader`** protocol (OBAKitCore/Network) rather than
  a live `URLSession` — that is the seam the rest of the networking suite already
  mocks via `MockDataLoader`, so the emitter is testable with the same double the
  codebase uses (and no bespoke `URLProtocol` subclass). `URLDataLoader` exposes
  `func data(for: URLRequest) async throws -> (Data, URLResponse)`. `hostname` is
  the current region's `OBABaseURL.host`.
  - **Default loader is a purpose-built session, NOT `URLSession.shared`.**
    `URLSession.shared` is an unconfigurable singleton, so the resource-timeout
    strategy below can't apply to it. The default comes from a small factory
    `static func makeDefaultSession() -> URLSession` that builds a
    `URLSession(configuration:)` whose `timeoutIntervalForResource` (and a short
    `timeoutIntervalForRequest`) are set to the fail-safe values. `MockDataLoader`
    is still injected in tests.
- **User-Agent:** computed once — `OneBusAway/\(Bundle.main.appVersion) (iOS
  \(UIDevice.current.systemVersion); \(UIDevice.current.modelName))`, e.g.
  `OneBusAway/2.5.0 (iOS 17.0; iPhone14,5)`. Uses the repo helpers noted in §1.
- **JSON body construction (fail-safe — do NOT use raw `JSONSerialization`):**
  the `Analytics` protocol passes `value: Any?`, so the Umami `data` dict holds
  heterogeneous values. `JSONSerialization.data(withJSONObject:)` throws an
  **Objective-C `NSException`** (not a Swift `Error`) for non-JSON input — a Swift
  `do/catch` will **not** catch it, so it would crash inside the fire-and-forget
  `Task`, violating "all errors swallowed." Instead, model the payload as an
  `Encodable` struct and coerce `data` values into a closed JSON enum
  (`String`/`Int`/`Double`/`Bool`, stringifying anything else, dropping non-finite
  doubles). Encode with `JSONEncoder`, whose `EncodingError` is a catchable Swift
  error. This also keeps the outer payload type-safe.
- **`postEvent(path:name:data:) async`:** builds the payload via the `Encodable`
  struct above, POSTs to `serverURL` + `/api/send` with
  `Content-Type: application/json` and the explicit `User-Agent` header via
  `dataLoader.data(for:)`. Parses the response **defensively**: a 200 whose body
  is `{"beep":"boop"}` is a failure, and so is any body lacking the success
  markers (`cache`/`sessionId`/`visitId`) or that fails to parse — none of these
  may throw out of the method. Logged in DEBUG, swallowed otherwise. All errors
  swallowed — never throws to callers.
- **Timeout (fail-safe):** set on the factory session's `URLSessionConfiguration`.
  `timeoutIntervalForResource` is the wall-clock end-to-end cap (Apple default is
  7 days); set it tight (~10s). `timeoutIntervalForRequest` is the separate
  *idle/stall* timer — do not treat it as the total cap. This intentionally
  deviates from Apple's "avoid short timeouts" guidance because this is
  best-effort telemetry with all errors swallowed and must stay off the UI hot
  path. (Do not use `URLRequest.timeoutInterval` for the total cap — it is the
  idle timer.)
- **Mirror methods** (parallel to `PlausibleAnalytics`):
  - `reportEvent(pageURL:label:value:)` → named event: `name = label`,
    `url = path(of: pageURL)`, `data = ["value": value]` (omitted when value nil).
  - `reportSearchQuery(_:)` → `reportEvent(pageURL: "app://localhost/search",
    label: "query", value: query)`.
  - `reportStopViewed(name:id:stopDistance:)` → pageview at `/stop` (no `name`)
    with `data = ["id": id, "distance": stopDistance]`.
  - `setUserProperty(key:value:)` → merged into default `data` applied to every
    event (mirrors Plausible's `defaultProperties`).
- **Path reduction:** `app://localhost/map` → `/map` for the Umami `url` field.

### 3. Orchestrator wiring (`Apps/Shared/Analytics/AnalyticsOrchestrator.swift`)

- Add `private var umami: UmamiAnalytics?`.
- Change `updateServer(defaultDomainURL:analyticsServerURL:)` →
  `updateServer(region:)`. Inside:
  - Configure Plausible as today, reading `region.OBABaseURL` /
    `region.plausibleAnalyticsServerURL`.
  - Tear down `umami`. Then, if `reportingEnabled()` **and**
    `region.umamiAnalytics != nil`, build a new `UmamiAnalytics(serverURL:
    config.url, websiteID: config.id, hostname: region.OBABaseURL.host ?? "")`.
- `setReportingEnabled(false)` nils `umami` (same as Plausible) → privacy opt-out
  takes effect immediately.
- **Opt-in asymmetry (documented, parity with Plausible):** `setReportingEnabled(true)`
  only persists the flag — it does **not** rebuild `umami` (or Plausible), because
  both are constructed solely in `updateServer(region:)`. So re-enabling reporting
  takes effect on the **next** `updateServer` call (next app-foreground via
  `applicationDidBecomeActive`, or a region change). This matches existing
  Plausible behavior and is acceptable for this PR; the orchestrator test must
  therefore not assert *instantaneous* emitter creation on opt-in.
- Forward to `umami` inside a `Task` from `reportEvent`, `reportSearchQuery`,
  `reportStopViewed`, and `setUserProperty`. `UmamiAnalytics` stays a plain class
  (no `actor`/`Sendable` ceremony) — parity with the existing Plausible `Task`
  pattern, which the orchestrator solely owns and mutates on the main thread. To
  avoid the latent `defaultProperties` read/write race Plausible also has, snapshot
  the default `data` at `postEvent` entry rather than reading it mid-flight.
- `reportSetRegion` is a no-op for Umami (per-region by construction, keyed by
  website UUID — like Plausible).
- `reportError` skips Umami.

### 4. Protocol + call sites

- Update `Analytics.updateServer` signature to `updateServer(region:)` in
  `OBAKit/Analytics/Analytics.swift`.
- Update both call sites in `OBAKit/Orchestration/Application.swift` (≈ lines 437
  and 582) to pass `region`.
- Update the existing mock conformer `AnalyticsMock`
  (`OBAKitTests/Helpers/Mocks/AnalyticsMock.swift`) for the new signature — or
  simply drop its `updateServer` override, since the protocol method is
  `@objc optional`.

## Testing

- **Region decoding** (`OBAKitTests`): fixture region with
  `umamiAnalytics:{url,id}` decodes `url`/`id`; a region without the key → `nil`;
  an explicit `"umamiAnalytics": null` → `nil`. Extend an existing region in
  `OBAKitTests/fixtures/regions-v3.json` (or add a focused fixture).
- **Region encode→decode round-trip:** assert `umamiAnalytics` survives a full
  `encode(to:)` → `decode` cycle. `Region` is persisted to disk via `encode(to:)`,
  so a missing `encodeIfPresent` line would silently drop the field on next load —
  decode-only tests would not catch it.
- **`UmamiAnalytics`** (`OBAKitTests`, injected `MockDataLoader`):
  - The POST body JSON matches the contract (`type`, nested `payload` with
    `website`, `hostname`, `url`, `name`, `data`) — assert off the recorded
    request.
  - A real, non-bot `User-Agent` header is present on the recorded request.
  - A `{"beep":"boop"}` 200 response body is treated as a failure (register it
    via `MockDataLoader.mock(data:matcher:)`; explicitly called out by the issue).
    Also assert a success body (`cache`/`sessionId`/`visitId`) is treated as
    success.
  - `pageURL` → path reduction: `app://localhost/map` → `/map`; define and test
    the edge cases — no path (`app://localhost` → `/`) and a query
    (`app://localhost/search?q=x`).
  - **Non-JSON safety:** feeding a non-JSON / non-finite `value` (e.g. `Double.nan`
    or a model object) must not crash and must not throw out of `postEvent` —
    guards the fire-and-forget guarantee against the `JSONSerialization` NSException
    hazard.
  - "Never emit" assertions can use `MockDataLoader.recordedRequestURLs` to prove
    no request was made.
- **Orchestrator:** on `updateServer(region:)`, the emitter is created when config
  is present and reporting is on, and is absent for null config; it is destroyed on
  opt-out. Do **not** assert instantaneous creation on `setReportingEnabled(true)`
  — re-enable takes effect on the next `updateServer` (see Opt-in asymmetry above).
  (Run in the App test target if reachable; otherwise this behavior is covered via
  the reporter + region tests.)

## Fail-safe guarantees

- Emission is fire-and-forget off the UI hot path (`Task`).
- All network/parse errors are swallowed.
- Short request timeout (~10s).
- Null/absent config and the opt-out switch both result in no `UmamiAnalytics`,
  so no request is ever made.

## Manual verification (not automatable)

Acceptance criterion "a real device event shows up under the correct website in
the Umami dashboard" requires a device build plus dashboard access. Checklist for
Aaron to run:

1. Build/run on a device or simulator in a region whose feed includes
   `umamiAnalytics`.
2. Ensure the privacy "Send usage data" switch is on.
3. Trigger a mirrored event (view a stop, run a search).
4. Confirm the event appears under the correct website UUID in the Umami
   dashboard, and that the response body was `cache/sessionId/visitId` (not
   `beep/boop`).
5. Confirm no events are sent for a region without `umamiAnalytics`.

After adding the new source files, re-run `scripts/generate_project` so they are
included in the Xcode project (XcodeGen).

## Out of scope

- Removing or deprecating Plausible (tracked separately).
- New event taxonomy beyond what the app already reports.
- Any UI changes (the existing privacy opt-out is reused as-is).
