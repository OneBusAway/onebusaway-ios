# Stop Sheet Plain Header and Fixed Bottom Toolbar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the stop sheet's dark map header with the existing map-free header, and turn its scroll-tracking action row into a fixed glass capsule pinned to the bottom.

**Architecture:** `StopDetailsSheetView` adopts two views the pushed `StopPageView` already uses — `StopPageSheetHeaderView` and a bottom-mounted action row — and drops the collapse arithmetic that existed to keep a tall header's actions reachable. The action row moves from `.overlay(alignment: .top)` with a computed offset to a constant-height `.safeAreaInset(edge: .bottom)`, which is what lets the list reserve its own bottom room.

**Tech Stack:** Swift 6 language mode, SwiftUI, Swift Testing, XcodeGen, SwiftLint.

**Spec:** `docs/superpowers/specs/2026-08-07-stop-sheet-header-and-toolbar-design.md`

## Global Constraints

- Every target builds in the **Swift 6 language mode** with main-actor default isolation. The five concurrency diagnostic groups are escalated to errors — a data-race warning fails the build.
- Tests are **Swift Testing** (`@Suite` / `@Test` / `#expect`), not XCTest. Suites are marked `.serialized`.
- Build and test destination is **`platform=iOS Simulator,name=iPhone 16,OS=26.5`**. Not iPhone 17 Pro.
- Run `scripts/generate_project OneBusAway` before building only if files were **created or deleted** — the project uses directory-synchronized sources, so pure edits need no regeneration.
- Commit messages are a **single subject line**. No body paragraphs, no `Co-Authored-By` trailers.
- Do not commit unless the task's step says to. Do not push.
- `RentalFormatTests.rangeFallbackUsesAbbreviatedUnits()` fails on `main` and is unrelated. A run with exactly that one failure is green.

## Verification commands

Build:
```bash
xcodebuild build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.5' 2>&1 | tail -5
```

Full suite:
```bash
xcodebuild test-without-building -only-testing:OBAKitTests -project 'OBAKit.xcodeproj' \
  -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.5' 2>&1 \
  | grep -E "recorded an issue|Test run with"
```

One suite:
```bash
xcodebuild test-without-building -only-testing:OBAKitTests/<SuiteName> -project 'OBAKit.xcodeproj' \
  -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.5' 2>&1 \
  | grep -E "^✔ Test |^✘ Test |Test run with"
```

Lint (changed files only):
```bash
swiftlint lint --quiet <paths…>
```

## File Structure

| File | Responsibility | Task |
| --- | --- | --- |
| `OBAKit/Sheet/Content/Stop/Details/StopSheetHeaderCollapse.swift` | Deleted; replaced by the file below | 1 |
| `OBAKit/Sheet/Content/Stop/Details/StopSheetTitleFade.swift` | Scroll offset → title opacity, 0…1 | 1 |
| `OBAKitTests/Sheet/StopSheetHeaderCollapseTests.swift` | Deleted; replaced by the file below | 1 |
| `OBAKitTests/Sheet/StopSheetTitleFadeTests.swift` | The fade arithmetic | 1 |
| `OBAKit/Stops/StopPage/StopPageSheetHeaderView.swift` | Gains `showsCloseButton` on both header views | 2 |
| `OBAKitTests/Stops/StopPage/StopPageSheetHeaderCloseButtonTests.swift` | Pins the default that protects the pushed page | 2 |
| `OBAKit/Sheet/Content/Stop/Details/StopPageActionRow.swift` | Becomes a floating glass capsule | 3 |
| `OBAKit/Sheet/Content/Stop/Details/StopDetailsSheetView.swift` | Bottom inset (task 3), header swap (task 4) | 3, 4 |

Task order matters: task 3 removes every piece of collapse state, which task 4 then does not have to reason about. Each task leaves the app building and running.

---

### Task 1: Rename the fade arithmetic

