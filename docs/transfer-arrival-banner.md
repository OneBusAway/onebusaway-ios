# Transfer arrival banner

When a rider taps a stop on a trip, the stop page can treat that stop as a
transfer: it shows an **Arriving at HH:MM via ROUTENAME** banner, hides
departures that already left before the rider arrives, and prints remaining
times relative to that arrival instead of the clock.

That is useful for connections. It is also the behavior #1277 asked to turn
off — relative "NOW" / "-5m" times and a filtered list are easy to misread as
the live stop.

## Setting

Settings → Arrival Display → **Show transfer arrival banner**. Default **on**,
so existing riders keep the current trip-to-stop flow.

When the switch is off, `UserDataStore.displayedTransferContext(_:)` (a Swift
protocol extension — `TransferContext` cannot appear on the `@objc` protocol)
returns `nil` and `StopViewController` renders the stop as a normal stop:
wall-clock times, walk-time row, full departure list.

The new stop page still does not implement transfer UX. With the toggle **on**,
`Router.makeStopController` sends a real transfer to the legacy screen. With it
**off**, `displayedTransferContext` is nil at the routing boundary too, so a
trip→stop tap uses the new stop page like any other stop.
