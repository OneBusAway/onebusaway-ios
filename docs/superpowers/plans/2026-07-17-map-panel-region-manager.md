# MapPanelRootView ↔ MapRegionManager Adaptation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Feed the SwiftUI `MapPanelRootView` map's camera region into `MapRegionManager` so the shared stop cache populates, then render those stops as branded squircle-with-arrow annotations that open the real stop screen on tap.

**Architecture:** `MapRegionManager` gains an explicit-region load entrypoint (`requestStops(in:)`) plus a debounced scheduler (`scheduleStopsRequest(in:)`). `MapPanelRootView` drives that scheduler from `.onMapCameraChange`, observes stop changes through a new `MapStopsObserver` (a `MapRegionDelegate → @Published` bridge), renders stops via a new `StopIconFactory.buildSquircleIcon(for:)`, and pushes `.stopDetails` on tap. The `.stopDetails` route is wired to a new `StopDetailSheetHost` that bridges the UIKit `StopViewController`.

**Tech Stack:** Swift 5 (language mode) / iOS 18+, SwiftUI, MapKit, Combine, XCTest + Nimble, MockDataLoader fixtures.

## Global Constraints

- Target iOS 18.0+; Swift language mode v5. Match surrounding code's idioms and comment density.
- `MapViewModel` must stay MapKit-free — do **not** add MapKit imports or map-region logic to it. MapKit wiring lives in the View and the new helper types.
- Do **not** stage or commit unless a step explicitly says to; each task ends with its own commit step. No `Co-Authored-By` / authored-by lines in commit messages. One-line commit subjects, no body.
- Do not reset/erase the simulator.
- Build/test scheme is `App`; unit tests target `OBAKitTests`. Run `scripts/generate_project OneBusAway` first if the project file is stale.
- Test build/run commands:
  - Build for testing: `xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
  - Run a test class: `xcodebuild test-without-building -only-testing:OBAKitTests/<ClassName> -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`

**Reference spec:** `docs/superpowers/specs/2026-07-17-map-panel-region-manager-design.md`

---

## File Structure

- **Modify** `OBAKit/Mapping/MapRegionManager.swift` — extract `requestStops(in:)`, add `scheduleStopsRequest(in:)` + `deinit` cancel. (Tasks 1–2)
- **Modify** `OBAKit/Mapping/StopIconFactory.swift` — add `buildSquircleIcon(for:)` / `renderSquircleIcon(routeType:direction:)` + squircle-background helper + cache. (Task 3)
- **Create** `OBAKit/Sheet/Root/MapStopsObserver.swift` — `MapRegionDelegate → @Published [Stop]` bridge. (Task 4)
- **Create** `OBAKit/Sheet/Root/StopDetailSheetHost.swift` — UIKit `StopViewController` bridge. (Task 5)
- **Modify** `OBAKit/Sheet/DI/AppSheetViewFactory.swift` — implement the `.stopDetails` branch. (Task 6)
- **Modify** `OBAKit/Sheet/Root/MapPanelRootView.swift` — camera observation, stop rendering, selection→push, store `application` + `@StateObject` observer + `selectedStopID`, trim the completed TODO. (Task 7)

**Tests:**
- **Modify** `OBAKitTests/Application/Mapping/MapRegionManagerTests.swift` — Tasks 1–2.
- **Create** `OBAKitTests/Application/Mapping/StopIconFactoryTests.swift` — Task 3.
- **Create** `OBAKitTests/Sheet/MapStopsObserverTests.swift` — Task 4.
- **Create** `OBAKitTests/Sheet/StopDetailSheetHostTests.swift` — Task 5.
- **Modify** `OBAKitTests/Sheet/AppSheetViewFactoryTests.swift` — Task 6.

---

## Task 1: `MapRegionManager.requestStops(in:)` — explicit-region load

Extract the body of `requestDataForMapRegion()` into a region-taking method so a SwiftUI host can drive stop loading with its own camera region. `requestDataForMapRegion()` becomes a thin caller using `mapView.region` — zero behavior change for the UIKit path.

**Files:**
- Modify: `OBAKit/Mapping/MapRegionManager.swift` (the `requestDataForMapRegion()` at ~lines 251–313)
- Test: `OBAKitTests/Application/Mapping/MapRegionManagerTests.swift`

**Interfaces:**
- Consumes: `application.apiService.getStops(region:)`, `MapRegionManager.stops` (existing).
- Produces: `func requestStops(in region: MKCoordinateRegion) async` (populates `stops`); `func requestDataForMapRegion() async` retained (now delegates to `requestStops(in: mapView.region)`).

- [ ] **Step 1: Write the failing test**

Add to `MapRegionManagerTests` (it already has `import MapKit`? it imports `Foundation`/`XCTest` — add `import MapKit` and `import CoreLocation` at the top if not present):

```swift
@MainActor
func test_requestStops_inRegion_populatesStops() async {
    let dataLoader = MockDataLoader(testName: name)
    stubRegions(dataLoader: dataLoader)
    stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
    Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

    // Any stops-for-location request returns the Seattle fixture.
    dataLoader.mock(data: Fixtures.loadData(file: "stops_for_location_seattle.json")) { request in
        request.url?.path.contains("/api/where/stops-for-location.json") ?? false
    }

    let locManager = MockAuthorizedLocationManager(
        updateLocation: TestData.mockSeattleLocation,
        updateHeading: TestData.mockHeading
    )
    let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
    let application = makeApp(dataLoader: dataLoader, locationService: locationService)

    let mgr = MapRegionManager(application: application)
    let region = MKCoordinateRegion(
        center: TestData.mockSeattleLocation.coordinate,
        latitudinalMeters: 5000,
        longitudinalMeters: 5000
    )

    await mgr.requestStops(in: region)

    expect(mgr.stops).toNot(beEmpty())
}
```

If `makeApp(dataLoader:locationService:)` is not visible from this test file, build the `Application` with the same `makeConfig(...)` helper already present in `MapRegionManagerTests` and set the location service on it — mirror `test_init`'s construction, adding the `stops-for-location` mock above.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test-without-building -only-testing:OBAKitTests/MapRegionManagerTests/test_requestStops_inRegion_populatesStops -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: FAIL to compile — `value of type 'MapRegionManager' has no member 'requestStops'`.

- [ ] **Step 3: Refactor `requestDataForMapRegion()` into `requestStops(in:)`**

In `OBAKit/Mapping/MapRegionManager.swift`, replace the existing `func requestDataForMapRegion() async { … }` (the ~60-line body) with the two methods below. The body is the original verbatim except `var mapRegion = mapView.region` becomes `var mapRegion = region`:

```swift
/// Loads stops for an explicitly provided region and stores them in `stops`.
///
/// Used by SwiftUI hosts whose map view is not this manager's `mapView`.
/// Applies the same fudge factor, cache-save, and cache-fallback behavior as
/// the UIKit region-change path.
func requestStops(in region: MKCoordinateRegion) async {
    guard let apiService = application.apiService else {
        return
    }

    await MainActor.run {
        notifyDelegatesDataLoadingStarted()
    }

    defer {
        Task { @MainActor in
            notifyDelegatesDataLoadingFinished()
        }
    }

    var mapRegion = region
    mapRegion.span.latitudeDelta *= preferredLoadDataRegionFudgeFactor
    mapRegion.span.longitudeDelta *= preferredLoadDataRegionFudgeFactor

    do {
        let stops = try await apiService.getStops(region: mapRegion).list

        await MainActor.run {
            // Some UI code is dependent on this being changed on Main.
            self.stops = stops
        }

        // Save to cache in the background for offline use.
        // See: https://github.com/OneBusAway/onebusaway-ios/issues/62
        if let regionId = application.currentRegion?.regionIdentifier,
           let repository = application.stopCacheRepository {
            repository.saveStops(stops, regionId: regionId)
        }
    } catch {
        // Don't attempt cache fallback for cancelled tasks (e.g., user navigated away).
        if error is CancellationError { return }

        Logger.error("API stop request failed, attempting cache fallback: \(error)")

        // On API failure, try serving from cache before showing error
        if let regionId = application.currentRegion?.regionIdentifier,
           let repository = application.stopCacheRepository {
            let minLat = mapRegion.center.latitude - mapRegion.span.latitudeDelta / 2.0
            let maxLat = mapRegion.center.latitude + mapRegion.span.latitudeDelta / 2.0
            let minLon = mapRegion.center.longitude - mapRegion.span.longitudeDelta / 2.0
            let maxLon = mapRegion.center.longitude + mapRegion.span.longitudeDelta / 2.0

            let cachedStops = repository.stopsInRegion(
                minLat: minLat, maxLat: maxLat,
                minLon: minLon, maxLon: maxLon,
                regionId: regionId
            )

            if !cachedStops.isEmpty {
                await MainActor.run {
                    self.stops = cachedStops
                }
                return
            }
        }
        await self.application.displayError(error)
    }
}

