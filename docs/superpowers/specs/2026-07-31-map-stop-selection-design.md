# Map Stop Selection — Route Lines & Live Vehicles — Design

**Date:** 2026-07-31
**Branch:** `route-projection`
**Deployment target:** iOS 18.0 (`Apps/Shared/app_shared.yml`)
**Source of truth for visuals/behavior:** Claude Design project "OBA iOS" — `OBA Map Stop Selection.html` plus components `map-stop-select.jsx`, `trip-focus.jsx`, `stop-head-options.jsx`, `oba-dep-core.jsx`, and `Map Stop Selection - Implementation Brief.md`.
**Predecessor spec:** `2026-07-10-stop-page-rethink-design.md` (built `StopPageView` and `StopViewModel`, which this spec consumes without modifying).

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
reaching a stop screen (the legacy `StopViewController`, and `StopPageViewController`
reached by a push from Bookmarks, Recents, nearby-stops, or a transfer context)
is untouched.

## Decisions made (with rationale)

| Decision | Choice | Why |
|---|---|---|
| Target surface | UIKit `MapViewController` / `MapRegionManager`'s `MKMapView`, stop sheet via `StopSheetPresenter` | Gated by `OBAUseNewStopPage`, which defaults **on**, so this is what riders actually see. Its `StopSheetLayout` already has `.full`/`.half`/`.tip` detents, so the map is already visible behind the sheet. `MapRegionManager` already has an overlay pipeline and a layer registry. The SwiftUI `MapPanelRootView` path is behind a second, off-by-default flag, has no toolbar chrome, uses a `.large`-only detent that covers the map, and draws no overlays today. |
| Vehicle positions | Reuse `tripStatus` already on each `ArrivalDeparture` | Zero new network calls. The stop already fetches arrivals every 15 s, and each carries `position`/`lastKnownLocation`, `orientation`, `vehicleId`, `occupancyStatus`, `scheduleDeviation`, and `lastUpdateTime` — everything the marker and the callout need. It also makes the chip's live dot mean exactly "this route has an arrival with a live position," which is the brief's definition. |
| Route polylines | Per-route trip shape: soonest arrival's `trip.shapeID` → `GET shape/{id}` | `Trip.shapeID` is already on the REST model and `ArrivalDeparture.trip` is resolved from `references`, so the ID is free. Yields **one** line per route — the path the rider will actually ride — rather than `stops-for-route`'s bundle of every pattern and direction overlapping each other. Same shape the future trip-focus view will need. |
| Rendering structure | A `MapLayer` conformer, `StopRouteFocusMapLayer` | `MapLayer`'s own doc comment names this work: "rentals are the first conformer; route shapes, live vehicles, and GTFS-Flex zones are expected to follow." Reuses registration, `activate`/`deactivate`, annotation-view dispatch, and the Map-sheet enable/disable persistence. |
| Vehicle marker | Extend the existing `PulsingVehicleAnnotationView` | It already handles the heading arrow — including the OBA-vs-CoreGraphics orientation sign flip, which has a load-bearing comment at `PulsingVehicleAnnotationView.swift:88` — plus realtime pulsing and the gray schedule-only state. Building a third vehicle marker (after the UIKit trip screen's and the SwiftUI Vehicles screen's) would be the wrong direction. |
| Vehicle tap | Callout with **Follow this trip** → existing `TripViewController` | No new trip UI. The push already works inside the sheet's nav stack — it's the same path the trip panel's "View full trip" takes today. A callout with no action reads as a dead end. |
| Gating mechanism | Attachment, not a conditional | The map hands the page a `StopMapFocus` object. Surfaces that don't hand one over cannot render lines — there is no branch to get wrong. |

## Architecture

### Entry point and gating

`MapViewController.present(stopController:deselecting:)` (`OBAKit/Mapping/MapViewController.swift:773`)
already branches on `stopController is StopPageViewController` to choose sheet-vs-push.
That single existing branch is the switch for this whole feature. Inside it, and
only inside it, the controller:

1. Creates a `StopMapFocus`.
2. Calls `stopPageVC.attach(focus:)`.
3. Activates `StopRouteFocusMapLayer` with that focus object.
4. Subscribes to the page's `StopViewModel.$stopArrivals`.

Consequences, which are the point:

