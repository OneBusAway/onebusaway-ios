# More Floating Button — Design

**Branch:** `feature/more-floating-button`
**Reference:** [PR #1166 — Weather overlay](https://github.com/OneBusAway/onebusaway-ios/pull/1166/changes) (established the floating-button + overlay pattern this feature mirrors)
**Date:** 2026-07-02

## Goal

Add a top-trailing floating "More" button to `MapPanelRootView`, and route its tap through the existing sheet coordinator to a wiring `UIViewControllerRepresentable` that hosts the current UIKit `MoreViewController`. The wiring is a deliberate bridge until the More screen is rewritten in SwiftUI.

## Non-goals

- Modifying `MoreViewController` internals. The wrapper exists precisely to leave it untouched.
- Building a SwiftUI `MoreView`. Deferred to a follow-up.
- Adding a programmatic close hook from `MoreViewController` back into the sheet coordinator. Not needed today; added only when a concrete use case appears.
- Adding a new feature flag. The button appears whenever `MapPanelRootView` renders, which is itself gated by `FeatureFlags.useMapPanelExperienceKey`.

## Architecture

Three additions inside `OBAKit/`:

### `MoreButton` (SwiftUI)

- Location: `OBAKit/Sheet/Root/MoreButton.swift`
- Sibling to the `WeatherButton` introduced in #1166.
- Renders an SF Symbol (`line.3.horizontal`) inside a capsule with `regularGlassEffectIfAvailable(in: Capsule())` — iOS 26 Liquid Glass, `.regularMaterial` fallback pre-26.
- Purely presentational: takes a `() -> Void` action closure. No state, no VM.
- Accessibility label localized as "More" (existing `more_controller.title` string is reused).

### `MoreSheetHost` (`UIViewControllerRepresentable`)

- Location: `OBAKit/Sheet/Root/MoreSheetHost.swift`
- Wraps `UINavigationController(rootViewController: MoreViewController(application:))`.
- The `UINavigationController` is required — `MoreViewController` wires up `navigationItem.leftBarButtonItem` ("Contact Us") and `navigationItem.rightBarButtonItem` ("Settings") in its initializer, and both are dead unless a nav bar is on screen.
- Owned by the SwiftUI view identity of `AppSheetRoute.more`: created once per push, torn down when the sheet dismisses.
- Deliberately minimal:
  - No SwiftUI-side close button. The `.more` route's `SheetDetentConfiguration` already has `isDismissDisabled: false`, so the drag-down handle is the dismissal (consistent with the other stacked routes).
  - Empty `updateUIViewController(_:context:)`: `MoreViewController` reads `application` and its stores directly, so nothing SwiftUI-side changes over the sheet's lifetime.

```swift
struct MoreSheetHost: UIViewControllerRepresentable {
    let application: Application

    func makeUIViewController(context: Context) -> UINavigationController {
        let more = MoreViewController(application: application)
        return UINavigationController(rootViewController: more)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) { }
}
```

### `AppSheetViewFactory.moreView()`

- The `.more` case moves out of the shared `unimplementedView(for:)` branch into a real per-route builder that returns `MoreSheetHost(application: application)`.
- No change to `AppSheetRoute` (the case already exists) and no change to `SheetCoordinator`.

## Wiring in `MapPanelRootView`

- Add `.overlay(alignment: .topTrailing) { moreButton }` mirroring where `WeatherButton` sits at `.topLeading` in #1166.
- `moreButton`'s action calls `coordinator.push(.more)`.
- No local `@State` presentation bool — presentation lives in the coordinator, so `AppSheetRoute.more.detentConfiguration` (already `[.medium, .large]`, initial `.large`, `prefersStacking: true`) drives the sheet automatically.
- Padding matches `WeatherButton`: `ThemeMetrics.controllerMargin`.

## Glass modifier

`regularGlassEffectIfAvailable(in:)` is introduced on `View` in `OBAKit/Extensions/SwiftUIExtensions.swift` with the same signature as #1166:

```swift
@ViewBuilder
func regularGlassEffectIfAvailable(in shape: some Shape = Capsule()) -> some View {
    if #available(iOS 26.0, *) {
        self.glassEffect(.regular, in: shape)
    } else {
        self.background(.regularMaterial, in: shape)
    }
}
```

If #1166 lands first, resolution is trivial — identical modifiers, keep one.

## Data flow

```
User taps MoreButton (topTrailing overlay on MapPanelRootView)
        │
        ▼
coordinator.push(.more)               // existing SheetCoordinator
        │
        ▼
AppSheetViewFactory.view(for: .more) → moreView()
        │
        ▼
MoreSheetHost (UIViewControllerRepresentable)
        │
        ▼
UINavigationController
        │
        └── MoreViewController(application:)   // unchanged
                • navigationItem.leftBarButtonItem  → showContactUsDialog
                • navigationItem.rightBarButtonItem → showSettings
```

`MoreViewController` presents its own child VCs (Settings, Safari, Mail) via `present(_:animated:)`; those already work from any host and need no extra plumbing from the wrapper.

## Testing

- **`AppSheetRouteTests` extension** — assert `AppSheetViewFactory.view(for: .more)` returns a non-nil view (mirrors the pattern used for other factory branches today).
- **`MoreSheetHostTests` (new, XCTest)** — assert that `makeUIViewController(context:)` returns a `UINavigationController` whose `topViewController` is a `MoreViewController`. The wrapping is the entire product surface of this type.
- **No test for `MoreButton`** — it's a `Button` around an SF Symbol and a closure. Snapshot testing is not part of this project's suite.
- **Manual verification** — boot the app with the map-panel feature flag enabled:
  1. Tap the top-trailing button; sheet presents at `.large`.
  2. Verify "Contact Us" (left) and "Settings" (right) bar buttons work.
  3. Drag the sheet down to dismiss; verify no orphaned VC state.
  4. Verify the button hit target does not overlap the top-leading weather slot (once #1166 lands).

## Merge considerations

- The `regularGlassEffectIfAvailable` modifier is introduced here even though #1166 is not yet merged. If #1166 lands first, the merge conflict is a duplicate modifier — resolved by keeping one copy.
- `MapPanelRootView`'s overlay change is additive (`.overlay(alignment: .topTrailing)`), orthogonal to #1166's `.topLeading` overlay. Both can coexist post-merge without further work.
- No changes to `AppSheetRoute`, `SheetCoordinator`, or `FloatingSheetContainer` — the design deliberately stays inside the existing seams.

## Follow-ups (out of scope)

- Rewrite `MoreView` in SwiftUI; swap `MoreSheetHost` for the native view in the factory.
- Introduce a `@Environment(\.dismiss)`-style bridge if a nav action inside More ever needs to close the containing sheet.
- Consolidate glass modifier(s) once #1166 lands.