/// UIKit entrypoint: loads stops for the manager's own `mapView` region.
func requestDataForMapRegion() async {
    await requestStops(in: mapView.region)
}
```

Leave the `@objc func requestDataForMapRegion(_ timer: Timer)` immediately below it untouched — it still calls the no-arg `requestDataForMapRegion()`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild test-without-building -only-testing:OBAKitTests/MapRegionManagerTests/test_requestStops_inRegion_populatesStops -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` (build first with the `build-for-testing` command if needed)
Expected: PASS.

- [ ] **Step 5: Verify the UIKit path is unregressed**

Run: `xcodebuild test-without-building -only-testing:OBAKitTests/RoutePickerViewModelTests/test_loadRoutes_cacheFirst_doesNotHitAPI -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: PASS (this test calls `requestDataForMapRegion()`, proving the delegation works).

- [ ] **Step 6: Commit**

```bash
git add OBAKit/Mapping/MapRegionManager.swift OBAKitTests/Application/Mapping/MapRegionManagerTests.swift
git commit -m "Add MapRegionManager.requestStops(in:) explicit-region load path"
```

---

## Task 2: `MapRegionManager.scheduleStopsRequest(in:)` — debounced scheduler

Add a debounced, fire-and-forget entrypoint the View can call on every camera settle. It coalesces bursts (matching the UIKit 0.25s timer) and cancels the previous in-flight request.

**Files:**
- Modify: `OBAKit/Mapping/MapRegionManager.swift`
- Test: `OBAKitTests/Application/Mapping/MapRegionManagerTests.swift`

**Interfaces:**
- Consumes: `requestStops(in:)` from Task 1.
- Produces: `func scheduleStopsRequest(in region: MKCoordinateRegion)` (non-async, debounced). A private `pendingStopsRequestTask: Task<Void, Never>?` cancelled in `deinit`.

- [ ] **Step 1: Write the failing test**

Add to `MapRegionManagerTests`:

```swift
@MainActor
func test_scheduleStopsRequest_debouncedLoadPopulatesStops() async {
    let dataLoader = MockDataLoader(testName: name)
    stubRegions(dataLoader: dataLoader)
    stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
    Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

    dataLoader.mock(data: Fixtures.loadData(file: "stops_for_location_seattle.json")) { request in
        request.url?.path.contains("/api/where/stops-for-location.json") ?? false
    }

    let locManager = MockAuthorizedLocationManager(
        updateLocation: TestData.mockSeattleLocation,
        updateHeading: TestData.mockHeading
    )
    let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
    let application = makeApp(dataLoader: dataLoader, locationService: locationService)

    let mgr = MapRegionManager(application: application)
    let region = MKCoordinateRegion(
        center: TestData.mockSeattleLocation.coordinate,
        latitudinalMeters: 5000,
        longitudinalMeters: 5000
    )

    // Rapid succession: only the last should survive the debounce.
    mgr.scheduleStopsRequest(in: region)
    mgr.scheduleStopsRequest(in: region)

    // Debounce is 250ms; poll up to Nimble's default timeout for the load.
    await expect(mgr.stops).toEventuallyNot(beEmpty())
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test-without-building -only-testing:OBAKitTests/MapRegionManagerTests/test_scheduleStopsRequest_debouncedLoadPopulatesStops -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: FAIL to compile — no member `scheduleStopsRequest`.

- [ ] **Step 3: Add the scheduler and deinit cancel**

In `MapRegionManager.swift`, add the property near `private var regionChangeRequestTimer: Timer?` (~line 72):

```swift
/// Debounced request task for SwiftUI hosts driving `scheduleStopsRequest(in:)`.
private var pendingStopsRequestTask: Task<Void, Never>?
```

Add this method directly beneath `requestDataForMapRegion()` (from Task 1):

```swift
/// Debounced, fire-and-forget entrypoint for SwiftUI hosts. Coalesces rapid
/// camera settles (matching the UIKit 0.25s timer) and cancels any in-flight
/// request before loading stops for `region`.
func scheduleStopsRequest(in region: MKCoordinateRegion) {
    pendingStopsRequestTask?.cancel()
    pendingStopsRequestTask = Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        await self?.requestStops(in: region)
    }
}
```

In the existing `deinit` (~line 219), add this line alongside the other teardown (e.g. after `regionChangeRequestTimer?.invalidate()`):

```swift
pendingStopsRequestTask?.cancel()
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild test-without-building -only-testing:OBAKitTests/MapRegionManagerTests/test_scheduleStopsRequest_debouncedLoadPopulatesStops -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OBAKit/Mapping/MapRegionManager.swift OBAKitTests/Application/Mapping/MapRegionManagerTests.swift
git commit -m "Add debounced MapRegionManager.scheduleStopsRequest(in:)"
```

---

## Task 3: `StopIconFactory.buildSquircleIcon(for:)` — squircle icon with directional arrow

Render the recent-stops squircle treatment (brand-gradient squircle + white transport glyph) with the stop's directional arrow drawn in the outer track, reusing the existing arrow geometry. Cache by `(routeType, direction)`.

**Files:**
- Modify: `OBAKit/Mapping/StopIconFactory.swift`
- Test: `OBAKitTests/Application/Mapping/StopIconFactoryTests.swift` (create)

**Interfaces:**
- Consumes: existing `drawIcon(routeType:rect:context:color:)`, `drawArrowImage(direction:strokeColor:rect:context:)`, `strokeColor`, `themeColors`, `iconSize`, `arrowTrackSize`, `context.pushPop`, `UIColor.blended(with:amount:)`, `Icons.transportIcon(from:)`.
- Produces: `func buildSquircleIcon(for stop: Stop) -> UIImage`; `func renderSquircleIcon(routeType: Route.RouteType, direction: Direction) -> UIImage`.

- [ ] **Step 1: Write the failing test**

Create `OBAKitTests/Application/Mapping/StopIconFactoryTests.swift`:

```swift
//
//  StopIconFactoryTests.swift
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

final class StopIconFactoryTests: OBATestCase {

    private func makeFactory() -> StopIconFactory {
        StopIconFactory(iconSize: 44, themeColors: ThemeColors.shared)
    }

    func test_buildSquircleIcon_returnsCachedInstanceForSameStop() throws {
        let factory = makeFactory()
        let stop = try XCTUnwrap(Fixtures.loadSomeStops().first)

        let first = factory.buildSquircleIcon(for: stop)
        let second = factory.buildSquircleIcon(for: stop)

        // Same (routeType, direction) key → cache hit → identical instance.
        expect(first) === second
    }

    func test_buildSquircleIcon_producesIconAtConfiguredSize() throws {
        let factory = makeFactory()
        let stop = try XCTUnwrap(Fixtures.loadSomeStops().first)

        let icon = factory.buildSquircleIcon(for: stop)

        expect(icon.size.width) == 44
        expect(icon.size.height) == 44
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test-without-building -only-testing:OBAKitTests/StopIconFactoryTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: FAIL to compile — no member `buildSquircleIcon`.

- [ ] **Step 3: Implement the squircle icon**

In `OBAKit/Mapping/StopIconFactory.swift`, add a cache property near `private let iconCache = NSCache<NSString, UIImage>()` (~line 19):

```swift
private let squircleIconCache = NSCache<NSString, UIImage>()
```

Add these methods (e.g. after the existing `renderIcon(routeType:direction:isBookmarked:)`):

```swift
// MARK: - Squircle map annotation icon

/// Map annotation icon: the recent-stops squircle treatment (brand-gradient
/// squircle + white transport glyph) with the stop's directional arrow drawn
/// in the outer track. Cached by `(routeType, direction)`.
func buildSquircleIcon(for stop: Stop) -> UIImage {
    renderSquircleIcon(routeType: stop.prioritizedRouteTypeForDisplay, direction: stop.direction)
}

/// Draws a squircle stop icon with the specified route type and direction.
func renderSquircleIcon(routeType: Route.RouteType, direction: Direction) -> UIImage {
    let key = "squircle:\(routeType.rawValue):\(direction.rawValue):\(iconSize)" as NSString
    if let cached = squircleIconCache.object(forKey: key) {
        return cached
    }

    let imageBounds = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
    let rect = imageBounds.insetBy(dx: arrowTrackSize, dy: arrowTrackSize)

    let renderer = UIGraphicsImageRenderer(size: CGSize(width: iconSize, height: iconSize))
    let image = renderer.image { [weak self] rendererContext in
        guard let self = self else { return }
        let ctx = rendererContext.cgContext

        self.drawSquircleBackground(rect: rect, context: ctx)
        self.drawIcon(routeType: routeType, rect: rect, context: ctx, color: .white)
        self.drawArrowImage(direction: direction, strokeColor: self.strokeColor, rect: imageBounds, context: ctx)
    }

    squircleIconCache.setObject(image, forKey: key)
    return image
}

/// Draws the brand-color gradient squircle background, echoing
/// `Icons.squircleTransportIcon`.
private func drawSquircleBackground(rect: CGRect, context: CGContext) {
    context.pushPop {
        let brand = themeColors.brand
        UIBezierPath(roundedRect: rect, cornerRadius: iconSize * 0.28).addClip()

        let colors = [
            brand.blended(with: .white, amount: 0.18).cgColor,
            brand.blended(with: .black, amount: 0.12).cgColor
        ]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0, 1]) else {
            brand.setFill()
            context.fill(rect)
            return
        }

        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.minY),
            end: CGPoint(x: rect.midX, y: rect.maxY),
            options: []
        )
    }
}
```

If the compiler reports `blended(with:amount:)` unavailable, confirm the exact spelling by searching `OBAKit/Theme/Icons.swift` (it is used there in `squircleTransportIcon`) and match it.

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild test-without-building -only-testing:OBAKitTests/StopIconFactoryTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add OBAKit/Mapping/StopIconFactory.swift OBAKitTests/Application/Mapping/StopIconFactoryTests.swift
git commit -m "Add StopIconFactory.buildSquircleIcon(for:) for the SwiftUI map"
```

