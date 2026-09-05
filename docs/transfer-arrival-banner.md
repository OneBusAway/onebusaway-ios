# Transfer arrival banner / trip highlight

When a rider taps a stop on a trip, that stop can be treated as a transfer
destination. How that looks depends on which stop page is showing and whether
the Settings toggle is on.

## Setting

Settings → Arrival & Departure Display → **Show transfer arrival banner**.
Default **on**, so existing riders keep transfer UX unless they opt out. The
footer in every locale starts with that switch title verbatim.

When the switch is off, `UserDataStore.displayedTransferContext(_:)` (a Swift
protocol extension — `TransferContext` cannot appear on the `@objc` protocol)
returns `nil`. Routers and stop screens then treat the stop as ordinary:
wall-clock times, walk-time row, full departure list, no highlight.

## New stop page (feature flag on)

`Router.makeStopController` always builds `StopPageViewController` when
`FeatureFlags.isNewStopPageEnabled` is true, and passes the *effective*
transfer context (nil when the toggle is off).

On that page, a non-nil context with `fromTripID` **highlights** departure rows
whose `tripID` matches — brand-tint background plus a leading accent bar. Times
stay absolute (live stop clocks). Relative “NOW” / “-5m” banner timing is not
used here.

`TransferContext.from(arrivalDeparture:arrivalDate:)` copies
`arrivalDeparture.tripID` into `fromTripID`. Selection is pure:
`TransferTripHighlight.tripID(from:)` / `shouldHighlight(tripID:context:)`.

## Legacy stop page (feature flag off)

The same effective context still drives the legacy **Arriving at HH:MM via
ROUTENAME** banner on `StopViewController`: it hides departures that left before
the rider arrives and prints remaining times relative to that arrival.
