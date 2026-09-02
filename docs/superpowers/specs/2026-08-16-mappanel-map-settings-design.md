# Map Settings in the MapPanel Experience

**Date:** 2026-08-16
**Status:** Approved design, ready for implementation planning

## Problem

`MapViewController` (the classic UIKit map) presents a Map sheet — `MapSheetView`
plus `MapSheetModel` in `OBAKit/Mapping/Layers/MapSheetView.swift` — reached from
the basemap button in its control stack. The sheet carries five things:

1. Basemap tiles: Standard, Satellite, Hybrid
2. A Points of Interest toggle
3. The Transit layer group
4. The "Other ways to get around" group (Bikes, Scooters) plus a minimum-range picker
5. A Reset button restoring defaults

The button itself carries `mapLayerBadge`, an active-layer count described in its
own doc comment as "the primary discoverability lever for the Map sheet."

The experimental MapPanel experience (`MapPanelRootView`, gated by
`FeatureFlags.useMapPanelExperienceKey`) has none of it. Its map-type button is a
plain two-way toggle between standard and hybrid — satellite is unreachable — and
none of the layer, POI, range-filter, or reset settings exist.

This design brings every setting in that sheet to the MapPanel surface.

## Constraints discovered during exploration

Three facts shape everything below.

**MapPanel is a pure SwiftUI `Map`, not an `MKMapView`.** It shares `MapViewModel`
with the UIKit path and uses `MapRegionManager` only as a *stops data source*
(`scheduleStopsRequest(in:)` / `cancelScheduledStopsRequest()`). The `MKMapView`
that `MapRegionManager` owns still exists in panel mode but is never added to a
view hierarchy, so its `visibleMapRect` is meaningless there.

**The layer registry is empty in panel mode.** `configureMapLayers()` is defined
on `MapViewController` and called from nowhere else, so `mapRegionManager.mapLayers`
is `[]` whenever the panel is the root. Presenting `MapSheetView` as-is today would
render the basemap tiles and the POI toggle above two empty groups.

**Two registered layers cannot render on the panel at all.**
`StopRouteFocusMapLayer` (route lines and live vehicles) and `TripFocusMapLayer`
(the followed trip) draw `MKOverlay` polylines. The SwiftUI `Map` has no
equivalent path today.

## Scope

| Setting | Panel outcome |
| --- | --- |
| Basemap: standard / satellite / hybrid | Ships. `.mapStyle` today collapses satellite into `.hybrid`; fixed. |
| Points of Interest | Ships, via `.mapStyle(.standard(pointsOfInterest:))` |
| Bus stops layer | Ships, gating the `renderStops` `ForEach` |
| Bikes / Scooters | Ships, including clustering and detail sheets |
| Minimum range filter | Ships |
| Reset to defaults | Ships |
| Layer-count badge | Ships, on `MapTypeButton` |
| Route lines & vehicles | Not registered in panel mode; row never appears |
| Followed trip | Not registered in panel mode; row never appears |
| "Plan a trip using this bike" | **Blocked.** See "The trip-planner blocker". |

Rows for the two overlay layers are hidden rather than dimmed, following the rule
already stated in `MapLayer.swift`: "Unsupported layers are hidden entirely — a row
for something that can never load isn't a feature, it's a bug report."

## Design

### 1. `MapRegionManager` — host-agnostic viewport

`forwardViewport(to:)` reads `mapView.visibleMapRect`, and `updateMapLayers()` is
reachable only from `mapView(_:regionDidChangeAnimated:)`. Neither works when the
`MKMapView` is never laid out.

Add stored state and a public entry point:

- `private(set) var currentVisibleMapRect: MKMapRect`, seeded from
  `mapView.visibleMapRect`
- `func mapLayersViewportDidChange(_ rect: MKMapRect)` — stores the rect, then fans
  out to every enabled layer, honouring each layer's `zoomWindow` exactly as
  `updateMapLayers()` does now