---

## Task 4: `MapStopsObserver` — MapRegionDelegate → @Published bridge

A small `ObservableObject` that registers as a `MapRegionDelegate` and republishes `MapRegionManager.stops` so SwiftUI can render annotations reactively. Keeps the UIKit-era delegate off `MapViewModel`.

**Files:**
- Create: `OBAKit/Sheet/Root/MapStopsObserver.swift`
- Test: `OBAKitTests/Sheet/MapStopsObserverTests.swift` (create)

**Interfaces:**
- Consumes: `MapRegionManager.addDelegate(_:)`, `MapRegionManager.stops`, `MapRegionDelegate.mapRegionManager(_:stopsUpdated:)`, `requestStops(in:)` (Task 1).
- Produces: `@MainActor final class MapStopsObserver: NSObject, ObservableObject, MapRegionDelegate` with `@Published private(set) var stops: [Stop]` and `init(mapRegionManager: MapRegionManager)`.

- [ ] **Step 1: Write the failing test**

Create `OBAKitTests/Sheet/MapStopsObserverTests.swift`:

```swift
//
//  MapStopsObserverTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import MapKit
import Nimble
@testable import OBAKit
@testable import OBAKitCore

final class MapStopsObserverTests: OBATestCase {

    private var queue: OperationQueue!

    override func setUp() {
        super.setUp()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    override func tearDown() {
        super.tearDown()
        queue.cancelAllOperations()
    }

    @MainActor
    func test_observer_publishesStopsWhenManagerLoads() async {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        dataLoader.mock(data: Fixtures.loadData(file: "stops_for_location_seattle.json")) { request in
            request.url?.path.contains("/api/where/stops-for-location.json") ?? false
        }

        let observer = MapStopsObserver(mapRegionManager: application.mapRegionManager)
        expect(observer.stops).to(beEmpty())

        let region = MKCoordinateRegion(
            center: TestData.mockSeattleLocation.coordinate,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        )
        await application.mapRegionManager.requestStops(in: region)

        expect(observer.stops).toNot(beEmpty())
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test-without-building -only-testing:OBAKitTests/MapStopsObserverTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: FAIL to compile — `cannot find 'MapStopsObserver' in scope`.

- [ ] **Step 3: Implement the observer**

Create `OBAKit/Sheet/Root/MapStopsObserver.swift`:

```swift
//
//  MapStopsObserver.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Bridges `MapRegionManager`'s `stopsUpdated` delegate callback to a
/// `@Published` array so a SwiftUI `Map` can render stop annotations
/// reactively.
///
/// Intentionally separate from `MapViewModel`, which stays MapKit-free and does
/// not adopt the UIKit-era `MapRegionDelegate`.
@MainActor
final class MapStopsObserver: NSObject, ObservableObject, MapRegionDelegate {

