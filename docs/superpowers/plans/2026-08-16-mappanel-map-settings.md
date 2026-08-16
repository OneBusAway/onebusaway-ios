# MapPanel Map Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring every setting in the UIKit Map sheet — basemap, Points of Interest, layer toggles, rental range filter, reset — to the experimental SwiftUI MapPanel experience, including rental markers with client-side clustering.

**Architecture:** Three refactors make the existing layer machinery host-agnostic (`MapRegionManager` stops reading a never-laid-out `MKMapView`; `RentalLayerCoordinator` publishes models instead of writing annotations; registration moves into a shared `MapLayerRegistrar`). Two feature phases then wire `MapPanelRootView` to that machinery and add three sheet routes that reuse the already-SwiftUI `MapSheetView`, `RentalDetailView`, and `RentalClusterListView` unchanged.

**Tech Stack:** Swift 6 language mode, SwiftUI, MapKit, Combine, Swift Testing, XcodeGen, OTPKit (`VehicleRental`).

**Spec:** `docs/superpowers/specs/2026-08-16-mappanel-map-settings-design.md`

## Global Constraints

- **Swift 6 language mode with main-actor default isolation.** `OBAKitCore` pins `SWIFT_DEFAULT_ACTOR_ISOLATION` back to `nonisolated`. Five concurrency diagnostic groups are escalated to errors — a data-race warning fails the build.
- **Deployment target iOS 18.0.** `MapStyle.standard(elevation:pointsOfInterest:showsTraffic:)`, `.hybrid(...)`, and `.imagery(...)` are all iOS 17+, so all are available.
- **Tests use Swift Testing**, not XCTest: `@Suite(.serialized)`, `@Test`, `#expect`. Test names are written in backticks (`` @Test func `Does the thing`() ``). Suites needing fixtures inherit `OBATestCase` and override `init() async throws`; teardown goes in `deinit`.
- **Project generation is required before building:** `scripts/generate_project OneBusAway`. New files are picked up by XcodeGen from the directory structure — no manual project edits.
- **Build and test on iPhone 16 / iOS 26.**
- **Commit messages are a single line, no AI/Claude attribution of any kind.**
- **`RegionsService` holds delegates weakly** in an `NSHashTable`. Anything registering as a `RegionsServiceDelegate` must be strongly retained by its host or it will silently stop receiving callbacks.
- **`RegionsServiceDelegate` is an `@objc` protocol**, so conformers must subclass `NSObject`.
- **New rider-facing copy uses `OBALoc(_:value:comment:)`.** This plan introduces no new strings — every label is reused from an existing key.

## Build & test commands

Run once per session, and again after any task that adds a file:

```bash
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Per-suite test runs (used in the steps below):

```bash
xcodebuild test-without-building \
  -only-testing:OBAKitTests/<SuiteName> \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## File structure

**Created**

| File | Responsibility |
| --- | --- |
| `OBAKit/Mapping/Layers/RentalAnnotationSyncer.swift` | Mirrors `RentalLayerCoordinator.visibleRentals` onto an `MKMapView` as `RentalAnnotation`s. UIKit-only. |
| `OBAKit/Mapping/Layers/MapLayerRegistrar.swift` | Host-neutral layer registration + region-change rebuilds. Owns the `RentalLayerCoordinator`. |
| `OBAKit/Mapping/Layers/RentalMapItem.swift` | `Identifiable` enum: a single rental or a cluster of them. |
| `OBAKit/Mapping/Layers/RentalClustering.swift` | Pure grid-clustering function over rentals + viewport. |
| `OBAKit/Sheet/Root/MapPanelLayersModel.swift` | Panel-side observable: layer state, POI, badge count, clustered rental items. |
| `OBAKit/Sheet/Root/Controls/RentalMapMarker.swift` | SwiftUI markers for a single rental and for a cluster. |
| `OBAKit/ViewModels/MapViewModel/MapBaseType+MapStyle.swift` | `MapBaseType` → `MapStyle` mapping, isolated so it is testable. |

**Modified**

| File | Change |
| --- | --- |
| `OBAKit/Mapping/MapRegionManager.swift` | `currentVisibleMapRect` + `mapLayersViewportDidChange(_:)` |
| `OBAKit/Mapping/Layers/RentalLayerCoordinator.swift` | Drops `MKMapView`; publishes `visibleRentals` / `showsFuelLabels` |
| `OBAKit/Mapping/Layers/RentalMapLayer.swift` | Gains `annotationSyncer`; `mapAnnotationsWereCleared()` retargets |
| `OBAKit/Mapping/MapViewController+MapLayers.swift` | Delegates registration to `MapLayerRegistrar`; owns the syncer |
| `OBAKit/Mapping/Layers/RentalDetailViewController.swift` | `onPlanTrip` becomes optional on both SwiftUI views |
| `OBAKit/Sheet/Coordinator/SheetRoute.swift` | Three new `AppSheetRoute` cases |
| `OBAKit/Sheet/DI/AppSheetViewFactory.swift` | Branches for the new routes; takes `MapViewModel` + layers model |
| `OBAKit/Sheet/Root/MapPanelRootController.swift` | Constructs and injects `MapViewModel` + `MapPanelLayersModel` |
| `OBAKit/Sheet/Root/MapPanelRootView.swift` | Injected VMs, map style, stops gate, rentals, selection enum |
| `OBAKit/Sheet/Root/Controls/MapControlsCluster.swift` | `onOpenMapSettings` + `layerBadgeCount` |
| `OBAKit/Sheet/Root/Controls/MapTypeButton.swift` | Badge overlay; tap opens the sheet |
| `OBAKit/ViewModels/MapViewModel/MapViewModel.swift` | `toggleMapType()` deleted |

---

## Phase 1 — Host-agnostic viewport

### Task 1: `MapRegionManager` stops reading the map view for viewports

`forwardViewport(to:)` reads `mapView.visibleMapRect`, and `updateMapLayers()` is reachable only from the `MKMapView` delegate. In panel mode that map view is never added to a view hierarchy, so its `visibleMapRect` is meaningless and the delegate never fires. This task adds the seam; nothing consumes it until Task 6.

**Files:**
- Modify: `OBAKit/Mapping/MapRegionManager.swift` (`forwardViewport(to:)` / `updateMapLayers()` around line 515; `regionDidChangeAnimated` around line 1011)
- Test: `OBAKitTests/Mapping/MapLayerViewportForwardingTests.swift` (create)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `MapRegionManager.currentVisibleMapRect: MKMapRect` (`public private(set)`)
  - `MapRegionManager.mapLayersViewportDidChange(_ rect: MKMapRect)` (`public`)

- [ ] **Step 1: Write the failing test**

Create `OBAKitTests/Mapping/MapLayerViewportForwardingTests.swift`:

```swift
//
//  MapLayerViewportForwardingTests.swift
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
@testable import OBAKit
@testable import OBAKitCore

/// A layer that records every viewport it is handed, so the manager's zoom
/// gating can be asserted without a real data pipeline behind it.
@MainActor
private final class RecordingMapLayer: NSObject, MapLayer {
    let id: String
    let maxVisibleHeight: Double
    private(set) var receivedViewports: [MKMapRect?] = []

    init(id: String, maxVisibleHeight: Double) {
        self.id = id
        self.maxVisibleHeight = maxVisibleHeight
        super.init()
    }

    let title = "Recording"
    let iconName = "bus.fill"
    let tintColor: UIColor = .systemBlue
    let group: MapLayerGroup = .transit
    let isEnabledByDefault = true
    let availability: MapLayerAvailability = .available
    var zoomWindow: MapLayerZoomWindow { MapLayerZoomWindow(maxVisibleHeight: maxVisibleHeight) }
    let densityBudget = 100
    let isClusterable = false
    let refreshPolicy: MapLayerRefreshPolicy = .onViewportChange
    let staleAfter: Duration? = nil

    func annotationView(for annotation: MKAnnotation, in mapView: MKMapView) -> MKAnnotationView? { nil }
    func detailViewController(for annotation: MKAnnotation) -> UIViewController? { nil }
    func activate() {}
    func deactivate() {}
    func viewportDidChange(_ mapRect: MKMapRect?) { receivedViewports.append(mapRect) }
    func mapAnnotationsWereCleared() {}
}

/// The panel drives the layer pipeline through `mapLayersViewportDidChange(_:)`
/// because the `MKMapView` this manager owns is never laid out in panel mode.
@MainActor
@Suite(.serialized)
final class MapLayerViewportForwardingTests: OBATestCase {

    private var manager: MapRegionManager!

    override init() async throws {
        try await super.init()
        let queue = OperationQueue()
        let dataLoader = MockDataLoader(testName: name)
        manager = MapRegionManager(application: buildApplication(queue: queue, dataLoader: dataLoader))
    }

    private func rect(height: Double) -> MKMapRect {
        MKMapRect(x: 0, y: 0, width: height, height: height)
    }

    @Test func `Forwards the viewport to an enabled layer inside its zoom window`() {
        let layer = RecordingMapLayer(id: "inside", maxVisibleHeight: 20_000)
        manager.registerMapLayer(layer)
        layer.receivedViewports.removeAll()

        manager.mapLayersViewportDidChange(rect(height: 10_000))

        #expect(layer.receivedViewports.count == 1)
        #expect(layer.receivedViewports.first??.height == 10_000)
    }

    @Test func `Passes nil when the viewport is outside the zoom window`() {
        let layer = RecordingMapLayer(id: "outside", maxVisibleHeight: 20_000)
        manager.registerMapLayer(layer)
        layer.receivedViewports.removeAll()

        manager.mapLayersViewportDidChange(rect(height: 50_000))

        #expect(layer.receivedViewports.count == 1)
        #expect(layer.receivedViewports.first! == nil)
    }

    @Test func `Skips disabled layers`() {
        let layer = RecordingMapLayer(id: "disabled", maxVisibleHeight: 20_000)
        manager.registerMapLayer(layer)
        manager.setMapLayerEnabled(false, id: "disabled")
        layer.receivedViewports.removeAll()

        manager.mapLayersViewportDidChange(rect(height: 10_000))

        #expect(layer.receivedViewports.isEmpty)
    }

    /// A layer registered *after* the panel reported a viewport must be primed
    /// with that viewport, not with the never-laid-out map view's rect.
    @Test func `Stores the rect so a later registration is primed with it`() {
        manager.mapLayersViewportDidChange(rect(height: 10_000))

        let layer = RecordingMapLayer(id: "late", maxVisibleHeight: 20_000)
        manager.registerMapLayer(layer)

        #expect(manager.currentVisibleMapRect.height == 10_000)
        #expect(layer.receivedViewports.first??.height == 10_000)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: compile error — `value of type 'MapRegionManager' has no member 'mapLayersViewportDidChange'`.

- [ ] **Step 3: Add the stored viewport and the public entry point**

In `OBAKit/Mapping/MapRegionManager.swift`, add near the other layer state (beside `mapLayers`):

```swift
    /// The viewport the layer pipeline last saw.
    ///
    /// Seeded from the map view so the UIKit path is unchanged, then written by
    /// whichever host is driving. The panel must write it: the `MKMapView` this
    /// manager owns is never added to a view hierarchy in panel mode, so its
    /// `visibleMapRect` is not the viewport the rider is actually looking at.
    public private(set) var currentVisibleMapRect: MKMapRect = .world
```

In `init`, after `super.init()` and alongside the existing `mapView.mapType = userSelectedMapType` line (around line 250):

```swift
        currentVisibleMapRect = mapView.visibleMapRect
```

Replace `forwardViewport(to:)` and `updateMapLayers()` (around line 513-525) with:

```swift
    /// Feeds the current viewport to a layer, applying its zoom window: outside
    /// the window the layer receives nil and removes its annotations.
    private func forwardViewport(to layer: MapLayer) {
        let visibleRect = currentVisibleMapRect
        let insideWindow = layer.zoomWindow.contains(visibleHeight: visibleRect.height)
        layer.viewportDidChange(insideWindow ? visibleRect : nil)
    }

    /// Records a new viewport and fans it out to every enabled layer.
    ///
    /// Called by both hosts: `mapView(_:regionDidChangeAnimated:)` on the UIKit
    /// path, and `.onMapCameraChange` on the SwiftUI panel.
    public func mapLayersViewportDidChange(_ rect: MKMapRect) {
        currentVisibleMapRect = rect
        for layer in mapLayers where isMapLayerEnabled(id: layer.id) {
            forwardViewport(to: layer)
        }
    }
```

- [ ] **Step 4: Route the UIKit delegate through the new method**

In `mapView(_:regionDidChangeAnimated:)` (around line 1011), replace `updateMapLayers()` with:

```swift
        mapLayersViewportDidChange(mapView.visibleMapRect)
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests/MapLayerViewportForwardingTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: 4 tests PASS.

- [ ] **Step 6: Run the existing map suites to confirm no regression**

