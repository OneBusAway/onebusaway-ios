# Rental fuel label dark mode (#1364)

## Cause
MapKit `RentalAnnotationView` painted the fuel figure in `rentalPurple` with a
**white** layer shadow. On dark / satellite tiles that pair ghosts out.
SwiftUI `RentalMapMarker` had the same problem with purple + adaptive
`systemBackground` shadow.

Hardcoding white + a soft `CALayer` shadow moved the failure to the app's
default case: light appearance on `.mutedStandard` (near-white tiles), where a
blurred halo never reaches full opacity behind a thin caption glyph.

## Fix
White fill with a real black outline on both renderers:

- **UIKit:** `NSAttributedString` `strokeColor` / negative `strokeWidth` (same
  idiom as `StopAnnotationView.strokedText`) — not a Gaussian shadow.
- **SwiftUI:** `MapLabelOutline` in black around white `.caption.bold()` text —
  the existing stand-in for glyph stroke used by panel stop labels.

Choice: fixed white+black outline rather than appearance/basemap switching,
so one treatment stays readable on Standard, Hybrid, and Satellite without
tracking map type.

Screenshots for #1364 live on the GitHub issue, not in `docs/`.
