# Duplicate bookmark confirmation analytics

Adding a trip bookmark that already exists shows a "Duplicate Bookmark" alert.
`addBookmark` fires only if the rider taps Create Duplicate.

The lock is the Cancel `UIAlertAction` installed by `EditBookmarkViewController.save()`.
`EditBookmarkViewModel.resolveDuplicate(.cancelled)` is a bare `return` and is not
a regression guard on its own (#1145 / review of #1320).