```bash
xcodebuild test-without-building -only-testing:OBAKitTests/MapRegionManagerTests \
  -only-testing:OBAKitTests/MapRegionManagerRentalFilterTests \
  -only-testing:OBAKitTests/MapLayerRendererDispatchTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add OBAKit/Mapping/MapRegionManager.swift OBAKitTests/Mapping/MapLayerViewportForwardingTests.swift
git commit -m "Let any host drive map layer viewports"
```

---

## Phase 2 — Map-agnostic rentals

### Task 2: `RentalLayerCoordinator` publishes rentals instead of annotating a map

**Files:**
- Modify: `OBAKit/Mapping/Layers/RentalLayerCoordinator.swift` (whole file)
- Modify: `OBAKitTests/Mapping/RentalLayerCoordinatorTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces:
  - `RentalLayerCoordinator.init(service: VehicleRentalService, locationService: LocationService)`
  - `@Published private(set) var visibleRentals: [VehicleRental]` — sorted by `id`, deterministic
  - `@Published private(set) var showsFuelLabels: Bool`
  - `func apply(_ snapshot: VehicleRentalSnapshot)` — still non-private, for tests
  - Unchanged: `setLayer(id:enabled:formFactors:)`, `setRangeFilter(_:)`, `viewportDidChange(_:)`, `availability`, `lastSnapshotAt`, `userLocation`, `hasEnabledLayers`
  - **Removed:** `reattachAnnotations()` (moves to `RentalAnnotationSyncer` in Task 3)

- [ ] **Step 1: Rewrite the existing tests against the published array**

In `OBAKitTests/Mapping/RentalLayerCoordinatorTests.swift`, replace the `makeCoordinator` helper and the `rentalAnnotations` helper with:

```swift
    private func makeCoordinator() -> RentalLayerCoordinator {
        RentalLayerCoordinator(
            service: StubVehicleRentalService(),
            locationService: LocationService(userDefaults: UserDefaults(), locationManager: LocationManager())
        )
    }
```

Then update every test body to drop the `mapView` tuple element and assert on `coordinator.visibleRentals`. For example, `addingVehiclesRendersBothAnnotations` becomes:

```swift
    @Test func `Adding vehicles publishes both rentals`() throws {
        let coordinator = makeCoordinator()
        coordinator.setLayer(id: "scooters", enabled: true, formFactors: scooters)

        coordinator.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "near", rangeMeters: 3_000),
            try RentalFixtures.vehicle(id: "far", rangeMeters: 12_000)
        ]))

        #expect(coordinator.visibleRentals.count == 2)
    }
```

and `raisingTheThresholdHidesTheShortRangeVehicle` becomes:

```swift
    @Test func `Raising the threshold hides the short range vehicle`() throws {
        let coordinator = makeCoordinator()
        coordinator.setLayer(id: "scooters", enabled: true, formFactors: scooters)
        coordinator.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "near", rangeMeters: 3_000),
            try RentalFixtures.vehicle(id: "far", rangeMeters: 12_000)
        ]))

        coordinator.setRangeFilter(RentalRangeFilter(minimumRangeMeters: 8047))

        #expect(coordinator.visibleRentals.map(\.id) == ["far"])
    }
```

Apply the same transformation to every remaining test in the file: the `(coordinator, mapView)` tuple becomes a bare `coordinator`, and `rentalAnnotations(mapView)` becomes `coordinator.visibleRentals`. Also update the suite's doc comment — it currently says the tests drive "the actual `MKMapView`"; they now drive the published model.

Add one new test asserting the ordering contract that SwiftUI depends on:

```swift
    /// `visibleRentals` is sorted by id. `Array(dictionary.values)` has no
    /// guaranteed order, and an unstable order would reshuffle the panel's
    /// `ForEach` on every snapshot.
    @Test func `Publishes rentals sorted by id`() throws {
        let coordinator = makeCoordinator()
        coordinator.setLayer(id: "scooters", enabled: true, formFactors: scooters)

        coordinator.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "c"),
            try RentalFixtures.vehicle(id: "a"),
            try RentalFixtures.vehicle(id: "b")
        ]))

        #expect(coordinator.visibleRentals.map(\.id) == ["a", "b", "c"])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: compile error — `extra argument 'locationService' in call` / `has no member 'visibleRentals'`.

- [ ] **Step 3: Replace the map view with published state**

In `OBAKit/Mapping/Layers/RentalLayerCoordinator.swift`:

Change the class declaration to conform to `ObservableObject`:

```swift
@MainActor final class RentalLayerCoordinator: ObservableObject {
```

Replace the `private weak var mapView: MKMapView?` and `private var annotations:` declarations with:

```swift
    /// The rentals that currently belong on the map, sorted by id.
    ///
    /// Both surfaces render from this: the UIKit map through
    /// `RentalAnnotationSyncer`, the SwiftUI panel by clustering it. Sorting is
    /// not cosmetic — an unstable order reshuffles the panel's `ForEach` on
    /// every snapshot.
    @Published private(set) var visibleRentals: [VehicleRental] = []

    /// Whether the current zoom is tight enough to show fuel figures.
    @Published private(set) var showsFuelLabels = false

    /// Keyed store behind `visibleRentals`. Must stay equal to
    /// `RentalVisibility`'s visible-id set — see `applyChanges(_:)`.
    private var rentalsByID: [VehicleRental.ID: VehicleRental] = [:]

    private let locationService: LocationService
```

Replace the `userLocation` computed property:

```swift
    /// The rider's location, for walk-time estimates in detail sheets.
    var userLocation: CLLocation? {
        locationService.currentLocation
    }
```

Change the initializer:

```swift
    init(service: VehicleRentalService, locationService: LocationService) {
        self.source = VehicleRentalSource(service: service)
        self.locationService = locationService
```

(the two `Task` blocks that follow are unchanged).

Delete the `private var showsFuelLabels = false` stored property lower in the file — it is now the `@Published` above.

- [ ] **Step 4: Replace `syncMapView(with:)` with `applyChanges(_:)`**

Replace the whole `syncMapView(with:)` method with:

```swift
    /// Folds a visibility diff into `rentalsByID` and republishes.
    ///
    /// The only place this class mutates `rentalsByID` — it must keep
    /// `Set(rentalsByID.keys)` equal to `RentalVisibility`'s visible-id set. Do
    /// not add an early return that skips a branch: one would silently break
    /// that invariant and, with it, cache restore when a filter is relaxed.
    private func applyChanges(_ changes: RentalVisibility.Changes) {
        guard !changes.isEmpty else { return }

        for id in changes.removed {
            rentalsByID.removeValue(forKey: id)
        }
        for rental in changes.updated where rentalsByID[rental.id] != nil {
            rentalsByID[rental.id] = rental
        }
        for rental in changes.added {
            rentalsByID[rental.id] = rental
        }

        visibleRentals = rentalsByID.values.sorted { $0.id < $1.id }
    }
```

Update the three call sites, all of which currently read `syncMapView(with: ...)`:

- in `setLayer(id:enabled:formFactors:)`: `applyChanges(visibility.setFormFactors(factors))`
- in `setRangeFilter(_:)`: `applyChanges(visibility.setFilter(filter))`
- in `apply(_ snapshot:)`: `applyChanges(visibility.apply(snapshot))`

- [ ] **Step 5: Simplify the fuel-label gate and the failure handler**

Replace `updateFuelLabelVisibility(for:)` with:

```swift
    /// Publishes the current zoom's label decision. Cheap: `@Published` still
    /// fires on every write, so the equality guard stays.
    private func updateFuelLabelVisibility(for mapRect: MKMapRect?) {
        let shows = mapRect.map { Self.fuelLabelZoomWindow.contains(visibleHeight: $0.height) } ?? false
        guard shows != showsFuelLabels else { return }
        showsFuelLabels = shows
    }
```

In `handle(_ failure:)`, change the emptiness check:

```swift
        if visibleRentals.isEmpty {
```

Delete `reattachAnnotations()` entirely — Task 3 gives it a new home.

Finally, drop the now-unused `import MapKit`? **No** — keep it: `MKMapRect` is still used by `viewportDidChange(_:)` and `boundingBox(for:)`.

- [ ] **Step 6: Run tests to verify they pass**

```bash
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests/RentalLayerCoordinatorTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: all PASS. The build will still fail in `MapViewController+MapLayers.swift` and `RentalMapLayer.swift` — that is Task 3. If the compiler blocks the test run, complete Task 3 before running this step and commit the two together.

- [ ] **Step 7: Commit**

```bash
git add OBAKit/Mapping/Layers/RentalLayerCoordinator.swift OBAKitTests/Mapping/RentalLayerCoordinatorTests.swift
git commit -m "Publish rentals from the coordinator instead of annotating a map"
```

---

### Task 3: `RentalAnnotationSyncer` restores the UIKit map behaviour

The coordinator no longer touches `MKMapView`. This task puts that behaviour behind a dedicated type so the UIKit map is byte-for-byte unchanged for riders.

**Files:**
- Create: `OBAKit/Mapping/Layers/RentalAnnotationSyncer.swift`
- Modify: `OBAKit/Mapping/Layers/RentalMapLayer.swift` (`mapAnnotationsWereCleared()`, around line 108)
- Modify: `OBAKit/Mapping/MapViewController+MapLayers.swift` (`configureRentalLayers()`)
- Modify: `OBAKit/Mapping/MapViewController.swift` (add the stored syncer beside `rentalLayerCoordinator`, around line 717)
- Test: `OBAKitTests/Mapping/RentalAnnotationSyncerTests.swift` (create)

**Interfaces:**
- Consumes: `RentalLayerCoordinator.$visibleRentals`, `$showsFuelLabels` (Task 2).
- Produces:
  - `RentalAnnotationSyncer.init(coordinator: RentalLayerCoordinator, mapView: MKMapView)`
  - `func sync(to rentals: [VehicleRental])` — non-private, for tests
  - `func reattachAnnotations()`
  - `RentalMapLayer.annotationSyncer: RentalAnnotationSyncer?` (`weak var`)

- [ ] **Step 1: Write the failing test**

Create `OBAKitTests/Mapping/RentalAnnotationSyncerTests.swift`:

```swift
//
//  RentalAnnotationSyncerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Testing
import OTPKit
@testable import OBAKit
@testable import OBAKitCore

/// The syncer is the UIKit half of what `RentalLayerCoordinator` used to do
/// itself. Tests drive `sync(to:)` directly rather than through the Combine
/// subscription, which would need the run loop to turn.
@MainActor
@Suite(.serialized)
final class RentalAnnotationSyncerTests {

    private struct StubVehicleRentalService: VehicleRentalService {
        func fetchVehicleRentals(
            in boundingBox: VehicleRentalBoundingBox,
            formFactors: Set<VehicleFormFactor>?
        ) async throws -> VehicleRentalFetchResult {
            VehicleRentalFetchResult(rentals: [])
        }
    }

    private func makeSyncer() -> (syncer: RentalAnnotationSyncer, mapView: MKMapView) {
        let mapView = MKMapView()
        let coordinator = RentalLayerCoordinator(
            service: StubVehicleRentalService(),
            locationService: LocationService(userDefaults: UserDefaults(), locationManager: LocationManager())
        )
        return (RentalAnnotationSyncer(coordinator: coordinator, mapView: mapView), mapView)
    }

    /// `MKMapView.annotations` may include a user-location annotation, so never
    /// assert on the raw count — only on rental annotations specifically.
    private func rentalAnnotations(_ mapView: MKMapView) -> [RentalAnnotation] {
        mapView.annotations.compactMap { $0 as? RentalAnnotation }
    }

    @Test func `Adds an annotation for each new rental`() throws {
        let (syncer, mapView) = makeSyncer()

        syncer.sync(to: [
            try RentalFixtures.vehicle(id: "a"),
            try RentalFixtures.vehicle(id: "b")
        ])

        #expect(Set(rentalAnnotations(mapView).map(\.rental.id)) == ["a", "b"])
    }

    @Test func `Removes annotations for rentals that left the list`() throws {
        let (syncer, mapView) = makeSyncer()
        syncer.sync(to: [
            try RentalFixtures.vehicle(id: "a"),
            try RentalFixtures.vehicle(id: "b")
        ])

        syncer.sync(to: [try RentalFixtures.vehicle(id: "a")])

        #expect(rentalAnnotations(mapView).map(\.rental.id) == ["a"])
    }

    /// Identity must survive an update, or MapKit drops the selection and any
    /// open callout every time the feed refreshes.
    @Test func `Reuses the same annotation object when a rental updates`() throws {
        let (syncer, mapView) = makeSyncer()
        syncer.sync(to: [try RentalFixtures.vehicle(id: "a", rangeMeters: 1_000)])
        let first = try #require(rentalAnnotations(mapView).first)

        syncer.sync(to: [try RentalFixtures.vehicle(id: "a", rangeMeters: 9_000)])
        let second = try #require(rentalAnnotations(mapView).first)

        #expect(first === second)
        #expect(rentalAnnotations(mapView).count == 1)
    }

