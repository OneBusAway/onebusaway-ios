# Duplicate trip-stop list identifiers

A loop route visits the same stop twice. `TripStopViewModel.id` was the
bare `stop.id`, so `NSDiffableDataSource` saw two rows with the same
item identifier and crashed. That is the App Store crash in #538.

The SwiftUI trip page already qualifies ids by position
(`TripStopListModel.Row.id` is `"\(index)-\(stopID)"`). The UIKit trip
list now uses the same format.

`Equatable` includes `id`, matching the protocol's "all values, including
the identifier" rule. Two visits to one stop are no longer equal.

The tests exercise `TripStopViewModel` directly and do not load
`TripViewController.view`, so they pin the identifier contract rather than
the `NSDiffableDataSource` apply that #538 crashed in. The whole-trip test
doubles the fixture out-and-back, because the fixture's own stops are all
distinct and would satisfy a bare `stop.id` identifier too.
