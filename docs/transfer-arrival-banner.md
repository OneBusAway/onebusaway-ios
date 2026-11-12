# Transfer trip highlight

When a rider taps a stop on a trip, that stop can be treated as a transfer
destination. How that looks depends on whether the Settings toggle is on.

## Setting

Settings → Arrival & Departure Display → **Highlight your trip on stop pages**
(`UserDataStore.highlightTransferTrip`). Default **on**, so existing riders keep
transfer UX unless they opt out. The value is still stored under the
`showTransferArrivalBanner` defaults key from when the toggle also drove a
banner, so riders who turned it off keep that choice.

When the switch is off, `UserDataStore.displayedTransferContext(_:)` (a Swift
protocol extension — `TransferContext` cannot appear on the `@objc` protocol)
returns `nil`. Routers and stop screens then treat the stop as ordinary: no
highlight.

## Stop page

`Router.makeStopController` builds `StopPageViewController` and passes the
*effective* transfer context (nil when the toggle is off).

On that page, a non-nil context with `fromTripID` **highlights** departure rows
whose `tripID` matches — brand-tint background plus a leading accent bar. Times
stay absolute (live stop clocks).

`TransferContext.from(arrivalDeparture:arrivalDate:)` copies
`arrivalDeparture.tripID` into `fromTripID`. Selection is pure:
`TransferTripHighlight.tripID(from:)` / `shouldHighlight(tripID:context:)`.
