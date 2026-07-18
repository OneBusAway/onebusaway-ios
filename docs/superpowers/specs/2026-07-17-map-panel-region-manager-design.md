# MapPanelRootView ↔ MapRegionManager adaptation

**Date:** 2026-07-17
**Branch:** `feature/map-panel-region-manager`
**Status:** Approved design, ready for implementation planning

## Problem

`MapPanelRootView` is the pure-SwiftUI composition root for the sheet system: a
full-screen SwiftUI `Map` with the floating sheet layered on top. Its `Map` never
touches `MapRegionManager`, which produces two defects:

1. **Pickers disagree with the map.** The UIKit `MapViewController` populates
   `MapRegionManager.stops` via `requestDataForMapRegion()` whenever its `MKMapView`
   region changes. Both `RoutePickerViewModel` and `CurrentTripViewModel` read
   `application.mapRegionManager.stops` (cache-first) before falling back to a
   coordinate-based API call. Because the SwiftUI `Map` never feeds the region
   manager, the cache stays empty on this surface and the pickers always take the
   coordinate-fallback path — yielding a different (often larger) route/trip set
   than the UIKit picker shows for the same on-screen viewport.

2. **No stops on the SwiftUI map.** With the cache never populated and no rendering
   wiring, the SwiftUI `Map` shows only the user-location dot — no stop annotations,
   no way to open a stop.

This is captured by the `TODO` at `OBAKit/Sheet/Root/MapPanelRootView.swift:55`.

## Goal

1. Feed the SwiftUI `Map`'s camera region into `MapRegionManager` so
   `mapRegionManager.stops` is populated for the on-screen viewport, making both
   pickers agree with the UIKit surface.
2. Render the loaded stops as branded annotations on the SwiftUI `Map`.
3. Tapping a stop opens the real stop screen.

## Key constraints discovered

- `MapRegionManager.requestDataForMapRegion()` reads `mapView.region` from the
  manager's **own** `MKMapView`, which `MapPanelRootView` never displays. An
  un-laid-out `MKMapView`'s region is unreliable, so the SwiftUI camera region must
  be passed in **explicitly** rather than leaning on the manager's map view.
- `MapViewModel` is deliberately MapKit-free (documented). The MapKit-touching
  wiring therefore lives in the View / dedicated helpers, not the VM.
- `MapRegionManager.stops` is not observable; the manager broadcasts changes via the
  `MapRegionDelegate.mapRegionManager(_:stopsUpdated:)` callback. `MapViewModel`
  intentionally does not adopt that delegate (its callbacks are "UIKit/router-shaped").
- `Stop` already conforms to `MKAnnotation` (retroactive extension) and is
  `Identifiable` by `StopID`, with `coordinate` and `name` — directly usable in a
  SwiftUI `Map` content builder.
- No SwiftUI stop-detail view exists yet. The real stop screen is UIKit
  `StopViewController`. The `.stopDetails` sheet route exists but its
  `AppSheetViewFactory` branch is an unimplemented placeholder.
- Two existing stop-icon treatments are relevant:
  - `Icons.squircleTransportIcon(for: Route.RouteType)` — the transport glyph in
    white over a brand-color gradient squircle (echoing the stop page's
    `RouteBadgeView`), used by the recent-stops list rows. Cached globally per
    `RouteType`; no directional arrow.
  - `StopIconFactory` — the current map annotation icon. Its `drawArrowImage`
    renders the stop's directional arrow in an outer gutter around the badge, and
    it caches per `(routeType, direction, size, appearance, bookmarked)`.
  The map annotation here wants the squircle *look* with the directional arrow
  *preserved*, so it combines both.

## Decisions (locked)

- **Scope:** cache wiring **and** stop rendering with tap-to-open.
- **Tap target:** UIKit bridge — open the real `StopViewController` now (also fills
  in the currently-unimplemented `.stopDetails` factory branch).
- **Annotation style:** the recent-stops squircle treatment (brand-gradient
  squircle + white transport glyph) **with the directional arrow preserved** from
  the old map annotation. Combines `Icons.squircleTransportIcon`'s look with
  `StopIconFactory`'s directional arrow.

## Design

### Part A — Feed the camera region into the stop cache

**A1. `MapRegionManager` — parametrize the load path (no behavior change for UIKit).**
Extract the current `requestDataForMapRegion()` body into a region-taking method;
keep the no-arg version as a thin caller:

```swift
/// Loads stops for an explicitly provided region. Applies the same fudge factor,
/// cache-save, and cache-fallback as the UIKit region-change path.
func requestStops(in region: MKCoordinateRegion) async {
    // = current requestDataForMapRegion() body, using `region` instead of mapView.region
}

func requestDataForMapRegion() async {          // unchanged UIKit entrypoint
    await requestStops(in: mapView.region)
}
```

The `@objc requestDataForMapRegion(_ timer:)` and the existing
`RoutePickerViewModelTests` call site keep working unchanged. `stops`'s `didSet`
still runs `displayUniqueStopAnnotations()` against the offscreen map view —
harmless (nothing is displayed), and it keeps a single code path and preserves the
`stopsUpdated` delegate notification that Part B relies on.

**A2. `MapRegionManager` — debounced, cancelling wrapper for the SwiftUI caller.**

```swift
private var pendingStopsRequestTask: Task<Void, Never>?

/// Debounced, fire-and-forget entrypoint for SwiftUI hosts. Coalesces rapid camera
/// settles (matching the UIKit 0.25s timer) and cancels any in-flight request.
func scheduleStopsRequest(in region: MKCoordinateRegion) {
    pendingStopsRequestTask?.cancel()
    pendingStopsRequestTask = Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        await self?.requestStops(in: region)
    }
}
```

