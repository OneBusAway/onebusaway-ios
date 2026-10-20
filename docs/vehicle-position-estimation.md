# Estimated vehicle positions on the map

Status: **implemented behind `FeatureFlags.estimatesVehiclePositionsKey`
(Settings › Experimental), off by default.** Phases 0–2 below shipped together;
§0.1 records what changed from this spec while building it and what the
replays measured. Written from the brief `vehicle-position-estimation-brief.md`
(2026-10-19) after reading this codebase, the Java server
(`onebusaway-application-modules`) and maglev.
Earlier work this builds on: `docs/vehicle-coordinate-interpolation.md`
(#1109 / #1323 / #1341).

## 0.1 As built (2026-10-19)

**Measured on live Puget Sound (Java server, behind CloudFront),** eight trips on
the C, D and E Lines and route 21, `trip-details` polled every 15 s for 25 minutes
(`OBAKitTests/fixtures/vehicle_replay_*.json`, made with `scripts/vehicle_replay_fixture`):

- A fix is **67–77 s old when it arrives** (median by trip), ~85 s at p90. R4 was
  right: the marker is always more than a minute stale before the app does anything.
- Distinct fixes arrive 15–30 s apart.

**Replay evaluation** (`VehicleEstimationReplayTests`, §8.3), all eight trips:

| | median | p90 |
|---|---|---|
| Display error, estimate | **146 m** | **421 m** |
| Display error, reported fix (trip page today) | 313 m | 977 m |
| Display error, server `position` (stop map today) | 318 m | 1070 m |
| Next-fix error, estimate | **65 m** | **186 m** |
| Next-fix error, reported fix | 107 m | 390 m |
| Next-fix error, server `position` | 123 m | 409 m |

Display error is what a rider sees: the marker every 5 s against where the bus
actually was then, interpolated from the fixes that arrive later. Next-fix error
counts only a fix newer than any before it; a repeat or a late, older fix is not a
prediction. The test fails
if the estimate stops beating the reported fix on either measure. R1 is settled
for Java regions: `position` is no better than the raw fix, so the trip page keeps
`lastKnownLocation` as its fallback.

**Changes from the spec:**

- **Phase 2 schedules come from `trip-details` per vehicle, not `trips-for-route`.**
  A live `trips-for-route` for route 21 was 278 KB (31 trips plus 267 stop
  references), so up to ~1.6 MB per stop opened; one `trip-details` is 10–20 KB.
  Cached per trip per map session in `TripScheduleCache`.
- **The algorithm is schedule-paced** (§4.3 as written), with the pace weight
  decaying by the newest fix's age.
- **The staleness halo grows with fix age, not `v × age`.** A radius in meters
  needs the zoom level; a radius in points from age alone doesn't
  (`VehicleMarkerStaleness`). Because fixes are already ~70 s old on arrival, a
  Puget Sound marker spends most of its time in the aging state.
- **Skew is corrected** from each response's `currentTime` plus its `Age` header
  (`ServerClockSample`, `ClockSkewEstimator`), and trip and stop polls bypass the
  URL cache while the flag is on.
- **No Android port contract.** Android has its own implementation, so §9's
  shared vectors were dropped.
- **Estimation also covers the stop map** (Phase 2), not only the trip page that
  §0 scoped v1 to: each bus on its own trip's shape and schedule.
- **A frozen marker reads as estimated.** Past the horizon it stays where the
  horizon left it, up to 120 s of travel past the fix, so the freshness line says
  "estimated position, updated …", not §7's "Location last updated …". Only a
  `.raw` estimate draws the reported fix.
- R2 is fixed and covered by a synthetic test. It has not been reproduced against
  a live maglev region.

## 0. Summary

Today the trip page draws the vehicle at `tripStatus.lastKnownLocation`, the raw
GPS fix, and glides it for 0.8 s when a poll moves it (`VehicleCoordinateUpdate`).
This spec adds an on-device estimator. It anchors the last fix to the trip's
shape, advances it at a speed taken from the schedule and scaled by the
vehicle's observed pace, holds briefly at stops, and stops after a horizon. The
estimate drives the marker at 1 Hz.

Before writing the algorithm, I red-teamed the brief against the code and the
servers. Several of its premises do not hold. §1 lists them, and they reshape
the plan:

- **Scope.** The original plan: v1 covers the **trip page only**. As built, it
  also covers the stop map (§0.1).
- **Phase 0 first.** Three prerequisites ship before the estimator. One is a
  decoding bug that probably blanks vehicles on maglev today.
- **Measure first.** The estimator stays behind a flag until a replay evaluation
  shows that it beats the baseline.

## 1. Red team: where the brief is wrong or under-specified

| # | Brief says | What is actually true | Consequence |
|---|---|---|---|
| R1 | `position` is "server-interpolated from schedule + `scheduleDeviation`", so switching to it is a quick win. | **Java:** `position` is the schedule location at `timeOfRecord − deviation`, computed once at ingest. It is *not* re-extrapolated per request: `_locationInterpolation = false`, `AbstractBlockLocationServiceImpl.java:57`, read at `:320`. It is a schedule-implied point at fix time, and it can sit far from the GPS. In `arrivals_and_departures_for_stop_mts_11671_filter_route_alerts.json`, `position` is ≈640 m from `lastKnownLocation`. **maglev:** `position` is the GPS fix snapped to the shape (`trips_helper.go:344`). | The "quick win" means different things on the two servers and may be worse than GPS on Java. It is not a quick win until it is measured. The app is already inconsistent: the stop-route-focus layer prefers `position` (`StopRouteFocusModel.swift:148`), but the trip page uses `lastKnownLocation` (`ModelExtensions.swift:85`, `VehicleAnnotation.swift:24`). |
| R2 | Prefer server `lastKnownDistanceAlongTrip` for the anchor. | **Java never sets it**: `setLastKnownDistanceAlongBlock` is called only from tests. **maglev** emits `0` when GPS projection fails and a *fractional* meter value when it succeeds (`trips_helper.go:316`). iOS decodes it as `Int?` (`TripStatus.swift:170`). `JSONDecoder` throws on `1234.56` (verified: "Number 1234.56 is not representable in Swift"). | **Probable live bug on maglev regions.** `ArrivalDeparture.tripStatus` is decoded with `try?` (`ArrivalDeparture.swift:181`), so the vehicle silently disappears. `TripDetails.status` is decoded with `try` (`TripDetails.swift:79`), so the whole trip-details decode fails and the stop list says it is unavailable. This is fixed in Phase 0 regardless of this feature. The anchor is our own projection of `lastKnownLocation`. |
| R3 | Anchor = fix distance + fix timestamp. | Java's `distanceAlongTrip` is the **schedule** distance at `timeOfRecord − deviation` (`ABLS:150,293`), not a GPS measurement. maglev's is GPS-projected when the fix is fresh (`trips_helper.go:310`). The decoded `CLLocation` carries **no fix time**: `CLLocation(container:key:)` builds it from lat/lon only (`InternalTypes.swift:28`), so `.timestamp` is the decode time. | Anchor = client projection of `lastKnownLocation` at `lastLocationUpdateTime`. Server `distanceAlongTrip` is only a disambiguation hint (§4.2). Never read `lastKnownLocation.timestamp`. |
| R4 | Fixes arrive every 30–120 s, so a 90–120 s horizon is reasonable. | The servers ingest GTFS-RT every 30 s (Java `GtfsRealtimeSource.java:142`; maglev ±10% jitter). The trip page polls every 30 s (`TripViewModel.swift:87`), the stop page every 15 s (`StopViewModel.swift:224`). maglev sends `Cache-Control: public, max-age=30` on trip-details, arrival(s)-and-departure(s)-for-stop and trips-for-route (`maglev/internal/restapi/routes.go:117-121`), and `getData` uses `.useProtocolCachePolicy` (`APIService+GetData.swift:68`). Feed latency + ingest + HTTP cache + poll phase can stack to **60–100 s of age before the first tick**. | The age distribution is unknown and decides every tunable. Phase 0 measures it. The horizon default is provisional, and the trip page's polls must bypass the HTTP cache (§5.3). |
| R5 | Detect layover / not-started / completed from `phase`. | With GTFS-RT, Java forces `phase = in_progress` (`VehicleStatusServiceImpl.java:91-94`). Layover labels come only from the Orbcad source. maglev uses `in_progress` / `scheduled` / `""`. | `phase` is useless for layover. Infer layover from geometry and schedule instead (§4.6). |
| R6 | Observed speed from "the last two fixes". | Each 30 s poll often returns the *same* fix: same `lastLocationUpdateTime`, two polls per ingest on the stop page. The trip page also receives a `TripStatus` twice per poll, from `arrival-and-departure-for-stop` and from `trip-details` (`TripViewModel.swift:153-155`). | Deduplicate fixes by `(vehicleID, lastLocationUpdateTime)`, not per poll. Real fixes are about 30 s apart at best. |
| R7 | Scheduled segment speed. | Per-stop `distanceAlongTrip` is in the trip-details payload (`trip_details_1_18196913_no_status.json`), but `TripStopTime` does not decode it (`TripStopTime.swift:40-42`). Schedule data exists only on the trip page (`TripViewModel.tripDetails`). The stop-route-focus layer has none. | Phase 0 decodes it. The stop-route-focus layer is out of v1. |
| R8 | "~50 vehicles visible". | No surface draws dozens of OBA vehicles with shapes. The trip page draws one. Stop-route-focus draws one per departure for at most `routeCap` routes, and its shape is pinned **per route** from the soonest departure (`StopRouteFocusMapLayer.swift` `syncRouteOverlays`), so it can be the wrong shape for other trips on the route. `VehiclesMapView` draws raw GTFS-RT `VehiclePosition`s (`RealtimeVehicle.swift`), with no shape and no OBA trip status. | Estimating many vehicles would need per-trip shapes and schedules for each one. That is a Phase 2 cost question (§9). The CPU budget is still designed for 50 (§6.4). |
| R9 | Distance along trip and shape length are the same measure. | Both servers compute distances from the shape geometry and ignore `shape_dist_traveled`, so server-side the stop distances and the status distances agree. The client's haversine length of the decoded polyline differs slightly, and `TripShapeSplit` already works around that by using fractions (`TripShapeSplit.swift:15-24`). | Rescale server distances by `L_client / totalDistanceAlongTrip` before using them on the client shape. |
| R10 | Block continuation is an edge case. | `tripStatus.activeTripID` can name the *previous* trip of the block while the page shows the next one. `distanceAlongTrip` is then relative to the active trip, but the page holds the page trip's shape. Today's split (`TripPageViewController.swift:266-271`) already misreads this. | Estimate only when `activeTripID == page trip ID`. Otherwise fall back to today's behavior (§4.6). |
| R11 | VoiceOver labels on the marker. | The trip-page marker cannot get VoiceOver focus: `isUserInteractionEnabled = false` (`PulsingVehicleAnnotationView.swift:31`), and the SwiftUI marker is `.accessibilityHidden(true)` (`TripFocusMapOverlays.swift`). | Convey "estimated / last updated" in the trip page's text (§7), not on the marker. |
| R12 | Animate new fixes over 1–2 s; continuous motion. | The current Reduce Motion policy is to snap (`VehicleCoordinateUpdate.swift:41`). A marker that glides continuously is exactly the motion that setting asks to remove. | With Reduce Motion on, the marker steps every 10 s without animation (§6.3). |
| R13 | Evaluate "estimate at *t* vs. the fix received at *t*". | A fix received at *t* describes the vehicle at `fixTime < t`. | The metric predicts at the *next fix's timestamp* using only the information available before it (§8.3). |
| R14 | Clock skew: device vs server. | Three clocks are involved: the AVL timestamp, the server, and the device. The envelope `currentTime` exists (`RESTAPIResponse.swift:20`) but can be up to 30 s stale on maglev because of the HTTP cache. `BookingDeadlineEvaluator.swift:45` already warns about this. | Skew estimation must account for the `Age` header, or the request must bypass the cache (§4.7). |

## 2. Answers to the brief's investigation list (§4)

1. **Where markers are drawn.**
   - **Map tab (`MKMapView`):** `TripFocusMapLayer.drawVehicle` (`OBAKit/Mapping/Layers/TripFocus/TripFocusMapLayer.swift:185`) draws a `VehicleAnnotation` (`OBAKit/Trip/VehicleAnnotation.swift`) with a `PulsingVehicleAnnotationView`.
   - **Map panel experience (SwiftUI `Map`, behind `FeatureFlags.useMapPanelExperienceKey`):** `TripFocusMapDisplayModel.vehicle(_:)` (`OBAKit/Sheet/Root/TripFocusMapDisplayModel.swift:235`) feeds `TripVehicleMarker` in `tripFocusMapContent` (`TripFocusMapOverlays.swift`).
   - **One source for both:** each reads `TripMapFocus.Content` (`OBAKit/Mapping/Layers/TripFocus/TripMapFocus.swift`), published by `TripPageViewController.publishMapFocus` (`OBAKit/Trip/TripPage/TripPageViewController.swift:243`).
   - **Other vehicle surfaces:**
     - The stop-route-focus layer: `StopVehicleAnnotation` / `StopRouteFocusMapLayer.syncVehicleAnnotations`, line 309.
     - The legacy `TripViewController`, still reachable from the classic `StopViewController` (`Router.swift:237`) and from vehicle search on the classic map (`MapViewController.swift:1546`).
     - `VehiclesMapView` (raw GTFS-RT).
   - **Forward architecture:** the `TripMapFocus` channel. Implementing at that channel covers both maps. The legacy `TripViewController` gets **no shim**: it keeps today's behavior and is retired with the classic stop page.
2. **Which coordinate the app uses today.**
   - **Trip page and legacy trip screen:** `lastKnownLocation`, through `TripStatus.coordinate` (`OBAKit/Extensions/ModelExtensions.swift:85`) and `VehicleAnnotation.updateAnnotation`.
   - **Stop-route-focus:** `position ?? lastKnownLocation` (`StopRouteFocusModel.swift:148`).
   - **Switching the trip page to `position`:** see R1. Measure it in the Phase 0 replay rather than ship it blind.
3. **Realtime fields (`TripStatus.swift`).** Decoded:

   | Field | Swift type / note |
   |---|---|
   | `distanceAlongTrip` | `Double` |
   | `lastKnownDistanceAlongTrip` | `Int?` (**bug**, R2) |
   | `scheduledDistanceAlongTrip` | `Double` |
   | `totalDistanceAlongTrip` | `Double` |
   | `lastLocationUpdateTime` | `Int64` epoch ms |
   | `lastUpdateTime` | decoded as `lastUpdate: Date?` |
   | `scheduleDeviation` | `TimeInterval` |
   | `predicted` | decoded as `isRealTime` |
   | `phase` | `String` |
   | `status` | decoded as `statusModifier` |
   | `orientation` | OBA degrees, 0 = East, counter-clockwise |
   | `lastKnownOrientation` | `CLLocationDirection?` |
   | `activeTripId` | `activeTripID` |
   | `nextStop` | with `nextStopTimeOffset` |
   | `closestStop` | with `closestStopTimeOffset` |
   | `blockTripSequence` | `Int` |
   | `frequency` | `Frequency?` |
   | `vehicleId` | `vehicleID` |

   None need adding. One needs a type fix. In live fixtures, `lastKnownOrientation` and `lastKnownDistanceAlongTrip` are always 0. Treat 0 as absent.
4. **Shapes.**
   - **Trip page:** `TripViewModel.fetchMapPolyline` (`OBAKit/ViewModels/TripViewModel.swift:257`) fetches `getShape(id:)` **once per page**: it is skipped while `routePolylineCoordinates != nil`. It decodes with `Polyline(encodedPolyline:)` and has no cross-page cache.
   - **Stop-route-focus:** `ShapeCache` (`OBAKit/Mapping/Layers/StopRouteFocus/ShapeCache.swift`) is an actor with 64 entries that de-duplicates in-flight fetches. It is the right cache to share in Phase 2.
   - **Cost:** one ~few-KB request per distinct shape. maglev caches it for 5 min (`CacheDurationLong`).
5. **Stop times / schedule.** Available on the trip page only: `TripViewModel.tripDetails.stopTimes`, refreshed every 30 s even though the schedule is static. `distanceAlongTrip` per stop is present in the payload but not decoded (R7). On other surfaces, the cheapest bulk source is `trips-for-route`: `includeSchedule` defaults to true on both servers, and it returns every trip's stop times for a route in one call.
6. **Refresh cadence.**
   - **Trip page:** a 30 s `Timer` (`TripViewModel.swift:87,321`) runs three concurrent fetches.
   - **Stop page:** a 15 s timer, with a 30 s threshold.
   - **Vehicles map:** a 30 s `Task.sleep` loop (`VehiclesViewModel.swift:57,152`).
   - **Display link:** there is none. `VehicleCoordinateUpdate` animates once per fix.
7. **History.** Nothing keeps a previous fix. `TripFocusMapLayer` keeps only the current annotation and its `tripStatus`. New state is introduced in §3.
8. **Tests and fixtures.**
   - **Mapping:** `OBAKitTests/Mapping/VehicleCoordinateUpdateTests.swift`, `OBAKitTests/Mapping/TripFocus/TripFocusMapLayerTests.swift` + `TripMapFocusFixture.swift`, `OBAKitTests/Mapping/StopRouteFocus/*`.
   - **Models:** `OBAKitTests/Modeling/Model Unit Tests/TripStatusTests.swift`, `EpochWidthTests.swift`.
   - **Fixtures:** `shape_1_20010002.json`, `shape_1_40046045.json`, `trip_details_1_18196913_*.json`, `trip-for-vehicle-1_2799.json`, `frequency-vehicle.json`.
   - **Clock:** `OBAKitTests/Helpers/TestClock.swift`, a `Clock` usable for tick tests.
   - **Gap:** there are no multi-fix sequences. Phase 0 adds a recorder.

## 3. Architecture

```
TripViewModel (30 s poll)                       OBAKitCore (pure, portable, nonisolated)
  tripConvertible.tripStatus ─┐                 ┌───────────────────────────────────────┐
  tripDetails.status ─────────┼─► Fix ─────────►│ VehicleTrack     (value: ≤3 fixes,    │
  tripDetails.stopTimes ──────┼─► TripGeometry ►│                   reconcile state)    │
  routePolylineCoordinates ───┘   (built once)  │ VehiclePositionEstimator.estimate(    │
                                                │   track, geometry, at: Date)          │
TripPageViewController                          │   → VehicleEstimate                   │
  owns TripMapFocus ─┐                          └───────────────────────────────────────┘
                     │ @Published content (per poll, as today)
                     │ @Published vehicleEstimate (per tick, NEW)
                     ▼
     VehicleEstimationDriver (@MainActor, OBAKit): owns VehicleTrack, ticks at 1 Hz
     via an injected Clock, pauses when hidden or backgrounded
                     │
       ┌─────────────┴──────────────┐
TripFocusMapLayer             TripFocusMapDisplayModel
(MKMapView: UIView.animate    (SwiftUI Map: separate @Published vehicle,
 linear 1 s per tick)          so the polylines are not rebuilt per tick)
```

### 3.1 OBAKitCore: `OBAKitCore/Models/VehicleEstimation/` (new, portable tree)

The core types are pure value types: no UIKit, no MapKit, no `CLLocation`
timestamps. They take `Date` and `Double` meters only (no `Int` epochs; see the
`arm64_32` rule in CLAUDE.md). Everything is `nonisolated` and `Sendable`.

- `VehicleFix`: `tripID`, `vehicleID?`, `fixTime: Date`, `coordinate` (lat/lon
  doubles), `serverDistanceAlongTrip: Double?`, `totalDistanceAlongTrip: Double`,
  `isRealTime`, `isCanceled`, `isFrequencyBased`.
  `init?(tripStatus:pageTripID:)` returns `nil` in these cases:
  - no `lastKnownLocation`
  - null island or an invalid coordinate
  - `lastLocationUpdateTime == 0`
  - `activeTripID != pageTripID`
  - `!isRealTime`
- `TripGeometry`: the shape as coordinates, its cumulative lengths in meters,
  and the stops as `(s: meters on the client shape, arrival: Date, departure: Date)`,
  rescaled per R9. It is built once per (shape, stop times) and memoized by trip ID.
- `ShapeProjection`: `project(_:onto:hint:) -> (s, offsetMeters)?` and
  `point(at s:) -> (coordinate, bearingDegrees)`. Bearings use the same
  convention as `OnDemandGeometry`, which already does nearest-point-on-segment
  math (`OBAKitCore/Models/OnDemand/OnDemandGeometry.swift`).
- `VehicleTrack`: the last ≤3 accepted fixes and the reconciliation state
  (`displayedS`, `holdStartedAt`). It has `mutating func ingest(_ fix:, geometry:, now:) -> IngestResult`
  (`.accepted`, `.duplicate`, `.rejected(reason)`, `.reset(reason)`).
- `VehiclePositionEstimator`: a stateless `static func estimate(track:geometry:at:tunables:) -> VehicleEstimate`.
- `VehicleEstimate`: `coordinate`, `s`, `bearingDegrees` (compass),
  `obaOrientation` (= `90 − bearing`, for `PulsingVehicleAnnotationView`, which
  expects OBA degrees), `fixAge: TimeInterval`, `mode` (`.estimated`, `.frozen`,
  `.raw(reason)`), and `snap: Bool`.
- `VehicleEstimationTunables`: a struct holding every constant in §4.8, so tests
  and the debug menu can override them.

### 3.2 OBAKit

- `VehicleEstimationDriver` (`OBAKit/Mapping/VehicleEstimation/`): a
  `@MainActor final class` owned by `TripMapFocus`, so its lifetime is the
  page's. It does the following:
  - Feeds every `TripStatus` from `TripViewModel` into the track, from both
    `tripConvertible` and `tripDetails`.
  - Rebuilds `TripGeometry` when the shape or stop times first arrive.
  - Runs a `Task` loop on an injected `Clock` (`ContinuousClock` in production,
    `TestClock` in tests).
  - Publishes `vehicleEstimate`.
- `TripMapFocus` gains `@Published private(set) var vehicleEstimate: VehicleEstimate?`.
  `Content` stays as it is, so poll-rate rendering (shape, stops) is untouched.
  `Content.vehicleCoordinate` remains the fallback when there is no estimate.
- `TripFocusMapLayer` subscribes to `$vehicleEstimate`. Each tick applies a
  linear `UIView.animate(withDuration: tickInterval, options: [.curveLinear, .beginFromCurrentState])`
  to `annotation.coordinate`, and sets `PulsingVehicleAnnotationView`'s heading
  from `obaOrientation`. A new `applyHeading(_:)` is needed, because
  `updateHeading(tripStatus:)` reads `tripStatus.orientation`. The existing
  `VehicleCoordinateUpdate` decision logic still decides snap versus glide on
  `estimate.snap`.
- `TripFocusMapDisplayModel` subscribes separately and publishes
  `@Published vehicle: TripVehicle?`, **not** a new `Display`. `render(_:)`
  rebuilds `MKPolyline`s and arrow placements, which is fine at 30 s and wasteful
  at 1 Hz. The view applies the coordinate in `withAnimation(.linear(duration: 1))`.
  **Spike needed:** I could not confirm from docs that SwiftUI `Map` `Annotation`
  interpolates a changed coordinate inside `withAnimation`. If it doesn't, the
  SwiftUI path updates without animation at 1 Hz, accepting visible 1 s steps,
  or uses a 4 Hz tick for that host only.
- **Threading:** everything after decode runs on the main actor. Projection is
  O(shape points) once per accepted fix. Per-tick work is a binary search over
  the cumulative lengths plus a few multiplies, so actor hops are not worth it.

## 4. Algorithm

Notation: `s` = meters along the client shape, `L` = client shape length,
`now` = device time corrected for skew (§4.7).

### 4.1 Geometry

```
L = Σ haversine(shape[i], shape[i+1])
k = L / totalDistanceAlongTrip            // R9; if total ≤ 0 → k = 1
for each stopTime: s_stop = clamp(k × stopTime.distanceAlongTrip, 0, L)
// maglev emits 0 for every stop on a shapeless trip — no shape ⇒ no estimator anyway.
// If stop distances are not non-decreasing, or are all 0, the schedule is unusable:
// set stops = [] (the scheduled-speed term drops out; see 4.3).
```

### 4.2 Projection with a loop/double-back hint

```
candidates = every segment whose perpendicular distance to fix ≤ maxProjectionMeters
if candidates empty → reject fix (.offShape) — see edge cases
hint = track.displayedS ?? (k × fix.serverDistanceAlongTrip) ?? nil
choose candidate minimizing |s − hint| if hint, else minimizing offset
// tie-break within 1 m of offset → smaller |s − hint|
// reject if hint exists and s < hint − maxBackwardJumpMeters and another candidate
//   exists ahead (a loop's return leg); prefer the forward one.
```

### 4.3 Speed: schedule-paced, scaled by observed pace

The brief's blend of an observed speed and a scheduled speed collapses into
something more robust: follow the schedule's *shape of speed* (slow downtown,
fast on the freeway), scaled by how fast this bus is actually running.

