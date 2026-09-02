# Trip map stop selection

Trip-map stop pins have no MapKit callout (`TripMapAnnotationPolicy`). A rider
tap on a pin opens that stop. Opening a trip from a departure auto-selects the
origin pin; that programmatic select must not push the stop back on top.

## Skip flag

`TripViewController.skipNextStopTimeHighlight` is armed by `selectedStopTime`'s
`didSet`, immediately before the `selectAnnotation` it is there to cover.
`mapView(_:didSelect:)` consumes the flag and skips `openStop`. It still
deselects the pin: MapKit will not re-fire `didSelect` for an already-selected
annotation, and the first tap on the origin stop would otherwise do nothing.

Arming at the `selectAnnotation` call site rather than at the assignment's
callers is what keeps the flag from leaking. An assignment that finds no
matching annotation — a stop the map has not been given yet — makes no
selection, so there is no `didSelect` to consume an arm, and a leftover arm
would swallow the rider's next real pin tap.

`didSelect` also skips `highlightStopInList` when the flag is set. The origin
pin is not highlighted in the trip list on load.

## What load actually does

There are two programmatic assignments: `applyOriginStopSelection` on the first
`$tripDetails` emission, and `showStopOnMap` from a "Show on map" list action.
Both tear themselves down inside their own call stack — `didSelect` consumes the
skip and deselects, and `didDeselect` sets `selectedStopTime = nil`. So
`selectedStopTime` is nil at every point the rider can observe, and neither the
origin pin nor its list row stays highlighted after load.

## Refresh

`$tripDetails` republishes about every 30 seconds. `applyOriginStopSelection`
writes the origin on the first load only, tracked by
`hasAppliedOriginStopSelection`. That flag is set after the origin stop time is
found, so an early emission that cannot supply one does not burn the single
attempt. Later emissions do nothing: re-selecting would fire `didSelect` →
`openStop` and push the stop page out from under whatever the rider is doing.

## Deselect after open

`openStop` deselects the annotation on the `MKMapView` MapKit passed into
`didSelect` (same pattern as `MapViewController`). Come back from the stop
page and the same pin can be tapped again.

It also reports `AnalyticsLabels.mapStopAnnotationTapped` against
`app://localhost/trip` — the same "selection is the open gesture" case
`MapViewController` reports for callout-less stop annotations.

`didSelect` scrolls the list to the tapped stop but passes
`blinksAfterScroll: false`. The blink is delayed 750 ms for scrolling to settle,
which is under the stop page it is about to push, so the rider would never see
it. The scroll still leaves the row on screen for their return.

Tests must not load `TripViewController.view` (`viewDidLoad` reads an
unresolved `ArrivalDeparture.route`).
