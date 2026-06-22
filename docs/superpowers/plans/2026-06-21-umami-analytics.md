# Umami Analytics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Umami analytics as an additive, per-region, fire-and-forget HTTP event backend alongside the existing Plausible and Firebase analytics.

**Architecture:** A new `UmamiAnalytics` (in OBAKit) POSTs events to a per-region Umami `/api/send` endpoint discovered from a new `Region.umamiAnalytics` config object (in OBAKitCore). `AnalyticsOrchestrator` constructs/destroys the reporter on region change and opt-out, and forwards the events the app already reports — no view-controller changes. All emission is off the UI hot path and swallows every error.

**Tech Stack:** Swift 5 / UIKit, iOS 17+, `URLSession` via the repo's `URLDataLoader` seam, `JSONEncoder`/`Codable`, XCTest + Nimble, XcodeGen.

## Global Constraints

- **iOS target:** 17.0+. **Language mode:** Swift 5.
- **Simulator for tests:** `iPhone 17` (the `iPhone 16` named in CLAUDE.md is not installed locally).
- **Fail-safe:** analytics code must never throw to callers, never block the UI, and never crash the app. All network/encode/parse errors are swallowed (logged only under `#if DEBUG`).
- **Never use `JSONSerialization.data(withJSONObject:)` to BUILD request bodies** — it throws an uncatchable Obj-C `NSException` on non-JSON input. Build bodies with `JSONEncoder` over `Encodable` types only. (Reading responses with `JSONSerialization.jsonObject(with:)` is fine — that path throws a catchable Swift error.)
- **Explicit User-Agent** on every Umami request: `OneBusAway/<appVersion> (iOS <systemVersion>; <modelName>)` using `Bundle.main.appVersion`, `UIDevice.current.systemVersion`, `UIDevice.current.modelName`. A bot-like/missing UA makes Umami silently drop the event (200 + `{"beep":"boop"}`).
- **Per-region:** read `umamiAnalytics.url` / `.id` from the current region; `null`/absent ⇒ analytics disabled ⇒ never emit.
- **Regenerate the project** with `scripts/generate_project OneBusAway` after adding any new `.swift` file, or it won't be in the Xcode target and tests will silently not run.

---

### Task 1: `Region.umamiAnalytics` config model + decoding

Adds the `UmamiAnalytics` value type and wires it through `Region`'s Codable, equality, and hashing. No new files (the struct lives in `Region.swift` next to `Open311Server`), so no project regeneration is needed for this task.

**Files:**
- Modify: `OBAKitCore/Models/Region.swift` (add struct near `Open311Server` ~line 525; add property ~line 53; CodingKey ~line 172; decoder ~line 259; encoder ~line 297; custom `init` ~line 233; `isEqual` ~line 358; `hash` ~line 390)
- Modify (fixtures): `OBAKitTests/fixtures/regions-v3.json` (region index 0 gets a config, index 1 gets explicit `null`)
- Test: `OBAKitTests/Modeling/Model Unit Tests/RegionsEncodingTests.swift`

**Interfaces:**
- Produces: `public struct UmamiAnalytics: Codable, Equatable, Hashable { public let url: URL; public let id: String }` and `Region.umamiAnalytics: UmamiAnalytics?`. Consumed by Task 3 (orchestrator).

- [ ] **Step 1: Add the `umamiAnalytics` config to the JSON fixture**

