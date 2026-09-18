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

Empty `tripID` is a wildcard in `tracksSameTrip`: if either side is empty, the
comparison falls back to stop + route + headsign. That keeps bookmark identity
unpinned while still letting `Activity.running(matching:)` reconcile a bookmark
card with a stop-page card for the same stop/route/headsign (the cross-path
guard from 89a47ff).

When a stop-page activity's pinned trip leaves the arrivals list, refresh falls
back to rebuilding from the unpinned list (degradation): the card may show a
different vehicle. Re-Tracking from the stop page currently promotes relevance
score only via `running(matching:)` — it does not rewrite content state — so
degradation is repaired on the next successful pinned refresh (or a new activity
if the existing one has ended), not by the promote alone.

Relaunch re-registration in `updateRunningLiveActivities()` passes the same
primary arrival `buildRefreshContentState` uses (pinned trip when present) as
`LiveActivityTracker` metadata, so OBACloud push stays on the tracked vehicle
rather than the soonest bookmark arrival.

Opposite-direction mixing (#1326) cannot happen once the stop-page key is the
trip itself. Loop routes that visit a stop twice under the same `tripID` can
still match the wrong visit on refresh until `StaticData` carries more identity
fields; that is out of scope here.