- Legacy `StopViewController` takes the `guard` at the top of that method and never reaches step 1.
- `StopPageViewController` reached by a *push* — `Router.navigateTo(stop:)`/`(stopID:)`, Bookmarks, Recents, `MapFloatingPanelController`, `TripFloatingPanelController` — never has `attach(focus:)` called, so its `focus` stays nil, its route chips render exactly as they do today (non-interactive), and no map state exists.
- No new feature flag. `OBAUseNewStopPage` (default on) already gates which controller `makeStopController` returns, and the branch keys off the returned controller rather than re-reading the flag — deliberately, per the comment at `MapViewController.swift:765-772`.

### `StopMapFocus`

The single channel between the sheet and the map. Owned by `MapViewController`,
one per presentation, released when the sheet is dismissed.

```swift
@MainActor final class StopMapFocus: ObservableObject {
    struct FocusRoute: Identifiable, Equatable {
        let id: RouteID
        let shortName: String
        let color: UIColor
        let hasLiveVehicle: Bool
    }

    /// Routes serving this stop, in routes-arriving order (first appearance in
    /// the time-sorted, filtered departure list) — not alphabetical. Written
    /// only by the layer, via `apply(routes:)`.
    @Published private(set) var routes: [FocusRoute] = []

    /// Written by chip taps and by vehicle-marker taps alike, so the two can
    /// never disagree about what is focused.
    @Published var focusedRouteID: RouteID?

    /// The layer's one write path. Also drops `focusedRouteID` when the focused
    /// route leaves the list (its last trip departed), so focus can't dangle.
    func apply(routes: [FocusRoute]) { … }
}
```

`StopPageViewController` gains `attach(focus:)`, which sets `rootView.mapFocus` —
the same shape as the existing `setAtTip(_:)` (`StopPageViewController.swift:133-137`),
so `Router.makeStopController` keeps its current signature and pushed
presentations are entirely unaffected.

### `StopRouteFocusMapLayer`

New file in `OBAKit/Mapping/Layers/`. Conforms to `MapLayer`:

- `id = "stopRoutes"`, `group = .transit`, `isEnabledByDefault = true`.
- `refreshPolicy = .static` — this layer is **selection-driven, not viewport-driven**. `viewportDidChange(_:)` is a no-op.
- No zoom gate (`zoomWindow` admits all heights). A trip shape spans far more than a stop-density viewport; culling it by visible-rect height would hide the line at exactly the zoom levels where it is most useful.
- `isClusterable = false`.
- `availability = .available` — shapes and trip status are core OBA REST, present in every region.

It owns its own overlays and annotations and removes only those on `deactivate()`.

### Changes to shared map infrastructure

Two changes to code the rental layer also depends on. Both are additive or
strictly-safer; neither changes rental behavior.

**1. `MapLayer` gains an overlay hook.** New protocol requirement with a default
implementation returning `nil`, so `StopsMapLayer` and `RentalMapLayer` need no edits:

```swift
func renderer(for overlay: MKOverlay, in mapView: MKMapView) -> MKOverlayRenderer?
```

**2. `MapRegionManager.mapView(_:rendererFor:)` stops crashing.** It currently
ends in a bare `fatalError()` for any overlay that isn't an `MKPolyline`
(`MapRegionManager.swift:1039`). It becomes: ask each **enabled** registered layer
in order → fall back to the existing brand-colored polyline renderer → for
anything still unrecognized, `Logger.error` and return a plain
`MKOverlayRenderer(overlay:)`. A shipping app should not abort because an overlay
type was unexpected, and this spec is the first thing to add overlay types beyond
the two hardcoded ones.

**3. `cancelSearch()` stops wiping other layers' overlays.** It currently does
`mapView.removeOverlays(mapView.overlays)` (`MapRegionManager.swift:650`), which
would silently erase our route lines whenever a search is cancelled. It must
remove only the overlays `displaySearchResult(stopsForRoute:)` added — tracked in
a stored property, mirroring how `displayUniqueStopAnnotations` tracks its own
annotations.

### Data flow

```
StopViewModel.$stopArrivals ──(Combine, existing 15 s timer)──▶ MapViewController
                                                                      │
                                                    update(stopArrivals:preferences:)
                                                                      ▼
                                                        StopRouteFocusMapLayer
                                                          │                │
                                              overlays + annotations   routes[]
                                                          │                ▼
                                                       MKMapView       StopMapFocus
                                                                           │
                                                                    @Published
                                                                           ▼
                                                          StopPageSheetHeaderView chips
```