`forwardViewport(to:)` reads the stored rect instead of the map view. UIKit calls
the new method from `regionDidChangeAnimated` with `mapView.visibleMapRect`; the
panel calls it from `.onMapCameraChange` with `context.rect`. UIKit behaviour is
unchanged.

### 2. `RentalLayerCoordinator` — map-agnostic

Today the coordinator holds `weak var mapView: MKMapView?` and applies visibility
diffs by adding, removing, and re-assigning `RentalAnnotation` objects on it.

Remove the map view. `syncMapView(with:)` becomes `apply(changes:)`, maintaining:

- `@Published private(set) var visibleRentals: [VehicleRental]`
- `@Published private(set) var showsFuelLabels: Bool`

`userLocation` moves from `mapView?.userLocation.location` to
`application.locationService.currentLocation`. `handle(_ failure:)` gates its
"dim the row" decision on `visibleRentals.isEmpty` rather than the annotation
dictionary.

The invariant currently documented on `syncMapView` — that the tracked set must
equal `RentalVisibility`'s visible-id set, with no early return permitted — carries
over verbatim to `apply(changes:)`, because cache restore still depends on it.

The `MKMapView` half moves to a new `RentalAnnotationSyncer`
(`OBAKit/Mapping/Layers/RentalAnnotationSyncer.swift`): owned by
`MapViewController`, subscribing to `$visibleRentals`, performing the add / remove /
re-assign against `mapRegionManager.mapView`, and answering
`reattachAnnotations()`. One syncer per coordinator — **not** one per layer — so
Bikes and Scooters sharing a coordinator cannot double-add.

### 3. `MapLayerRegistrar` — shared registration

Extract the host-neutral half of `configureMapLayers()` into a new
`MapLayerRegistrar` (`OBAKit/Mapping/Layers/MapLayerRegistrar.swift`):

- registers `StopsMapLayer` when absent
- tears down and rebuilds the rental layers for the current region, gated on
  `region.isBikeshareEnabled` and `region.openTripPlannerGraphQLURL`
- owns the `RentalLayerCoordinator` and applies the persisted
  `rentalRangeFilter` before the first fetch
- conforms to `RegionsServiceDelegate` and registers itself, so both hosts get
  correct rebuilds when the region changes or the regions list refreshes

`MapViewController.configureMapLayers()` keeps only what is genuinely
`MKMapView`-shaped: the region-scoped `ShapeCache` rebuild for
`StopRouteFocusMapLayer` and `TripFocusMapLayer`, and the `actionsDelegate`
assignment on the rental layers. Its existing `RegionsServiceDelegate` conformance
stays for `dismissStopSheetForReplacement()`; the two delegates are independent, so
firing order between them does not matter.

### 4. Panel wiring

A new `MapPanelLayersModel` (`@StateObject` on `MapPanelRootView`) owns a
registrar and publishes `isStopsLayerEnabled`, `showsPointsOfInterest`,
`rentalItems`, `showsFuelLabels`, and `enabledLayerCount`. It refreshes on
`.mapLayerEnabledStateDidChange`, `.mapPointsOfInterestVisibilityDidChange`, and
`.rentalRangeFilterDidChange`.

**Basemap and POI.** Replace
`.mapStyle(mapType == .standard ? .standard(emphasis: .muted) : .hybrid)` — which
silently collapses satellite into hybrid — with a mapping to
`.standard(emphasis:pointsOfInterest:)`, `.imagery`, and
`.hybrid(pointsOfInterest:)`. `.imagery` takes no `pointsOfInterest` argument, which
is correct: imagery carries no labels. The mapping is extracted as a pure function
so it is testable without instantiating a view.

**Bus stops.** Gate the `renderStops` `ForEach` on `isStopsLayerEnabled`. Bookmark
pins stay unconditional, mirroring `displayUniqueStopAnnotations`, where
`stopsToAdd` is gated but bookmarks are not.

**Viewport forwarding.** `.onMapCameraChange` calls
`application.mapRegionManager.mapLayersViewportDidChange(context.rect)`.

