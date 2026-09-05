# Rental fuel label dark mode (#1364)

## Cause
MapKit `RentalAnnotationView` painted the fuel figure in `rentalPurple` with a
**white** layer shadow. On dark / satellite tiles that pair ghosts out.
SwiftUI `RentalMapMarker` had the same problem with purple + adaptive
`systemBackground` shadow.

## Fix
White text + black halo on both renderers, independent of color scheme.

## Screenshots
`docs/screenshots-1364/before-dark-satellite.jpg` · `after-dark-satellite.jpg`