```
v_sched(s) = (s_{i+1} − s_i) / (arrival_{i+1} − departure_i)   for the stop pair around s
             (Δt ≤ 0 or no stops → nil)

pace ratio from the last two accepted fixes f1, f2 (same trip, 10 s ≤ Δt ≤ 180 s):
   r_obs = (∫_{s1}^{s2} ds / v_sched(s)) / (f2.fixTime − f1.fixTime)   // scheduled ÷ observed time to cover it
   if no schedule: v_obs = (s2 − s1) / Δt, used directly
r = clamp(w × r_obs + (1 − w) × 1.0, rMin, rMax),  w = observedWeight × e^{−(now − f2.fixTime)/observedHalfLife·ln2}
v(s) = r × v_sched(s), capped at maxSpeed
if no v_sched and no v_obs → no extrapolation (mode .raw(.noSpeed))
```

Frequency-based trips (`tripStatus.frequency != nil` or
`TripDetails.frequency != nil`) have schedule times that are a template, not
clock times. Absolute times are wrong, but stop-to-stop Δt is still a valid
travel-time template, so `v_sched` is still usable. Only `fixTime` against
schedule time is meaningless, and this formulation never uses it.

### 4.4 Extrapolation with dwell

```
age = now − fix.fixTime            (clamped ≥ 0)
budget = min(age, horizonSeconds) − (time already spent dwelling, tracked per stop)
s = s_fix
walk forward stop segment by stop segment:
    advance at v(s) until budget exhausted or next stop s_i reached
    on reaching s_i (and s_i > s_fix + dwellMinApproachMeters): hold dwellSeconds, budget −= dwellSeconds
s = min(s, s_fix + maxExtrapolationMeters, L)
mode = age > horizonSeconds ? .frozen : .estimated
```

