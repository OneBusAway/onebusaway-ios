# Rental Range Filter and Fuel Labels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a shared minimum-range filter for the Bikes and Scooters map layers, and render each rental pin's battery percent (falling back to remaining range) beneath its marker.

**Architecture:** Three new pure value types carry all the logic — `RentalRangeFilter` (the predicate), `RentalRangePreset` (the menu ladder), and `RentalVisibility` (a cache of every delivered entity plus the diff between what is cached and what belongs on the map). `RentalLayerCoordinator` shrinks to translating `RentalVisibility.Changes` into `MKMapView` calls. The threshold persists on `MapRegionManager` beside the existing per-layer enablement, so the Map sheet's Reset affordance covers it; `MapViewController` wires a change notification through to the coordinator.

**Tech Stack:** Swift 6, UIKit + MapKit, SwiftUI (Map sheet), OTPKit (`VehicleRental` models), Swift Testing, XcodeGen.

Full design rationale: `docs/superpowers/specs/2026-07-29-rental-range-filter-design.md`.

## Global Constraints

Every task's requirements implicitly include this section.

- **Simulator destination must pin the OS: `platform=iOS Simulator,OS=26.3.1,name=iPhone 17 Pro`.** iPhone 16 is not installed, so `CLAUDE.md`'s destination string is stale. Worse, the bare form `platform=iOS Simulator,name=iPhone 17 Pro` **fails to resolve on this machine** — six iOS runtimes are installed (18.5, 26.3, and four separate 27.0 builds), and `xcodebuild` responds with "Unable to find a device matching the provided destination specifier" while listing only macOS and watchOS candidates. That error looks like a missing simulator; it is actually ambiguity. Always pin `OS=26.3.1`.
- **Run `scripts/generate_project OneBusAway` after creating ANY new source or test file.** XcodeGen discovers files from disk. A test file the project doesn't know about does not fail — it silently runs zero tests, which reads as passing.
- **`OBAKit.xcodeproj` is gitignored** (`.gitignore:16`, `OBAKit.xcodeproj/**`). It is generated, never committed — do not add it to any `git add`, and do not list it among changed files in a report. The proof that XcodeGen picked up a new file is the test count, not the project file.
- **Always `set -o pipefail` before piping `xcodebuild` to `tail`.** Without it a failed build exits 0 and the failure is invisible.
- **A failing test run stalls for ~10 minutes in `simctl diagnose`.** Once failures have printed, kill `xcodebuild` rather than waiting. Do not run two failing suites concurrently.
- **Swift 6 language mode, main-actor default isolation** in OBAKit (OBAKitCore pins back to `nonisolated`). The five concurrency diagnostic groups are escalated to **errors** — a data-race warning fails the build.
- **Consequence of the above:** every new type in this plan is implicitly main-actor isolated, so every test suite touching them must be annotated `@MainActor`.
- **Tests are Swift Testing** (`@Suite` / `@Test` / `#expect`), never XCTest. Suites are `final class`, annotated `@MainActor @Suite(.serialized)`.
- **Test isolation comes from fixtures, not scheduling.** Swift Testing runs suites in parallel via task groups in one process. Never touch `UserDefaults.standard`; use `OBATestCase`'s per-instance `userDefaultsSuiteName`.
- **OTPKit's rental models have no public memberwise initializer.** `RentalVehicle`, `VehicleRentalStation`, `FuelInfo`, and `VehicleType` expose only internal memberwise inits. Test fixtures must be built by decoding JSON through `VehicleRental.init(from:)`, which *is* public. Task 1 builds that helper.
- **New user-facing strings are declared ONLY in code**, via `OBALoc("key", value: "English text", comment: "…")`. Do **not** add them to `OBAKit/Strings/en.lproj/Localizable.strings`, and do not hand-edit other locales. `OBAKitTests/Strings/LocalizationTests.swift` asserts key parity between `en` and all 12 other locales, so an en-only entry fails that suite 12 times over. Every rental string already on this branch (`map_layers.bikes`, `map_sheet.title`, `rental_detail.range`, …) has zero `.strings` entries and relies on the `value:` default — follow that.
- **Lint before each commit:** `scripts/swiftlint.sh`.

### Standard commands

Build for testing (run once up front, and again after any `generate_project`):

```bash
set -o pipefail
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17 Pro' 2>&1 | tail -20
```

Run one suite:

```bash
set -o pipefail
xcodebuild test-without-building -only-testing:OBAKitTests/<SuiteName> \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17 Pro' 2>&1 | tail -20
```

---

## File Structure

**Create — production (`OBAKit/Mapping/Layers/`)**

| File | Responsibility |
| --- | --- |
| `RentalRangeFilter.swift` | The fail-open minimum-range predicate. Nothing else. |
| `RentalRangePreset.swift` | The locale-appropriate menu ladder and nearest-rung lookup. |
| `RentalVisibility.swift` | Cache of delivered entities + the add/remove/update diff. No MapKit, no async. |
| `RentalFormat.swift` | Shared rental formatting, moved out of `RentalDetailViewController.swift`, plus the new fuel-label text. |

**Create — tests (`OBAKitTests/Mapping/`)**

| File | Responsibility |
| --- | --- |
| `RentalFixtures.swift` | JSON-decoded `VehicleRental` builders. Not a suite. |
| `RentalRangeFilterTests.swift` | The allow matrix. |
| `RentalRangePresetTests.swift` | Both ladders, metres, titles, nearest rung. |
| `RentalVisibilityTests.swift` | Diffs, threshold changes, cache restore, ordering. |
| `RentalFormatTests.swift` | Percent rounding/clamping, range fallback, nil cases. |
| `RentalAnnotationViewTests.swift` | Label text, hidden state, tint, accessibility. |
| `MapRegionManagerRentalFilterTests.swift` | Persistence, reset, differs-from-defaults. |

**Modify**

| File | Change |
| --- | --- |
| `OBAKit/Mapping/Layers/RentalDetailViewController.swift` | Remove the `RentalFormat` enum (moved to its own file). |
| `OBAKit/Mapping/Layers/MapLayer.swift` | Add the `.rentalRangeFilterDidChange` notification name. |
| `OBAKit/Mapping/MapRegionManager.swift` | Add `rentalRangeFilter`; fold it into reset and differs-from-defaults. |
| `OBAKit/Mapping/Layers/RentalAnnotation.swift` | Add `showsFuelLabel`. |
| `OBAKit/Mapping/Layers/RentalAnnotationView.swift` | Add the fuel label subview and accessibility label. |
| `OBAKit/Mapping/Layers/RentalLayerCoordinator.swift` | Adopt `RentalVisibility`; add `setRangeFilter`; add the label zoom gate; delete `pruneAnnotations`. |
| `OBAKit/Mapping/Layers/MapSheetView.swift` | Add the picker row to the "Other ways to get around" section. |
| `OBAKit/Mapping/MapViewController+MapLayers.swift` | Seed the coordinator's filter; observe the change notification. |
| `OBAKit/Mapping/MapViewController.swift:166-167` | Register the new notification observer. |
| `OBAKit/Analytics/Analytics.swift` | Add the `rentalRangeFilterChanged` label. |

---

## Task 1: Range filter predicate and test fixtures

The predicate is the smallest piece and the first consumer of the fixture helper, so they land together.

**Files:**
- Create: `OBAKit/Mapping/Layers/RentalRangeFilter.swift`
- Create: `OBAKitTests/Mapping/RentalFixtures.swift`
- Test: `OBAKitTests/Mapping/RentalRangeFilterTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct RentalRangeFilter: Equatable` with `let minimumRangeMeters: Int`, `static let any`, `var isActive: Bool`, `func allows(_ rental: VehicleRental) -> Bool`
  - `enum RentalFixtures` with
    `static func vehicle(id: String, formFactor: String, propulsion: String?, rangeMeters: Int?, batteryPercent: Double?, operative: Bool, lat: Double, lon: Double) throws -> VehicleRental`
    and `static func station(id: String, vehiclesAvailable: Int?, operative: Bool, lat: Double, lon: Double) throws -> VehicleRental`

- [ ] **Step 1: Write the fixture helper**

Create `OBAKitTests/Mapping/RentalFixtures.swift`. This decodes rather than constructs, because OTPKit's rental models expose no public memberwise init — only `VehicleRental.init(from:)` is public.

```swift
//
//  RentalFixtures.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OTPKit

/// Builds `VehicleRental` values for tests.
///
/// These are decoded from JSON rather than constructed directly: OTPKit's
/// `RentalVehicle`, `VehicleRentalStation`, `FuelInfo`, and `VehicleType` expose
/// only internal memberwise initializers, so the sole cross-module entry point is
/// `VehicleRental.init(from:)`. Decoding has the side benefit of exercising the
/// same path real payloads take, including `__typename` discrimination.
enum RentalFixtures {

    /// A free-floating rental vehicle. Pass `rangeMeters: nil, batteryPercent: nil`
    /// for a vehicle whose feed publishes no fuel data at all.
    static func vehicle(
        id: String = "v1",
        formFactor: String = "SCOOTER",
        propulsion: String? = "ELECTRIC",
        rangeMeters: Int? = nil,
        batteryPercent: Double? = nil,
        operative: Bool = true,
        lat: Double = 47.6,
        lon: Double = -122.3
    ) throws -> VehicleRental {
        var fuelFields: [String] = []
        if let batteryPercent {
            fuelFields.append("\"percent\": \(batteryPercent)")
        }
        if let rangeMeters {
            fuelFields.append("\"range\": \(rangeMeters)")
        }
        let fuelJSON = fuelFields.isEmpty ? "null" : "{ \(fuelFields.joined(separator: ", ")) }"
        let propulsionJSON = propulsion.map { "\"\($0)\"" } ?? "null"

        let json = """
        {
          "__typename": "RentalVehicle",
          "vehicleId": "\(id)",
          "name": "Default vehicle type",
          "lat": \(lat),
          "lon": \(lon),
          "allowPickupNow": true,
          "operative": \(operative),
          "rentalNetwork": { "networkId": "lime_seattle", "url": null },
          "rentalUris": null,
          "vehicleType": { "formFactor": "\(formFactor)", "propulsionType": \(propulsionJSON) },
          "fuel": \(fuelJSON)
        }
        """
        return try JSONDecoder().decode(VehicleRental.self, from: Data(json.utf8))
    }

    /// A non-powered vehicle: a pedal bike, with no `fuel` object at all.
    static func pedalBike(id: String = "b1") throws -> VehicleRental {
        try vehicle(id: id, formFactor: "BICYCLE", propulsion: "HUMAN", rangeMeters: nil, batteryPercent: nil)
    }

    /// A docked station. Stations never carry fuel data.
    static func station(
        id: String = "s1",
        vehiclesAvailable: Int? = 4,
        operative: Bool = true,
        lat: Double = 47.6,
        lon: Double = -122.3
    ) throws -> VehicleRental {
        let json = """
        {
          "__typename": "VehicleRentalStation",
          "stationId": "\(id)",
          "name": "Pine St Station",
          "lat": \(lat),
          "lon": \(lon),
          "vehiclesAvailable": \(vehiclesAvailable.map(String.init) ?? "null"),
          "operative": \(operative)
        }
        """
        return try JSONDecoder().decode(VehicleRental.self, from: Data(json.utf8))
    }
}
```

