# Compact stop and trip pages

A rider asked for a more space-saving stop and trip layout (#1278). It is
opt-in and **off by default**.

## Setting

Settings → Accessibility → **Compact stop and trip pages**.

When on, the new stop page (departure rows, grouped cards) and the new trip
page (header card, stop timeline) read tighter spacing from `StopTripSpacing`.
Accessibility-size stacked layouts are left alone.

No arrivals, occupancy, or actions are hidden. This is spacing only.

The `@AppStorage` key is `stopTripCompactMode` (dot-free, same KVO constraint
as `stopUIReducedColors`).