The walk is O(stops crossed), at most a handful per tick.

### 4.5 Reconciliation (new fix arrives)

```
target = estimate(new track, now).s ; shown = track.displayedS
Δ = target − shown
Δ > snapForwardMeters (500, = VehicleCoordinateUpdate.snapBeyondMeters) → snap
0 ≤ Δ                 → catch up over reconcileSeconds: displayed glides at the
                        rate Δ/reconcileSeconds + v, then follows the estimate
−backwardToleranceMeters ≤ Δ < 0 → treat as 0 (absorb jitter)
−snapBackMeters ≤ Δ < −backwardToleranceMeters → HOLD: displayed = max(shown, estimate(t))
                        until the estimate passes it; if holding > maxHoldSeconds → snap
Δ < −snapBackMeters, vehicle/trip change, off-shape → snap (and reset track)
displayedS is monotonic except through an explicit snap.
```

### 4.6 Modes and gating, checked before each estimate

| Condition | Behavior |
|---|---|
| Flag off, no shape (< 2 points), `activeTripID ≠ page trip`, `!isRealTime`, canceled | `.raw`: today's marker at `lastKnownLocation`, today's 0.8 s glide |
| Fix off-shape (> `maxProjectionMeters`) | `.raw(.offShape)` at the GPS point; the track keeps the last on-shape fixes; re-enter on the next on-shape fix |
| **Layover / not started** (inferred, R5): `s_fix ≤ terminalZoneMeters` and `now < firstStop.departure + scheduleDeviation` | hold at the projected point, no extrapolation |
| **Completed**: `s_fix ≥ L − terminalZoneMeters` | hold at the end |
| `age > horizonSeconds` | `.frozen` at the horizon estimate |
| Fix older than the horizon at load | `.frozen`, drawn at `s_fix` itself, not advanced. A first fix with no history has no observed pace, and jumping it forward up to 120 s on schedule pace alone is the riskiest guess the estimator can make. |
| Only one fix ever seen | Extrapolate on schedule pace alone (`r = 1`). No schedule either → `.raw(.noSpeed)` |

