# Polyline Direction Arrows

Route direction is shown with small heading-aware chevrons:

- On the remaining, untraveled shape in trip focus.
- On each colored route line in stop focus.
- Every 500 meters, beginning 500 meters from the start of the applicable shape.
- Capped at 24 chevrons per shape, with short end remainders omitted.
- Tinted and dimmed with the route line they annotate.

The chevrons indicate the direction encoded by the route geometry. They are
annotations over the existing colored core line, not additions to its white
casing.

`chevron.up` points north at identity. Compass heading is clockwise from north;
UIKit rotation is counter-clockwise, so the view transform is
`-heading.radians`. Using `CLLocationDirection.affineTransform` as-is would
point eastbound chevrons west.

This intentionally does not reproduce Transit App's vehicle-dots design. It
uses lightweight directional marks on OneBusAway's existing route polylines.
