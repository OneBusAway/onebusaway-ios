# Synthesized Rental Deep Links Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a rental feed publishes no GBFS `rental_uris`, synthesize an operator deep link from the vehicle ID so the rental sheet's "Open in Lime" button finally works.

**Architecture:** One new pure-Swift type, `RentalDeepLink`, in OBAKit. It holds a static table of known operators keyed by GBFS network prefix, and resolves a `VehicleRental` to a `Target` (URL + App Store fallback + operator name). `RentalDetailView.deepLinkURL` becomes a thin call into it. No OTPKit changes.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing (`@Test`/`@Suite`), OTPKit models, xcodegen.

## Global Constraints

- **Build URLs with `URLComponents` + `URLQueryItem`, never `String(format:)`.** `.urlQueryAllowed` does not escape `&`, `=`, `?`, `/`, or `+` inside a query *value*. This is the spec's central correctness requirement.
- **Never emit `%d` via `String(format:)` for the timestamp** — 32-bit specifier. Use `String(Int(now.timeIntervalSince1970))`.
- **No new localized strings.** Reuse `rental_detail.open_in_fmt` ("Open in %@").
- **No OTPKit changes.** No `canOpenURL`, no `LSApplicationQueriesSchemes` entry.
- Copyright header on every new file, matching sibling files verbatim (see Task 1 Step 3).
- Tests are Swift Testing (`import Testing`, `@Test`, `@Suite`), not XCTest.
- SwiftLint must pass: `scripts/swiftlint.sh`.
- Branch is `rental-deep-links`, already created off `origin/main` with the spec committed.

**Known operator values** (do not re-derive):

| Operator | Scheme | Vehicle host | Query key | App Store ID |
| --- | --- | --- | --- | --- |
| `lime` | `limebike` | `map` | `selected_vehicle_id` | `1199780189` |
| `bird` | `bird` | *(none — cannot target)* | *(none)* | `1260842311` |

**Build/test commands** (run from `/Users/aaron/repos/onebusaway/ios-bikeshare`):