### 4.7 Time and skew

```
fixTime = Date(ms: lastLocationUpdateTime)      // fall back to lastUpdate if 0; neither → reject
serverNowAtReceipt = envelope.currentTime + (HTTP Age header ?? 0)
skew = median over the last 5 responses of (deviceReceiveTime − serverNowAtReceipt)
now  = Date() − skew
if fixTime > now + 5 s → clamp age to 0 and log (AVL clock ahead)
```

This needs the envelope `currentTime` and the response headers to reach the
model layer. Today `RESTAPIResponse` decodes `currentTime`, but the typed
`getTrip` / `getTripArrivalDepartureAtStop` return `.entry`. The fallback, if
plumbing that through is too invasive, is `skew = 0` plus a cache-bypassing
request policy for the trip page's two polls. With the cache bypassed, the
AVL→server difference is the residual risk, and the replay data measures it.

### 4.8 Tunables (`VehicleEstimationTunables`)

All are provisional until the Phase 0 data comes in.

| Name | Default | Why |
|---|---|---|
| `tickInterval` | 1.0 s | Smooth with 1 s linear animations; 4 Hz only if the SwiftUI spike needs it |
| `horizonSeconds` | 120 s | The brief's upper bound; revisit against the measured age p90 (R4) |
| `maxExtrapolationMeters` | 800 m | Caps a schedule-pace error at freeway speeds |
| `maxProjectionMeters` | 40 m | Beyond urban GPS error plus shape generalization |
| `maxBackwardJumpMeters` | 100 m | Loop disambiguation |
| `observedWeight` | 0.7 | Trust observed pace when fresh |
| `observedHalfLife` | 60 s | |
| `rMin` / `rMax` | 0.3 / 1.6 | A bus can crawl; it rarely beats the schedule by 60% |
| `maxSpeed` | 30 m/s | The brief's plausibility bound |
| `dwellSeconds` | 15 s | Brief, 15–20 s |
| `dwellMinApproachMeters` | 20 m | Don't re-dwell at the stop the fix is already sitting at |
| `terminalZoneMeters` | 75 m | |
| `reconcileSeconds` | 1.5 s | Brief, 1–2 s |
| `backwardToleranceMeters` | 15 m | |
| `snapBackMeters` | 150 m | |
| `maxHoldSeconds` | 20 s | |
| `snapForwardMeters` | 500 m | Matches `VehicleCoordinateUpdate.snapBeyondMeters` |
| `splitRefreshInterval` | 5 s | §6.2 |
| `reduceMotionStepInterval` | 10 s | §6.3 |

