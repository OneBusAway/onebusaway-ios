# Map Stop Selection — Route Lines & Live Vehicles — Design

**Date:** 2026-07-31
**Branch:** `route-projection`
**Deployment target:** iOS 18.0 (`Apps/Shared/app_shared.yml`)
**Source of truth for visuals/behavior:** Claude Design project "OBA iOS" — `OBA Map Stop Selection.html` plus components `map-stop-select.jsx`, `trip-focus.jsx`, `stop-head-options.jsx`, `oba-dep-core.jsx`, and `Map Stop Selection - Implementation Brief.md`.
**Predecessor spec:** `2026-07-10-stop-page-rethink-design.md` (built `StopPageView` and `StopViewModel`, which this spec consumes).
**Review status:** Four independent verification passes against source; findings incorporated. Items marked **[verified]** were checked empirically or against a working precedent rather than assumed.

## Summary

When a rider taps a stop on the map and the redesigned Stop page comes up as a
half-detent sheet, the map behind it starts showing **the routes that serve that
stop and the live vehicles arriving on them**. Route shapes draw as
white-cased, route-colored polylines; each arriving bus or train with a real-time
position draws as a vehicle marker with a heading arrow. Tapping a route chip in
the stop header, or tapping a vehicle marker, focuses that route: its line
thickens, every other line dims, and the vehicle gets a callout with a
**Follow this trip** action.

Nothing changes on any other surface. The feature attaches to exactly one
presentation path — the map's `StopSheetPresenter` sheet — and every other way of
reaching a stop screen is untouched.

## Decisions made (with rationale)

| Decision | Choice | Why |
|---|---|---|
| Target surface | UIKit `MapViewController` / `MapRegionManager`'s `MKMapView`, sheet via `StopSheetPresenter` | Gated by `OBAUseNewStopPage`, which defaults **on**, so this is what riders see. `StopSheetLayout` already has `.full`/`.half`/`.tip`, so the map is already visible behind the sheet. `MapRegionManager` already has an overlay pipeline and a layer registry. The SwiftUI `MapPanelRootView` path is behind a second, off-by-default flag, has no toolbar chrome, uses a `.large`-only detent that covers the map, and draws no overlays. |
| Vehicle positions | Reuse `tripStatus` already on each `ArrivalDeparture` | Zero new network calls. Each arrival carries `position`/`lastKnownLocation`, `orientation`, `vehicleId`, `occupancyStatus`, `scheduleDeviation`, and `lastUpdateTime` — everything the marker and callout need. |
| Route polylines | Per-route trip shape: soonest arrival's `trip.shapeID` → `GET shape/{id}` | `Trip.shapeID` is already on the REST model and `ArrivalDeparture.trip` is resolved from `references`, so the ID is free. Yields **one** line per route — the path the rider will ride — rather than `stops-for-route`'s bundle of every pattern and direction overlapping. |
| Rendering structure | A `MapLayer` conformer, `StopRouteFocusMapLayer` | `MapLayer`'s doc comment (`MapLayer.swift:60-64`) names this work: "rentals are the first conformer; route shapes, live vehicles, and GTFS-Flex zones are expected to follow." |
| Vehicle marker | Extend the existing `PulsingVehicleAnnotationView` | Already handles the heading arrow — including the OBA-vs-CoreGraphics sign flip at `:88` — plus realtime pulsing and the gray schedule-only state. It is **already registered** on `MapRegionManager`'s map view (`:254`). |
| Vehicle tap | Callout with **Follow this trip** → existing `TripViewController` | No new trip UI. The push already works inside the sheet's nav stack. |
| Chip membership | **All routes serving the stop, alphabetical — unchanged from today** | Keeps the sheet and the pushed page showing an identical header, and preserves "which routes serve this stop" as a complete answer. Deliberate deviation from the brief's "routes-arriving order"; see *Deviations*. |
| Gating mechanism | Attachment, not a conditional | The map hands the page a `StopMapFocus`. Surfaces that don't hand one over cannot render lines — there is no branch to get wrong. |