- [ ] **Step 2: Write the failing test**

Create `OBAKitTests/Mapping/RentalRangeFilterTests.swift`:

```swift
//
//  RentalRangeFilterTests.swift
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

/// The rental minimum-range filter is deliberately fail-open: it hides only a
/// vehicle that *reports* a range below the threshold. Everything else — stations,
/// pedal bikes, vehicles whose feed omits range — stays on the map, so a feed that
/// never publishes range can't be filtered into an empty map.
@MainActor
@Suite(.serialized)
final class RentalRangeFilterTests {

    @Test func inactiveFilterAllowsEverything() throws {
        let filter = RentalRangeFilter.any

        #expect(filter.isActive == false)
        #expect(filter.allows(try RentalFixtures.vehicle(rangeMeters: 100)))
        #expect(filter.allows(try RentalFixtures.station()))
        #expect(filter.allows(try RentalFixtures.pedalBike()))
    }

    @Test func hidesVehicleBelowThreshold() throws {
        let filter = RentalRangeFilter(minimumRangeMeters: 8047)
        #expect(filter.allows(try RentalFixtures.vehicle(rangeMeters: 3200)) == false)
    }

    @Test func keepsVehicleAtExactlyThreshold() throws {
        let filter = RentalRangeFilter(minimumRangeMeters: 8047)
        #expect(filter.allows(try RentalFixtures.vehicle(rangeMeters: 8047)))
    }

    @Test func keepsVehicleAboveThreshold() throws {
        let filter = RentalRangeFilter(minimumRangeMeters: 8047)
        #expect(filter.allows(try RentalFixtures.vehicle(rangeMeters: 13000)))
    }

    @Test func keepsVehicleWithUnknownRange() throws {
        let filter = RentalRangeFilter(minimumRangeMeters: 8047)
        #expect(filter.allows(try RentalFixtures.vehicle(rangeMeters: nil)))
    }

    /// A battery percent is not a range; it must not be mistaken for one.
    @Test func keepsVehicleWithPercentButNoRange() throws {
        let filter = RentalRangeFilter(minimumRangeMeters: 8047)
        #expect(filter.allows(try RentalFixtures.vehicle(rangeMeters: nil, batteryPercent: 0.05)))
    }

    /// A pedal bike's range is the rider's legs. Filtering it out would be wrong.
    @Test func keepsPedalBike() throws {
        let filter = RentalRangeFilter(minimumRangeMeters: 8047)
        #expect(filter.allows(try RentalFixtures.pedalBike()))
    }

    @Test func keepsStation() throws {
        let filter = RentalRangeFilter(minimumRangeMeters: 8047)
        #expect(filter.allows(try RentalFixtures.station()))
    }
}
```

- [ ] **Step 3: Regenerate the project and run the test to verify it fails**

```bash
set -o pipefail
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17 Pro' 2>&1 | tail -20
```

Expected: **build FAILS** with "cannot find 'RentalRangeFilter' in scope". This is the red state — the type doesn't exist yet.

- [ ] **Step 4: Write the minimal implementation**

Create `OBAKit/Mapping/Layers/RentalRangeFilter.swift`:

```swift
//
//  RentalRangeFilter.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OTPKit

/// The rider's "don't show me nearly-dead vehicles" filter.
///
/// Fail-open by design: only a vehicle that *reports* a range below the threshold
/// is hidden. Docked stations, pedal bikes, and vehicles whose feed omits `range`
/// all leave through the same early return — a feed that never publishes range
/// must not be filterable into an empty map. This mirrors the convention already
/// set by `VehicleRental.matches(formFactors:)`.
struct RentalRangeFilter: Equatable {

    /// Threshold in meters. Zero means "Any" — no filtering at all.
    let minimumRangeMeters: Int

    static let any = RentalRangeFilter(minimumRangeMeters: 0)

    var isActive: Bool { minimumRangeMeters > 0 }

    func allows(_ rental: VehicleRental) -> Bool {
        guard isActive,
              case .vehicle(let vehicle) = rental,
              let range = vehicle.fuel?.range else {
            return true
        }
        return range >= minimumRangeMeters
    }
}
```

- [ ] **Step 5: Regenerate, build, and run the test to verify it passes**

```bash
set -o pipefail
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17 Pro' 2>&1 | tail -20
xcodebuild test-without-building -only-testing:OBAKitTests/RentalRangeFilterTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17 Pro' 2>&1 | tail -20
```

Expected: PASS, **8 tests executed**. If it reports 0 tests, `generate_project` did not pick up the new files — re-run it and rebuild.

- [ ] **Step 6: Lint and commit**

```bash
scripts/swiftlint.sh
git add OBAKit/Mapping/Layers/RentalRangeFilter.swift \
        OBAKitTests/Mapping/RentalFixtures.swift \
        OBAKitTests/Mapping/RentalRangeFilterTests.swift
git commit -m "Add the fail-open rental range filter predicate"
```

---

## Task 2: Preset ladder

**Files:**
- Create: `OBAKit/Mapping/Layers/RentalRangePreset.swift`
- Test: `OBAKitTests/Mapping/RentalRangePresetTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `struct RentalRangePreset: Equatable, Identifiable` with `let meters: Int`, `let title: String`, `var id: Int { meters }`,
  `static func presets(measurementSystem: Locale.MeasurementSystem = Locale.current.measurementSystem) -> [RentalRangePreset]`,
  `static func nearest(toMeters: Int, in: [RentalRangePreset]) -> RentalRangePreset?`

- [ ] **Step 1: Write the failing test**

Create `OBAKitTests/Mapping/RentalRangePresetTests.swift`. Note the exact metre values: 1 mi = 1609.344 → 1609; 2 mi → 3219; 5 mi = 8046.72 → 8047; 10 mi → 16093; 15 mi → 24140.

```swift
//
//  RentalRangePresetTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit

/// The range-filter menu ladder. Rungs are whole numbers in the rider's own units
/// rather than a metric ladder converted from miles, because "8 km" reads as a bug.
@MainActor
@Suite(.serialized)
final class RentalRangePresetTests {

    @Test func imperialLadderUsesWholeMiles() {
        let titles = RentalRangePreset.presets(measurementSystem: .us).map(\.title)
        #expect(titles == ["Any", "1 mi", "2 mi", "5 mi", "10 mi", "15 mi"])
    }

    @Test func metricLadderUsesWholeKilometres() {
        let titles = RentalRangePreset.presets(measurementSystem: .metric).map(\.title)
        #expect(titles == ["Any", "2 km", "5 km", "10 km", "15 km", "25 km"])
    }

    /// UK road distances are in miles even though the UK is otherwise metric.
    @Test func unitedKingdomGetsMiles() {
        let titles = RentalRangePreset.presets(measurementSystem: .uk).map(\.title)
        #expect(titles == ["Any", "1 mi", "2 mi", "5 mi", "10 mi", "15 mi"])
    }

    /// `Locale.MeasurementSystem` is a struct constructible from any BCP-47
    /// identifier, so it can never be switched exhaustively. Anything unrecognized
    /// must land on metric — that's right for most of the world.
    @Test func unknownSystemFallsBackToMetric() {
        let titles = RentalRangePreset.presets(measurementSystem: Locale.MeasurementSystem("nonsense")).map(\.title)
        #expect(titles == ["Any", "2 km", "5 km", "10 km", "15 km", "25 km"])
    }

    @Test func anyRungIsZeroMetres() {
        let presets = RentalRangePreset.presets(measurementSystem: .us)
        #expect(presets.first?.meters == 0)
    }

    @Test func imperialRungsConvertToMetres() {
        let meters = RentalRangePreset.presets(measurementSystem: .us).map(\.meters)
        #expect(meters == [0, 1609, 3219, 8047, 16093, 24140])
    }

    @Test func metricRungsConvertToMetres() {
        let meters = RentalRangePreset.presets(measurementSystem: .metric).map(\.meters)
        #expect(meters == [0, 2000, 5000, 10000, 15000, 25000])
    }

    @Test func identifierIsTheMetreValue() {
        let presets = RentalRangePreset.presets(measurementSystem: .us)
        #expect(presets.map(\.id) == presets.map(\.meters))
    }

    @Test func nearestRungMatchesExactly() {
        let presets = RentalRangePreset.presets(measurementSystem: .us)
        #expect(RentalRangePreset.nearest(toMeters: 8047, in: presets)?.meters == 8047)
    }

    /// A stored value from another locale's ladder highlights the closest rung,
    /// without the stored preference being rewritten.
    @Test func nearestRungSnapsAnOffLadderValue() {
        let presets = RentalRangePreset.presets(measurementSystem: .us)
        #expect(RentalRangePreset.nearest(toMeters: 10_000, in: presets)?.meters == 8047)
    }

    @Test func nearestRungHandlesZero() {
        let presets = RentalRangePreset.presets(measurementSystem: .us)
        #expect(RentalRangePreset.nearest(toMeters: 0, in: presets)?.meters == 0)
    }