**Selection.** `@State private var selectedStopID: Stop.ID?` becomes
`@State private var mapSelection: MapPinSelection?`, where `MapPinSelection` is a
`Hashable` enum over `.stop(Stop.ID)`, `.rental(VehicleRental.ID)`, and
`.rentalCluster(String)`.

### 5. Clustering

SwiftUI `Map` has no clustering API. It de-collides annotation *titles*, not
annotation *views*; `clusteringIdentifier` has no counterpart. The UIKit path gets
clustering entirely from MapKit: `RentalAnnotationView` sets
`clusteringIdentifier = "rentals"`, MapKit collision-tests marker frames, and
`RentalClusterAnnotationView` renders the resulting count.

Two new types in `OBAKit/Mapping/Layers/`:

- **`RentalMapItem`** — `Identifiable` enum, either `.single(VehicleRental)` or
  `.cluster(id:coordinate:members:)`
- **`RentalClustering`** — `nonisolated`, MapKit-view-free:
  `static func items(for: [VehicleRental], span: MKCoordinateSpan, mapSize: CGSize, cellSize: CGFloat = 60) -> [RentalMapItem]`.
  Converts the cell size from points to degrees via `span / mapSize`, buckets by
  cell index, and emits a single for a lone occupant or a cluster at the centroid
  otherwise.

Cluster identity is a hash of the **sorted member IDs**, not the cell index. Cell
indices shift as the viewport origin pans, which would churn SwiftUI's diff on
every camera move; member-set identity is stable exactly as long as membership is,
which is the property both the `ForEach` and the sheet route `id` require.

**This is what removes the need for a density cap.** Marker count is bounded by
occupied cells — screen area divided by cell area, roughly 90 on an iPhone-sized
map — regardless of how many vehicles the viewport holds. `RentalMapLayer` declares
a `densityBudget` of 500; clustering keeps the panel far below it without hiding a
single vehicle.

Fuel labels render on `.single` items only, still gated on the existing
8,000-point window.

**Accepted divergence.** MapKit clusters by view-frame collision and declusters
progressively; a fixed grid pops at cell boundaries, so two vehicles straddling one
stay separate while visually overlapping. The dominant real case — a genuine
pile-up at a single corner — falls in one cell, so this surfaces mainly as slightly
different declustering timing while zooming.

### 6. Sheet routes

Three new `AppSheetRoute` cases, all stacked, `[.medium, .large]`:

| Route | View |
| --- | --- |
| `.mapSettings` | `MapSheetView` |
| `.rentalDetail(rentalID:)` | `RentalDetailView` |
| `.rentalCluster(memberIDs:)` | `RentalClusterListView` |

`.rentalCluster`'s `id` uses the same sorted-member hash as the map item, so the
route and the marker agree on identity.

Both rental routes carry **IDs, not model objects**, and `AppSheetViewFactory`
resolves them through `MapPanelLayersModel`. An open sheet therefore tracks
refreshes: a vehicle that vanishes from the feed drops out of the cluster list
instead of lingering as a stale row.

`MapSheetView` and both rental views are already pure SwiftUI — the UIKit classes
around the latter two are bare `UIHostingController` wrappers — so all three are
reused unchanged apart from the closure change in the next section.
`RentalClusterListView` already presents `RentalDetailView` internally via
`.sheet(item:)`, so tapping a row inside a cluster needs no route of its own.

**Button and cluster changes.** `MapTypeButton` gains a `badgeCount` and pushes
`.mapSettings` on tap, mirroring `MapViewController`, where the basemap button
already opens the sheet rather than toggling. `MapControlsCluster` swaps
`onToggleMapType` for `onOpenMapSettings` and gains `layerBadgeCount`.

**Dependency injection.** `MapSheetModel` needs the panel's `MapViewModel`, which
`MapPanelRootView.init` currently constructs itself. Hoist that construction into
`MapPanelRootController` and inject the instance into both the view and
`AppSheetViewFactory` — the factory is the established DI seam, so nothing new is
introduced. `MapPanelRootView` takes the instance as an `@StateObject(wrappedValue:)`
parameter.