## 5. Data requirements

### 5.1 Model changes (Phase 0, OBAKitCore)

1. `TripStatus.lastKnownDistanceAlongTrip: Int?` becomes `Double?`, and `0`
   decodes as `nil`. Add a regression test with a maglev-shaped fractional value
   in `TripStatusTests`. Check every reader of the old `Int`. **This is a bug
   fix that ships alone.**
2. `TripStopTime` gains `public let distanceAlongTrip: Double?`, read with
   `decodeIfPresent`, plus a test against `trip_details_1_18196913_no_status.json`.
3. `lastKnownOrientation == 0` becomes `nil`? Not needed by this spec (heading
   comes from the shape). Leave it.

### 5.2 No new endpoints in v1

The trip page already fetches the shape (once), trip-details (stop times +
status) and arrival-and-departure-for-stop (status) every 30 s. Optional
improvement: stop re-fetching the static schedule every 30 s. That is out of
scope here.

### 5.3 Caching and request policy

- **Shape:** keep `TripViewModel`'s one-per-page fetch. In Phase 2, move the
  trip page to a shared `ShapeCache` (lifted out of `StopRouteFocus/` to
  `OBAKit/Mapping/`) so reopening a trip costs nothing.
- **`TripGeometry`:** memoize per trip ID in the driver. It is rebuilt only if
  the stop times change (a different count or distances).