Cancel `pendingStopsRequestTask` in `deinit`. `requestStops`'s existing
`CancellationError` handling means cancelled loads surface no error.

**A3. `MapPanelRootView` — observe the camera.** Store the manager (init already
receives `application` but currently discards it), then:

```swift
Map(position: $cameraPosition, selection: $selectedStopID) { /* content */ }
    .onMapCameraChange(frequency: .onEnd) { context in
        mapRegionManager.scheduleStopsRequest(in: context.region)
    }
```

`.onMapCameraChange` fires an initial callback when the map first appears, so the
cache primes on load without a separate initial fetch.

### Part B — Render stops as branded annotations, tap opens the real stop

**B1. Reactive stop state — new `MapStopsObserver`.**

```swift
@MainActor
final class MapStopsObserver: NSObject, ObservableObject, MapRegionDelegate {
    @Published private(set) var stops: [Stop] = []

    init(mapRegionManager: MapRegionManager) {
        super.init()
        stops = mapRegionManager.stops            // seed with whatever's already loaded
        mapRegionManager.addDelegate(self)
    }

    func mapRegionManager(_ manager: MapRegionManager, stopsUpdated stops: [Stop]) {
        self.stops = stops
    }
}
```

Owned by `MapPanelRootView` as a `@StateObject`. Isolates the UIKit-era delegate
from `MapViewModel`, keeping the VM MapKit-free. (`addDelegate` uses a weak table,
so no explicit removal is required, but `deinit` may remove for symmetry.)

**B2. Squircle icon with directional arrow.** The annotation icon layers the stop's
directional arrow over the recent-stops squircle treatment (brand-gradient squircle
+ white transport glyph). Implement as a new `StopIconFactory` method — e.g.
`buildSquircleIcon(for stop: Stop) -> UIImage` — that draws the squircle background +
white glyph inset to leave the outer gutter, then reuses the existing
`drawArrowImage(direction:…)` for the arrow. Cache by `(routeType, direction)` (no
bookmark or appearance variation — the squircle is appearance-independent). The View
renders `Image(uiImage: application.stopIconFactory.buildSquircleIcon(for: stop))`.

Reuse, don't duplicate: the arrow geometry stays in `StopIconFactory`; the
squircle-glyph drawing may share a helper with `Icons.squircleTransportIcon` if
convenient, but that refactor is optional and secondary to keeping the arrow path
single-sourced.

**B3. Rendering + tap via selection binding** (tap gestures inside `Map` are
unreliable; selection binding is the robust idiom):

```swift
@State private var selectedStopID: StopID?

Map(position: $cameraPosition, selection: $selectedStopID) {
    UserAnnotation()
    ForEach(stopsObserver.stops) { stop in
        Annotation(stop.name, coordinate: stop.coordinate) {
            Image(uiImage: application.stopIconFactory.buildSquircleIcon(for: stop))
        }
        .tag(stop.id)
    }
}
.annotationTitles(.hidden)             // keep name for a11y, avoid label clutter
.onChange(of: selectedStopID) { _, id in
    guard let id else { return }
    coordinator.push(.stopDetails(stopID: id))
    selectedStopID = nil               // allow re-tapping the same stop
}
```

**B4. Real stop screen via UIKit bridge — new `StopDetailSheetHost`.** Mirrors
`MoreSheetHost`: wraps `StopViewController(application:stopID:)` in a
`UINavigationController`, with a testable static `makeNavigationController(
application:stopID:)` seam. Register in `AppSheetViewFactory`: the
`.stopDetails(let stopID)` case moves out of `unimplementedView` into
`StopDetailSheetHost(application:stopID:)`.

## Files touched

- `OBAKit/Mapping/MapRegionManager.swift` — region-taking load (`requestStops(in:)`),
  debounced scheduler (`scheduleStopsRequest(in:)`), `deinit` cancel.
- `OBAKit/Mapping/StopIconFactory.swift` — new `buildSquircleIcon(for:)` (squircle
  treatment + reused directional arrow), cached by `(routeType, direction)`.
- `OBAKit/Sheet/Root/MapPanelRootView.swift` — store `application` (for
  `stopIconFactory`) + `mapRegionManager` + `@StateObject stopsObserver` +
  `selectedStopID`; camera observation; stop rendering; selection→push; trim the two
  TODO comments to what's still open.
- `OBAKit/Sheet/Root/MapStopsObserver.swift` *(new)* — delegate→`@Published` bridge.
- `OBAKit/Sheet/Root/StopDetailSheetHost.swift` *(new)* — UIKit stop bridge.
- `OBAKit/Sheet/DI/AppSheetViewFactory.swift` — implement the `.stopDetails` branch.

## Testing

- `OBAKitTests/Application/Mapping/MapRegionManagerTests.swift`:
  `requestStops(in:)` populates `stops` for a stubbed `stops-for-location` response
  (mirrors the existing `requestDataForMapRegion()` priming test).
- New `MapStopsObserver` test: after `await manager.requestStops(in:)`, an observer
  constructed on that manager reflects the manager's `stops`.
- New `StopDetailSheetHost` test: `makeNavigationController(application:stopID:)`
  returns a `UINavigationController` whose root is a `StopViewController` (mirrors
  the `MoreSheetHost` seam-based test).
- `StopIconFactory.buildSquircleIcon(for:)` smoke test: returns a cached (identical)
  instance for two stops sharing the same `(routeType, direction)`, and a distinct
  instance across differing directions.

## Explicit non-goals

- Detent-aware bottom padding (the second TODO in `MapPanelRootView`).
- Bookmark treatment on the map. The squircle icon is bookmark-agnostic, so
  bookmarked stops render like any other stop; the UIKit map's separate `Bookmark`
  annotation type is not replicated.
- The UIKit zoom-out "don't fetch when too far out" gate on the SwiftUI path.
