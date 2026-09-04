# Track pins the selected trip (#1334)

Stop-page / trip-panel Track used to build Live Activity content from every
same-route/headsign arrival (up to three), sorted soonest-first. Picking a
later vehicle still showed the earlier “next train” as the headline.

`BookmarkActions.buildContentState(from:matching:)` filters by the tracked
departure's identity (`$0.id == departure.id`, which includes tripID). Bookmark
refresh and `Activity.running(matching:)` thread the same `tripID` through
`TripAttributes.StaticData` and `tracksSameTrip`, so a foreground reload or a
second Track tap cannot clobber or promote the wrong vehicle.

Opposite-direction mixing (#1326) cannot happen once the key is the trip itself.