```bash
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild test-without-building -only-testing:OBAKitTests/RentalDeepLinkTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

`scripts/generate_project` is only needed after adding a NEW file (Task 1 and Task 2 add files; Tasks 3–5 do not).

---

## File Structure

| File | Responsibility |
| --- | --- |
| `OBAKit/Mapping/Layers/RentalDeepLink.swift` *(new)* | Operator table + resolution. Pure Swift: no UIKit, no MapKit, no async. Sibling of `RentalFormat.swift`, same shape. |
| `OBAKitTests/Mapping/RentalDeepLinkTests.swift` *(new)* | Full behavioral coverage of the above. |
| `OBAKitTests/Mapping/RentalFixtures.swift` *(modify)* | Gains `networkId`, `networkURL`, `rentalUris` parameters. |
| `OBAKit/Mapping/Layers/RentalDetailViewController.swift` *(modify)* | `deepLinkURL` collapses to a `RentalDeepLink` call. |
| `OBAKit/Analytics/Analytics.swift` *(modify)* | Two new labels. |
| `OBAKit/Mapping/MapViewController+MapLayers.swift` *(modify)* | Report those labels; correct a now-false comment. |

---

## Task 1: Fixture parameters

Widen `RentalFixtures` first, because every later test depends on it.

**Files:**
- Modify: `OBAKitTests/Mapping/RentalFixtures.swift:27-63` (`vehicle`) and `:71-92` (`station`)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `RentalFixtures.vehicle(id:formFactor:propulsion:rangeMeters:batteryPercent:operative:lat:lon:networkId:networkURL:rentalUris:) throws -> VehicleRental`
  - `RentalFixtures.station(id:vehiclesAvailable:operative:lat:lon:networkId:) throws -> VehicleRental`
  - New params are all trailing with defaults matching today's hardcoded values, so existing call sites compile unchanged.
  - `networkId: String?` — `nil` produces a vehicle with **no** `rentalNetwork` at all.
  - `rentalUris: [String: String]?` — `nil` (default) produces `NSNull()`; a dictionary like `["ios": "..."]` produces a populated object.

- [ ] **Step 1: Add the parameters to `vehicle(...)`**

Replace the signature and the `rentalNetwork`/`rentalUris` entries in the dictionary. The full method becomes:

```swift
    /// A free-floating rental vehicle. Pass `rangeMeters: nil, batteryPercent: nil`
    /// for a vehicle whose feed publishes no fuel data at all.
    ///
    /// `networkId: nil` omits `rentalNetwork` entirely — the shape a feed takes
    /// when it publishes no network block, which deep-link resolution must survive.
    static func vehicle(
        id: String = "v1",
        formFactor: String = "SCOOTER",
        propulsion: String? = "ELECTRIC",
        rangeMeters: Int? = nil,
        batteryPercent: Double? = nil,
        operative: Bool = true,
        lat: Double = 47.6,
        lon: Double = -122.3,
        networkId: String? = "lime_seattle",
        networkURL: String? = nil,
        rentalUris: [String: String]? = nil
    ) throws -> VehicleRental {
        var fuel: [String: Any] = [:]
        if let batteryPercent { fuel["percent"] = batteryPercent }
        if let rangeMeters { fuel["range"] = rangeMeters }
        let fuelValue: Any = fuel.isEmpty ? NSNull() : fuel

        var vehicleType: [String: Any] = ["formFactor": formFactor]
        if let propulsion {
            vehicleType["propulsionType"] = propulsion
        } else {
            vehicleType["propulsionType"] = NSNull()
        }

        var dictionary: [String: Any] = [
            "__typename": "RentalVehicle",
            "vehicleId": id,
            "name": "Default vehicle type",
            "lat": lat,
            "lon": lon,
            "allowPickupNow": true,
            "operative": operative,
            "rentalUris": rentalUris ?? NSNull(),
            "vehicleType": vehicleType,
            "fuel": fuelValue
        ]

        // Conditional insertion, not a NSNull() value: `networkId: nil` must
        // produce a payload with the key absent, which is the shape a feed takes
        // when it publishes no network block.
        if let networkId {
            dictionary["rentalNetwork"] = ["networkId": networkId, "url": networkURL ?? NSNull()] as [String: Any]
        }

        return try Fixtures.dictionaryToModel(type: VehicleRental.self, dictionary: dictionary)
    }
```

- [ ] **Step 2: Add `networkId` to `station(...)`**

Append the parameter and set the key. The signature gains `networkId: String? = "lime_seattle"` after `lon`, and immediately before `return try Fixtures.dictionaryToModel(...)` insert:

```swift
        if let networkId {
            dictionary["rentalNetwork"] = ["networkId": networkId, "url": NSNull()] as [String: Any]
        }
```

- [ ] **Step 3: Verify existing tests still pass**

```bash
cd /Users/aaron/repos/onebusaway/ios-bikeshare
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild test-without-building -only-testing:OBAKitTests/RentalVisibilityTests -only-testing:OBAKitTests/RentalAnnotationViewTests -only-testing:OBAKitTests/RentalLayerCoordinatorTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: PASS. Defaults reproduce the old dictionaries exactly, so nothing should change.

- [ ] **Step 4: Commit**

```bash
git add OBAKitTests/Mapping/RentalFixtures.swift
git commit -m "Let rental fixtures vary network id, network url, and rental uris"
```

---

## Task 2: `RentalDeepLink` resolution

The whole feature. TDD: tests first, all failing, then one implementation.

**Files:**
- Create: `OBAKit/Mapping/Layers/RentalDeepLink.swift`
- Create: `OBAKitTests/Mapping/RentalDeepLinkTests.swift`