## Architecture

### Entry point and gating

`MapViewController.present(stopController:deselecting:)` (`MapViewController.swift:774`)
guards on `stopController is StopPageViewController`. **[verified]** `stopSheet.present`
appears exactly once in the codebase (`:791`), inside that method, and all four
entry paths funnel through it — annotation tap (`:1139`, `:1182`), search result
(`:1226`), panel select (`:1076`), context-menu commit (`:1371`). There is no
bypass.

Consequences:

- Legacy `StopViewController` takes the `guard` and never reaches attachment.
- `StopPageViewController` reached by a *push* — `Router.swift:89`/`:94`, `BookmarksViewController.swift:437`, `RecentStopsViewController.swift:183`, `MapFloatingPanelController.swift:258`/`:355`, `TripFloatingPanelController.swift:362`, `StopDetailSheetHost.swift:44` — never has `attach(focus:)` called. Its chips render exactly as today and are inert.
- **[verified]** The context-menu peek controller (`:1351`) is `enterPreviewMode()`'d, so `showsBottomToolbar` is false and `StopPageView` renders `StopPageHeaderView`, not `StopPageSheetHeaderView`. The sheet chips never appear during a peek, so there are no dead-interactive chips.
- No new feature flag.

### `StopMapFocus`

The single channel between sheet and map. Owned by `MapViewController`, one per
presentation. **Always non-nil** — an unattached page gets an inert instance
rather than an Optional, which sidesteps `@ObservedObject`'s inability to wrap an
Optional.

```swift
@MainActor final class StopMapFocus: ObservableObject {
    struct FocusRoute: Identifiable, Equatable {
        let id: RouteID
        let shortName: String
        let color: UIColor
        let hasLiveVehicle: Bool
    }

    /// Routes with a drawn line, keyed by RouteID. Chips look themselves up
    /// here for decoration; a chip with no match renders plain and inert.
    @Published private(set) var routes: [FocusRoute] = []

    @Published var focusedRouteID: RouteID?

    /// The layer's one write path. Also drops `focusedRouteID` when the focused
    /// route leaves the list, so focus can't dangle.
    func apply(routes: [FocusRoute]) { … }
}
```

### SwiftUI propagation

**[verified]** A plain `let` gives zero observation: reassigning
`UIHostingController.rootView` evaluates the body once, and later `@Published`
mutations do nothing. Something must declare the observation. The precedent is in
this very subtree — `StopPageRootView.viewModel` is a plain `let`
(`StopPageView.swift:76`) and works only because `StopPageView` declares
`@ObservedObject var viewModel` (`:111`).

```
StopPageViewController      private var mapFocus = StopMapFocus()   // stored on the VC
StopPageRootView            let mapFocus: StopMapFocus              // plain pass-through
StopPageView                let mapFocus: StopMapFocus              // plain pass-through
StopPageSheetHeaderView     @ObservedObject var mapFocus            // the only observer
```

