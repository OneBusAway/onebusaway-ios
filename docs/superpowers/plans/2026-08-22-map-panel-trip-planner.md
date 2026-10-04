# Trip Planner in the Map Panel — implementation plan

## Context

OTPKit's trip planner runs today only on the UIKit map surface
(`MapViewController`), which hands OTPKit a whole second `MKMapView`
(`tripPlannerMapView`) and alpha-swaps the two. The SwiftUI map panel
(`MapPanelRoot`) has no `MKMapView`, so OTPKit's shipped `MKMapViewAdapter`
cannot be used there.

Already landed on this branch:

- `OBAKit/Sheet/Root/TripPlannerMapDisplayModel.swift` — an `OTPMapProvider`
  conformance backed by `@Published` state, so OTPKit's imperative map calls
  become state the SwiftUI `Map` renders. Commit `d018e1ed`.
- `OBAKitTests/Sheet/TripPlannerMapDisplayModelTests.swift` — 17 tests, passing.

Already open upstream (both required for this branch to compile):

- OneBusAway/otpkit#160 — `@MainActor` on `OTPMapProvider`.
- OneBusAway/otpkit#161 — `chrome:` parameter on `TripPlannerView` /
  `TripPlanner.createTripPlannerView`, plus `TripPlanner.reset()`.

Out of scope for this plan: wiring the rental "Plan a trip using this bike"
action. That depends on onebusaway-ios#1293, which is unmerged, and the shared
`RentalDetailView` it introduces does not exist on this branch.

## Spec

The authority for this work is the integration study published at
https://claude.ai/code/artifact/ec3932e7-93db-4966-b9dd-4ad6c9546db2 —
in particular blockers B3 (route carries no destination), B4 (no `MKMapView`),
B7 (detent vocabularies) and B11 (single map selection type). Where this plan
and that study disagree, the study wins.

## Global Constraints