**Interfaces:**
- Consumes: `RentalFixtures` from Task 1.
- Produces:
  - `RentalDeepLink.Target` — `struct Target: Equatable { let url: URL; let storeFallback: URL?; let operatorName: String? }`, internal.
  - `RentalDeepLink.target(for rental: VehicleRental, now: Date = Date()) -> Target?`
  - Task 3 calls exactly this.

- [ ] **Step 1: Write the failing tests**

Create `OBAKitTests/Mapping/RentalDeepLinkTests.swift`:

```swift
//
//  RentalDeepLinkTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import OTPKit
@testable import OBAKit

/// `RentalDeepLink` answers "where should the Open in <operator> button go?"
///
/// The interesting cases are all absences: no feed publishes GBFS `rental_uris`,
/// so synthesis from the vehicle ID is the live path, and the feed-provided
/// branches exist only to avoid regressing a feed that someday starts sending them.
@Suite
struct RentalDeepLinkTests {

    /// Fixed so `generated_at` renders deterministically.
    private let now = Date(timeIntervalSince1970: 1_785_462_137)
    private let timestamp = "1785462137"

    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.reduce(into: [:]) { $0[$1.name] = $1.value }
    }

    // MARK: - Synthesis

    @Test func synthesizesLimeVehicleLink() throws {
        let rental = try RentalFixtures.vehicle(id: "lime_seattle:e0762983-6769-4191-903e-7a9e44444ea3")
        let target = try #require(RentalDeepLink.target(for: rental, now: now))

        #expect(target.url.scheme == "limebike")
        #expect(target.url.host == "map")
        #expect(query(target.url)["selected_vehicle_id"] == "e0762983-6769-4191-903e-7a9e44444ea3")
        #expect(query(target.url)["generated_at"] == timestamp)
        #expect(target.storeFallback?.absoluteString == "https://apps.apple.com/app/id1199780189")
        #expect(target.operatorName == "Lime")
    }

    @Test func usesWholeVehicleIDWhenThereIsNoColon() throws {
        let rental = try RentalFixtures.vehicle(id: "bare-id-42")
        let target = try #require(RentalDeepLink.target(for: rental, now: now))

        #expect(query(target.url)["selected_vehicle_id"] == "bare-id-42")
    }

    /// An id that is empty after the network prefix must not produce
    /// `selected_vehicle_id=` with no value — fall back to launching the app.
    @Test func fallsBackToAppLaunchWhenIDIsEmptyAfterPrefix() throws {
        let rental = try RentalFixtures.vehicle(id: "lime_seattle:")
        let target = try #require(RentalDeepLink.target(for: rental, now: now))

        #expect(target.url.scheme == "limebike")
        #expect(query(target.url)["selected_vehicle_id"] == nil)
        #expect(target.storeFallback?.absoluteString == "https://apps.apple.com/app/id1199780189")
    }

    /// The reason this type builds URLs with URLComponents: `.urlQueryAllowed`
    /// would let `&` and `=` through and let a hostile id forge parameters.
    @Test func escapesReservedCharactersInTheVehicleID() throws {
        let nasty = "a&b=c d\u{00e9}?e"
        let rental = try RentalFixtures.vehicle(id: "lime_seattle:\(nasty)")
        let target = try #require(RentalDeepLink.target(for: rental, now: now))

        #expect(query(target.url)["selected_vehicle_id"] == nasty)
        #expect(query(target.url)["generated_at"] == timestamp)
        #expect(query(target.url).count == 2)
    }

    @Test func synthesizesAppLevelLinkForBird() throws {
        let rental = try RentalFixtures.vehicle(id: "bird-seattle-washington:abc", networkId: "bird-seattle-washington")
        let target = try #require(RentalDeepLink.target(for: rental, now: now))

        #expect(target.url.scheme == "bird")
        #expect(query(target.url)["selected_vehicle_id"] == nil)
        #expect(target.storeFallback?.absoluteString == "https://apps.apple.com/app/id1260842311")
        #expect(target.operatorName == "Bird")
    }

    /// A station id is not a vehicle id; it must never land in `selected_vehicle_id`.
    @Test func stationGetsAppLevelLinkOnly() throws {
        let rental = try RentalFixtures.station(id: "lime_seattle:station-7")
        let target = try #require(RentalDeepLink.target(for: rental, now: now))

        #expect(target.url.scheme == "limebike")
        #expect(query(target.url)["selected_vehicle_id"] == nil)
    }

    // MARK: - Feed data

    @Test func feedProvidedURIWinsOverSynthesis() throws {
        let rental = try RentalFixtures.vehicle(
            id: "lime_seattle:abc",
            rentalUris: ["ios": "https://lime.example/ride/abc"]
        )
        let target = try #require(RentalDeepLink.target(for: rental, now: now))

        #expect(target.url.absoluteString == "https://lime.example/ride/abc")
    }

    /// Branch 1's fallback is the operator web page, not the App Store.
    @Test func feedProvidedURIKeepsTheNetworkURLAsFallback() throws {
        let rental = try RentalFixtures.vehicle(
            id: "lime_seattle:abc",
            networkURL: "https://www.li.me/",
            rentalUris: ["ios": "https://lime.example/ride/abc"]
        )
        let target = try #require(RentalDeepLink.target(for: rental, now: now))

        #expect(target.storeFallback?.absoluteString == "https://www.li.me/")
    }

    /// Pins the deliberate decision that synthesis outranks `rentalNetwork.url`.
    @Test func synthesisOutranksNetworkURLForKnownOperators() throws {
        let rental = try RentalFixtures.vehicle(id: "lime_seattle:abc", networkURL: "https://www.li.me/")
        let target = try #require(RentalDeepLink.target(for: rental, now: now))

        #expect(target.url.scheme == "limebike")
        #expect(target.storeFallback?.absoluteString == "https://apps.apple.com/app/id1199780189")
    }

    @Test func unknownOperatorFallsThroughToNetworkURL() throws {
        let rental = try RentalFixtures.vehicle(
            id: "veo_seattle:abc",
            networkId: "veo_seattle",
            networkURL: "https://www.veoride.com/"
        )
        let target = try #require(RentalDeepLink.target(for: rental, now: now))

        #expect(target.url.absoluteString == "https://www.veoride.com/")
        #expect(target.storeFallback == nil)
        #expect(target.operatorName == "Veo")
    }

    // MARK: - Absences

    @Test func unknownOperatorWithNoURLReturnsNil() throws {
        let rental = try RentalFixtures.vehicle(id: "veo_seattle:abc", networkId: "veo_seattle")
        #expect(RentalDeepLink.target(for: rental, now: now) == nil)
    }

    @Test func missingRentalNetworkReturnsNil() throws {
        let rental = try RentalFixtures.vehicle(id: "lime_seattle:abc", networkId: nil)
        #expect(RentalDeepLink.target(for: rental, now: now) == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/aaron/repos/onebusaway/ios-bikeshare
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: BUILD FAILURE — `cannot find 'RentalDeepLink' in scope`. That is the correct red state; the type does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `OBAKit/Mapping/Layers/RentalDeepLink.swift`:

```swift
//
//  RentalDeepLink.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OTPKit

