# Duplicate trip-stop list identifiers

A loop route visits the same stop twice. `TripStopViewModel.id` was the
bare `stop.id`, so `NSDiffableDataSource` saw two rows with the same
item identifier and crashed. That is the App Store crash in #538.

The SwiftUI trip page already qualifies ids by position
(`TripStopListModel.Row.id` is `"\(index)-\(stopID)"`). The UIKit trip
list now uses the same format.

`Equatable` includes `id`, matching the protocol's "all values, including
the identifier" rule. Two visits to one stop are no longer equal.

Tests do not load `TripViewController.view`.