In `OBAKitTests/fixtures/regions-v3.json`, in the **first** region object (`"regionName": "Tampa Bay"`, `"id": 0`), add this key (place it right after the `"sidecarBaseUrl"` line so it's easy to find):

```json
        "umamiAnalytics": { "url": "https://analytics.onebusawaycloud.com", "id": "abc-123-uuid" },
```

In the **second** region object (`"id": 1`), add an explicit null to prove the null path:

```json
        "umamiAnalytics": null,
```

- [ ] **Step 2: Write the failing test**

Add this method to `RegionsEncodingTests` in `OBAKitTests/Modeling/Model Unit Tests/RegionsEncodingTests.swift`:

```swift
    func testUmamiAnalyticsDecoding() {
        let regions = try! Fixtures.loadRESTAPIPayload(type: [Region].self, fileName: "regions-v3.json")

        // Present: region 0 decodes url + id.
        let umami = regions[0].umamiAnalytics
        expect(umami?.url) == URL(string: "https://analytics.onebusawaycloud.com")!
        expect(umami?.id) == "abc-123-uuid"

        // Explicit JSON null (region 1) → nil.
        expect(regions[1].umamiAnalytics).to(beNil())

        // Absent key (region 2) → nil.
        expect(regions[2].umamiAnalytics).to(beNil())

        // Survives a property-list encode → decode round trip (Region is persisted to disk).
        let plist = try! PropertyListEncoder().encode(regions)
        let roundTripped = try! PropertyListDecoder().decode([Region].self, from: plist)
        expect(roundTripped[0].umamiAnalytics?.url) == URL(string: "https://analytics.onebusawaycloud.com")!
        expect(roundTripped[0].umamiAnalytics?.id) == "abc-123-uuid"
        expect(roundTripped[1].umamiAnalytics).to(beNil())
    }
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
scripts/generate_project OneBusAway
xcodebuild test -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:OBAKitTests/RegionsEncodingTests/testUmamiAnalyticsDecoding
```
Expected: FAIL to compile with "value of type 'Region' has no member 'umamiAnalytics'".

- [ ] **Step 4: Add the `UmamiAnalytics` struct**

In `OBAKitCore/Models/Region.swift`, immediately above the `public class Open311Server` declaration (~line 525), add:

```swift
/// Per-region Umami analytics discovery info, published in the region feed.
///
/// `nil` (a JSON `null` or an absent key) means analytics is disabled for the
/// region and no events should be emitted.
public struct UmamiAnalytics: Codable, Equatable, Hashable {
    /// The Umami host to POST events to, e.g. `https://analytics.onebusawaycloud.com`.
    public let url: URL

    /// The Umami website UUID that events are keyed/routed by.
    public let id: String
}
```

(The JSON keys `url`/`id` match the property names, so no custom `CodingKeys` are needed.)

- [ ] **Step 5: Wire the property into `Region`**

In `OBAKitCore/Models/Region.swift`, make these six edits.

a) Property — after the `plausibleAnalyticsServerURL` declaration (~line 53):

```swift
    /// Per-region Umami analytics config, or `nil` when analytics is disabled for this region.
    public let umamiAnalytics: UmamiAnalytics?
```

b) CodingKeys — after `case plausibleAnalyticsServerURL = "plausibleAnalyticsServerUrl"` (~line 172):

```swift
        case umamiAnalytics
```

c) Decoder — after the `plausibleAnalyticsServerURL = ...` line (~line 259):

```swift
        umamiAnalytics = try? container.decodeIfPresent(UmamiAnalytics.self, forKey: .umamiAnalytics)
```

d) Encoder — after `try container.encode(plausibleAnalyticsServerURL, forKey: .plausibleAnalyticsServerURL)` (~line 297):

```swift
        try container.encodeIfPresent(umamiAnalytics, forKey: .umamiAnalytics)
```

e) Custom `init` — after `plausibleAnalyticsServerURL = nil` (~line 233):

```swift
        umamiAnalytics = nil
```

f) `isEqual` — add a clause to the `return` chain (after the `plausibleAnalyticsServerURL == rhs.plausibleAnalyticsServerURL &&` line ~340):

```swift
            umamiAnalytics == rhs.umamiAnalytics &&
```

g) `hash` — after `hasher.combine(plausibleAnalyticsServerURL)` (~line 371):

```swift
        hasher.combine(umamiAnalytics)
