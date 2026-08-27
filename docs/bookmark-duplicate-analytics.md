# Duplicate bookmark confirmation analytics

Adding a trip bookmark that already exists shows a "Duplicate Bookmark" alert.
Analytics for `addBookmark` fire only if the rider confirms.

`EditBookmarkViewModel.resolveDuplicate(.cancelled)` is a no-op: it does not
write to the store and does not report analytics. Confirming calls
`persistNew`, which is what emits the event.

This is the #1138 behavior change. The test
`Cancelling duplicate confirmation does not persist or report analytics` is
the regression lock for it (#1145).
