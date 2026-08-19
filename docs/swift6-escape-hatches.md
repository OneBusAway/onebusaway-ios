# Swift 6 escape hatches unwound in #1198

Follow-up to the Swift 6 migration plan (`docs/swift6-migration-plan.md`) and
issue #1198. This change only takes hatches that are compiler-checked today
without new factories or Apple annotations.

## Done

- `ArrivalDeparture.route`, `.stop`, and `.trip` are `public private(set)`.
  `loadReferences` remains the only writer, which is the HasReferences
  "read-only after handoff" contract. Covered by
  `ArrivalDepartureTests` `Load references`.
- `StopArrivals.stop` is the same.
- `DecodingErrorReporter.reportHandler` is a `Mutex` instead of
  `nonisolated(unsafe)` plus `NSLock`. Existing
  `DecodingErrorReporterTests` still drive get/set/`report`.

## Left alone on purpose

- `Trip.route` stays a public `var`. `TripTests` assign it because `References`
  has no public memberwise factory.
- `UncheckedSendableBox` stays. MapKit's `MKDirections.Request` /
  `MKLookAroundSceneRequest` still need a sole-owner hop at
  `MapRegionManager.handleMapFeatureSelection` and `MapItemViewModel.fetchScene`.
- `AnalyticsOrchestrator.userDefaults`, `Icons.iconCache`, and other
  `NSCache` / `UserDefaults` marks wait on Apple `Sendable` annotations.