    /// Stops currently loaded for the visible map region.
    @Published private(set) var stops: [Stop] = []

    init(mapRegionManager: MapRegionManager) {
        super.init()
        // Seed with whatever's already loaded so a re-created observer isn't empty.
        stops = mapRegionManager.stops
        mapRegionManager.addDelegate(self)
    }

    // MARK: - MapRegionDelegate

    func mapRegionManager(_ manager: MapRegionManager, stopsUpdated stops: [Stop]) {
        self.stops = stops
    }
}
```

Note: `addDelegate` stores the delegate in an `NSHashTable.weakObjects()`, so no explicit removal is required; the observer is released with its owner.

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild test-without-building -only-testing:OBAKitTests/MapStopsObserverTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OBAKit/Sheet/Root/MapStopsObserver.swift OBAKitTests/Sheet/MapStopsObserverTests.swift
git commit -m "Add MapStopsObserver bridging MapRegionManager stops to SwiftUI"
```

---

## Task 5: `StopDetailSheetHost` — UIKit StopViewController bridge

Mirror `MoreSheetHost`: wrap the UIKit `StopViewController` in a `UINavigationController` so `.stopDetails` opens the real stop screen. Expose a testable static seam.

**Files:**
- Create: `OBAKit/Sheet/Root/StopDetailSheetHost.swift`
- Test: `OBAKitTests/Sheet/StopDetailSheetHostTests.swift` (create)

