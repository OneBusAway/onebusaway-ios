# Stop UI Accessibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the stop page's route badges WCAG-AA readable (fixing white-on-yellow), honor system Increase Contrast, and add an opt-in reduced-color badge presentation.

**Architecture:** WCAG 2.1 contrast math lives in a new OBAKitCore `UIColor` extension so both `RouteBadgeView` copies (stop page + widget) share one text-color decision. The stop page's copy additionally gains a reduced-color variant (vertical route-color bar + primary-label text) driven by a dot-free `@AppStorage` key that a new `UserDataStore` property and Eureka `SwitchRow` write.

**Tech Stack:** Swift, SwiftUI (stop page), Eureka (settings form), Swift Testing (new tests), XcodeGen project generation.

**Spec:** `docs/superpowers/specs/2026-07-20-stop-ui-accessibility-design.md`

## Global Constraints

- iOS 18.0+ deployment target; Swift 5/6 language modes; modern syntax is fine.
- OBAKitCore must remain application-extension safe (no UIApplication, no app-only API).
- Run `scripts/generate_project OneBusAway` after adding any file, before building.
- Build/test destination: `platform=iOS Simulator,name=iPhone 17 Pro` (iPhone 16 is NOT installed).
- Test command shape: `xcodebuild test-without-building -only-testing:OBAKitTests/<ClassOrSuite> -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` — build first with `xcodebuild build-for-testing -scheme 'App' -destination '…'`. Use `set -o pipefail` if piping through `tail`; a failed build leaves stale products the simulator refuses to launch.
- User-facing strings use `OBALoc("key", value:, comment:)`.
- The reduced-colors defaults key MUST be the dot-free string `stopUIReducedColors` (KVO/@AppStorage constraint — see spec §3).
- WCAG thresholds: 4.5:1 normal, 7.0:1 under Increase Contrast. Never special-case by text size.
- Commit after each task.

---

### Task 1: WCAG contrast math + badge text-color decision (OBAKitCore)

**Files:**
- Create: `OBAKitCore/Extensions/UIColor+WCAG.swift`
- Test: `OBAKitTests/Extensions/UIColorWCAGTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces (used by Tasks 2–3):
  - `UIColor.wcagRelativeLuminance: CGFloat`
  - `UIColor.wcagContrastRatio(against other: UIColor) -> CGFloat`
  - `UIColor.badgeTextColor(preferring preferred: UIColor?, minimumRatio: CGFloat) -> UIColor`

- [ ] **Step 1: Write the failing tests**

Create `OBAKitTests/Extensions/UIColorWCAGTests.swift`. Swift Testing (there is precedent in `OBAKitTests/Strings/LocalizationTests.swift`); most old tests are XCTest but new tests use Swift Testing.

```swift
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import UIKit
@testable import OBAKitCore

struct UIColorWCAGTests {

    // MARK: - Relative luminance

    @Test func luminanceOfBlackIsZero() {
        #expect(abs(UIColor.black.wcagRelativeLuminance - 0.0) < 0.0001)
    }

    @Test func luminanceOfWhiteIsOne() {
        #expect(abs(UIColor.white.wcagRelativeLuminance - 1.0) < 0.0001)
    }

    // MARK: - Contrast ratio

    @Test func whiteOnBlackIs21ToOne() {
        #expect(abs(UIColor.white.wcagContrastRatio(against: .black) - 21.0) < 0.01)
    }

    @Test func ratioIsSymmetric() {
        let yellow = UIColor(red: 0.96, green: 0.71, blue: 0.20, alpha: 1.0)
        let a = UIColor.white.wcagContrastRatio(against: yellow)
        let b = yellow.wcagContrastRatio(against: .white)
        #expect(abs(a - b) < 0.0001)
    }

    /// #767676 is the canonical WCAG AA boundary gray: white text over it is
    /// almost exactly 4.5:1.
    @Test func whiteOn767676IsTheAABoundary() {
        let gray = UIColor(red: 118.0/255.0, green: 118.0/255.0, blue: 118.0/255.0, alpha: 1.0)
        let ratio = UIColor.white.wcagContrastRatio(against: gray)
        #expect(abs(ratio - 4.54) < 0.01)
    }