/// Resolves the destination of the rental sheet's "Open in <operator>" button.
///
/// GBFS defines `rental_uris` for exactly this, and OTPKit asks for it — but no
/// Lime system publishes it. A survey of all 48 Lime systems in MobilityData's
/// catalog (~87,000 vehicles) found zero. Deep links are a Lime Transit
/// Partnership feature; the public feed omits them worldwide. So when the feed
/// says nothing, we synthesize the link from the operator's URL scheme and the
/// vehicle's own id.
///
/// The Lime scheme is reverse-engineered (ubahnverleih/WoBike) and undocumented
/// by Lime. That is tolerable only because failure is graceful: `UIApplication`
/// reports `success == false` when no app claims the scheme, and the caller then
/// opens `storeFallback`.
enum RentalDeepLink {

    /// Where the button should go, and where to land if that fails.
    struct Target: Equatable {
        let url: URL
        let storeFallback: URL?
        let operatorName: String?
    }

    /// A known operator's app-launch surface, expressed as URL *components*.
    ///
    /// Deliberately not a format string: `String(format:)` would bypass
    /// percent-encoding, and `.urlQueryAllowed` does not escape `&` or `=`
    /// inside a query value. Holding components makes the unsafe construction
    /// unexpressible.
    private struct Operator {
        let scheme: String
        /// Host of the vehicle-targeting URL. Nil when the app cannot target an
        /// individual vehicle, in which case only `appHost` is ever used.
        let vehicleHost: String?
        /// Query key carrying the vehicle id.
        let vehicleIDKey: String?
        /// Host for the plain app-launch URL: stations, untargetable operators.
        let appHost: String?
        let appStoreID: String
    }