```

- [ ] **Step 6: Run the test to verify it passes**

```bash
xcodebuild test -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:OBAKitTests/RegionsEncodingTests/testUmamiAnalyticsDecoding
```
Expected: PASS.

- [ ] **Step 7: Run the full Region encoding suite to confirm no regression**

```bash
xcodebuild test -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:OBAKitTests/RegionsEncodingTests
```
Expected: PASS (the existing `testRoundtrippingRegion` still passes; region count is still 17).

- [ ] **Step 8: Commit**

```bash
git add OBAKitCore/Models/Region.swift OBAKitTests/fixtures/regions-v3.json "OBAKitTests/Modeling/Model Unit Tests/RegionsEncodingTests.swift"
git commit -m "Add Region.umamiAnalytics config decoding (#1162)"
```

---

### Task 2: `UmamiAnalytics` HTTP emitter

The self-contained emitter and its JSON-value coercion, with the crash-safe body construction, explicit UA, defensive response parsing, and a tight resource timeout. All logic is unit-tested via the existing `MockDataLoader`.

**Files:**
- Create: `OBAKit/Analytics/UmamiAnalytics.swift`
- Create: `OBAKitTests/Analytics/UmamiAnalyticsTests.swift`
- Test: `OBAKitTests/Analytics/UmamiAnalyticsTests.swift`

**Interfaces:**
- Consumes: `URLDataLoader` (OBAKitCore), `Bundle.appVersion` (OBAKitCore), `UIDevice.modelName` (OBAKitCore), `Region.UmamiAnalytics` (Task 1).
- Produces (all `internal`, reachable via `@testable import OBAKit`):
  - `final class UmamiAnalytics` with `init(serverURL: URL, websiteID: String, hostname: String, dataLoader: URLDataLoader = UmamiAnalytics.makeDefaultSession())`
  - `func reportEvent(pageURL: String, label: String, value: Any?) async`
  - `func reportSearchQuery(_ query: String) async`
  - `func reportStopViewed(name: String, id: String, stopDistance: String) async`
  - `func setUserProperty(key: String, value: String?)`
  - `static func path(from pageURL: String) -> String`
  - `static func isSuccessfulIngest(_ data: Data) -> Bool`
  - `enum UmamiJSONValue: Encodable { case string(String); case int(Int); case double(Double); case bool(Bool); init?(_ value: Any?) }`

- [ ] **Step 1: Create the emitter source file**

Create `OBAKit/Analytics/UmamiAnalytics.swift` with the full implementation:

```swift
//
//  UmamiAnalytics.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import UIKit
import OBAKitCore

/// A JSON-safe value for a Umami custom-event `data` dictionary.
///
/// The `Analytics` protocol passes `value: Any?`, so values are coerced through
/// `init?` into a closed set of encodable cases. Anything that can't be
/// represented (e.g. a non-finite `Double`) is dropped by returning `nil`, which
/// keeps body construction crash-free (we never hand raw `Any` to JSON encoding).
enum UmamiJSONValue: Encodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    init?(_ value: Any?) {
        guard let value else { return nil }
        switch value {
        case let v as Bool: self = .bool(v)
        case let v as Int: self = .int(v)
        case let v as Double:
            guard v.isFinite else { return nil }
            self = .double(v)
        case let v as String: self = .string(v)
        case let v as CustomStringConvertible: self = .string(v.description)
        default: return nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        }
    }
}

/// Fire-and-forget Umami event emitter. POSTs to `<serverURL>/api/send`.
///
/// Never throws, never blocks the UI, swallows all errors. Constructed per-region
/// by `AnalyticsOrchestrator`; one instance is bound to a single Umami website.
final class UmamiAnalytics {
    private let serverURL: URL
    private let websiteID: String
    private let hostname: String
    private let dataLoader: URLDataLoader
    private let userAgent: String

    /// Default properties merged into every event's `data`. Set via `setUserProperty`.
    private var defaultData: [String: UmamiJSONValue] = [:]

    init(serverURL: URL,
         websiteID: String,
         hostname: String,
         dataLoader: URLDataLoader = UmamiAnalytics.makeDefaultSession()) {
        self.serverURL = serverURL
        self.websiteID = websiteID
        self.hostname = hostname
        self.dataLoader = dataLoader
        self.userAgent = "OneBusAway/\(Bundle.main.appVersion) (iOS \(UIDevice.current.systemVersion); \(UIDevice.current.modelName))"
    }

    /// A session with a tight end-to-end resource timeout. `URLSession.shared`
    /// cannot be configured, so we build our own.
    static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10   // idle/stall timer
        config.timeoutIntervalForResource = 10  // wall-clock end-to-end cap
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    // MARK: - Event API (mirrors the Analytics protocol)

