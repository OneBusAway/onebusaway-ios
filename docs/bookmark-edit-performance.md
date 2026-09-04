# Bookmark edit performance

Editing the Bookmarks list used to freeze the UI for several seconds once a
rider had more than about ten bookmarks (#548). Moving or deleting one item
rewrote the whole bookmark plist once per remaining row: `bookmarks` get
decodes the array, `bookmarks` set encodes it, and `add(_:to:index:)` /
`delete(bookmark:)` looped that round-trip.

Those methods now decode once, reorder in memory, and encode once.

Existing sort-order tests in `UserDefaultsStore_BookmarksTests` still define
the grouping and `sortOrder` contract. Two new tests count writes to the
`UserDataStore.bookmarks` key and fail if the per-row loop is restored.
