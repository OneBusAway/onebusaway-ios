# UIKit Weather Card via UIHostingController — Design

**Status:** Approved
**Branch:** `feature/new-weather-card-uikit`

## Motivation

The classic UIKit surface (`MapViewController`) still presents weather as a plain `UIAlertController` built from `WeatherDisplay.legacyAlert`. Meanwhile, the SwiftUI surface (`MapPanelRootView`) already renders the redesigned card — `WeatherDetailPopup` — with header, hourly strip, and stats row, all reading live from `MapViewModel.weatherDisplay`. Bringing the new card to the UIKit surface should reuse the existing SwiftUI views via `UIHostingController`, not reimplement them in UIKit.

## Scope

**In scope**
- Replace `MapViewController.showWeather()`'s `UIAlertController` code path with a `UIHostingController`-hosted SwiftUI card.
- Add a thin SwiftUI wrapper view (`WeatherDetailPopupHost`) that bridges `MapViewModel` into `WeatherDetailPopup`.
- Delete `WeatherDisplay+LegacyAlert.swift` and the tests that only cover it, since no caller remains once the rewrite lands.

**Out of scope**
- The `HoverBar` `weatherButton` (UIButton) and toolbar layout stay as-is.
- `MapPanelRootView` (SwiftUI surface) is not touched.
- `WeatherButton.swift` (SwiftUI pill) is not touched.
- `MapViewModel` structure is not restructured.
- No feature flag — `showWeather()` has one caller.

## Components

### 1. `WeatherDetailPopupHost` (new SwiftUI view)

Package-internal wrapper, roughly:

```swift
struct WeatherDetailPopupHost: View {
    @ObservedObject var viewModel: MapViewModel
    @State private var isPresented = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        WeatherDetailPopup(display: viewModel.weatherDisplay, isPresented: $isPresented)
            .onChange(of: isPresented) { _, newValue in
                if !newValue { dismiss() }
            }
    }
}
```

Responsibilities:
- Owns the `isPresented` `@State` binding that `WeatherDetailPopup` uses to run its scale + opacity exit transition.
- `@ObservedObject` on `MapViewModel` keeps `weatherDisplay` propagating live into the card, matching the SwiftUI path's "refresh under the user" behavior (see `MapPanelRootView.swift:31-33` and `WeatherDetailPopup.swift:62-68`).
- Uses SwiftUI's `@Environment(\.dismiss)` to close the hosting controller after `isPresented` flips to false, so the SwiftUI exit animation runs before UIKit tears the modal down. Because the card animates itself away first, the underlying UIKit dismissal is a no-op on a transparent view.

Lives near the other SwiftUI hosting bridges under `OBAKit/Sheet/Root/` or a sibling folder; concrete path to be chosen during implementation.

### 2. `MapViewController.showWeather()` rewrite

Replace the alert construction (`MapViewController.swift:434-445`) with roughly:

```swift
@objc private func showWeather() {
    guard weatherDisplay != nil else { return }
    let host = UIHostingController(
        rootView: WeatherDetailPopupHost(viewModel: viewModel)
    )
    host.modalPresentationStyle = .overFullScreen
    host.modalTransitionStyle = .crossDissolve
    host.view.backgroundColor = .clear
    present(host, animated: true)
}
```

Notes:
- `.overFullScreen` + clear background lets the map stay visible; the card supplies its own dim overlay (`Color.black.opacity(0.25)` at `WeatherDetailPopup.swift:47`).
- Dismissal is fully owned by SwiftUI: `WeatherDetailPopup` runs its scale/opacity exit, then `WeatherDetailPopupHost` calls `@Environment(\.dismiss)` which tears down the hosting controller.
- `crossDissolve` on the presentation side avoids a hard cut when the hosting view first appears.

### 3. Legacy path removal

The new hosted card replaces the alert entirely, and `MapViewController.showWeather()` is the only production caller of `WeatherDisplay.legacyAlert`. Once the rewrite lands there is nothing left to keep the legacy path alive, so all of the following are deleted in the same change:

- The `UIAlertController` construction inside `showWeather()`.
- `WeatherDisplay+LegacyAlert.swift` in `OBAKit/ViewModels/MapViewModel/`.
- Any `WeatherDisplay.legacyAlert`-only tests in `OBAKitTests/Weather/WeatherDisplayTests.swift` (and equivalent formatter tests that only exist to back `legacyAlert`). Tests that cover shared formatting used by the new card stay.

Before deleting, run `grep -rn "legacyAlert"` across the tree to confirm no other production code has picked it up; if the grep is clean apart from the file being removed and its own tests, the removal is unconditional.

## State Flow

1. `MapViewModel.weatherDisplay` is already a `@Published` property (subscribed at `MapViewController.swift:1171-1172`).
2. `WeatherDetailPopupHost` binds it via `@ObservedObject`, so a refresh that lands while the popup is open re-renders `WeatherDetailPopup` in place.
3. Dismissal chain:
   - User taps backdrop or close button in `WeatherDetailPopup`.
   - `WeatherDetailPopup` sets its `isPresented` binding to `false`, triggering the exit animation via `.animation(.smooth(duration: 0.25), value: isShowing)`.
   - `WeatherDetailPopupHost`'s `.onChange(of: isPresented)` fires with `newValue == false`.
   - The wrapper calls `dismiss()` from `@Environment(\.dismiss)`, which UIKit routes to the presenting controller.

## Testing

- Existing `MapViewModelTests` covers `weatherDisplay` publishing — no change needed.
- No new `MapViewController` unit test: there is no existing test fixture for it and a bespoke one would test UIKit plumbing (modal style, background color) rather than product behavior. The wrapper view itself is ~10 lines of pure SwiftUI glue.
- In `WeatherDisplayTests`, prune the `legacyAlert` assertions from `test_init_populatesHeaderStatsAndLegacyAlertFromFixture` (four expectations plus the block comment naming `LegacyAlert`) and rename the test to reflect its remaining scope. Any test whose sole purpose is asserting `legacyAlert` output goes. Header/Stats/HourlyEntry coverage stays.
- Since `WeatherDisplay.todaySummary` exists only to feed `legacyAlert` (see comment at `WeatherDisplay.swift:38-40`), it is removed with the legacy path. `WeatherForecast.todaySummary` in OBAKitCore stays untouched — it's an API field with its own coverage in `WeatherModelOperationTests`.
- Manual verification: run `scripts/generate_project OneBusAway`, launch the classic tab-based app on iPhone 16 simulator, tap the weather button in the `HoverBar`, verify the new card presents over the map, updates live when a refresh completes, and dismisses via both backdrop tap and close button.

## Risks

- **FloatingPanel z-order during the transition.** `MapViewController` hosts a `FloatingPanelController`. `.overFullScreen` from `MapViewController` should render the popup above the floating panel (system modal presentation), but this needs a quick manual smoke check that no frame of the floating panel bleeds through during cross-dissolve.
- **Region change while popup is open.** `WeatherDetailPopup.swift:62-68` already resets `isPresented` when `display` becomes `nil`, which flows through the wrapper and calls `dismiss()` — no extra plumbing needed.

## Non-goals

- No visual redesign; the SwiftUI card is the source of truth.
- No refactor of the `HoverBar` toolbar.
- No changes to the SwiftUI `MapPanelRootView` composition.