    func reportEvent(pageURL: String, label: String, value: Any?) async {
        var data = defaultData
        if let jsonValue = UmamiJSONValue(value) {
            data["value"] = jsonValue
        }
        await postEvent(path: Self.path(from: pageURL), name: label, data: data)
    }

    func reportSearchQuery(_ query: String) async {
        await reportEvent(pageURL: "app://localhost/search", label: "query", value: query)
    }

    func reportStopViewed(name: String, id: String, stopDistance: String) async {
        var data = defaultData
        data["id"] = .string(id)
        data["distance"] = .string(stopDistance)
        // No `name` → recorded as a pageview at /stop.
        await postEvent(path: "/stop", name: nil, data: data)
    }

    func setUserProperty(key: String, value: String?) {
        if let value {
            defaultData[key] = .string(value)
        } else {
            defaultData.removeValue(forKey: key)
        }
    }

    // MARK: - Wire format

    private struct Payload: Encodable {
        let type = "event"
        let payload: Body

        struct Body: Encodable {
            let website: String
            let hostname: String
            let url: String
            let name: String?                       // omitted when nil → pageview
            let data: [String: UmamiJSONValue]?     // omitted when nil/empty
        }
    }

    private func postEvent(path: String, name: String?, data: [String: UmamiJSONValue]) async {
        let payload = Payload(payload: .init(
            website: websiteID,
            hostname: hostname,
            url: path,
            name: name,
            data: data.isEmpty ? nil : data
        ))

        // JSONEncoder throws a *catchable* Swift error; never an NSException.
        guard let httpBody = try? JSONEncoder().encode(payload) else { return }

        var request = URLRequest(url: serverURL.appendingPathComponent("api/send"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = httpBody

        do {
            let (responseData, _) = try await dataLoader.data(for: request)
            if !Self.isSuccessfulIngest(responseData) {
                #if DEBUG
                let body = String(data: responseData, encoding: .utf8) ?? "<non-utf8>"
                print("[UmamiAnalytics] event dropped (bot UA / bad config?). Body: \(body)")
                #endif
            }
        } catch {
            #if DEBUG
            print("[UmamiAnalytics] emit failed: \(error)")
            #endif
        }
    }

    // MARK: - Helpers

    /// Reduces an internal page URL (e.g. `app://localhost/map`) to the Umami `url`
    /// path (`/map`). Empty/path-less URLs become `/`; query strings are dropped.
    static func path(from pageURL: String) -> String {
        guard let components = URLComponents(string: pageURL), !components.path.isEmpty else {
            return "/"
        }
        return components.path
    }

    /// A successful Umami ingest returns a body with `cache`/`sessionId`/`visitId`.
    /// A dropped event returns `{"beep":"boop"}`. Treats anything else as failure.
    static func isSuccessfulIngest(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        if object["beep"] != nil { return false }
        return object["cache"] != nil || object["sessionId"] != nil || object["visitId"] != nil
    }
}
```

- [ ] **Step 2: Create the failing test file**

Create `OBAKitTests/Analytics/UmamiAnalyticsTests.swift`:

```swift
//
//  UmamiAnalyticsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
@testable import OBAKit
@testable import OBAKitCore

final class UmamiAnalyticsTests: OBATestCase {

    private let successBody = #"{"cache":"x","sessionId":"s","visitId":"v"}"#.data(using: .utf8)!
    private let beepBoopBody = #"{"beep":"boop"}"#.data(using: .utf8)!

    private func makeReporter(loader: MockDataLoader) -> UmamiAnalytics {
        UmamiAnalytics(serverURL: URL(string: "https://analytics.example.com")!,
                      websiteID: "site-uuid",
                      hostname: "api.example.org",
                      dataLoader: loader)
    }

    // MARK: - path(from:)

    func testPathReduction() {
        expect(UmamiAnalytics.path(from: "app://localhost/map")) == "/map"
        expect(UmamiAnalytics.path(from: "app://localhost")) == "/"
        expect(UmamiAnalytics.path(from: "app://localhost/search?q=x")) == "/search"
    }

    // MARK: - isSuccessfulIngest

    func testSuccessDetection() {
        expect(UmamiAnalytics.isSuccessfulIngest(self.successBody)).to(beTrue())
        expect(UmamiAnalytics.isSuccessfulIngest(self.beepBoopBody)).to(beFalse())
        expect(UmamiAnalytics.isSuccessfulIngest("not json".data(using: .utf8)!)).to(beFalse())
    }

    // MARK: - UmamiJSONValue coercion

    func testJSONValueCoercion() {
        expect(UmamiJSONValue("hi")).toNot(beNil())
        expect(UmamiJSONValue(42)).toNot(beNil())
        // Non-JSON / non-finite values are dropped (nil), never crash.
        expect(UmamiJSONValue(Double.nan)).to(beNil())
        expect(UmamiJSONValue(nil)).to(beNil())
    }

    // MARK: - Request construction

    func testReportStopViewedBuildsContractRequest() async throws {
        let loader = MockDataLoader(testName: name)
        var captured: URLRequest?
        loader.mock(data: successBody) { request in
            captured = request
            return true
        }

        let reporter = makeReporter(loader: loader)
        await reporter.reportStopViewed(name: "Pine St", id: "1_75403", stopDistance: "near")

        let request = try XCTUnwrap(captured)
        expect(request.url?.absoluteString) == "https://analytics.example.com/api/send"
        expect(request.httpMethod) == "POST"
        expect(request.value(forHTTPHeaderField: "Content-Type")) == "application/json"

        // Explicit, non-bot User-Agent.
        let ua = try XCTUnwrap(request.value(forHTTPHeaderField: "User-Agent"))
        expect(ua).to(contain("OneBusAway/"))

        // Body matches the Umami contract.
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as! [String: Any]
        expect(body["type"] as? String) == "event"
        let payload = body["payload"] as! [String: Any]
        expect(payload["website"] as? String) == "site-uuid"
        expect(payload["hostname"] as? String) == "api.example.org"
        expect(payload["url"] as? String) == "/stop"
        expect(payload["name"]).to(beNil())   // pageview → no name
        let data = payload["data"] as! [String: Any]
        expect(data["id"] as? String) == "1_75403"
        expect(data["distance"] as? String) == "near"
    }

    func testReportEventIncludesName() async throws {
        let loader = MockDataLoader(testName: name)
        var captured: URLRequest?
        loader.mock(data: successBody) { request in
            captured = request
            return true
        }

        let reporter = makeReporter(loader: loader)
        await reporter.reportEvent(pageURL: "app://localhost/map", label: "Clicked MapStopIcon", value: nil)

        let request = try XCTUnwrap(captured)
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as! [String: Any]
        let payload = body["payload"] as! [String: Any]
        expect(payload["name"] as? String) == "Clicked MapStopIcon"
        expect(payload["url"] as? String) == "/map"
    }

    // MARK: - Fail-safe

    func testNonJSONValueDoesNotCrashOrThrow() async throws {
        let loader = MockDataLoader(testName: name)
        loader.mock(data: successBody) { _ in true }
        let reporter = makeReporter(loader: loader)
        // Double.nan is not representable; the event still emits without the value, no crash.
        await reporter.reportEvent(pageURL: "app://localhost/map", label: "x", value: Double.nan)
    }

    func testBeepBoopResponseIsSwallowed() async throws {
        let loader = MockDataLoader(testName: name)
        loader.mock(data: beepBoopBody) { _ in true }
        let reporter = makeReporter(loader: loader)
        // Should complete normally despite the dropped-event response.
        await reporter.reportSearchQuery("downtown")
        expect(loader.recordedRequestURLs.count) == 1
    }
}
```

- [ ] **Step 3: Regenerate the project and run the test to verify it passes**

The new source + test files must be added to the Xcode targets first.

```bash
scripts/generate_project OneBusAway
xcodebuild test -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:OBAKitTests/UmamiAnalyticsTests
```
Expected: PASS (all 7 test methods).

- [ ] **Step 4: Commit**

```bash
git add OBAKit/Analytics/UmamiAnalytics.swift OBAKitTests/Analytics/UmamiAnalyticsTests.swift OBAKit.xcodeproj
git commit -m "Add UmamiAnalytics event emitter (#1162)"
```

---

### Task 3: Orchestrator wiring + protocol signature change

Changes `Analytics.updateServer` to take a `Region`, builds/tears down the Umami reporter alongside Plausible, forwards the mirrored events, and updates the two call sites and the test mock. There is no unit test for `AnalyticsOrchestrator` (it lives in the App target, outside `OBAKitTests`); correctness here is gated by a clean build of the whole app + the full existing test suite still passing.

**Files:**
- Modify: `OBAKit/Analytics/Analytics.swift:85` (protocol method signature)
- Modify: `Apps/Shared/Analytics/AnalyticsOrchestrator.swift` (add `umami` field; rewrite `updateServer`; forward events; opt-out)
- Modify: `OBAKit/Orchestration/Application.swift:437` and `:582` (call sites)
- Modify: `OBAKitTests/Helpers/Mocks/AnalyticsMock.swift:40-42` (drop stale override)

**Interfaces:**
- Consumes: `UmamiAnalytics` (Task 2), `Region.umamiAnalytics` (Task 1).
- Produces: `Analytics.updateServer(region: Region)`.

- [ ] **Step 1: Change the protocol signature**

In `OBAKit/Analytics/Analytics.swift`, replace line 85:

```swift
    @objc optional func updateServer(defaultDomainURL: URL, analyticsServerURL: URL?)
```

with:

```swift
    @objc optional func updateServer(region: Region)
```

- [ ] **Step 2: Update the two call sites in `Application.swift`**

In `OBAKit/Orchestration/Application.swift`, replace line 437:

```swift
            analytics.updateServer!(defaultDomainURL: region.OBABaseURL, analyticsServerURL: region.plausibleAnalyticsServerURL)
```

with:

```swift
            analytics.updateServer!(region: region)
```

And replace line 582:

```swift
            analytics.updateServer!(defaultDomainURL: region.OBABaseURL, analyticsServerURL: region.plausibleAnalyticsServerURL)
```

with:

```swift
            analytics.updateServer!(region: region)
```

- [ ] **Step 3: Drop the stale override in `AnalyticsMock`**

In `OBAKitTests/Helpers/Mocks/AnalyticsMock.swift`, delete lines 40-42 (the `updateServer` method is `@objc optional`, so the mock doesn't need to implement it):

```swift
    func updateServer(defaultDomainURL: URL, analyticsServerURL: URL?) {
        //
    }
```

- [ ] **Step 4: Add the Umami field and rewrite `updateServer` in the orchestrator**

In `Apps/Shared/Analytics/AnalyticsOrchestrator.swift`, add the field after line 17 (`private var plausibleAnalytics: PlausibleAnalytics?`):

```swift
    private var umami: UmamiAnalytics?
```

Then replace the entire `updateServer` method (lines 60-70):

```swift
    public func updateServer(defaultDomainURL: URL, analyticsServerURL: URL?) {
        plausibleAnalytics = nil

        guard let analyticsServerURL else {
            return
        }

        if reportingEnabled() {
            plausibleAnalytics = PlausibleAnalytics(defaultDomainURL: defaultDomainURL, analyticsServerURL: analyticsServerURL)
        }
    }
```

with:

```swift
    public func updateServer(region: Region) {
        // Rebuild per-region analytics backends from scratch on every region change.
        plausibleAnalytics = nil
        umami = nil

        guard reportingEnabled() else { return }

        if let plausibleURL = region.plausibleAnalyticsServerURL {
            plausibleAnalytics = PlausibleAnalytics(defaultDomainURL: region.OBABaseURL, analyticsServerURL: plausibleURL)
        }

        if let umamiConfig = region.umamiAnalytics {
            umami = UmamiAnalytics(serverURL: umamiConfig.url,
                                  websiteID: umamiConfig.id,
                                  hostname: region.OBABaseURL.host ?? "")
        }
    }
```

- [ ] **Step 5: Forward events to Umami**

In `Apps/Shared/Analytics/AnalyticsOrchestrator.swift`, add an `await umami?...` call inside the existing `Task` blocks.

In `reportEvent` (the `Task` at ~line 80-82):

```swift
        Task {
            await plausibleAnalytics?.reportEvent(pageURL: pageURL, label: label, value: value)
            await umami?.reportEvent(pageURL: pageURL, label: label, value: value)
        }
```

In `reportSearchQuery` (the `Task` at ~line 88-90):

```swift
        Task {
            await plausibleAnalytics?.reportSearchQuery(query)
            await umami?.reportSearchQuery(query)
        }
```

In `reportStopViewed` (the `Task` at ~line 96-98):

```swift
        Task {
            await plausibleAnalytics?.reportStopViewed(name: name, id: id, stopDistance: stopDistance)
            await umami?.reportStopViewed(name: name, id: id, stopDistance: stopDistance)
        }
```

In `setUserProperty` (~line 118-121), add the Umami forward after the Plausible one:

```swift
    @objc public func setUserProperty(key: String, value: String?) {
        firebaseAnalytics?.setUserProperty(key: key, value: value)
        plausibleAnalytics?.setUserProperty(key: key, value: value)
        umami?.setUserProperty(key: key, value: value)
    }
```

- [ ] **Step 6: Tear down Umami on opt-out**

In `Apps/Shared/Analytics/AnalyticsOrchestrator.swift`, update `setReportingEnabled` (~line 106-112) so the `!enabled` branch also nils `umami`:

```swift
    @objc public func setReportingEnabled(_ enabled: Bool) {
        userDefaults.set(enabled, forKey: AnalyticsKeys.reportingEnabledUserDefaultsKey)
        firebaseAnalytics?.setReportingEnabled(enabled)
        if !enabled {
            plausibleAnalytics = nil
            umami = nil
        }
    }
```

- [ ] **Step 7: Build the whole app to confirm everything compiles**

```bash
scripts/generate_project OneBusAway
xcodebuild build -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```
Expected: BUILD SUCCEEDED (proves the protocol change, both call sites, the mock, and the orchestrator all line up).

- [ ] **Step 8: Run the full unit test suite to confirm no regression**

```bash
xcodebuild test -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:OBAKitTests
```
Expected: PASS (includes Task 1 + Task 2 tests and all pre-existing tests).

- [ ] **Step 9: Commit**

```bash
git add OBAKit/Analytics/Analytics.swift Apps/Shared/Analytics/AnalyticsOrchestrator.swift OBAKit/Orchestration/Application.swift OBAKitTests/Helpers/Mocks/AnalyticsMock.swift
git commit -m "Wire Umami into AnalyticsOrchestrator via updateServer(region:) (#1162)"
```

---

### Task 4: Manual device verification

Automated tests cannot prove an event reaches the live Umami dashboard (acceptance criterion #2). This task is a human checklist for Aaron; there is no code.

**Files:** none.

- [ ] **Step 1: Build and run on a simulator or device in a Umami-enabled region**

Run the app in a region whose live region feed includes a non-null `umamiAnalytics` object. Confirm Settings → Privacy → "Send usage data to developer" is ON.

- [ ] **Step 2: Trigger mirrored events**

View a stop (fires `reportStopViewed`) and run a search (fires `reportSearchQuery`).

- [ ] **Step 3: Confirm ingestion in the Umami dashboard**

In the Umami dashboard for the region's website UUID, confirm the events appear. If they don't, capture the `/api/send` response body — a `{"beep":"boop"}` body means the User-Agent was bot-flagged.

- [ ] **Step 4: Confirm the no-op path**

Switch to a region without `umamiAnalytics` (or toggle the privacy switch off), repeat the actions, and confirm **no** request is sent to `/api/send` (e.g. via a proxy/Charles, or absence of new dashboard events).

---

## Notes for the implementer

- **`@testable import OBAKit`** exposes `UmamiAnalytics` and `UmamiJSONValue` even though they're `internal` — keep them `internal`, not `private`/`public`.
- **`OBATestCase`** is the base class for these tests (see `OBAKitTests/Helpers/OBATestCase.swift`); `Fixtures.loadRESTAPIPayload` and `MockDataLoader(testName:)` come from there.
- **Do not** reach for `XCTestExpectation` in the async reporter tests — the methods are `async`, so just `await` them directly in `async` test methods.
- If `xcodebuild` reports "0 tests ran" for a new file, you forgot `scripts/generate_project OneBusAway`.