`StopSheetHeaderCollapse` is a clamped `scrollOffset / height` whose only caller is the top bar's title fade. After this plan nothing collapses, so the name points at something that will not exist. Pure rename — the arithmetic and every assertion are unchanged.

**Files:**
- Create: `OBAKit/Sheet/Content/Stop/Details/StopSheetTitleFade.swift`
- Delete: `OBAKit/Sheet/Content/Stop/Details/StopSheetHeaderCollapse.swift`
- Create: `OBAKitTests/Sheet/StopSheetTitleFadeTests.swift`
- Delete: `OBAKitTests/Sheet/StopSheetHeaderCollapseTests.swift`
- Modify: `OBAKit/Sheet/Content/Stop/Details/StopDetailsSheetView.swift` (the `track(scrollOffset:)` call site)

**Interfaces:**
- Consumes: nothing.
- Produces: `StopSheetTitleFade.progress(scrollOffset: CGFloat, fadeDistance: CGFloat) -> CGFloat`, clamped `0...1`, returns `0` when `fadeDistance <= 0`.

- [ ] **Step 1: Create the renamed type**

Create `OBAKit/Sheet/Content/Stop/Details/StopSheetTitleFade.swift`:

```swift
//
//  StopSheetTitleFade.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreGraphics

/// Maps scroll position to how far the stop sheet's pinned title has faded in,
/// 0 (invisible, the header still names the stop) through 1 (fully in).
///
/// A pure function rather than logic inside the view, both so it can be tested
/// and so the feedback-loop hazard has one obvious home.
///
/// **Nothing downstream of this value may touch layout.** An earlier design
/// shrank a `safeAreaInset` as this rose, and it oscillated — the inset shifted
/// the offset, which changed progress, which resized the inset — until the main
/// thread was pegged and the app stopped responding. Two things keep that fixed:
/// callers pass `contentOffset.y + contentInsets.top`, a sum that holds steady
/// when an inset changes, and this drives opacity only. The sheet's chrome is
/// two fixed-height insets — the top bar and the action row — for the same
/// reason. See the note in `StopDetailsSheetView.sheetBody(proxy:)`.
nonisolated enum StopSheetTitleFade {

    /// - Parameters:
    ///   - scrollOffset: `contentOffset.y + contentInsets.top` — distance
    ///     scrolled from the top, invariant to inset changes.
    ///   - fadeDistance: the distance over which the fade completes. A plain
    ///     constant is correct here — a fade has no real geometry to stay
    ///     registered with, which is exactly why it is safe.
    /// - Returns: progress clamped to `0...1`; `0` when there is no distance to
    ///   fade over.
    static func progress(scrollOffset: CGFloat, fadeDistance: CGFloat) -> CGFloat {
        guard fadeDistance > 0 else { return 0 }
        return min(max(scrollOffset / fadeDistance, 0), 1)
    }
}
```

- [ ] **Step 2: Create the renamed tests**

Create `OBAKitTests/Sheet/StopSheetTitleFadeTests.swift`:

```swift
//
//  StopSheetTitleFadeTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreGraphics
import Testing
@testable import OBAKit

/// The pinned title's fade arithmetic. Extracted from the view because it is
/// the part most likely to misbehave and the only part a unit test can reach —
/// the scroll interaction itself needs a real scroll view.
@Suite(.serialized)
struct StopSheetTitleFadeTests {

    @Test func `At rest the title is fully faded out`() {
        #expect(StopSheetTitleFade.progress(scrollOffset: 0, fadeDistance: 170) == 0)
    }

    @Test func `Scrolling the full fade distance fully fades in`() {
        #expect(StopSheetTitleFade.progress(scrollOffset: 170, fadeDistance: 170) == 1)
    }

    @Test func `Halfway through the range is half faded`() {
        #expect(StopSheetTitleFade.progress(scrollOffset: 85, fadeDistance: 170) == 0.5)
    }

    @Test func `Overscrolling past a full fade clamps to one`() {
        #expect(StopSheetTitleFade.progress(scrollOffset: 900, fadeDistance: 170) == 1)
    }

    @Test func `Rubber banding above the top clamps to zero`() {
        #expect(StopSheetTitleFade.progress(scrollOffset: -120, fadeDistance: 170) == 0)
    }

    /// A stop that never resolves has no header to scroll past. Without this
    /// guard the range divides by zero.
    @Test func `A zero fade distance reports no progress`() {
        #expect(StopSheetTitleFade.progress(scrollOffset: 50, fadeDistance: 0) == 0)
    }

    @Test func `A negative fade distance reports no progress`() {
        #expect(StopSheetTitleFade.progress(scrollOffset: 50, fadeDistance: -10) == 0)
    }

    @Test func `Progress is monotonic across the range`() {
        var previous: CGFloat = -1
        for offset in stride(from: CGFloat(0), through: 170, by: 10) {
            let value = StopSheetTitleFade.progress(scrollOffset: offset, fadeDistance: 170)
            #expect(value >= previous)
            previous = value
        }
    }
}
```

- [ ] **Step 3: Delete the old files**

```bash
rm OBAKit/Sheet/Content/Stop/Details/StopSheetHeaderCollapse.swift
rm OBAKitTests/Sheet/StopSheetHeaderCollapseTests.swift
```

- [ ] **Step 4: Update the one call site**

In `OBAKit/Sheet/Content/Stop/Details/StopDetailsSheetView.swift`, find `track(scrollOffset:)` and replace its body:

```swift
    private func track(scrollOffset offset: CGFloat) {
        scrollOffset = offset
        titleProgress = StopSheetTitleFade.progress(
            scrollOffset: offset,
            fadeDistance: Self.titleFadeDistance
        )
    }
```

- [ ] **Step 5: Confirm no references remain**

Run: `grep -rn "StopSheetHeaderCollapse" OBAKit/ OBAKitTests/`
Expected: no output.

- [ ] **Step 6: Regenerate, build and test**

Files were created and deleted, so regeneration is required.

```bash
scripts/generate_project OneBusAway
```
Then the build command, then the one-suite command with `<SuiteName>` = `StopSheetTitleFadeTests`.
Expected: BUILD SUCCEEDED, 8 tests pass.

- [ ] **Step 7: Lint and commit**

```bash
swiftlint lint --quiet OBAKit/Sheet/Content/Stop/Details/StopSheetTitleFade.swift OBAKitTests/Sheet/StopSheetTitleFadeTests.swift
git add -A
git commit -m "Rename the stop sheet's collapse arithmetic to what it actually drives"
```

---

### Task 2: Give the sheet headers an optional close button

The sheet's top bar keeps Close. The header carries its own. Without a way to suppress one, the rider gets two ✕ roughly 10pt apart.

**Files:**
- Modify: `OBAKit/Stops/StopPage/StopPageSheetHeaderView.swift`
- Create: `OBAKitTests/Stops/StopPage/StopPageSheetHeaderCloseButtonTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `StopPageSheetHeaderView.showsCloseButton: Bool` (default `true`), declared **after** `onClose` and **before** `isCollapsed`. Same property on `StopPageSheetHeaderPlaceholderView`, declared after `onClose` and before `isCollapsed`. Task 4 passes `false` for both.

**A note on what this test can and cannot prove.** The valuable assertion — that the *sheet* passes `false` and the *pushed page* does not — is not reachable from a unit test: both call sites are inside private `some View` builders. What is reachable, and what actually protects the pushed page from a careless default flip, is the default itself. The sheet's `false` is verified by running the app in Task 4. Do not pad this suite with rendered-view inspection; the branch does not snapshot-test.

- [ ] **Step 1: Write the failing test**

Create `OBAKitTests/Stops/StopPage/StopPageSheetHeaderCloseButtonTests.swift`:

```swift
//
//  StopPageSheetHeaderCloseButtonTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import OBAKitCore
@testable import OBAKit

