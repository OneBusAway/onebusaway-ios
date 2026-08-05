# Trip Page Rethink — SwiftUI Trip View & Whole-Trip Map Focus — Design

**Date:** 2026-07-31
**Branch:** `route-projection`
**Deployment target:** iOS 18.0 (`Apps/Shared/app_shared.yml`)
**Source of truth for visuals:** design screenshot supplied by the product owner (Claude Design project "OBA iOS", `trip-focus.jsx`). The `.jsx` itself was not reachable from this session; layout below is transcribed from the screenshot and reconciled against components already shipping on this branch.
**Predecessor specs:** `2026-07-10-stop-page-rethink-design.md` (built the shared departure components this consumes), `2026-07-31-map-stop-selection-design.md` (built `StopMapFocus` / `StopRouteFocusMapLayer`, and deferred this work at its line 439).

## Summary

Replace `TripViewController` — a full-screen `MKMapView` that adds its *own*
`OBAFloatingPanelController` as a child — with a SwiftUI page that draws no map
at all, plus a map layer that puts the map it sits over into **whole-trip
focus**: only this trip's shape, split into a dimmed *spent* portion behind the
vehicle and a route-colored *ahead* portion, with a ring dot per stop and a
terminal marker at the last one.

The nested-panel structure is the reason the current screen is unusable when
pushed into the stop sheet: a floating panel inside a floating panel. Restyling
cannot fix it. The page has to stop owning a map.

## Decisions made (with rationale)

| Decision | Choice | Why |
|---|---|---|
| Page hosting | `TripPageViewController: UIHostingController<TripPageView>`, host-agnostic | The page never touches `MKMapView`. It publishes to a `TripMapFocus` and lets whoever owns a map render it. |
| Off-sheet entry points | A second host, `TripMapHostViewController`, owning an `MKMapView` + panel | Eight of nine entry points push full-screen with no map behind them. One page implementation, two hosts, one map layer. Decided with the product owner over rewiring all callers to present sheets. |
| Map rendering | New `TripFocusMapLayer`, a `MapLayer` conformer | Same seam `StopRouteFocusMapLayer` uses; `MapLayer.swift:60-64` names route shapes and vehicles as expected conformers. |
| Sheet↔map channel | `TripMapFocus`, mirroring `StopMapFocus` | One published value, one writer, no way for two input surfaces to disagree. Always non-nil; an unattached page gets an inert instance. |
| Spent/ahead split | `TripStatus.distanceAlongTrip / totalDistanceAlongTrip` | Already on the model the page fetches. No new network call, and it is the same number the vehicle marker is positioned from. |
| Stop list | All stops (`TripDetails.stopTimes`), not the 5-stop approach window | The design's section header reads **ALL 16 STOPS**. `ApproachSlice`'s windowing is a stop-page-panel concern and stays there. |
| Card content | Reuse `RouteBadgeView`, `CountdownView`, `DepartureStatus`, `OccupancyBadge`, `DepartureTimeText` | The design's trip card is `DepartureRowView`'s content plus a provenance footer. Rebuilding it would fork the visual language mid-branch. |
| Live Activity | Reuse the existing `startLiveActivity(_:)` path | `StopPageView.swift:42` and `LiveActivityTracker` already ship it; the design only changes where the button lives. |

## Layout (from the design)

Top ~30% is map. The rest is the sheet:

1. **Back row** — circular chevron button + the originating stop's name
   (`3rd Ave & Union St`). Plain, light. Replaces today's blue/green gradient
   title bar entirely.
2. **Trip card** (white, rounded, inset) — route badge; headsign (`Downtown
   Seattle`) bold; scheduled time struck through beside the predicted time and
   a colored adherence clause (`1 min late`); occupancy badge; a big countdown
   with the realtime glyph at trailing; and a secondary footer line reading
   `{route} · Vehicle {id} · position updated {n}s ago`.
3. **Section header** — `ALL {n} STOPS`, uppercase caption, secondary.
4. **Stop list** (white, rounded) — line-and-dot per stop with the stop name and
   its scheduled time, right-aligned. Stops at or behind the vehicle are gray;
   ahead are route-colored; the rider's stop is emphasized; the vehicle's
   position carries the transport glyph.
5. **Action bar** (pinned, outside the scroll) — full-width green **Live
   Activity — track on Lock Screen**, then a row of three: **Add bookmark**,
   **View schedule**, **Add alarm**.

## Map focus

`TripFocusMapLayer` renders, and nothing else:

- The trip shape as two overlays — spent (gray, behind the vehicle) and ahead
  (route color) — split at the vehicle's fractional progress along the trip.
- One ring dot per stop, gray behind the vehicle and route-colored ahead.
- The vehicle marker (existing `PulsingVehicleAnnotationView`).
- A terminal marker at the final stop.

Camera fits the ahead portion. On the stop sheet, pushing the page swaps the map
from stop focus to trip focus; popping restores it.

## Degradation

- No `shapeID`, or the shape fetch fails → no line; dots, vehicle, and the whole
  page still render.
- No `tripStatus` (schedule-only trip) → no split, no vehicle marker; the entire
  shape draws in route color and no stop is marked as passed.
- `totalDistanceAlongTrip <= 0` → treated as no split rather than dividing by
  zero.
- No `arrivalDeparture` (trip reached from vehicle search) → no rider's-stop
  emphasis and no alarm action; everything else renders.

## Testing

Pure-value first, per TDD: the shape split and the stop-list derivation are
plain functions over model values and carry the bulk of the logic. The layer is
exercised against a real `MKMapView` the way `StopRouteFocusMapLayerTests`
already does. SwiftUI views are covered through their models, not by snapshot.

## Out of scope

- Changing the stop page, the map tab, or `StopRouteFocusMapLayer`'s own behavior
  beyond yielding the map while a trip is focused.
- The `Trip.shapeID` release note already outstanding on this branch.