    /// Search flows call `removeAllAnnotations`; without this the syncer's
    /// bookkeeping and the map disagree forever.
    @Test func `Reattaches tracked annotations after a wholesale clear`() throws {
        let (syncer, mapView) = makeSyncer()
        syncer.sync(to: [
            try RentalFixtures.vehicle(id: "a"),
            try RentalFixtures.vehicle(id: "b")
        ])
        mapView.removeAnnotations(mapView.annotations)
        #expect(rentalAnnotations(mapView).isEmpty)

        syncer.reattachAnnotations()

        #expect(Set(rentalAnnotations(mapView).map(\.rental.id)) == ["a", "b"])
    }

    @Test func `Reattaching twice does not duplicate annotations`() throws {
        let (syncer, mapView) = makeSyncer()
        syncer.sync(to: [try RentalFixtures.vehicle(id: "a")])

        syncer.reattachAnnotations()
        syncer.reattachAnnotations()

        #expect(rentalAnnotations(mapView).count == 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: compile error — `cannot find 'RentalAnnotationSyncer' in scope`.

- [ ] **Step 3: Create the syncer**

Create `OBAKit/Mapping/Layers/RentalAnnotationSyncer.swift`:

```swift
//
//  RentalAnnotationSyncer.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import MapKit
import OTPKit

/// Mirrors `RentalLayerCoordinator.visibleRentals` onto an `MKMapView`.
///
/// The coordinator is map-agnostic so the SwiftUI panel can render the same
/// data; this type is the UIKit half that used to live inside it. Exactly one
/// syncer exists per coordinator — **not** one per layer. Bikes and Scooters
/// share a coordinator, so a per-layer syncer would add every annotation twice.
@MainActor final class RentalAnnotationSyncer {

    private weak var mapView: MKMapView?

    /// The annotations currently on the map, by entity id.
    private var annotations: [VehicleRental.ID: RentalAnnotation] = [:]

    private var showsFuelLabels = false
    private var cancellables = Set<AnyCancellable>()

    init(coordinator: RentalLayerCoordinator, mapView: MKMapView) {
        self.mapView = mapView

        coordinator.$visibleRentals
            .sink { [weak self] rentals in self?.sync(to: rentals) }
            .store(in: &cancellables)

        coordinator.$showsFuelLabels
            .sink { [weak self] shows in self?.applyFuelLabelVisibility(shows) }
            .store(in: &cancellables)
    }

    /// Brings the map in line with `rentals`, reusing annotation objects for
    /// entities that are still present.
    func sync(to rentals: [VehicleRental]) {
        guard let mapView else { return }

        let incoming = Dictionary(rentals.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })

        var removed: [RentalAnnotation] = []
        for (id, annotation) in annotations where incoming[id] == nil {
            annotations.removeValue(forKey: id)
            removed.append(annotation)
        }
        mapView.removeAnnotations(removed)

        var added: [RentalAnnotation] = []
        for rental in rentals {
            if let existing = annotations[rental.id] {
                existing.update(with: rental)
                // Re-assigning re-runs the view's configure() so glyphs, tint,
                // and the fuel label track the data; identity is unchanged, so
                // selection and any open callout survive.
                if let view = mapView.view(for: existing) as? RentalAnnotationView {
                    view.annotation = existing
                }
            } else {
                let annotation = RentalAnnotation(rental: rental)
                annotation.showsFuelLabel = showsFuelLabels
                annotations[rental.id] = annotation
                added.append(annotation)
            }
        }
        mapView.addAnnotations(added)
    }

    /// Pushes the current zoom's label decision onto every annotation without
    /// re-running a full reconfigure per marker.
    private func applyFuelLabelVisibility(_ shows: Bool) {
        showsFuelLabels = shows
        guard let mapView else { return }
        for annotation in annotations.values {
            annotation.showsFuelLabel = shows
            (mapView.view(for: annotation) as? RentalAnnotationView)?.setShowsFuelLabel(shows)
        }
    }

    /// Re-adds every tracked annotation after a wholesale `removeAllAnnotations`
    /// (search flows). `addAnnotations` ignores members already present, so this
    /// is safe to call unconditionally.
    func reattachAnnotations() {
        guard let mapView, !annotations.isEmpty else { return }
        mapView.addAnnotations(Array(annotations.values))
    }
}
```

- [ ] **Step 4: Point `RentalMapLayer` at the syncer**

In `OBAKit/Mapping/Layers/RentalMapLayer.swift`, add beside `actionsDelegate`:

```swift
    /// Re-attaches annotations after a wholesale map clear. Set by
    /// `MapViewController` at registration; nil on the SwiftUI panel, which has
    /// no `MKMapView` to re-attach to.
    weak var annotationSyncer: RentalAnnotationSyncer?
```

and replace `mapAnnotationsWereCleared()`:

```swift
    func mapAnnotationsWereCleared() {
        annotationSyncer?.reattachAnnotations()
    }
```

- [ ] **Step 5: Wire it in `MapViewController`**

In `OBAKit/Mapping/MapViewController.swift`, beside `var rentalLayerCoordinator: RentalLayerCoordinator?` (around line 717):

```swift
    /// Mirrors the coordinator's published rentals onto the map view. Held here
    /// because the coordinator no longer knows about `MKMapView`.
    var rentalAnnotationSyncer: RentalAnnotationSyncer?
```

In `OBAKit/Mapping/MapViewController+MapLayers.swift`, inside `configureRentalLayers()`, change the teardown line to also clear the syncer:

```swift
        rentalLayerCoordinator = nil
        rentalAnnotationSyncer = nil
```

change the coordinator construction:

```swift
        let coordinator = RentalLayerCoordinator(service: service, locationService: application.locationService)
        rentalLayerCoordinator = coordinator
        rentalAnnotationSyncer = RentalAnnotationSyncer(coordinator: coordinator, mapView: mapRegionManager.mapView)
```

and set the syncer on both layers alongside `actionsDelegate`:

```swift
        let bikes = RentalMapLayer.bikesLayer(coordinator: coordinator)
        bikes.actionsDelegate = self
        bikes.annotationSyncer = rentalAnnotationSyncer
        mapRegionManager.registerMapLayer(bikes)

        let scooters = RentalMapLayer.scootersLayer(coordinator: coordinator)
        scooters.actionsDelegate = self
        scooters.annotationSyncer = rentalAnnotationSyncer
        mapRegionManager.registerMapLayer(scooters)
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests/RentalAnnotationSyncerTests \
  -only-testing:OBAKitTests/RentalLayerCoordinatorTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add OBAKit/Mapping/Layers/RentalAnnotationSyncer.swift OBAKit/Mapping/Layers/RentalMapLayer.swift \
  OBAKit/Mapping/MapViewController.swift OBAKit/Mapping/MapViewController+MapLayers.swift \
  OBAKitTests/Mapping/RentalAnnotationSyncerTests.swift
git commit -m "Move rental annotation syncing out of the coordinator"
```

---

## Phase 3 — Shared registration

### Task 4: `MapLayerRegistrar`

`configureMapLayers()` lives only on `MapViewController`, which is why `mapRegionManager.mapLayers` is empty in panel mode. Extract the host-neutral half.

**Files:**
- Create: `OBAKit/Mapping/Layers/MapLayerRegistrar.swift`
- Modify: `OBAKit/Mapping/MapViewController+MapLayers.swift` (`configureMapLayers()`, `configureRentalLayers()`, `RegionsServiceDelegate` extension)
- Modify: `OBAKit/Mapping/MapViewController.swift` (store the registrar)
- Test: `OBAKitTests/Mapping/MapLayerRegistrarTests.swift` (create)

**Interfaces:**
- Consumes: `RentalLayerCoordinator.init(service:locationService:)` (Task 2), `RentalAnnotationSyncer` (Task 3).
- Produces:
  - `MapLayerRegistrar.init(application: Application, onDidConfigure: @escaping (MapLayerRegistrar) -> Void)`
  - `var rentalCoordinator: RentalLayerCoordinator?` (`public private(set)`)
  - `var rentalLayers: [RentalMapLayer]` (`public private(set)`)
  - `func configure()`

- [ ] **Step 1: Write the failing test**

Create `OBAKitTests/Mapping/MapLayerRegistrarTests.swift`:

```swift
//
//  MapLayerRegistrarTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// The registrar is the half of layer setup both map surfaces share. These
/// tests assert what it registers, not what any surface then draws.
@MainActor
@Suite(.serialized)
final class MapLayerRegistrarTests: OBATestCase {

    private var application: Application!
    private var registrar: MapLayerRegistrar!

    override init() async throws {
        try await super.init()
        let queue = OperationQueue()
        let dataLoader = MockDataLoader(testName: name)
        application = buildApplication(queue: queue, dataLoader: dataLoader)
    }

    @Test func `Registers the stops layer`() {
        registrar = MapLayerRegistrar(application: application) { _ in }
        registrar.configure()

        #expect(application.mapRegionManager.mapLayer(id: StopsMapLayer.layerID) != nil)
    }

    @Test func `Registering twice does not duplicate the stops layer`() {
        registrar = MapLayerRegistrar(application: application) { _ in }
        registrar.configure()
        registrar.configure()

        let stopsLayers = application.mapRegionManager.mapLayers.filter { $0.id == StopsMapLayer.layerID }
        #expect(stopsLayers.count == 1)
    }

    /// The region flag is product enablement and the GraphQL URL is the
    /// capability. Without both, there is no rental data source, so no rows.
    @Test func `Skips rental layers when the region has no bikeshare`() {
        registrar = MapLayerRegistrar(application: application) { _ in }
        registrar.configure()

        #expect(application.mapRegionManager.mapLayer(id: RentalMapLayer.bikesLayerID) == nil)
        #expect(application.mapRegionManager.mapLayer(id: RentalMapLayer.scootersLayerID) == nil)
        #expect(registrar.rentalCoordinator == nil)
    }

    @Test func `Registers both rental layers for a bikeshare region`() throws {
        try enableBikeshareOnCurrentRegion()

        registrar = MapLayerRegistrar(application: application) { _ in }
        registrar.configure()

        #expect(application.mapRegionManager.mapLayer(id: RentalMapLayer.bikesLayerID) != nil)
        #expect(application.mapRegionManager.mapLayer(id: RentalMapLayer.scootersLayerID) != nil)
        #expect(registrar.rentalCoordinator != nil)
        #expect(registrar.rentalLayers.count == 2)
    }

    /// A returning rider's stored threshold must reach the coordinator before
    /// the first fetch, not one notification later.
    @Test func `Applies the persisted range filter before the first fetch`() throws {
        try enableBikeshareOnCurrentRegion()
        application.mapRegionManager.rentalRangeFilter = RentalRangeFilter(minimumRangeMeters: 8047)

        registrar = MapLayerRegistrar(application: application) { _ in }
        registrar.configure()

        #expect(registrar.rentalCoordinator != nil)
    }

    @Test func `Rebuilds rental layers on reconfigure`() throws {
        try enableBikeshareOnCurrentRegion()
        registrar = MapLayerRegistrar(application: application) { _ in }
        registrar.configure()
        let first = try #require(registrar.rentalCoordinator)

        registrar.configure()
        let second = try #require(registrar.rentalCoordinator)

        #expect(first !== second)
    }

    @Test func `Notifies the host after configuring`() throws {
        var callCount = 0
        registrar = MapLayerRegistrar(application: application) { _ in callCount += 1 }

        registrar.configure()

        #expect(callCount == 1)
    }

    /// Sets `isBikeshareEnabled` and an OTP GraphQL URL on the current region so
    /// the rental branch is reachable.
    private func enableBikeshareOnCurrentRegion() throws {
        let region = try #require(application.regionsService.currentRegion)
        region.isBikeshareEnabled = true
        region.openTripPlannerURL = URL(string: "https://otp.example.com/otp/routers/default/index/graphql")
    }
}
```

> **Note for the implementer:** `Region`'s bikeshare and OTP-URL property names must be confirmed against `OBAKitCore/Models/.../Region.swift` — `isBikeshareEnabled` and `openTripPlannerGraphQLURL` are read in `configureRentalLayers()`, but the *writable* backing property may differ. If `Region` is immutable, build a fresh `Region` via `Fixtures` and set it as the current region instead. Adjust `enableBikeshareOnCurrentRegion()` accordingly; the assertions above do not change.

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: compile error — `cannot find 'MapLayerRegistrar' in scope`.

- [ ] **Step 3: Create the registrar**

Create `OBAKit/Mapping/Layers/MapLayerRegistrar.swift`:

```swift
//
//  MapLayerRegistrar.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore
import OTPKit

/// Registers the map layers both surfaces share, and rebuilds the region-scoped
/// ones when the region changes.
///
/// `MapViewController` used to own all of this, which is why
/// `MapRegionManager.mapLayers` was empty whenever the SwiftUI panel was the
/// root — and why the Map sheet showed empty groups there. The overlay layers
/// (`StopRouteFocusMapLayer`, `TripFocusMapLayer`) deliberately stay in
/// `MapViewController`: they draw `MKOverlay` polylines the panel cannot render,
/// and their region-scoped `ShapeCache` rebuild is `MKMapView`-shaped.
///
/// Subclasses `NSObject` because `RegionsServiceDelegate` is an `@objc`
/// protocol. `RegionsService` holds delegates weakly, so the host must retain
/// this object or region changes will silently stop rebuilding layers.
@MainActor public final class MapLayerRegistrar: NSObject {

    private let application: Application

    /// Called after every `configure()`, so the host can re-wire whatever it
    /// hangs off the freshly-built layers (`MapViewController` re-points
    /// `actionsDelegate` and rebuilds its annotation syncer).
    private let onDidConfigure: (MapLayerRegistrar) -> Void

    /// The engine behind the rental layers, or nil when the current region has
    /// no bikeshare.
    public private(set) var rentalCoordinator: RentalLayerCoordinator?

    /// The rental layers built by the most recent `configure()`, in registration
    /// order: Bikes then Scooters.
    public private(set) var rentalLayers: [RentalMapLayer] = []

    public init(application: Application, onDidConfigure: @escaping (MapLayerRegistrar) -> Void) {
        self.application = application
        self.onDidConfigure = onDidConfigure
        super.init()
        application.regionsService.addDelegate(self)
    }

    private var mapRegionManager: MapRegionManager { application.mapRegionManager }

    /// Registers the stops layer once, then tears down and rebuilds the
    /// region-scoped rental layers. Safe to call repeatedly.
    public func configure() {
        if mapRegionManager.mapLayer(id: StopsMapLayer.layerID) == nil {
            mapRegionManager.registerMapLayer(StopsMapLayer(manager: mapRegionManager))
        }
        configureRentalLayers()
        onDidConfigure(self)
    }

    private func configureRentalLayers() {
        // Tear down any layers built for a previous region; preferences persist.
        mapRegionManager.removeMapLayer(id: RentalMapLayer.bikesLayerID)
        mapRegionManager.removeMapLayer(id: RentalMapLayer.scootersLayerID)
        rentalCoordinator = nil
        rentalLayers = []

        // Region flag = product enablement; the GraphQL service supplies the
        // capability. Whether the server actually works is decided by the first
        // fetch, which can dim the rows at runtime.
        guard let region = application.regionsService.currentRegion,
              region.isBikeshareEnabled,
              let graphQLURL = region.openTripPlannerGraphQLURL else {
            return
        }

        let service = GraphQLAPIService(baseURL: graphQLURL)
        let coordinator = RentalLayerCoordinator(service: service, locationService: application.locationService)
        rentalCoordinator = coordinator

        // Apply a filter chosen in a previous session before the first fetch,
        // rather than one notification late.
        coordinator.setRangeFilter(mapRegionManager.rentalRangeFilter)

        let bikes = RentalMapLayer.bikesLayer(coordinator: coordinator)
        let scooters = RentalMapLayer.scootersLayer(coordinator: coordinator)
        rentalLayers = [bikes, scooters]

        mapRegionManager.registerMapLayer(bikes)
        mapRegionManager.registerMapLayer(scooters)
    }
}

// MARK: - RegionsServiceDelegate

extension MapLayerRegistrar: RegionsServiceDelegate {
    public func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        configure()
    }

    /// A regions-list refresh can flip the current region's bikeshare fields in
    /// place without changing the region identity; re-evaluate the layers.
    public func regionsService(_ service: RegionsService, updatedRegionsList regions: [Region]) {
        configure()
    }
}
```

- [ ] **Step 4: Delegate from `MapViewController`**

In `OBAKit/Mapping/MapViewController.swift`, beside `rentalLayerCoordinator` (around line 717), replace that property and add the registrar:

```swift
    /// Retained here because `RegionsService` holds its delegates weakly.
    var mapLayerRegistrar: MapLayerRegistrar?

    /// Mirrors the coordinator's published rentals onto the map view.
    var rentalAnnotationSyncer: RentalAnnotationSyncer?

    var rentalLayerCoordinator: RentalLayerCoordinator? { mapLayerRegistrar?.rentalCoordinator }
```

In `OBAKit/Mapping/MapViewController+MapLayers.swift`, replace `configureMapLayers()` and delete `configureRentalLayers()` entirely:

```swift
    /// Registers the map's toggleable layers. The shared half (stops, rentals)
    /// lives in `MapLayerRegistrar`; the overlay layers stay here because they
    /// draw `MKOverlay`s and carry a region-scoped `ShapeCache`.
    func configureMapLayers() {
        if mapLayerRegistrar == nil {
            mapLayerRegistrar = MapLayerRegistrar(application: application) { [weak self] registrar in
                self?.attachRentalLayerHost(registrar)
            }
        }
        mapLayerRegistrar?.configure()

        configureStopRouteFocusLayer()
        updateMapLayerBadge()
    }

    /// Re-points everything hanging off the freshly-built rental layers: the
    /// detail-sheet action delegate, and the `MKMapView` syncer that replaced
    /// the coordinator's own map-view writes.
    private func attachRentalLayerHost(_ registrar: MapLayerRegistrar) {
        guard let coordinator = registrar.rentalCoordinator else {
            rentalAnnotationSyncer = nil
            return
        }

        let syncer = RentalAnnotationSyncer(coordinator: coordinator, mapView: mapRegionManager.mapView)
        rentalAnnotationSyncer = syncer

        for layer in registrar.rentalLayers {
            layer.actionsDelegate = self
            layer.annotationSyncer = syncer
        }
    }
```

In the `RegionsServiceDelegate` extension at the bottom of the same file, `configureMapLayers()` stays in both methods — the registrar's own delegate handles the rentals, and these calls handle the overlay layers plus the stop-sheet dismissal. Leave `dismissStopSheetForReplacement()` exactly where it is.

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests/MapLayerRegistrarTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: 7 tests PASS.

- [ ] **Step 6: Run the full map + rental suites**

```bash
xcodebuild test-without-building \
  -only-testing:OBAKitTests/MapRegionManagerTests \
  -only-testing:OBAKitTests/MapRegionManagerRentalFilterTests \
  -only-testing:OBAKitTests/MapLayerRendererDispatchTests \
  -only-testing:OBAKitTests/MapLayerViewportForwardingTests \
  -only-testing:OBAKitTests/RentalLayerCoordinatorTests \
  -only-testing:OBAKitTests/RentalAnnotationSyncerTests \
  -only-testing:OBAKitTests/BackgroundAnnotationDeemphasisTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: all PASS. **This is the Phase 1–3 gate:** the UIKit map must be fully green before any panel work starts.

- [ ] **Step 7: Commit**

```bash
git add OBAKit/Mapping/Layers/MapLayerRegistrar.swift OBAKit/Mapping/MapViewController.swift \
  OBAKit/Mapping/MapViewController+MapLayers.swift OBAKitTests/Mapping/MapLayerRegistrarTests.swift
git commit -m "Share map layer registration between both map surfaces"
```

---

## Phase 4 — Panel settings

### Task 5: `MapBaseType` → `MapStyle`

`MapPanelRootView` currently does `.mapStyle(mapViewModel.mapType == .standard ? .standard(emphasis: .muted) : .hybrid)`, which silently renders satellite as hybrid. Extract the decision so it can be tested without a view.

**Files:**
- Create: `OBAKit/ViewModels/MapViewModel/MapBaseType+MapStyle.swift`
- Test: `OBAKitTests/ViewModels/MapBaseTypeMapStyleTests.swift` (create)

**Interfaces:**
- Consumes: `MapBaseType` (existing).
- Produces:
  - `enum MapBaseStyleDescriptor: Equatable { case standard(pointsOfInterest: Bool), imagery, hybrid(pointsOfInterest: Bool) }`
  - `MapBaseType.styleDescriptor(showingPointsOfInterest: Bool) -> MapBaseStyleDescriptor`
  - `MapBaseStyleDescriptor.mapStyle: MapStyle`

- [ ] **Step 1: Write the failing test**

Create `OBAKitTests/ViewModels/MapBaseTypeMapStyleTests.swift`:

```swift
//
//  MapBaseTypeMapStyleTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
@testable import OBAKit

/// `MapStyle` is opaque and not `Equatable`, so the decision is modelled as a
/// descriptor that *is*, and the descriptor is what these tests assert. The
/// panel's `.mapStyle` modifier then reads `descriptor.mapStyle`.
@Suite(.serialized)
struct MapBaseTypeMapStyleTests {

    @Test func `Standard keeps the muted emphasis and honours points of interest`() {
        #expect(MapBaseType.standard.styleDescriptor(showingPointsOfInterest: true) == .standard(pointsOfInterest: true))
        #expect(MapBaseType.standard.styleDescriptor(showingPointsOfInterest: false) == .standard(pointsOfInterest: false))
    }

    /// The bug this task fixes: satellite used to fall through to hybrid,
    /// making the sheet's third basemap tile indistinguishable from its second.
    @Test func `Satellite maps to imagery, not hybrid`() {
        #expect(MapBaseType.satellite.styleDescriptor(showingPointsOfInterest: true) == .imagery)
        #expect(MapBaseType.satellite.styleDescriptor(showingPointsOfInterest: false) == .imagery)
    }

    @Test func `Hybrid honours points of interest`() {
        #expect(MapBaseType.hybrid.styleDescriptor(showingPointsOfInterest: true) == .hybrid(pointsOfInterest: true))
        #expect(MapBaseType.hybrid.styleDescriptor(showingPointsOfInterest: false) == .hybrid(pointsOfInterest: false))
    }

    /// Imagery carries no labels, so there is nothing for the POI preference to
    /// act on — the descriptor must not vary with it.
    @Test func `Imagery ignores the points of interest preference`() {
        let on = MapBaseType.satellite.styleDescriptor(showingPointsOfInterest: true)
        let off = MapBaseType.satellite.styleDescriptor(showingPointsOfInterest: false)
        #expect(on == off)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: compile error — `cannot find 'MapBaseStyleDescriptor' in scope`.

- [ ] **Step 3: Create the mapping**

Create `OBAKit/ViewModels/MapViewModel/MapBaseType+MapStyle.swift`:

```swift
//
//  MapBaseType+MapStyle.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import SwiftUI

/// The basemap decision, in a form that can be compared and therefore tested.
///
/// `MapStyle` is opaque and not `Equatable`, so asserting on it directly is
/// impossible. Splitting the decision from its construction keeps the branch —
/// which previously collapsed satellite into hybrid — under test.
enum MapBaseStyleDescriptor: Equatable {
    case standard(pointsOfInterest: Bool)
    /// Imagery carries no labels, so it takes no points-of-interest argument.
    case imagery
    case hybrid(pointsOfInterest: Bool)
}

extension MapBaseType {
    func styleDescriptor(showingPointsOfInterest: Bool) -> MapBaseStyleDescriptor {
        switch self {
        case .standard: return .standard(pointsOfInterest: showingPointsOfInterest)
        case .satellite: return .imagery
        case .hybrid: return .hybrid(pointsOfInterest: showingPointsOfInterest)
        }
    }
}

extension MapBaseStyleDescriptor {
    var mapStyle: MapStyle {
        switch self {
        case .standard(let showsPOI):
            // `.muted` matches the UIKit map's `MKMapType.mutedStandard`.
            return .standard(emphasis: .muted, pointsOfInterest: showsPOI ? .all : .excludingAll)
        case .imagery:
            return .imagery
        case .hybrid(let showsPOI):
            return .hybrid(pointsOfInterest: showsPOI ? .all : .excludingAll)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests/MapBaseTypeMapStyleTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add OBAKit/ViewModels/MapViewModel/MapBaseType+MapStyle.swift OBAKitTests/ViewModels/MapBaseTypeMapStyleTests.swift
git commit -m "Map each base type to its own map style"
```

---

### Task 6: `MapPanelLayersModel`

The panel's observable window onto the layer system: layer enablement, POI, badge count. Rental items are added in Task 9.

**Files:**
- Create: `OBAKit/Sheet/Root/MapPanelLayersModel.swift`
- Test: `OBAKitTests/ViewModels/MapPanelLayersModelTests.swift` (create)

**Interfaces:**
- Consumes: `MapLayerRegistrar` (Task 4), `MapRegionManager.mapLayersViewportDidChange(_:)` (Task 1).
- Produces:
  - `MapPanelLayersModel.init(application: Application)`
  - `@Published private(set) var isStopsLayerEnabled: Bool`
  - `@Published private(set) var showsPointsOfInterest: Bool`
  - `@Published private(set) var enabledLayerCount: Int`
  - `func viewportDidChange(_ rect: MKMapRect)`

- [ ] **Step 1: Write the failing test**

Create `OBAKitTests/ViewModels/MapPanelLayersModelTests.swift`:

```swift
//
//  MapPanelLayersModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// The panel's window onto the layer system. `MapSheetView` writes through
/// `MapRegionManager`, which posts notifications; this model is what turns those
/// into published state the SwiftUI map re-renders from.
@MainActor
@Suite(.serialized)
final class MapPanelLayersModelTests: OBATestCase {

    private var application: Application!
    private var model: MapPanelLayersModel!

    override init() async throws {
        try await super.init()
        let queue = OperationQueue()
        let dataLoader = MockDataLoader(testName: name)
        application = buildApplication(queue: queue, dataLoader: dataLoader)
        model = MapPanelLayersModel(application: application)
    }

    @Test func `Registers the stops layer on construction`() {
        #expect(application.mapRegionManager.mapLayer(id: StopsMapLayer.layerID) != nil)
        #expect(model.isStopsLayerEnabled)
    }

    @Test func `Tracks the stops layer being switched off`() {
        application.mapRegionManager.setMapLayerEnabled(false, id: StopsMapLayer.layerID)

        #expect(model.isStopsLayerEnabled == false)
    }

    @Test func `Tracks the stops layer being switched back on`() {
        application.mapRegionManager.setMapLayerEnabled(false, id: StopsMapLayer.layerID)
        application.mapRegionManager.setMapLayerEnabled(true, id: StopsMapLayer.layerID)

        #expect(model.isStopsLayerEnabled)
    }

    @Test func `Points of interest default to on`() {
        #expect(model.showsPointsOfInterest)
    }

    @Test func `Tracks points of interest being switched off`() {
        application.mapRegionManager.mapViewShowsPointsOfInterest = false

        #expect(model.showsPointsOfInterest == false)
    }

    /// The badge is the panel's only at-a-glance readout of layer state, so it
    /// has to move with the toggles.
    @Test func `Badge count follows enabled layers`() {
        let initial = model.enabledLayerCount
        #expect(initial == 1)

        application.mapRegionManager.setMapLayerEnabled(false, id: StopsMapLayer.layerID)
        #expect(model.enabledLayerCount == 0)
    }

    /// Reset restores stops on and points of interest on in one write; the model
    /// must reflect both.
    @Test func `Reflects a reset to defaults`() {
        application.mapRegionManager.setMapLayerEnabled(false, id: StopsMapLayer.layerID)
        application.mapRegionManager.mapViewShowsPointsOfInterest = false

        application.mapRegionManager.resetMapLayersToDefaults()

        #expect(model.isStopsLayerEnabled)
        #expect(model.showsPointsOfInterest)
    }

    @Test func `Forwards the viewport to the layer pipeline`() {
        let rect = MKMapRect(x: 0, y: 0, width: 10_000, height: 10_000)

        model.viewportDidChange(rect)

        #expect(application.mapRegionManager.currentVisibleMapRect.height == 10_000)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: compile error — `cannot find 'MapPanelLayersModel' in scope`.

- [ ] **Step 3: Create the model**

Create `OBAKit/Sheet/Root/MapPanelLayersModel.swift`:

```swift
//
//  MapPanelLayersModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import MapKit
import OBAKitCore

/// The SwiftUI panel's window onto the map layer system.
///
/// `MapSheetView` writes through `MapRegionManager`, which owns the persistence
/// and posts notifications. This model turns those notifications into published
/// state so the panel's `Map` re-renders — the UIKit surface gets the same
/// effect from `MKMapView` delegate callbacks it has no counterpart to here.
///
/// Retains the registrar because `RegionsService` holds delegates weakly.
@MainActor final class MapPanelLayersModel: ObservableObject {

    @Published private(set) var isStopsLayerEnabled = true
    @Published private(set) var showsPointsOfInterest = true

    /// Drives the badge on the map-type button — the panel's only at-a-glance
    /// readout of layer state.
    @Published private(set) var enabledLayerCount = 0

    private let application: Application
    private var registrar: MapLayerRegistrar!
    private var cancellables = Set<AnyCancellable>()

    init(application: Application) {
        self.application = application

        registrar = MapLayerRegistrar(application: application) { [weak self] _ in
            self?.refresh()
        }
        registrar.configure()

        let center = NotificationCenter.default
        for name in [
            Notification.Name.mapLayerEnabledStateDidChange,
            .mapLayerAvailabilityDidChange,
            .mapPointsOfInterestVisibilityDidChange,
            .rentalRangeFilterDidChange
        ] {
            center.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refresh() }
                .store(in: &cancellables)
        }

        refresh()
    }

    private var mapRegionManager: MapRegionManager { application.mapRegionManager }

    private func refresh() {
        isStopsLayerEnabled = mapRegionManager.isStopsLayerEnabled
        showsPointsOfInterest = mapRegionManager.mapViewShowsPointsOfInterest
        enabledLayerCount = mapRegionManager.enabledMapLayerCount
    }

    /// Feeds the panel's camera into the layer pipeline. The `MKMapView` this
    /// manager owns is never laid out in panel mode, so nothing else would.
    func viewportDidChange(_ rect: MKMapRect) {
        mapRegionManager.mapLayersViewportDidChange(rect)
    }
}
```

> **Note for the implementer:** `MapRegionManager.isStopsLayerEnabled`, `mapViewShowsPointsOfInterest`, and `enabledMapLayerCount` are declared `internal`/`public` on the manager today — confirm each is reachable from `OBAKit` (they are all in the same module) before assuming the accessor list above compiles unchanged.

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests/MapPanelLayersModelTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: 8 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add OBAKit/Sheet/Root/MapPanelLayersModel.swift OBAKitTests/ViewModels/MapPanelLayersModelTests.swift
git commit -m "Add a layers model for the map panel"
```

---

### Task 7: The `.mapSettings` route, the badge, and the VM hoist

**Files:**
- Modify: `OBAKit/Sheet/Coordinator/SheetRoute.swift` (add `.mapSettings` to the enum, `prefersStacking`, `detentConfiguration`, and the `id` switch)
- Modify: `OBAKit/Sheet/DI/AppSheetViewFactory.swift`
- Modify: `OBAKit/Sheet/Root/MapPanelRootController.swift`
- Modify: `OBAKit/Sheet/Root/MapPanelRootView.swift`
- Modify: `OBAKit/Sheet/Root/Controls/MapTypeButton.swift`
- Modify: `OBAKit/Sheet/Root/Controls/MapControlsCluster.swift`
- Modify: `OBAKit/ViewModels/MapViewModel/MapViewModel.swift` (delete `toggleMapType()`)
- Modify: `OBAKitTests/Sheet/AppSheetRouteTests.swift`
- Modify: `OBAKitTests/ViewModels/MapViewModelTests.swift`

**Interfaces:**
- Consumes: `MapPanelLayersModel` (Task 6), `MapBaseType.styleDescriptor(showingPointsOfInterest:)` (Task 5).
- Produces:
  - `AppSheetRoute.mapSettings` — stacked, `[.medium, .large]`, initial `.medium`, `id == "mapSettings"`
  - `AppSheetViewFactory.init(application:mapViewModel:layersModel:onPresentTrip:)`
  - `MapPanelRootView.init(application:mapViewModel:layersModel:factory:)`
  - `MapTypeButton(mapType:badgeCount:onTap:)`
  - `MapControlsCluster(mapType:badgeCount:isLocationButtonVisible:onOpenMapSettings:onCenterOnUser:)`

- [ ] **Step 1: Write the failing route tests**

Add to `OBAKitTests/Sheet/AppSheetRouteTests.swift`:

```swift
    @Test func `Map settings route has a stable id`() {
        #expect(AppSheetRoute.mapSettings.id == "mapSettings")
    }

    /// Stacked so the home sheet peeks beneath, matching every other detail
    /// destination — and because `SheetCoordinator.push` preconditions that a
    /// stacked route allows interactive dismissal.
    @Test func `Map settings route stacks and allows dismissal`() {
        #expect(AppSheetRoute.mapSettings.prefersStacking)
        #expect(AppSheetRoute.mapSettings.detentConfiguration.isDismissDisabled == false)
    }

    /// Opens at `.medium` so the map stays visible behind the basemap tiles —
    /// picking a basemap you cannot see is a guess.
    @Test func `Map settings route opens at medium`() {
        let config = AppSheetRoute.mapSettings.detentConfiguration
        #expect(config.initialDetent == .medium)
        #expect(config.detents == [.medium, .large])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: compile error — `type 'AppSheetRoute' has no member 'mapSettings'`.

- [ ] **Step 3: Add the route**

In `OBAKit/Sheet/Coordinator/SheetRoute.swift`:

Add the case beside `.more` and `.settings`:

```swift
    case more
    case settings
    case mapSettings
```

Add `mapSettings` to the caseless arm of the `id` switch:

```swift
        case .home, .search, .nearbyAll, .recentStopsAll, .bookmarksAll,
             .tripPlanner, .routePicker, .more, .settings, .mapSettings:
            return caseName
```

Add it to `prefersStacking`'s `true` arm:

```swift
        case .stopDetails, .tripPlanner, .tripDetails, .currentTrip, .transitAlert, .more, .nearbyAll, .recentStopsAll, .bookmarksAll, .settings, .mapSettings:
            return true
```

Give it its own `detentConfiguration` arm — it opens at `.medium`, unlike the other stacked routes:

```swift
        case .mapSettings:
            // Opens at `.medium` so the map stays visible behind the basemap
            // tiles: picking a basemap you cannot see is a guess.
            return SheetDetentConfiguration(
                detents: [.medium, .large],
                initialDetent: .medium,
                isDismissDisabled: false
            )
```

(and remove nothing from the existing `.tripPlanner, .tripDetails, ...` arm).

- [ ] **Step 4: Run route tests to verify they pass**

```bash
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests/AppSheetRouteTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: all PASS.

- [ ] **Step 5: Hoist the view models into the controller**

In `OBAKit/Sheet/Root/MapPanelRootController.swift`, replace the initializer:

```swift
    public init(application: Application) {
        let bridge = TripPresentationBridge()

        // Built here, not inside `MapPanelRootView.init`, because
        // `AppSheetViewFactory` needs the same instances — `MapSheetModel` reads
        // and writes the map type through the view model the map renders from,
        // so a second instance would let the sheet and the map disagree.
        let initialMapType = MapBaseType(application.mapRegionManager.userSelectedMapType)
        let mapViewModel = MapViewModel(application: application, initialMapType: initialMapType)
        let layersModel = MapPanelLayersModel(application: application)

        let factory = AppSheetViewFactory(
            application: application,
            mapViewModel: mapViewModel,
            layersModel: layersModel,
            onPresentTrip: { [weak bridge] arrival in bridge?.present(arrival) }
        )
        let rootView = MapPanelRootView(
            application: application,
            mapViewModel: mapViewModel,
            layersModel: layersModel,
            factory: factory
        )
        self.host = UIHostingController(rootView: rootView)
        self.bridge = bridge
        super.init(nibName: nil, bundle: nil)
        self.bridge.host = self
        self.bridge.application = application
    }
```

- [ ] **Step 6: Accept the injected models in the view**

In `OBAKit/Sheet/Root/MapPanelRootView.swift`, add the layers model property beside the other `@StateObject`s:

```swift
    @StateObject private var layersModel: MapPanelLayersModel
```

and replace the initializer's view-model construction:

```swift
    init(
        application: Application,
        mapViewModel: MapViewModel,
        layersModel: MapPanelLayersModel,
        factory: AppSheetViewFactory
    ) {
        _coordinator = StateObject(wrappedValue: SheetCoordinator<AppSheetRoute>(root: .home))
        _stopsObserver = StateObject(wrappedValue: MapStopsObserver(application: application))
        _mapViewModel = StateObject(wrappedValue: mapViewModel)
        _layersModel = StateObject(wrappedValue: layersModel)
        self.application = application
        self.factory = factory
```

(the rest of the initializer body — `fallback`, `_cameraPosition`, `_needsInitialRecenter` — is unchanged).

- [ ] **Step 7: Apply the map style, the stops gate, and viewport forwarding**

In `body`, replace the `.mapStyle` modifier:

```swift
        .mapStyle(mapViewModel.mapType.styleDescriptor(
            showingPointsOfInterest: layersModel.showsPointsOfInterest
        ).mapStyle)
```

Gate the regular-stops `ForEach` on the layer toggle. Bookmark pins stay ungated, mirroring `displayUniqueStopAnnotations`, where `stopsToAdd` is gated but bookmarks are not:

```swift
            if isZoomedInForStops && layersModel.isStopsLayerEnabled {
                ForEach(stopsObserver.renderStops) { renderStop in
```

In `.onMapCameraChange`, forward the viewport to the layer pipeline. Add immediately after `visibleMapRectHeight = context.rect.height`:

```swift
            layersModel.viewportDidChange(context.rect)
```

- [ ] **Step 8: Give the button a badge and point it at the sheet**

Replace `OBAKit/Sheet/Root/Controls/MapTypeButton.swift`'s `body` and add the badge. The type doc comment also needs updating — it currently claims the button mirrors a UIKit *toggle*, which stopped being true when the UIKit button absorbed its toggle into the sheet:

```swift
/// Floating basemap button on the bottom-trailing cluster of
/// `MapPanelRootView`. Opens the Map sheet, which absorbs the old
/// standard/hybrid toggle as its basemap tiles — the same move
/// `MapViewController`'s basemap button already made.
///
/// The badge carries the active-layer count: layer state stays readable
/// without opening anything.
struct MapTypeButton: View {
    let mapType: MapBaseType
    let badgeCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: symbolName)
                .font(.system(size: 16, weight: .regular))
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .liquidGlassButtonStyle(borderShape: .circle, fallbackShape: Circle())
        .overlay(alignment: .topTrailing) {
            if badgeCount > 0 {
                Text(String(badgeCount))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 15, minHeight: 15)
                    .background(Color(uiColor: ThemeColors.shared.brand), in: Circle())
                    .offset(x: -2, y: 2)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(Text(OBALoc(
            "map_controller.map_type.accessibility_label",
            value: "Map type",
            comment: "Voiceover text indicating that this button toggles the base map type."
        )))
        .accessibilityValue(Text(accessibilityValueText))
    }
```

(`symbolName` and `accessibilityValueText` are unchanged.)

- [ ] **Step 9: Update the control cluster and its call site**

Replace `OBAKit/Sheet/Root/Controls/MapControlsCluster.swift`'s body:

```swift
struct MapControlsCluster: View {
    let mapType: MapBaseType
    let badgeCount: Int
    let isLocationButtonVisible: Bool
    let onOpenMapSettings: () -> Void
    let onCenterOnUser: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            MapTypeButton(mapType: mapType, badgeCount: badgeCount, onTap: onOpenMapSettings)
            CurrentLocationButton(isVisible: isLocationButtonVisible, onTap: onCenterOnUser)
        }
    }
}
```

In `MapPanelRootView`'s `mapControlsCluster`:

```swift
    private var mapControlsCluster: some View {
        MapControlsCluster(
            mapType: mapViewModel.mapType,
            badgeCount: layersModel.enabledLayerCount,
            isLocationButtonVisible: application.locationService.isLocationUseAuthorized,
            onOpenMapSettings: { coordinator.push(.mapSettings) },
            onCenterOnUser: centerOnUser
        )
        .padding(.trailing, ThemeMetrics.controllerMargin)
        .floatingOverSheet(height: sheetHeight, opacity: toolbarsOpacity, duration: toolbarsAnimationDuration)
    }
```

- [ ] **Step 10: Register the route in the factory**

In `OBAKit/Sheet/DI/AppSheetViewFactory.swift`, extend the initializer:

```swift
    let application: Application
    let mapViewModel: MapViewModel
    let layersModel: MapPanelLayersModel
    let onPresentTrip: (ArrivalDeparture) -> Void

    init(
        application: Application,
        mapViewModel: MapViewModel,
        layersModel: MapPanelLayersModel,
        onPresentTrip: @escaping (ArrivalDeparture) -> Void
    ) {
        self.application = application
        self.mapViewModel = mapViewModel
        self.layersModel = layersModel
        self.onPresentTrip = onPresentTrip
    }
```

Add the dispatcher branch (and remove nothing else):

```swift
        case .mapSettings:
            mapSettingsView()
```

and the builder:

```swift
    /// The Map sheet, shared verbatim with `MapViewController`. Its own doc
    /// comment calls it "the single canonical place riders turn layers on and
    /// off" — so the panel reuses it rather than growing a parallel surface.
    func mapSettingsView() -> MapSheetView {
        MapSheetView(model: MapSheetModel(
            mapRegionManager: application.mapRegionManager,
            mapViewModel: mapViewModel
        ))
    }
```

- [ ] **Step 11: Delete `toggleMapType()` and repoint its test**

In `OBAKit/ViewModels/MapViewModel/MapViewModel.swift`, delete `toggleMapType()` entirely — the panel button now opens the sheet, and the UIKit button already did. `setMapType(_:)` stays.

In `OBAKitTests/ViewModels/MapViewModelTests.swift`, replace any `toggleMapType` test with:

```swift
    /// The Map sheet's basemap tiles call `setMapType` directly; the old
    /// two-way toggle is gone from both surfaces.
    @Test func `Setting the map type persists it through the region manager`() {
        viewModel.setMapType(.satellite)

        #expect(viewModel.mapType == .satellite)
        #expect(application.mapRegionManager.userSelectedMapType == .satellite.mkMapType)
    }

    @Test func `Setting the same map type is a no-op`() {
        viewModel.setMapType(.standard)

        #expect(viewModel.mapType == .standard)
    }
```

> **Note for the implementer:** match the existing fixture names in that suite (`viewModel`, `application`) rather than the placeholders above if they differ.

- [ ] **Step 12: Run the affected suites**

```bash
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building \
  -only-testing:OBAKitTests/AppSheetRouteTests \
  -only-testing:OBAKitTests/MapViewModelTests \
  -only-testing:OBAKitTests/MapPanelViewModelTests \
  -only-testing:OBAKitTests/MapPanelLayersModelTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: all PASS.

- [ ] **Step 13: Verify by hand in the simulator**

Enable the panel flag, launch, and confirm: the basemap button shows a badge of `1`; tapping it opens the Map sheet at `.medium` with the map visible behind; each of the three basemap tiles visibly changes the map (satellite must differ from hybrid); the Points of Interest toggle adds and removes POI pins; switching Bus stops off clears stop pins while bookmark pins remain; Reset restores both.

- [ ] **Step 14: Commit**

```bash
git add OBAKit/Sheet OBAKit/ViewModels/MapViewModel/MapViewModel.swift \
  OBAKitTests/Sheet/AppSheetRouteTests.swift OBAKitTests/ViewModels/MapViewModelTests.swift
git commit -m "Open the map settings sheet from the panel basemap button"
```

---

## Phase 5 — Rentals on the panel

### Task 8: `RentalMapItem` and `RentalClustering`

SwiftUI `Map` has no clustering API — it de-collides annotation *titles*, not annotation *views*, and `clusteringIdentifier` has no counterpart. This is the replacement, and it is a pure function so it carries real tests.

**Files:**
- Create: `OBAKit/Mapping/Layers/RentalMapItem.swift`
- Create: `OBAKit/Mapping/Layers/RentalClustering.swift`
- Test: `OBAKitTests/Mapping/RentalClusteringTests.swift` (create)

**Interfaces:**
- Consumes: `VehicleRental` (OTPKit: `Identifiable`, `Hashable`, `id: String`, `coordinate: CLLocationCoordinate2D`).
- Produces:
  - `enum RentalMapItem: Identifiable { case single(VehicleRental); case cluster(id: String, coordinate: CLLocationCoordinate2D, members: [VehicleRental]) }`, with `var id: String`
  - `enum RentalClustering { static func items(for:span:mapSize:cellSize:) -> [RentalMapItem] }`
  - `static func clusterID(for members: [VehicleRental]) -> String`

- [ ] **Step 1: Write the failing test**

Create `OBAKitTests/Mapping/RentalClusteringTests.swift`:

```swift
//
//  RentalClusteringTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import MapKit
import Testing
import OTPKit
@testable import OBAKit

/// MapKit clusters by view-frame collision; SwiftUI `Map` offers nothing
/// equivalent, so the panel groups in screen space itself. Pure function, so
/// these tests need no map at all.
@Suite(.serialized)
struct RentalClusteringTests {

    /// An iPhone-ish map viewport spanning roughly one square kilometre.
    private let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    private let mapSize = CGSize(width: 390, height: 844)

    private func items(_ rentals: [VehicleRental]) -> [RentalMapItem] {
        RentalClustering.items(for: rentals, span: span, mapSize: mapSize, cellSize: 60)
    }

    @Test func `Isolated vehicles stay single`() throws {
        let result = items([
            try RentalFixtures.vehicle(id: "a", lat: 47.600, lon: -122.300),
            try RentalFixtures.vehicle(id: "b", lat: 47.609, lon: -122.309)
        ])

        #expect(result.count == 2)
        #expect(result.allSatisfy { if case .single = $0 { return true } else { return false } })
    }

    @Test func `Co-located vehicles collapse into one cluster`() throws {
        let result = items([
            try RentalFixtures.vehicle(id: "a", lat: 47.6000, lon: -122.3000),
            try RentalFixtures.vehicle(id: "b", lat: 47.60001, lon: -122.30001),
            try RentalFixtures.vehicle(id: "c", lat: 47.60002, lon: -122.30002)
        ])

        #expect(result.count == 1)
        guard case .cluster(_, _, let members) = try #require(result.first) else {
            Issue.record("expected a cluster")
            return
        }
        #expect(Set(members.map(\.id)) == ["a", "b", "c"])
    }

    @Test func `A cluster sits at the centroid of its members`() throws {
        let result = items([
            try RentalFixtures.vehicle(id: "a", lat: 47.6000, lon: -122.3000),
            try RentalFixtures.vehicle(id: "b", lat: 47.6001, lon: -122.3001)
        ])

        guard case .cluster(_, let coordinate, _) = try #require(result.first) else {
            Issue.record("expected a cluster")
            return
        }
        #expect(abs(coordinate.latitude - 47.60005) < 0.000001)
        #expect(abs(coordinate.longitude - (-122.30005)) < 0.000001)
    }

    /// Identity is a hash of the sorted member ids, not the cell index. Cell
    /// indices shift as the viewport origin pans, which would churn SwiftUI's
    /// diff on every camera move.
    @Test func `Cluster id is stable while membership is unchanged`() throws {
        let members = [
            try RentalFixtures.vehicle(id: "a", lat: 47.6000, lon: -122.3000),
            try RentalFixtures.vehicle(id: "b", lat: 47.6001, lon: -122.3001)
        ]

        #expect(RentalClustering.clusterID(for: members) == RentalClustering.clusterID(for: members.reversed()))
    }

    @Test func `Cluster id changes when a member leaves`() throws {
        let a = try RentalFixtures.vehicle(id: "a")
        let b = try RentalFixtures.vehicle(id: "b")
        let c = try RentalFixtures.vehicle(id: "c")

        #expect(RentalClustering.clusterID(for: [a, b, c]) != RentalClustering.clusterID(for: [a, b]))
    }

    /// The property that removes the need for a density cap: marker count is
    /// bounded by occupied cells, not by how many vehicles are in the viewport.
    @Test func `Marker count is bounded by viewport cells at extreme density`() throws {
        let crowd = try (0..<500).map { index in
            try RentalFixtures.vehicle(
                id: "v\(index)",
                lat: 47.600 + Double(index % 25) * 0.0004,
                lon: -122.300 + Double(index / 25) * 0.0004
            )
        }

        let result = items(crowd)

        let maxCells = Int(ceil(mapSize.width / 60)) * Int(ceil(mapSize.height / 60))
        #expect(result.count <= maxCells)
        #expect(result.count < 500)
    }

    @Test func `Every input rental appears exactly once in the output`() throws {
        let crowd = try (0..<40).map { index in
            try RentalFixtures.vehicle(
                id: "v\(index)",
                lat: 47.600 + Double(index) * 0.0002,
                lon: -122.300
            )
        }

        let emitted = items(crowd).flatMap { item -> [String] in
            switch item {
            case .single(let rental): return [rental.id]
            case .cluster(_, _, let members): return members.map(\.id)
            }
        }

        #expect(Set(emitted).count == 40)
        #expect(emitted.count == 40)
    }

    @Test func `An empty input produces no items`() {
        #expect(items([]).isEmpty)
    }

    /// A degenerate viewport (before the Map reports its first layout) must not
    /// divide by zero or emit garbage.
    @Test func `A zero-sized map produces one item per rental`() throws {
        let result = RentalClustering.items(
            for: [try RentalFixtures.vehicle(id: "a"), try RentalFixtures.vehicle(id: "b")],
            span: span,
            mapSize: .zero,
            cellSize: 60
        )

        #expect(result.count == 2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: compile error — `cannot find 'RentalClustering' in scope`.

- [ ] **Step 3: Create `RentalMapItem`**

Create `OBAKit/Mapping/Layers/RentalMapItem.swift`:

```swift
//
//  RentalMapItem.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import OTPKit

/// One thing drawn on the SwiftUI panel map for the rental layers: either a
/// vehicle on its own, or a group of them that would otherwise overlap.
///
/// The UIKit map gets this split from MapKit, which hands back
/// `MKClusterAnnotation`s. SwiftUI `Map` has no equivalent, so the panel
/// computes it — see `RentalClustering`.
enum RentalMapItem: Identifiable {
    case single(VehicleRental)
    case cluster(id: String, coordinate: CLLocationCoordinate2D, members: [VehicleRental])

    var id: String {
        switch self {
        case .single(let rental): return "rental-\(rental.id)"
        case .cluster(let id, _, _): return id
        }
    }

    var coordinate: CLLocationCoordinate2D {
        switch self {
        case .single(let rental): return rental.coordinate
        case .cluster(_, let coordinate, _): return coordinate
        }
    }

    /// Every rental this item stands for — one for a single, all of them for a
    /// cluster. Used to resolve a tapped item back to a sheet route.
    var members: [VehicleRental] {
        switch self {
        case .single(let rental): return [rental]
        case .cluster(_, _, let members): return members
        }
    }
}
```

- [ ] **Step 4: Create `RentalClustering`**

Create `OBAKit/Mapping/Layers/RentalClustering.swift`:

```swift
//
//  RentalClustering.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import MapKit
import OTPKit

/// Groups rentals that would visually collide on the SwiftUI panel map.
///
/// MapKit gives the UIKit map this for free via `clusteringIdentifier`, testing
/// actual marker frames for collision and declustering progressively as the
/// rider zooms. SwiftUI `Map` exposes nothing equivalent, so the panel buckets
/// into a fixed screen-space grid instead. The tradeoff is accepted and known:
/// two vehicles either side of a cell boundary stay separate even when they
/// overlap. The dominant real case — a pile-up at one corner — lands in one
/// cell.
///
/// This is also what makes a density cap unnecessary. Marker count is bounded by
/// *occupied cells* (screen area ÷ cell area, roughly 90 on an iPhone-sized
/// map), not by how many vehicles the viewport holds, so `RentalMapLayer`'s
/// 500-vehicle `densityBudget` never translates into 500 SwiftUI views — and no
/// vehicle is ever silently dropped to stay under a limit.
enum RentalClustering {

    /// Buckets `rentals` into `cellSize`-point grid cells, emitting a single for
    /// a lone occupant and a cluster at the centroid otherwise.
    ///
    /// - Parameters:
    ///   - span: the visible region's span, used to convert points to degrees.
    ///   - mapSize: the map view's size in points. `.zero` before the first
    ///     layout, which yields one item per rental rather than a division by zero.
    static func items(
        for rentals: [VehicleRental],
        span: MKCoordinateSpan,
        mapSize: CGSize,
        cellSize: CGFloat = 60
    ) -> [RentalMapItem] {
        guard !rentals.isEmpty else { return [] }

        // Before the Map reports a layout there is no screen space to cluster
        // in; drawing each rental on its own is the honest fallback.
        guard mapSize.width > 0, mapSize.height > 0, cellSize > 0 else {
            return rentals.map { .single($0) }
        }

        let latitudePerCell = span.latitudeDelta * Double(cellSize / mapSize.height)
        let longitudePerCell = span.longitudeDelta * Double(cellSize / mapSize.width)

        guard latitudePerCell > 0, longitudePerCell > 0 else {
            return rentals.map { .single($0) }
        }

        // Preserves input order (which the coordinator sorts by id), so the
        // output is deterministic for a given input.
        var cellOrder: [String] = []
        var buckets: [String: [VehicleRental]] = [:]

        for rental in rentals {
            let row = Int(floor(rental.coordinate.latitude / latitudePerCell))
            let column = Int(floor(rental.coordinate.longitude / longitudePerCell))
            let key = "\(row):\(column)"
            if buckets[key] == nil {
                buckets[key] = []
                cellOrder.append(key)
            }
            buckets[key]?.append(rental)
        }

        return cellOrder.compactMap { key -> RentalMapItem? in
            guard let members = buckets[key], !members.isEmpty else { return nil }
            if members.count == 1 {
                return .single(members[0])
            }
            return .cluster(
                id: clusterID(for: members),
                coordinate: centroid(of: members),
                members: members
            )
        }
    }

    /// A cluster's identity, derived from its sorted member ids.
    ///
    /// Deliberately *not* the cell index: indices shift as the viewport origin
    /// pans, so a cell-keyed id would churn SwiftUI's `ForEach` diff on every
    /// camera move and re-create the marker views. The same id is used for the
    /// `.rentalCluster` sheet route, so an open sheet and its marker agree.
    static func clusterID(for members: [VehicleRental]) -> String {
        var hasher = Hasher()
        for id in members.map(\.id).sorted() {
            hasher.combine(id)
        }
        return "rentalCluster-\(hasher.finalize())"
    }

    private static func centroid(of members: [VehicleRental]) -> CLLocationCoordinate2D {
        let count = Double(members.count)
        let latitude = members.reduce(0.0) { $0 + $1.coordinate.latitude } / count
        let longitude = members.reduce(0.0) { $0 + $1.coordinate.longitude } / count
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
```

> **Warning for the implementer:** `Hasher` is seeded per process on Apple platforms, so `clusterID` is stable *within* a launch but not across launches. That is exactly the guarantee needed here (SwiftUI diffing and a live sheet route), and the tests above only compare ids within one run. Do **not** persist a cluster id or send it off-device.

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests/RentalClusteringTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: 9 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add OBAKit/Mapping/Layers/RentalMapItem.swift OBAKit/Mapping/Layers/RentalClustering.swift \
  OBAKitTests/Mapping/RentalClusteringTests.swift
git commit -m "Cluster rentals in screen space for the SwiftUI map"
```

---

### Task 9: Render rentals on the panel map

**Files:**
- Modify: `OBAKit/Sheet/Root/MapPanelLayersModel.swift`
- Create: `OBAKit/Sheet/Root/Controls/RentalMapMarker.swift`
- Modify: `OBAKit/Sheet/Root/MapPanelRootView.swift`
- Modify: `OBAKitTests/ViewModels/MapPanelLayersModelTests.swift`

**Interfaces:**
- Consumes: `RentalClustering.items(for:span:mapSize:cellSize:)` (Task 8), `RentalLayerCoordinator.$visibleRentals` (Task 2), `MapLayerRegistrar.rentalCoordinator` (Task 4).
- Produces:
  - `MapPanelLayersModel.rentalItems: [RentalMapItem]` (`@Published private(set)`)
  - `MapPanelLayersModel.showsFuelLabels: Bool` (`@Published private(set)`)
  - `MapPanelLayersModel.updateViewport(span:mapSize:)`
  - `MapPanelLayersModel.rental(withID: VehicleRental.ID) -> VehicleRental?`
  - `MapPanelLayersModel.rentals(withIDs: [VehicleRental.ID]) -> [VehicleRental]`
  - `MapPanelLayersModel.rentalFetchedAt: Date?`
  - `MapPanelLayersModel.rentalUserLocation: CLLocation?`
  - `enum MapPinSelection: Hashable { case stop(Stop.ID); case rental(VehicleRental.ID); case rentalCluster(String) }`
  - `RentalMapMarker`, `RentalClusterMapMarker`

- [ ] **Step 1: Write the failing tests**

Add to `OBAKitTests/ViewModels/MapPanelLayersModelTests.swift`:

```swift
    @Test func `Publishes no rental items without a bikeshare region`() {
        #expect(model.rentalItems.isEmpty)
    }

    /// The two rental sheet routes carry ids, not model objects, so the model
    /// has to resolve them — and answer nil once a vehicle leaves the feed.
    @Test func `Resolving an unknown rental id returns nil`() {
        #expect(model.rental(withID: "not-in-the-feed") == nil)
    }

    @Test func `Resolving unknown rental ids drops them`() {
        #expect(model.rentals(withIDs: ["a", "b"]).isEmpty)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: compile error — `value of type 'MapPanelLayersModel' has no member 'rentalItems'`.

- [ ] **Step 3: Publish clustered rentals from the model**

In `OBAKit/Sheet/Root/MapPanelLayersModel.swift`, add the published state:

```swift
    /// Clustered rental markers for the current viewport.
    @Published private(set) var rentalItems: [RentalMapItem] = []

    /// Whether the current zoom is tight enough to show fuel figures.
    @Published private(set) var showsFuelLabels = false

    /// Every rental currently visible, before clustering. Backs id resolution
    /// for the rental sheet routes.
    private var visibleRentals: [VehicleRental] = []

    private var lastSpan = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    private var lastMapSize: CGSize = .zero
    private var rentalCancellables = Set<AnyCancellable>()
```

In `refresh()`, add a re-subscribe hook and call it (the registrar rebuilds its coordinator on every region change, so a stale subscription would silently stop delivering):

```swift
    private func refresh() {
        isStopsLayerEnabled = mapRegionManager.isStopsLayerEnabled
        showsPointsOfInterest = mapRegionManager.mapViewShowsPointsOfInterest
        enabledLayerCount = mapRegionManager.enabledMapLayerCount
        subscribeToRentalCoordinator()
    }

    /// (Re-)binds to the registrar's current coordinator. `MapLayerRegistrar`
    /// builds a fresh one on every region change, so an old subscription would
    /// keep delivering the previous region's vehicles.
    private func subscribeToRentalCoordinator() {
        rentalCancellables.removeAll()

        guard let coordinator = registrar.rentalCoordinator else {
            visibleRentals = []
            rentalItems = []
            showsFuelLabels = false
            return
        }

        coordinator.$visibleRentals
            .sink { [weak self] rentals in
                self?.visibleRentals = rentals
                self?.recomputeClusters()
            }
            .store(in: &rentalCancellables)

        coordinator.$showsFuelLabels
            .sink { [weak self] shows in self?.showsFuelLabels = shows }
            .store(in: &rentalCancellables)
    }

    /// Records the viewport geometry clustering needs and recomputes.
    func updateViewport(span: MKCoordinateSpan, mapSize: CGSize) {
        lastSpan = span
        lastMapSize = mapSize
        recomputeClusters()
    }

    private func recomputeClusters() {
        rentalItems = RentalClustering.items(
            for: visibleRentals,
            span: lastSpan,
            mapSize: lastMapSize
        )
    }

    // MARK: - Route resolution

    /// When the rental data arrived — feeds the detail sheet's freshness line.
    var rentalFetchedAt: Date? { registrar.rentalCoordinator?.lastSnapshotAt }

    /// The rider's location, for walk-time estimates in detail sheets.
    var rentalUserLocation: CLLocation? { registrar.rentalCoordinator?.userLocation }

    /// Resolves a route's id back to a live model. Returns nil once the vehicle
    /// has left the feed, so an open sheet reflects reality rather than a
    /// snapshot taken at push time.
    func rental(withID id: VehicleRental.ID) -> VehicleRental? {
        visibleRentals.first { $0.id == id }
    }

    func rentals(withIDs ids: [VehicleRental.ID]) -> [VehicleRental] {
        let wanted = Set(ids)
        return visibleRentals.filter { wanted.contains($0.id) }
    }
```

Add `import CoreLocation` and `import OTPKit` to the file's imports.

- [ ] **Step 4: Create the SwiftUI markers**

Create `OBAKit/Sheet/Root/Controls/RentalMapMarker.swift`:

```swift
//
//  RentalMapMarker.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import OTPKit
import SwiftUI

/// A single rental on the SwiftUI panel map. Approximates
/// `RentalAnnotationView`: rental purple when operative, gray when not, a
/// form-factor glyph for free-floating vehicles and an availability count for
/// docked stations.
struct RentalMapMarker: View {
    let rental: VehicleRental
    let showsFuelLabel: Bool

    var body: some View {
        VStack(spacing: 1) {
            ZStack {
                Circle()
                    .fill(markerColor)
                    .frame(width: 28, height: 28)
                    .shadow(radius: 1, y: 1)

                if let count = stationAvailabilityText {
                    Text(count)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: glyphName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }

            if showsFuelLabel, let fuelText = RentalFormat.fuelLabelText(for: rental) {
                Text(fuelText)
                    .font(.caption.bold())
                    .foregroundStyle(markerColor)
                    // A light halo keeps the figure legible over satellite.
                    .shadow(color: Color(uiColor: .systemBackground), radius: 2)
            }
        }
        // VoiceOver ignores the zoom gate: a visual-density rule must not cost a
        // VoiceOver user information, so the fuel figure is always announced.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var markerColor: Color {
        rental.isOperative ? Color(uiColor: .rentalPurple) : Color(uiColor: .systemGray)
    }

    private var stationAvailabilityText: String? {
        guard case .station(let station) = rental, let available = station.vehiclesAvailableCount else {
            return nil
        }
        return String(available)
    }

    private var glyphName: String {
        guard case .vehicle(let vehicle) = rental, let formFactor = vehicle.vehicleType?.formFactor else {
            return "bicycle"
        }
        if formFactor.isScooter { return "scooter" }
        if formFactor.isBicycle { return "bicycle" }
        switch formFactor {
        case .car: return "car"
        case .moped: return "moped"
        default: return "bicycle"
        }
    }

    private var accessibilityLabel: String {
        [rental.displayLabel, RentalFormat.fuelLabelText(for: rental)]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

/// A group of rentals too close together to draw separately. Mirrors
/// `RentalClusterAnnotationView`: a count badge in rental purple.
struct RentalClusterMapMarker: View {
    let count: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(uiColor: .rentalPurple))
                .frame(width: 32, height: 32)
                .shadow(radius: 1, y: 1)

            Text(String(count))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(
            format: OBALoc(
                "rental_cluster.title_fmt",
                value: "%d vehicles here",
                comment: "Title of the sheet listing the members of a rental cluster"
            ),
            count
        )))
    }
}
```

> **Note for the implementer:** `VehicleRentalStation.vehiclesAvailableCount`, `RentalVehicle.vehicleType?.formFactor`, and `VehicleFormFactor.isScooter` / `.isBicycle` are all read the same way in `RentalAnnotationView.configure()` — match that file exactly if any accessor name differs.

- [ ] **Step 5: Render them on the map and widen the selection**

In `OBAKit/Sheet/Root/MapPanelRootView.swift`:

Add the selection type at file scope, above `MapPanelRootView`:

```swift
/// What the panel map's `selection` can hold. Stops and rentals share one Map,
/// so the binding needs one type covering both.
enum MapPinSelection: Hashable {
    case stop(Stop.ID)
    case rental(VehicleRental.ID)
    case rentalCluster(String)
}
```

Rename the selection state and widen its type:

```swift
    /// The pin the user tapped, if any. Bound to the `Map`'s `selection`;
    /// cleared after pushing so re-tapping the same pin pushes again.
    @State private var mapSelection: MapPinSelection?
```

Update the `Map` initializer and the stop annotation's tag:

```swift
        Map(position: $cameraPosition, selection: $mapSelection) {
```

```swift
        .tag(MapPinSelection.stop(stop.id))
```

Add the rental content inside the `Map` builder, after the stops `ForEach`:

```swift
            ForEach(layersModel.rentalItems) { item in
                Annotation("", coordinate: item.coordinate) {
                    switch item {
                    case .single(let rental):
                        RentalMapMarker(rental: rental, showsFuelLabel: layersModel.showsFuelLabels)
                    case .cluster(_, _, let members):
                        RentalClusterMapMarker(count: members.count)
                    }
                }
                .tag(tag(for: item))
            }
```

and the tag helper alongside `stopAnnotation`:

```swift
    private func tag(for item: RentalMapItem) -> MapPinSelection {
        switch item {
        case .single(let rental): return .rental(rental.id)
        case .cluster(let id, _, _): return .rentalCluster(id)
        }
    }
```

Replace the selection handler:

```swift
        .onChange(of: mapSelection) { _, selection in
            guard let selection else { return }
            switch selection {
            case .stop(let stopID):
                coordinator.push(.stopDetails(stopID: stopID))
            case .rental(let rentalID):
                coordinator.push(.rentalDetail(rentalID: rentalID))
            case .rentalCluster(let clusterID):
                let members = layersModel.rentalItems
                    .first { $0.id == clusterID }?
                    .members ?? []
                guard !members.isEmpty else { break }
                coordinator.push(.rentalCluster(memberIDs: members.map(\.id)))
            }
            mapSelection = nil
        }
```

In `.onMapCameraChange`, feed clustering its geometry beside the existing viewport forward:

```swift
            layersModel.viewportDidChange(context.rect)
            layersModel.updateViewport(span: context.region.span, mapSize: mapSize)
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests/MapPanelLayersModelTests \
  -only-testing:OBAKitTests/RentalClusteringTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: all PASS. The build will fail on `.rentalDetail` / `.rentalCluster` until Task 10 — complete Task 10 before running this step and commit the two together if so.

- [ ] **Step 7: Commit**

```bash
git add OBAKit/Sheet/Root/MapPanelLayersModel.swift OBAKit/Sheet/Root/Controls/RentalMapMarker.swift \
  OBAKit/Sheet/Root/MapPanelRootView.swift OBAKitTests/ViewModels/MapPanelLayersModelTests.swift
git commit -m "Draw rental markers and clusters on the panel map"
```

---

### Task 10: Rental sheet routes, and suppressing the blocked trip-planner action

**Files:**
- Modify: `OBAKit/Sheet/Coordinator/SheetRoute.swift`
- Modify: `OBAKit/Sheet/DI/AppSheetViewFactory.swift`
- Modify: `OBAKit/Mapping/Layers/RentalDetailViewController.swift`
- Modify: `OBAKitTests/Sheet/AppSheetRouteTests.swift`

**Interfaces:**
- Consumes: `MapPanelLayersModel.rental(withID:)`, `.rentals(withIDs:)`, `.rentalFetchedAt`, `.rentalUserLocation` (Task 9).
- Produces:
  - `AppSheetRoute.rentalDetail(rentalID: VehicleRental.ID)`, `.rentalCluster(memberIDs: [VehicleRental.ID])`
  - `RentalDetailView.onPlanTrip: ((VehicleRental) -> Void)?`
  - `RentalClusterListView.onPlanTrip: ((VehicleRental) -> Void)?`

- [ ] **Step 1: Write the failing route tests**

Add to `OBAKitTests/Sheet/AppSheetRouteTests.swift`:

```swift
    @Test func `Rental routes embed their associated values`() {
        #expect(AppSheetRoute.rentalDetail(rentalID: "bike_7").id == "rentalDetail-bike_7")
    }

    /// The cluster route's id is the cluster's own id, so an open sheet and the
    /// marker that opened it agree on identity across a camera move.
    @Test func `Rental cluster id is order independent`() {
        let a = AppSheetRoute.rentalCluster(memberIDs: ["a", "b", "c"])
        let b = AppSheetRoute.rentalCluster(memberIDs: ["c", "b", "a"])

        #expect(a.id == b.id)
    }

    @Test func `Rental cluster id changes with membership`() {
        let a = AppSheetRoute.rentalCluster(memberIDs: ["a", "b", "c"])
        let b = AppSheetRoute.rentalCluster(memberIDs: ["a", "b"])

        #expect(a.id != b.id)
    }

    @Test func `Rental routes stack and allow dismissal`() {
        for route in [
            AppSheetRoute.rentalDetail(rentalID: "bike_7"),
            AppSheetRoute.rentalCluster(memberIDs: ["a", "b"])
        ] {
            #expect(route.prefersStacking)
            #expect(route.detentConfiguration.isDismissDisabled == false)
            #expect(route.detentConfiguration.initialDetent == .medium)
        }
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: compile error — `type 'AppSheetRoute' has no member 'rentalDetail'`.

- [ ] **Step 3: Add the routes**

In `OBAKit/Sheet/Coordinator/SheetRoute.swift`, add the cases beside the other stacked ones:

```swift
    case rentalDetail(rentalID: VehicleRental.ID)
    case rentalCluster(memberIDs: [VehicleRental.ID])
```

Add `import OTPKit` at the top of the file.

Extend the `id` switch:

```swift
        case .rentalDetail(let rentalID):
            return "\(caseName)-\(rentalID)"
        case .rentalCluster(let memberIDs):
            // Sorted so the id is order-independent — the same pile of vehicles
            // must produce the same route regardless of feed ordering, which is
            // what keeps an open sheet bound to its marker across a camera move.
            return "\(caseName)-\(memberIDs.sorted().joined(separator: ","))"
```

Add both to `prefersStacking`'s `true` arm and to a `detentConfiguration` arm:

```swift
        case .rentalDetail, .rentalCluster:
            // `.medium` first: a rental sheet is a glance, and the map behind it
            // is the context for "is this one near me?".
            return SheetDetentConfiguration(
                detents: [.medium, .large],
                initialDetent: .medium,
                isDismissDisabled: false
            )
```

- [ ] **Step 4: Make `onPlanTrip` optional on both views**

In `OBAKit/Mapping/Layers/RentalDetailViewController.swift`:

```swift
struct RentalDetailView: View {
    let rental: VehicleRental
    let fetchedAt: Date?
    /// The layer's declared trust window; past it, the footer flags the data as stale.
    let staleAfter: Duration?
    let userLocation: CLLocation?
    /// Nil on the SwiftUI map panel, which has no trip planner to route into —
    /// `AppSheetRoute.tripPlanner` has no registered view. The button is hidden
    /// rather than disabled: a dead primary action is worse than none.
    var onPlanTrip: ((VehicleRental) -> Void)?
    var onOpenURL: (URL, URL?, String?) -> Void
```

and wrap the button:

```swift
            if let onPlanTrip {
                Button {
                    onPlanTrip(rental)
                } label: {
                    Label(
                        OBALoc("rental_detail.plan_trip", value: "Plan a trip using this bike", comment: "Primary action on the rental vehicle sheet"),
                        systemImage: "arrow.triangle.turn.up.right.diamond.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(uiColor: .rentalPurple))
            }
```

Apply the same optional treatment to `RentalClusterListView.onPlanTrip` — it passes the closure straight through to the `RentalDetailView` it presents in `.sheet(item:)`, so only the declaration changes there:

```swift
    var onPlanTrip: ((VehicleRental) -> Void)?
```

The two `UIHostingController` wrappers are unchanged: they already pass a non-nil closure.

- [ ] **Step 5: Register the routes in the factory**

In `OBAKit/Sheet/DI/AppSheetViewFactory.swift`, add the dispatcher branches:

```swift
        case .rentalDetail(let rentalID):
            rentalDetailView(rentalID: rentalID)

        case .rentalCluster(let memberIDs):
            rentalClusterView(memberIDs: memberIDs)
```

and the builders:

```swift
    /// Resolves the id to a live model, so a vehicle that leaves the feed while
    /// the sheet is open reads as gone rather than as a stale row.
    ///
    /// `onPlanTrip` is nil: the panel has no trip planner to route into. See
    /// the doc comment on `RentalDetailView.onPlanTrip`.
    @ViewBuilder
    func rentalDetailView(rentalID: VehicleRental.ID) -> some View {
        if let rental = layersModel.rental(withID: rentalID) {
            RentalDetailView(
                rental: rental,
                fetchedAt: layersModel.rentalFetchedAt,
                staleAfter: .seconds(120),
                userLocation: layersModel.rentalUserLocation,
                onPlanTrip: nil,
                onOpenURL: { [weak application] url, webFallback, _ in
                    guard let application else { return }
                    application.open(url, options: [:]) { success in
                        guard !success, let webFallback else { return }
                        application.open(webFallback, options: [:], completionHandler: nil)
                    }
                }
            )
        } else {
            rentalUnavailableView
        }
    }

    @ViewBuilder
    func rentalClusterView(memberIDs: [VehicleRental.ID]) -> some View {
        let rentals = layersModel.rentals(withIDs: memberIDs)
        if rentals.isEmpty {
            rentalUnavailableView
        } else {
            RentalClusterListView(
                rentals: rentals,
                fetchedAt: layersModel.rentalFetchedAt,
                staleAfter: .seconds(120),
                userLocation: layersModel.rentalUserLocation,
                onPlanTrip: nil,
                onOpenURL: { [weak application] url, webFallback, _ in
                    guard let application else { return }
                    application.open(url, options: [:]) { success in
                        guard !success, let webFallback else { return }
                        application.open(webFallback, options: [:], completionHandler: nil)
                    }
                }
            )
        }
    }

    /// Shown when a rental route outlives the vehicle it points at — the feed
    /// dropped it while the sheet was open.
    private var rentalUnavailableView: some View {
        Text(OBALoc(
            "map_layers.rental_unavailable",
            value: "Not available right now",
            comment: "Reason shown on a dimmed rental layer row when its server is unreachable"
        ))
        .font(.headline)
        .foregroundStyle(.secondary)
        .padding()
    }
```

Add `import OTPKit` to the factory's imports.

> **Note for the implementer:** `.seconds(120)` mirrors `RentalMapLayer.staleAfter`. If that literal drifts, both must move together — consider promoting it to a `static let` on `RentalMapLayer` and reading it here.

- [ ] **Step 6: Run tests to verify they pass**

```bash
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests/AppSheetRouteTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: all PASS.

- [ ] **Step 7: Run the whole test target**

```bash
xcodebuild test-without-building -only-testing:OBAKitTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: all PASS.

- [ ] **Step 8: Run SwiftLint**

```bash
scripts/swiftlint.sh
```

Expected: no new violations.

- [ ] **Step 9: Verify by hand in the simulator**

With the panel flag on and a bikeshare region selected: Bikes and Scooters rows appear in the Map sheet's "Other ways to get around" group; switching Scooters on puts markers on the map; zooming out collapses them into purple count badges; tapping a single marker opens the detail sheet **without** a "Plan a trip using this bike" button; tapping a cluster opens the "N vehicles here" list; the minimum-range picker removes short-range vehicles without a refetch; and the badge count on the basemap button tracks the toggles.

Then switch to the classic UIKit map (flag off) and confirm the "Plan a trip using this bike" button is still present and still works.

- [ ] **Step 10: Commit**

```bash
git add OBAKit/Sheet OBAKit/Mapping/Layers/RentalDetailViewController.swift \
  OBAKitTests/Sheet/AppSheetRouteTests.swift
git commit -m "Open rental detail and cluster sheets from the panel map"
```

---

## Self-review notes

**Spec coverage.** Every numbered section of the design maps to a task: §1 → Task 1, §2 → Tasks 2–3, §3 → Task 4, §4 → Tasks 5, 6, 7, 9, §5 → Task 8, §6 → Tasks 7 and 10, §7 → Task 10. The spec's testing section is distributed across the tasks that introduce each type.

**Known gaps handed to the implementer.** Three notes above flag things this plan could not verify by reading alone, each with a stated fallback: `Region`'s writable bikeshare properties (Task 4 Step 1), `MapRegionManager` accessor visibility (Task 6 Step 3), and OTPKit's `VehicleRentalStation` / `VehicleFormFactor` accessor names (Task 9 Step 4). None of them change a task's assertions.

**Build-order coupling.** Tasks 2/3 and 9/10 each leave the tree uncompilable between them, and both say so in their test steps. If executing task-by-task with a build gate, treat each pair as one unit.