    /// Keyed by the leading token of the GBFS network id — the same tokenization
    /// OTPKit's `RentalNetwork.displayName` uses, so the button's operator and
    /// the sheet header's operator can never disagree.
    private static let operators: [String: Operator] = [
        "lime": Operator(
            scheme: "limebike",
            vehicleHost: "map",
            vehicleIDKey: "selected_vehicle_id",
            appHost: "map",
            appStoreID: "1199780189"
        ),
        "bird": Operator(
            scheme: "bird",
            vehicleHost: nil,
            vehicleIDKey: nil,
            appHost: nil,
            appStoreID: "1260842311"
        )
    ]

    /// - Parameter now: injected so `generated_at` is deterministic in tests.
    static func target(for rental: VehicleRental, now: Date = Date()) -> Target? {
        let network = rental.rentalNetwork
        let operatorName = network?.displayName
        let webURL = network?.url.flatMap(URL.init(string:))

        // 1. Feed data wins, network block or not. The pre-synthesis behaviour
        //    never required one, and the two fields are independently optional.
        if let ios = rental.rentalUris?.ios, let url = URL(string: ios) {
            return Target(url: url, storeFallback: webURL, operatorName: operatorName)
        }

        // Synthesis and the web-page fallback both need the network block.
        guard let network else { return nil }

        // 2. Synthesize for known operators. Deliberately outranks the network
        //    URL below: a targeted app link beats an operator homepage, which is
        //    a dead end for someone standing next to a scooter.
        if let synthesized = synthesize(for: rental, network: network, now: now) {
            return Target(
                url: synthesized.url,
                storeFallback: synthesized.storeFallback,
                operatorName: operatorName
            )
        }

        // 3. The operator's web page, when the feed published one.
        if let webURL {
            return Target(url: webURL, storeFallback: nil, operatorName: operatorName)
        }

        // 4. Nothing to open; the caller hides the button.
        return nil
    }

    // MARK: - Synthesis

    private static func synthesize(
        for rental: VehicleRental,
        network: RentalNetwork,
        now: Date
    ) -> (url: URL, storeFallback: URL?)? {
        guard let op = operators[networkToken(network.networkId)] else { return nil }

        var components = URLComponents()
        components.scheme = op.scheme

        // Stations carry a station id, never a vehicle id, so they only ever
        // get the app-launch form.
        if case .vehicle(let vehicle) = rental,
           let host = op.vehicleHost,
           let key = op.vehicleIDKey,
           let id = rawVehicleID(vehicle.vehicleId) {
            components.host = host
            components.queryItems = [
                URLQueryItem(name: key, value: id),
                // Epoch seconds is an inference: the documented format carries an
                // untyped <timestamp>. Built as a string because "%d" via
                // String(format:) is a 32-bit specifier.
                URLQueryItem(name: "generated_at", value: String(Int(now.timeIntervalSince1970)))
            ]
        } else {
            components.host = op.appHost
        }

        guard let url = components.url else { return nil }
        return (url, URL(string: "https://apps.apple.com/app/id\(op.appStoreID)"))
    }