- **Build/test environment.** `Apps/Shared/app_shared.yml` temporarily points
  the OTPKit dependency at the local checkout
  `/Users/mohamedsliem/Desktop/Work/OBA/otpkit`, which sits on branch
  `integration/trip-planner-embedding` (= #160 + #161 merged). Never commit a
  change to `app_shared.yml`, and never commit `OBAKit.xcodeproj`.
- **Regenerate before building.** `/usr/bin/ruby scripts/generate_project OneBusAway`
  (the repo's rbenv ruby is not installed; system ruby works).
- **Build:** `xcodebuild build-for-testing -scheme App -destination 'platform=iOS Simulator,name=iPhone 16'`
- **Test:** `xcodebuild test-without-building -only-testing:OBAKitTests -project OBAKit.xcodeproj -scheme App -destination 'platform=iOS Simulator,name=iPhone 16'`
- **Always iPhone 16 (iOS 26).** Never iPhone 17 Pro.
- **Two pre-existing test failures** are expected and are NOT yours to fix:
  `RentalFormatTests.rangeFallbackUsesAbbreviatedUnits` (locale artifact) and
  `BackgroundAnnotationDeemphasisTests` "Opening a sheet refreshes every
  participating annotation but the selected stop" (cross-suite interference;
  passes in isolation). Baseline is 2294 tests with exactly these 2 failures.
- **Swift 6 language mode**, main-actor default isolation, five concurrency
  diagnostic groups escalated to errors. A data race warning fails the build.
- **Tests use Swift Testing** (`@Suite(.serialized)` / `@Test` / `#expect`),
  never XCTest.
- **SwiftLint:** `scripts/swiftlint.sh` must report no new violations. Five
  violations are pre-existing in files this plan does not touch.
- **No Claude/AI attribution** in commit messages.
- Follow the surrounding code's comment density and idiom. This codebase
  documents *why*, at length, on non-obvious decisions.

---

## Task 1: Give `.tripPlanner` a destination payload and a tip detent

**Files:** `OBAKit/Sheet/Coordinator/SheetRoute.swift`,
`OBAKitTests/Sheet/AppSheetRouteTests.swift`

`AppSheetRoute.tripPlanner` currently takes no associated value, so pushing it
cannot say where the rider is going. Both entry points need a payload, and they
need different shapes: a map item prefills a destination and leaves the mode
open; a rental (later) prefills a via point and locks the mode.

**Requirements:**

1. Add a `TripPlannerRequest` type in `SheetRoute.swift`, `nonisolated`,
   `Hashable` and `Equatable`, with exactly these stored properties, all
   optional, all defaulting to `nil`:
   - `destination: MKMapItem?`
   - `viaPoint: CLLocationCoordinate2D?`
   - `transportMode: TransportMode?` (from `import OTPKit`)

   `CLLocationCoordinate2D` is not `Hashable` or `Equatable` — implement both
   by hand over `latitude`/`longitude`. `MKMapItem` is a reference type that
   is already used as an associated value by `case mapItem(MKMapItem)`; follow
   whatever that case does.

2. Change the case to `case tripPlanner(TripPlannerRequest)`.

3. Add an arm for the payload in the analytics-key `switch` (the one deriving
   a key per case, around line 123). Key format must follow the existing
   mechanical convention in that switch. Do not include the payload's
   coordinates in the key — an analytics key with a rider's location in it is
   a privacy leak. Use the presence/absence of each field instead, e.g.
   `tripPlanner_destination` / `tripPlanner_viaPoint` / `tripPlanner_blank`.

4. Give `.tripPlanner` its own detent configuration, split out of the group it
   currently shares with `.tripDetails`, `.routePicker`, `.currentTrip`,
   `.transitAlert`, `.more`, `.settings`:
   - detents: a tip-sized `.height(_)` detent, `.medium`, and `.large`
   - initial detent: `.large`
   - `isDismissDisabled: false`

   Define the tip height as a named static constant on `AppSheetRoute`
   alongside `homeCollapsedHeight`, and document why it exists: OTPKit
   collapses to its own custom tip detent when turn-by-turn directions open
   (`DirectionsSheetView.tipDetent`), and the panel owns detents centrally, so
   the panel needs a comparable rung. Pick a value consistent with the
   existing `homeCollapsedHeight`.

   Note the `precondition` in `SheetDetentConfiguration.init`: the initial
   detent must be a member of the detents set.

5. Leave `.tripPlanner`'s existing stacking preference (`prefersStacking == true`)
   as it is.

**Tests** in `OBAKitTests/Sheet/AppSheetRouteTests.swift` (existing file —
match its conventions):

- Two `TripPlannerRequest` values with equal fields are equal and hash equally;
  differing coordinates compare unequal.
- The analytics key differs between a destination request, a via-point request
  and an empty one, and contains no coordinate digits.
- `.tripPlanner`'s detent configuration contains three detents, opens `.large`,
  and its initial detent is a member of its detent set.

**Verification:** build, then run the full `OBAKitTests`. Expect the 2
pre-existing failures and no others. Note that changing the case's shape will
break `AppSheetViewFactory`'s existing `.tripPlanner` arm — update that arm
minimally to keep compiling (it currently routes to `unimplementedView(for:)`;
it must keep doing so until Task 2 replaces it).

---

## Task 2: Build `TripPlannerSheetView` and register it in the factory

**Files:** new `OBAKit/Sheet/Content/TripPlanner/TripPlannerSheetView.swift`,
`OBAKit/Sheet/DI/AppSheetViewFactory.swift`,
`OBAKitTests/Sheet/AppSheetViewFactoryTests.swift`

**Requirements:**

1. `TripPlannerSheetView` owns one `OTPKit.TripPlanner` for the lifetime of the
   sheet. Construct it **once in `init`** and hold it in `@StateObject` (wrap it
   in a small `ObservableObject` box if `TripPlanner` is not one). This is
   load-bearing: `AppSheetViewFactory` rebuilds view bodies freely, `TripPlanner`
   owns exactly one `TripPlannerViewModel` for its lifetime, and rebuilding it
   mid-flow would reset the rider's trip.

2. Build the planner the way `MapViewController.buildTripPlanner(region:)`
   (around line 528) does, and keep parity with it:
   - `GraphQLAPIService(baseURL:)` when `region.openTripPlannerGraphQLURL` exists,
     else `RestAPIService(baseURL:)` when `region.openTripPlannerURL` exists,
     else the sheet renders an unavailable state rather than crashing.
   - enabled modes `[.transit, .walk, .bike, .car]`, plus
     `[.transitBikeRental, .bikeRental]` when `region.isBikeshareEnabled`.
   - `OTPConfiguration` with `themeConfiguration` primary colour
     `Color(uiColor: ThemeColors().brand)` and `searchRegion` from
     `application.currentRegion?.serviceRect`.
   - Pass `application.notificationCenter`.

3. The map provider is the **already-built** `TripPlannerMapDisplayModel`
   (`OBAKit/Sheet/Root/TripPlannerMapDisplayModel.swift`), injected from the
   factory — not constructed here. It is owned by the panel, because the panel's
   `Map` renders it.

   Task 3 runs before this task and constructs that instance in
   `MapPanelRootController`, handing it to `MapPanelRootView`. **This task adds
   the `AppSheetViewFactory` parameter** for the same instance and updates the
   controller's factory call site. Splitting it this way keeps each task's diff
   self-consistent: Task 3 never adds a parameter it does not use.

4. Render OTPKit's view with `chrome: .embedded` via
   `tripPlanner.createTripPlannerView(destination:viaPoint:transportMode:chrome:onClose:)`,
   supplying the panel's own header in the style of the other detail sheets.
   Translate `TripPlannerRequest.destination` (`MKMapItem`) into OTPKit's
   `Location` the way `MapViewController.showTripPlanner` does.

5. On dismissal, call `TripPlanner.reset()` **and** the display model's
   `clear()`. OTPKit's `.embedded` chrome renders no close button, so this
   cleanup is the host's responsibility; without it the next presentation
   reopens on the previous trip.

6. In `AppSheetViewFactory`, replace `.tripPlanner` in the `unimplementedView`
   group with a real arm calling a new `tripPlannerView(request:)`. The factory
   already holds `application`; add whatever it needs for the display model,
   following how `layersModel`/`mapViewModel` are injected in that file.

**Tests:** extend `AppSheetViewFactoryTests.swift` — building `.tripPlanner`
no longer hits the unimplemented path, and a factory built for a region with no
OTP URL still produces a view rather than trapping.

**Verification:** build, full `OBAKitTests`, `scripts/swiftlint.sh`.

---

## Task 3: Render the trip on the panel's map

**Execution order: this task runs BEFORE Task 2.** Task 2 consumes the display
model instance this task creates.

**Files:** `OBAKit/Sheet/Root/MapPanelRootView.swift`, new
`OBAKit/Sheet/Root/TripPlannerMapOverlays.swift`,
`OBAKit/Sheet/Root/MapPanelRootController.swift`,
`OBAKitTests/Sheet/` (new or existing suite)

Construct the model in `MapPanelRootController` and pass it to
`MapPanelRootView` only. Task 2 threads the same instance into
`AppSheetViewFactory`.

**Requirements:**

1. Own one `TripPlannerMapDisplayModel` at the panel level: construct it in
   `MapPanelRootController` beside `MapPanelLayersModel`, hand it to both
   `MapPanelRootView` and `AppSheetViewFactory`.

2. Add a free `@MapContentBuilder` function in a new
   `TripPlannerMapOverlays.swift` that renders the model's `routes` as
   `MapPolyline` and its `annotations` as `Annotation`. Put it in its own file
   for the reason `MapSearchOverlays.swift` states in its own doc comment:
   `MapPanelRootView.body` has already exceeded Swift's type-check budget once.
   Follow `MapSearchOverlays.swift` closely — it is the precedent.

   Route styling: honour each `Route`'s `color`, `lineWidth` and `dashPattern`.
   Draw in array order; that order is OTPKit's z-order (white halo first, then
   the coloured leg on top).