- **Polls:** while estimation is on, the trip page's two status requests use
  `.reloadIgnoringLocalCacheData`. That means a cache-policy parameter on
  `getData(for:)` (`APIService+GetData.swift:67`), defaulting to today's value.
  A CDN in front of a server can still cache, and the `Age` header (§4.7)
  covers that.

## 6. Rendering and animation

### 6.1 Update loop

- 1 Hz, driven by `VehicleEstimationDriver`.
- **Paused** in each of these cases:
  - the page disappears (`TripMapFocus.clear()` / `TripFocusMapLayer.end()`)
  - the app leaves the foreground (`UIApplication.didEnterBackgroundNotification`
    / `willEnterForeground`, the same signals `TripViewModel.deactivate()` already
    follows through the page)
  - the trip sheet covers the map at its full detent
  - the vehicle's coordinate is outside `mapView.visibleMapRect` (MKMapView host;
    SwiftUI: the camera region from `onMapCameraChange`)
- A paused driver still ingests fixes. On resume, the first tick snaps if the
  marker would move more than `snapForwardMeters`.

### 6.2 The spent/ahead split

The split comes from `Content.progress`, at fix time. A marker that runs ahead
of the junction between the gray and colored lines reads as a bug. v1 re-splits
from `estimate.s / L` every `splitRefreshInterval` (5 s), and only on the
SwiftUI display model's `spent`/`ahead` and the layer's shape overlays. **Risk:**
`TripFocusMapLayer.render` removes and re-adds every shape overlay, arrows
included. At 5 s that may flicker or cost arrow layout. The spike measures it.
The fallback is to keep the split at the fix and accept the gap (≤ ~30 s of
travel).