**Interfaces:**
- Consumes: `StopViewController(application:stopID:)`, `Stop.ID` (= `StopID`).
- Produces: `struct StopDetailSheetHost: UIViewControllerRepresentable` with stored `application: Application` and `stopID: Stop.ID`, plus `static func makeNavigationController(application:stopID:) -> UINavigationController`.

- [ ] **Step 1: Write the failing test**

Create `OBAKitTests/Sheet/StopDetailSheetHostTests.swift`:

```swift
//
//  StopDetailSheetHostTests.swift
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

final class StopDetailSheetHostTests: OBATestCase {

    private var queue: OperationQueue!

    override func setUp() {
        super.setUp()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    override func tearDown() {
        super.tearDown()
        queue.cancelAllOperations()
    }

    @MainActor
    func test_makeNavigationController_wrapsStopViewControllerInNav() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let nav = StopDetailSheetHost.makeNavigationController(application: application, stopID: "1_10914")

        expect(nav.viewControllers.count) == 1
        expect(nav.topViewController).to(beAKindOf(StopViewController.self))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test-without-building -only-testing:OBAKitTests/StopDetailSheetHostTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: FAIL to compile — `cannot find 'StopDetailSheetHost' in scope`.

- [ ] **Step 3: Implement the host**

Create `OBAKit/Sheet/Root/StopDetailSheetHost.swift`:

```swift
//
//  StopDetailSheetHost.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore

/// UIKit wiring wrapper: presents the existing `StopViewController` inside a
/// `UINavigationController` so its `navigationItem` bar buttons render correctly
/// when reached via `AppSheetRoute.stopDetails`.
///
/// Deliberately minimal — a future SwiftUI stop-detail view will replace this
/// wrapper in `AppSheetViewFactory` without touching the coordinator or route enum.
struct StopDetailSheetHost: UIViewControllerRepresentable {
    let application: Application
    let stopID: Stop.ID

    func makeUIViewController(context: Context) -> UINavigationController {
        Self.makeNavigationController(application: application, stopID: stopID)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) { }

    /// Internal factory seam mirroring `MoreSheetHost`: builds the same
    /// controller hierarchy without a `Context`, so tests can drive the wiring
    /// without going through `UIHostingController`.
    static func makeNavigationController(application: Application, stopID: Stop.ID) -> UINavigationController {
        let stopController = StopViewController(application: application, stopID: stopID)
        return UINavigationController(rootViewController: stopController)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild test-without-building -only-testing:OBAKitTests/StopDetailSheetHostTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OBAKit/Sheet/Root/StopDetailSheetHost.swift OBAKitTests/Sheet/StopDetailSheetHostTests.swift
git commit -m "Add StopDetailSheetHost bridging UIKit StopViewController"
```

---

## Task 6: Wire `.stopDetails` into `AppSheetViewFactory`

Move the `.stopDetails` case out of the `unimplementedView` catch-all and return a `StopDetailSheetHost`.

**Files:**
- Modify: `OBAKit/Sheet/DI/AppSheetViewFactory.swift`
- Test: `OBAKitTests/Sheet/AppSheetViewFactoryTests.swift`

**Interfaces:**
- Consumes: `StopDetailSheetHost` (Task 5).
- Produces: `func stopDetailView(stopID: Stop.ID) -> StopDetailSheetHost`; `view(for: .stopDetails(let stopID))` now returns it.

- [ ] **Step 1: Write the failing test**

Add to `AppSheetViewFactoryTests`:

```swift
@MainActor
func test_stopDetailView_returnsStopDetailSheetHostForwardingApplicationAndStopID() {
    let dataLoader = MockDataLoader(testName: name)
    let application = buildApplication(queue: queue, dataLoader: dataLoader)

    let factory = AppSheetViewFactory(application: application, onPresentTrip: { _ in })
    let host = factory.stopDetailView(stopID: "1_10914")

    expect(host.application === application) == true
    expect(host.stopID) == "1_10914"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test-without-building -only-testing:OBAKitTests/AppSheetViewFactoryTests/test_stopDetailView_returnsStopDetailSheetHostForwardingApplicationAndStopID -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: FAIL to compile — no member `stopDetailView`.

- [ ] **Step 3: Implement the branch**

In `OBAKit/Sheet/DI/AppSheetViewFactory.swift`, remove `.stopDetails` from the `unimplementedView` catch-all case list and add a dedicated case. The dispatcher's catch-all currently reads:

```swift
        case .search, .nearbyAll, .recentStopsAll, .bookmarksAll,
             .stopDetails, .tripPlanner, .tripDetails, .transitAlert, .settings:
            unimplementedView(for: route)
```

Change it to (note `.stopDetails` removed) and add the new case:

```swift
        case .search, .nearbyAll, .recentStopsAll, .bookmarksAll,
             .tripPlanner, .tripDetails, .transitAlert, .settings:
            unimplementedView(for: route)

        case .stopDetails(let stopID):
            stopDetailView(stopID: stopID)
```

Add the per-route builder alongside `moreView()`:

```swift
/// Bridges `AppSheetRoute.stopDetails` to the existing UIKit `StopViewController`
/// via `StopDetailSheetHost`. Swap this branch's return type once a SwiftUI
/// stop-detail view lands.
func stopDetailView(stopID: Stop.ID) -> StopDetailSheetHost {
    StopDetailSheetHost(application: application, stopID: stopID)
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild test-without-building -only-testing:OBAKitTests/AppSheetViewFactoryTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: PASS (existing `moreView` test and the new one).

- [ ] **Step 5: Commit**

```bash
git add OBAKit/Sheet/DI/AppSheetViewFactory.swift OBAKitTests/Sheet/AppSheetViewFactoryTests.swift
git commit -m "Wire AppSheetRoute.stopDetails to StopDetailSheetHost"
```

---

## Task 7: Wire `MapPanelRootView` — camera observation, stop rendering, tap

Integrate everything: store `application` and a `@StateObject` `MapStopsObserver`; feed camera settles to `scheduleStopsRequest(in:)`; render stops as squircle annotations; push `.stopDetails` on selection. Trim the completed region-manager TODO (keep the still-open detent-padding TODO). This is a SwiftUI-view integration; it is verified by compiling the test target and a manual run rather than a unit test.

**Files:**
- Modify: `OBAKit/Sheet/Root/MapPanelRootView.swift`

**Interfaces:**
- Consumes: `application.mapRegionManager.scheduleStopsRequest(in:)` (Task 2), `application.stopIconFactory.buildSquircleIcon(for:)` (Task 3), `MapStopsObserver` (Task 4), `AppSheetRoute.stopDetails(stopID:)` (Task 6), `SheetCoordinator.push(_:)` (existing).
- Produces: none (top-level view).

- [ ] **Step 1: Add stored `application`, observer, and selection state**

In `MapPanelRootView`, add these properties near the other `@State`/`@StateObject` declarations:

```swift
@StateObject private var stopsObserver: MapStopsObserver

/// The stop the user tapped, if any. Bound to the `Map`'s `selection`; cleared
/// after pushing so re-tapping the same stop pushes again.
@State private var selectedStopID: Stop.ID?

private let application: Application
```

Update `init` to store `application` and seed the observer:

```swift
init(application: Application, factory: AppSheetViewFactory) {
    _coordinator = StateObject(wrappedValue: SheetCoordinator<AppSheetRoute>(root: .home))
    _mapViewModel = StateObject(wrappedValue: MapViewModel(application: application))
    _stopsObserver = StateObject(wrappedValue: MapStopsObserver(mapRegionManager: application.mapRegionManager))
    self.application = application
    self.factory = factory
}
```

- [ ] **Step 2: Replace the `Map` with the selection-driven, annotated version**

Delete the multi-line `// TODO: Wire this SwiftUI Map to application.mapRegionManager …` comment block (the one ending at `… also unblocks rendering stop annotations on the SwiftUI map).`) — it is now implemented. Replace the existing `Map(position: $cameraPosition) { UserAnnotation() }` with:

```swift
Map(position: $cameraPosition, selection: $selectedStopID) {
    UserAnnotation()
    ForEach(stopsObserver.stops) { stop in
        Annotation(stop.name, coordinate: stop.coordinate) {
            Image(uiImage: application.stopIconFactory.buildSquircleIcon(for: stop))
        }
        .tag(stop.id)
    }
}
.annotationTitles(.hidden)
.onMapCameraChange(frequency: .onEnd) { context in
    application.mapRegionManager.scheduleStopsRequest(in: context.region)
}
.onChange(of: selectedStopID) { _, id in
    guard let id else { return }
    coordinator.push(.stopDetails(stopID: id))
    selectedStopID = nil
}
```

Keep every existing modifier that already follows the `Map` (`.safeAreaPadding(.bottom, 180)`, `.onGeometryChange { … }`, the second `.safeAreaPadding(.bottom, AppSheetRoute.homeCollapsedHeight)` with its **still-valid** detent-padding TODO, the `.overlay` blocks, `.floatingSheet`, `.onAppear`, `.onChange(of: scenePhase)`). Do **not** remove the detent-padding TODO at `// TODO: Detent-aware bottom padding. …` — it is a separate, still-open item (explicit non-goal here).

- [ ] **Step 3: Build the test target to verify it compiles**

Run: `xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: BUILD SUCCEEDED. (Resolves the `Map` selection generic, `Annotation`/`.tag`, and the new property wiring.)

- [ ] **Step 4: Run the full new/affected suites**

Run: `xcodebuild test-without-building -only-testing:OBAKitTests/MapRegionManagerTests -only-testing:OBAKitTests/StopIconFactoryTests -only-testing:OBAKitTests/MapStopsObserverTests -only-testing:OBAKitTests/StopDetailSheetHostTests -only-testing:OBAKitTests/AppSheetViewFactoryTests -only-testing:OBAKitTests/RoutePickerViewModelTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: PASS.

- [ ] **Step 5: Manual verification (run the app on the experimental SwiftUI root)**

Use the `run` skill (or launch the `App` scheme on the simulator with the SwiftUI map-panel experience enabled). Confirm: panning the map loads stop annotations (squircle icon with a directional arrow), and tapping a stop opens the real `StopViewController` in a sheet. Confirm the route picker's route list now matches the on-screen viewport.

- [ ] **Step 6: Commit**

```bash
git add OBAKit/Sheet/Root/MapPanelRootView.swift
git commit -m "Render stops and wire region loading in MapPanelRootView"
```

---

## Self-Review Notes (for the executor)

- **Spec coverage:** A1→Task 1; A2→Task 2; A3→Task 7 Step 2; B1→Task 4; B2→Task 3; B3→Task 7 Step 2; B4→Tasks 5–6. Testing bullets → Tasks 1–6 tests. Non-goals (detent padding, bookmark treatment, zoom-out gate) are intentionally untouched.
- **Type consistency:** `requestStops(in:)`, `scheduleStopsRequest(in:)`, `buildSquircleIcon(for:)`, `MapStopsObserver(mapRegionManager:)`, `StopDetailSheetHost(application:stopID:)` / `makeNavigationController(application:stopID:)`, `stopDetailView(stopID:)`, `AppSheetRoute.stopDetails(stopID:)` are used identically across producing and consuming tasks. `Stop.ID` is `StopID` (String) throughout.
- **If `makeApp(dataLoader:locationService:)` is not accessible** from `MapRegionManagerTests`, build the `Application` via the file's own `makeConfig(...)` helper (see `test_init`) and add the `stops-for-location` mock — the assertions are unchanged.
