# Live Activity stale chrome (#1376)

ActivityKit sets `context.isStale` once `staleDate` passes. Promote/demote and
push paths already preserve that marker; the widget must show it.

- Lock screen: `TripLiveActivityCardView(isStale:)` dims content and shows
  `LiveActivityStaleChrome.warningText` (orange warning).
- Dynamic Island: same opacity helper; compact/minimal swap the route chip for
  a warning glyph when stale.

Copy and opacity live in `LiveActivityStaleChrome` so the two surfaces cannot
drift. Creating an activity with `staleDate: nil` until the first push is
intentional and unchanged.