    // MARK: - Badge text color decision

    /// The reported bug: Metro's yellow with white text is ~1.8:1. The
    /// decision must reject white and return black (~11:1).
    @Test func metroYellowGetsBlackText() {
        let metroYellow = UIColor(red: 0.96, green: 0.71, blue: 0.20, alpha: 1.0)
        let chosen = metroYellow.badgeTextColor(preferring: .white, minimumRatio: 4.5)
        #expect(chosen == UIColor.black)
    }

    @Test func darkBlueKeepsAgencyWhiteText() {
        let darkBlue = UIColor(red: 0.05, green: 0.15, blue: 0.45, alpha: 1.0)
        let chosen = darkBlue.badgeTextColor(preferring: .white, minimumRatio: 4.5)
        #expect(chosen == UIColor.white)
    }

    @Test func nilPreferredComputesBlackOrWhite() {
        let metroYellow = UIColor(red: 0.96, green: 0.71, blue: 0.20, alpha: 1.0)
        #expect(metroYellow.badgeTextColor(preferring: nil, minimumRatio: 4.5) == UIColor.black)

        let darkBlue = UIColor(red: 0.05, green: 0.15, blue: 0.45, alpha: 1.0)
        #expect(darkBlue.badgeTextColor(preferring: nil, minimumRatio: 4.5) == UIColor.white)
    }

