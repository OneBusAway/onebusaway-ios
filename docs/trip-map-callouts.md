# Trip map stop selection

Trip-map stop pins have no MapKit callout (`TripMapAnnotationPolicy`). A rider
tap on a pin opens that stop. Opening a trip from a departure auto-selects the
origin pin; that programmatic select must not push the stop back on top.

## Skip flag

`TripViewController.skipNextStopTimeHighlight` is armed on every programmatic
assignment of `selectedStopTime` (first load, and `showStopOnMap` from the
list). `mapView(_:didSelect:)` consumes the flag and skips `openStop`. It
still deselects the pin: MapKit will not re-fire `didSelect` for an
already-selected annotation, and the first tap on the origin stop would
otherwise do nothing.

A value-equal assignment (same `TripStopTime` on a 30s refresh) clears the
flag in `selectedStopTime`'s `didSet` so a leaked arm cannot swallow the next
tap.

`didSelect` also skips `highlightStopInList` when the flag is set. The origin
pin is not highlighted in the trip list on load.

## Refresh

`$tripDetails` republishes about every 30 seconds. `applyOriginStopSelection`
writes the origin only on the first load, or while the origin is still the
selected stop. After the rider deselects (`didDeselect` → `selectedStopTime =
nil`) or picks another stop, a later emission leaves that choice alone.

## Deselect after open

`openStop` deselects the annotation on the `MKMapView` MapKit passed into
`didSelect` (same pattern as `MapViewController`). Come back from the stop
page and the same pin can be tapped again.

Tests must not load `TripViewController.view` (`viewDidLoad` reads an
unresolved `ArrivalDeparture.route`).
