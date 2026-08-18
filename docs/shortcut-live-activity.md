# Shortcuts → Live Activity

#1222 asked for a Shortcut that starts a Live Activity for a stop and routes.
The app's Live Activities are already trip-shaped (stop + route + headsign),
and the only user-curated list of those is **trip bookmarks**.

## What a Shortcut does

1. The **Track Bookmark** App Intent (`openAppWhenRun = true`) writes the
   bookmark UUID into the app-group defaults via `LiveActivityShortcutRequest`.
2. The app comes to the foreground and selects the Bookmarks tab so
   `BookmarksViewController` loads arrivals.
3. Once that bookmark's arrivals are in, the existing Track path starts (or
   promotes) the Live Activity. No `Activity` is captured into a `Task`.

Whole-stop bookmarks are omitted from the intent's entity query: they have no
single route to Track. Arbitrary stop IDs that are not bookmarked are out of
scope for this change.

## Tests

`LiveActivityShortcutRequestTests` pin store / peek / take. ActivityKit itself
is not injectable; the start path is the same code the Bookmarks Track action
already uses.