    @Test func nearestRungOnEmptyLadderIsNil() {
        #expect(RentalRangePreset.nearest(toMeters: 5000, in: []) == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
set -o pipefail
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17 Pro' 2>&1 | tail -20
```

Expected: **build FAILS** with "cannot find 'RentalRangePreset' in scope".

- [ ] **Step 3: Write the minimal implementation**

Create `OBAKit/Mapping/Layers/RentalRangePreset.swift`:

```swift
//
//  RentalRangePreset.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// One rung of the Map sheet's minimum-range menu.
///
/// The stored preference is always metres; these rungs are the rider-facing
/// choices. Rung values are whole numbers in the rider's own units rather than a
/// metric ladder converted from miles, because "8 km" reads as a bug.
struct RentalRangePreset: Equatable, Identifiable {

    /// The threshold this rung selects. Zero is the "Any" rung.
    let meters: Int

    /// Rider-facing label: "Any", "5 mi", "10 km".
    let title: String

    var id: Int { meters }

    /// The ladder for a measurement system.
    ///
    /// `Locale.MeasurementSystem` is a struct, not an enum — it carries `.metric`,
    /// `.us`, and `.uk` but can be built from any BCP-47 identifier, so it can
    /// never be switched exhaustively. Miles are therefore the *explicit* case and
    /// metric the fallback: `.uk` genuinely wants miles (UK road distances are in
    /// miles), and anything unrecognized lands on metric, which is right for most
    /// of the world.
    static func presets(
        measurementSystem: Locale.MeasurementSystem = Locale.current.measurementSystem
    ) -> [RentalRangePreset] {
        let usesMiles = measurementSystem == .us || measurementSystem == .uk
        let unit: UnitLength = usesMiles ? .miles : .kilometers
        let values: [Double] = usesMiles ? [1, 2, 5, 10, 15] : [2, 5, 10, 15, 25]

        let anyRung = RentalRangePreset(
            meters: 0,
            title: OBALoc("map_sheet.minimum_range_any", value: "Any", comment: "Range filter menu option imposing no minimum range")
        )

        return [anyRung] + values.map { value in
            let measurement = Measurement(value: value, unit: unit)
            return RentalRangePreset(
                meters: Int(measurement.converted(to: .meters).value.rounded()),
                title: formatter.string(from: measurement)
            )
        }
    }

    /// The rung closest to a stored metre value. Used only to highlight the menu
    /// selection — filtering keeps using the stored value, so a preference set in
    /// another locale is never silently rewritten.
    static func nearest(toMeters meters: Int, in presets: [RentalRangePreset]) -> RentalRangePreset? {
        presets.min { abs($0.meters - meters) < abs($1.meters - meters) }
    }

    /// `.providedUnit` suppresses both conversion and locale substitution, so the
    /// displayed number matches the rung exactly ("5 mi", not "8 km").
    private static let formatter: MeasurementFormatter = {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .medium
        formatter.numberFormatter.maximumFractionDigits = 0
        return formatter
    }()
}
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
set -o pipefail
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17 Pro' 2>&1 | tail -20
xcodebuild test-without-building -only-testing:OBAKitTests/RentalRangePresetTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17 Pro' 2>&1 | tail -20
```

Expected: PASS, **13 tests executed**.

- [ ] **Step 6: Lint and commit**

```bash
scripts/swiftlint.sh
git add OBAKit/Mapping/Layers/RentalRangePreset.swift \
        OBAKitTests/Mapping/RentalRangePresetTests.swift
git commit -m "Add the locale-appropriate rental range preset ladder"
```

---

## Task 3: Extract RentalFormat and add fuel-label text

`RentalFormat` currently lives inside `RentalDetailViewController.swift`, which was already the wrong home; this task adds a third consumer, so it moves out.

**Files:**
- Create: `OBAKit/Mapping/Layers/RentalFormat.swift`
- Modify: `OBAKit/Mapping/Layers/RentalDetailViewController.swift` (delete the `RentalFormat` enum, lines ~33-52)
- Test: `OBAKitTests/Mapping/RentalFormatTests.swift`

**Interfaces:**
- Consumes: `RentalFixtures` from Task 1.
- Produces: `enum RentalFormat` with the existing `static let distanceFormatter: MKDistanceFormatter`, `static func walkTimeText(from: CLLocation?, to: CLLocationCoordinate2D) -> String?`, `static func batteryText(_ percent: Double) -> String`, plus new `static let abbreviatedDistanceFormatter: MKDistanceFormatter` and `static func fuelLabelText(for rental: VehicleRental) -> String?`

- [ ] **Step 1: Write the failing test**

Create `OBAKitTests/Mapping/RentalFormatTests.swift`. The range assertions avoid hard-coding a locale-specific string; they assert the *abbreviated* property, which is what actually matters for a pin label.

```swift
//
//  RentalFormatTests.swift
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

/// The text that sits under a rental pin: battery percent when the feed provides
/// it, remaining range otherwise. On the launch feed `percent` is null fleet-wide
/// while `range` is populated, so the fallback is the common path, not the edge.
@MainActor
@Suite(.serialized)
final class RentalFormatTests {

    @Test func percentIsPreferredOverRange() throws {
        let rental = try RentalFixtures.vehicle(rangeMeters: 5470, batteryPercent: 0.62)
        #expect(RentalFormat.fuelLabelText(for: rental) == "62%")
    }

    @Test func percentRoundsToWholeNumber() throws {
        let rental = try RentalFixtures.vehicle(batteryPercent: 0.626)
        #expect(RentalFormat.fuelLabelText(for: rental) == "63%")
    }

    /// Feeds do send out-of-range values; clamp rather than render "120%".
    @Test func percentAboveOneClampsToHundred() throws {
        let rental = try RentalFixtures.vehicle(batteryPercent: 1.2)
        #expect(RentalFormat.fuelLabelText(for: rental) == "100%")
    }

    @Test func negativePercentClampsToZero() throws {
        let rental = try RentalFixtures.vehicle(batteryPercent: -0.1)
        #expect(RentalFormat.fuelLabelText(for: rental) == "0%")
    }

    @Test func fallsBackToRangeWhenPercentMissing() throws {
        let rental = try RentalFixtures.vehicle(rangeMeters: 5470, batteryPercent: nil)
        let text = RentalFormat.fuelLabelText(for: rental)
        #expect(text != nil)
        #expect(text?.contains("%") == false)
    }

    /// The default `MKDistanceFormatter` style spells the unit out ("3.4 miles"),
    /// which is far too long to sit under a map pin. The abbreviated style is the
    /// whole reason this formatter is separate from the detail sheet's.
    @Test func rangeFallbackUsesAbbreviatedUnits() throws {
        let rental = try RentalFixtures.vehicle(rangeMeters: 5470, batteryPercent: nil)
        let text = try #require(RentalFormat.fuelLabelText(for: rental))
        #expect(text.contains("miles") == false)
        #expect(text.contains("Kilometer") == false)
    }

    @Test func noFuelDataYieldsNoLabel() throws {
        let rental = try RentalFixtures.vehicle(rangeMeters: nil, batteryPercent: nil)
        #expect(RentalFormat.fuelLabelText(for: rental) == nil)
    }

    @Test func pedalBikeYieldsNoLabel() throws {
        #expect(RentalFormat.fuelLabelText(for: try RentalFixtures.pedalBike()) == nil)
    }

    /// Stations have no fuel of their own; the docked vehicles do.
    @Test func stationYieldsNoLabel() throws {
        #expect(RentalFormat.fuelLabelText(for: try RentalFixtures.station()) == nil)
    }

    /// The detail sheet's formatter must keep its spelled-out style — this task
    /// adds a formatter rather than mutating the shared one.
    @Test func detailSheetFormatterIsUnchanged() {
        #expect(RentalFormat.distanceFormatter.unitStyle == .default)
        #expect(RentalFormat.abbreviatedDistanceFormatter.unitStyle == .abbreviated)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
set -o pipefail
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17 Pro' 2>&1 | tail -20
```

Expected: **build FAILS** with "type 'RentalFormat' has no member 'fuelLabelText'" and "...no member 'abbreviatedDistanceFormatter'".

- [ ] **Step 3: Create the new file with the moved and new code**

Create `OBAKit/Mapping/Layers/RentalFormat.swift`:

```swift
//
//  RentalFormat.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import MapKit
import OBAKitCore
import OTPKit

/// Shared rider-facing formatting for rental entities, used by the detail sheet,
/// the cluster list, and the map annotation's fuel label.
enum RentalFormat {

    /// Cached: a fresh MKDistanceFormatter per row per render is waste.
    static let distanceFormatter = MKDistanceFormatter()

    /// A second formatter for space-constrained surfaces. The default style spells
    /// the unit out — 5,470 m renders as "3.4 miles" under en_US, where this one
    /// gives "3.4 mi". Only the abbreviated form fits under a map pin. The detail
    /// sheet's spelled-out rendering is deliberate, so the two coexist rather than
    /// one being mutated in place.
    static let abbreviatedDistanceFormatter: MKDistanceFormatter = {
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated
        return formatter
    }()

    /// Straight-line walk estimate at the app's default walking speed.
    /// Nil beyond 10 km — a "119 min walk" line is noise, not information.
    static func walkTimeText(from userLocation: CLLocation?, to coordinate: CLLocationCoordinate2D) -> String? {
        guard let userLocation else { return nil }
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let meters = userLocation.distance(from: target)
        guard meters.isFinite, meters < 10_000 else { return nil }

        let minutes = max(1, Int((meters / WalkingSpeed.defaultMetersPerSecond / 60).rounded()))
        return String(format: OBALoc("rental_detail.walk_time_fmt", value: "%d min walk", comment: "Estimated walking time to a rental vehicle"), minutes)
    }

    static func batteryText(_ percent: Double) -> String {
        "\(Int((percent * 100).rounded()))%"
    }

    /// The text rendered beneath a rental map pin: battery percent when the feed
    /// provides it, else remaining range, else nothing.
    ///
    /// The percent-first ordering matches the mockup, but the range fallback is the
    /// common path in practice: on the launch feed `percent` is null across the
    /// whole fleet while `range` is populated.
    static func fuelLabelText(for rental: VehicleRental) -> String? {
        guard case .vehicle(let vehicle) = rental, let fuel = vehicle.fuel else { return nil }

        if let percent = fuel.percent {
            // Feeds do send values outside 0...1; clamp rather than render "120%".
            return batteryText(min(max(percent, 0), 1))
        }

        if let range = fuel.range {
            return abbreviatedDistanceFormatter.string(fromDistance: CLLocationDistance(range))
        }

        return nil
    }
}
```

- [ ] **Step 4: Delete the old enum from the detail view controller**

In `OBAKit/Mapping/Layers/RentalDetailViewController.swift`, delete the entire `enum RentalFormat { ... }` block (it begins at the line `enum RentalFormat {` and ends with the closing brace before the `// MARK: - Detail Sheet` comment). Leave everything else in that file untouched — the `RentalFormat.` call sites still resolve, now to the new file.

- [ ] **Step 5: Run the test to verify it passes**

```bash
set -o pipefail
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17 Pro' 2>&1 | tail -20
xcodebuild test-without-building -only-testing:OBAKitTests/RentalFormatTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17 Pro' 2>&1 | tail -20
```

Expected: PASS, **10 tests executed**.

- [ ] **Step 6: Lint and commit**

```bash
scripts/swiftlint.sh
git add OBAKit/Mapping/Layers/RentalFormat.swift \
        OBAKit/Mapping/Layers/RentalDetailViewController.swift \
        OBAKitTests/Mapping/RentalFormatTests.swift
git commit -m "Extract RentalFormat and add abbreviated fuel-label text"
```

---

## Task 4: Visibility cache and diff

The core of the feature. `VehicleRentalSource` emits only diffs against what it has previously delivered, so without a local cache a vehicle dropped for being under threshold would never reappear when the threshold is lowered.

**Files:**
- Create: `OBAKit/Mapping/Layers/RentalVisibility.swift`
- Test: `OBAKitTests/Mapping/RentalVisibilityTests.swift`

**Interfaces:**
- Consumes: `RentalRangeFilter` (Task 1), `RentalFixtures` (Task 1).
- Produces: `struct RentalVisibility` with
  - nested `struct Changes: Equatable` having `var added: [VehicleRental]`, `var removed: [VehicleRental.ID]`, `var updated: [VehicleRental]`, `var isEmpty: Bool`
  - `private(set) var formFactors: Set<VehicleFormFactor>`, `private(set) var filter: RentalRangeFilter`
  - `mutating func apply(_ snapshot: VehicleRentalSnapshot) -> Changes`
  - `mutating func setFormFactors(_ formFactors: Set<VehicleFormFactor>) -> Changes`
  - `mutating func setFilter(_ filter: RentalRangeFilter) -> Changes`

- [ ] **Step 1: Write the failing test**

Create `OBAKitTests/Mapping/RentalVisibilityTests.swift`:

```swift
//
//  RentalVisibilityTests.swift
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

/// `RentalVisibility` holds every entity the source has delivered — not just the
/// visible ones — and answers "what should change on the map?" for each mutation.
/// The cache is what makes the range filter reversible: `VehicleRentalSource` emits
/// only diffs, so a dropped entity is not in a later `added` list.
@MainActor
@Suite(.serialized)
final class RentalVisibilityTests {

    private let scooters: Set<VehicleFormFactor> = [.scooter, .scooterSeated, .scooterStanding]
    private let bikes: Set<VehicleFormFactor> = [.bicycle, .cargoBicycle]

    private func snapshot(
        added: [VehicleRental] = [],
        removed: [VehicleRental.ID] = [],
        updated: [VehicleRental] = []
    ) -> VehicleRentalSnapshot {
        VehicleRentalSnapshot(added: added, removed: removed, updated: updated, fetchedAt: Date(timeIntervalSince1970: 0))
    }

    // MARK: - Snapshot application

    @Test func addsMatchingEntities() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)

        let scooter = try RentalFixtures.vehicle(id: "v1", formFactor: "SCOOTER")
        let changes = visibility.apply(snapshot(added: [scooter]))

        #expect(changes.added.map(\.id) == ["v1"])
        #expect(changes.removed.isEmpty)
    }

    @Test func ignoresEntitiesOfOtherFormFactors() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)

        let bike = try RentalFixtures.vehicle(id: "b1", formFactor: "BICYCLE")
        let changes = visibility.apply(snapshot(added: [bike]))

        #expect(changes.isEmpty)
    }

    @Test func withNoFormFactorsNothingIsVisible() throws {
        var visibility = RentalVisibility()
        let scooter = try RentalFixtures.vehicle(id: "v1", formFactor: "SCOOTER")

        #expect(visibility.apply(snapshot(added: [scooter])).isEmpty)
    }

    @Test func removesEntities() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)
        _ = visibility.apply(snapshot(added: [try RentalFixtures.vehicle(id: "v1")]))

        let changes = visibility.apply(snapshot(removed: ["v1"]))
        #expect(changes.removed == ["v1"])
    }

    @Test func removingAnInvisibleEntityChangesNothing() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)
        _ = visibility.apply(snapshot(added: [try RentalFixtures.vehicle(id: "b1", formFactor: "BICYCLE")]))

        #expect(visibility.apply(snapshot(removed: ["b1"])).isEmpty)
    }

    @Test func duplicateAddIsIgnored() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)
        let scooter = try RentalFixtures.vehicle(id: "v1")
        _ = visibility.apply(snapshot(added: [scooter]))

        #expect(visibility.apply(snapshot(added: [scooter])).isEmpty)
    }

    @Test func updatesVisibleEntityInPlace() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)
        _ = visibility.apply(snapshot(added: [try RentalFixtures.vehicle(id: "v1", rangeMeters: 10_000)]))

        let changes = visibility.apply(snapshot(updated: [try RentalFixtures.vehicle(id: "v1", rangeMeters: 9_000)]))
        #expect(changes.updated.map(\.id) == ["v1"])
        #expect(changes.added.isEmpty)
        #expect(changes.removed.isEmpty)
    }

    // MARK: - Threshold crossing

    /// A scooter that drains below the threshold has to leave the map, and an
    /// update is not a way to leave — it must be emitted as a removal.
    @Test func updateCrossingBelowThresholdBecomesARemoval() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)
        _ = visibility.apply(snapshot(added: [try RentalFixtures.vehicle(id: "v1", rangeMeters: 10_000)]))
        _ = visibility.setFilter(RentalRangeFilter(minimumRangeMeters: 8047))

        let changes = visibility.apply(snapshot(updated: [try RentalFixtures.vehicle(id: "v1", rangeMeters: 3_000)]))
        #expect(changes.removed == ["v1"])
        #expect(changes.updated.isEmpty)
    }

    /// The mirror image: fresh data lifting a vehicle above the threshold is an add.
    @Test func updateCrossingAboveThresholdBecomesAnAdd() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)
        _ = visibility.setFilter(RentalRangeFilter(minimumRangeMeters: 8047))
        _ = visibility.apply(snapshot(added: [try RentalFixtures.vehicle(id: "v1", rangeMeters: 3_000)]))

        let changes = visibility.apply(snapshot(updated: [try RentalFixtures.vehicle(id: "v1", rangeMeters: 12_000)]))
        #expect(changes.added.map(\.id) == ["v1"])
        #expect(changes.updated.isEmpty)
    }

    @Test func updateStayingInvisibleChangesNothing() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)
        _ = visibility.setFilter(RentalRangeFilter(minimumRangeMeters: 8047))
        _ = visibility.apply(snapshot(added: [try RentalFixtures.vehicle(id: "v1", rangeMeters: 1_000)]))

        #expect(visibility.apply(snapshot(updated: [try RentalFixtures.vehicle(id: "v1", rangeMeters: 2_000)])).isEmpty)
    }

    // MARK: - Filter changes

    @Test func raisingTheThresholdHidesShortRangeVehicles() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)
        _ = visibility.apply(snapshot(added: [
            try RentalFixtures.vehicle(id: "near", rangeMeters: 3_000),
            try RentalFixtures.vehicle(id: "far", rangeMeters: 12_000)
        ]))

        let changes = visibility.setFilter(RentalRangeFilter(minimumRangeMeters: 8047))
        #expect(changes.removed == ["near"])
        #expect(changes.added.isEmpty)
    }

    /// The whole point of the cache: lowering the threshold restores vehicles
    /// without waiting for a refetch, because the source will not re-add them.
    @Test func loweringTheThresholdRestoresFromCache() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)
        _ = visibility.apply(snapshot(added: [
            try RentalFixtures.vehicle(id: "near", rangeMeters: 3_000),
            try RentalFixtures.vehicle(id: "far", rangeMeters: 12_000)
        ]))
        _ = visibility.setFilter(RentalRangeFilter(minimumRangeMeters: 8047))

        let changes = visibility.setFilter(.any)
        #expect(changes.added.map(\.id) == ["near"])
        #expect(changes.removed.isEmpty)
    }

    @Test func settingTheSameFilterChangesNothing() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)
        _ = visibility.apply(snapshot(added: [try RentalFixtures.vehicle(id: "v1", rangeMeters: 3_000)]))
        _ = visibility.setFilter(RentalRangeFilter(minimumRangeMeters: 8047))

        #expect(visibility.setFilter(RentalRangeFilter(minimumRangeMeters: 8047)).isEmpty)
    }

    /// Fail-open under a filter change too: stations and pedal bikes never leave.
    @Test func raisingTheThresholdKeepsStationsAndPedalBikes() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(bikes)
        _ = visibility.apply(snapshot(added: [
            try RentalFixtures.station(id: "s1"),
            try RentalFixtures.pedalBike(id: "b1")
        ]))

        #expect(visibility.setFilter(RentalRangeFilter(minimumRangeMeters: 24_140)).isEmpty)
    }

    // MARK: - Form factor changes

    @Test func narrowingFormFactorsPrunes() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters.union(bikes))
        _ = visibility.apply(snapshot(added: [
            try RentalFixtures.vehicle(id: "v1", formFactor: "SCOOTER"),
            try RentalFixtures.vehicle(id: "b1", formFactor: "BICYCLE")
        ]))

        let changes = visibility.setFormFactors(scooters)
        #expect(changes.removed == ["b1"])
    }

    @Test func wideningFormFactorsRestoresFromCache() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)
        _ = visibility.apply(snapshot(added: [
            try RentalFixtures.vehicle(id: "v1", formFactor: "SCOOTER"),
            try RentalFixtures.vehicle(id: "b1", formFactor: "BICYCLE")
        ]))

        let changes = visibility.setFormFactors(scooters.union(bikes))
        #expect(changes.added.map(\.id) == ["b1"])
    }

    @Test func clearingFormFactorsRemovesEverything() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)
        _ = visibility.apply(snapshot(added: [
            try RentalFixtures.vehicle(id: "v1"),
            try RentalFixtures.vehicle(id: "v2")
        ]))

        let changes = visibility.setFormFactors([])
        #expect(changes.removed == ["v1", "v2"])
    }

    /// Wholesale recomputations sort by id, matching `VehicleRentalSource`'s own
    /// convention, so the emitted changes are reproducible.
    @Test func wholesaleChangesAreSortedByIdentifier() throws {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)
        _ = visibility.apply(snapshot(added: [
            try RentalFixtures.vehicle(id: "zebra", rangeMeters: 1_000),
            try RentalFixtures.vehicle(id: "alpha", rangeMeters: 1_000),
            try RentalFixtures.vehicle(id: "middle", rangeMeters: 1_000)
        ]))

        let changes = visibility.setFilter(RentalRangeFilter(minimumRangeMeters: 8047))
        #expect(changes.removed == ["alpha", "middle", "zebra"])
    }

    @Test func exposesCurrentFormFactorsAndFilter() {
        var visibility = RentalVisibility()
        _ = visibility.setFormFactors(scooters)
        _ = visibility.setFilter(RentalRangeFilter(minimumRangeMeters: 5_000))

        #expect(visibility.formFactors == scooters)
        #expect(visibility.filter == RentalRangeFilter(minimumRangeMeters: 5_000))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
set -o pipefail
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17 Pro' 2>&1 | tail -20
```

Expected: **build FAILS** with "cannot find 'RentalVisibility' in scope".

- [ ] **Step 3: Write the minimal implementation**

Create `OBAKit/Mapping/Layers/RentalVisibility.swift`:

```swift
//
//  RentalVisibility.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OTPKit

/// Which delivered rentals belong on the map.
///
/// Holds every entity `VehicleRentalSource` has delivered for the current viewport
/// — not just the visible ones — so relaxing a filter restores vehicles from cache
/// instead of waiting for a refetch. The source emits only diffs, so an entity
/// dropped for being under threshold would otherwise never come back.
///
/// Memory stays bounded without extra work: the source replaces its delivered set
/// wholesale on each fetch and reports everything absent as removed, so this cache
/// tracks the padded viewport rather than growing across a session.
///
/// No MapKit and no async: every mutation returns the exact changes to apply.
struct RentalVisibility {

    /// What the map must do to catch up with a mutation.
    struct Changes: Equatable {
        var added: [VehicleRental] = []
        var removed: [VehicleRental.ID] = []
        var updated: [VehicleRental] = []

        var isEmpty: Bool { added.isEmpty && removed.isEmpty && updated.isEmpty }
    }

    private var cache: [VehicleRental.ID: VehicleRental] = [:]
    private var visibleIDs: Set<VehicleRental.ID> = []

    private(set) var formFactors: Set<VehicleFormFactor> = []
    private(set) var filter: RentalRangeFilter = .any

    /// With no form factors selected, every layer is off and nothing is visible.
    private func isVisible(_ rental: VehicleRental) -> Bool {
        !formFactors.isEmpty && rental.matches(formFactors: formFactors) && filter.allows(rental)
    }

    // MARK: - Snapshot application

    mutating func apply(_ snapshot: VehicleRentalSnapshot) -> Changes {
        var changes = Changes()

        for id in snapshot.removed {
            cache.removeValue(forKey: id)
            if visibleIDs.remove(id) != nil {
                changes.removed.append(id)
            }
        }

        for rental in snapshot.added where cache[rental.id] == nil {
            cache[rental.id] = rental
            if isVisible(rental) {
                visibleIDs.insert(rental.id)
                changes.added.append(rental)
            }
        }

        for rental in snapshot.updated {
            cache[rental.id] = rental
            // An update that crosses the visibility boundary is an add or a
            // removal — never an update. Emitting it as an update would leave the
            // map showing a vehicle the rider has filtered out.
            switch (visibleIDs.contains(rental.id), isVisible(rental)) {
            case (true, true):
                changes.updated.append(rental)
            case (true, false):
                visibleIDs.remove(rental.id)
                changes.removed.append(rental.id)
            case (false, true):
                visibleIDs.insert(rental.id)
                changes.added.append(rental)
            case (false, false):
                break
            }
        }

        return changes
    }

    // MARK: - Selection changes

    mutating func setFormFactors(_ formFactors: Set<VehicleFormFactor>) -> Changes {
        guard formFactors != self.formFactors else { return Changes() }
        self.formFactors = formFactors
        return reconcile()
    }

    mutating func setFilter(_ filter: RentalRangeFilter) -> Changes {
        guard filter != self.filter else { return Changes() }
        self.filter = filter
        return reconcile()
    }

    /// Recomputes visibility across the whole cache. Sorted by id so the emitted
    /// changes are deterministic, mirroring `VehicleRentalSource`'s own convention
    /// of sorting its removed array.
    private mutating func reconcile() -> Changes {
        var changes = Changes()

        for id in cache.keys.sorted() {
            guard let rental = cache[id] else { continue }

            switch (visibleIDs.contains(id), isVisible(rental)) {
            case (true, false):
                visibleIDs.remove(id)
                changes.removed.append(id)
            case (false, true):
                visibleIDs.insert(id)
                changes.added.append(rental)
            case (true, true), (false, false):
                break
            }
        }

        return changes
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
set -o pipefail
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17 Pro' 2>&1 | tail -20
xcodebuild test-without-building -only-testing:OBAKitTests/RentalVisibilityTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17 Pro' 2>&1 | tail -20
```

Expected: PASS, **19 tests executed**.

- [ ] **Step 5: Lint and commit**

```bash
scripts/swiftlint.sh
git add OBAKit/Mapping/Layers/RentalVisibility.swift \
        OBAKitTests/Mapping/RentalVisibilityTests.swift
git commit -m "Add RentalVisibility: cache delivered rentals and diff visibility"
```

---

## Task 5: Persist the threshold on MapRegionManager

**Files:**
- Modify: `OBAKit/Mapping/Layers/MapLayer.swift` (append to the `Notification.Name` extension)
- Modify: `OBAKit/Mapping/MapRegionManager.swift` (add property near line 320; edit `mapLayersDifferFromDefaults` line 329 and `resetMapLayersToDefaults` line 334)
- Modify: `OBAKit/Analytics/Analytics.swift` (add label after `rentalPlanTripTapped`, line 66)
- Test: `OBAKitTests/Mapping/MapRegionManagerRentalFilterTests.swift`

**Interfaces:**
- Consumes: `RentalRangeFilter` (Task 1).
- Produces:
  - `MapRegionManager.rentalMinimumRangeDefaultsKey: String` (static)
  - `MapRegionManager.rentalRangeFilter: RentalRangeFilter` (get/set, persists + posts + reports analytics)
  - `Notification.Name.rentalRangeFilterDidChange`
  - `AnalyticsLabels.rentalRangeFilterChanged`

- [ ] **Step 1: Write the failing test**

Create `OBAKitTests/Mapping/MapRegionManagerRentalFilterTests.swift`. It inherits `OBATestCase` for the per-instance `UserDefaults` domain — never `UserDefaults.standard`, since Swift Testing runs suites concurrently in one process.

```swift
//
//  MapRegionManagerRentalFilterTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Persistence for the shared rental minimum-range threshold. It lives on
/// `MapRegionManager` beside the per-layer enablement so the Map sheet's Reset
/// affordance covers it without new machinery.
///
/// Inherits `OBATestCase` for its per-instance `UserDefaults` domain: Swift Testing
/// runs suites concurrently within one process, so isolation has to come from the
/// fixture rather than from the schedule.
@MainActor
@Suite(.serialized)
final class MapRegionManagerRentalFilterTests: OBATestCase {

    private var manager: MapRegionManager!

    override init() async throws {
        try await super.init()
        let queue = OperationQueue()
        let dataLoader = MockDataLoader(testName: name)
        manager = MapRegionManager(application: buildApplication(queue: queue, dataLoader: dataLoader))
    }

    @Test func defaultsToAny() {
        #expect(manager.rentalRangeFilter == .any)
        #expect(manager.rentalRangeFilter.isActive == false)
    }

    @Test func persistsTheThreshold() {
        manager.rentalRangeFilter = RentalRangeFilter(minimumRangeMeters: 8047)
        #expect(manager.rentalRangeFilter.minimumRangeMeters == 8047)
    }

    /// Asserts the write lands in the suite's scratch domain. This depends on
    /// `buildApplication` configuring the app with `OBATestCase.userDefaults` —
    /// check `OBATestCase.buildApplication(queue:dataLoader:)` if it fails, and
    /// read through `manager.rentalRangeFilter` instead if the app owns a
    /// different domain.
    @Test func writesThroughToUserDefaults() {
        manager.rentalRangeFilter = RentalRangeFilter(minimumRangeMeters: 8047)
        let stored = userDefaults.integer(forKey: MapRegionManager.rentalMinimumRangeDefaultsKey)
        #expect(stored == 8047)
    }

    @Test func postsOnChange() async {
        var posted = false
        let token = NotificationCenter.default.addObserver(
            forName: .rentalRangeFilterDidChange, object: nil, queue: nil
        ) { _ in posted = true }
        defer { NotificationCenter.default.removeObserver(token) }

        manager.rentalRangeFilter = RentalRangeFilter(minimumRangeMeters: 8047)
        #expect(posted)
    }

    /// A redundant write must not post — the coordinator would refilter for nothing.
    @Test func doesNotPostWhenUnchanged() {
        manager.rentalRangeFilter = RentalRangeFilter(minimumRangeMeters: 8047)

        var posted = false
        let token = NotificationCenter.default.addObserver(
            forName: .rentalRangeFilterDidChange, object: nil, queue: nil
        ) { _ in posted = true }
        defer { NotificationCenter.default.removeObserver(token) }

        manager.rentalRangeFilter = RentalRangeFilter(minimumRangeMeters: 8047)
        #expect(posted == false)
    }

    /// An active filter is a difference from defaults, so Reset must be offered
    /// even when every layer toggle is untouched.
    @Test func activeFilterCountsAsDifferingFromDefaults() {
        #expect(manager.mapLayersDifferFromDefaults == false)
        manager.rentalRangeFilter = RentalRangeFilter(minimumRangeMeters: 8047)
        #expect(manager.mapLayersDifferFromDefaults)
    }

    @Test func resetClearsTheFilter() {
        manager.rentalRangeFilter = RentalRangeFilter(minimumRangeMeters: 8047)
        manager.resetMapLayersToDefaults()
        #expect(manager.rentalRangeFilter == .any)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
set -o pipefail
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17 Pro' 2>&1 | tail -20
```

Expected: **build FAILS** with "value of type 'MapRegionManager' has no member 'rentalRangeFilter'".

- [ ] **Step 3: Add the notification name**

In `OBAKit/Mapping/Layers/MapLayer.swift`, inside the existing `extension Notification.Name`, append after `mapLayerEnabledStateDidChange`:

```swift
    /// Posted when the shared rental minimum-range filter changes. Lets
    /// `MapViewController` push the new value into the rental coordinator without
    /// `MapRegionManager` needing to know the coordinator exists.
    public static let rentalRangeFilterDidChange = Notification.Name("OBARentalRangeFilterDidChange")
```

- [ ] **Step 4: Add the analytics label**

In `OBAKit/Analytics/Analytics.swift`, after the `rentalPlanTripTapped` declaration:

```swift
    /// Label used when the rental minimum-range filter changes. Value: the
    /// threshold in meters, or "0" for no minimum.
    @objc public static let rentalRangeFilterChanged = "Rental Range Filter Changed"
```

- [ ] **Step 5: Add the property to MapRegionManager**

In `OBAKit/Mapping/MapRegionManager.swift`, insert immediately after `setMapLayerEnabled(_:id:)` (which ends at line 320) and before `enabledMapLayerCount`:

```swift
    /// The UserDefaults key persisting the shared rental minimum-range threshold.
    static let rentalMinimumRangeDefaultsKey = "mapLayer.rentals.minimumRangeMeters"

    /// The minimum-range filter shared by the Bikes and Scooters layers — one
    /// threshold, not one per layer.
    ///
    /// It lives here beside the per-layer enablement so `mapLayersDifferFromDefaults`
    /// and `resetMapLayersToDefaults()` cover it, which is what makes the Map
    /// sheet's Reset button honest. No `register(defaults:)` is needed: an unset
    /// key reads as 0, which is exactly `.any`.
    var rentalRangeFilter: RentalRangeFilter {
        get {
            RentalRangeFilter(
                minimumRangeMeters: application.userDefaults.integer(forKey: Self.rentalMinimumRangeDefaultsKey)
            )
        }
        set {
            guard rentalRangeFilter != newValue else { return }
            application.userDefaults.set(newValue.minimumRangeMeters, forKey: Self.rentalMinimumRangeDefaultsKey)

            NotificationCenter.default.post(name: .rentalRangeFilterDidChange, object: nil)
            application.analytics?.reportEvent(
                pageURL: "app://localhost/map",
                label: AnalyticsLabels.rentalRangeFilterChanged,
                value: String(newValue.minimumRangeMeters)
            )
        }
    }
```

- [ ] **Step 6: Fold the filter into reset and differs-from-defaults**

Replace `mapLayersDifferFromDefaults` (line ~329) with:

```swift
    /// True when any layer's on/off state differs from its default, or the rental
    /// range filter is active — drives the Map sheet's Reset affordance.
    public var mapLayersDifferFromDefaults: Bool {
        if rentalRangeFilter != .any { return true }
        return mapLayers.contains { isMapLayerEnabled(id: $0.id) != $0.isEnabledByDefault }
    }
```

Replace `resetMapLayersToDefaults()` (line ~334) with:

```swift
    /// Restores every registered layer to its default on/off state, and clears the
    /// rental range filter.
    public func resetMapLayersToDefaults() {
        for layer in mapLayers {
            setMapLayerEnabled(layer.isEnabledByDefault, id: layer.id)
        }
        rentalRangeFilter = .any
    }
```

- [ ] **Step 7: Run the test to verify it passes**

```bash
set -o pipefail
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17 Pro' 2>&1 | tail -20
xcodebuild test-without-building -only-testing:OBAKitTests/MapRegionManagerRentalFilterTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17 Pro' 2>&1 | tail -20
```

Expected: PASS, **7 tests executed**.

- [ ] **Step 8: Lint and commit**

```bash
scripts/swiftlint.sh
git add OBAKit/Mapping/MapRegionManager.swift \
        OBAKit/Mapping/Layers/MapLayer.swift \
        OBAKit/Analytics/Analytics.swift \
        OBAKitTests/Mapping/MapRegionManagerRentalFilterTests.swift
git commit -m "Persist the rental range filter alongside map layer preferences"
```

---

## Task 6: Fuel label on the annotation view

**Files:**
- Modify: `OBAKit/Mapping/Layers/RentalAnnotation.swift` (add a property)
- Modify: `OBAKit/Mapping/Layers/RentalAnnotationView.swift` (add the label; extend `configure()` and `prepareForReuse()`)
- Test: `OBAKitTests/Mapping/RentalAnnotationViewTests.swift`

**Interfaces:**
- Consumes: `RentalFormat.fuelLabelText(for:)` (Task 3), `RentalFixtures` (Task 1).
- Produces: `RentalAnnotation.showsFuelLabel: Bool` (default `false`); `RentalAnnotationView.fuelLabel: UILabel` (internal, for tests).

**Before starting — measure the geometry.** Apple documents neither what occupies `MKMarkerAnnotationView.bounds` nor its default `centerOffset`, so the constant below is an intent, not a guarantee. Add a temporary `print("bounds=\(bounds) centerOffset=\(centerOffset)")` at the end of `configure()`, run the app on the simulator with the Bikes layer on, read the values, then remove the print. If the balloon's tip is not at `bounds.maxY`, adjust the `constant:` on the top constraint accordingly and note the real value in a comment.

- [ ] **Step 1: Write the failing test**

Create `OBAKitTests/Mapping/RentalAnnotationViewTests.swift`:

```swift
//
//  RentalAnnotationViewTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Testing
import UIKit
import OTPKit
@testable import OBAKit

/// The fuel figure rendered beneath a rental marker. Its visibility is driven by
/// `RentalAnnotation.showsFuelLabel` rather than by the view reading the viewport,
/// because the layer's dequeue path has no access to map state.
@MainActor
@Suite(.serialized)
final class RentalAnnotationViewTests {

    private func view(for rental: VehicleRental, showsFuelLabel: Bool) -> RentalAnnotationView {
        let annotation = RentalAnnotation(rental: rental)
        annotation.showsFuelLabel = showsFuelLabel
        return RentalAnnotationView(annotation: annotation, reuseIdentifier: nil)
    }

    @Test func showsPercentWhenGatedOn() throws {
        let subject = view(for: try RentalFixtures.vehicle(batteryPercent: 0.62), showsFuelLabel: true)

        #expect(subject.fuelLabel.text == "62%")
        #expect(subject.fuelLabel.isHidden == false)
    }

    /// The zoom gate hides the label, but the text stays correct so re-showing it
    /// costs nothing.
    @Test func hidesLabelWhenGatedOff() throws {
        let subject = view(for: try RentalFixtures.vehicle(batteryPercent: 0.62), showsFuelLabel: false)
        #expect(subject.fuelLabel.isHidden)
    }

    @Test func hidesLabelWhenThereIsNoFuelData() throws {
        let subject = view(for: try RentalFixtures.vehicle(rangeMeters: nil, batteryPercent: nil), showsFuelLabel: true)

        #expect(subject.fuelLabel.text == nil)
        #expect(subject.fuelLabel.isHidden)
    }

    @Test func hidesLabelForStations() throws {
        let subject = view(for: try RentalFixtures.station(), showsFuelLabel: true)
        #expect(subject.fuelLabel.isHidden)
    }

    @Test func labelIsPurpleWhenOperative() throws {
        let subject = view(for: try RentalFixtures.vehicle(batteryPercent: 0.62, operative: true), showsFuelLabel: true)
        #expect(subject.fuelLabel.textColor == .rentalPurple)
    }

    @Test func labelIsGrayWhenNotOperative() throws {
        let subject = view(for: try RentalFixtures.vehicle(batteryPercent: 0.62, operative: false), showsFuelLabel: true)
        #expect(subject.fuelLabel.textColor == .systemGray)
    }

    /// A visual-clutter rule must not cost a VoiceOver user information: the fuel
    /// figure is announced even when the label is hidden by zoom.
    @Test func accessibilityLabelCarriesFuelEvenWhenHidden() throws {
        let subject = view(for: try RentalFixtures.vehicle(batteryPercent: 0.62), showsFuelLabel: false)

        let label = try #require(subject.accessibilityLabel)
        #expect(label.contains("62%"))
    }

    @Test func accessibilityLabelIncludesTheDisplayLabel() throws {
        let rental = try RentalFixtures.vehicle(batteryPercent: 0.62)
        let subject = view(for: rental, showsFuelLabel: true)

        let label = try #require(subject.accessibilityLabel)
        #expect(label.contains(rental.displayLabel))
    }

    /// The child label must not be its own element, or VoiceOver announces the
    /// figure twice.
    @Test func childLabelIsNotAnAccessibilityElement() throws {
        let subject = view(for: try RentalFixtures.vehicle(batteryPercent: 0.62), showsFuelLabel: true)
        #expect(subject.fuelLabel.isAccessibilityElement == false)
    }

    /// `MKAnnotationView.prepareForReuse()` does nothing by default, so subclass
    /// state that isn't reset by hand leaks into the next annotation.
    @Test func reuseClearsTheLabel() throws {
        let subject = view(for: try RentalFixtures.vehicle(batteryPercent: 0.62), showsFuelLabel: true)
        subject.prepareForReuse()

        #expect(subject.fuelLabel.text == nil)
        #expect(subject.fuelLabel.isHidden)
    }

    /// Re-assigning the annotation is how the coordinator pushes a new gate value.
    @Test func reassigningAnnotationRefreshesTheLabel() throws {
        let subject = view(for: try RentalFixtures.vehicle(batteryPercent: 0.62), showsFuelLabel: false)
        #expect(subject.fuelLabel.isHidden)

        let annotation = try #require(subject.annotation as? RentalAnnotation)
        annotation.showsFuelLabel = true
        subject.annotation = annotation

        #expect(subject.fuelLabel.isHidden == false)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
set -o pipefail
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17 Pro' 2>&1 | tail -20
```

Expected: **build FAILS** with "value of type 'RentalAnnotation' has no member 'showsFuelLabel'" and "...'RentalAnnotationView' has no member 'fuelLabel'".

- [ ] **Step 3: Add the annotation flag**

In `OBAKit/Mapping/Layers/RentalAnnotation.swift`, add after the `subtitle` computed property:

```swift
    /// Whether the view should render its fuel label.
    ///
    /// Set by `RentalLayerCoordinator` from the current zoom. It lives on the
    /// annotation rather than the view because `RentalMapLayer.annotationView(for:)`
    /// only dequeues a view and has no access to viewport state.
    public var showsFuelLabel: Bool = false
```

- [ ] **Step 4: Add the label to the annotation view**

In `OBAKit/Mapping/Layers/RentalAnnotationView.swift`, add the stored property to `RentalAnnotationView` before `public override var annotation`:

```swift
    /// The fuel figure rendered beneath the balloon. A plain subview, so it does
    /// not participate in MapKit's marker collision logic — `collisionMode`
    /// interprets a frame derived from this view's own bounds, and the label is
    /// drawn outside them. Some overlap in an unusually dense block is accepted.
    let fuelLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.isHidden = true

        // Start from a preferred font so Dynamic Type applies, then add weight.
        let base = UIFont.preferredFont(forTextStyle: .caption1)
        let descriptor = base.fontDescriptor.withSymbolicTraits(.traitBold) ?? base.fontDescriptor
        label.font = UIFont(descriptor: descriptor, size: 0)
        label.adjustsFontForContentSizeCategory = true

        // A white halo keeps the text legible over satellite basemaps.
        label.layer.shadowColor = UIColor.white.cgColor
        label.layer.shadowRadius = 2
        label.layer.shadowOpacity = 1
        label.layer.shadowOffset = .zero

        // The view composes its own accessibility label; a second element here
        // would make VoiceOver announce the figure twice.
        label.isAccessibilityElement = false

        return label
    }()
```

In `init(annotation:reuseIdentifier:)`, after `titleVisibility = .hidden` and before `configure()`:

```swift
        // The label sits outside bounds, so it must not be clipped.
        clipsToBounds = false
        addSubview(fuelLabel)
        NSLayoutConstraint.activate([
            fuelLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            fuelLabel.topAnchor.constraint(equalTo: bottomAnchor, constant: 1)
        ])
```

Replace the body of `configure()` with:

```swift
    private func configure() {
        guard let rentalAnnotation = annotation as? RentalAnnotation else { return }
        let rental = rentalAnnotation.rental

        markerTintColor = rental.isOperative ? .rentalPurple : .systemGray

        switch rental {
        case .station(let station):
            glyphImage = nil
            if let available = station.vehiclesAvailableCount {
                glyphText = String(available)
            } else {
                glyphText = nil
                glyphImage = UIImage(systemName: "bicycle")
            }
        case .vehicle(let vehicle):
            glyphText = nil
            glyphImage = UIImage(systemName: Self.glyphName(for: vehicle.vehicleType?.formFactor))
        }

        let fuelText = RentalFormat.fuelLabelText(for: rental)
        fuelLabel.text = fuelText
        fuelLabel.textColor = rental.isOperative ? .rentalPurple : .systemGray
        fuelLabel.isHidden = fuelText == nil || !rentalAnnotation.showsFuelLabel

        // VoiceOver ignores the zoom gate: a visual-density rule must not cost a
        // VoiceOver user the fuel figure.
        accessibilityLabel = [rental.displayLabel, rentalAnnotation.subtitle, fuelText]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
```

Extend `prepareForReuse()`:

```swift
    public override func prepareForReuse() {
        super.prepareForReuse()
        clusteringIdentifier = "rentals"
        displayPriority = .defaultLow
        // MKAnnotationView's default implementation does nothing, so subclass
        // state that isn't reset here leaks into the next annotation.
        fuelLabel.text = nil
        fuelLabel.isHidden = true
    }
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
set -o pipefail
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17 Pro' 2>&1 | tail -20
xcodebuild test-without-building -only-testing:OBAKitTests/RentalAnnotationViewTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17 Pro' 2>&1 | tail -20
```

Expected: PASS, **12 tests executed**.

- [ ] **Step 6: Lint and commit**

```bash
scripts/swiftlint.sh
git add OBAKit/Mapping/Layers/RentalAnnotation.swift \
        OBAKit/Mapping/Layers/RentalAnnotationView.swift \
        OBAKitTests/Mapping/RentalAnnotationViewTests.swift
git commit -m "Render battery percent or range beneath rental markers"
```

---

## Task 7: Adopt RentalVisibility in the coordinator

No new tests: with `RentalVisibility` extracted, what remains here is `MKMapView` plumbing behind a 250 ms debounce and an `AsyncStream`. The logic is covered by `RentalVisibilityTests`. Verification is that every existing suite still passes plus a manual check on the simulator.

**Files:**
- Modify: `OBAKit/Mapping/Layers/RentalLayerCoordinator.swift`

**Interfaces:**
- Consumes: `RentalVisibility` (Task 4), `RentalRangeFilter` (Task 1), `RentalAnnotation.showsFuelLabel` (Task 6).
- Produces: `RentalLayerCoordinator.setRangeFilter(_ filter: RentalRangeFilter)`.

- [ ] **Step 1: Replace the annotation bookkeeping**

In `OBAKit/Mapping/Layers/RentalLayerCoordinator.swift`, replace the `annotations` stored property declaration with:

```swift
    /// Decides which delivered rentals belong on the map. All the caching and
    /// diffing lives here; this class only applies the result to the map view.
    private var visibility = RentalVisibility()

    /// The annotations currently on the map, by entity id.
    private var annotations: [VehicleRental.ID: RentalAnnotation] = [:]

    /// Visible-map-rect height (in map points) at or below which fuel labels
    /// render. Tighter than the layer's own 20,000-point zoom window because the
    /// labels are subviews and don't participate in MapKit's collision logic, so
    /// they need more room than the markers do. At latitude 47.6 there are 9.9464
    /// map points per metre, making this an 804 m-tall viewport — a few blocks.
    private static let fuelLabelMaxVisibleHeight = 8_000.0

    private var showsFuelLabels = false
```

- [ ] **Step 2: Route layer and filter changes through RentalVisibility**

Replace `setLayer(id:enabled:formFactors:)` with:

```swift
    func setLayer(id: String, enabled: Bool, formFactors: Set<VehicleFormFactor>) {
        if enabled {
            enabledLayerFactors[id] = formFactors
        } else {
            enabledLayerFactors.removeValue(forKey: id)
        }

        let factors = combinedFormFactors
        apply(visibility.setFormFactors(factors))

        let mapRect = lastMapRect
        Task {
            if factors.isEmpty {
                await source.reset()
            } else {
                await source.setFormFactors(factors)
                // Re-prime the viewport: after a reset (all layers off) the source
                // has no viewport to refetch with. Redundant calls coalesce into
                // one fetch, so this is safe to do unconditionally.
                if let mapRect {
                    await source.setViewport(Self.boundingBox(for: mapRect))
                }
            }
        }
    }

    /// Applies a new minimum-range threshold. Purely client-side: the entities are
    /// already cached, so relaxing the threshold restores vehicles with no refetch.
    func setRangeFilter(_ filter: RentalRangeFilter) {
        apply(visibility.setFilter(filter))
    }
```

- [ ] **Step 3: Split snapshot handling from map application**

Replace `private func apply(_ snapshot: VehicleRentalSnapshot)` with these two methods:

```swift
    private func apply(_ snapshot: VehicleRentalSnapshot) {
        lastSnapshotAt = snapshot.fetchedAt
        setAvailability(.available)

        if !snapshot.partialErrors.isEmpty {
            Logger.info("Rental fetch partial errors: \(snapshot.partialErrors.joined(separator: "; "))")
        }

        apply(visibility.apply(snapshot))
    }

    /// Translates a visibility diff into map view operations. The only place this
    /// class touches annotations.
    private func apply(_ changes: RentalVisibility.Changes) {
        guard let mapView, !changes.isEmpty else { return }

        var removed: [RentalAnnotation] = []
        for id in changes.removed {
            if let annotation = annotations.removeValue(forKey: id) {
                removed.append(annotation)
            }
        }
        mapView.removeAnnotations(removed)

        for rental in changes.updated {
            guard let annotation = annotations[rental.id] else { continue }
            annotation.update(with: rental)
            // Re-assigning the annotation re-runs the view's configure() so glyphs
            // (availability counts), tint (operative state), and the fuel label
            // track the data; identity is unchanged, so selection survives.
            if let view = mapView.view(for: annotation) as? RentalAnnotationView {
                view.annotation = annotation
            }
        }

        var added: [RentalAnnotation] = []
        for rental in changes.added where annotations[rental.id] == nil {
            let annotation = RentalAnnotation(rental: rental)
            annotation.showsFuelLabel = showsFuelLabels
            annotations[rental.id] = annotation
            added.append(annotation)
        }
        mapView.addAnnotations(added)
    }
```

- [ ] **Step 4: Add the fuel-label zoom gate**

Replace `viewportDidChange(_:)` with:

```swift
    /// `mapRect` is nil when the zoom gate is closed — everything is removed.
    func viewportDidChange(_ mapRect: MKMapRect?) {
        lastMapRect = mapRect
        updateFuelLabelVisibility(for: mapRect)
        guard hasEnabledLayers else { return }

        // The layer might have been dimmed by an earlier failure; a region change
        // is the retry trigger, so let the next fetch decide again.
        let boundingBox = mapRect.map(Self.boundingBox(for:))
        Task {
            await source.setViewport(boundingBox)
        }
    }

    /// Pushes the current zoom's label decision onto every annotation. Cheap: it
    /// no-ops unless the gate actually flipped.
    private func updateFuelLabelVisibility(for mapRect: MKMapRect?) {
        let shows = mapRect.map { $0.height <= Self.fuelLabelMaxVisibleHeight } ?? false
        guard shows != showsFuelLabels else { return }
        showsFuelLabels = shows

        guard let mapView else { return }
        for annotation in annotations.values {
            annotation.showsFuelLabel = shows
            if let view = mapView.view(for: annotation) as? RentalAnnotationView {
                view.annotation = annotation
            }
        }
    }
```

- [ ] **Step 5: Delete the superseded prune method**

Delete `private func pruneAnnotations(notMatching factors: Set<VehicleFormFactor>)` in its entirety — `RentalVisibility.setFormFactors(_:)` now does this job, and does it against the full cache rather than only what is on the map.

- [ ] **Step 6: Build and run the full test target**

```bash
set -o pipefail
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17 Pro' 2>&1 | tail -20
xcodebuild test-without-building -only-testing:OBAKitTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17 Pro' 2>&1 | tail -30
```

Expected: PASS, with no regressions. Record the total test count.

- [ ] **Step 7: Lint and commit**

```bash
scripts/swiftlint.sh
git add OBAKit/Mapping/Layers/RentalLayerCoordinator.swift
git commit -m "Route rental annotations through RentalVisibility"
```

---

## Task 8: Map sheet picker row

**Files:**
- Modify: `OBAKit/Mapping/Layers/MapSheetView.swift`

**Interfaces:**
- Consumes: `RentalRangePreset` (Task 2), `MapRegionManager.rentalRangeFilter` (Task 5).
- Produces: `MapSheetModel.rangeFilterPresets`, `MapSheetModel.selectedRangePresetID`, `MapSheetModel.selectRangePreset(id:)`.

- [ ] **Step 1: Add the model plumbing**

In `OBAKit/Mapping/Layers/MapSheetView.swift`, add to `MapSheetModel` after `resetToDefaults()`:

```swift
    // MARK: - Rental Range Filter

    /// Computed once per sheet presentation: the ladder involves a
    /// MeasurementFormatter and a localized string, neither worth redoing per render.
    let rangeFilterPresets = RentalRangePreset.presets()

    /// The rung to highlight. A stored value that isn't on the current ladder — the
    /// rider's locale changed since they chose it — highlights the closest rung
    /// without the stored preference being rewritten.
    var selectedRangePresetID: Int {
        RentalRangePreset.nearest(
            toMeters: mapRegionManager.rentalRangeFilter.minimumRangeMeters,
            in: rangeFilterPresets
        )?.id ?? 0
    }

    func selectRangePreset(id: Int) {
        objectWillChange.send()
        mapRegionManager.rentalRangeFilter = RentalRangeFilter(minimumRangeMeters: id)
    }
```

- [ ] **Step 2: Replace the other-modes section with one that carries the row**

In `MapSheetView.body`, replace the second `layerSection(...)` call (the `.otherModes` one) with:

```swift
                otherModesSection
```

Then add these two methods after `layerSection(title:group:)`:

```swift
    /// The non-transit section, which carries the range-filter row beneath its
    /// layer toggles. The row shows whenever a rental layer row is visible — not
    /// only when one is enabled — so it doesn't jump in and out of the sheet as the
    /// rider toggles them, and so the filter can be set before turning a layer on.
    @ViewBuilder
    private var otherModesSection: some View {
        let layers = model.visibleLayers(in: .otherModes)
        if !layers.isEmpty {
            Section(OBALoc("map_sheet.other_modes_group", value: "Other ways to get around", comment: "Map sheet group header for non-transit mobility layers")) {
                ForEach(layers, id: \.id) { layer in
                    layerRow(layer)
                }
                rangeFilterRow
            }
        }
    }

    /// `.menu` is stated explicitly rather than left to `.automatic`, which Apple
    /// documents as "based on the picker's context" — in a List that has resolved
    /// to a navigation link in some OS versions and a menu in others.
    private var rangeFilterRow: some View {
        Picker(selection: Binding(
            get: { model.selectedRangePresetID },
            set: { model.selectRangePreset(id: $0) }
        )) {
            ForEach(model.rangeFilterPresets) { preset in
                Text(preset.title).tag(preset.meters)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bolt")
                    .foregroundStyle(Color(uiColor: .rentalPurple))
                    .frame(width: 28)
                Text(OBALoc("map_sheet.minimum_range", value: "Minimum range", comment: "Map sheet row label for the rental minimum-range filter"))
            }
        }
        .pickerStyle(.menu)
    }
```

- [ ] **Step 4: Build and verify the sheet renders**

```bash
set -o pipefail
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17 Pro' 2>&1 | tail -20
```

Expected: build succeeds. Then run the app on the simulator, open the Map sheet from the basemap button, and confirm: the "Minimum range" row appears under Bikes and Scooters with a trailing value of "Any"; tapping it opens a menu with Any / 1 mi / 2 mi / 5 mi / 10 mi / 15 mi; choosing a rung updates the trailing value and makes the Reset button appear.

- [ ] **Step 5: Lint and commit**

```bash
scripts/swiftlint.sh
git add OBAKit/Mapping/Layers/MapSheetView.swift
git commit -m "Add the minimum-range row to the Map sheet"
```

---

## Task 9: Wire the filter through to the coordinator

The last connection: the Map sheet writes to `MapRegionManager`, which posts; `MapViewController` observes and pushes into the coordinator.

**Files:**
- Modify: `OBAKit/Mapping/MapViewController.swift` (add an observer beside lines 166-167)
- Modify: `OBAKit/Mapping/MapViewController+MapLayers.swift` (seed the filter; add the handler)

**Interfaces:**
- Consumes: `RentalLayerCoordinator.setRangeFilter(_:)` (Task 7), `MapRegionManager.rentalRangeFilter` (Task 5), `.rentalRangeFilterDidChange` (Task 5).
- Produces: nothing for later tasks — this is the final task.

- [ ] **Step 1: Register the observer**

In `OBAKit/Mapping/MapViewController.swift`, after line 167 (the `.mapLayerAvailabilityDidChange` registration):

```swift
        NotificationCenter.default.addObserver(self, selector: #selector(rentalRangeFilterDidChange(_:)), name: .rentalRangeFilterDidChange, object: nil)
```

- [ ] **Step 2: Seed the coordinator with the persisted filter**

In `OBAKit/Mapping/MapViewController+MapLayers.swift`, inside `configureRentalLayers()`, immediately after `rentalLayerCoordinator = coordinator`:

```swift
        // Apply a filter chosen in a previous session before the first fetch,
        // rather than one notification late.
        coordinator.setRangeFilter(mapRegionManager.rentalRangeFilter)
```

- [ ] **Step 3: Add the notification handler**

In the same file, after `mapLayerStateDidChange(_:)`:

```swift
    /// `MapViewController` is the composition root for the rental layers, so it
    /// carries the threshold from the Map sheet's write to the coordinator that
    /// acts on it. `MapRegionManager` stays unaware the coordinator exists.
    @objc func rentalRangeFilterDidChange(_ note: NSNotification) {
        rentalLayerCoordinator?.setRangeFilter(mapRegionManager.rentalRangeFilter)
    }
```

- [ ] **Step 4: Build and run the full test target**

```bash
set -o pipefail
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17 Pro' 2>&1 | tail -20
xcodebuild test-without-building -only-testing:OBAKitTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17 Pro' 2>&1 | tail -30
```

Expected: PASS, no regressions.

- [ ] **Step 5: Verify end to end on the simulator**

Run the app in a bikeshare-enabled region and confirm:

1. Turn on Scooters. Zoom in until pins appear; zoom further until fuel labels appear beneath them.
2. Set Minimum range to 5 mi. Short-range scooters disappear **without** a visible refetch flash.
3. Set it back to Any. The removed scooters **come straight back** — this is the cache doing its job; if they only reappear after a pan, `RentalVisibility` isn't being consulted.
4. Tap Reset. The threshold returns to Any and layer toggles return to their defaults.
5. Turn VoiceOver on, focus a rental pin at a zoom where labels are hidden, and confirm one announcement containing both the vehicle name and the fuel figure — no duplication.
6. Kill and relaunch the app. The chosen threshold persists.

- [ ] **Step 6: Lint and commit**

```bash
scripts/swiftlint.sh
git add OBAKit/Mapping/MapViewController.swift \
        OBAKit/Mapping/MapViewController+MapLayers.swift
git commit -m "Wire the rental range filter through to the map coordinator"
```

---

## Deferred to implementation — status at completion

1. **The label's vertical offset** — **RESOLVED.** Measured during Task 6 on
   iPhone 17 Pro / iOS 26.3: `bounds` (0, 0, 31.33, 34.94), `centerOffset`
   (0, −17.47). Since `centerOffset.y == -bounds.height/2`, MapKit places
   `bounds.maxY` at the annotation's coordinate, which is where the balloon tip
   sits — so the plan's assumption held and `constant: 1` is correct. Pinning to
   `bottomAnchor` tracks the tip as the view's height changes, making the constant
   a 1pt gap rather than a derived offset. The measurement is now recorded in a
   comment at the constraint so it needn't be re-derived.

   Caveat: measured via a hosted unit-test probe, not on a live `MKMapView`
   (simulator UI automation is unavailable on this machine). The label has still
   never been *seen* rendered on a map.

2. **VoiceOver's default derivation** — **STILL OPEN, and it is the most
   important thing left.** Assigning `accessibilityLabel` does not make a
   `UIView` an accessibility element, and Apple documents neither whether
   `MKAnnotationView` is one by default nor what it derives from the annotation's
   `title`/`subtitle`. If it is not an element, the entire VoiceOver story here —
   including the pre-existing behavior this feature had to preserve — is a no-op,
   and all twelve `RentalAnnotationViewTests` still pass. No automated test can
   close this. Focus a rental pin with VoiceOver on: expect exactly one
   announcement carrying the vehicle name, the station occupancy where
   applicable, and the fuel figure. If nothing is announced, add
   `isAccessibilityElement = true`. If the name is doubled, MapKit is composing
   its own label and the fix is to override the composition rather than append
   to it.

## Follow-up filed during the final review

A ~40-line synchronous `RentalLayerCoordinator` test — stub the one-method
`VehicleRentalService`, drop `private` from `apply(_ snapshot:)`, drive it with no
async at all. It would close two things with **no coverage at any level**: the
`Set(annotations.keys)` == visible-id-set invariant, and the
`fuelLabelMaxVisibleHeight` zoom gate. Neither is a bug today; see the spec's
Testing section for why the original "it's all behind a debounce" reasoning was
wrong.