/// Who owns the close button.
///
/// The header carries one because the pushed sheet presentation has no
/// navigation bar behind it. The map sheet's own top bar carries one too, so
/// there the header's must be suppressed or the rider sees two ✕ a few points
/// apart. The default is what keeps the pushed presentation's only way out from
/// disappearing if someone flips it.
@MainActor
@Suite(.serialized)
struct StopPageSheetHeaderCloseButtonTests {

    /// `Fixtures.loadSomeStops()` is the project's only `Stop` source and it
    /// throws — the same call `StopPageSheetHeaderLayoutTests` uses.
    private func someStop() throws -> Stop {
        try #require(Fixtures.loadSomeStops().first)
    }

    @Test func `The header shows its close button by default`() throws {
        let header = StopPageSheetHeaderView(
            stop: try someStop(),
            walkTime: nil,
            onWalkingDirections: {},
            onClose: {},
            mapFocus: StopMapFocus()
        )
        #expect(header.showsCloseButton)
    }

    @Test func `The header can suppress its close button`() throws {
        let header = StopPageSheetHeaderView(
            stop: try someStop(),
            walkTime: nil,
            onWalkingDirections: {},
            onClose: {},
            showsCloseButton: false,
            mapFocus: StopMapFocus()
        )
        #expect(!header.showsCloseButton)
    }

    @Test func `The placeholder shows its close button by default`() {
        let placeholder = StopPageSheetHeaderPlaceholderView(onClose: {})
        #expect(placeholder.showsCloseButton)
    }