    /// `lime_seattle` -> `lime`, `bird-seattle-washington` -> `bird`.
    private static func networkToken(_ networkId: String) -> String {
        let token = networkId.split(whereSeparator: { $0 == "_" || $0 == "-" }).first
        return (token.map(String.init) ?? networkId).lowercased()
    }

    /// OTP returns `network:id`. Strip through the first colon to recover the raw
    /// GBFS `bike_id`. Nil when nothing usable remains, so the caller drops to the
    /// app-launch form rather than emitting an empty parameter.
    private static func rawVehicleID(_ vehicleId: String) -> String? {
        let raw = vehicleId.firstIndex(of: ":").map { String(vehicleId[vehicleId.index(after: $0)...]) } ?? vehicleId
        return raw.isEmpty ? nil : raw
    }
}
```

Note: `components.url` produces `limebike://map?...`. `URLComponents` escapes `&` and `=` inside the value; `URLQueryItem` round-trips them.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd /Users/aaron/repos/onebusaway/ios-bikeshare
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild test-without-building -only-testing:OBAKitTests/RentalDeepLinkTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: PASS, 12 tests.

If `escapesReservedCharactersInTheVehicleID` fails on the `?` character, check that you used `URLQueryItem` and not manual string building — that test exists precisely to catch it.

- [ ] **Step 5: Lint**

```bash
scripts/swiftlint.sh
```

Expected: no new violations.

- [ ] **Step 6: Commit**

```bash
git add OBAKit/Mapping/Layers/RentalDeepLink.swift OBAKitTests/Mapping/RentalDeepLinkTests.swift
git commit -m "Synthesize rental deep links when the feed publishes none

No Lime system anywhere publishes GBFS rental_uris, so the Open in
Lime button has never rendered. Build the link from the vehicle id
instead, with the App Store as the failure path."
```

---

## Task 3: Wire the detail sheet to it

**Files:**
- Modify: `OBAKit/Mapping/Layers/RentalDetailViewController.swift:210-224`

**Interfaces:**
- Consumes: `RentalDeepLink.target(for:now:)` and `RentalDeepLink.Target` from Task 2.
- Produces: no new API. `deepLinkURL` keeps its existing tuple shape `(title: String, url: URL, webFallback: URL?)` so the `body` call site at `:91-100` is untouched.

- [ ] **Step 1: Replace `deepLinkURL`**

Replace the whole computed property (currently lines 210–224, from the `/// Deep link:` comment through its closing brace) with:

```swift
    /// Where the "Open in <operator>" button goes. Feed-published URIs win;
    /// otherwise `RentalDeepLink` synthesizes one from the operator's scheme.
    /// Nil hides the button.
    private var deepLinkURL: (title: String, url: URL, webFallback: URL?)? {
        guard let target = RentalDeepLink.target(for: rental) else { return nil }

        let template = OBALoc("rental_detail.open_in_fmt", value: "Open in %@", comment: "Button opening the rental operator's app or website")
        let name = target.operatorName ?? target.url.host() ?? "app"

        return (String(format: template, name), target.url, target.storeFallback)
    }
```

- [ ] **Step 2: Build and run the full rental test suite**

