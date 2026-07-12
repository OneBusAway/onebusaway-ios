# Add floating More button to SwiftUI map panel

## Summary

Adds a top-trailing floating "More" button to `MapPanelRootView` that pushes `AppSheetRoute.more` onto the SwiftUI sheet coordinator. The route is bridged to the existing UIKit `MoreViewController` via a new `MoreSheetHost` representable, so the More screen becomes reachable from the SwiftUI composition root without duplicating any of its functionality.

This is a wiring change only — no product behavior in `MoreViewController` moves. The `MoreSheetHost` wrapper is deliberately thin so a future SwiftUI `MoreView` can drop in at `AppSheetViewFactory.moreView()` without touching the coordinator, the route enum, or the overlay button.

## What's in the branch

- `MoreButton` — a stateless SwiftUI capsule button rendered in the map's top-trailing overlay slot. Uses the new `regularGlassEffectIfAvailable(in:)` modifier so it picks up Liquid Glass on iOS 26+ and falls back to `.regularMaterial` on older systems.
- `MoreSheetHost` — a `UIViewControllerRepresentable` that wraps `MoreViewController` in a `UINavigationController` so its `navigationItem` bar buttons render correctly when reached via a sheet route. Exposes an `internal` `makeNavigationController(application:)` factory seam so tests can exercise the wiring without going through `UIHostingController`'s lifecycle.
- `AppSheetViewFactory.moreView()` — new per-route branch returning `MoreSheetHost(application:)`, replacing the previous `unimplementedView` fallback for `.more`.
- `MapPanelRootView` — adds a `.overlay(alignment: .topTrailing) { moreButton }` slot; the button calls `coordinator.push(.more)`.
- `regularGlassEffectIfAvailable(in:)` — new `View` extension in `SwiftUIExtensions.swift` centralizing the iOS 26 Liquid Glass availability check for reuse by future floating controls.

## Tests

- `MoreSheetHostTests.test_makeNavigationController_wrapsMoreViewControllerInNav` — asserts the representable produces a `UINavigationController` rooted on a `MoreViewController`.
- `AppSheetViewFactoryTests.test_moreView_returnsMoreSheetHostForwardingApplication` — asserts the factory forwards its own `Application` into the host (identity check), guarding against future refactors that accidentally reconstruct or drop the reference.

## Test plan

- [ ] `xcodebuild test-without-building -only-testing:OBAKitTests/MoreSheetHostTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'` passes.
- [ ] `xcodebuild test-without-building -only-testing:OBAKitTests/AppSheetViewFactoryTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'` passes.
- [ ] Full unit test suite passes.
- [ ] On device / simulator with `MapPanelRootView` mounted: the More button renders in the top-trailing corner, tapping it presents the More screen with its navigation bar and bar-button items intact.
- [ ] Verified on iOS 26 (Liquid Glass render) and one earlier iOS (regularMaterial fallback).
- [ ] VoiceOver reads the button as "More".

## Notes for reviewers

- `MoreSheetHost.makeNavigationController(application:)` is `internal` on purpose — production code must go through `makeUIViewController`; the factory exists solely so the wiring can be unit-tested without a hosting-controller lifecycle. Marked in the doc comment.
- The `AppSheetViewFactory.moreView()` return type is `MoreSheetHost` today; the comment there flags that it should change when a SwiftUI `MoreView` lands.
