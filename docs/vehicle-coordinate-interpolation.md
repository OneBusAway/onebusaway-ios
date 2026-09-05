# Vehicle coordinate interpolation (#1109 / #1341)

Between arrival polls the trip-page (and stop-route-focus) vehicle marker
interpolates when the hop is short, and snaps when it is not.

## Threshold

`VehicleCoordinateUpdate.snapBeyondMeters` is **500 m** — a bit over one 30 s
poll at ~50 km/h. That is a **city-traffic** tuning choice: a 30 s poll at
60 km/h is exactly 500 m, so freeway / express buses usually snap and degrade to
the old teleport behavior. Docs and tests describe the constant, not a
motorway-speed framing.

## Apply path

Callers that assign `VehicleAnnotation.tripStatus` must restore the previous
`coordinate` before `VehicleCoordinateUpdate.apply`, because `tripStatus`'s
`didSet` writes `lastKnownLocation` immediately and would otherwise skip the
animation. Used by:

- `TripFocusMapLayer.drawVehicle`
- `StopVehicleAnnotation.update`
- `TripViewController.currentTripStatus` (legacy trip screen; fixed in #1341)