```bash
cd /Users/aaron/repos/onebusaway/ios-bikeshare
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild test-without-building -only-testing:OBAKitTests/RentalDeepLinkTests -only-testing:OBAKitTests/RentalVisibilityTests -only-testing:OBAKitTests/RentalAnnotationViewTests -only-testing:OBAKitTests/RentalLayerCoordinatorTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: PASS. No project regeneration needed — no files added.

- [ ] **Step 3: Commit**

```bash
git add OBAKit/Mapping/Layers/RentalDetailViewController.swift
git commit -m "Route the rental sheet's deep link through RentalDeepLink"
```

---

## Task 4: Analytics

Scheme rot is invisible client-side — `open` reports false whether Lime is absent or Lime changed the scheme. Tap and fallback counts are the only field signal.

**Files:**
- Modify: `OBAKit/Analytics/Analytics.swift:66-71` (insert after `rentalPlanTripTapped`)
- Modify: `OBAKit/Mapping/MapViewController+MapLayers.swift:209-223`

**Interfaces:**
- Consumes: `AnalyticsLabels.rentalPlanTripTapped` as the style precedent; `application.analytics?.reportEvent(pageURL:label:value:)`.
- Produces: `AnalyticsLabels.rentalDeepLinkTapped`, `AnalyticsLabels.rentalDeepLinkFallbackFired`.

- [ ] **Step 1: Add the labels**

In `OBAKit/Analytics/Analytics.swift`, directly after the `rentalPlanTripTapped` declaration, insert:

```swift
    /// Label used when the rider taps "Open in <operator>" on the rental sheet.
    /// Value: the network id.
    @objc public static let rentalDeepLinkTapped = "Rental Deep Link Tapped"

    /// Label used when a rental deep link failed to open and the fallback URL was
    /// used instead. Value: the network id. A fallback rate that jumps toward
    /// 100% is the only signal that an operator changed its URL scheme.
    @objc public static let rentalDeepLinkFallbackFired = "Rental Deep Link Fallback Fired"
```

- [ ] **Step 2: Report them, and correct the stale comment**

In `OBAKit/Mapping/MapViewController+MapLayers.swift`, replace the `rentalLayer(open:webFallback:)` method **and its doc comment** with:

```swift
    /// Opens a rental deep link. No `canOpenURL` pre-check: Apple's own guidance
    /// is to attempt the open and handle failure, and `open` — unlike
    /// `canOpenURL` — is not constrained by `LSApplicationQueriesSchemes`.
    ///
    /// The URL is often synthesized from a reverse-engineered scheme rather than
    /// published by the feed (see `RentalDeepLink`), so failure is expected and
    /// routine: no app claims the scheme, `success` is false, and we fall back to
    /// the operator's App Store page or web page.
    func rentalLayer(open url: URL, webFallback: URL?, networkID: String?) {
        application.analytics?.reportEvent(
            pageURL: "app://localhost/bikeshare",
            label: AnalyticsLabels.rentalDeepLinkTapped,
            value: networkID
        )

        application.open(url, options: [:]) { [weak self] success in
            guard !success else { return }
            Logger.info("Rental deep link failed to open: \(url)")
            self?.application.analytics?.reportEvent(
                pageURL: "app://localhost/bikeshare",
                label: AnalyticsLabels.rentalDeepLinkFallbackFired,
                value: networkID
            )
            if let webFallback {
                self?.application.open(webFallback, options: [:], completionHandler: nil)
            }
        }
    }
```

- [ ] **Step 3: Thread the network id through the delegate**

`MapViewController` holds no selected-rental state (verified: the only `VehicleRental` reference in `MapViewController+MapLayers.swift` is `rentalLayer(planTripUsing:)`'s parameter), so `selectedRentalNetworkID` used in Step 2 does not exist and must be a parameter instead. `RentalDetailView` already has `rental` in hand, so the value is free at the call site.

Make these five edits in `OBAKit/Mapping/Layers/RentalDetailViewController.swift`:

**3a — protocol method, line 25-26:**

```swift
    /// Open a rental deep link, falling back to the operator's web page or App
    /// Store listing when the primary URI fails to open (e.g. a synthesized
    /// custom scheme with no app installed). `networkID` is for analytics.
    func rentalLayer(open url: URL, webFallback: URL?, networkID: String?)