Chip tap and marker tap both write `StopMapFocus.focusedRouteID`; the layer
observes it and restyles. There is no second source of focus state.

Riding the existing `$stopArrivals` publisher means **no new timer and no new
polling** — vehicles advance on the same 15 s tick that already updates the
countdowns in the list.

### Deriving the model

From `viewModel.stopArrivals?.arrivalsAndDepartures`, filtered through
`stopPreferences` (`ArrivalDeparture.filter(preferences:)`, `ArrivalDeparture.swift:480`)
so hidden routes draw no line and contribute no vehicle:

- **Routes** — deduplicated by `routeID`, in first-appearance order over the time-sorted list. This is "routes-arriving order," which the brief specifies over alphabetical.
- **Polyline per route** — the soonest arrival for that route supplies `trip.shapeID`. Skip when `shapeID` is empty (agencies without shapes). Fetch via `RESTAPIService.getShape(id:)` (`RESTAPIService+Get.swift:260`) through a shape cache keyed by shape ID; decode with the existing `PolylineEntity.polyline` / `Polyline.mkPolyline`. Different routes that share a shape fetch once.
- **Vehicles** — every filtered arrival whose `tripStatus` yields a usable coordinate (prefer `position`, fall back to `lastKnownLocation`; reject null-island as `TripViewController` already does), deduplicated by `vehicleID ?? tripID`. Carries the `ArrivalDeparture` so the marker and callout can read headsign, countdown, deviation, occupancy, and `lastUpdateTime` without another lookup.
- **`hasLiveVehicle`** per route — true iff that route contributed at least one vehicle. This is what lights the chip's green dot, so the dot is literally "there is something on the map to point at."

## Rendering

### Route lines

Two overlays per route, added casing-first so the colored core draws above:

- **Casing**: white, `lineWidth = core + 4`, `lineCap = .round`.
- **Core**: `route.color` (agency/GTFS), `lineWidth = 5`, `lineCap = .round`; `7` when focused.
- When any route is focused, non-focused lines render at `alpha 0.32`; the focused one at full opacity.

The casing is not decoration — it is what makes a route-colored line legible over
the basemap, and it is why the prototype draws every line twice. Overlay count
stays small (2 × routes; ≤ 12 at a six-route hub).

A `RouteShapeOverlay: MKPolyline` subclass carries `routeID` and `isCasing` so
`renderer(for:)` can style without a side table.

### Vehicle markers

`PulsingVehicleAnnotationView` gains route-color tinting and a focused state
(raised `zPriority`, emphasized ring). It keeps its existing behavior for
heading rotation, realtime pulsing, and the gray non-realtime treatment.

A `StopVehicleAnnotation` carries the `ArrivalDeparture`, its `TripStatus`, and
the route color.

### Vehicle callout

`canShowCallout = true` with a `detailCalloutAccessoryView` carrying: route
badge, headsign, `Vehicle NNNN`, the large countdown in status color, the
deviation label, "position updated Ns ago" from `lastUpdateTime`, and a
**Follow this trip** row.

**Follow this trip** pushes the existing `TripViewController` via `ViewRouter`
into the sheet's navigation stack — the same path the trip panel's "View full
trip" takes today, which works because `StopSheetPresenter` deliberately wraps
the page in a `UINavigationController` for exactly this reason.

### Focus behavior

- Tapping a chip focuses the route of its first live vehicle. Line thickens, others dim to `0.32`, other chips dim to 45%, focused chip gets tinted fill and a 1 pt border in the route color, and the vehicle's callout opens.
- Tapping the same chip again, or tapping the focused marker, clears focus.
- A chip for a route with **no** live vehicle is a **no-op**. There is nothing on the map to point at. No error, no camera move, no visual change.
- **The arrivals list is never filtered.** Focus is map-side emphasis only. Every arrival stays visible in chronological order.

### Camera

On stop selection, recenter so the stop sits in the map area above the `.half`
detent — today there is no recentering at all, so a tapped pin can end up behind
the sheet. Uses `mapRectThatFits(_:edgePadding:)` with a bottom inset derived
from the panel's actual surface height rather than the ad-hoc `200`/`128`
constants at the two existing fit sites.

Focus changes do **not** move the camera. Focus is emphasis, not navigation.

### Route chips in the header

