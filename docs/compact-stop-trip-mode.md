# Compact stop and trip pages

A rider asked for a more space-saving stop and trip layout (#1278). It is
opt-in and **off by default**.

## Setting

Settings → Accessibility → **Compact stop and trip pages**.

When on, the new stop page (departure rows, grouped cards) and the new trip
page (header card, stop timeline) read tighter spacing from `StopTripSpacing`.
Accessibility-size stacked layouts use the same table — compact is opt-in, so
tighter AX stacks are intentional. A compact trip-stop row is shorter than
44pt at default Dynamic Type; its tap target is the row itself. Do not add a
44pt overlay (`minHeight` or canceling slop) — overlapping hit rects in a
`LazyVStack(spacing: 0)` open the neighbouring stop.

No arrivals, occupancy, or actions are hidden. This is spacing only.

The `@AppStorage` key is `stopTripCompactMode` (dot-free, same KVO constraint
as `stopUIReducedColors`).