```

**3b — `RentalDetailViewController.init`, line 49:**

```swift
            onOpenURL: { delegate?.rentalLayer(open: $0, webFallback: $1, networkID: $2) }
```

**3c — `RentalDetailView.onOpenURL`, line 66:**

```swift
    var onOpenURL: (URL, URL?, String?) -> Void
```

**3d — the button action, line 93:**

```swift
                    onOpenURL(deepLink.url, deepLink.webFallback, rental.rentalNetwork?.networkId)
```

**3e — `RentalClusterListViewController.init` (line 294) and `RentalClusterListView.onOpenURL` (line 310):**

```swift
            onOpenURL: { delegate?.rentalLayer(open: $0, webFallback: $1, networkID: $2) }
```

```swift
    var onOpenURL: (URL, URL?, String?) -> Void
```

Line 334 (`onOpenURL: onOpenURL`, the cluster list handing its closure to `RentalDetailView`) needs no edit — the type widens with the declarations.

`MapViewController+MapLayers.swift` needs no further edit: the method written in Step 2 already declares `networkID: String?` and uses it directly. These five edits exist to make that parameter reach it.

- [ ] **Step 4: Build and test**

```bash
cd /Users/aaron/repos/onebusaway/ios-bikeshare
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild test-without-building -only-testing:OBAKitTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: PASS. Full suite, because Step 3(b) can touch shared signatures.

- [ ] **Step 5: Lint and commit**

```bash
scripts/swiftlint.sh
git add OBAKit/Analytics/Analytics.swift OBAKit/Mapping/MapViewController+MapLayers.swift OBAKit/Mapping/Layers/RentalDetailViewController.swift
git commit -m "Report rental deep link taps and fallbacks

A synthesized scheme can rot without warning. The ratio of fallbacks
to taps is the only field signal that an operator changed it."
```

---

## Task 5: Full verification

**Files:** none modified.

**Interfaces:** none.

- [ ] **Step 1: Clean build and the entire test suite**

```bash
cd /Users/aaron/repos/onebusaway/ios-bikeshare
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild test-without-building -only-testing:OBAKitTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: PASS, no new failures versus `origin/main`.

- [ ] **Step 2: Lint the whole repo**

```bash
scripts/swiftlint.sh
```

Expected: clean.

- [ ] **Step 3: Confirm no stray files are staged**

```bash
git status --short
git log --oneline origin/main..HEAD
```

`Apps/Shared/app_shared.yml` **must not** appear. A local `path:` override for it is parked in `git stash` (message: "local OTPKit path override (pre-deep-links)") and must stay out of the branch.

- [ ] **Step 4: Record the manual verification checklist in the PR**

This cannot be automated — the unit tests prove we build the URL we intend, not that Lime honours it. The PR body must carry:

```text
### Manual verification (required before merge)
- [ ] Install Lime on a device running this build
- [ ] Open a Lime vehicle sheet, tap "Open in Lime"
- [ ] Lime opens AND focuses that specific vehicle (not a generic map)
- [ ] If it opens to a generic map, retry with `generated_at` in
      milliseconds, then omitted, before concluding targeting is
      unsupported — the unit is an inference, not documented
- [ ] Delete Lime, repeat, confirm the App Store fallback opens
- [ ] Confirm bare `limebike://map` (the station form) launches the app
```

---

## Notes for the implementer

- **Do not** add `limebike` to `LSApplicationQueriesSchemes`. `canOpenURL` is deprecated; `open` is not constrained by that key. This was an explicit design decision.
- **Do not** touch OTPKit. It is a separate repo and this feature needs nothing from it.
- **Do not** consult `rentalUris.web`. It has never been read and this change does not alter that.
- If a test seems wrong, re-read the spec at `docs/superpowers/specs/2026-07-30-lime-deep-links-design.md` before changing it. Several tests encode decisions that look arbitrary without it — particularly `synthesisOutranksNetworkURLForKnownOperators`.
