# Compact stop and trip pages

A rider asked for a more space-saving stop and trip layout (#1278). It is
opt-in and **off by default**.

## Setting

Settings → Accessibility → **Compact stop and trip pages**.

When on, the new stop page (departure rows, grouped cards) and the new trip
page (header card, stop timeline) read tighter spacing from `StopTripSpacing`.
Accessibility-size stacked layouts use the same table — compact is opt-in, so
tighter AX stacks are intentional. A compact trip-stop row is shorter than
44pt at default Dynamic Type; its tap target is the row itself. Do not put
`.frame(minHeight: 44)` on the row — that reports 44pt to the stack and clamps
compact and regular to the same height at default Dynamic Type, so compact
saves nothing on the timeline. Do not add canceling slop either — overlapping
hit rects in a `LazyVStack(spacing: 0)` open the neighbouring stop.

No arrivals, occupancy, or actions are hidden. This is spacing only.

The `@AppStorage` key is `stopTripCompactMode` (dot-free, same KVO constraint
as `stopUIReducedColors`). The trip page hosts through `TripPageRootView`,
which applies `.defaultAppStorage` to the app-group suite — a bare
`@AppStorage` would read `UserDefaults.standard` and ignore the Settings toggle.
