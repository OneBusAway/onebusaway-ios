# Vehicle coordinate interpolation (#1109 / #1323 / #1341)

Between arrival polls the trip-page (and stop-route-focus) vehicle marker
interpolates when the hop is short, and snaps when it is not.

## Thresholds

`VehicleCoordinateUpdate` has three branches:

- `ignoreBelowMeters` — hops smaller than this are left alone (noise).
- interpolate — city-block hops animate for `animationDuration`.
- `snapBeyondMeters` (**500 m**) — longer hops teleport. A bit over one 30 s
  poll at ~50 km/h (city-traffic tuning). At *exactly* 500 m the comparison is
  `>`, so that hop still animates; freeway / express buses usually snap.

Docs and tests describe the constants, not a motorway-speed framing.

## Apply path

Callers that assign `VehicleAnnotation.tripStatus` must restore the previous
`coordinate` before `VehicleCoordinateUpdate.apply`, because `tripStatus`'s
`didSet` writes `lastKnownLocation` immediately and would otherwise skip the
animation. Used by:

- `TripFocusMapLayer.drawVehicle` (removes the pin when the feed omits a coordinate)
- `StopVehicleAnnotation.update`
- `TripViewController.currentTripStatus` (legacy trip screen; same remove-when-nil
  policy as the focus layer — fixed in #1341)
