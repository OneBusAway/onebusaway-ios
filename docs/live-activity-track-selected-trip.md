# Track pins the selected trip (#1334)

Stop-page / trip-panel Track builds Live Activity content from the selected
departure via `BookmarkActions.buildContentState(from:matching:)`, filtering by
that departure's identity (`$0.id == departure.id`, which includes `tripID`).
The stop-page start path stores that `tripID` in `TripAttributes.StaticData` so
`Activity.running(matching:)` and refresh can keep following the same vehicle.

Bookmark Track does **not** pin a `tripID` in `StaticData` — identity is
stop + route + headsign only — and refresh uses the unpinned multi-arrival
builder (up to three, soonest-first). Setting `tripID` from the first arrival
would roll over on refresh, break the duplicate guard, and collapse the card to
a single pinned arrival.

When a stop-page activity's pinned trip leaves the arrivals list, refresh falls
back to rebuilding from the unpinned list (degradation): the card may show a
different vehicle until the user re-Tracks from the stop page.

Opposite-direction mixing (#1326) cannot happen once the stop-page key is the
trip itself.
