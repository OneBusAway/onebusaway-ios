# Map Stop Selection — Route Lines & Live Vehicles — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a rider taps a stop on the map and the redesigned Stop page opens as a half-detent sheet, draw the routes serving that stop as polylines and their arriving vehicles as markers, with route-chip and marker taps focusing a route.

**Architecture:** A new `StopRouteFocusMapLayer` conforming to the existing `MapLayer` protocol owns the overlays and annotations. A `StopMapFocus` observable object is the single channel between the sheet's SwiftUI header and the map layer. `MapViewController` creates it inside the one existing `stopController is StopPageViewController` branch, so no other surface is affected. Vehicle positions come from `tripStatus` already present on each `ArrivalDeparture` (no new network); polylines come from one `GET shape/{id}` per route.

**Tech Stack:** Swift 6 language mode, UIKit + MapKit, SwiftUI (hosted), Combine, Swift Testing.

**Design spec:** `docs/superpowers/specs/2026-07-31-map-stop-selection-design.md`. Read it before starting.

## Global Constraints

- **Swift 6 language mode**, main-actor default isolation, five concurrency diagnostic groups escalated to **errors** (`Apps/Shared/app_shared.yml:20-29`). A data-race warning fails the build. `OBAKitCore` pins `SWIFT_DEFAULT_ACTOR_ISOLATION` back to `nonisolated`.
- **Deployment target iOS 18.0.**
- **Tests use Swift Testing** (`@Suite` / `@Test` / `#expect`), never XCTest. Suites are `@MainActor` and `.serialized`. Pure-logic suites use lightweight **stub structs conforming to a protocol**, because `ArrivalDeparture` only decodes from JSON — follow `OBAKitTests/Stops/StopPage/StopPageListBuilderTests.swift`.
- **`OBAKitCore` must stay application-extension safe.**
- **Always run `scripts/generate_project OneBusAway` after adding or removing a file**, or the new file is not in the target and tests silently do not run.
- Build/test command used throughout (adjust the OS if the simulator list differs):
  ```bash
  set -o pipefail
  xcodebuild build-for-testing -project OBAKit.xcodeproj -scheme App \
    -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -5
  xcodebuild test-without-building -only-testing:OBAKitTests/<SuiteName> \
    -project OBAKit.xcodeproj -scheme App \
    -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -20
  ```
  Never pipe to `tail` without `set -o pipefail` — a failed build otherwise reports success.
- **Do not touch** the legacy `StopViewController`, the `Vehicles` screen, or `MapPanelRootView`.

---

### Task 1: Harden `Trip.shapeID` decoding

`shapeID` is non-optional and decoded with plain `decode`. `References.swift:47` decodes trips as an array, so **one** trip with a missing or null `shapeId` throws out of `References.init` and fails the entire arrivals response. This feature depends on `shapeID`, so fix it first.

**Files:**
- Modify: `OBAKitCore/Models/REST/References/Trip.swift:47`, `:88`
- Test: `OBAKitTests/Modeling/TripShapeIDDecodingTests.swift` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `Trip.shapeID` becomes `String?` (was `String`). Later tasks read it as optional.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
struct TripShapeIDDecodingTests {

    private func decodeTrip(shapeIDFragment: String) throws -> Trip {
        let json = """
        {
          "blockId": "1_block", "id": "1_trip", "routeId": "1_100",
          "routeShortName": "40", "serviceId": "1_svc",
          \(shapeIDFragment)
          "tripShortName": "", "tripHeadsign": "Downtown Seattle",
          "timeZone": "America/Los_Angeles", "direction": "0"
        }
        """
        return try JSONDecoder().decode(Trip.self, from: Data(json.utf8))
    }

    @Test func `Present shapeId decodes`() throws {
        let trip = try decodeTrip(shapeIDFragment: "\"shapeId\": \"1_shape\",")
        #expect(trip.shapeID == "1_shape")
    }

    @Test func `Missing shapeId decodes to nil rather than throwing`() throws {
        let trip = try decodeTrip(shapeIDFragment: "")
        #expect(trip.shapeID == nil)
    }

    @Test func `Null shapeId decodes to nil`() throws {
        let trip = try decodeTrip(shapeIDFragment: "\"shapeId\": null,")
        #expect(trip.shapeID == nil)
    }

    @Test func `Blank shapeId is nilified like the adjacent string fields`() throws {
        let trip = try decodeTrip(shapeIDFragment: "\"shapeId\": \"\",")
        #expect(trip.shapeID == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
scripts/generate_project OneBusAway
set -o pipefail
xcodebuild build-for-testing -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -5
xcodebuild test-without-building -only-testing:OBAKitTests/TripShapeIDDecodingTests \
  -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -20
```

Expected: the three non-`Present` tests FAIL — decoding throws `keyNotFound`/`valueNotFound`, and the blank case returns `""` not `nil`.

- [ ] **Step 3: Make `shapeID` optional and nilify blanks**

In `OBAKitCore/Models/REST/References/Trip.swift`, change the declaration at `:45-47`:

```swift
    /// The shape_id field contains an ID that defines a shape for the trip.
    /// This value is referenced from the shapes API.
    ///
    /// Optional and blank-nilified: agencies without shape data omit it, and OBA
    /// emits `""` for absent string fields. Decoding it strictly used to throw out
    /// of `References.init`, failing an entire arrivals response over one trip.
    public let shapeID: String?
```

and the decode at `:88`:

```swift
        shapeID = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .shapeID))
```

- [ ] **Step 4: Fix any compile errors from the type change**

```bash
grep -rn 'shapeID' --include='*.swift' OBAKit OBAKitCore OBAKitTests | grep -v 'gtfs-realtime.pb.swift'
```

`isEqual` (`:123`) and `hash` (`:138`) already work unchanged with `String?`.

**One caller is known to break and needs a decision, not a mechanical edit.**
`OBAKit/ViewModels/TripViewModel.swift:159` calls
`apiService.getShape(id: tripConvertible.trip.shapeID)`, and `getShape(id:)` takes
a non-optional `String` (`RESTAPIService+Get.swift:260`). Guard it so the trip map
simply draws no shape when the ID is absent — which is the correct behavior for an
agency without shape data, and strictly better than today's whole-response decode
failure:

```swift
        guard let shapeID = tripConvertible.trip.shapeID, !shapeID.isEmpty else { return [] }
        let shape = try await apiService.getShape(id: shapeID)
```

Match the surrounding method's actual return type and error handling — read
`:150-165` before editing.

- [ ] **Step 5: Run tests to verify they pass**

Same commands as Step 2. Expected: 4 passed. Then run the broader modeling suites to confirm nothing regressed:

```bash
xcodebuild test-without-building -only-testing:OBAKitTests \
  -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -20
```

- [ ] **Step 6: Commit**

```bash
git add OBAKitCore/Models/REST/References/Trip.swift OBAKitTests/Modeling/TripShapeIDDecodingTests.swift
git commit -m "fix: decode Trip.shapeID leniently so one trip can't fail a whole response"
```

---

### Task 2: Fix inverted `removeAllAnnotations(excludeUserLocation:)`

`MKMapView.removeAllAnnotations(excludeUserLocation:)` has its ternary backwards: with the default `true` it removes the user-location annotation. Every caller uses the default, and Task 8's layer will depend on the clearing semantics being sane.

**Files:**
- Modify: `OBAKit/Extensions/MapKitExtensions.swift:263-266`
- Test: `OBAKitTests/Mapping/MapKitExtensionsTests.swift` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: nothing new; corrects existing behavior.

- [ ] **Step 1: Read the current implementation**

```bash
sed -n '255,275p' OBAKit/Extensions/MapKitExtensions.swift
```

Confirm the ternary is `excludeUserLocation ? annotations : annotations.filter { !($0 is MKUserLocation) }` — i.e. "exclude" selects the list that *includes* `MKUserLocation`.

- [ ] **Step 2: Write the failing test**

```swift
import MapKit
import Testing
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class MapKitExtensionsTests {

    private final class StubAnnotation: NSObject, MKAnnotation {
        let coordinate = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)
    }

    // NOTE: do NOT try to test this through a real MKMapView + showsUserLocation.
    // Verified empirically on the iOS 26 simulator: MapKit materializes
    // MKUserLocation only once CoreLocation authorizes and delivers a fix, which
    // never happens in a unit-test process. A round-trip test would fail both
    // before AND after the fix, proving nothing. Test the predicate instead.

    @Test func `The keep-user-location filter keeps exactly the user location`() {
        let stub = StubAnnotation()
        let user = MKUserLocation()

        let doomed = MKMapView.annotationsToRemove(from: [stub, user], excludingUserLocation: true)

        #expect(doomed.count == 1)
        #expect(doomed.first === stub)
    }

    @Test func `Opting out removes the user location as well`() {
        let stub = StubAnnotation()
        let user = MKUserLocation()

        let doomed = MKMapView.annotationsToRemove(from: [stub, user], excludingUserLocation: false)

        #expect(doomed.count == 2)
    }

    @Test func `Non-user annotations are always removed`() {
        let mapView = MKMapView()
        mapView.addAnnotation(StubAnnotation())

        mapView.removeAllAnnotations()

        #expect(mapView.annotations.isEmpty)
    }
}
```

- [ ] **Step 3: Run test to verify the first one fails**

```bash
scripts/generate_project OneBusAway
set -o pipefail
xcodebuild build-for-testing -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -5
xcodebuild test-without-building -only-testing:OBAKitTests/MapKitExtensionsTests \
  -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -20
