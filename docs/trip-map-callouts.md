# Trip map stop selection

Trip-map stop pins have no MapKit callout (`TripMapAnnotationPolicy`). A rider
tap on a pin opens that stop. Opening a trip from a departure auto-selects the
origin pin; that programmatic select must not push the stop back on top.

## Skip flag

`TripViewController.skipNextStopTimeHighlight` is armed on every programmatic
assignment of `selectedStopTime` (first load, and `showStopOnMap` from the
list). `mapView(_:didSelect:)` consumes the flag and skips `openStop`.

A value-equal assignment (same `TripStopTime` on a 30s refresh) clears the
flag in `selectedStopTime`'s `didSet` so a leaked arm cannot swallow the next
tap.

## Refresh

`$tripDetails` republishes about every 30 seconds. `applyOriginStopSelection`
writes the origin only on the first load, or while the origin is still the
selected stop. After the rider deselects (`didDeselect` → `selectedStopTime =
nil`) or picks another stop, a later emission leaves that choice alone.

`didSelect` still skips list highlight and the floating-panel move when the
flag is set: those share the same `didSelect` entry. The origin pin is
selected on the map. Tests must not load `TripViewController.view`
(`viewDidLoad` reads an unresolved `ArrivalDeparture.route`).