    @Test func `The placeholder can suppress its close button`() {
        let placeholder = StopPageSheetHeaderPlaceholderView(onClose: {}, showsCloseButton: false)
        #expect(!placeholder.showsCloseButton)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Regenerate first — a file was created:
```bash
scripts/generate_project OneBusAway
```
Then the build command.
Expected: BUILD FAILED with "extra argument 'showsCloseButton' in call" and "value of type 'StopPageSheetHeaderView' has no member 'showsCloseButton'".

- [ ] **Step 3: Add the property to `StopPageSheetHeaderView`**

In `OBAKit/Stops/StopPage/StopPageSheetHeaderView.swift`, insert after the `onClose` declaration and before `isCollapsed`:

```swift
    /// `false` where something else already offers a way out — the map sheet's
    /// pinned top bar carries its own Close, and two ✕ a few points apart read
    /// as a mistake. Defaults to showing it: the pushed sheet presentation has
    /// no navigation bar behind it, so this is that presentation's only way out.
    var showsCloseButton = true
```

Then guard the button in `body`, replacing `StopSheetCloseButton(action: onClose)`:

```swift
                    if showsCloseButton {
                        StopSheetCloseButton(action: onClose)
                    }
```

- [ ] **Step 4: Add the property to `StopPageSheetHeaderPlaceholderView`**

Insert after its `onClose` declaration and before `isCollapsed`:

```swift
    /// See `StopPageSheetHeaderView.showsCloseButton`. Suppressed on the map
    /// sheet, whose top bar carries Close even while the stop is unknown.
    var showsCloseButton = true
```

Then in its `body`, replace `StopSheetCloseButton(action: onClose)`:

```swift
            if showsCloseButton {
                StopSheetCloseButton(action: onClose)
            }
```

- [ ] **Step 5: Run the test to verify it passes**

Build, then the one-suite command with `<SuiteName>` = `StopPageSheetHeaderCloseButtonTests`.
Expected: BUILD SUCCEEDED, 4 tests pass.

- [ ] **Step 6: Confirm the pushed page is untouched**

Run: `grep -n "StopPageSheetHeaderView(\|StopPageSheetHeaderPlaceholderView(" OBAKit/Stops/StopPage/StopPageView.swift`
Expected: three call sites, none mentioning `showsCloseButton` — they take the default.

Then run the full suite. Expected: only the known `RentalFormatTests` failure.

- [ ] **Step 7: Lint and commit**

```bash
swiftlint lint --quiet OBAKit/Stops/StopPage/StopPageSheetHeaderView.swift OBAKitTests/Stops/StopPage/StopPageSheetHeaderCloseButtonTests.swift
git add -A
git commit -m "Let the sheet headers suppress their close button"
```

---

### Task 3: Pin the action row to the bottom as a glass capsule

Removes every piece of collapse state at once. `mapCardHeight`, `topBarHeight` and `actionRowHeight` exist only to compute `actionRowOffset`, so they all go together.

**Files:**
- Modify: `OBAKit/Sheet/Content/Stop/Details/StopPageActionRow.swift`
- Modify: `OBAKit/Sheet/Content/Stop/Details/StopDetailsSheetView.swift`

**Interfaces:**
- Consumes: `StopSheetTitleFade.progress(scrollOffset:fadeDistance:)` from Task 1.
- Produces: `StopDetailsSheetView.actionRow(navigation:) -> some View`, replacing `actionRowOverlay(navigation:)`. No other task depends on it.

**No unit test.** This task changes only layout and surface treatment. The branch has no snapshot or UI tests, and a test asserting "the row is a bottom inset" would restate the code. Its gate is: the full suite stays green, and the sheet is looked at on a device — the row fixed at the bottom, the last departure not hidden under it, and the capsule clear of the home indicator.

- [ ] **Step 1: Turn the action row into a floating capsule**

In `OBAKit/Sheet/Content/Stop/Details/StopPageActionRow.swift`, replace the trailing modifiers on `body`:

```swift
        .padding(.vertical, 10)
        // Clipped before the surface so the accessibility-size horizontal
        // scroll cannot run out past the pill's rounded ends.
        .clipShape(Capsule())
        .regularGlassEffectIfAvailable(in: Capsule())
        // Outside the surface, so this is the gap between the capsule and the
        // sheet's edges rather than internal padding.
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
```

That is: delete `.background(Color(uiColor: .systemBackground))` and `.overlay(alignment: .bottom) { Divider() }`, and add the four modifiers above. The row is no longer a full-width strip with a hairline; it is a pill that floats.

Update the type's doc comment — it currently says the row "stays beneath the map header as the list scrolls", which stops being true:

```swift
/// Schedule, Filter, Bookmark and More, as circular buttons in a glass capsule
/// fixed at the bottom of the stop sheet.
///
/// Filter is promoted out of the More menu into its own button, so More carries
/// only the four remaining actions. A plain-value view: every action is a
/// closure supplied by `StopDetailsSheetView`.
```

- [ ] **Step 2: Replace the overlay with a bottom inset**

In `StopDetailsSheetView.swift`, rename `actionRowOverlay(navigation:)` to `actionRow(navigation:)` and delete its last two modifiers (`.onGeometryChange` and `.offset(y:)`), so it ends at the closing paren of `StopPageActionRow(...)`:

```swift
    private func actionRow(navigation: StopPageNavigationHandler) -> some View {
        StopPageActionRow(
            state: StopPageActionRowState(
                hasStop: viewModel.stop != nil,
                routeCount: viewModel.stop?.routes.count ?? 0,
                hasHiddenRoutes: viewModel.stopPreferences.hasHiddenRoutes,
                isListFiltered: viewModel.isListFiltered,
                hasServiceAlerts: !(viewModel.stopArrivals?.serviceAlerts ?? []).isEmpty
            ),
            onSchedule: navigation.showScheduleForStop,
            onSetListFiltered: { filtered in
                viewModel.isListFiltered = filtered
                // Picking "Filtered Routes" opens the picker, matching the
                // pushed presentation's `filterMenu()` — otherwise choosing it
                // on a stop with no saved hidden routes silently does nothing.
                if filtered { navigation.showRouteFilter() }
            },
            onBookmark: { navigation.showBookmarkEditor(nil) },
            onServiceAlerts: navigation.showServiceAlerts,
            onNearbyStops: navigation.showNearbyStops,
            onWalkingDirections: navigation.showWalkingDirections,
            onReportProblem: navigation.showReportProblem
        )
    }
```

- [ ] **Step 3: Rewire `sheetBody(proxy:)`**

In `sheetBody(proxy:)`, replace the `.overlay(alignment: .top)` line and the `.contentMargins` line. Delete both of these:

```swift
            .overlay(alignment: .top) { actionRowOverlay(navigation: navigation) }
```
```swift
            .contentMargins(.bottom, Self.scrollToTopClearance, for: .scrollContent)
```

And add, immediately after the existing `.safeAreaInset(edge: .top, spacing: 0) { topBar }` line:

```swift
            // Fixed height, like the top bar above it. An inset whose height
            // tracked scroll position is what pegged the main thread here once;
            // a constant one has no such loop, and it means the list reserves
            // the capsule's room itself — so the last departure cannot hide
            // underneath it and no hand-tuned bottom margin has to be kept in
            // sync with the capsule's height.
            .safeAreaInset(edge: .bottom, spacing: 0) { actionRow(navigation: navigation) }
```

Also update the comment above `.safeAreaInset(edge: .top…)`, which currently reads "Fixed height — it holds only the top bar, so nothing here resizes as the list scrolls." That is still true; leave it.

- [ ] **Step 4: Delete the collapse state**

In `StopDetailsSheetView.swift`, delete these stored properties and their doc comments:

```swift
    @State private var topBarHeight: CGFloat = 0
    @State private var mapCardHeight: CGFloat = 0
    @State private var actionRowHeight: CGFloat = 0
```

Keep `scrollOffset` and `viewportHeight`, and narrow the comment above them, which currently talks about "the sticky-overlay arithmetic":

```swift
    /// Distance scrolled from the top. Drives the title fade and the
    /// scroll-to-top button's visibility — never any layout the scroll view can
    /// observe.
    @State private var scrollOffset: CGFloat = 0
```

Delete `actionRowOffset` entirely:

```swift
    private var actionRowOffset: CGFloat {
        topBarHeight + max(0, mapCardHeight - scrollOffset)
    }
```

Delete `scrollToTopClearance`:

```swift
    private static let scrollToTopClearance: CGFloat = 72
```

Delete the `.onGeometryChange` on `topBar`, so it becomes:

```swift
    private var topBar: some View {
        StopDetailsSheetTopBar(
            title: viewModel.stop?.name ?? "",
            titleOpacity: Double(titleProgress),
            statusText: viewModel.statusText,
            isRefreshing: isManuallyRefreshing,
            onRefresh: refresh,
            onClose: { coordinator.pop() }
        )
    }
```

In `headerRows(showsLoadingState:navigation:)`, delete the `.onGeometryChange` that fed `mapCardHeight` and the entire `Color.clear` spacer row, and update the function's doc comment:

```swift
    /// The map card. Scrolls with the list — there is no sticky chrome below the
    /// top bar for it to collide with.
    @ViewBuilder
    private func headerRows(showsLoadingState: Bool, navigation: StopPageNavigationHandler) -> some View {
        Section {
            Group {
                if let stop = viewModel.stop {
                    StopPageHeaderView(
                        stop: stop,
                        walkTime: viewModel.walkTime,
                        statusText: viewModel.statusText,
                        snapshotLoader: { size in
                            await presenter.loadSnapshot(stop: stop, size: size, traitCollection: snapshotTraits)
                        },
                        onWalkingDirections: navigation.showWalkingDirections
                    )
                } else if showsLoadingState {
                    StopPageHeaderPlaceholderView()
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        // The scroll-to-top target. The id belongs on the Section: a row-level id
        // does not resolve for `ScrollViewReader` in this List. It rides the
        // existing header rather than a zero-height sentinel row, which would pick
        // up the List's minimum row height and leave a visible gap.
        .id(Self.topRowID)
    }
```

- [ ] **Step 5: Update the scroll-to-top overlay's comment**

Its `.padding(.bottom, 24)` now measures from the capsule's top rather than the sheet's edge. Change the comment above `scrollToTopOverlay(proxy:)`:

```swift
    /// The floating "back to top" control, above the action capsule.
    ///
    /// The capsule is a bottom safe-area inset, so this overlay's bottom edge
    /// already sits above it and the padding below is clearance from the
    /// capsule, not from the sheet's edge.
    private func scrollToTopOverlay(proxy: ScrollViewProxy) -> some View {
```

- [ ] **Step 6: Confirm nothing dangling**

```bash
grep -n "actionRowOffset\|mapCardHeight\|topBarHeight\|actionRowHeight\|scrollToTopClearance\|actionRowOverlay" OBAKit/Sheet/Content/Stop/Details/StopDetailsSheetView.swift
```
Expected: no output.

- [ ] **Step 7: Build and test**

No files created or deleted, so no regeneration. Run the build command, then the full suite.
Expected: BUILD SUCCEEDED; only the known `RentalFormatTests` failure.

- [ ] **Step 8: Look at it**

Run the app, tap a stop on the map, and confirm: the action capsule is fixed at the bottom and does not move when the list scrolls; scrolling to the very end shows the last departure clear of the capsule; the capsule sits above the home indicator; scroll-to-top appears above the capsule, not behind it. Then set Dynamic Type to an accessibility size and confirm the capsule scrolls horizontally without its content spilling past the rounded ends.

If any of these fail, stop and report rather than compensating with a magic constant.

- [ ] **Step 9: Lint and commit**

```bash
swiftlint lint --quiet OBAKit/Sheet/Content/Stop/Details/StopPageActionRow.swift OBAKit/Sheet/Content/Stop/Details/StopDetailsSheetView.swift
git add -A
git commit -m "Fix the stop sheet's action row to the bottom as a glass capsule"
```

---

### Task 4: Swap in the map-free header

**Files:**
- Modify: `OBAKit/Sheet/Content/Stop/Details/StopDetailsSheetView.swift`

**Interfaces:**
- Consumes: `showsCloseButton` from Task 2; the `headerRows` shape left by Task 3.
- Produces: nothing further.

**No unit test**, for the same reason as Task 3 — this is which view gets constructed inside a private `some View` builder. Task 2's suite already pins the default that protects the pushed page. The gate is the full suite plus a look at the running app.

- [ ] **Step 1: Add the map-focus channel**

`StopPageSheetHeaderView` requires a `StopMapFocus`. Add to `StopDetailsSheetView`'s stored properties, next to the other `@StateObject`:

```swift
    /// The header's route chips decorate themselves from map focus — route
    /// colour, live-vehicle dot, tap-to-highlight. That channel is wired only
    /// through the UIKit `MapViewController`; this sheet sits over the SwiftUI
    /// map panel, which has none. An unwired instance is a supported mode: every
    /// route reports unfocusable, so the chips render plain, carry no button
    /// trait, and their tap gesture is a no-op. See `StopMapFocus`.
    ///
    /// `@StateObject` so it is one instance for the life of the sheet rather
    /// than a fresh object per body pass. It never publishes, so observing it
    /// costs nothing.
    @StateObject private var mapFocus = StopMapFocus()
```

- [ ] **Step 2: Swap the header views**

Replace the body of `headerRows(showsLoadingState:navigation:)` with:

```swift
    /// The stop's identity block. Scrolls with the list — there is no sticky
    /// chrome below the top bar for it to collide with.
    ///
    /// The map-free header, not `StopPageHeaderView`'s dark map card: this sheet
    /// sits over a live map, so a map thumbnail inside it spends the sheet's
    /// scarce height showing the rider something they can see by looking up.
    /// Close is suppressed because the pinned top bar carries one.
    @ViewBuilder
    private func headerRows(showsLoadingState: Bool, navigation: StopPageNavigationHandler) -> some View {
        Section {
            Group {
                if let stop = viewModel.stop {
                    StopPageSheetHeaderView(
                        stop: stop,
                        walkTime: viewModel.walkTime,
                        onWalkingDirections: navigation.showWalkingDirections,
                        onClose: { coordinator.pop() },
                        showsCloseButton: false,
                        mapFocus: mapFocus
                    )
                } else if showsLoadingState {
                    StopPageSheetHeaderPlaceholderView(
                        showsSkeleton: true,
                        onClose: { coordinator.pop() },
                        showsCloseButton: false
                    )
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        // The scroll-to-top target. The id belongs on the Section: a row-level id
        // does not resolve for `ScrollViewReader` in this List. It rides the
        // existing header rather than a zero-height sentinel row, which would pick
        // up the List's minimum row height and leave a visible gap.
        .id(Self.topRowID)
    }
```

Note `isCollapsed` is not passed. It defaults to `false` and exists for the old FloatingPanel `.tip` detent, which `.stopDetails` (`[.large]` only) does not have.

- [ ] **Step 3: Delete the snapshot plumbing**

Delete the `snapshotTraits` computed property and its doc comment, and the `displayScale` environment property and its doc comment:

```swift
    @Environment(\.displayScale) private var displayScale
```
```swift
    private var snapshotTraits: UITraitCollection {
        UITraitCollection { traits in
            traits.displayScale = displayScale
        }
    }
```

Do **not** remove `StopPageActionPresenter.loadSnapshot` — the pushed `StopPageView` still renders the map card and still calls it.

- [ ] **Step 4: Confirm nothing dangling**

```bash
grep -n "snapshotTraits\|displayScale\|StopPageHeaderView\|StopPageHeaderPlaceholderView" OBAKit/Sheet/Content/Stop/Details/StopDetailsSheetView.swift
```
Expected: no output.

```bash
grep -rn "loadSnapshot" OBAKit/ | grep -v StopDetailsSheetView
```
Expected: still present in `StopPageActionPresenter.swift` and `StopPageView.swift`.

- [ ] **Step 5: Check whether `import UIKit` is still needed**

`snapshotTraits` was the file's `UITraitCollection` user. Check for other UIKit references:

```bash
grep -n "UIColor\|UITrait\|UIApplication\|UIView\|NSUserActivity" OBAKit/Sheet/Content/Stop/Details/StopDetailsSheetView.swift
```
If there are hits (`Color(uiColor:)` and `NSUserActivity` are likely), keep `import UIKit`. If there are none, remove it. Do not remove it on assumption — let the build decide.

- [ ] **Step 6: Build and test**

No files created or deleted; no regeneration. Run the build command, then the full suite.
Expected: BUILD SUCCEEDED; only the known `RentalFormatTests` failure.

- [ ] **Step 7: Look at it**

Run the app and tap a stop. Confirm: the header shows name, stop code and direction, the walk pill and route chips — no map thumbnail; there is exactly **one** ✕ (in the top bar); the header scrolls away and the top bar's title fades in as it goes; route chips are plain grey and do nothing when tapped, which is expected here.

Then force a failed first fetch if you can (airplane mode on a stop not in cache) and confirm the sheet still shows a top bar with a working ✕.

- [ ] **Step 8: Lint and commit**

```bash
swiftlint lint --quiet OBAKit/Sheet/Content/Stop/Details/StopDetailsSheetView.swift
git add -A
git commit -m "Use the map-free header in the stop details sheet"
```

---

## Done when

- The stop sheet shows `StopPageSheetHeaderView`, scrolling with the list.
- The action row is a glass capsule fixed at the bottom.
- No collapse arithmetic remains in `StopDetailsSheetView`.
- The pushed `StopPageView` renders exactly as it did before.
- Full suite green apart from the known `RentalFormatTests` failure; SwiftLint clean on every touched file.