**Fallout.** `MapViewModel.toggleMapType()` loses its last caller once the panel
button opens the sheet; UIKit already routes its button to the sheet. Delete it and
repoint its `MapViewModelTests` coverage at `setMapType`.

### 7. The trip-planner blocker

`RentalDetailView.onPlanTrip` and `RentalClusterListView.onPlanTrip` are
non-optional closures, and the "Plan a trip using this bike" button renders
unconditionally. Make both optional and render the button only when non-nil. The
UIKit path passes its delegate closure exactly as today; the panel passes `nil`.

The deep-link button is unaffected — it routes through `application.open`, not the
trip planner.

**Why it is blocked.** The UIKit action calls
`showTripPlanner(viaPoint:preselectedMode:)`, a `MapViewController` method with no
panel counterpart, and `AppSheetRoute.tripPlanner` currently falls through to
`AppSheetViewFactory.unimplementedView(for:)` — which fires an `assertionFailure`
in DEBUG builds. Wiring the action in panel mode requires a real trip-planner sheet
(SwiftUI, or a UIKit bridge in the shape of `MoreSheetHost`) that accepts a
`viaPoint` and a `preselectedMode`. That is its own piece of work and is explicitly
out of scope here.

## Testing

Swift Testing throughout, `.serialized` suites, matching the conventions in
`OBAKitTests`. Build and test on iPhone 16 / iOS 26.

**Updated**

- `RentalLayerCoordinatorTests` — assert against `visibleRentals` rather than map
  annotations
- `MapViewModelTests` — repoint `toggleMapType` coverage at `setMapType`

**New**

- `RentalAnnotationSyncerTests` — a visibility diff produces the right `MKMapView`
  add / remove / re-assign calls, and `reattachAnnotations()` is idempotent
- `MapLayerRegistrarTests` — `StopsMapLayer` always registered; rental layers
  registered only when the region has `isBikeshareEnabled` and a GraphQL URL; torn
  down and rebuilt on region change; persisted range filter applied before the
  first fetch
- `RentalClusteringTests` — lone vehicles stay `.single`; co-located vehicles
  group; cluster ID stable across a small pan with unchanged membership and
  changed when a member leaves; marker count bounded by viewport cells at extreme
  density
- `MapPanelLayersModelTests` — each of the three notifications flips the matching
  published value; ID-to-model resolution for the two rental routes returns nil for
  a vehicle that has left the feed
- `MapRegionManagerTests` — `mapLayersViewportDidChange` forwards to enabled layers
  and passes nil outside a layer's `zoomWindow`
- `AppSheetRouteTests` — detent configuration and `prefersStacking` for the three
  new cases; `id` stability for `.rentalCluster`
- Map-style mapping — the extracted pure function returns the right `MapStyle` for
  each `MapBaseType` and POI combination

## Implementation phases

Phases 1 through 3 are refactors that leave the UIKit map behaviourally unchanged
and must keep its tests green on their own. Phases 4 and 5 are where the panel
visibly changes.

1. Host-agnostic viewport in `MapRegionManager`
2. Map-agnostic `RentalLayerCoordinator` plus `RentalAnnotationSyncer`
3. `MapLayerRegistrar`, with `MapViewController` delegating to it
4. Panel: `MapPanelLayersModel`, basemap and POI, stops gate, `.mapSettings` route,
   badge on `MapTypeButton`
5. Panel: `RentalClustering`, rental annotations, `.rentalDetail` and
   `.rentalCluster` routes, optional `onPlanTrip`

## Out of scope

- A trip-planner sheet for the panel (see "The trip-planner blocker")
- Route lines, live vehicles, and followed-trip overlays on the SwiftUI map
- Dimming rentals while a stop sheet is open — the panel counterpart of
  `recedesBehindStopSheet`. Worth doing later; not required for settings parity.
- The Settings screen, which mirrors some of the same UserDefaults keys but does
  not own them
