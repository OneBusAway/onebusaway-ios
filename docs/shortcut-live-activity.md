# Shortcuts → Live Activity

#1222 asked for a Shortcut that starts a Live Activity for a stop and routes.
The app's Live Activities are already trip-shaped (stop + route + headsign),
and the only user-curated list of those is **trip bookmarks**.

## What a Shortcut does

1. The **Track Bookmark** App Intent (`openAppWhenRun = true`) writes the
   bookmark UUID into the app-group defaults via `LiveActivityShortcutRequest`.
   `store` posts `.liveActivityShortcutRequestDidStore`.
2. `openAppWhenRun` is equivalent to `supportedModes = .foreground(.immediate)`:
   the app is already frontmost **before** `perform()` runs. Lifecycle hooks
   (`applicationDidBecomeActive`, `rootUserInterfaceDidLoad`) therefore peek
   an empty queue. The store notification is what selects the Bookmarks tab
   on a warm launch. Cold launch still peeks from `rootUserInterfaceDidLoad`
   if the observer was not yet registered when `store` posted.
3. Once that bookmark's arrivals are in, the existing Track path starts (or
   promotes) the Live Activity. No `Activity` is captured into a `Task`.

Intents live in OBAKit. The app target includes them through
`OBAAppIntentsPackage` → `OBAKitAppIntentsPackage`. Without that chain,
Shortcuts never sees Track.

The App Shortcut phrase includes `$bookmark`. `OBAAppShortcuts.updateAppShortcutParameters()`
runs at launch and on `.bookmarksDidChange` so the donated list tracks the
current region's trip bookmarks.

Whole-stop bookmarks are omitted from the intent's entity query: they have no
single route to Track. Out-of-region trip bookmarks are omitted too — arrivals
only load for the current region, so offering them queued a request that never
started and hijacked the Bookmarks tab on every launch. The region filter
reads `RegionsService.currentRegionIdentifierUserDefaultsKey` (public
`nonisolated`), not a copied string.

A queued request expires after 90 seconds (and leftover ids without a timestamp
are dropped). `rootNavigateTo(page: .bookmarks)` selects the tab. Live
Activities disabled system-wide, or a region mismatch, clears the request and
logs a warning (no Track error alert — the rider is not on a Track tap).

Arbitrary stop IDs that are not bookmarked are out of scope for this change.

## Tests

`LiveActivityShortcutRequestTests` pin store / peek / expiry, that `store`
posts the drain notification, and that a still-fresh timestamp plus a
non-UUID string is treated as empty (not as a missing timestamp).
`BookmarkIntentMappingTests` pin trip-vs-whole-stop, the region filter, and
that the query reads the `RegionsService` key.