**The observation must not go on `StopPageView`.** Its doc comment (`:107-109`)
records that it is deliberately the only view observing `StopViewModel`, so the
VM's frequent churn re-evaluates one shallow body. Observing focus there would
re-evaluate the whole list on every route update and every chip tap. The header's
own doc comment (`StopPageSheetHeaderView.swift:47`, "A plain-value view — it
never touches `StopViewModel`") needs amending to reflect that it now observes
`StopMapFocus` — and only that.

`attach(focus:)` **stores `mapFocus` on the view controller and re-threads it
through `installRootView()`**, exactly as `isAtTip` does (`:124-128`, `:110-122`).
Writing `rootView.mapFocus` alone would be silently wiped by any later
`installRootView()` (`:555`, from `exitPreviewMode`). Today's call ordering
happens to save it, which is precisely why it should not be relied on.

### `StopRouteFocusMapLayer`

New file in `OBAKit/Mapping/Layers/`. Conforms to `MapLayer`:

- `id = "stopRoutes"`, `group = .transit`, `isEnabledByDefault = true`.
- `refreshPolicy = .static` — selection-driven, not viewport-driven. `viewportDidChange(_:)` is a no-op.
- No zoom gate. A trip shape spans far more than a stop-density viewport.
- `isClusterable = false`, `availability = .available`.
- Implements `mapAnnotationsWereCleared()` (see below).

**[verified]** The protocol change is safe: conformers are exactly three, all
internal (`StopsMapLayer.swift:20`, `RentalMapLayer.swift:18`, and a test fake),
with **zero conformers in `Apps/`** — no white-label app conforms today.

### Changes to shared map infrastructure

**1. `MapLayer` gains overlay hooks**, with default implementations so existing
conformers need no edits:

```swift
func renderer(for overlay: MKOverlay, in mapView: MKMapView) -> MKOverlayRenderer?
func mapOverlaysWereCleared()
```

**2. `MapRegionManager.mapView(_:rendererFor:)` stops crashing.** It currently
ends in a bare `fatalError()` (`MapRegionManager.swift:1040`). It becomes: ask
each registered layer → fall back to the existing brand-colored polyline renderer
→ otherwise `Logger.error` and return a plain `MKOverlayRenderer(overlay:)`.

Two ordering constraints, both load-bearing:

- **Iterate `mapLayers` unfiltered**, mirroring the annotation path at `:970`, which deliberately consults every layer with no enabled check. `isMapLayerEnabled(id:)` (`:301`) is a raw `UserDefaults.bool` and is the wrong gate: redundant when `deactivate()` did its job, harmful when it didn't.
- **The layer loop must run before the `as? MKPolyline` branch at `:1031`.** `RouteShapeOverlay` *is* an `MKPolyline`, so a loop placed after it is unreachable and every route line renders as a 3 pt brand-colored stroke. This is the single easiest way to get this feature subtly wrong.

**3. Wholesale-removal sites.** `cancelSearch()` (`:647`) calls both
`removeAllAnnotations()` (`:649`) and `removeOverlays(mapView.overlays)` (`:650`);
`displaySearchResult(stopsForRoute:)` (`:725`) calls `removeAllAnnotations()`
(`:726`).

- The annotation half **already has** a recovery path — `notifyMapLayersAnnotationsCleared()` (`:653-659`) → `MapLayer.mapAnnotationsWereCleared()` (`MapLayer.swift:125`). The layer must implement it to re-add markers.
- The overlay half has no analog, hence `mapOverlaysWereCleared()`, called from `cancelSearch()`.

Pre-existing bug in the blast radius:
`MKMapView.removeAllAnnotations(excludeUserLocation:)`
(`OBAKit/Extensions/MapKitExtensions.swift:263-266`) has **inverted** logic — with
its default `true` it removes the user-location annotation. Every caller uses the
default. Fix while here.

**4. `Trip.shapeID` decode fragility.** `Trip.swift:47` declares it non-optional
and `:88` decodes with plain `container.decode`. `References.swift:47` decodes
trips as an array, so **one** trip with a missing or null `shapeId` throws out of
`References.init` and fails the entire arrivals response — a dead region, not a
missing line. Nothing catches it. Change to `decodeIfPresent` +
`String.nilifyBlankValue` → `String?`, matching the adjacent
`routeShortName`/`shortName`/`timeZone` fields (`:85-88`).

**[verified]** Empty-string `shapeId` is separately reachable — `shapeID` is the
one field on those lines *not* run through `nilifyBlankValue`, and OBA
demonstrably emits `""` for such fields. **[verified]** A scan of all test
fixtures found 305 trips, none missing, empty, or null — so neither path has any
existing coverage, and both need new fixtures.

### Data flow

```
StopViewModel.$stopArrivals ─┐
        $isListFiltered ─────┼─(Combine, ~30 s effective)──▶ MapViewController
        $stopPreferences ────┘                                      │
                                              update(departures:)   │
                                                                    ▼
                                                     StopRouteFocusMapLayer
                                                       │                │
                                           overlays + annotations   routes[]
                                                       │                ▼
                                                    MKMapView       StopMapFocus
                                                                        │
                                                                 @ObservedObject
                                                                        ▼
                                                       StopPageSheetHeaderView chips
```

**[verified] The Combine subscription compiles under Swift 6.**
`StopViewController.bindArrivalsSink()` (`OBAKit/Stops/StopViewController.swift:1260-1272`)
already does exactly `viewModel.$stopArrivals.sink { [weak self] … }.store(in: &cancellables)`
and ships today under `SWIFT_STRICT_CONCURRENCY: complete` with
`SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` and warnings-as-errors
(`Apps/Shared/app_shared.yml:20-29`). Combine's `sink(receiveValue:)` takes a
plain `@escaping (Output) -> Void`, **not** `@Sendable`, so under MainActor
default isolation the closure inherits `@MainActor` and no boundary is crossed.
`MapViewController` already imports Combine (`:14`) and owns `cancellables`
(`:68`). One caveat: `@Published` fires in `willSet`, so the closure must use its
parameter and **never re-read `viewModel.stopArrivals`**.

**Cadence.** The refresh timer is 15 s (`StopViewModel.swift:174`, `:604`) but
each tick is gated by a 30 s `shouldRefresh` threshold (`:619-622`), so arrivals
emissions land roughly every 30 s. Vehicles advance at that rate; no new timer.

### Deriving the model

**The map must use the identical filter chain as the list**, or it will show
lines and vehicles for departures the rider cannot see. `StopPageView.filteredDepartures`
(`StopPageView.swift:179-183`) is:

```swift
let visible = viewModel.isListFiltered ? all.filter(preferences: viewModel.stopPreferences) : all
return visible.filteringTerminalDuplicates()
```

Two things this spec gets from that and must not simplify:

- `isListFiltered` is **rider-toggleable** (`StopViewModel.swift:107`) and force-cleared by `disableFilterIfAllRoutesHidden()` (`:577-581`). Filtering unconditionally would hide lines for routes the list is currently showing. Hence the layer observes `$isListFiltered` and `$stopPreferences`, not just `$stopArrivals`.
- `filteringTerminalDuplicates()` (`ArrivalDeparture+Deduplication.swift:80`) affects first-appearance ordering and `hasLiveVehicle` bookkeeping.

**[verified] `filteredDepartures` is NOT sorted.** Sorting happens downstream in
`StopPageListBuilder` (`:43`, `:75`); at that call site the order is whatever the
server returned. **The layer sorts by `arrivalDepartureMinutes` itself**, and
excludes `temporalState == .past` — a departed bus should not be drawn
approaching the stop.

From that sorted, filtered list:

- **Routes** — deduplicated by `routeID`, capped at **6** by soonest arrival.
- **Polyline per route** — the soonest arrival supplies `trip.shapeID`. Fetch via `RESTAPIService.getShape(id:)` (`RESTAPIService+Get.swift:260`; `public nonisolated async throws`, so cancellable and safe off the main actor).

  **Build `RouteShapeOverlay` from coordinates directly.** `PolylineEntity.polyline`
  (`:25-28`) and `Polyline.mkPolyline` (`:63-67`) both hardcode a plain `MKPolyline`
  return, which cannot be downcast. Go through `Polyline(encodedPolyline:).coordinates`
  — the pattern at `TripViewModel.swift:159-160` — and construct
  `RouteShapeOverlay(coordinates:count:)`.

  **Pin the shape per route for the life of the presentation.** The soonest
  arrival rolls over as buses depart, so re-resolving `shapeID` each tick would
  miss the cache, refetch, and visibly redraw the line. Memoize `routeID → shapeID`;
  re-resolve only when that route leaves the arrival set.

  **Cap the fan-out.** A downtown stop routinely serves 10–20+ routes over the
  ~35-minute window. The 6-route cap plus a bounded `TaskGroup` keeps this to a
  handful of concurrent `GET shape/{id}` calls. Cancel in flight on dismiss or swap.

- **Vehicles** — every filtered arrival whose `tripStatus` yields a usable coordinate, deduplicated by `vehicleID ?? tripID`.

  Coordinate resolution needs its own implementation: the existing
  `VehicleAnnotation.updateAnnotation()` (`VehicleAnnotation.swift:24-27`) reads
  **only** `lastKnownLocation` and falls back to a literal `(0, 0)` — it
  manufactures exactly the null-island coordinate we must reject. Prefer
  `position`, fall back to `lastKnownLocation`, and produce **no annotation** when
  neither is usable.

- **`hasLiveVehicle`** per route — true iff that route contributed ≥ 1 vehicle. This lights the chip's green dot, so the dot means "there is something on the map to point at."

**Shape cache** lives on `StopRouteFocusMapLayer`, which registers once with
`MapRegionManager` (`:273-287`) and outlives any single presentation. It must be
**bounded**, invalidated on region change (shape IDs are region-scoped), and it
must coalesce concurrent requests for the same shape ID — a stop whose routes
share a trip pattern otherwise fetches the same line several times over.

`NSCache` is the obvious reach and the wrong one here: its eviction is opaque and
untestable, and it has nothing to say about the in-flight coalescing, which is
the harder half. Use an `actor` owning a dictionary plus an insertion-order list
for bounded eviction, and a small reference-typed box per in-flight `Task` so a
resolving fetch can tell whether the entry it installed is still the installed
one (`Task` is a struct; `===` cannot compare two `Task` values). A generation
counter, bumped on invalidation, drops a response that resolves after the cache
was cleared.

Late responses are dropped on *two* levels, and they answer different questions:
the cache's generation counter decides whether a response may be *stored*, while
a presentation token on the layer decides whether it may be *drawn*. A sheet can
close without the region changing, so neither subsumes the other.

There is no existing shape or polyline cache in the app to reuse.

## Rendering

### Route lines

Two overlays per route, casing first:

- **Casing**: white, `lineWidth = core + 4`, `lineCap = .round`.
- **Core**: `route.color`, `lineWidth = 5` (`7` focused), `lineCap = .round`.
- When any route is focused, others render at `alpha 0.32`.

The casing is what makes a route-colored line legible over the basemap. Overlay
count is 2 × drawn routes, bounded at 12 by the 6-route cap.

`RouteShapeOverlay: MKPolyline` carries `routeID` and `isCasing`. **[verified]**
Compiled and run against real MapKit: the factory-imported initializers allocate
the subclass, the runtime class really is `RouteShapeOverlay`, stored properties
survive, `MKPolylineRenderer(polyline:)` preserves the dynamic type, and `as?` off
an `MKOverlay` succeeds. Apple's own `MKGeodesicPolyline` is an `MKPolyline`
subclass — the confirming precedent. No wrapper type or side table needed.

### Vehicle markers

`StopVehicleAnnotation` **must subclass `VehicleAnnotation`**
(`VehicleAnnotation.swift:12`). `PulsingVehicleAnnotationView`'s `annotation`
`didSet` (`:56-65`) guards on `as? VehicleAnnotation` and returns silently
otherwise — a non-conforming annotation yields a marker with no heading arrow, no
route icon, and no realtime state, with no error anywhere.

**[verified]** The view is already registered on `MapRegionManager`'s map view
(`:254`) and needs no `reuseIdentifier(for:)` case, because `viewFor` asks layers
first at `:970` — exactly the hook `annotationView(for:in:)` fills.

Three fixes to the marker, two of them pre-existing bugs:

1. **Taps are impossible today.** `isUserInteractionEnabled = false` (`:29`) makes `hitTest` return nil, so the selection gesture never lands and the `canShowCallout = true` above it is inert. `TripViewController` only ever displays these markers, never selects them, which is why nobody has noticed. Expose interactivity as a settable property — flipping it globally would make the trip screen's markers selectable and show a title-only callout there.
2. **Route-color tinting doesn't take effect when assigned.** `realTimeAnnotationColor` (`:101`) is a plain stored var with no `didSet`, and the only write to `annotationColor` is inside `isRealTime`'s `didSet` (`:43-54`). Because `dequeueReusableAnnotationView` assigns the annotation first, that chain runs *before* the caller sets the color — so the tint lands one status-apply late, on a recycled view carrying the previous route's color. `TripViewController.swift:419-423` has this bug today. Give `realTimeAnnotationColor` a `didSet` re-applying `annotationColor` and the heading tint (`:85`).
3. **Focused state** — raised `zPriority`, emphasized ring.

### Vehicle callout

`detailCalloutAccessoryView` carrying route badge, headsign, `Vehicle NNNN`, the
countdown in status color, the deviation label, "position updated Ns ago" from
`lastUpdateTime`, and a **Follow this trip** row that pushes the existing
`TripViewController` via `ViewRouter` into the sheet's navigation stack — the
same path the trip panel's "View full trip" takes today, which works because
`StopSheetPresenter` wraps the page in a `UINavigationController` for exactly
this reason.

### Focus behavior

- Tapping a chip focuses the route of its first live vehicle: line thickens, others dim to `0.32`, other chips dim to 45%, the focused chip gets tinted fill and a 1 pt border in the route color, and the vehicle's callout opens.
- Tapping the same chip again, or the focused marker, clears focus.
- A chip for a route with **no live vehicle**, or no drawn line at all, is a **no-op** — no error, no camera move, no visual change.
- **The arrivals list is never filtered by focus.** Focus is map-side emphasis only.
- **Focus persists across detent changes.** At `.tip` the header hides the chip row entirely (`StopPageSheetHeaderView.swift:122` gates on `!isCollapsed`), so focus would otherwise become unclearable; the focused marker remains tappable and is the escape hatch.
- **Rendering persists at every detent**, including `.full` where the map is covered. Riders drag between detents constantly; tearing down and refetching on each transition would be both slower and visibly janky.

### Camera

On stop selection, recenter so the stop sits above the `.half` detent.
**[verified]** There is no recentering today: `present(stopController:)`
(`:774-806`) contains no camera call, and `mapView(_:didSelect:)` (`:1113-1151`)
only calls `setCenter` for a `UserDroppedPin` (`:1144`). MapKit's automatic
callout-pan doesn't cover for it either — `StopAnnotationView.updateCalloutVisibility()`
(`:215-218`) sets `canShowCallout = false` whenever `showsStopAnnotationCallouts`
is false, and that is `!FeatureFlags.isNewStopPageEnabled(...)`
(`MapRegionManager.swift:784-786`), so callouts are off on precisely this path.
Under VoiceOver, or with the flag off, callouts return and MapKit pans on its own
— the recenter must not fight that.

**Derive the inset from a layout constant, not the live surface.** The panel is
unreachable from `MapViewController`: `stopSheet` is `private lazy` (`:810`) and
`StopSheetPresenter.panel` is `private` (`:33`), and that presenter's doc comment
(`:23-25`) says it is "deliberately ignorant of the map." A live frame read would
also be wrong on timing — `addPanel(toParent:animated: true)` (`:120`) slides in
from `.hidden`, so the surface frame isn't final when `present(stopController:)`
runs. Expose a `nonisolated static` half-detent inset on `StopSheetLayout` (which
today overrides only `.tip` at `:369-373`) and use that.

Focus changes do **not** move the camera.

### Presentation lifecycle and the stop-to-stop swap

`StopSheetPresenter.present` calls `tearDown(animated:restoringTabBar:)` as its
**first statement** (`:63`), which deliberately fires the *outgoing*
presentation's dismiss handler (`:40-44`). So the ordering in
`present(stopController:)` is load-bearing:

1. Call `stopSheet.present(...)` — this tears down the outgoing sheet and runs its handler, which deactivates the layer and releases the old `StopMapFocus`.
2. **Then** build the new `StopMapFocus`, attach it, and activate the layer.

Building and activating before step 1 would have the outgoing handler deactivate
the layer that was just activated — a blank map on every stop-to-stop tap.

### Route chips in the header

**Membership and order are unchanged from today**: `stop.routes`, alphabetical by
short name, empty short names dropped, not filtered by `hiddenRoutes`
(`StopPageSheetHeaderView.swift:70-77`). What changes is that each chip looks
itself up in `StopMapFocus.routes` and, when found, gains a color bar, a green
live dot, focused fill + 1 pt border, 45% dim when another route is focused, and a
tap target. A chip with no match renders exactly as it does today and is inert.

Two mechanical consequences:

- `routeBadgeNames` changes from `[String]` to a small chip value carrying the route's ID(s), so a tap maps to a route. Today's dedupe is **by short name**, which collapses two `RouteID`s sharing a short name into one badge; preserve that visual behavior by having the chip carry the *set* of route IDs sharing its short name and focusing whichever has a live vehicle.
- The VoiceOver label at `:201` (`Formatters.formattedRoutes(stop.routes)`) keeps describing the same set the chips show, because the set is unchanged. Had we adopted the arrivals-derived list, it would have drifted.

**[verified] Chips cannot become `Button`s.** `FlowLayout` sizes subviews with
`.unspecified` (`StopPageHeaderView.swift:298`, `:314`, `:320`), and a
load-bearing comment at `StopPageSheetHeaderView.swift:123-126` records that a
`Button` answers that with a greedy height — "that is what stretched the walk pill
down the whole sheet." Use `.contentShape(Rectangle())` + `.onTapGesture` +
`.accessibilityAddTraits(.isButton)`.

## Deliberate deviations from the prototype

- **Chip order stays alphabetical**, not routes-arriving order. The brief asks for arriving order, but that would make the sheet's header disagree with the pushed page's for the same stop, and would silently drop routes with nothing in the arrival window from a control whose stated purpose is answering "which routes serve this stop."
- **No route-stop ring dots** along the lines. Sourcing them means a second per-route fetch (`stops-for-route`) for decoration.
- **No basemap dimming** (`dimBasemap` in the prototype). Cheap via `MKStandardMapConfiguration.emphasisStyle = .muted`, but a global map-appearance change with its own dark-mode and map-type questions.
- **No direction-flow animation** (`animateFlow`, off by default in the prototype).
- **No `picker` header variant.** The brief itself says ship `wrap`.

## Error and empty states

- Shape fetch fails, or `shapeID` is absent/empty → that route draws no line. Its vehicles still render and its chip still works. Not surfaced as an error.
- Arrival has no usable `tripStatus` coordinate → no marker; the arrival stays in the list, its chip dot stays off.
- Stop has no arrivals, or all are filtered → no lines, no vehicles; chips render plain. The map looks as it does today.
- Arrivals refresh fails → last-good overlays and markers stay, matching `StopViewModel`'s existing keep-last-good behavior.
- More than 6 routes arriving → the 6 soonest draw. Chips for the rest render plain and inert, which is the same treatment as a route with no live vehicle.

## Accessibility

- Vehicle markers carry a label naming route, headsign, countdown, and adherence — never color alone.
- Chips announce focused state and whether the route has live tracking; the green dot is always paired with that text. `.accessibilityAddTraits(.isButton)` on tappable chips, omitted on inert ones so VoiceOver doesn't promise an action that doesn't exist.
- Line color is never the only differentiator — the chip pairs color with the route short name, and the callout names the route.
- Reduce Motion: vehicle pulsing already respects the existing non-realtime path; the line draw-on animation is skipped.

## Testing

Unit tests in `OBAKitTests` against pure logic, per repo convention:

- **Filter parity**: the map model's departure list is byte-identical to `StopPageView.filteredDepartures` for the same inputs, including `isListFiltered` off and terminal-duplicate cases.
- **Sorting**: the layer sorts by `arrivalDepartureMinutes` (the input is *not* pre-sorted) and excludes `.past`.
- **Route derivation**: dedupe by `routeID`; cap at 6 by soonest arrival.
- **`hasLiveVehicle`**: true iff ≥ 1 filtered arrival for that route yields a coordinate.
- **Vehicle derivation**: dedupe by `vehicleID ?? tripID`; `lastKnownLocation` used when `position` is absent; neither present → no annotation, and specifically **not** a `(0, 0)` marker.
- **Shape cache**: one fetch per distinct shape ID; two routes sharing a shape fetch once; a late response for a dismissed presentation is dropped.
- **Shape pinning**: when the soonest arrival rolls to a trip with a different `shapeID`, the pin holds and no refetch occurs; released only when the route leaves the set.
- **Focus semantics**: same route twice clears; a route with no live vehicle no-ops; marker tap and chip tap converge on one value; focus clears when its route leaves the set; focus survives a detent change.
- **Renderer dispatch** (two regressions): an unrecognized overlay yields a renderer rather than trapping — the `fatalError()` at `MapRegionManager.swift:1040` must not return; **and** a `RouteShapeOverlay` reaches its layer's renderer rather than the generic `as? MKPolyline` branch at `:1031`.
- **Clearing recovery**: `cancelSearch()` and `displaySearchResult(_:)` leave the layer's content on the map or restore it via `mapAnnotationsWereCleared()` / `mapOverlaysWereCleared()`.
- **Marker plumbing**: a `StopVehicleAnnotation` gets heading and route color applied on **first** display (regression against the late-apply bug).
- **`Trip` decode robustness**: new fixtures for a trip with missing, null, and empty `shapeId` — none of which may fail the enclosing `References` decode. No such fixture exists today (305 trips scanned, all well-formed).
- **Chip mapping**: two routes sharing a short name yield one chip carrying both IDs; a chip whose route has no drawn line is inert and carries no button trait.
- **Attachment gating**: a pushed `StopPageViewController` has an inert focus object and non-interactive chips. Existing `StopSheetPresenterTests`, `StopPagePresentationTests`, `StopPageSheetHeaderLayoutTests`, and `StopDetailSheetHostTests` keep passing.

Verification: `scripts/generate_project OneBusAway`, then build-for-testing plus
`OBAKitTests` on the iPhone 17 simulator, plus a manual simulator walkthrough
against a live region — tap a stop, confirm lines and vehicles appear, tap a
chip, tap a marker, follow a trip, swap directly to another stop, drag through all
three detents, dismiss, and confirm the map is clean.

## Out of scope

Each gets its own spec:

- **Stop-sheet header compaction** — folding the Chronological/By-route control into the list header as compact `Time`/`Route` segments, and moving `Past · N` there.
- **Trip push view** — tapping an arrival cell pushing a SwiftUI trip page and switching the map to whole-trip focus with spent/ahead treatment and a terminal chip.
- Route-stop ring dots, basemap dimming, direction-flow animation, the `picker` header variant.
- The SwiftUI `MapPanelRootView` / `StopDetailSheetHost` surface. It presents the same `StopPageViewController` as a second sheet-over-map surface, but behind an off-by-default flag with a `.large`-only detent; it gets no focus object and is unchanged.
- The legacy `StopViewController` and the `Vehicles` screen.
