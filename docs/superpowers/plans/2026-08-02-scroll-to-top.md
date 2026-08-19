# Stop Sheet Scroll-to-Top Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a floating scroll-to-top button to the stop details sheet that appears once the rider has scrolled more than one viewport down, and returns the list to the top when tapped.

**Architecture:** A pure visibility predicate (`ScrollToTopVisibility`), a plain-value glass button (`ScrollToTopButton`), and four small additions to `StopDetailsSheetView` — a `ScrollPosition`, a second read-only scroll observer for the viewport height, a bottom-trailing overlay, and a constant bottom content margin.

**Tech Stack:** Swift 6 language mode, SwiftUI (iOS 18+), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-08-02-scroll-to-top-design.md`

## Global Constraints

- **Deployment target:** iOS 18.0+. `ScrollPosition`, `onScrollGeometryChange` and `contentMargins` are all available.
- **Language mode:** Swift 6 with main-actor default isolation. The five concurrency diagnostic groups are **errors** — a data-race warning fails the build.
- **Tests:** Swift Testing (`@Suite(.serialized)`, `@Test`, `#expect`), never XCTest. A suite that needs no fixtures is a plain `struct` with no `OBATestCase` superclass.
- **Localization:** every user-facing string goes through `OBALoc(key, value:comment:)` with a real comment.
- **Linting:** `scripts/swiftlint.sh` must pass with no new violations. Current baseline: **4 violations in 467 files**.
- **Commits:** one-line subject, imperative, sentence case (e.g. `Add the stop sheet scroll-to-top button`). **No** `Co-Authored-By` trailer, no `feat:`/`fix:` prefixes.
- **Project generation:** not required — new files land in Xcode buildable folders automatically.

**THE LOAD-BEARING CONSTRAINT.** Nothing added here may make layout a function of scroll position. This sheet previously drove a top `safeAreaInset`'s height from scroll offset; measured on device, collapsing a 170 pt header shifted `contentOffset.y + contentInsets.top` by exactly 170, so the metric is not inset-invariant and any mid-range value oscillated (progress → inset → offset → progress) until the main thread was pegged and the entire app stopped responding. Both additions here are safe by construction: an **overlay** takes no part in the list's layout, and the bottom content margin is a **constant**. Do not make the margin conditional on the button's visibility.

**Build and test commands:**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test-without-building -only-testing:OBAKitTests/<SuiteName> \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test-without-building -only-testing:OBAKitTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Known pre-existing failure:** `RentalFormatTests.rangeFallbackUsesAbbreviatedUnits()` in `OBAKitTests/Mapping/` fails on this branch already and is unrelated. The baseline is **1725 tests, 1724 passing**. Any OTHER failure is yours.

## File Structure

| File | Responsibility |
| --- | --- |
| Create `OBAKit/Sheet/Content/Stop/Details/ScrollToTopVisibility.swift` | The pure predicate deciding whether the button shows |
| Create `OBAKitTests/Sheet/ScrollToTopVisibilityTests.swift` | Its tests |
| Create `OBAKit/Sheet/Content/Stop/Details/ScrollToTopButton.swift` | The glass circle button + preview |
| Modify `OBAKit/Sheet/Content/Stop/Details/StopDetailsSheetView.swift` | Wire the state, observer, overlay and margin |

---

### Task 1: `ScrollToTopVisibility`

**Files:**
- Create: `OBAKit/Sheet/Content/Stop/Details/ScrollToTopVisibility.swift`
- Create: `OBAKitTests/Sheet/ScrollToTopVisibilityTests.swift`

**Interfaces:**
- Produces: `nonisolated enum ScrollToTopVisibility` with `static func shouldShow(scrollOffset: CGFloat, viewportHeight: CGFloat) -> Bool`

- [ ] **Step 1: Write the failing tests**

Create `OBAKitTests/Sheet/ScrollToTopVisibilityTests.swift`:

```swift
//
//  ScrollToTopVisibilityTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreGraphics
import Testing
@testable import OBAKit

/// The scroll-to-top button's visibility rule. Extracted from the view because
/// it is the only part of the feature a unit test can reach — whether the
/// overlay actually renders, and whether tapping scrolls, both need a real
/// scroll view.
@Suite(.serialized)
struct ScrollToTopVisibilityTests {

    private let viewport: CGFloat = 800

    @Test func `Hidden at rest`() {
        #expect(!ScrollToTopVisibility.shouldShow(scrollOffset: 0, viewportHeight: viewport))
    }

    @Test func `Hidden just short of one viewport`() {
        #expect(!ScrollToTopVisibility.shouldShow(scrollOffset: 799, viewportHeight: viewport))
    }

    @Test func `Hidden at exactly one viewport`() {
        #expect(!ScrollToTopVisibility.shouldShow(scrollOffset: 800, viewportHeight: viewport))
    }

    @Test func `Shown just past one viewport`() {
        #expect(ScrollToTopVisibility.shouldShow(scrollOffset: 801, viewportHeight: viewport))
    }

    @Test func `Shown far down a long list`() {
        #expect(ScrollToTopVisibility.shouldShow(scrollOffset: 5000, viewportHeight: viewport))
    }

    /// Rubber-banding past the top yields a negative offset.
    @Test func `Hidden while rubber banding above the top`() {
        #expect(!ScrollToTopVisibility.shouldShow(scrollOffset: -120, viewportHeight: viewport))
    }

    /// Before the first layout pass the container has no height. Without the
    /// guard every offset counts as "more than nothing" and the button would
    /// appear on a sheet that has not been laid out.
    @Test func `Hidden before the sheet has been laid out`() {
        #expect(!ScrollToTopVisibility.shouldShow(scrollOffset: 500, viewportHeight: 0))
    }

    @Test func `Hidden for a negative viewport height`() {
        #expect(!ScrollToTopVisibility.shouldShow(scrollOffset: 500, viewportHeight: -10))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: **build failure** — `cannot find 'ScrollToTopVisibility' in scope`.

- [ ] **Step 3: Implement the predicate**

Create `OBAKit/Sheet/Content/Stop/Details/ScrollToTopVisibility.swift`:

```swift
//
//  ScrollToTopVisibility.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreGraphics

/// Decides whether the stop sheet's scroll-to-top button is showing.
///
/// A pure function rather than logic inside the view, so the rule can be tested:
/// the overlay's rendering and the scroll itself both need a real scroll view and
/// are verified by hand.
///
/// One viewport is the threshold because it is both the convention (Safari, the
/// App Store) and its own content gate — a stop with a handful of departures
/// cannot scroll a full screen, so the button never appears there and no separate
/// cell-count rule is needed.
nonisolated enum ScrollToTopVisibility {

    /// - Parameters:
    ///   - scrollOffset: distance scrolled from the top, as
    ///     `contentOffset.y + contentInsets.top`. Negative while rubber-banding
    ///     above the top.
    ///   - viewportHeight: the scroll view's container height. Zero before the
    ///     first layout pass.
    /// - Returns: `true` once the rider has scrolled more than one viewport.
    static func shouldShow(scrollOffset: CGFloat, viewportHeight: CGFloat) -> Bool {
        guard viewportHeight > 0 else { return false }
        return scrollOffset > viewportHeight
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests/ScrollToTopVisibilityTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: PASS, 8 tests.

- [ ] **Step 5: Run SwiftLint**

```bash
scripts/swiftlint.sh
```

Expected: 4 violations, unchanged from baseline.

- [ ] **Step 6: Commit**

```bash
git add OBAKit/Sheet/Content/Stop/Details/ScrollToTopVisibility.swift \
        OBAKitTests/Sheet/ScrollToTopVisibilityTests.swift
git commit -m "Add the stop sheet scroll-to-top visibility rule"
```

---

### Task 2: `ScrollToTopButton`

**Files:**
- Create: `OBAKit/Sheet/Content/Stop/Details/ScrollToTopButton.swift`

**Interfaces:**
- Produces: `ScrollToTopButton(isVisible: Bool, action: @escaping () -> Void)`

No tests: this is a presentational view whose only inputs are a `Bool` and a closure. Its states are covered by previews, matching the precedent set by `StopDetailsSheetTopBar`.

- [ ] **Step 1: Create the button**

Create `OBAKit/Sheet/Content/Stop/Details/ScrollToTopButton.swift`:

```swift
//
//  ScrollToTopButton.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The stop sheet's floating "back to the top" control.
///
/// Wears the same interactive Liquid Glass circle as `StopPageActionRow` and
/// `StopDetailsSheetTopBar`, so the sheet's chrome reads as one system rather
/// than three unrelated surfaces.
///
/// A plain-value view: it takes its visibility and its action from the caller and
/// owns no state.
struct ScrollToTopButton: View {
    let isVisible: Bool
    let action: () -> Void

    /// Matches the top bar's circles. Smaller than the action row's 44pt, because
    /// this floats over content rather than sitting in a row of primary actions.
    private static let buttonSize: CGFloat = 44

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.up")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .contentShape(Circle())
        }
        .liquidGlassButtonStyle(borderShape: .circle, fallbackShape: Circle())
        // The glass style colours its content from the environment accent; the
        // sheet's chrome is deliberately neutral.
        .tint(.primary)
        .accessibilityLabel(OBALoc(
            "stop_page.scroll_to_top",
            value: "Scroll to top",
            comment: "VoiceOver label for the button that returns the stop page's departure list to the top."
        ))
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.8)
        // Fully out of the accessibility tree when hidden, so VoiceOver cannot
        // land on an invisible control.
        .accessibilityHidden(!isVisible)
        .allowsHitTesting(isVisible)
    }
}

#Preview("Visible") {
    ScrollToTopButton(isVisible: true, action: {})
}

#Preview("Hidden") {
    ScrollToTopButton(isVisible: false, action: {})
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: build succeeds. The view is not referenced yet — a later task composes it, so unreferenced production code here is expected.

- [ ] **Step 3: Run SwiftLint**

```bash
scripts/swiftlint.sh
```

Expected: 4 violations, unchanged from baseline.

- [ ] **Step 4: Commit**

```bash
git add OBAKit/Sheet/Content/Stop/Details/ScrollToTopButton.swift
git commit -m "Add the stop sheet scroll-to-top button"
```

---

### Task 3: Wire the button into the sheet

**Files:**
- Modify: `OBAKit/Sheet/Content/Stop/Details/StopDetailsSheetView.swift`

**Interfaces:**
- Consumes: `ScrollToTopVisibility.shouldShow(scrollOffset:viewportHeight:)` (Task 1); `ScrollToTopButton(isVisible:action:)` (Task 2)

Read the current file before editing. The relevant parts are the `@State` block near the top, the modifier chain in `body`, the `// MARK: - Side effects` section containing `track(scrollOffset:)`, and the `// MARK: - Chrome` section containing `topBar`, `actionRowOffset` and `actionRowOverlay`.

- [ ] **Step 1: Add the state**

In the `@State` block, directly below `@State private var viewportHeight` does **not** exist yet — add both new properties after the existing `actionRowHeight` declaration:

```swift
    /// The scroll view's container height, used to decide when the rider has
    /// scrolled far enough to offer a way back. Read-only, like `scrollOffset` —
    /// nothing derived from it affects layout.
    @State private var viewportHeight: CGFloat = 0
    /// Drives the programmatic scroll back to the top.
    @State private var scrollPosition = ScrollPosition()
```

- [ ] **Step 2: Observe the viewport height and apply the scroll position**

In `body`, immediately after the existing `.onScrollGeometryChange(...) { ... } action: { _, offset in track(scrollOffset: offset) }` block, add a second observer and the scroll-position binding:

```swift
            // A second, separate observation so each stays single-purpose. Like
            // the offset above it is read-only: it feeds a predicate and an
            // overlay, never layout.
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.containerSize.height
            } action: { _, height in
                viewportHeight = height
            }
            .scrollPosition($scrollPosition)
```

- [ ] **Step 3: Add the overlay and the constant bottom margin**

Immediately after the existing `.overlay(alignment: .top) { actionRowOverlay }` line, add:

```swift
            // Bottom-trailing overlay, for the same reason the action row is an
            // overlay: it takes no part in the list's layout, so it cannot feed
            // back into scroll geometry.
            .overlay(alignment: .bottomTrailing) { scrollToTopOverlay }
            // A CONSTANT margin so the button never permanently covers the
            // footer's attribution line. It must not depend on the button's
            // visibility — layout driven by scroll position is what hung the app.
            .contentMargins(.bottom, Self.scrollToTopClearance, for: .scrollContent)
```

- [ ] **Step 4: Add the chrome members**

In the `// MARK: - Chrome` section, after `actionRowOverlay`, add:

```swift
    /// Space reserved at the end of the list so the floating button does not sit
    /// permanently on top of the attribution line. Constant by design.
    private static let scrollToTopClearance: CGFloat = 72

    private var showsScrollToTop: Bool {
        ScrollToTopVisibility.shouldShow(scrollOffset: scrollOffset, viewportHeight: viewportHeight)
    }

    private var scrollToTopOverlay: some View {
        ScrollToTopButton(isVisible: showsScrollToTop, action: scrollToTop)
            .padding(.trailing, 16)
            .padding(.bottom, 24)
            .animation(.snappy(duration: 0.2), value: showsScrollToTop)
    }
```

- [ ] **Step 5: Add the action**

In the `// MARK: - List actions` section, after `loadMore()`, add:

```swift
    private func scrollToTop() {
        withAnimation {
            scrollPosition.scrollTo(edge: .top)
        }
    }
```

- [ ] **Step 6: Build**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: build succeeds. If the compiler reports the body is too complex to type-check, extract the two new modifiers into a `private func scrollToTopModifiers` — do not restructure the existing chain.

- [ ] **Step 7: Run the full suite**

```bash
xcodebuild test-without-building -only-testing:OBAKitTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: 1733 tests, 1732 passing — the 1725 baseline plus Task 1's 8 tests — with only `RentalFormatTests.rangeFallbackUsesAbbreviatedUnits()` failing.

- [ ] **Step 8: Run SwiftLint**

```bash
scripts/swiftlint.sh
```

Expected: 4 violations, unchanged from baseline.

- [ ] **Step 9: Commit**

```bash
git add OBAKit/Sheet/Content/Stop/Details/StopDetailsSheetView.swift
git commit -m "Show a scroll-to-top button once the stop sheet is scrolled"
```

---

### Task 4: Manual verification

The overlay's appearance threshold and the scroll itself need a real scroll view. So does the regression check that matters most here.

**Files:** none

- [ ] **Step 1: Reach the sheet**

Nothing pushes `.stopDetails` from a tap in the simulator without a map interaction. To exercise it, temporarily add to `MapPanelRootView`'s modifier chain, after the `.onChange(of: selectedStopID)` block:

```swift
        .task {
            try? await Task.sleep(for: .seconds(4))
            coordinator.push(.stopDetails(stopID: "1_75403"))
        }
```

and temporarily force the map-panel root in `ApplicationRootControllerFactory.make(application:)` by returning `MapPanelRootController(application: application)` before the feature-flag branch. **Both are scaffolding — do not commit either.**

- [ ] **Step 2: Walk the checklist**

- [ ] Button is absent at rest
- [ ] Button is still absent after a short scroll (less than one screen)
- [ ] Button fades in once scrolled past roughly one screen
- [ ] Tapping it returns the list to the top, animated
- [ ] Button fades out again as the top is reached
- [ ] The map card and pinned title return to their at-rest appearance after the scroll
- [ ] The attribution line at the end of the list is readable — not covered by the button
- [ ] **Scrolling slowly down and up through the mid-range does not hang.** This feature adds a second scroll observer to a view that previously froze the whole app through a scroll-driven layout cycle; a slow drag through the middle is what exposed it
- [ ] Overscroll past the top: button stays hidden, nothing flickers
- [ ] Largest accessibility Dynamic Type size: the button is still reachable and does not overlap the action row
- [ ] VoiceOver: the button is not focusable while hidden, and reads "Scroll to top" when visible

- [ ] **Step 3: Remove the scaffolding**

```bash
git status --short
```

Expected: no modification to `MapPanelRootView.swift` or `ApplicationRootControllerFactory.swift`.

---

## Self-Review

**Spec coverage**

| Spec section | Task |
| --- | --- |
| `ScrollToTopVisibility` + its six-plus cases | 1 |
| `ScrollToTopButton`, glass styling, localised label, previews | 2 |
| `ScrollPosition` state and `.scrollPosition($scrollPosition)` | 3 |
| Second `onScrollGeometryChange` for `containerSize.height` | 3 |
| `.overlay(alignment: .bottomTrailing)` | 3 |
| Constant bottom content margin | 3 |
| Appear/disappear animation | 3 |
| Tap behaviour and self-resetting state | 3 |
| Rubber-banding handled by the predicate | 1 (test), 4 (manual) |
| Manual checks, including the no-hang re-check | 4 |

Every spec section maps to a task.

**Deviations from the spec**

1. The spec says the button is "hidden from accessibility entirely when not visible". The plan implements that with `accessibilityHidden(!isVisible)` **and** `allowsHitTesting(isVisible)` — opacity alone leaves an invisible but tappable target, which would swallow taps meant for the last departure row.
2. The spec did not fix a threshold for "one viewport". The plan uses strictly greater than the container height, and Task 1 pins the boundary explicitly: hidden at exactly one viewport, shown at one past it.

**Placeholder scan:** no TBD/TODO, no "handle edge cases", no "similar to Task N". Every code step carries real code.

**Type consistency:** `ScrollToTopVisibility.shouldShow(scrollOffset:viewportHeight:)` is defined in Task 1 and called with those exact labels in Task 3. `ScrollToTopButton(isVisible:action:)` is defined in Task 2 and constructed with those labels in Task 3. `viewportHeight`, `scrollPosition`, `showsScrollToTop`, `scrollToTopOverlay`, `scrollToTopClearance` and `scrollToTop()` are each declared once in Task 3 and referenced consistently.

**Known risk:** `ScrollPosition` is not used anywhere else in this codebase, so its interaction with `List` is unproven here. If `scrollTo(edge: .top)` does not move the list, the fallback is `ScrollViewReader` with the id attached to the existing header row in `headerRows` — *not* a zero-height sentinel row, which picks up a default minimum row height in this List and leaves a visible gap.