3. **Do not make trip annotations selectable in this pass.** Render them
   untagged.

   The study's B11 assumed `MapPinSelection`, a closed selection enum — but
   that type arrives with onebusaway-ios#1293 and does not exist on this
   branch, where the `Map`'s selection is still
   `@State private var selectedStopID: Stop.ID?`. Introducing an equivalent
   enum here would duplicate #1293's work inside `MapPanelRootView.swift`,
   the file that PR rewrites most heavily.

   `TripPlannerMapDisplayModel` already stores OTPKit's handler and exposes
   `handleAnnotationSelection(identifier:)`, so the seam is built; wiring it
   is a one-line change once #1293 lands. Leave `selectedStopID` and its
   `onChange` exactly as they are.

4. Feed the model the map's viewport: call `updateVisibleRegion(_:)` from the
   existing `.onMapCameraChange` handler. `getCurrentRegion()` is a synchronous
   read in OTPKit's protocol and a SwiftUI `Map` has nothing to ask.

5. Apply `cameraTarget` when it appears and call `consumeCameraTarget()`, exactly
   as the view already does for `MapSearchDisplayModel.CameraTarget`. Handle all
   three cases: `.region`, `.rect` (respect `edgePadding`), `.userLocation`.

6. Suppress the ambient stop layer while a trip is drawn — extend the existing
   `searchDisplay.suppressesAmbientStops` gate to also consider
   `displayModel.isShowingTrip`, matching how a drawn search route already
   takes over the map.

7. Clear the model when `.tripPlanner` leaves the sheet stack, in the existing
   `.onChange(of: coordinator.stackedRoutes)` handler that
   `MapSearchDisplayModel.clearIfOwnerAbsent(from:)` already uses. Route-stack
   lifetime, not `onDisappear` — read that method's doc comment for why.

**Tests:** the ambient-stop suppression gate and the selection-forwarding
behaviour are the testable parts; assert them directly on the model plus
whatever seam the view exposes. Do not write tests that assert on SwiftUI view
internals.

**Verification:** build, full `OBAKitTests`, `scripts/swiftlint.sh`.

---

## Task 4: Wire the map item "Directions" action

**Files:** `OBAKit/Sheet/Content/Search/MapItemSheetView.swift`,
`OBAKitTests/Sheet/MapItemSheetViewTests.swift`

`MapItemSheetView` builds its `MapItemViewModel` with `planTripHandler: nil`
(around line 70), which hides the button. The comment there names this exact
task.

**Requirements:**

1. Replace `planTripHandler: nil` with a handler that pushes
   `.tripPlanner(TripPlannerRequest(destination: mapItem))`.

2. Gate it on the region actually supporting OTP — `Region.supportsOTP`. When
   the current region has no OTP server, keep passing `nil` so the button stays
   hidden. A visible button that opens an unavailable planner is worse than no
   button; the existing comment makes the same argument for the `nil` case.

3. Replace the stale comment explaining why the handler is `nil`.

**Tests:** extend `MapItemSheetViewTests.swift` — a region with an OTP URL
produces a handler that pushes `.tripPlanner` carrying the map item; a region
without one leaves the handler `nil`.

**Verification:** build, full `OBAKitTests`, `scripts/swiftlint.sh`.
