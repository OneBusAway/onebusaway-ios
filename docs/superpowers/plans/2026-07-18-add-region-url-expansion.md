# Add-Region Deep Link & Custom Region Form Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the `onebusaway://add-region` deep link and the Add/Edit Custom Region form set a region's Obaco sidecar URL and Umami analytics config (URL + website ID).

**Architecture:** Three new optional query params (`sidecar-url`, `umami-url`, `umami-id`) flow through `URLSchemeRouter` → `AddRegionURLData` → the `Region` custom initializer; the SwiftUI `RegionCustomForm` gains two sections feeding the same initializer. The both-or-nothing Umami rule lives in one place: a failable `UmamiAnalyticsConfig.init?(url:id:)`.

**Tech Stack:** Swift, SwiftUI, XCTest + Nimble. Frameworks: OBAKitCore (models, deep links), OBAKit (UI, app orchestration).

**Spec:** `docs/superpowers/specs/2026-07-18-add-region-url-expansion-design.md`

## Global Constraints

- All three new values are optional; their absence changes nothing about existing behavior.
- Umami is both-or-nothing: config exists only when both a valid URL and a non-blank (whitespace-trimmed) ID are present; partial pairs are silently ignored (`umamiAnalytics = nil`), the region still saves.
- Well-formed-only validation for the new URLs — no network reachability checks. Invalid optional URLs degrade to `nil` (matches `otp-url` posture). Only a bad `oba-url` hard-fails.
- Deep link URLs require an explicit scheme (router's `validateAndCreateURL` semantics); the form assumes `https://` for human-typed input. This split is deliberate.
- Nested URLs in deep links must be percent-encoded; unencoded `&` truncates. Document, don't recover.
- OBAKitCore must remain application-extension safe (no UIKit app APIs).
- New user-facing strings use `OBALoc` with `custom_region_builder_controller.*` keys.
- Do not create new source files — all changes land in existing files, so `scripts/generate_project` regeneration is not required. (If you DO add a file, run `scripts/generate_project OneBusAway` afterward or the test target won't see it.)

## Build & Test Commands

One-time setup (required before any build):

```bash
cd /Users/aaron/repos/onebusaway/ios
scripts/generate_project OneBusAway
```

Per-task test cycle (always `set -o pipefail` if you pipe xcodebuild — a masked build failure leaves stale products that produce confusing test results):

```bash
set -o pipefail
xcodebuild build-for-testing -scheme 'App' -project 'OBAKit.xcodeproj' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' | tail -20
xcodebuild test-without-building -only-testing:OBAKitTests/<TestClass> -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' | tail -30
```

The simulator is **iPhone 17 Pro** (iPhone 16 is not installed on this machine).

---

### Task 1: `UmamiAnalyticsConfig` public inits (memberwise + both-or-nothing failable)

**Files:**
- Modify: `OBAKitCore/Models/Region.swift:538-544` (the `UmamiAnalyticsConfig` struct)
- Test: `OBAKitTests/Modeling/Model Unit Tests/RegionsEncodingTests.swift` (append to class)

**Interfaces:**
- Consumes: nothing new.
- Produces: `public init(url: URL, id: String)` and `public init?(url: URL?, id: String?)` on `UmamiAnalyticsConfig`. The failable init is the single source of truth for the both-or-nothing rule; Tasks 3, 4, and 5 all call it. Trimming uses the existing `String.strip()` from `OBAKitCore/Extensions/FoundationExtensions.swift:288`.

- [ ] **Step 1: Write the failing tests**

Append inside the `RegionsEncodingTests` class in `OBAKitTests/Modeling/Model Unit Tests/RegionsEncodingTests.swift`:

```swift
    // MARK: - UmamiAnalyticsConfig inits

    func testUmamiConfig_memberwiseInit() {
        let config = UmamiAnalyticsConfig(url: URL(string: "https://analytics.example.com")!, id: "site-123")
        expect(config.url.absoluteString) == "https://analytics.example.com"
        expect(config.id) == "site-123"
    }

    func testUmamiConfig_failableInit_bothPresent() {
        let config = UmamiAnalyticsConfig(url: URL(string: "https://analytics.example.com"), id: "site-123")
        expect(config?.id) == "site-123"
    }

    func testUmamiConfig_failableInit_trimsID() {
        let config = UmamiAnalyticsConfig(url: URL(string: "https://analytics.example.com"), id: "  site-123 \n")
        expect(config?.id) == "site-123"
    }

    func testUmamiConfig_failableInit_partialPairsCollapseToNil() {
        expect(UmamiAnalyticsConfig(url: nil, id: "site-123")).to(beNil())
        expect(UmamiAnalyticsConfig(url: URL(string: "https://analytics.example.com"), id: nil)).to(beNil())
        expect(UmamiAnalyticsConfig(url: URL(string: "https://analytics.example.com"), id: "")).to(beNil())
        expect(UmamiAnalyticsConfig(url: URL(string: "https://analytics.example.com"), id: "   ")).to(beNil())
        expect(UmamiAnalyticsConfig(url: nil, id: nil)).to(beNil())
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run (after build-for-testing; see Build & Test Commands):
`xcodebuild build-for-testing …` — Expected: **build FAILS** with "extra argument" / "no exact matches in call to initializer" because `init?(url: URL?, id: String?)` does not exist. (A compile failure is the red state here.)

- [ ] **Step 3: Implement the inits**

In `OBAKitCore/Models/Region.swift`, replace the `UmamiAnalyticsConfig` struct body (lines 538-544) with:

```swift
public struct UmamiAnalyticsConfig: Codable, Equatable, Hashable {
    /// The Umami host to POST events to, e.g. `https://analytics.onebusawaycloud.com`.
    public let url: URL

    /// The Umami website UUID that events are keyed/routed by.
    public let id: String

    public init(url: URL, id: String) {
        self.url = url
        self.id = id
    }

    /// The single source of truth for the both-or-nothing rule: a config exists
    /// only when both a URL and a non-blank website ID are present. Partial
    /// pairs collapse to `nil`, which means "analytics disabled."
    public init?(url: URL?, id: String?) {
        guard let url, let id = id?.strip(), !id.isEmpty else {
            return nil
        }
        self.init(url: url, id: id)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
set -o pipefail
xcodebuild build-for-testing -scheme 'App' -project 'OBAKit.xcodeproj' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' | tail -20
xcodebuild test-without-building -only-testing:OBAKitTests/RegionsEncodingTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' | tail -30
```

Expected: all `RegionsEncodingTests` PASS (new + pre-existing).

- [ ] **Step 5: Commit**

```bash
git add OBAKitCore/Models/Region.swift "OBAKitTests/Modeling/Model Unit Tests/RegionsEncodingTests.swift"
git commit -m "Add public memberwise and both-or-nothing failable inits to UmamiAnalyticsConfig"
```

---

### Task 2: `Region` custom initializer accepts sidecar + umami; Codable round-trip proof

**Files:**
- Modify: `OBAKitCore/Models/Region.swift:210-248` (the custom-region `init`)
- Modify: `OBAKitTests/Helpers/Fixtures.swift:71-75` (add fixture next to `customMinneapolisRegion`)
- Test: `OBAKitTests/Modeling/Model Unit Tests/RegionsEncodingTests.swift`

**Interfaces:**
- Consumes: `UmamiAnalyticsConfig.init(url:id:)` from Task 1.
- Produces: `Region.init(name:OBABaseURL:coordinateRegion:contactEmail:regionIdentifier:openTripPlannerURL:sidecarBaseURL:umamiAnalytics:)` — the last two parameters are new, both defaulted to `nil` (source-compatible with the two existing call sites: `Application.swift:603` and `Fixtures.swift:74`). Also `Fixtures.customRegionWithSidecarAndUmami` for later tests.

- [ ] **Step 1: Write the failing test and fixture**

In `OBAKitTests/Helpers/Fixtures.swift`, directly below the `customMinneapolisRegion` class var (after line 75), add:

```swift
    class var customRegionWithSidecarAndUmami: Region {
        let coordinateRegion = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 44.9778, longitude: -93.2650), latitudinalMeters: 1000.0, longitudinalMeters: 1000.0)

        return Region(
            name: "Custom Region",
            OBABaseURL: URL(string: "http://www.example.com")!,
            coordinateRegion: coordinateRegion,
            contactEmail: "contact@example.com",
            sidecarBaseURL: URL(string: "https://obaco.example.com")!,
            umamiAnalytics: UmamiAnalyticsConfig(url: URL(string: "https://analytics.example.com")!, id: "site-uuid-123"))
    }
```

Append inside `RegionsEncodingTests`:

```swift
    func testCustomRegions_creation_withSidecarAndUmami() {
        let region = Fixtures.customRegionWithSidecarAndUmami
        expect(region.sidecarBaseURL?.absoluteString) == "https://obaco.example.com"
        expect(region.umamiAnalytics?.url.absoluteString) == "https://analytics.example.com"
        expect(region.umamiAnalytics?.id) == "site-uuid-123"
    }

    func testCustomRegions_roundtripping_withSidecarAndUmami() {
        let plistData = try! PropertyListEncoder().encode([Fixtures.customRegionWithSidecarAndUmami])
        let rt = try! PropertyListDecoder().decode([Region].self, from: plistData)[0]

        expect(rt.sidecarBaseURL?.absoluteString) == "https://obaco.example.com"
        expect(rt.umamiAnalytics?.url.absoluteString) == "https://analytics.example.com"
        expect(rt.umamiAnalytics?.id) == "site-uuid-123"
        expect(rt.isCustom) == true
    }
```

- [ ] **Step 2: Run to verify failure**

Build-for-testing. Expected: **build FAILS** — "extra arguments at positions … in call" (the initializer has no `sidecarBaseURL`/`umamiAnalytics` parameters yet).

- [ ] **Step 3: Add the initializer parameters**

In `OBAKitCore/Models/Region.swift`, change the custom-region initializer. The signature (line 210) becomes:

```swift
    public required init(name: String, OBABaseURL: URL, coordinateRegion: MKCoordinateRegion, contactEmail: String, regionIdentifier: Int? = nil, openTripPlannerURL: URL? = nil, sidecarBaseURL: URL? = nil, umamiAnalytics: UmamiAnalyticsConfig? = nil) {
```

In the body, replace the hardcoded nils:
- Line 218: `self.sidecarBaseURL = nil` → `self.sidecarBaseURL = sidecarBaseURL`
- Line 238 (inside the "Uninitialized properties" block): `umamiAnalytics = nil` → `self.umamiAnalytics = umamiAnalytics`

Also extend the doc comment above the init with:

```swift
    /// - Parameter sidecarBaseURL: Optional base URL for the Obaco sidecar server.
    /// - Parameter umamiAnalytics: Optional Umami analytics configuration.
```

- [ ] **Step 4: Run tests to verify they pass**

Build-for-testing, then run `-only-testing:OBAKitTests/RegionsEncodingTests`. Expected: PASS, including the pre-existing `testCustomRegions_roundtripping` (nil fields still round-trip).

- [ ] **Step 5: Commit**

```bash
git add OBAKitCore/Models/Region.swift OBAKitTests/Helpers/Fixtures.swift "OBAKitTests/Modeling/Model Unit Tests/RegionsEncodingTests.swift"
git commit -m "Allow custom regions to carry sidecarBaseURL and umamiAnalytics"
```

---

### Task 3: `URLSchemeRouter` parses `sidecar-url`, `umami-url`, `umami-id`

**Files:**
- Modify: `OBAKitCore/DeepLinks/URLSchemeRouter.swift` (`AddRegionURLData` struct at lines 27-31; `decodeAddRegion` at lines 108-122; doc comment at lines 18-26)
- Test: `OBAKitTests/Modeling/DeepLinks/URLSchemeRouterTests.swift`

**Interfaces:**
- Consumes: `UmamiAnalyticsConfig.init?(url:id:)` from Task 1; existing `validateAndCreateURL(from:)` (`URLSchemeRouter.swift:125`); `String.strip()`.
- Produces: `AddRegionURLData` gains `public let sidecarURL: URL?`, `public let umamiURL: URL?`, `public let umamiID: String?`, and `public var umamiAnalytics: UmamiAnalyticsConfig? { get }`. Task 4 consumes `sidecarURL` and `umamiAnalytics` (never raw `umamiID` — a dangling ID with an invalid URL must not read as "enabled").

- [ ] **Step 1: Write the failing tests**

Append inside the `URLSchemeRouterTests` class in `OBAKitTests/Modeling/DeepLinks/URLSchemeRouterTests.swift`:

```swift
    // MARK: - Sidecar & Umami Parameters

    private func decodeAddRegion(_ queryItems: [URLQueryItem]) -> AddRegionURLData? {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = queryItems
        guard let url = components.url, case .addRegion(let data)? = router.decodeURLType(from: url) else {
            fail("Expected addRegion URLType")
            return nil
        }
        return data
    }

    func test_decodeURLType_addRegion_decodesAllNewParameters() {
        let data = decodeAddRegion([
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com"),
            URLQueryItem(name: "sidecar-url", value: "https://obaco.example.com"),
            URLQueryItem(name: "umami-url", value: "https://analytics.example.com"),
            URLQueryItem(name: "umami-id", value: "site-uuid-123")
        ])

        expect(data?.sidecarURL?.absoluteString) == "https://obaco.example.com"
        expect(data?.umamiURL?.absoluteString) == "https://analytics.example.com"
        expect(data?.umamiID) == "site-uuid-123"
        expect(data?.umamiAnalytics?.url.absoluteString) == "https://analytics.example.com"
        expect(data?.umamiAnalytics?.id) == "site-uuid-123"
    }

    func test_decodeURLType_addRegion_newParametersDefaultToNil() {
        let data = decodeAddRegion([
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com")
        ])

        expect(data?.sidecarURL).to(beNil())
        expect(data?.umamiURL).to(beNil())
        expect(data?.umamiID).to(beNil())
        expect(data?.umamiAnalytics).to(beNil())
    }

    func test_decodeURLType_addRegion_partialUmamiPairCollapsesToNilConfig() {
        // URL without ID.
        let urlOnly = decodeAddRegion([
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com"),
            URLQueryItem(name: "umami-url", value: "https://analytics.example.com")
        ])
        expect(urlOnly?.umamiURL).toNot(beNil())
        expect(urlOnly?.umamiAnalytics).to(beNil())

        // ID without URL — the region still decodes; the dangling ID never becomes a config.
        let idOnly = decodeAddRegion([
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com"),
            URLQueryItem(name: "umami-id", value: "site-uuid-123")
        ])
        expect(idOnly?.umamiID) == "site-uuid-123"
        expect(idOnly?.umamiAnalytics).to(beNil())

        // Invalid umami URL + valid ID — dangling ID, nil config.
        let invalidURL = decodeAddRegion([
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com"),
            URLQueryItem(name: "umami-url", value: "not a valid url"),
            URLQueryItem(name: "umami-id", value: "site-uuid-123")
        ])
        expect(invalidURL?.umamiURL).to(beNil())
        expect(invalidURL?.umamiAnalytics).to(beNil())
    }

    func test_decodeURLType_addRegion_blankUmamiIDBecomesNil() {
        let data = decodeAddRegion([
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com"),
            URLQueryItem(name: "umami-url", value: "https://analytics.example.com"),
            URLQueryItem(name: "umami-id", value: "   ")
        ])
        expect(data?.umamiID).to(beNil())
        expect(data?.umamiAnalytics).to(beNil())
    }

    func test_decodeURLType_addRegion_invalidSidecarURLDegradesToNil() {
        let data = decodeAddRegion([
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com"),
            URLQueryItem(name: "sidecar-url", value: "not a valid url")
        ])
        expect(data).toNot(beNil())
        expect(data?.sidecarURL).to(beNil())
    }

    // MARK: - Raw-String Decoding (percent-encoding behavior)

    // The queryItems-based tests above auto-encode values on the way out, so they
    // can never exercise encoding bugs. These two lock in the documented contract:
    // nested URLs MUST be percent-encoded; an unencoded `&` truncates.

    func test_decodeURLType_addRegion_rawString_percentEncodedNestedURL() {
        let url = URL(string: "onebusaway://add-region?name=Raw%20Region&oba-url=https%3A%2F%2Foba.example.com&sidecar-url=https%3A%2F%2Fobaco.example.com%2Fapi%3Fa%3D1%26b%3D2&umami-url=https%3A%2F%2Fanalytics.example.com&umami-id=site-uuid-123")!

        guard case .addRegion(let data)? = router.decodeURLType(from: url) else {
            fail("Expected addRegion URLType")
            return
        }

        expect(data?.name) == "Raw Region"
        expect(data?.obaURL.absoluteString) == "https://oba.example.com"
        expect(data?.sidecarURL?.absoluteString) == "https://obaco.example.com/api?a=1&b=2"
        expect(data?.umamiAnalytics?.id) == "site-uuid-123"
    }

    func test_decodeURLType_addRegion_rawString_unencodedAmpersandTruncates() {
        let url = URL(string: "onebusaway://add-region?name=Raw&oba-url=https://oba.example.com&sidecar-url=https://obaco.example.com/api?a=1&b=2")!

        guard case .addRegion(let data)? = router.decodeURLType(from: url) else {
            fail("Expected addRegion URLType")
            return
        }

        // The unencoded `&` ends the sidecar-url value; `b=2` parses as a separate
        // (ignored) query item. This is documented behavior, not a bug.
        expect(data?.sidecarURL?.absoluteString) == "https://obaco.example.com/api?a=1"
    }
```

- [ ] **Step 2: Run to verify failure**

Build-for-testing. Expected: **build FAILS** — `AddRegionURLData` has no member `sidecarURL` / `umamiURL` / `umamiID` / `umamiAnalytics`.

- [ ] **Step 3: Implement parsing**

In `OBAKitCore/DeepLinks/URLSchemeRouter.swift`, replace the `AddRegionURLData` struct (lines 18-31 including doc comment) with:

```swift
/// `AddRegionURLData` is a data structure that encapsulates the information needed to add a new region
/// through a deep link. All URL values must be percent-encoded inside the deep link; an unencoded `&`
/// inside a nested URL ends that value.
///
/// - Parameters:
///   - name: The name of the region to be added. This is a human-readable string that identifies the region.
///   - obaURL: The URL to the OneBusAway (OBA) server for the region. This URL is used to access transit data.
///   - otpURL: An optional URL to the OpenTripPlanner (OTP) server, used for trip planning.
///   - sidecarURL: An optional base URL for the Obaco sidecar server.
///   - umamiURL: An optional Umami analytics server URL. Never read this directly to decide whether
///               analytics is enabled — use `umamiAnalytics`.
///   - umamiID: An optional Umami website ID. Like `umamiURL`, this can dangle (e.g. an ID with an
///              invalid URL); use `umamiAnalytics`.
public struct AddRegionURLData {
    public let name: String
    public let obaURL: URL
    public let otpURL: URL?
    public let sidecarURL: URL?
    public let umamiURL: URL?
    public let umamiID: String?

    /// The both-or-nothing Umami config: non-nil only when both `umamiURL` and a
    /// non-blank `umamiID` are present. Consumers must use this, not the raw fields.
    public var umamiAnalytics: UmamiAnalyticsConfig? {
        UmamiAnalyticsConfig(url: umamiURL, id: umamiID)
    }
}
```

Replace `decodeAddRegion` (lines 108-122) with:

```swift
    /// Decodes an `AddRegionURLData` from `add-region` URL components. `name` and a valid
    /// `oba-url` are required; `otp-url`, `sidecar-url`, `umami-url`, and `umami-id` are
    /// optional, and invalid optional values degrade to `nil`.
    private func decodeAddRegion(from components: URLComponents) -> URLType? {
        guard
            let name = components.queryItem(named: "name")?.value,
            let obaUrlString = components.queryItem(named: "oba-url")?.value,
            let obaURL = validateAndCreateURL(from: obaUrlString) else {
            return .addRegion(nil)
        }

        var umamiID: String?
        if let rawUmamiID = components.queryItem(named: "umami-id")?.value {
            let trimmed = rawUmamiID.strip()
            umamiID = trimmed.isEmpty ? nil : trimmed
        }

        return .addRegion(AddRegionURLData(
            name: name,
            obaURL: obaURL,
            otpURL: optionalURL(named: "otp-url", in: components),
            sidecarURL: optionalURL(named: "sidecar-url", in: components),
            umamiURL: optionalURL(named: "umami-url", in: components),
            umamiID: umamiID))
    }

    /// Extracts and validates an optional URL query item; missing or invalid values become `nil`.
    private func optionalURL(named name: String, in components: URLComponents) -> URL? {
        guard let string = components.queryItem(named: name)?.value else {
            return nil
        }
        return validateAndCreateURL(from: string)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Build-for-testing, then run `-only-testing:OBAKitTests/URLSchemeRouterTests`. Expected: all PASS, including every pre-existing test (backward compat: `test_decodeURLType_addRegion_decodesValidURLWithOTPURL` etc.).

- [ ] **Step 5: Commit**

```bash
git add OBAKitCore/DeepLinks/URLSchemeRouter.swift OBAKitTests/Modeling/DeepLinks/URLSchemeRouterTests.swift
git commit -m "Parse sidecar-url, umami-url, and umami-id in add-region deep links"
```

---

### Task 4: Deep link handler passes the new values into `Region`

**Files:**
- Modify: `OBAKit/Orchestration/Application.swift:603` (the `Region` construction in the `.addRegion` case)
- Test: existing `OBAKitTests/Application/ApplicationTests.swift` (no new tests — the rule logic was tested at the `AddRegionURLData` layer in Task 3; this task is pure plumbing)

**Interfaces:**
- Consumes: `AddRegionURLData.sidecarURL` and `.umamiAnalytics` (Task 3); `Region` init params (Task 2).
- Produces: nothing new for later tasks.

- [ ] **Step 1: Update the Region construction**

In `OBAKit/Orchestration/Application.swift`, replace line 603:

```swift
                    // Construct Region from URL data
                    let currentRegion = Region(name: regionData.name, OBABaseURL: regionData.obaURL, coordinateRegion: adjustedRegionCoordinate, contactEmail: "example@example.com", openTripPlannerURL: regionData.otpURL)
```

with:

```swift
                    // Construct Region from URL data. umamiAnalytics applies the
                    // both-or-nothing rule; no rule logic lives here.
                    let currentRegion = Region(
                        name: regionData.name,
                        OBABaseURL: regionData.obaURL,
                        coordinateRegion: adjustedRegionCoordinate,
                        contactEmail: "example@example.com",
                        openTripPlannerURL: regionData.otpURL,
                        sidecarBaseURL: regionData.sidecarURL,
                        umamiAnalytics: regionData.umamiAnalytics)
```

- [ ] **Step 2: Build and run the Application tests**

```bash
set -o pipefail
xcodebuild build-for-testing -scheme 'App' -project 'OBAKit.xcodeproj' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' | tail -20
xcodebuild test-without-building -only-testing:OBAKitTests/ApplicationTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' | tail -30
```

Expected: build succeeds, `ApplicationTests` PASS.

- [ ] **Step 3: Commit**

```bash
git add OBAKit/Orchestration/Application.swift
git commit -m "Wire sidecar and umami deep link values into region creation"
```

---

### Task 5: `RegionCustomForm` — Sidecar Server and Analytics sections

**Files:**
- Modify: `OBAKit/Onboarding/RegionPicker/RegionCustomForm.swift`
- Test: `OBAKitTests/Onboarding/RegionCustomFormTests.swift`

**Interfaces:**
- Consumes: `Region` init params (Task 2); `UmamiAnalyticsConfig.init?(url:id:)` (Task 1).
- Produces: `static func normalizeURL(_ string: String) -> URL?` on `RegionCustomForm` (general URL normalization: trim, assume `https://`, strip trailing slashes, require http(s) + host). `normalizeBaseURL` becomes a wrapper that additionally strips `/api/where`.

- [ ] **Step 1: Write the failing `normalizeURL` tests**

Append inside `RegionCustomFormTests` in `OBAKitTests/Onboarding/RegionCustomFormTests.swift`:

```swift
    // MARK: - normalizeURL (general, no /api/where handling)

    private func normalizeGeneral(_ string: String) -> String? {
        RegionCustomForm.normalizeURL(string)?.absoluteString
    }

    func test_normalizeURL_prependsHTTPS() {
        expect(self.normalizeGeneral("obaco.example.com")) == "https://obaco.example.com"
    }

    func test_normalizeURL_preservesExplicitScheme() {
        expect(self.normalizeGeneral("http://example.com")) == "http://example.com"
    }

    func test_normalizeURL_stripsWhitespaceAndTrailingSlashes() {
        expect(self.normalizeGeneral("  analytics.example.com/ \n")) == "https://analytics.example.com"
    }

    /// Unlike the Base URL field, general URLs keep an `/api/where` path verbatim.
    func test_normalizeURL_doesNotStripAPIWhere() {
        expect(self.normalizeGeneral("example.com/api/where")) == "https://example.com/api/where"
    }

    func test_normalizeURL_rejectsInvalidInput() {
        expect(self.normalizeGeneral("")).to(beNil())
        expect(self.normalizeGeneral("   ")).to(beNil())
        expect(self.normalizeGeneral("ftp://example.com")).to(beNil())
        expect(self.normalizeGeneral("https://")).to(beNil())
    }
```

- [ ] **Step 2: Run to verify failure**

Build-for-testing. Expected: **build FAILS** — `RegionCustomForm` has no member `normalizeURL`.

- [ ] **Step 3: Implement `normalizeURL` and the form changes**

In `OBAKit/Onboarding/RegionPicker/RegionCustomForm.swift`:

**(a)** Replace `normalizeBaseURL` (lines 35-67, keeping its doc comment) with the pair:

```swift
    /// Normalizes user input into a base URL: trims whitespace, assumes
    /// `https://` when no scheme was typed, and strips a trailing `/api/where`
    /// (the field's help text promises that part is added automatically, so
    /// pasting a full API URL must not double it). Static and pure for
    /// testability.
    static func normalizeBaseURL(_ string: String) -> URL? {
        guard let url = normalizeURL(string) else {
            return nil
        }

        var urlString = url.absoluteString
        if urlString.lowercased().hasSuffix("/api/where") {
            urlString = String(urlString.dropLast("/api/where".count))
            while urlString.hasSuffix("/") {
                urlString = String(urlString.dropLast())
            }
        }
        return URL(string: urlString)
    }

    /// General URL normalization for human-typed input: trims whitespace,
    /// assumes `https://` when no scheme was typed, strips trailing slashes,
    /// and requires an http(s) scheme and a host. Static and pure for
    /// testability.
    static func normalizeURL(_ string: String) -> URL? {
        var urlString = string.strip()
        guard !urlString.isEmpty else {
            return nil
        }

        if !urlString.contains("://") {
            urlString = "https://" + urlString
        }

        while urlString.hasSuffix("/") {
            urlString = String(urlString.dropLast())
        }

        guard
            let url = URL(string: urlString),
            let scheme = url.scheme,
            scheme == "http" || scheme == "https",
            url.host() != nil
        else {
            return nil
        }

        return url
    }
```

**(b)** Add three `@State` fields below `baseURLString` (line 26):

```swift
    @State private var sidecarURLString: String = ""
    @State private var umamiURLString: String = ""
    @State private var umamiIDString: String = ""
```

**(c)** Add computed normalizers below `normalizedBaseURL` (lines 30-33):

```swift
    /// The Sidecar URL field, normalized. Empty or invalid input degrades to `nil`.
    var normalizedSidecarURL: URL? {
        Self.normalizeURL(sidecarURLString)
    }

    /// The Umami analytics URL field, normalized. Empty or invalid input degrades to `nil`.
    var normalizedUmamiURL: URL? {
        Self.normalizeURL(umamiURLString)
    }
```

**(d)** In `body`, insert two new sections between the Service Area section's closing brace (line 122) and the `if editingRegion != nil` block (line 124):

```swift
            Section {
                TextField("onebusaway.co", text: $sidecarURLString)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text(OBALoc("custom_region_builder_controller.sidecar_section.header_title", value: "Sidecar Server", comment: "Title of the Sidecar Server header."))
            } footer: {
                Text(OBALoc("custom_region_builder_controller.sidecar_section.explanation", value: "Optional. The address of an Obaco (OneBusAway.co) sidecar server, which powers features like alarms and surveys. \"https://\" is assumed.", comment: "An explanation of the optional Obaco sidecar server URL field of a custom region."))
            }

            Section {
                TextField("analytics.example.com", text: $umamiURLString)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField(OBALoc("custom_region_builder_controller.analytics_section.website_id_placeholder", value: "Website ID", comment: "Placeholder for the Umami analytics website ID field."), text: $umamiIDString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text(OBALoc("custom_region_builder_controller.analytics_section.header_title", value: "Analytics", comment: "Title of the Analytics header."))
            } footer: {
                Text(OBALoc("custom_region_builder_controller.analytics_section.explanation", value: "Optional. The address of an Umami analytics server and this region's website ID. Both fields are required to enable analytics; leave them blank to disable it.", comment: "An explanation of the optional Umami analytics fields of a custom region."))
            }
```

Note the website ID field: autocapitalization and autocorrection off (it's a UUID), but **no** URL content type or keyboard.

**(e)** In `setInitialValues()` (line 162), populate the new fields inside the `if let editingRegion` branch, after `serviceArea = editingRegion.serviceRect`:

```swift
            if let sidecarBaseURL = editingRegion.sidecarBaseURL {
                sidecarURLString = displayString(for: sidecarBaseURL)
            }
            if let umamiAnalytics = editingRegion.umamiAnalytics {
                umamiURLString = displayString(for: umamiAnalytics.url)
                umamiIDString = umamiAnalytics.id
            }
```

**(f)** In `doSave()` (line 232), replace the `Region` construction:

```swift
        let region = Region(
            name: name,
            OBABaseURL: baseURL,
            coordinateRegion: MKCoordinateRegion(serviceArea),
            contactEmail: editingRegion?.contactEmail ?? Self.placeholderContactEmail,
            regionIdentifier: editingRegion?.regionIdentifier
        )
```

with:

```swift
        // openTripPlannerURL isn't editable in this form, so editing must carry
        // the existing value forward rather than silently dropping it.
        let region = Region(
            name: name,
            OBABaseURL: baseURL,
            coordinateRegion: MKCoordinateRegion(serviceArea),
            contactEmail: editingRegion?.contactEmail ?? Self.placeholderContactEmail,
            regionIdentifier: editingRegion?.regionIdentifier,
            openTripPlannerURL: editingRegion?.openTripPlannerURL,
            sidecarBaseURL: normalizedSidecarURL,
            umamiAnalytics: UmamiAnalyticsConfig(url: normalizedUmamiURL, id: umamiIDString)
        )
```

(`UmamiAnalyticsConfig(url:id:)` here resolves to the failable init from Task 1 — `normalizedUmamiURL` is `URL?` — so the both-or-nothing rule is applied without any form-local logic. The `openTripPlannerURL` line also fixes a pre-existing drop-on-edit bug for OTP URLs set via deep link.)

- [ ] **Step 4: Run tests to verify they pass**

Build-for-testing, then run `-only-testing:OBAKitTests/RegionCustomFormTests`. Expected: all PASS — new `normalizeURL` tests and all pre-existing `normalizeBaseURL` tests (the wrapper must preserve exact behavior, including `/API/WHERE` case-insensitivity and trailing-slash handling).

- [ ] **Step 5: Run the full OBAKitTests suite**

```bash
set -o pipefail
xcodebuild test-without-building -only-testing:OBAKitTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' | tail -30
```

Expected: PASS (this is the integration checkpoint before docs).

- [ ] **Step 6: Commit**

```bash
git add OBAKit/Onboarding/RegionPicker/RegionCustomForm.swift OBAKitTests/Onboarding/RegionCustomFormTests.swift
git commit -m "Add Sidecar Server and Analytics sections to the custom region form"
```

---

### Task 6: Documentation

**Files:**
- Modify: `CLAUDE.md` (Deep Linking section)

**Interfaces:** none.

(The spec also mentions the README, but `README.md` contains no deep-linking
section — verified via grep — so CLAUDE.md is the only doc to update.)

- [ ] **Step 1: Update the deep-linking docs**

In `CLAUDE.md`, replace:

````markdown
## Deep Linking

Custom region addition:
```
onebusaway://add-region?name=REGION_NAME&oba-url=ENCODED_SERVER_URL
```
````

with:

````markdown
## Deep Linking

Custom region addition:
```
onebusaway://add-region?name=REGION_NAME&oba-url=ENCODED_SERVER_URL
    [&otp-url=ENCODED_OTP_URL]
    [&sidecar-url=ENCODED_OBACO_URL]
    [&umami-url=ENCODED_UMAMI_URL&umami-id=UMAMI_WEBSITE_ID]
```

All URL parameter values must be percent-encoded (an unencoded `&` inside a
nested URL truncates it). `umami-url` and `umami-id` are both-or-nothing:
analytics is configured only when both are present and valid.
````

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "Document expanded add-region deep link parameters"
```