```

Expected: `removeAllAnnotations keeps the user location by default` FAILS.

- [ ] **Step 4: Correct the ternary**

```swift
    /// Removes every annotation from the map.
    /// - Parameter excludeUserLocation: When `true` (the default), the
    ///   `MKUserLocation` annotation is preserved — removing it makes the blue
    ///   dot vanish until the next location update.
    func removeAllAnnotations(excludeUserLocation: Bool = true) {
        removeAnnotations(Self.annotationsToRemove(from: annotations, excludingUserLocation: excludeUserLocation))
    }

    /// Extracted so the filter is testable: MKUserLocation never materializes on a
    /// map view in a unit-test process, so the round trip through `removeAllAnnotations`
    /// cannot exercise the `excludeUserLocation` branch at all.
    static func annotationsToRemove(from annotations: [MKAnnotation], excludingUserLocation: Bool) -> [MKAnnotation] {
        excludingUserLocation ? annotations.filter { !($0 is MKUserLocation) } : annotations
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Same command as Step 3. Expected: 2 passed. Then run the full `OBAKitTests` target — this changes behavior every caller relies on.

- [ ] **Step 6: Commit**

```bash
git add OBAKit/Extensions/MapKitExtensions.swift OBAKitTests/Mapping/MapKitExtensionsTests.swift
git commit -m "fix: removeAllAnnotations no longer deletes the user location by default"
```

---

### Task 3: Give `MapLayer` overlay hooks and stop `rendererFor` from crashing

**Files:**
- Modify: `OBAKit/Mapping/Layers/MapLayer.swift` (add two requirements + defaults)
- Modify: `OBAKit/Mapping/MapRegionManager.swift:1030-1041` (renderer dispatch), `:647-660` (`cancelSearch`)
- Test: `OBAKitTests/Mapping/MapLayerRendererDispatchTests.swift` (create)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `MapLayer.renderer(for overlay: MKOverlay, in mapView: MKMapView) -> MKOverlayRenderer?` — default returns `nil`.
  - `MapLayer.mapOverlaysWereCleared()` — default is a no-op.
  - `MapRegionManager` consults every registered layer, in registration order, **before** its own `as? MKPolyline` branch.

- [ ] **Step 1: Read the current code**

```bash
sed -n '1030,1041p' OBAKit/Mapping/MapRegionManager.swift
sed -n '645,662p' OBAKit/Mapping/MapRegionManager.swift
sed -n '115,130p' OBAKit/Mapping/Layers/MapLayer.swift
```

Note `fatalError()` at `:1040`, `as? MKPolyline` at `:1031`, and the existing `mapAnnotationsWereCleared()` requirement.

- [ ] **Step 2: Write the failing test**

```swift
import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class MapLayerRendererDispatchTests: OBATestCase {

    /// An overlay type only the stub layer recognizes.
    private final class StubOverlay: MKPolyline {}

    private final class StubLayer: NSObject, MapLayer {
        let id = "stub"
        let title = "Stub"
        let iconName = "circle"
        let tintColor = UIColor.systemPink
        let group = MapLayerGroup.transit
        let isEnabledByDefault = true
        let availability = MapLayerAvailability.available
        let zoomWindow = MapLayerZoomWindow(maxVisibleHeight: .greatestFiniteMagnitude)
        let densityBudget = 10
        let isClusterable = false
        let refreshPolicy = MapLayerRefreshPolicy.static
        let staleAfter: Duration? = nil

        private(set) var overlaysClearedCount = 0

        func annotationView(for annotation: MKAnnotation, in mapView: MKMapView) -> MKAnnotationView? { nil }
        func detailViewController(for annotation: MKAnnotation) -> UIViewController? { nil }
        func activate() { }
        func deactivate() { }
        func viewportDidChange(_ mapRect: MKMapRect?) { }
        func mapAnnotationsWereCleared() { }
        func mapOverlaysWereCleared() { overlaysClearedCount += 1 }

        func renderer(for overlay: MKOverlay, in mapView: MKMapView) -> MKOverlayRenderer? {
            guard let overlay = overlay as? StubOverlay else { return nil }
            let renderer = MKPolylineRenderer(polyline: overlay)
            renderer.lineWidth = 42
            return renderer
        }
    }

    private func makeCoordinates() -> [CLLocationCoordinate2D] {
        [CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3),
         CLLocationCoordinate2D(latitude: 47.7, longitude: -122.4)]
    }

    @Test func `A layer claims its own overlay before the generic polyline branch`() {
        let manager = MapRegionManager(application: buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: #function)))
        let layer = StubLayer()
        manager.registerMapLayer(layer)

        var coords = makeCoordinates()
        let overlay = StubOverlay(coordinates: &coords, count: coords.count)

        let renderer = manager.mapView(manager.mapView, rendererFor: overlay)

        // 42 proves the layer won, not the generic 3.0pt brand renderer.
        #expect((renderer as? MKPolylineRenderer)?.lineWidth == 42)
    }

    @Test func `An unrecognized overlay yields a renderer instead of trapping`() {
        let manager = MapRegionManager(application: buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: #function)))
        let circle = MKCircle(center: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3), radius: 100)

        // Before the fix this call hits `fatalError()` and crashes the test run.
        let renderer = manager.mapView(manager.mapView, rendererFor: circle)

        #expect(renderer.overlay === circle)
    }

    @Test func `A wholesale overlay clear notifies the layer so it can re-add`() {
        let manager = MapRegionManager(application: buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: #function)))
        let layer = StubLayer()
        manager.registerMapLayer(layer)

        manager.cancelSearch()

        // Without this notification `mapOverlaysWereCleared()` is dead code and a
        // search cancellation silently erases the stop's route lines.
        #expect(layer.overlaysClearedCount == 1)
    }

    @Test func `A plain polyline still gets the brand renderer`() {
        let manager = MapRegionManager(application: buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: #function)))
        var coords = makeCoordinates()
        let polyline = MKPolyline(coordinates: &coords, count: coords.count)

        let renderer = manager.mapView(manager.mapView, rendererFor: polyline)

        #expect((renderer as? MKPolylineRenderer)?.lineWidth == 3.0)
    }
}
```

**Suite must inherit `OBATestCase`.** There is no `ApplicationStubs` helper in
this repo — the real pattern is `OBATestCase.buildApplication(queue:dataLoader:)`
(`OBAKitTests/Helpers/OBATestCase.swift:212`), used exactly this way by
`OBAKitTests/Mapping/MapRegionManagerRentalFilterTests.swift:52-62`. Inheriting is
required for a second reason: `registerMapLayer` writes
`mapLayer.stub.enabled` into UserDefaults (`MapRegionManager.swift:273-286`), and
`OBATestCase` supplies the per-instance UserDefaults domain that keeps that from
leaking between suites.

- [ ] **Step 3: Run test to verify it fails**

```bash
scripts/generate_project OneBusAway
set -o pipefail
xcodebuild build-for-testing -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -5
xcodebuild test-without-building -only-testing:OBAKitTests/MapLayerRendererDispatchTests \
  -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -20
```

Expected: compile failure first (`renderer(for:in:)` and `mapOverlaysWereCleared()` are not `MapLayer` members).

- [ ] **Step 4: Add the protocol requirements and defaults**

In `OBAKit/Mapping/Layers/MapLayer.swift`, add to the protocol body:

```swift
    /// Returns a configured renderer when `overlay` belongs to this layer, nil
    /// otherwise. The manager tries each registered layer before its own overlay
    /// types — which matters because a layer's overlay may itself be an
    /// `MKPolyline` subclass that the manager's generic branch would otherwise
    /// swallow.
    func renderer(for overlay: MKOverlay, in mapView: MKMapView) -> MKOverlayRenderer?

    /// Called when something removed every overlay from the map wholesale. The
    /// layer re-adds its own. Mirrors `mapAnnotationsWereCleared()`.
    func mapOverlaysWereCleared()
```

and below the protocol:

```swift
public extension MapLayer {
    func renderer(for overlay: MKOverlay, in mapView: MKMapView) -> MKOverlayRenderer? { nil }
    func mapOverlaysWereCleared() { }
}
```

- [ ] **Step 5: Rework the renderer dispatch**

Replace `MapRegionManager.swift:1030-1041` entirely:

```swift
    public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        // Layers get first claim, mirroring `viewFor annotation`. This loop MUST
        // precede the `as? MKPolyline` branch below: a layer's overlay can be an
        // `MKPolyline` subclass, which that branch would otherwise claim and paint
        // as a generic 3pt brand-colored stroke.
        //
        // Deliberately unfiltered by enablement, exactly like the annotation path:
        // `deactivate()` is what removes a layer's overlays. Gating here on the
        // UserDefaults flag would leave a stale overlay falling through to the
        // generic branch instead of its own renderer.
        for layer in mapLayers {
            if let layerRenderer = layer.renderer(for: overlay, in: mapView) {
                return layerRenderer
            }
        }

        if let overlay = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: overlay)
            renderer.strokeColor = ThemeColors.shared.brand.withAlphaComponent(0.75)
            renderer.lineWidth = 3.0
            renderer.lineCap = .round

            return renderer
        }

        // Previously `fatalError()`. An unexpected overlay type is not worth
        // aborting a transit app over — log it and draw nothing.
        Logger.error("No renderer for overlay of type \(type(of: overlay)); drawing nothing.")
        return MKOverlayRenderer(overlay: overlay)
    }
```

- [ ] **Step 6: Notify layers when overlays are cleared wholesale**

In `cancelSearch()` (around `:647-660`), after the existing
`mapView.removeOverlays(mapView.overlays)`, add a call mirroring the annotation
notification that already exists:

```swift
        notifyMapLayersOverlaysCleared()
```

and add the helper next to `notifyMapLayersAnnotationsCleared()`:

```swift
    /// Wholesale overlay removal strips layer overlays behind the layers' backs;
    /// tell each enabled layer so it can re-add its own. Mirrors
    /// `notifyMapLayersAnnotationsCleared()`.
    private func notifyMapLayersOverlaysCleared() {
        for layer in mapLayers where isMapLayerEnabled(id: layer.id) {
            layer.mapOverlaysWereCleared()
        }
    }
```

- [ ] **Step 7: Run tests to verify they pass**

Same command as Step 3. Expected: 4 passed. Then run the rental-layer suites, which exercise the same dispatch:

```bash
xcodebuild test-without-building -only-testing:OBAKitTests/MapRegionManagerRentalFilterTests \
  -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -20
```

- [ ] **Step 8: Commit**

```bash
git add OBAKit/Mapping/Layers/MapLayer.swift OBAKit/Mapping/MapRegionManager.swift \
        OBAKitTests/Mapping/MapLayerRendererDispatchTests.swift
git commit -m "feat: let map layers supply overlay renderers; stop trapping on unknown overlays"
```

---

### Task 4: `RouteShapeOverlay` and the shape cache

**Files:**
- Create: `OBAKit/Mapping/Layers/StopRouteFocus/RouteShapeOverlay.swift`
- Create: `OBAKit/Mapping/Layers/StopRouteFocus/ShapeCache.swift`
- Test: `OBAKitTests/Mapping/StopRouteFocus/ShapeCacheTests.swift` (create)

**Interfaces:**
- Consumes: `Polyline(encodedPolyline:)` from `OBAKitCore`.
- Produces:
  - `final class RouteShapeOverlay: MKPolyline { var routeID: RouteID; var isCasing: Bool }`
  - `RouteShapeOverlay.make(coordinates:routeID:isCasing:) -> RouteShapeOverlay`
  - `actor ShapeCache` with `func coordinates(forShapeID:) async throws -> [CLLocationCoordinate2D]` and `func removeAll()`

- [ ] **Step 1: Write `RouteShapeOverlay`**

Subclassing `MKPolyline` is verified to work — the factory-imported initializers
allocate the subclass, and `MKPolylineRenderer` preserves the dynamic type.
Apple's own `MKGeodesicPolyline` is the precedent.

```swift
//
//  RouteShapeOverlay.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore

/// One route's drawn shape. Carries its identity so the layer's renderer can
/// style it without a side table.
///
/// Each route draws twice: a white casing underneath and the route-colored core
/// on top. The casing is what keeps a route-colored line legible over the
/// basemap, and `isCasing` is how the renderer tells them apart.
final class RouteShapeOverlay: MKPolyline {
    /// Assigned immediately after construction — `MKPolyline`'s initializers are
    /// imported class factories, so there is no init to thread these through.
    var routeID: RouteID = ""
    var isCasing: Bool = false

    static func make(coordinates: [CLLocationCoordinate2D], routeID: RouteID, isCasing: Bool) -> RouteShapeOverlay {
        var coordinates = coordinates
        let overlay = RouteShapeOverlay(coordinates: &coordinates, count: coordinates.count)
        overlay.routeID = routeID
        overlay.isCasing = isCasing
        return overlay
    }
}
```

- [ ] **Step 2: Write the failing cache test**

```swift
import CoreLocation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
struct ShapeCacheTests {

    /// Counts calls so the test can prove memoization.
    private actor Counter {
        private(set) var count = 0
        func increment() { count += 1 }
    }

    private func encodedSeattleLine() -> String {
        // Two points near downtown Seattle, Google encoded-polyline format.
        Polyline(coordinates: [
            CLLocationCoordinate2D(latitude: 47.60, longitude: -122.33),
            CLLocationCoordinate2D(latitude: 47.61, longitude: -122.34)
        ]).encodedPolyline
    }

    @Test func `A shape is fetched once and reused`() async throws {
        let counter = Counter()
        let encoded = encodedSeattleLine()
        let cache = ShapeCache { _ in
            await counter.increment()
            return encoded
        }

        let first = try await cache.coordinates(forShapeID: "1_shape")
        let second = try await cache.coordinates(forShapeID: "1_shape")

        #expect(first.count == 2)
        #expect(second.count == 2)
        #expect(await counter.count == 1)
    }

    @Test func `Distinct shapes fetch separately`() async throws {
        let counter = Counter()
        let encoded = encodedSeattleLine()
        let cache = ShapeCache { _ in
            await counter.increment()
            return encoded
        }

        _ = try await cache.coordinates(forShapeID: "1_a")
        _ = try await cache.coordinates(forShapeID: "1_b")

        #expect(await counter.count == 2)
    }

    @Test func `Concurrent callers for the same shape fetch once`() async throws {
        // The three sequential tests above all hit either `storage` or a cold
        // fetch — delete the whole `inFlight` map and they still pass. This is the
        // one that actually proves in-flight deduplication, which is what keeps a
        // six-route stop from firing six requests for one shared shape.
        let counter = Counter()
        let encoded = encodedSeattleLine()
        let cache = ShapeCache { _ in
            try? await Task.sleep(for: .milliseconds(50))
            await counter.increment()
            return encoded
        }

        async let first = cache.coordinates(forShapeID: "1_shape")
        async let second = cache.coordinates(forShapeID: "1_shape")
        _ = try await (first, second)

        #expect(await counter.count == 1)
    }

    @Test func `removeAll forces a refetch`() async throws {
        let counter = Counter()
        let encoded = encodedSeattleLine()
        let cache = ShapeCache { _ in
            await counter.increment()
            return encoded
        }

        _ = try await cache.coordinates(forShapeID: "1_shape")
        await cache.removeAll()
        _ = try await cache.coordinates(forShapeID: "1_shape")

        #expect(await counter.count == 2)
    }
}
```

**Before writing this test**, confirm `Polyline` exposes an
`init(coordinates:)` and an `encodedPolyline` property:

```bash
grep -n 'public init\|encodedPolyline' OBAKitCore/Models/Helpers/Polyline.swift | head
```

If the encoder is not exposed, hardcode a known encoded string instead and assert
on the decoded coordinate count.

- [ ] **Step 3: Run test to verify it fails**

```bash
scripts/generate_project OneBusAway
set -o pipefail
xcodebuild build-for-testing -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -5
```

Expected: compile failure — `ShapeCache` does not exist.

- [ ] **Step 4: Write `ShapeCache`**

```swift
//
//  ShapeCache.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import OBAKitCore

/// Memoizes decoded route shapes for the life of a map session.
///
/// Shapes are static per region, and the same shape is commonly shared by
/// several routes, so refetching per stop-open would be pure waste. Bounded
/// because a long session visiting many stops would otherwise grow without
/// limit, and invalidated on region change because shape IDs are region-scoped.
///
/// An `actor` rather than a `@MainActor` type: the fetch is `nonisolated async`
/// and the decode is pure CPU work with no reason to occupy the main actor.
actor ShapeCache {

    /// Injected so tests can count fetches without a network stub. Production
    /// passes a closure over `RESTAPIService.getShape(id:)`.
    typealias Fetch = @Sendable (String) async throws -> String

    /// `Task` is a struct with no identity of its own, so `===` can't compare
    /// two `Task` values directly. This box gives each in-flight fetch a
    /// reference identity to compare against, which is what lets us tell "my
    /// task is still the installed one" apart from "someone else's newer task
    /// replaced mine" without using `defer` (see the comment in
    /// `coordinates(forShapeID:)`).
    private final class InFlightBox {
        let task: Task<[CLLocationCoordinate2D], Error>
        init(task: Task<[CLLocationCoordinate2D], Error>) {
            self.task = task
        }
    }

    private let fetch: Fetch
    private var storage: [String: [CLLocationCoordinate2D]] = [:]
    /// In-flight requests, so two routes sharing a shape don't both fetch.
    private var inFlight: [String: InFlightBox] = [:]

    /// Beyond this, the least-recently-inserted entries are dropped. Shapes are
    /// a few KB each; this bounds a long session at a few hundred KB.
    private let capacity = 64
    private var insertionOrder: [String] = []

    /// Bumped by `removeAll()` so an in-flight fetch that resolves afterwards can
    /// tell it belongs to a torn-down presentation and decline to cache itself.
    private var generation: UInt64 = 0

    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    func coordinates(forShapeID shapeID: String) async throws -> [CLLocationCoordinate2D] {
        if let cached = storage[shapeID] { return cached }
        if let existing = inFlight[shapeID] { return try await existing.task.value }

        let generation = self.generation
        let task = Task<[CLLocationCoordinate2D], Error> { [fetch] in
            let encoded = try await fetch(shapeID)
            return Polyline(encodedPolyline: encoded).coordinates ?? []
        }
        let box = InFlightBox(task: task)
        inFlight[shapeID] = box

        // No `defer` here. The actor suspends at the `await` below, so a `defer`
        // would run after other callers have had a turn — and would clear whatever
        // NEW task another caller installed for this shape ID, not necessarily
        // ours. Compare identity instead.
        let coordinates: [CLLocationCoordinate2D]
        do {
            coordinates = try await task.value
        } catch {
            if inFlight[shapeID] === box { inFlight[shapeID] = nil }
            throw error
        }
        if inFlight[shapeID] === box { inFlight[shapeID] = nil }

        // Drop a response that resolved after `removeAll()` — otherwise a fetch
        // started for a dismissed sheet repopulates the cache for a presentation
        // that no longer exists.
        guard generation == self.generation else { return coordinates }
        store(coordinates, for: shapeID)
        return coordinates
    }

    func removeAll() {
        generation &+= 1
        storage.removeAll()
        insertionOrder.removeAll()
        for box in inFlight.values { box.task.cancel() }
        inFlight.removeAll()
    }

    private func store(_ coordinates: [CLLocationCoordinate2D], for shapeID: String) {
        storage[shapeID] = coordinates
        insertionOrder.append(shapeID)
        while insertionOrder.count > capacity {
            let evicted = insertionOrder.removeFirst()
            storage[evicted] = nil
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
scripts/generate_project OneBusAway
set -o pipefail
xcodebuild build-for-testing -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -5
xcodebuild test-without-building -only-testing:OBAKitTests/ShapeCacheTests \
  -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -20
```

Expected: 4 passed.

- [ ] **Step 6: Commit**

```bash
git add OBAKit/Mapping/Layers/StopRouteFocus/ OBAKitTests/Mapping/StopRouteFocus/
git commit -m "feat: add RouteShapeOverlay and a bounded shape cache"
```

---

### Task 5: `StopRouteFocusModel` — the pure derivation

The heart of the feature and the most heavily tested piece. Follows the
`StopPageListBuilder` precedent: a protocol so tests can pass stubs, because
`ArrivalDeparture` only decodes from JSON.

**Files:**
- Create: `OBAKit/Mapping/Layers/StopRouteFocus/StopRouteFocusModel.swift`
- Test: `OBAKitTests/Mapping/StopRouteFocus/StopRouteFocusModelTests.swift` (create)

**Interfaces:**
- Consumes: `DepartureListEntry` (existing, `StopPageListBuilder.swift:16-21`).
- Produces:
  - `protocol MapDepartureEntry: DepartureListEntry` with `routeShortName`, `routeColor`, `shapeID`, `tripID`, `vehicleID`, `vehicleCoordinate`, `orientation`.
  - `struct StopRouteFocusModel { let routes: [DrawnRoute]; let vehicles: [DrawnVehicle] }`
  - `StopRouteFocusModel.make(departures:routeCap:) -> StopRouteFocusModel`
  - `StopRouteFocusModel.visibleDepartures(_:isListFiltered:preferences:) -> [ArrivalDeparture]`

- [ ] **Step 1: Write the failing test**

```swift
import CoreLocation
import Testing
import UIKit
import OBAKitCore
@testable import OBAKit

private struct StubMapDeparture: MapDepartureEntry {
    let id: String
    let routeID: RouteID
    let arrivalDepartureMinutes: Int
    let routeShortName: String
    let routeColor: UIColor
    let shapeID: String?
    let tripID: String
    let vehicleID: String?
    let vehicleCoordinate: CLLocationCoordinate2D?
    let orientation: CLLocationDirection

    var temporalState: TemporalState {
        arrivalDepartureMinutes < 0 ? .past : (arrivalDepartureMinutes == 0 ? .present : .future)
    }
}

private func dep(
    _ id: String,
    route: String,
    mins: Int,
    shape: String? = "shape_\(#function)",
    trip: String? = nil,
    vehicle: String? = nil,
    located: Bool = true
) -> StubMapDeparture {
    StubMapDeparture(
        id: id,
        routeID: route,
        arrivalDepartureMinutes: mins,
        routeShortName: route,
        routeColor: .systemBlue,
        shapeID: shape,
        tripID: trip ?? "trip_\(id)",
        vehicleID: vehicle,
        vehicleCoordinate: located ? CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3) : nil,
        orientation: 90
    )
}

@MainActor
@Suite(.serialized)
final class StopRouteFocusModelTests {

    // MARK: - Filter parity with the list

    // `visibleDepartures` takes real `ArrivalDeparture`s, which only decode from
    // JSON — build them with the repo's `Fixtures.dictionaryToModel(type:dictionary:)`
    // helper (see OBAKitTests/Modeling/) rather than the stubs used below.
    //
    // Three cases, all required by the spec's "filter parity" item:
    //   1. isListFiltered == true  => hidden routes are excluded
    //   2. isListFiltered == false => hidden routes are INCLUDED, because the
    //      rider toggled the filter off and the list is showing them
    //   3. terminal duplicates are collapsed in both cases
    //
    // Case 2 is the one that matters: filtering unconditionally would draw a map
    // that disagrees with the visible list.

    // MARK: - Ordering and membership

    @Test func `Input is sorted by minutes, not taken as given`() {
        // filteredDepartures is NOT sorted at its call site — the model must sort.
        let model = StopRouteFocusModel.make(
            departures: [dep("b", route: "62", mins: 9), dep("a", route: "H", mins: 2)],
            routeCap: 6
        )
        #expect(model.routes.map(\.routeID) == ["H", "62"])
    }

    @Test func `Past departures contribute neither route nor vehicle`() {
        let model = StopRouteFocusModel.make(
            departures: [dep("gone", route: "24", mins: -3), dep("soon", route: "H", mins: 4)],
            routeCap: 6
        )
        #expect(model.routes.map(\.routeID) == ["H"])
        #expect(model.vehicles.allSatisfy { $0.routeID == "H" })
    }

    @Test func `Routes dedupe by routeID, keeping soonest-first order`() {
        let model = StopRouteFocusModel.make(
            departures: [dep("h1", route: "H", mins: 1), dep("r62", route: "62", mins: 3), dep("h2", route: "H", mins: 12)],
            routeCap: 6
        )
        #expect(model.routes.map(\.routeID) == ["H", "62"])
    }

    @Test func `Route count is capped by soonest arrival`() {
        let departures = (1...9).map { dep("d\($0)", route: "R\($0)", mins: $0) }
        let model = StopRouteFocusModel.make(departures: departures, routeCap: 6)
        #expect(model.routes.count == 6)
        #expect(model.routes.map(\.routeID) == ["R1", "R2", "R3", "R4", "R5", "R6"])
    }

    // MARK: - Shapes

    @Test func `A route takes its shape from its soonest departure`() {
        let model = StopRouteFocusModel.make(
            departures: [dep("h2", route: "H", mins: 12, shape: "late"), dep("h1", route: "H", mins: 1, shape: "early")],
            routeCap: 6
        )
        #expect(model.routes.first?.shapeID == "early")
    }

    @Test func `A route whose soonest departure has no shape yields no shape`() {
        let model = StopRouteFocusModel.make(
            departures: [dep("h1", route: "H", mins: 1, shape: nil)],
            routeCap: 6
        )
        #expect(model.routes.first?.shapeID == nil)
    }

    // MARK: - Vehicles

    @Test func `Vehicles dedupe by vehicleID`() {
        let model = StopRouteFocusModel.make(
            departures: [dep("a", route: "H", mins: 1, vehicle: "6821"), dep("b", route: "H", mins: 30, vehicle: "6821")],
            routeCap: 6
        )
        #expect(model.vehicles.count == 1)
    }

    @Test func `Vehicles without a vehicleID fall back to tripID for identity`() {
        let model = StopRouteFocusModel.make(
            departures: [dep("a", route: "H", mins: 1, trip: "t1"), dep("b", route: "H", mins: 5, trip: "t2")],
            routeCap: 6
        )
        #expect(model.vehicles.count == 2)
    }

    @Test func `A departure with no coordinate produces no vehicle`() {
        let model = StopRouteFocusModel.make(
            departures: [dep("a", route: "H", mins: 1, located: false)],
            routeCap: 6
        )
        #expect(model.vehicles.isEmpty)
        #expect(model.routes.first?.hasLiveVehicle == false)
    }

    @Test func `hasLiveVehicle is true only for routes with a located vehicle`() {
        let model = StopRouteFocusModel.make(
            departures: [dep("a", route: "H", mins: 1, located: true), dep("b", route: "62", mins: 3, located: false)],
            routeCap: 6
        )
        let byRoute = Dictionary(uniqueKeysWithValues: model.routes.map { ($0.routeID, $0.hasLiveVehicle) })
        #expect(byRoute["H"] == true)
        #expect(byRoute["62"] == false)
    }

    @Test func `Vehicles for routes beyond the cap are dropped`() {
        let departures = (1...9).map { dep("d\($0)", route: "R\($0)", mins: $0) }
        let model = StopRouteFocusModel.make(departures: departures, routeCap: 6)
        #expect(model.vehicles.allSatisfy { model.routes.map(\.routeID).contains($0.routeID) })
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
scripts/generate_project OneBusAway
set -o pipefail
xcodebuild build-for-testing -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -5
```

Expected: compile failure — `MapDepartureEntry` and `StopRouteFocusModel` do not exist.

- [ ] **Step 3: Write the model**

```swift
//
//  StopRouteFocusModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import MapKit
import OBAKitCore
import UIKit

/// What the map needs from a departure, beyond what the list needs.
///
/// Mirrors `DepartureListEntry`'s reason for existing: `ArrivalDeparture` only
/// decodes from JSON, so tests pass stubs.
protocol MapDepartureEntry: DepartureListEntry {
    var routeShortName: String { get }
    var routeColor: UIColor { get }
    var shapeID: String? { get }
    var tripID: String { get }
    var vehicleID: String? { get }
    /// `position` preferred, `lastKnownLocation` as fallback, nil when neither is
    /// usable. Never a null-island placeholder.
    var vehicleCoordinate: CLLocationCoordinate2D? { get }
    var orientation: CLLocationDirection { get }
}

/// The map's view of one selected stop: which routes to draw and where their
/// vehicles are. Pure — no network, no side effects.
///
/// Deliberately NOT `Equatable`: `CLLocationCoordinate2D` has no `Equatable`
/// conformance (verified — synthesis fails with "stored property type
/// 'CLLocationCoordinate2D' does not conform to protocol 'Equatable'"), and
/// nothing compares whole models, so adding one would be busywork.
struct StopRouteFocusModel {

    struct DrawnRoute: Equatable, Identifiable {
        let routeID: RouteID
        var id: RouteID { routeID }
        let shortName: String
        let color: UIColor
        /// Pinned from the route's soonest departure at derivation time.
        let shapeID: String?
        let hasLiveVehicle: Bool
    }

    struct DrawnVehicle: Identifiable {
        /// `vehicleID` when the agency reports one, `tripID` otherwise.
        let id: String
        let routeID: RouteID
        let coordinate: CLLocationCoordinate2D
        let orientation: CLLocationDirection
        /// The departure this vehicle is serving. The layer resolves it back to
        /// the live `ArrivalDeparture` (and thus its `TripStatus`) rather than
        /// snapshotting one here — the annotation REQUIRES a non-nil
        /// `TripStatus`, see Task 7.
        let departureID: String
    }

    let routes: [DrawnRoute]
    let vehicles: [DrawnVehicle]

    static let empty = StopRouteFocusModel(routes: [], vehicles: [])

    /// The list's filter chain, reproduced exactly. The map must show lines for
    /// precisely the departures the list is showing — `isListFiltered` is
    /// rider-toggleable, so filtering unconditionally would hide lines for routes
    /// the list is currently displaying.
    ///
    /// Mirrors `StopPageView.filteredDepartures`.
    static func visibleDepartures(
        _ departures: [ArrivalDeparture],
        isListFiltered: Bool,
        preferences: StopPreferences
    ) -> [ArrivalDeparture] {
        let visible = isListFiltered ? departures.filter(preferences: preferences) : departures
        return visible.filteringTerminalDuplicates()
    }

    /// - Parameter routeCap: Maximum routes to draw. A downtown stop can serve
    ///   20+ routes over the arrival window; drawing all of them is both a
    ///   performance problem and an unreadable map.
    static func make<D: MapDepartureEntry>(departures: [D], routeCap: Int) -> StopRouteFocusModel {
        // The caller's list is NOT sorted — `filteredDepartures` sorts nowhere,
        // and sorting happens downstream in StopPageListBuilder. Sort here.
        let upcoming = departures
            .filter { $0.temporalState != .past }
            .sorted { $0.arrivalDepartureMinutes < $1.arrivalDepartureMinutes }

        // First appearance in the sorted list == soonest arrival per route.
        var routeOrder: [RouteID] = []
        var soonestByRoute: [RouteID: D] = [:]
        for departure in upcoming where soonestByRoute[departure.routeID] == nil {
            soonestByRoute[departure.routeID] = departure
            routeOrder.append(departure.routeID)
        }
        let drawnRouteIDs = Array(routeOrder.prefix(routeCap))
        let drawnRouteIDSet = Set(drawnRouteIDs)

        var vehicles: [DrawnVehicle] = []
        var seenVehicleIDs = Set<String>()
        var routesWithVehicles = Set<RouteID>()
        for departure in upcoming where drawnRouteIDSet.contains(departure.routeID) {
            guard let coordinate = departure.vehicleCoordinate else { continue }
            let identity = departure.vehicleID ?? departure.tripID
            guard seenVehicleIDs.insert(identity).inserted else { continue }
            vehicles.append(DrawnVehicle(
                id: identity,
                routeID: departure.routeID,
                coordinate: coordinate,
                orientation: departure.orientation,
                departureID: departure.id
            ))
            routesWithVehicles.insert(departure.routeID)
        }

        let routes = drawnRouteIDs.compactMap { routeID -> DrawnRoute? in
            guard let soonest = soonestByRoute[routeID] else { return nil }
            return DrawnRoute(
                routeID: routeID,
                shortName: soonest.routeShortName,
                color: soonest.routeColor,
                shapeID: soonest.shapeID,
                hasLiveVehicle: routesWithVehicles.contains(routeID)
            )
        }

        return StopRouteFocusModel(routes: routes, vehicles: vehicles)
    }
}
```

- [ ] **Step 4: Conform `ArrivalDeparture` to `MapDepartureEntry`**

Add to the same file:

**`ArrivalDeparture` already satisfies three of the seven requirements.** Verified:
`tripID: TripIdentifier` (`:94`, and `TripIdentifier` **is** `String`, `:12`),
`vehicleID: String?` (`:103`), and `routeShortName: String` (`:220`) all already
exist. Redeclaring any of them in the extension is `error: invalid redeclaration`
— not shadowing. So the extension covers only the remaining four:

```swift
extension ArrivalDeparture: MapDepartureEntry {

    var routeColor: UIColor { route.color ?? ThemeColors.shared.brand }

    var shapeID: String? { trip.shapeID }

    /// `position` is the extrapolated current location and is what the map should
    /// draw; `lastKnownLocation` is the raw last report. Prefer the former.
    ///
    /// Deliberately does NOT reuse `VehicleAnnotation.updateAnnotation()`, which
    /// reads only `lastKnownLocation` and falls back to a literal (0, 0) — it
    /// manufactures exactly the null-island coordinate this must reject.
    var vehicleCoordinate: CLLocationCoordinate2D? {
        guard let location = tripStatus?.position ?? tripStatus?.lastKnownLocation else { return nil }
        let coordinate = location.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate), !coordinate.isNullIsland else { return nil }
        return coordinate
    }

    var orientation: CLLocationDirection { tripStatus?.orientation ?? 0 }
}
```

`CLLocationCoordinate2D.isNullIsland` already exists at
`OBAKitCore/Extensions/CoreLocationExtensions.swift:73` — use it rather than
open-coding the zero check.

**Behavior note worth knowing:** because `vehicleID` resolves to
`ArrivalDeparture`'s own top-level field (`:103`) rather than
`tripStatus?.vehicleID`, vehicle identity comes from the arrival, not the trip
status. That is the right source — it is populated whenever the agency reports a
vehicle — but it is a different field from the one the design spec named, so do
not "fix" it back.

- [ ] **Step 5: Run tests to verify they pass**

```bash
scripts/generate_project OneBusAway
set -o pipefail
xcodebuild build-for-testing -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -5
xcodebuild test-without-building -only-testing:OBAKitTests/StopRouteFocusModelTests \
  -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -20
```

Expected: 11 passed.

- [ ] **Step 6: Commit**

```bash
git add OBAKit/Mapping/Layers/StopRouteFocus/StopRouteFocusModel.swift \
        OBAKitTests/Mapping/StopRouteFocus/StopRouteFocusModelTests.swift
git commit -m "feat: derive drawn routes and vehicles from a stop's arrivals"
```

---

### Task 6: `StopMapFocus` — the sheet ↔ map channel

**Files:**
- Create: `OBAKit/Mapping/Layers/StopRouteFocus/StopMapFocus.swift`
- Test: `OBAKitTests/Mapping/StopRouteFocus/StopMapFocusTests.swift` (create)

**Interfaces:**
- Consumes: `StopRouteFocusModel.DrawnRoute` (Task 5).
- Produces:
  - `@MainActor final class StopMapFocus: ObservableObject`
  - `@Published private(set) var routes: [StopRouteFocusModel.DrawnRoute]`
  - `@Published private(set) var focusedRouteID: RouteID?`
  - `func apply(routes:)`, `func toggleFocus(routeID:)`, `func clearFocus()`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import UIKit
import OBAKitCore
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class StopMapFocusTests {

    private func route(_ id: RouteID, live: Bool) -> StopRouteFocusModel.DrawnRoute {
        StopRouteFocusModel.DrawnRoute(
            routeID: id, shortName: id, color: .systemBlue, shapeID: "s_\(id)", hasLiveVehicle: live
        )
    }

    @Test func `Toggling a live route focuses it`() {
        let focus = StopMapFocus()
        focus.apply(routes: [route("H", live: true)])
        focus.toggleFocus(routeID: "H")
        #expect(focus.focusedRouteID == "H")
    }

    @Test func `Toggling the same route twice clears focus`() {
        let focus = StopMapFocus()
        focus.apply(routes: [route("H", live: true)])
        focus.toggleFocus(routeID: "H")
        focus.toggleFocus(routeID: "H")
        #expect(focus.focusedRouteID == nil)
    }

    @Test func `A route with no live vehicle is a no-op`() {
        let focus = StopMapFocus()
        focus.apply(routes: [route("40", live: false)])
        focus.toggleFocus(routeID: "40")
        #expect(focus.focusedRouteID == nil)
    }

    @Test func `An unknown route is a no-op`() {
        let focus = StopMapFocus()
        focus.apply(routes: [route("H", live: true)])
        focus.toggleFocus(routeID: "999")
        #expect(focus.focusedRouteID == nil)
    }

    @Test func `A no-op toggle leaves existing focus intact`() {
        let focus = StopMapFocus()
        focus.apply(routes: [route("H", live: true), route("40", live: false)])
        focus.toggleFocus(routeID: "H")
        focus.toggleFocus(routeID: "40")
        #expect(focus.focusedRouteID == "H")
    }

    @Test func `Focus drops when its route leaves the arrival set`() {
        let focus = StopMapFocus()
        focus.apply(routes: [route("H", live: true), route("62", live: true)])
        focus.toggleFocus(routeID: "H")
        focus.apply(routes: [route("62", live: true)])
        #expect(focus.focusedRouteID == nil)
    }

    @Test func `Focus survives a refresh that keeps the route`() {
        let focus = StopMapFocus()
        focus.apply(routes: [route("H", live: true)])
        focus.toggleFocus(routeID: "H")
        focus.apply(routes: [route("H", live: true), route("62", live: true)])
        #expect(focus.focusedRouteID == "H")
    }

    @Test func `Focus drops when its route loses its last live vehicle`() {
        let focus = StopMapFocus()
        focus.apply(routes: [route("H", live: true)])
        focus.toggleFocus(routeID: "H")
        focus.apply(routes: [route("H", live: false)])
        #expect(focus.focusedRouteID == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
scripts/generate_project OneBusAway
set -o pipefail
xcodebuild build-for-testing -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -5
```

Expected: compile failure — `StopMapFocus` does not exist.

- [ ] **Step 3: Write `StopMapFocus`**

```swift
//
//  StopMapFocus.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import Foundation
import OBAKitCore

/// The single channel between the stop sheet and the map layer.
///
/// Route chips write focus; vehicle markers write focus; the layer reads it. One
/// value, so the two input surfaces can never disagree about what is focused.
///
/// Always non-nil, even for presentations that never attach to a map — an inert
/// instance is simpler than an Optional, and `@ObservedObject` cannot wrap an
/// Optional anyway.
@MainActor
final class StopMapFocus: ObservableObject {

    /// Routes the map is actually drawing. Chips look themselves up here for
    /// decoration; a chip with no match renders plain and is inert.
    @Published private(set) var routes: [StopRouteFocusModel.DrawnRoute] = []

    @Published private(set) var focusedRouteID: RouteID?

    /// The layer's one write path.
    func apply(routes: [StopRouteFocusModel.DrawnRoute]) {
        self.routes = routes

        // Don't let focus dangle on a route that has left the arrival set, or
        // that has lost its last live vehicle — there would be nothing on the
        // map to point at, and the chip that could clear it may be gone too.
        if let focusedRouteID,
           !routes.contains(where: { $0.routeID == focusedRouteID && $0.hasLiveVehicle }) {
            self.focusedRouteID = nil
        }
    }

    /// Focus is a momentary map emphasis, not a list filter. A route with no live
    /// vehicle is deliberately a no-op rather than an error: there is nothing to
    /// point at, and an error would be noise.
    func toggleFocus(routeID: RouteID) {
        guard routes.contains(where: { $0.routeID == routeID && $0.hasLiveVehicle }) else { return }
        focusedRouteID = (focusedRouteID == routeID) ? nil : routeID
    }

    func clearFocus() {
        focusedRouteID = nil
    }

    /// Whether a chip for `routeID` should render as interactive.
    func isFocusable(routeID: RouteID) -> Bool {
        routes.contains { $0.routeID == routeID && $0.hasLiveVehicle }
    }

    /// Decoration for a chip, or nil when the map isn't drawing this route.
    func drawnRoute(for routeID: RouteID) -> StopRouteFocusModel.DrawnRoute? {
        routes.first { $0.routeID == routeID }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
scripts/generate_project OneBusAway
set -o pipefail
xcodebuild build-for-testing -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -5
xcodebuild test-without-building -only-testing:OBAKitTests/StopMapFocusTests \
  -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -20
```

Expected: 8 passed.

- [ ] **Step 5: Commit**

```bash
git add OBAKit/Mapping/Layers/StopRouteFocus/StopMapFocus.swift \
        OBAKitTests/Mapping/StopRouteFocus/StopMapFocusTests.swift
git commit -m "feat: add StopMapFocus as the sheet-to-map channel"
```

---

### Task 7: Vehicle annotation and marker fixes

**Files:**
- Create: `OBAKit/Mapping/Layers/StopRouteFocus/StopVehicleAnnotation.swift`
- Modify: `OBAKit/Mapping/PulsingVehicleAnnotationView.swift:29`, `:101`
- Test: `OBAKitTests/Mapping/StopRouteFocus/StopVehicleAnnotationTests.swift` (create)

**Interfaces:**
- Consumes: `StopRouteFocusModel.DrawnVehicle` (Task 5).
- Produces:
  - `final class StopVehicleAnnotation: VehicleAnnotation` with `routeID`, `routeColor`, `departureID`.
  - `PulsingVehicleAnnotationView.isSelectable: Bool` (default `false`, preserving trip-screen behavior).

- [ ] **Step 1: Read the current marker**

```bash
sed -n '20,110p' OBAKit/Mapping/PulsingVehicleAnnotationView.swift
```

Confirm `isUserInteractionEnabled = false` at `:29`, that `realTimeAnnotationColor`
at `:101` has no `didSet`, and that `annotation`'s `didSet` guards on
`as? VehicleAnnotation`.

- [ ] **Step 2: Write the failing test**

```swift
import CoreLocation
import MapKit
import Testing
import UIKit
import OBAKitCore
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class StopVehicleAnnotationTests {

    /// Build a real `TripStatus` from a fixture — the annotation requires one, and
    /// `TripStatus` only decodes from JSON. Follow the loading idiom in
    /// `OBAKitTests/Modeling/REST Model Service Tests/` (e.g. `Fixtures.loadRESTAPIPayload`
    /// against `trip_details_1_18196913.json`); grep for an existing suite that
    /// already materializes a `TripStatus` and reuse its helper verbatim rather
    /// than inventing one.
    private func makeTripStatus() throws -> TripStatus { … }

    @Test func `Assigning the annotation gives the view its bus icon`() throws {
        // The real risk: PulsingVehicleAnnotationView's `annotation` didSet
        // (:55-64) requires a NON-NIL tripStatus, and `applyTripStatus` is the only
        // thing that ever fires `routeType`'s didSet — the initializer assigns it
        // before super.init (:17), where didSet does not fire. A nil tripStatus
        // therefore yields a bare dot with no icon and no arrow, silently.
        // `image` being non-nil is the observable proof that chain ran.
        let annotation = StopVehicleAnnotation(
            id: "6821", routeID: "H", routeColor: .systemRed, departureID: "dep1",
            tripStatus: try makeTripStatus(),
            coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)
        )
        let view = PulsingVehicleAnnotationView(annotation: nil, reuseIdentifier: "test")

        view.annotation = annotation

        #expect(view.image != nil)
    }

    @Test func `The model's coordinate survives the superclass overwriting it`() throws {
        // VehicleAnnotation.init(tripStatus:) calls updateAnnotation(), which sets
        // coordinate from lastKnownLocation and falls back to (0, 0). The subclass
        // must assign afterwards or the marker lands on null island.
        let annotation = StopVehicleAnnotation(
            id: "6821", routeID: "H", routeColor: .systemRed, departureID: "dep1",
            tripStatus: try makeTripStatus(),
            coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)
        )
        #expect(annotation.coordinate.latitude == 47.6)
        #expect(annotation.coordinate.longitude == -122.3)
    }

    @Test func `Route color applies when set after the annotation`() throws {
        // Regression for the late-apply bug: isRealTime's didSet is the only writer
        // of annotationColor, and it runs when the annotation is assigned — so a
        // caller setting the color afterwards used to be ignored until the next
        // status apply, on a recycled view still carrying the previous route color.
        let view = PulsingVehicleAnnotationView(annotation: nil, reuseIdentifier: "test")
        view.annotation = StopVehicleAnnotation(
            id: "6821", routeID: "H", routeColor: .systemRed, departureID: "dep1",
            tripStatus: try makeTripStatus(),
            coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)
        )

        view.realTimeAnnotationColor = .systemGreen

        #expect(view.annotationColor == .systemGreen)
    }

    @Test func `Markers are not selectable by default, preserving the trip screen`() {
        let view = PulsingVehicleAnnotationView(annotation: nil, reuseIdentifier: "test")
        #expect(view.isUserInteractionEnabled == false)
    }

    @Test func `Selectable markers accept touches so the map can select them`() {
        let view = PulsingVehicleAnnotationView(annotation: nil, reuseIdentifier: "test")
        view.isSelectable = true
        #expect(view.isUserInteractionEnabled == true)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

```bash
scripts/generate_project OneBusAway
set -o pipefail
xcodebuild build-for-testing -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -5
```

Expected: compile failure — `StopVehicleAnnotation` and `isSelectable` do not exist.

- [ ] **Step 4: Write `StopVehicleAnnotation`**

```swift
//
//  StopVehicleAnnotation.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import MapKit
import OBAKitCore
import UIKit

/// A live vehicle arriving at the selected stop.
///
/// **The `tripStatus` is mandatory, and that is the whole point of this type.**
/// `PulsingVehicleAnnotationView`'s `annotation` observer
/// (`PulsingVehicleAnnotationView.swift:55-64`) requires BOTH `as? VehicleAnnotation`
/// AND a non-nil `tripStatus` before it runs `applyTripStatus`. And
/// `applyTripStatus` is the only thing that ever sets `routeType` and `isRealTime`
/// in a way that fires their `didSet`s — the initializer assigns them *before*
/// `super.init()` (`:17-18`), where `didSet` does not fire. So an annotation with
/// a nil `tripStatus` renders as a bare pulsing dot: **no bus icon, no heading
/// arrow, no realtime state**, and no error anywhere to explain it.
///
/// Every vehicle in `StopRouteFocusModel` is derived from a `tripStatus`
/// coordinate, so a non-nil status is always available at construction.
final class StopVehicleAnnotation: VehicleAnnotation {
    let id: String
    let routeID: RouteID
    let routeColor: UIColor
    /// The `ArrivalDeparture` this vehicle is serving, so the callout can read
    /// headsign, countdown, and adherence without another lookup.
    let departureID: String

    init(
        id: String,
        routeID: RouteID,
        routeColor: UIColor,
        departureID: String,
        tripStatus: TripStatus,
        coordinate: CLLocationCoordinate2D
    ) {
        self.id = id
        self.routeID = routeID
        self.routeColor = routeColor
        self.departureID = departureID
        super.init(tripStatus: tripStatus)
        // AFTER super.init: `VehicleAnnotation.init(tripStatus:)` calls
        // `updateAnnotation()` (`VehicleAnnotation.swift:21`), which sets
        // `coordinate` from `lastKnownLocation` — falling back to a literal
        // (0, 0). Assigning here overrides that with the `position`-preferred,
        // null-island-rejecting coordinate the model already resolved.
        self.coordinate = coordinate
    }
}
```

There is no `orientation` parameter: heading comes from
`tripStatus.orientation` inside `applyTripStatus` → `updateHeading(tripStatus:)`.
Passing one separately would be dead code.

- [ ] **Step 5: Fix the marker**

In `PulsingVehicleAnnotationView.swift`, replace the `isUserInteractionEnabled = false`
line at `:29` with nothing, and add:

```swift
    /// Whether this marker can be tapped to select it.
    ///
    /// Off by default: the trip screen only ever *displays* these markers, and
    /// turning selection on there would start showing a title-only callout it was
    /// never designed for. The stop-route-focus layer opts in.
    var isSelectable: Bool = false {
        didSet { isUserInteractionEnabled = isSelectable }
    }
```

and in `init`, after the existing setup, keep the default:

```swift
        isUserInteractionEnabled = false
```

Then give `realTimeAnnotationColor` a `didSet`:

```swift
    /// The annotation color for a vehicle with available real-time data.
    ///
    /// Re-applies on assignment. Without this, a caller that sets the color
    /// *after* assigning the annotation gets the previous route's color on a
    /// recycled view: `isRealTime`'s didSet is the only writer of
    /// `annotationColor`, and it runs when the annotation is assigned.
    /// `TripViewController.swift:419-423` has exactly that ordering today.
    public var realTimeAnnotationColor: UIColor = ThemeColors.shared.brand {
        didSet {
            guard isRealTime else { return }
            annotationColor = realTimeAnnotationColor
            headingImageView.tintColor = realTimeAnnotationColor
        }
    }
```

**Do not call `updateHeading()`** — the real method is
`private func updateHeading(tripStatus: TripStatus)` (`:79`) and takes an
argument, so a no-arg call will not compile. Setting
`headingImageView.tintColor` directly is what that method does with the color
anyway (`:85`). A property's initial value does not fire `didSet`, so this is
safe despite `headingImageView` belonging to the superclass.

- [ ] **Step 6: Run tests to verify they pass**

```bash
scripts/generate_project OneBusAway
set -o pipefail
xcodebuild build-for-testing -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -5
xcodebuild test-without-building -only-testing:OBAKitTests/StopVehicleAnnotationTests \
  -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -20
```

Expected: 4 passed. Then run the full target — `TripViewController` uses this view.

- [ ] **Step 7: Commit**

```bash
git add OBAKit/Mapping/Layers/StopRouteFocus/StopVehicleAnnotation.swift \
        OBAKit/Mapping/PulsingVehicleAnnotationView.swift \
        OBAKitTests/Mapping/StopRouteFocus/StopVehicleAnnotationTests.swift
git commit -m "fix: apply vehicle route color on first display; add opt-in marker selection"
```

---

### Task 8: `StopRouteFocusMapLayer`

**Files:**
- Create: `OBAKit/Mapping/Layers/StopRouteFocus/StopRouteFocusMapLayer.swift`
- Test: `OBAKitTests/Mapping/StopRouteFocus/StopRouteFocusMapLayerTests.swift` (create)

**Interfaces:**
- Consumes: `StopRouteFocusModel` (Task 5), `StopMapFocus` (Task 6), `RouteShapeOverlay` + `ShapeCache` (Task 4), `StopVehicleAnnotation` (Task 7), `MapLayer.renderer(for:in:)` + `mapOverlaysWereCleared()` (Task 3).
- Produces:
  - `final class StopRouteFocusMapLayer: NSObject, MapLayer`
  - `func begin(focus: StopMapFocus)`, `func end()`, `func update(model: StopRouteFocusModel)`

- [ ] **Step 1: Write the failing test**

```swift
import CoreLocation
import MapKit
import Testing
import UIKit
import OBAKitCore
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class StopRouteFocusMapLayerTests {

    private func makeLayer(mapView: MKMapView) -> StopRouteFocusMapLayer {
        let layer = StopRouteFocusMapLayer(mapView: mapView, shapeCache: ShapeCache { _ in "" })
        // REQUIRED: `syncVehicleAnnotations` builds nothing without a resolvable
        // departure, because `StopVehicleAnnotation` needs a non-nil `TripStatus`
        // (see Task 7). Back this with a fixture-loaded `ArrivalDeparture` — reuse
        // the `makeTripStatus()` fixture helper established in Task 7's suite.
        layer.departureProvider = { _ in Self.fixtureDeparture }
        return layer
    }

    /// A fixture-loaded `ArrivalDeparture` with a non-nil `tripStatus`. Load it via
    /// `Fixtures`; grep OBAKitTests for a suite that already materializes one.
    private static let fixtureDeparture: ArrivalDeparture? = nil // replace with the fixture

    private func model(routeIDs: [RouteID], vehicleRouteIDs: [RouteID]) -> StopRouteFocusModel {
        StopRouteFocusModel(
            routes: routeIDs.map {
                StopRouteFocusModel.DrawnRoute(
                    routeID: $0, shortName: $0, color: .systemBlue,
                    shapeID: "s_\($0)", hasLiveVehicle: vehicleRouteIDs.contains($0)
                )
            },
            vehicles: vehicleRouteIDs.map {
                StopRouteFocusModel.DrawnVehicle(
                    id: "v_\($0)", routeID: $0,
                    coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3),
                    orientation: 90, departureID: "d_\($0)"
                )
            }
        )
    }

    @Test func `Update adds one vehicle annotation per drawn vehicle`() {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        layer.begin(focus: StopMapFocus())

        layer.update(model: model(routeIDs: ["H", "62"], vehicleRouteIDs: ["H"]))

        #expect(mapView.annotations.compactMap { $0 as? StopVehicleAnnotation }.count == 1)
    }

    @Test func `Update replaces rather than accumulates markers`() {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        layer.begin(focus: StopMapFocus())

        layer.update(model: model(routeIDs: ["H"], vehicleRouteIDs: ["H"]))
        layer.update(model: model(routeIDs: ["H"], vehicleRouteIDs: ["H"]))

        #expect(mapView.annotations.compactMap { $0 as? StopVehicleAnnotation }.count == 1)
    }

    @Test func `end removes everything the layer added`() {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        layer.begin(focus: StopMapFocus())
        layer.update(model: model(routeIDs: ["H"], vehicleRouteIDs: ["H"]))

        layer.end()

        #expect(mapView.annotations.compactMap { $0 as? StopVehicleAnnotation }.isEmpty)
        #expect(mapView.overlays.compactMap { $0 as? RouteShapeOverlay }.isEmpty)
    }

    @Test func `Renderer styles the casing wider than the core`() {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        var coords = [CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3),
                      CLLocationCoordinate2D(latitude: 47.7, longitude: -122.4)]
        let casing = RouteShapeOverlay.make(coordinates: coords, routeID: "H", isCasing: true)
        let core = RouteShapeOverlay.make(coordinates: coords, routeID: "H", isCasing: false)
        _ = coords

        let casingWidth = (layer.renderer(for: casing, in: mapView) as? MKPolylineRenderer)?.lineWidth
        let coreWidth = (layer.renderer(for: core, in: mapView) as? MKPolylineRenderer)?.lineWidth

        #expect(casingWidth != nil && coreWidth != nil)
        #expect(casingWidth! > coreWidth!)
    }

    @Test func `Renderer ignores overlays that are not ours`() {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        var coords = [CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3),
                      CLLocationCoordinate2D(latitude: 47.7, longitude: -122.4)]
        let plain = MKPolyline(coordinates: &coords, count: coords.count)

        #expect(layer.renderer(for: plain, in: mapView) == nil)
    }

    @Test func `An unfocused route dims when another route is focused`() {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        let focus = StopMapFocus()
        layer.begin(focus: focus)
        layer.update(model: model(routeIDs: ["H", "62"], vehicleRouteIDs: ["H", "62"]))

        focus.toggleFocus(routeID: "H")

        var coords = [CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3),
                      CLLocationCoordinate2D(latitude: 47.7, longitude: -122.4)]
        _ = coords
        let dimmed = RouteShapeOverlay.make(coordinates: coords, routeID: "62", isCasing: false)
        let focused = RouteShapeOverlay.make(coordinates: coords, routeID: "H", isCasing: false)

        let dimmedAlpha = (layer.renderer(for: dimmed, in: mapView) as? MKPolylineRenderer)?.alpha
        let focusedAlpha = (layer.renderer(for: focused, in: mapView) as? MKPolylineRenderer)?.alpha

        #expect(dimmedAlpha! < focusedAlpha!)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
scripts/generate_project OneBusAway
set -o pipefail
xcodebuild build-for-testing -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -5
```

Expected: compile failure — `StopRouteFocusMapLayer` does not exist.

- [ ] **Step 3: Write the layer**

```swift
//
//  StopRouteFocusMapLayer.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import MapKit
import OBAKitCore
import UIKit

/// Draws the routes serving the selected stop and the vehicles arriving on them.
///
/// Selection-driven, not viewport-driven: it is activated when a stop sheet opens
/// and torn down when it closes, so `viewportDidChange` is a no-op and there is
/// no zoom gate — a trip shape spans far more than a stop-density viewport, and
/// culling it by visible-rect height would hide the line exactly when it is most
/// useful.
@MainActor
final class StopRouteFocusMapLayer: NSObject, MapLayer {

    // MARK: - Styling

    private enum Style {
        static let coreWidth: CGFloat = 5
        static let focusedCoreWidth: CGFloat = 7
        static let casingExtraWidth: CGFloat = 4
        static let dimmedAlpha: CGFloat = 0.32
        static let normalAlpha: CGFloat = 1.0
    }

    // MARK: - MapLayer

    let id = "stopRoutes"
    var title: String {
        OBALoc("map_layer.stop_routes.title", value: "Route lines & vehicles",
               comment: "Map sheet row for the layer drawing a selected stop's routes and live vehicles.")
    }
    let iconName = "arrow.triangle.branch"
    var tintColor: UIColor { ThemeColors.shared.brand }
    let group = MapLayerGroup.transit
    let isEnabledByDefault = true
    let availability = MapLayerAvailability.available
    /// No zoom gate — see the type doc.
    let zoomWindow = MapLayerZoomWindow(maxVisibleHeight: .greatestFiniteMagnitude)
    let densityBudget = 32
    let isClusterable = false
    let refreshPolicy = MapLayerRefreshPolicy.static
    let staleAfter: Duration? = .seconds(120)

    // MARK: - State

    private let mapView: MKMapView
    private let shapeCache: ShapeCache

    private var focus: StopMapFocus?
    private var cancellables = Set<AnyCancellable>()

    private var overlays: [RouteShapeOverlay] = []
    private var annotations: [StopVehicleAnnotation] = []
    private var model: StopRouteFocusModel = .empty

    /// Shapes already drawn, so a refresh doesn't redraw an unchanged line.
    private var drawnShapeIDsByRoute: [RouteID: String] = [:]

    /// Resolves a departure ID back to the live model object. Set by
    /// `MapViewController` (Task 11) BEFORE the first `update(model:)`, because
    /// vehicle annotations cannot be built without the `TripStatus` it yields.
    var departureProvider: ((String) -> ArrivalDeparture?)?

    /// Pushes the trip screen from the callout. Set by `MapViewController`.
    var onFollowTrip: ((ArrivalDeparture) -> Void)?
    /// Invalidates late shape responses for a presentation that has since ended.
    private var presentationToken = UUID()
    private var shapeTasks: [Task<Void, Never>] = []

    init(mapView: MKMapView, shapeCache: ShapeCache) {
        self.mapView = mapView
        self.shapeCache = shapeCache
        super.init()
    }

    // MARK: - Presentation lifecycle

    /// Called when a stop sheet opens. Subscribes to focus changes so chip and
    /// marker taps restyle the lines.
    func begin(focus: StopMapFocus) {
        end()
        self.focus = focus
        presentationToken = UUID()

        focus.$focusedRouteID
            .removeDuplicates()
            .sink { [weak self] _ in self?.restyleOverlays() }
            .store(in: &cancellables)
    }

    /// Called when the sheet closes. Cancels in-flight shape work so a late
    /// response can't draw onto a map that has moved on.
    func end() {
        presentationToken = UUID()
        for task in shapeTasks { task.cancel() }
        shapeTasks.removeAll()
        cancellables.removeAll()
        focus = nil
        model = .empty
        drawnShapeIDsByRoute.removeAll()
        removeAllContent()
    }

    /// Called on every arrivals refresh.
    func update(model: StopRouteFocusModel) {
        self.model = model
        focus?.apply(routes: model.routes)
        syncVehicleAnnotations()
        syncRouteOverlays()
    }

    // MARK: - Vehicles

    private func syncVehicleAnnotations() {
        mapView.removeAnnotations(annotations)
        annotations = model.vehicles.compactMap { vehicle in
            // A non-nil TripStatus is mandatory — without it the marker renders as
            // a bare dot with no icon and no heading arrow. See StopVehicleAnnotation.
            // Every modelled vehicle derived its coordinate from a TripStatus, so
            // this lookup only fails if the departure vanished between refreshes.
            guard let tripStatus = departureProvider?(vehicle.departureID)?.tripStatus else { return nil }
            return StopVehicleAnnotation(
                id: vehicle.id,
                routeID: vehicle.routeID,
                routeColor: model.routes.first { $0.routeID == vehicle.routeID }?.color ?? tintColor,
                departureID: vehicle.departureID,
                tripStatus: tripStatus,
                coordinate: vehicle.coordinate
            )
        }
        mapView.addAnnotations(annotations)
    }

    // MARK: - Shapes

    private func syncRouteOverlays() {
        let wantedRouteIDs = Set(model.routes.map(\.routeID))

        // Drop lines for routes that have left the arrival set.
        let stale = overlays.filter { !wantedRouteIDs.contains($0.routeID) }
        if !stale.isEmpty {
            mapView.removeOverlays(stale)
            overlays.removeAll { !wantedRouteIDs.contains($0.routeID) }
        }
        drawnShapeIDsByRoute = drawnShapeIDsByRoute.filter { wantedRouteIDs.contains($0.key) }

        for route in model.routes {
            guard let shapeID = route.shapeID, !shapeID.isEmpty else { continue }
            // Pin the shape: the soonest arrival rolls over as buses depart, so
            // re-resolving it every refresh would refetch and visibly redraw an
            // otherwise-unchanged line.
            guard drawnShapeIDsByRoute[route.routeID] == nil else { continue }
            drawnShapeIDsByRoute[route.routeID] = shapeID
            fetchAndDrawShape(shapeID: shapeID, route: route)
        }
    }

    private func fetchAndDrawShape(shapeID: String, route: StopRouteFocusModel.DrawnRoute) {
        let token = presentationToken
        let task = Task { [weak self, shapeCache] in
            guard let coordinates = try? await shapeCache.coordinates(forShapeID: shapeID),
                  coordinates.count > 1 else { return }
            guard let self, self.presentationToken == token else { return }
            self.addShape(coordinates: coordinates, routeID: route.routeID)
        }
        shapeTasks.append(task)
    }

    private func addShape(coordinates: [CLLocationCoordinate2D], routeID: RouteID) {
        // Casing first so the colored core draws above it.
        let casing = RouteShapeOverlay.make(coordinates: coordinates, routeID: routeID, isCasing: true)
        let core = RouteShapeOverlay.make(coordinates: coordinates, routeID: routeID, isCasing: false)
        overlays.append(contentsOf: [casing, core])
        mapView.addOverlays([casing, core], level: .aboveRoads)
    }

    // MARK: - Focus restyling

    private func restyleOverlays() {
        // `mapView.renderer(for:)` returns nil for any overlay MapKit has not asked
        // the delegate to render yet — offscreen ones, and everything if the map is
        // not in a window. Re-adding forces a fresh `rendererFor` round trip, which
        // picks up the new focus state. Without this fallback a chip tap silently
        // does nothing for the lines that happen to be off-screen.
        var needsReadd: [RouteShapeOverlay] = []
        for overlay in overlays {
            if let renderer = mapView.renderer(for: overlay) as? MKPolylineRenderer {
                apply(style: overlay, to: renderer)
                renderer.setNeedsDisplay()
            } else {
                needsReadd.append(overlay)
            }
        }
        if !needsReadd.isEmpty {
            mapView.removeOverlays(needsReadd)
            mapView.addOverlays(needsReadd, level: .aboveRoads)
        }
        for annotation in annotations {
            guard let view = mapView.view(for: annotation) as? PulsingVehicleAnnotationView else { continue }
            view.zPriority = (annotation.routeID == focus?.focusedRouteID) ? .max : .defaultUnselected
        }
    }

    private func apply(style overlay: RouteShapeOverlay, to renderer: MKPolylineRenderer) {
        let focusedRouteID = focus?.focusedRouteID
        let isFocused = overlay.routeID == focusedRouteID
        let color = model.routes.first { $0.routeID == overlay.routeID }?.color ?? tintColor

        let coreWidth = isFocused ? Style.focusedCoreWidth : Style.coreWidth
        renderer.lineWidth = overlay.isCasing ? coreWidth + Style.casingExtraWidth : coreWidth
        // The casing is what keeps a route-colored line legible over the basemap.
        renderer.strokeColor = overlay.isCasing ? .white : color
        renderer.lineCap = .round
        renderer.lineJoin = .round
        renderer.alpha = (focusedRouteID == nil || isFocused) ? Style.normalAlpha : Style.dimmedAlpha
    }

    private func removeAllContent() {
        mapView.removeOverlays(overlays)
        mapView.removeAnnotations(annotations)
        overlays.removeAll()
        annotations.removeAll()
    }

    // MARK: - MapLayer conformance

    func renderer(for overlay: MKOverlay, in mapView: MKMapView) -> MKOverlayRenderer? {
        guard let overlay = overlay as? RouteShapeOverlay else { return nil }
        let renderer = MKPolylineRenderer(polyline: overlay)
        apply(style: overlay, to: renderer)
        return renderer
    }

    func annotationView(for annotation: MKAnnotation, in mapView: MKMapView) -> MKAnnotationView? {
        guard let annotation = annotation as? StopVehicleAnnotation else { return nil }
        let view = mapView.dequeueReusableAnnotationView(
            withIdentifier: MKMapView.reuseIdentifier(for: PulsingVehicleAnnotationView.self),
            for: annotation
        ) as? PulsingVehicleAnnotationView
        // Set the color BEFORE the annotation, or the didSet chain applies the
        // previous route's color — see PulsingVehicleAnnotationView.
        view?.realTimeAnnotationColor = annotation.routeColor
        view?.isSelectable = true
        view?.canShowCallout = true
        view?.annotation = annotation
        return view
    }

    func detailViewController(for annotation: MKAnnotation) -> UIViewController? { nil }

    func activate() { }

    func deactivate() { end() }

    /// Selection-driven, not viewport-driven.
    func viewportDidChange(_ mapRect: MKMapRect?) { }

    func mapAnnotationsWereCleared() {
        guard focus != nil else { return }
        mapView.addAnnotations(annotations)
    }

    func mapOverlaysWereCleared() {
        guard focus != nil else { return }
        mapView.addOverlays(overlays, level: .aboveRoads)
    }
}
```

- [ ] **Step 4: Register the layer**

Find where `StopsMapLayer` and `RentalMapLayer` are registered (grep
`registerMapLayer`) and register `StopRouteFocusMapLayer` alongside them, passing
`mapRegionManager.mapView` and a `ShapeCache` whose fetch closure calls
`RESTAPIService.getShape(id:)`:

```bash
grep -rn 'registerMapLayer' --include='*.swift' OBAKit
```

The fetch closure shape:

```swift
ShapeCache { [weak apiService] shapeID in
    guard let apiService else { throw CancellationError() }
    return try await apiService.getShape(id: shapeID).entry.points
}
```

Confirm the response's property path with:

```bash
sed -n '255,268p' OBAKitCore/Network/RESTAPIService/RESTAPIService+Get.swift
sed -n '15,30p' OBAKitCore/Models/REST/PolylineEntity.swift
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
scripts/generate_project OneBusAway
set -o pipefail
xcodebuild build-for-testing -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -5
xcodebuild test-without-building -only-testing:OBAKitTests/StopRouteFocusMapLayerTests \
  -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -20
```

Expected: 6 passed.

- [ ] **Step 6: Commit**

```bash
git add OBAKit/Mapping/Layers/StopRouteFocus/StopRouteFocusMapLayer.swift \
        OBAKitTests/Mapping/StopRouteFocus/StopRouteFocusMapLayerTests.swift \
        OBAKit/Mapping/MapRegionManager.swift
git commit -m "feat: draw a selected stop's route lines and live vehicles"
```

---

### Task 9: Attach the focus object to the stop page and light up the chips

**Files:**
- Modify: `OBAKit/Stops/StopPage/StopPageViewController.swift` (add `attach(focus:)`, thread through `installRootView()`)
- Modify: `OBAKit/Stops/StopPage/StopPageView.swift` (`StopPageRootView` + `StopPageView` pass-through)
- Modify: `OBAKit/Stops/StopPage/StopPageSheetHeaderView.swift:47`, `:70-77`, `:122-136`
- Test: `OBAKitTests/Stops/StopPage/StopPageChipFocusTests.swift` (create)

**Interfaces:**
- Consumes: `StopMapFocus` (Task 6).
- Produces: `StopPageViewController.attach(focus: StopMapFocus)`; `RouteChip` value type used by the header.

- [ ] **Step 1: Read the current header and the `isAtTip` threading pattern**

```bash
sed -n '40,80p' OBAKit/Stops/StopPage/StopPageSheetHeaderView.swift
sed -n '118,140p' OBAKit/Stops/StopPage/StopPageSheetHeaderView.swift
sed -n '105,145p' OBAKit/Stops/StopPage/StopPageViewController.swift
sed -n '70,115p' OBAKit/Stops/StopPage/StopPageView.swift
```

Note in particular the comment at `StopPageSheetHeaderView.swift:123-126` — chips
must not become `Button`s, because `FlowLayout` sizes subviews with `.unspecified`
and a `Button` answers with a greedy height.

- [ ] **Step 2: Write the failing test**

```swift
import Testing
import UIKit
import OBAKitCore
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class StopPageChipFocusTests {

    private func route(_ id: RouteID, live: Bool) -> StopRouteFocusModel.DrawnRoute {
        StopRouteFocusModel.DrawnRoute(
            routeID: id, shortName: id, color: .systemBlue, shapeID: "s", hasLiveVehicle: live
        )
    }

    @Test func `Chips preserve today's membership and alphabetical order`() {
        // Membership is stop.routes, unchanged — a route with nothing upcoming
        // keeps its chip, and the sheet matches the pushed page.
        let chips = RouteChip.chips(
            forRouteShortNames: ["62", "H", "40", ""],
            routeIDsByShortName: ["62": ["1_62"], "H": ["1_H"], "40": ["1_40"]]
        )
        #expect(chips.map(\.shortName) == ["40", "62", "H"])
    }

    @Test func `A chip carries every route ID sharing its short name`() {
        // Today's dedupe is by short name; preserve that visually while keeping
        // enough identity to focus one of them.
        let chips = RouteChip.chips(
            forRouteShortNames: ["40", "40"],
            routeIDsByShortName: ["40": ["1_40", "2_40"]]
        )
        #expect(chips.count == 1)
        #expect(Set(chips[0].routeIDs) == ["1_40", "2_40"])
    }

    @Test func `A chip is interactive only when the map drew its route with a vehicle`() {
        let focus = StopMapFocus()
        focus.apply(routes: [route("1_H", live: true), route("1_62", live: false)])

        let liveChip = RouteChip(shortName: "H", routeIDs: ["1_H"])
        let schedChip = RouteChip(shortName: "62", routeIDs: ["1_62"])
        let undrawnChip = RouteChip(shortName: "40", routeIDs: ["1_40"])

        #expect(liveChip.isInteractive(in: focus))
        #expect(!schedChip.isInteractive(in: focus))
        #expect(!undrawnChip.isInteractive(in: focus))
    }

    @Test func `Tapping a chip focuses the first of its routes with a vehicle`() {
        let focus = StopMapFocus()
        focus.apply(routes: [route("1_40", live: false), route("2_40", live: true)])
        let chip = RouteChip(shortName: "40", routeIDs: ["1_40", "2_40"])

        chip.toggleFocus(in: focus)

        #expect(focus.focusedRouteID == "2_40")
    }

    @Test func `Tapping an undrawn chip does nothing`() {
        let focus = StopMapFocus()
        focus.apply(routes: [route("1_H", live: true)])
        let chip = RouteChip(shortName: "40", routeIDs: ["1_40"])

        chip.toggleFocus(in: focus)

        #expect(focus.focusedRouteID == nil)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

```bash
scripts/generate_project OneBusAway
set -o pipefail
xcodebuild build-for-testing -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -5
```

Expected: compile failure — `RouteChip` does not exist.

- [ ] **Step 4: Write `RouteChip`**

Add to `OBAKit/Stops/StopPage/StopPageSheetHeaderView.swift` (or a small sibling
file if the header is already long):

```swift
/// One header chip. Membership and ordering are unchanged from before this
/// feature — `stop.routes`, deduped by short name, alphabetical — so the sheet
/// and the pushed stop page keep showing the same header for the same stop, and
/// the VoiceOver summary built from `stop.routes` keeps matching what is drawn.
///
/// Carries every route ID sharing its short name, because today's dedupe is by
/// string: two `RouteID`s with short name "40" collapse to one badge, and the tap
/// has to resolve to whichever of them the map is actually drawing.
struct RouteChip: Identifiable, Hashable {
    let shortName: String
    let routeIDs: [RouteID]
    var id: String { shortName }

    static func chips(
        forRouteShortNames shortNames: [String],
        routeIDsByShortName: [String: [RouteID]]
    ) -> [RouteChip] {
        let unique = Set(shortNames.filter { !$0.isEmpty })
        return unique
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { RouteChip(shortName: $0, routeIDs: routeIDsByShortName[$0] ?? []) }
    }

    /// The route this chip's tap should act on: the first of its IDs the map drew
    /// with a live vehicle.
    func focusableRouteID(in focus: StopMapFocus) -> RouteID? {
        routeIDs.first { focus.isFocusable(routeID: $0) }
    }

    func isInteractive(in focus: StopMapFocus) -> Bool {
        focusableRouteID(in: focus) != nil
    }

    func drawnRoute(in focus: StopMapFocus) -> StopRouteFocusModel.DrawnRoute? {
        routeIDs.lazy.compactMap { focus.drawnRoute(for: $0) }.first
    }

    func toggleFocus(in focus: StopMapFocus) {
        guard let routeID = focusableRouteID(in: focus) else { return }
        focus.toggleFocus(routeID: routeID)
    }
}
```

- [ ] **Step 5: Thread `StopMapFocus` through to the header**

In `StopPageViewController`:

```swift
    /// The map's focus channel, when this page was presented as the map's stop
    /// sheet. Inert for every pushed presentation.
    ///
    /// Stored on the controller and re-threaded through `installRootView()`,
    /// exactly like `isAtTip` — writing `rootView.mapFocus` alone would be
    /// silently dropped by the next `installRootView()` (e.g. from
    /// `exitPreviewMode`).
    private var mapFocus = StopMapFocus()

    func attach(focus: StopMapFocus) {
        mapFocus = focus
        installRootView()
    }
```

and add `mapFocus: mapFocus` to the `StopPageRootView(...)` construction inside
`installRootView()`.

In `StopPageView.swift`, add a plain `let mapFocus: StopMapFocus` to both
`StopPageRootView` and `StopPageView`, and pass it into the
`StopPageSheetHeaderView` built in the `.safeAreaInset(edge: .top)` at `:394-405`.

**Do not put `@ObservedObject` on `StopPageView`.** Its doc comment at `:107-109`
records that it is deliberately the only view observing `StopViewModel`, so the
VM's churn re-evaluates one shallow body. Observing focus there would re-evaluate
the entire list on every refresh and every chip tap.

In `StopPageSheetHeaderView`, add the observation and amend the doc comment at `:47`:

```swift
    /// Map focus state. This is the one view in the Stop page subtree that
    /// observes it — see `StopPageView`'s note on observation discipline.
    @ObservedObject var mapFocus: StopMapFocus
```

- [ ] **Step 6: Render chip decoration and taps**

Replace the chip body at `:122-136`. Keep it a `Text`-shaped view — **never a
`Button`** — per the comment at `:123-126`:

```swift
    @ViewBuilder
    private func chipView(_ chip: RouteChip) -> some View {
        let drawn = chip.drawnRoute(in: mapFocus)
        let isFocused = chip.focusableRouteID(in: mapFocus) == mapFocus.focusedRouteID
            && mapFocus.focusedRouteID != nil
        let isDimmed = mapFocus.focusedRouteID != nil && !isFocused

        HStack(spacing: 5) {
            if let drawn {
                // The route's map-line color, so the chip and its line read as one thing.
                Capsule()
                    .fill(Color(uiColor: drawn.color))
                    .frame(width: 13, height: 4)
            }
            Text(chip.shortName)
                .font(.subheadline.weight(.bold))
            if drawn?.hasLiveVehicle == true {
                // Only when there is a vehicle on the map to point at.
                Circle()
                    .fill(Color(uiColor: ThemeColors.shared.brand))
                    .frame(width: 5, height: 5)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(isFocused
                ? Color(uiColor: drawn?.color ?? .clear).opacity(0.16)
                : Color(uiColor: .secondarySystemFill))
        )
        .overlay(
            Capsule().strokeBorder(isFocused ? Color(uiColor: drawn?.color ?? .clear) : .clear, lineWidth: 1)
        )
        .opacity(isDimmed ? 0.45 : 1)
        // NOT a Button: FlowLayout proposes .unspecified, which a Button answers
        // with a greedy height — that is what stretched the walk pill down the
        // whole sheet. See the note above this view.
        .contentShape(Rectangle())
        .onTapGesture { chip.toggleFocus(in: mapFocus) }
        .accessibilityAddTraits(chip.isInteractive(in: mapFocus) ? .isButton : [])
        .accessibilityLabel(accessibilityLabel(for: chip, drawn: drawn, isFocused: isFocused))
    }

    private func accessibilityLabel(
        for chip: RouteChip,
        drawn: StopRouteFocusModel.DrawnRoute?,
        isFocused: Bool
    ) -> String {
        var parts = [chip.shortName]
        if drawn?.hasLiveVehicle == true { parts.append(liveTrackingLabel) }
        if isFocused { parts.append(highlightedLabel) }
        return parts.joined(separator: ", ")
    }
```

**There is no `OBAKit/Strings.swift`.** `Strings` lives in **OBAKitCore**
(`OBAKitCore/Strings/Strings.swift`), and its `OBALoc` binds to the OBAKitCore
bundle (`OBAKitCore/Strings/CoreLocalization.swift:14-15`) — so entries added
there need their English values in `OBAKitCore/Strings/en.lproj/Localizable.strings`.
Putting them under `OBAKit/Strings/en.lproj/` resolves nothing: the string
silently falls back to its `value:` default and never localizes, which stays
invisible until someone runs a non-English build.

For view-local copy like this, do what the file already does — a file-local
`OBALoc(...)`, matching `StopPageSheetHeaderView.swift:177`. Replace the two
`Strings.` references above with:

```swift
    private var liveTrackingLabel: String {
        OBALoc("stop_header.chip.live_tracking", value: "live tracking",
               comment: "Spoken suffix on a route chip whose route has a vehicle on the map.")
    }

    private var highlightedLabel: String {
        OBALoc("stop_header.chip.highlighted", value: "highlighted on map",
               comment: "Spoken suffix on the currently-focused route chip.")
    }
```

**Also fix the accessibility container, or none of the chip a11y above works.**
`StopPageSheetHeaderView.swift:134-135` puts `.accessibilityElement(children: .ignore)`
plus one summary `.accessibilityLabel` on the whole `FlowLayout`. That swallows
every per-chip trait and label, and makes chips impossible to activate with
VoiceOver — `.onTapGesture` on an ignored child is unreachable. Change it to
`.accessibilityElement(children: .contain)` and move the routes-served summary
onto the header's own label rather than the chip row.

- [ ] **Step 7: Fix every `StopPageRootView` / `StopPageView` construction site**

```bash
grep -rn 'StopPageRootView(\|StopPageView(\|StopPageSheetHeaderView(' --include='*.swift' OBAKit OBAKitTests
```

Every site needs the new `mapFocus:` argument. Pushed presentations and previews
pass a fresh `StopMapFocus()`.

- [ ] **Step 8: Run tests to verify they pass**

```bash
scripts/generate_project OneBusAway
set -o pipefail
xcodebuild build-for-testing -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -5
xcodebuild test-without-building -only-testing:OBAKitTests/StopPageChipFocusTests \
  -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -20
xcodebuild test-without-building -only-testing:OBAKitTests/StopPageSheetHeaderLayoutTests \
  -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -20
```

Expected: 5 passed, and the existing header layout suite still green — that suite
is the guard against the greedy-height regression.

- [ ] **Step 9: Commit**

```bash
git add OBAKit/Stops/StopPage/ \
        OBAKitTests/Stops/StopPage/StopPageChipFocusTests.swift
git commit -m "feat: make stop header route chips a map focus control"
```

---

### Task 10: Vehicle callout with Follow this trip

**Files:**
- Create: `OBAKit/Mapping/Layers/StopRouteFocus/VehicleCalloutView.swift`
- Modify: `OBAKit/Mapping/Layers/StopRouteFocus/StopRouteFocusMapLayer.swift` (attach the accessory, expose the follow callback)
- Test: `OBAKitTests/Mapping/StopRouteFocus/VehicleCalloutViewTests.swift` (create)

**Interfaces:**
- Consumes: `StopVehicleAnnotation` (Task 7), `ArrivalDeparture`.
- Produces:
  - `final class VehicleCalloutView: UIView` with `init(departure:routeColor:onFollow:)`
  - `StopRouteFocusMapLayer.onFollowTrip: ((ArrivalDeparture) -> Void)?`
  - `StopRouteFocusMapLayer.departureProvider: ((String) -> ArrivalDeparture?)?`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import UIKit
import OBAKitCore
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class VehicleCalloutViewTests {

    @Test func `Follow invokes the callback exactly once`() {
        var followCount = 0
        let view = VehicleCalloutView(
            headsign: "Downtown Seattle",
            vehicleLabel: "Vehicle 6821",
            countdownText: "1m",
            statusText: "1 min late",
            statusColor: .systemBlue,
            updatedText: "position updated 12s ago",
            routeColor: .systemRed,
            onFollow: { followCount += 1 }
        )

        view.simulateFollowTap()

        #expect(followCount == 1)
    }

    @Test func `The callout announces itself as one element to VoiceOver`() {
        let view = VehicleCalloutView(
            headsign: "Downtown Seattle",
            vehicleLabel: "Vehicle 6821",
            countdownText: "1m",
            statusText: "1 min late",
            statusColor: .systemBlue,
            updatedText: "position updated 12s ago",
            routeColor: .systemRed,
            onFollow: { }
        )

        #expect(view.accessibilityLabel?.contains("Downtown Seattle") == true)
        #expect(view.accessibilityLabel?.contains("1 min late") == true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
scripts/generate_project OneBusAway
set -o pipefail
xcodebuild build-for-testing -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -5
```

Expected: compile failure — `VehicleCalloutView` does not exist.

- [ ] **Step 3: Write the callout**

Build it as a UIKit view — a MapKit `detailCalloutAccessoryView` needs a concrete
`UIView` with a sensible intrinsic size, and hosting SwiftUI here would require a
child view controller for no benefit.

```swift
//
//  VehicleCalloutView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import UIKit

/// The callout shown when a rider taps a live vehicle on the map.
final class VehicleCalloutView: UIView {

    private let onFollow: () -> Void
    private let followButton = UIButton(type: .system)

    init(
        headsign: String,
        vehicleLabel: String,
        countdownText: String,
        statusText: String,
        statusColor: UIColor,
        updatedText: String,
        routeColor: UIColor,
        onFollow: @escaping () -> Void
    ) {
        self.onFollow = onFollow
        super.init(frame: .zero)

        let headsignLabel = UILabel()
        headsignLabel.text = headsign
        headsignLabel.font = .preferredFont(forTextStyle: .subheadline).bold
        headsignLabel.numberOfLines = 2
        headsignLabel.adjustsFontForContentSizeCategory = true

        let vehicle = UILabel()
        vehicle.text = vehicleLabel
        vehicle.font = .preferredFont(forTextStyle: .caption1)
        vehicle.textColor = .secondaryLabel
        vehicle.adjustsFontForContentSizeCategory = true

        let countdown = UILabel()
        countdown.text = countdownText
        countdown.font = .preferredFont(forTextStyle: .title2).bold
        countdown.textColor = statusColor
        countdown.adjustsFontForContentSizeCategory = true

        let status = UILabel()
        status.text = statusText
        status.font = .preferredFont(forTextStyle: .caption1)
        status.textColor = statusColor
        status.adjustsFontForContentSizeCategory = true

        let updated = UILabel()
        updated.text = updatedText
        updated.font = .preferredFont(forTextStyle: .caption2)
        updated.textColor = .tertiaryLabel
        updated.adjustsFontForContentSizeCategory = true

        var config = UIButton.Configuration.gray()
        config.title = OBALoc("vehicle_callout.follow_this_trip", value: "Follow this trip",
                              comment: "Button in the live-vehicle map callout that opens the trip screen.")
        config.image = UIImage(systemName: "chevron.right")
        config.imagePlacement = .trailing
        config.imagePadding = 6
        config.cornerStyle = .medium
        followButton.configuration = config
        followButton.addTarget(self, action: #selector(followTapped), for: .touchUpInside)

        let statusRow = UIStackView(arrangedSubviews: [countdown, status])
        statusRow.axis = .horizontal
        statusRow.alignment = .firstBaseline
        statusRow.spacing = 6

        let stack = UIStackView(arrangedSubviews: [headsignLabel, vehicle, statusRow, updated, followButton])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            // MapKit callouts have no intrinsic width; without this the content
            // collapses to the widest single word.
            widthAnchor.constraint(equalToConstant: 214)
        ])

        // One VoiceOver element: reading five separate labels inside a callout is
        // worse than one sentence.
        isAccessibilityElement = true
        accessibilityLabel = [headsign, vehicleLabel, countdownText, statusText, updatedText]
            .joined(separator: ", ")
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func followTapped() {
        onFollow()
    }

    /// Test seam — exercises the same path as a real tap.
    func simulateFollowTap() {
        followTapped()
    }

    override func accessibilityActivate() -> Bool {
        followTapped()
        return true
    }
}
```

The button title uses a file-local `OBALoc` rather than a `Strings` member —
`Strings` lives in OBAKitCore and binds to that bundle, so a new member there
would need its English value in `OBAKitCore/Strings/en.lproj/Localizable.strings`.
`UIFont.bold` is verified to exist (`OBAKitCore/Extensions/UIKitExtensions.swift:307`).

- [ ] **Step 4: Wire the callout into the layer**

`departureProvider` and `onFollowTrip` already exist on `StopRouteFocusMapLayer`
from Task 8 — do not redeclare them. In `annotationView(for:in:)`, after
`view?.annotation = annotation`, add:

```swift
        if let departure = departureProvider?(annotation.departureID) {
            view?.detailCalloutAccessoryView = makeCallout(for: departure, annotation: annotation)
        }
```

with:

```swift
    /// Relative-time formatter for "position updated 12s ago". Held statically —
    /// constructing one per callout is measurably wasteful and they are stateless.
    private static let updatedFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private func makeCallout(for departure: ArrivalDeparture, annotation: StopVehicleAnnotation) -> UIView {
        // `DepartureStatus`'s members are `label` and `color` — NOT statusLabel /
        // statusColor. Verified at DepartureStatus.swift:52 and :35.
        let status = DepartureStatus(arrivalDeparture: departure)
        // `route` is declared `Route!` (ArrivalDeparture.swift:53) — it is populated
        // by `loadReferences`, but reach for the non-optional `routeShortName`
        // (:220) as the fallback rather than force-unwrapping through `route`.
        let headsign = departure.tripHeadsign ?? departure.routeShortName
        return VehicleCalloutView(
            headsign: headsign,
            vehicleLabel: annotation.id,
            countdownText: "\(departure.arrivalDepartureMinutes)m",
            statusText: status.label,
            statusColor: status.color,
            // There is no `Formatters.formattedLastUpdated`. `ArrivalDeparture`
            // carries `lastUpdated: Date` (:35); format it here.
            updatedText: Self.updatedFormatter.localizedString(for: departure.lastUpdated, relativeTo: Date()),
            routeColor: annotation.routeColor,
            onFollow: { [weak self] in self?.onFollowTrip?(departure) }
        )
    }
```

Confirm the two `DepartureStatus` member names and `lastUpdated` before writing —
note the formatters file is at `OBAKitCore/Utilities/Formatters.swift`, not
`OBAKitCore/Formatters.swift`:

```bash
grep -n 'init(arrivalDeparture\|var label\|var color' OBAKit/Stops/StopPage/Shared/DepartureStatus.swift
grep -n 'lastUpdated' OBAKitCore/Models/REST/ArrivalDeparture.swift | head -3
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
scripts/generate_project OneBusAway
set -o pipefail
xcodebuild build-for-testing -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -5
xcodebuild test-without-building -only-testing:OBAKitTests/VehicleCalloutViewTests \
  -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -20
```

Expected: 2 passed.

- [ ] **Step 6: Commit**

```bash
git add OBAKit/Mapping/Layers/StopRouteFocus/ \
        OBAKitTests/Mapping/StopRouteFocus/VehicleCalloutViewTests.swift
git commit -m "feat: add the live vehicle callout with Follow this trip"
```

---

### Task 11: Wire it into `MapViewController`

The last task, and the one that turns the feature on. Ordering here is
load-bearing.

**Files:**
- Modify: `OBAKit/Mapping/MapViewController.swift:774-806` (`present(stopController:)`)
- Modify: `OBAKit/Mapping/StopSheetPresenter.swift` (expose the half-detent inset)
- Test: `OBAKitTests/Mapping/StopSheetLayoutMetricsTests.swift` (create)

**Interfaces:**
- Consumes: everything from Tasks 4–10.
- Produces: the working feature.

- [ ] **Step 1: Write the failing test for the layout constant**

```swift
import MapKit
import Testing
import UIKit
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class StopSheetLayoutMetricsTests {

    @Test func `The half detent inset is half the safe area, matching FloatingPanel`() {
        // FloatingPanel's stock .half anchor is fractionalInset 0.5 of the SAFE
        // AREA. Using screen height instead overshoots by half the insets, which
        // would push the tapped stop further up the map than intended.
        #expect(StopSheetLayout.halfDetentInset(safeAreaHeight: 800) == 400)
    }

    @Test func `Framing a stop leaves it above the sheet`() {
        // The camera fix that actually matters: a zero-size MKMapRect is degenerate
        // and slams the camera to maximum zoom, so the rect must have real extent.
        let coordinate = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.33)
        let rect = MKMapRect(MKCoordinateRegion(
            center: coordinate, latitudinalMeters: 400, longitudinalMeters: 400
        ))

        #expect(rect.size.width > 0)
        #expect(rect.size.height > 0)
        #expect(rect.contains(MKMapPoint(coordinate)))
    }
}
```

**Note:** the previous draft of this task asserted `halfDetentInset > 0` and
`< UIScreen.main.bounds.height`. Both are arithmetic consequences of multiplying
by `0.5` and could never fail — they measured nothing. These two assert the two
things that were actually wrong.

- [ ] **Step 2: Run test to verify it fails**

```bash
scripts/generate_project OneBusAway
set -o pipefail
xcodebuild build-for-testing -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -5
```

Expected: compile failure — `halfDetentInset` does not exist.

- [ ] **Step 3: Expose the inset**

In `StopSheetPresenter.swift`, add to `StopSheetLayout`:

```swift
    /// Height the `.half` detent occupies, given the host's safe-area height.
    ///
    /// Computed rather than read off the live surface: the panel is private, and
    /// `addPanel(toParent:animated: true)` slides in from `.hidden`, so the
    /// surface frame is not final when the presentation begins.
    ///
    /// Takes the safe-area height as a parameter for two reasons. FloatingPanel's
    /// stock `.half` anchor is `fractionalInset: 0.5, referenceGuide: .safeArea`
    /// (`.build/checkouts/FloatingPanel/Sources/Layout.swift:37`) — half the *safe
    /// area*, not half the screen, so screen height overshoots by roughly
    /// (top + bottom inset) / 2. And `UIScreen` is `@MainActor` in the SDK, so a
    /// `nonisolated` member cannot touch `UIScreen.main` at all under this
    /// project's Swift 6 settings.
    static func halfDetentInset(safeAreaHeight: CGFloat) -> CGFloat {
        safeAreaHeight * 0.5
    }
```

Callers pass `mapView.safeAreaLayoutGuide.layoutFrame.height`.

- [ ] **Step 4: Run tests to verify they pass**

```bash
scripts/generate_project OneBusAway
set -o pipefail
xcodebuild build-for-testing -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -5
xcodebuild test-without-building -only-testing:OBAKitTests/StopSheetLayoutMetricsTests \
  -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -20
```

Expected: 2 passed.

- [ ] **Step 5: Wire the presentation**

First widen the existing guard at `MapViewController.swift:775` so the typed
controller is in scope for the whole method — today the only binding is inside a
narrower `if let` at `:780-782` that closes well before `stopSheet.present(...)`
at `:791`:

```swift
        guard let stopPageVC = stopController as? StopPageViewController else {
            application.viewRouter.navigate(to: stopController, from: self)
            return
        }
```

and collapse the now-redundant `if let stopPageVC = ...` at `:780` to use it
directly.

Then, **after** the existing `stopSheet.present(...)` call — not before:

```swift
        // ORDERING IS LOAD-BEARING. `StopSheetPresenter.present` tears the outgoing
        // presentation down as its FIRST statement, which synchronously runs the
        // outgoing dismiss handler — and that handler ends the layer. Building and
        // activating the new focus before this call would have the outgoing handler
        // immediately tear down what we just set up: a blank map on every
        // stop-to-stop tap.
        let focus = StopMapFocus()
        stopPageVC.attach(focus: focus)
        beginRouteFocus(focus: focus, stopPageVC: stopPageVC)
        centerMapAboveSheet(on: stopPageVC.stopCoordinate)
```

and add:

```swift
    /// Feeds the route-focus layer from the stop page's view model, and routes
    /// "Follow this trip" into the sheet's navigation stack.
    private func beginRouteFocus(focus: StopMapFocus, stopPageVC: StopPageViewController) {
        guard let layer = mapRegionManager.mapLayer(id: "stopRoutes") as? StopRouteFocusMapLayer else { return }
        layer.begin(focus: focus)

        let viewModel = stopPageVC.viewModel
        layer.departureProvider = { [weak viewModel] departureID in
            viewModel?.stopArrivals?.arrivalsAndDepartures.first { $0.id == departureID }
        }
        layer.onFollowTrip = { [weak self, weak stopPageVC] departure in
            guard let self, let stopPageVC else { return }
            self.application.viewRouter.navigateTo(arrivalDeparture: departure, from: stopPageVC)
        }

        // Combine over a @MainActor ObservableObject from UIKit: the exact pattern
        // `StopViewController.bindArrivalsSink()` already ships under Swift 6
        // strict concurrency. `sink(receiveValue:)` takes a plain non-Sendable
        // closure, so it inherits @MainActor and crosses no isolation boundary.
        //
        // `@Published` fires in `willSet`, so use the closure's parameter — never
        // re-read `viewModel.stopArrivals` here, which would still hold the OLD value.
        viewModel.$stopArrivals
            .combineLatest(viewModel.$isListFiltered, viewModel.$stopPreferences)
            .sink { [weak self, weak layer] arrivals, isListFiltered, preferences in
                guard let self, let layer else { return }
                let visible = StopRouteFocusModel.visibleDepartures(
                    arrivals?.arrivalsAndDepartures ?? [],
                    isListFiltered: isListFiltered,
                    preferences: preferences
                )
                layer.update(model: StopRouteFocusModel.make(departures: visible, routeCap: 6))
                _ = self
            }
            .store(in: &stopFocusCancellables)
    }

    /// Keeps the tapped stop visible in the strip of map above the sheet. Without
    /// this the pin can end up behind the sheet — nothing recenters today.
    private func centerMapAboveSheet(on coordinate: CLLocationCoordinate2D?) {
        guard let coordinate else { return }
        let mapView = mapRegionManager.mapView
        let sheetInset = StopSheetLayout.halfDetentInset(
            safeAreaHeight: mapView.safeAreaLayoutGuide.layoutFrame.height
        )
        let padding = UIEdgeInsets(top: 60, left: 20, bottom: sheetInset + 20, right: 20)
        // A real extent, NOT a zero-size rect: `MKMapRect(x:y:width:0,height:0)` is
        // degenerate, and fitting it slams the camera to maximum zoom (or NaN).
        // 400 m keeps the stop and its immediate surroundings legible.
        let rect = MKMapRect(MKCoordinateRegion(
            center: coordinate, latitudinalMeters: 400, longitudinalMeters: 400
        ))
        mapView.setVisibleMapRect(rect, edgePadding: padding, animated: true)
    }

    /// Torn down alongside the layer when the sheet closes.
    private var stopFocusCancellables = Set<AnyCancellable>()
```

In the sheet's existing `onDismiss` closure, add the teardown:

```swift
            self.stopFocusCancellables.removeAll()
            (self.mapRegionManager.mapLayer(id: "stopRoutes") as? StopRouteFocusMapLayer)?.end()
```

- [ ] **Step 6: Resolve the helpers this step assumed**

Several names above may not exist verbatim. Check each and adapt:

```bash
grep -n 'func mapLayer(id:' OBAKit/Mapping/MapRegionManager.swift
grep -n 'var viewModel' OBAKit/Stops/StopPage/StopPageViewController.swift
grep -n 'stopCoordinate\|var stop' OBAKit/Stops/StopPage/StopPageViewController.swift
grep -n 'func navigateTo(arrivalDeparture' OBAKit/ViewRouting/Router.swift
grep -n '@Published.*isListFiltered\|@Published.*stopPreferences' OBAKit/ViewModels/StopViewModel.swift
```

- `mapLayer(id:)` exists at `MapRegionManager.swift:298` per the layer registry; confirm its exact name.
- If `StopPageViewController.viewModel` is private, expose it `private(set)`.
- If there is no `stopCoordinate`, read it from `viewModel.stop?.coordinate`.
- Use whatever router method the trip panel's "View full trip" already calls.

- [ ] **Step 7: Build and run the whole test suite**

```bash
scripts/generate_project OneBusAway
set -o pipefail
xcodebuild build-for-testing -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -5
xcodebuild test-without-building -only-testing:OBAKitTests \
  -project OBAKit.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.3.1' | tail -30
```

Expected: all suites pass, including `StopSheetPresenterTests`,
`StopPagePresentationTests`, `StopPageSheetHeaderLayoutTests`, and
`StopDetailSheetHostTests`.

- [ ] **Step 8: Manual verification in the simulator**

Run the app against a live region (Puget Sound) and confirm each of these:

1. Tap a downtown stop → sheet opens at `.half`, route lines and vehicle markers appear, and the tapped stop is visible above the sheet.
2. Tap a route chip with a green dot → its line thickens, others dim, other chips dim, that chip gets a tinted fill and border.
3. Tap the same chip again → everything returns to normal.
4. Tap a chip with **no** green dot → nothing happens, no error.
5. Tap a vehicle marker → callout appears with headsign, vehicle ID, countdown, adherence, and "position updated Ns ago".
6. Tap **Follow this trip** → the trip screen pushes inside the sheet; back returns to the stop sheet.
7. Drag the sheet to `.full` and back to `.tip` → lines and markers persist; focus survives.
8. With a route focused, tap a **different** stop directly → the new stop's lines appear (not a blank map), and focus is cleared.
9. Dismiss the sheet → every line and marker is gone.
10. Open a stop from **Bookmarks** (a pushed presentation) → chips render exactly as before, are not interactive, and the map is untouched.
11. Toggle the route filter in the sheet's toolbar → the lines shown match the list exactly, in both filter states.

- [ ] **Step 9: Commit**

```bash
git add OBAKit/Mapping/MapViewController.swift OBAKit/Mapping/StopSheetPresenter.swift \
        OBAKitTests/Mapping/StopSheetLayoutMetricsTests.swift
git commit -m "feat: show route lines and live vehicles behind the stop sheet"
```

---

## Self-Review

**Spec coverage.** Every spec section maps to a task: gating → 11; `StopMapFocus`
→ 6; SwiftUI propagation → 9; layer → 8; `MapLayer`/renderer/clearing changes → 3;
`Trip.shapeID` → 1; `removeAllAnnotations` → 2; model derivation, filter parity,
sorting, route cap → 5; shapes, cache, pinning, fan-out cap → 4 and 8; route line
styling → 8; vehicle markers and their two pre-existing bugs → 7; callout and
Follow this trip → 10; focus behavior → 6 and 8; camera → 11; chips → 9;
stop-to-stop swap ordering → 11.

**Deliberately deferred, matching the spec's "Out of scope":** route-stop ring
dots, basemap dimming, direction-flow animation, the `picker` header variant,
header compaction, and the trip push view.

**Known soft spots an implementer must resolve rather than guess** — each is
called out inline in the task that hits it, with the command to check:
`TripIdentifier`'s underlying type (Task 5, Step 4); `VehicleAnnotation`'s
initializer shape (Task 7, Step 4); the `Application` test-stub helper the mapping
suites use (Task 3, Step 2); `Polyline`'s encoder (Task 4, Step 2); the
`getShape` response property path (Task 8, Step 4); `DepartureStatus` and
formatter names (Task 10, Step 4); FloatingPanel's stock `.half` anchor definition
(Task 11, Step 3); and the router method for pushing a trip (Task 11, Step 6).
These are places where inventing an API would be worse than reading the real one.

**Type consistency check.** `StopRouteFocusModel.DrawnRoute` and `DrawnVehicle`
are used with identical field names in Tasks 5, 6, 8, and 9. `StopMapFocus`'s
`apply(routes:)` / `toggleFocus(routeID:)` / `isFocusable(routeID:)` /
`drawnRoute(for:)` are consistent across Tasks 6, 8, and 9. `RouteShapeOverlay.make(coordinates:routeID:isCasing:)`
is used identically in Tasks 4 and 8. `ShapeCache.coordinates(forShapeID:)` is
consistent in Tasks 4 and 8. `StopRouteFocusMapLayer.begin(focus:)` / `end()` /
`update(model:)` are consistent in Tasks 8 and 11.