### 6.3 Reduce Motion

The estimate is still computed, but the marker moves in discrete steps every
`reduceMotionStepInterval` with no animation. This keeps the existing contract
in `VehicleCoordinateUpdate.decision(reduceMotion:)`. Read
`UIAccessibility.isReduceMotionEnabled` per tick, and listen to
`reduceMotionStatusDidChangeNotification`.

### 6.4 Cost

One vehicle on the trip page has negligible cost. For the Phase 2 budget of 50
vehicles × 1 Hz:
- 50 binary searches over ≤ ~3k cumulative lengths plus 50 annotation coordinate
  writes per second. That is well under 1 ms of CPU.
- The real cost is MapKit re-laying out 50 animated annotation views. Measure it
  with Instruments (Time Profiler + Core Animation) on an iPhone 12-class device
  before Phase 2.

### 6.5 Staleness visuals

These match the existing vocabulary: gray means not realtime, the pulse means
live (`PulsingVehicleAnnotationView.isRealTime`).

| Mode / age | Marker |
|---|---|
| `.estimated`, age < 45 s | As today: route color, pulse, heading from the shape |
| `.estimated`, 45 s ≤ age ≤ horizon | Route color, pulse slows (`delayBetweenPulseCycles` scales with age), plus a translucent halo whose diameter grows with age, to 120 pt at the horizon (as built; see §0.1) |
| `.frozen` | No pulse, alpha 0.6, heading ring hidden |
| `.raw` | Exactly today |

Design review is owed. This is a starting point, not a decision.

## 7. Accessibility

- The marker stays unfocusable, as today (R11). The trip page's text carries the
  information. `TripPageView` / `TripCardView` already show freshness through
  `lastUpdated`. When estimation is active and the vehicle is shown, the page's
  vehicle line gets an accessibility value:
  - "Location estimated. Last update 45 seconds ago."
  - when frozen: "Location last updated 3 minutes ago."
  - Strings go through `OBALoc` in `OBAKit/Strings`. Mind the localization lens:
    every locale gets an entry, never an untranslated swap.
- The stop-route-focus callout already reads "Position updated %@"
  (`VehicleCalloutView.swift:119`). In Phase 2 it becomes "Estimated position.
  Updated %@".
- Under Reduce Motion, §6.3 applies.

## 8. Testing plan (Swift Testing, `OBAKitTests/VehicleEstimation/`)

### 8.1 Pure unit tests (`.serialized` suites, no hosting)

- **Projection:**
  - a straight line
  - a corner (clamped to the segment)
  - off-shape rejection at `maxProjectionMeters + 1`
  - a loop (a figure-eight synthetic shape) with the hint choosing the right leg
  - an out-and-back shape where the hint prevents a jump onto the return leg
- **Geometry:**
  - R9 rescaling
  - non-monotonic stop distances rejected
  - maglev's all-zero stop distances rejected
- **Speed:**
  - schedule-only
  - observed-only
  - blended, with the half-life decay
  - `rMin` / `rMax` / `maxSpeed` clamps
  - a frequency trip uses Δt
- **Extrapolation:**
  - mid-segment
  - crossing one stop with a dwell
  - crossing two stops
  - the horizon freezes
  - `maxExtrapolationMeters`
  - the `[0, L]` clamp
  - the terminal / not-started / completed holds
- **Reconciliation:**
  - each Δ band in §4.5
  - the hold expiring into a snap
  - displayed `s` is monotonic across 100 random fix sequences (property-style,
    seeded RNG)
- **Ingest:**
  - a duplicate `lastLocationUpdateTime` is a no-op
  - `activeTripID` mismatch → `.raw`
  - a vehicle ID change → reset
  - `lastLocationUpdateTime == 0` with a `lastUpdate` fallback
- **Skew:** the median, `Age` accounting, a future fix clamped to 0.
- **Model:** the `Double?` / `0 → nil` decode, plus `TripStopTime.distanceAlongTrip`.