`StopPageSheetHeaderView` already lays route chips out in a `FlowLayout`
(`:70-76`, `:122-136`) — the brief's `wrap` layout is effectively already there.
The chips gain: a short color bar in the route's map-line color, a small green
dot when `hasLiveVehicle`, focused fill + 1 pt border, 45% dim when another route
is focused, and a tap target.

When `mapFocus` is nil (every pushed presentation), the chips render exactly as
they do today and are not interactive.

## Deliberate deviations from the prototype

- **No route-stop ring dots along the lines.** The mockups show colored ring dots at each stop along each route. Sourcing them means a second per-route fetch (`stops-for-route`) for what is essentially decoration. Deferred.
- **No basemap dimming.** The prototype dims the basemap while a stop is selected (`dimBasemap: true`). Cheap in UIKit via `MKStandardMapConfiguration.emphasisStyle = .muted`, but it is a global map-appearance change with its own dark-mode and map-type questions. Deferred.
- **No direction-flow animation** (`animateFlow`, off by default in the prototype).
- **No `picker` header variant.** The brief itself says ship `wrap`.

## Error and empty states

- Shape fetch fails or `shapeID` is empty → that route draws no line. Its vehicles still render, and its chip still works if it has one. No error surfaced; a missing line is not a rider-facing failure.
- Arrival has no `tripStatus` position → no marker. The arrival stays in the list; its chip dot stays off.
- Stop has no arrivals (or all routes filtered) → no lines, no vehicles, no chips. The map looks as it does today.
- Arrivals refresh fails → last-good overlays and markers stay on screen, matching `StopViewModel`'s existing keep-last-good behavior for the list.

## Accessibility

- Vehicle markers carry an accessibility label naming route, headsign, countdown, and adherence — never color alone.
- Route chips announce their focused state and whether the route has live tracking; the green dot is paired with that text, never the sole signal.
- Line color is never the only way to tell routes apart — the chip pairs the color bar with the route short name, and the callout names the route.
- Reduce Motion: vehicle pulsing already respects the existing non-realtime `delayBetweenPulseCycles` path; the line draw-on animation is skipped entirely.

## Testing

Unit tests in `OBAKitTests` against pure logic, per repo convention (no UI tests):

- **Route derivation**: first-appearance ordering, not alphabetical; `hiddenRoutes` excluded from routes, lines, and vehicles; duplicate routes collapsed.
- **`hasLiveVehicle`**: true iff ≥ 1 filtered arrival for that route yields a coordinate; false for a schedule-only route.
- **Vehicle derivation**: dedupe by `vehicleID ?? tripID`; arrival with no `tripStatus` produces no marker; null-island coordinate rejected; `lastKnownLocation` used when `position` is absent.
- **Shape cache**: one fetch per distinct shape ID; two routes sharing a shape fetch once; empty `shapeID` short-circuits without a request.
- **Focus semantics**: tapping the same route twice clears focus; a route with no live vehicle is a no-op; marker tap and chip tap converge on one value.
- **Renderer dispatch** (regression): an unrecognized overlay yields a renderer instead of trapping — the `fatalError()` at `MapRegionManager.swift:1039` must not come back.
- **`cancelSearch()`** removes search overlays only, leaving layer overlays in place.
- **Attachment gating**: a pushed `StopPageViewController` has a nil focus object and non-interactive chips; existing `StopSheetPresenterTests`, `StopPagePresentationTests`, and `StopDetailSheetHostTests` keep passing.

Verification: `scripts/generate_project OneBusAway`, then build-for-testing plus
`OBAKitTests` on the iPhone 17 simulator, plus a manual simulator walkthrough
against a live region — tap a stop, confirm lines and vehicles appear, tap a
chip, tap a marker, follow a trip, dismiss, and confirm the map is clean.

## Out of scope

Each gets its own spec:

- **Stop-sheet header compaction** — folding the Chronological/By-route control into the list header as compact `Time`/`Route` segments, and moving `Past · N` to that row.
- **Trip push view** — tapping an arrival cell pushing a SwiftUI trip page (repeated cell header, stop list scrolled to YOUR STOP, the four actions) and switching the map to whole-trip focus with spent/ahead shape treatment and a terminal chip.
- Route-stop ring dots, basemap dimming, direction-flow animation, the `picker` header variant.
- Any change to the SwiftUI `MapPanelRootView` surface, the legacy `StopViewController`, or the `Vehicles` screen.
