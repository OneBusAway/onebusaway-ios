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
  <deviceModel>)` header so Umami's `isbot` check passes.
- **`updateServer` signature:** change from
  `updateServer(defaultDomainURL:analyticsServerURL:)` to `updateServer(region:)`
  so the orchestrator reads both the Plausible URL and the Umami config from a
  single source. Both call sites already hold the `Region`.
- **Naming:** the region-feed config model is `UmamiAnalytics` (mirrors the
  `umamiAnalytics` JSON key); the HTTP emitter is `UmamiReporter`.

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

Add a nested Codable config type mirroring the JSON shape:

```swift
@objc(OBAUmamiAnalytics)
public class UmamiAnalytics: NSObject, Codable {
    public let url: URL
    public let id: String
}
```

On `Region`:

- Property: `public let umamiAnalytics: UmamiAnalytics?`
- `CodingKeys`: `case umamiAnalytics`
- Decoder: `umamiAnalytics = try? container.decodeIfPresent(UmamiAnalytics.self, forKey: .umamiAnalytics)`
  — `null` / missing key / malformed entry all resolve to `nil` (disabled,
  never fails the surrounding region decode). Follows the existing
  `plausibleAnalyticsServerURL` pattern.
- Encoder: `try container.encodeIfPresent(umamiAnalytics, forKey: .umamiAnalytics)`
- Custom user-region `init`: `umamiAnalytics = nil`
- `isEqual` and `hash`: include `umamiAnalytics`
- `UmamiAnalytics` implements `Codable` equality so it composes with `Region`'s
  `isEqual`/`hash` (provide `==`/`hash` on the nested type, matching
  `Open311Server`).

### 2. Emitter — `UmamiReporter` (`OBAKit/Analytics/UmamiReporter.swift`)

Placed in OBAKit (alongside the `Analytics` protocol) so it is reachable by
`OBAKitTests`. Modeled on `PlausibleAnalytics`, but builds the request by hand
(no SDK).

- **Init:** `init(serverURL: URL, websiteID: String, hostname: String, session: URLSession = .shared)`.
  `session` is injectable for tests. `hostname` is the current region's
  `OBABaseURL.host`.
- **User-Agent:** computed once — `OneBusAway/<CFBundleShortVersionString>
  (iOS <UIDevice.systemVersion>; <device model>)`.
- **`postEvent(path:name:data:) async`:** builds the payload JSON, POSTs to
  `serverURL` + `/api/send` with `Content-Type: application/json` and the
  explicit `User-Agent` header. Parses the response body; a `beep`/`boop` body is
  treated as failure (logged in DEBUG, swallowed otherwise). Request timeout
  ~10s. All errors swallowed — never throws to callers.
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

- Add `private var umami: UmamiReporter?`.
- Change `updateServer(defaultDomainURL:analyticsServerURL:)` →
  `updateServer(region:)`. Inside:
  - Configure Plausible as today, reading `region.OBABaseURL` /
    `region.plausibleAnalyticsServerURL`.
  - Tear down `umami`. Then, if `reportingEnabled()` **and**
    `region.umamiAnalytics != nil`, build a new `UmamiReporter(serverURL:
    config.url, websiteID: config.id, hostname: region.OBABaseURL.host ?? "")`.
- `setReportingEnabled(false)` nils `umami` (same as Plausible) → privacy opt-out
  is respected with no extra code.
- Forward to `umami` inside a `Task` from `reportEvent`, `reportSearchQuery`,
  `reportStopViewed`, and `setUserProperty`.
- `reportSetRegion` is a no-op for Umami (per-region by construction, keyed by
  website UUID — like Plausible).
- `reportError` skips Umami.

### 4. Protocol + call sites

- Update `Analytics.updateServer` signature to `updateServer(region:)` in
  `OBAKit/Analytics/Analytics.swift`.
- Update both call sites in `OBAKit/Orchestration/Application.swift` (≈ lines 437
  and 582) to pass `region`.
- Update any test/mock conformers of `Analytics` to the new signature.

## Testing

- **Region decoding** (`OBAKitTests`): fixture region with
  `umamiAnalytics:{url,id}` decodes `url`/`id`; a region without the key → `nil`;
  an explicit `"umamiAnalytics": null` → `nil`. Extend an existing region in
  `OBAKitTests/fixtures/regions-v3.json` (or add a focused fixture).
- **`UmamiReporter`** (`OBAKitTests`, injected mock `URLSession`/protocol):
  - The POST body JSON matches the contract (`type`, nested `payload` with
    `website`, `hostname`, `url`, `name`, `data`).
  - A real, non-bot `User-Agent` header is present.
  - A `{"beep":"boop"}` response body is treated as a failure (explicitly called
    out by the issue).
  - `pageURL` → path reduction is correct.
- **Orchestrator:** emitter is created when config is present and reporting is on,
  and destroyed on opt-out or null config. (Run in the App test target if
  reachable; otherwise this behavior is covered via the reporter + region tests.)

## Fail-safe guarantees

- Emission is fire-and-forget off the UI hot path (`Task`).
- All network/parse errors are swallowed.
- Short request timeout (~10s).
- Null/absent config and the opt-out switch both result in no `UmamiReporter`,
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