    /// A preferred color passing 4.5 but failing 7.0 must be rejected at the
    /// Increase Contrast threshold. White on #767676 is ~4.54:1.
    @Test func strictThresholdRejectsBorderlinePreferred() {
        let gray = UIColor(red: 118.0/255.0, green: 118.0/255.0, blue: 118.0/255.0, alpha: 1.0)
        #expect(gray.badgeTextColor(preferring: .white, minimumRatio: 4.5) == UIColor.white)
        #expect(gray.badgeTextColor(preferring: .white, minimumRatio: 7.0) == UIColor.black)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
scripts/generate_project OneBusAway
set -o pipefail
xcodebuild build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
```

Expected: **build FAILS** — `value of type 'UIColor' has no member 'wcagRelativeLuminance'`. (Compile failure is this ecosystem's "red": the API doesn't exist yet.)

- [ ] **Step 3: Write the implementation**

Create `OBAKitCore/Extensions/UIColor+WCAG.swift`:

```swift
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit

// WCAG 2.1 contrast math (https://www.w3.org/TR/WCAG21/#dfn-relative-luminance).
// Distinct from `isLightColor`/`contrastingTextColor` in UIKitExtensions.swift,
// which use a perceived-luminance heuristic unsuitable for contrast-ratio checks.
public extension UIColor {

    /// WCAG 2.1 relative luminance: 0 (black) … 1 (white), with piecewise
    /// sRGB linearization.
    var wcagRelativeLuminance: CGFloat {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        func linearize(_ channel: CGFloat) -> CGFloat {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linearize(red) + 0.7152 * linearize(green) + 0.0722 * linearize(blue)
    }

    /// WCAG 2.1 contrast ratio between the receiver and `other`:
    /// 1 (identical) … 21 (black/white). Symmetric.
    func wcagContrastRatio(against other: UIColor) -> CGFloat {
        let lighter = max(wcagRelativeLuminance, other.wcagRelativeLuminance)
        let darker = min(wcagRelativeLuminance, other.wcagRelativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Text color for content drawn over the receiver. Honors `preferred`
    /// (e.g. the agency's GTFS `route_text_color`) when it clears
    /// `minimumRatio`; otherwise returns black or white, whichever contrasts
    /// more. Guarantees the best achievable contrast when no candidate
    /// clears the bar.
    func badgeTextColor(preferring preferred: UIColor?, minimumRatio: CGFloat) -> UIColor {
        if let preferred, preferred.wcagContrastRatio(against: self) >= minimumRatio {
            return preferred
        }

        let blackRatio = UIColor.black.wcagContrastRatio(against: self)
        let whiteRatio = UIColor.white.wcagContrastRatio(against: self)
        return blackRatio >= whiteRatio ? .black : .white
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
set -o pipefail
xcodebuild build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
xcodebuild test-without-building -only-testing:OBAKitTests/UIColorWCAGTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```

Expected: build succeeds; all 8 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add OBAKitCore/Extensions/UIColor+WCAG.swift OBAKitTests/Extensions/UIColorWCAGTests.swift
git commit -m "Add WCAG 2.1 contrast math and badge text-color decision"
```

---

### Task 2: Contrast-aware stop-page badge (OBAKit RouteBadgeView + call sites)

**Files:**
- Modify: `OBAKit/Stops/StopPage/Shared/RouteBadgeView.swift`
- Modify: `OBAKit/Stops/StopPage/Departures/DepartureRowView.swift:108-113`
- Modify: `OBAKit/Stops/StopPage/Departures/GroupedListView.swift:120-153`

**Interfaces:**
- Consumes (Task 1): `UIColor.badgeTextColor(preferring:minimumRatio:)`.
- Produces: `RouteBadgeView(routeShortName:routeColor:routeTextColor:size:)` — new optional `routeTextColor: Color? = nil` parameter, existing call sites without it still compile. Task 4 adds another parameter to this same view.

- [ ] **Step 1: Rewrite the badge with contrast-aware text and Increase Contrast support**

Replace the body of `OBAKit/Stops/StopPage/Shared/RouteBadgeView.swift` (keep the license header comment) with:

```swift
import SwiftUI
import OBAKitCore

/// Rounded-square route identity badge — the only place route color appears in
/// the departure list rows; the trip panel separately uses it for the vehicle
/// glyph and approach timeline. Spec §4.3 still holds: route color never tints
/// countdowns or adherence text.
///
/// Text color is WCAG-aware: the agency's `route_text_color` is honored when
/// it clears the contrast threshold, else black/white is computed. Under
/// system Increase Contrast the gradient flattens and the threshold rises to
/// 7:1 (see docs/superpowers/specs/2026-07-20-stop-ui-accessibility-design.md).
struct RouteBadgeView: View {
    let routeShortName: String
    let routeColor: Color
    var routeTextColor: Color?
    var size: CGFloat = 44

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    @Environment(\.colorSchemeContrast) private var contrast

    private var resolvedTextColor: Color {
        let minimumRatio: CGFloat = contrast == .increased ? 7.0 : 4.5
        let background = UIColor(routeColor)
        let preferred = routeTextColor.map { UIColor($0) }
        return Color(uiColor: background.badgeTextColor(preferring: preferred, minimumRatio: minimumRatio))
    }

    /// The gradient's luminance ramp is a small, intentional deviation from
    /// the flat color the ratio is computed against; Increase Contrast goes
    /// flat so the strict 7:1 tier has no ambiguity.
    private var backgroundStyle: AnyShapeStyle {
        contrast == .increased ? AnyShapeStyle(routeColor) : AnyShapeStyle(routeColor.gradient)
    }

    var body: some View {
        Text(routeShortName)
            .font(.system(size: (routeShortName.count <= 2 ? 18 : 13) * scale, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(resolvedTextColor)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .frame(width: size * scale, height: size * scale)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: size * scale * 0.28, style: .continuous))
            .accessibilityHidden(true) // route name is in the row's combined label
    }
}
```

Note: `import OBAKitCore` may already be implied via other imports but add it explicitly; `badgeTextColor` lives there.

- [ ] **Step 2: Pass the agency text color from DepartureRowView**

In `OBAKit/Stops/StopPage/Departures/DepartureRowView.swift`, replace the `routeBadge` computed property:

```swift
    private var routeBadge: some View {
        RouteBadgeView(
            routeShortName: departure.routeShortName,
            routeColor: Color(uiColor: departure.route.color ?? ThemeColors.shared.brand),
            routeTextColor: departure.route.textColor.map { Color(uiColor: $0) }
        )
    }
```

- [ ] **Step 3: Pass the agency text color from GroupedListView**

In `OBAKit/Stops/StopPage/Departures/GroupedListView.swift`, both `RouteBadgeView` calls inside `headerPrimaryRow(next:status:routeColor:)` (lines 124 and 136) become:

```swift
RouteBadgeView(routeShortName: next.routeShortName, routeColor: routeColor, routeTextColor: next.route.textColor.map { Color(uiColor: $0) }, size: 48)
```

(Other `RouteBadgeView` call sites — `BookmarkCardView`, `TripLiveActivityCardView` — are intentionally untouched: with `routeTextColor` nil they now get computed black/white instead of hardcoded white, which is the always-on fix, and wiring their agency color is out of scope.)

- [ ] **Step 4: Build and run the full stop-page-adjacent test suite**

```bash
set -o pipefail
xcodebuild build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
xcodebuild test-without-building -only-testing:OBAKitTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```

Expected: build succeeds, OBAKitTests PASS (no existing test asserts white badge text; if one does, update it to the new decision and say so in the commit).

- [ ] **Step 5: Commit**

```bash
git add OBAKit/Stops/StopPage/Shared/RouteBadgeView.swift OBAKit/Stops/StopPage/Departures/DepartureRowView.swift OBAKit/Stops/StopPage/Departures/GroupedListView.swift
git commit -m "Make stop page route badge text WCAG contrast-aware"
```

---

### Task 3: Contrast-aware widget badge (OBAKitCore RouteBadgeView)

**Files:**
- Modify: `OBAKitCore/UI/RouteBadgeView.swift`
- Modify: `OBAKitCore/UI/TripLiveActivityCardView.swift:46-50` (no signature change — verify only)

**Interfaces:**
- Consumes (Task 1): `UIColor.badgeTextColor(preferring:minimumRatio:)`.
- Produces: `RouteBadgeView(routeShortName:routeColor:routeTextColor:size:)` (public, OBAKitCore) — new optional `routeTextColor: Color? = nil` init parameter; existing callers compile unchanged.

- [ ] **Step 1: Mirror the contrast logic in the public badge**

Replace the struct in `OBAKitCore/UI/RouteBadgeView.swift` (keep the license header):

```swift
import SwiftUI

/// Rounded-square route identity badge. Public so the widget extension can use it.
///
/// Text color is WCAG-aware (same decision as the stop page's internal
/// `RouteBadgeView`): agency text color when it clears the threshold, else
/// computed black/white; Increase Contrast flattens the gradient and raises
/// the threshold to 7:1. Note: in `accented`/`vibrant` widget rendering modes
/// the system tints everything and this logic is moot; it matters in
/// `fullColor` rendering.
public struct RouteBadgeView: View {
    public let routeShortName: String
    public let routeColor: Color
    public var routeTextColor: Color?
    public var size: CGFloat = 44

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    @Environment(\.colorSchemeContrast) private var contrast

    public init(routeShortName: String, routeColor: Color, routeTextColor: Color? = nil, size: CGFloat = 44) {
        self.routeShortName = routeShortName
        self.routeColor = routeColor
        self.routeTextColor = routeTextColor
        self.size = size
    }

    private var resolvedTextColor: Color {
        let minimumRatio: CGFloat = contrast == .increased ? 7.0 : 4.5
        let background = UIColor(routeColor)
        let preferred = routeTextColor.map { UIColor($0) }
        return Color(uiColor: background.badgeTextColor(preferring: preferred, minimumRatio: minimumRatio))
    }

    private var backgroundStyle: AnyShapeStyle {
        contrast == .increased ? AnyShapeStyle(routeColor) : AnyShapeStyle(routeColor.gradient)
    }

    public var body: some View {
        Text(routeShortName)
            .font(.system(size: (routeShortName.count <= 2 ? 18 : 13) * scale, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(resolvedTextColor)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .frame(width: size * scale, height: size * scale)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: size * scale * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}
```

- [ ] **Step 2: Verify `TripLiveActivityCardView` still compiles unchanged**

It calls `RouteBadgeView(routeShortName:routeColor:size:)`; the new parameter defaults to nil, so no edit. Confirm by building.

- [ ] **Step 3: Build for testing (includes OBAKitCore and extensions)**

```bash
set -o pipefail
xcodebuild build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
```

Expected: build succeeds. (Extension-safety: the new code touches only UIColor/SwiftUI — safe.)

- [ ] **Step 4: Commit**

```bash
git add OBAKitCore/UI/RouteBadgeView.swift
git commit -m "Make shared/widget route badge text WCAG contrast-aware"
```

---

### Task 4: Reduced-color badge variant (stop page only)

**Files:**
- Modify: `OBAKit/Stops/StopPage/Shared/RouteBadgeView.swift` (as written by Task 2)
- Modify: `OBAKit/Stops/StopPage/Departures/DepartureRowView.swift` (as written by Task 2)
- Modify: `OBAKit/Stops/StopPage/Departures/GroupedListView.swift` (as written by Task 2)

**Interfaces:**
- Consumes: Task 2's `RouteBadgeView` (stop-page copy).
- Produces: `RouteBadgeView` gains `var reducedColors: Bool = false`. Call sites read `@AppStorage("stopUIReducedColors")` — the literal key string Task 5's setting writes. The stop page root already applies `.defaultAppStorage(application.userDefaults)` (see `StopPageViewController.swift:22`), so plain `@AppStorage` hits the right suite.

- [ ] **Step 1: Add the reduced-color rendering to the stop-page badge**

In `OBAKit/Stops/StopPage/Shared/RouteBadgeView.swift`, add the property and split the body (full struct after the edit; doc comment gains one line):

```swift
struct RouteBadgeView: View {
    let routeShortName: String
    let routeColor: Color
    var routeTextColor: Color?
    var size: CGFloat = 44
    /// When true (Settings > Accessibility > "Reduce colors on stop page"),
    /// route color shrinks to a thin vertical bar and the route number uses
    /// the standard label color — same information, minimal color area.
    var reducedColors: Bool = false

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    @ScaledMetric(relativeTo: .body) private var barWidth: CGFloat = 5
    @Environment(\.colorSchemeContrast) private var contrast

    private var resolvedTextColor: Color {
        let minimumRatio: CGFloat = contrast == .increased ? 7.0 : 4.5
        let background = UIColor(routeColor)
        let preferred = routeTextColor.map { UIColor($0) }
        return Color(uiColor: background.badgeTextColor(preferring: preferred, minimumRatio: minimumRatio))
    }

    private var backgroundStyle: AnyShapeStyle {
        contrast == .increased ? AnyShapeStyle(routeColor) : AnyShapeStyle(routeColor.gradient)
    }

    private var badgeFont: Font {
        .system(size: (routeShortName.count <= 2 ? 18 : 13) * scale, weight: .heavy)
    }

    var body: some View {
        Group {
            if reducedColors {
                reducedBody
            } else {
                standardBody
            }
        }
        .frame(width: size * scale, height: size * scale)
        .accessibilityHidden(true) // route name is in the row's combined label
    }

    private var standardBody: some View {
        Text(routeShortName)
            .font(badgeFont)
            .monospacedDigit()
            .foregroundStyle(resolvedTextColor)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .frame(width: size * scale, height: size * scale)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: size * scale * 0.28, style: .continuous))
    }

    /// Same frame as the standard badge so departure rows keep their column
    /// alignment when the setting flips.
    private var reducedBody: some View {
        HStack(spacing: 6 * scale) {
            Capsule(style: .continuous)
                .fill(routeColor)
                .frame(width: barWidth, height: size * scale)
            Text(routeShortName)
                .font(badgeFont)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}
```

(Note `barWidth` is itself a `@ScaledMetric`, so the bar tracks Dynamic Type per the spec. `standardBody` keeps its own inner `.frame` so the rounded-rect background hugs the square exactly as before; the outer shared frame is a no-op for it.)

- [ ] **Step 2: Drive it from the departure row**

In `OBAKit/Stops/StopPage/Departures/DepartureRowView.swift`, add alongside the other property wrappers (after line 38's `@ScaledMetric`):

```swift
    @AppStorage("stopUIReducedColors") private var reducedColors = false
```

and update `routeBadge`:

```swift
    private var routeBadge: some View {
        RouteBadgeView(
            routeShortName: departure.routeShortName,
            routeColor: Color(uiColor: departure.route.color ?? ThemeColors.shared.brand),
            routeTextColor: departure.route.textColor.map { Color(uiColor: $0) },
            reducedColors: reducedColors
        )
    }
```

- [ ] **Step 3: Drive it from the grouped list**

In `OBAKit/Stops/StopPage/Departures/GroupedListView.swift`, add the same `@AppStorage` property to the view struct containing `headerPrimaryRow` (top of the struct, near its other `@Environment` properties):

```swift
    @AppStorage("stopUIReducedColors") private var reducedColors = false
```

and both badge calls become:

```swift
RouteBadgeView(routeShortName: next.routeShortName, routeColor: routeColor, routeTextColor: next.route.textColor.map { Color(uiColor: $0) }, size: 48, reducedColors: reducedColors)
```

(Parameter order: `reducedColors` is declared after `size`, so this label order matches the memberwise initializer.)

- [ ] **Step 4: Build, test, and eyeball both modes**

```bash
set -o pipefail
xcodebuild build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
xcodebuild test-without-building -only-testing:OBAKitTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```

Expected: PASS. Visual verification of the reduced mode happens in Task 5 step 4, once the Settings toggle exists to flip it — don't hand-write app-group defaults here.

- [ ] **Step 5: Commit**

```bash
git add OBAKit/Stops/StopPage/Shared/RouteBadgeView.swift OBAKit/Stops/StopPage/Departures/DepartureRowView.swift OBAKit/Stops/StopPage/Departures/GroupedListView.swift
git commit -m "Add reduced-color route badge variant to the stop page"
```

---

### Task 5: The setting — UserDataStore property + Settings switch

**Files:**
- Modify: `OBAKitCore/Models/UserData/UserDataStore.swift` (protocol ~line 37; keys struct lines 380-403; `register(defaults:)` lines 408-412; new property after `debugMode` lines 421-428)
- Modify: `OBAKit/Settings/SettingsViewController.swift` (`form.setValues` lines 53-68; `saveFormValues` lines 79-124; `accessibilitySection` lines 202-221)

**Interfaces:**
- Consumes: nothing from other tasks at compile time; at runtime the key string must match Task 4's `@AppStorage("stopUIReducedColors")` exactly.
- Produces: `UserDataStore.stopUIReducedColors: Bool { get set }` (protocol + `UserDefaultsStore` implementation).

- [ ] **Step 1: Add the property to the UserDataStore protocol**

In `OBAKitCore/Models/UserData/UserDataStore.swift`, directly below `var debugMode: Bool { get set }` (line 37):

```swift
    /// Whether the stop page renders route badges in reduced-color form
    /// (thin route-color bar + label-colored text). Surfaced in
    /// Settings > Accessibility.
    var stopUIReducedColors: Bool { get set }
```

- [ ] **Step 2: Add the key, default, and implementation to UserDefaultsStore**

In the `UserDefaultsKeys` struct (after line 402):

```swift
        // Deliberately dot-free, unlike its neighbors: the stop page observes
        // this key via @AppStorage, whose KVO treats dots as key-path
        // separators and silently never fires. See the accessibility spec.
        static let stopUIReducedColors = "stopUIReducedColors"
```

In `init(userDefaults:)`, extend `register(defaults:)`:

```swift
        self.userDefaults.register(defaults: [
            UserDefaultsKeys.debugMode: false,
            UserDefaultsKeys.stopUIReducedColors: false,
            UserDefaultsKeys.walkingSpeedMetersPerSecond: WalkingSpeed.defaultMetersPerSecond,
            UserDefaultsKeys.walkingSpeedSource: WalkingSpeedSource.manual.rawValue
        ])
```

After the `debugMode` property (line 428), add:

```swift
    // MARK: - Stop UI Reduced Colors

    public var stopUIReducedColors: Bool {
        get {
            return userDefaults.bool(forKey: UserDefaultsKeys.stopUIReducedColors)
        }
        set {
            userDefaults.set(newValue, forKey: UserDefaultsKeys.stopUIReducedColors)
        }
    }
```

Check for other `UserDataStore` conformers before building: `grep -rn ': UserDataStore' OBAKit* Apps` — if a test mock conforms, add the property there too (a plain stored `var stopUIReducedColors = false` suffices in a mock).

- [ ] **Step 3: Add the switch to Settings > Accessibility**

In `OBAKit/Settings/SettingsViewController.swift`:

Near the other tag constants (e.g. below line 226's `walkingSpeedUseHealthKitKey`):

```swift
    private let stopUIReducedColorsTag = "stopUIReducedColors"
```

In `accessibilitySection` (before `return section`, line 220):

```swift
        section <<< SwitchRow {
            $0.tag = stopUIReducedColorsTag
            $0.title = OBALoc("settings_controller.accessibility_section.reduce_stop_colors", value: "Reduce colors on stop page", comment: "Settings > Accessibility section > Toggle that renders stop page route badges as a thin color bar beside plain text instead of a colored square")
        }
```

In `form.setValues([...])` (line 53-68), add:

```swift
            stopUIReducedColorsTag: application.userDataStore.stopUIReducedColors,
```

In `saveFormValues()` (near the `debugEnabled` block, line 109-111), add:

```swift
        if let reducedColors = values[stopUIReducedColorsTag] as? Bool {
            application.userDataStore.stopUIReducedColors = reducedColors
        }
```

- [ ] **Step 4: Build, test, and verify end-to-end in the simulator**

```bash
set -o pipefail
xcodebuild build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
xcodebuild test-without-building -only-testing:OBAKitTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```

Expected: PASS. Then run the app: More tab > Settings > Accessibility > flip "Reduce colors on stop page" > open a stop. Badges must render as bar + plain text. Flip back; colored squares return. If a stop page is left open behind Settings, it must update live on return (this is the dot-free-key guarantee).

- [ ] **Step 5: Commit**

```bash
git add OBAKitCore/Models/UserData/UserDataStore.swift OBAKit/Settings/SettingsViewController.swift
git commit -m "Add 'Reduce colors on stop page' accessibility setting"
```

---

### Task 6: Visual verification pass + SwiftLint

**Files:**
- No new files. Screenshots go to the session scratchpad, not the repo.

**Interfaces:** none — this is the ship-gate check for the whole feature.

- [ ] **Step 1: SwiftLint**

```bash
scripts/swiftlint.sh
```

Expected: no new violations in touched files.

- [ ] **Step 2: Contrast scenarios in the simulator**

Run the app on 'iPhone 17 Pro' against a region with colored routes (Puget Sound default; Metro route 48 is yellow). Verify, with screenshots at each step:

1. Default: yellow badges show **black** route numbers (the bug fix — compare against the user report's white-on-yellow).
2. Dark route colors still show white/agency text.
3. Settings > Accessibility > Increase Contrast (simulator: Settings app > Accessibility > Display & Text Size > Increase Contrast): badges go flat (no gradient) and text still passes visually.
4. Reduce Motion ON: header "Updated" dot and skeleton pulses are static (pre-existing behavior — regression check only).
5. Reduced-colors toggle ON: vertical bar + plain text in both chronological and by-route (grouped) modes, rows still aligned; accessibility Dynamic Type size scales the bar and text.

- [ ] **Step 3: Report**

Summarize pass/fail per scenario with the screenshots. Any failure loops back to the owning task before proceeding.

- [ ] **Step 4: Final commit (only if fixes were needed)**

```bash
git add -A && git commit -m "Fix visual issues found in accessibility verification"
```

---

## Self-Review Notes

- **Spec coverage:** §1 always-on contrast → Tasks 1-3; §2 Increase Contrast → Tasks 2-3, Reduce Motion verified-only → Task 6 step 2.4, Reduce Transparency / Differentiate Without Color → no-change per spec; §3 reduced-color mode → Tasks 4-5; spec Testing section → Tasks 1 and 6.
- **Key-string consistency:** `"stopUIReducedColors"` appears in Task 4 (`@AppStorage` ×2), Task 5 (`UserDefaultsKeys`, tag constant). All four must be the identical dot-free literal.
- **Signature consistency:** `badgeTextColor(preferring:minimumRatio:)` (Tasks 1→2→3); `RouteBadgeView(routeShortName:routeColor:routeTextColor:size:)` + stop-page-only `reducedColors:` (Tasks 2→4; memberwise label order `routeTextColor` before `size`, `reducedColors` last).