### 8.2 Driver and rendering (hosted, `@MainActor`)

- `VehicleEstimationDriver` with `TestClock`:
  - the tick cadence
  - a pause on `clear()` and on a background notification
  - resume snaps
  - Reduce Motion steps
- `TripFocusMapLayer`: extend `TripFocusMapLayerTests` to cover these:
  - the estimate moves the existing annotation without remove/re-add (identity
    preserved, so callouts survive)
  - heading from `obaOrientation`
  - `.raw` falls back to `Content.vehicleCoordinate`
- `TripFocusMapDisplayModel`: a tick changes `vehicle` and not `display`
  (polylines are not rebuilt).

### 8.3 Replay and offline evaluation

1. **Recorder (Phase 0, DEBUG builds only).** A debug-menu toggle appends each
   trip-page poll's raw JSON, with the device receive time and the `Age` header,
   to `Documents/vehicle-replays/<tripID>-<date>.jsonl`. It runs on device, on
   real routes: at least one Java region (Puget Sound) and one maglev region,
   covering downtown, freeway/express, and a loop route.
2. **Fixtures.** Curated replays are committed under
   `OBAKitTests/fixtures/vehicle-replays/`, each with its shape and trip details.
   They must be small: trimmed to ~20 fixes each.
3. **Metric.** For each consecutive pair of distinct fixes `(f_i, f_{i+1})`,
   predict the position at `f_{i+1}.fixTime` using only fixes ≤ `f_i` and the
   data received by `f_i`'s receipt time. Error = haversine to
   `f_{i+1}.lastKnownLocation`, also reported along-shape. Report the median and
   p90, bucketed by the prediction horizon (`f_{i+1}.fixTime − f_i.fixTime`), for:
   - **baseline A:** `f_i.lastKnownLocation` (today's trip page)
   - **baseline B:** `f_i.position` (today's stop-route-focus; R1)
   - **the estimator**
4. **Display-time error.** The rider sees the marker at `receipt + t`, not at
   `fixTime`. Also report the error at `f_i.receiptTime + 15 s`. That needs
   interpolating between fixes as ground truth, so it is labeled approximate.
5. **Gate.** The flag defaults on only if the estimator beats both baselines at
   the median **and** p90 in every bucket, on both servers.

## 9. Rollout and phases

**Phase 0: prerequisites and measurement.** Each item is its own PR.
- `lastKnownDistanceAlongTrip` decode fix (R2). Verify against a live maglev
  region's arrivals response first: if it reproduces, it is a P1 on its own.
- `TripStopTime.distanceAlongTrip`.
- The cache-policy parameter on `getData`.
- The replay recorder (DEBUG) and the evaluation harness, a test target helper
  that prints the §8.3 table.
- Collect replays. Decide the tunables. Decide R1 (whether the trip page should
  use `position` in `.raw` mode on maglev, where it is GPS-on-shape).

**Phase 1: trip page estimator, behind a flag.**
- `FeatureFlags.estimatesVehiclePositionsKey = "OBAEstimatesVehiclePositions"`,
  default off, with a toggle in Settings › Experimental (`SettingsView.swift:95`).
  Unlike the other flags it is read live by the driver: no relaunch needed.
- A debug-menu toggle "Show raw fix" (`SettingsView` Debug section,
  `SettingsView.swift:181`). It draws a small hollow dot at `lastKnownLocation`
  and a second at `position` next to the estimate, on both map hosts, and puts
  the age and mode in the callout or a debug label.
- Both map hosts. `TripViewController` (legacy) unchanged.

**Phase 2: stop-route-focus vehicles.** Each vehicle needs its own trip's shape
and schedule.
- Shapes: `ShapeCache`, keyed by the trip's `shapeID`, not the route's.
- Schedule: one `trip-details` per drawn vehicle, cached per trip (§0.1: a
  `trips-for-route` is ~280 KB). A vehicle whose schedule fails falls back to
  its observed speed.
- Re-measure the 50-vehicle cost (§6.4).

**Phase 3 (future, not scoped).** A 1-D Kalman filter over `(s, v)` along the
shape, replacing §4.3–4.4 with the same inputs and outputs. The process noise
comes from the schedule pace and the observation noise from the projection
offset. Alternatively, the server could supply historical segment speeds.
`VehiclesMapView` (raw GTFS-RT) stays out unless OBA trip matching is added.

## 10. Open questions

Settled: the fix-age distribution and `position` versus GPS on Java (§0.1), and
skew handling (`currentTime` + `Age`). Still open:

1. Does R2 reproduce against a live maglev region? The fix ships regardless.
2. Replays from a maglev region, where `position` is GPS on the shape, before the
   flag defaults on there.
3. Does SwiftUI `Map` animate an `Annotation`'s coordinate change inside
   `withAnimation`? The panel publishes each tick inside one, but Apple's docs
   don't say whether `Annotation` interpolates.
4. Does re-splitting the shape every 5 s on `MKMapView` flicker or cost arrow
   layout (§6.2)?
5. Should dwell be skipped at stops with no boardings expected? That would need
   pickup/drop-off types, which are not in the API.
6. Visual design for the staleness halo and the frozen state (§6.5). With fixes
   ~70 s old on arrival, the 45 s aging threshold puts most markers in the halo
   state; the threshold may want to move once the visuals are reviewed.
7. The horizon (120 s) against arrival ages of ~70–85 s leaves 35–50 s of
   extrapolation per fix. The replay shows that is a net win; a longer horizon
   is worth testing on the same fixtures.
