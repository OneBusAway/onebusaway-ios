# Stop UI Accessibility: Route Badge Contrast & Reduced-Color Mode

**Date:** 2026-07-20
**Branch:** `stop-accessibility`
**Status:** Approved

## Background

A rider with low vision reported that the new stop page's route badges are
unreadable: the badge renders the route short name in hardcoded white over the
agency-provided route color, which for King County Metro's yellow produces a
contrast ratio far below the WCAG 2.1 AA minimum. Distinguishing route 43 from
route 48 determines which stop she uses; this is a real navigation failure, not
a cosmetic issue.

Root cause: `RouteBadgeView` (two near-duplicate copies —
`OBAKit/Stops/StopPage/Shared/RouteBadgeView.swift` for the stop page and
`OBAKitCore/UI/RouteBadgeView.swift` for the widget) uses
`.foregroundStyle(.white)` unconditionally over `routeColor.gradient`. The GTFS
feed's `route_text_color` (`Route.textColor`) is decoded but ignored. No WCAG
contrast math exists in the codebase (only a perceived-luminance heuristic,
`UIColor.contrastingTextColor`, used by legacy/widget code). The stop page
reads no contrast-related accessibility environment values.

## Goals

1. Route badge text always meets WCAG 2.1 AA contrast against its background,
   with no user action required.
2. The stop page respects system accessibility settings: Increase Contrast and
   Reduce Motion.
3. An opt-in "reduced colors" presentation replaces the colored badge with a
   thin vertical route-color bar beside the route number in standard label
   color.

## Non-Goals

- The legacy UIKit `StopViewController` / `StopArrivalView`.
- Map route labels or any screen other than the new stop page (plus the shared
  badge used by the widget, which inherits the contrast fix in `fullColor`
  rendering; in `accented`/`vibrant` widget modes the system's own tinting
  overrides both the route color and the text color, so the fix is moot there).
- Changing the green/red/blue departure-status colors. The words "on time" /
  "early" / "delayed" already carry that information redundantly in text.
- Merging the two `RouteBadgeView` copies into one view.

## Design

### 1. Always-on contrast fix

**New WCAG helpers** in OBAKitCore (extension-safe), as a `UIColor` extension
in a new file (e.g. `OBAKitCore/Extensions/UIColor+WCAG.swift`):

- `wcagRelativeLuminance` — WCAG 2.1 relative luminance with proper sRGB
  linearization (piecewise `c/12.92` vs `((c+0.055)/1.055)^2.4`), not the
  existing `0.299/0.587/0.114` quick heuristic.
- `wcagContrastRatio(with:)` — `(L1 + 0.05) / (L2 + 0.05)`.

**One shared decision function** (also OBAKitCore, so the stop page and widget
badges use identical logic):

```
badgeTextColor(background: UIColor,
               agencyTextColor: UIColor?,
               minimumRatio: CGFloat) -> UIColor
```

Rules:
- If `agencyTextColor` is provided and its contrast ratio against
  `background` is ≥ `minimumRatio`, use it (respects agency branding).
- Otherwise return black or white, whichever has the higher ratio against
  `background`.

**Badge wiring** (both `RouteBadgeView` copies):
- Gain an optional `routeTextColor` parameter; `DepartureRowView` and the
  widget pass `route.textColor` through.
- Normal presentation: `minimumRatio` = 4.5 (AA). Background keeps the
  existing `.gradient` fill; the ratio is intentionally computed against the
  flat base color, an approximation — the gradient's lighter band has
  marginally lower contrast, and the Increase Contrast branch removes the
  ambiguity where it matters by going flat.
- Threshold note: WCAG large text (≥14 pt bold) and Apple's Accessibility
  Inspector (bold → 3:1 at all sizes) would accept 3:1 for the heavy badge
  text, but the badge can render as small as 13 pt, so we hold the stricter
  4.5:1 floor everywhere rather than special-casing by size.
- Under system Increase Contrast (`@Environment(\.colorSchemeContrast) ==
  .increased`): the badge uses a flat fill (no gradient) and raises
  `minimumRatio` to 7.0 (AAA) before falling back to computed black/white.

Result for the reported case: black text on Metro's yellow (~11:1) instead of
white (~1.8:1).

### 2. System accessibility settings

- **Reduce Motion:** verified already handled — implementation review found
  all three `repeatForever` pulse sites (`StopPageHeaderView.swift:201,235`,
  `TripDetailPanelView.swift:193`) are already gated on
  `@Environment(\.accessibilityReduceMotion)` with `guard !reduceMotion`
  plus static-opacity fallbacks, matching the `RealtimeGlyph` precedent
  (`RealtimeGlyph.swift:26`). An earlier grep saw the `repeatForever` calls
  but missed the surrounding guards. No code change required; the
  implementation plan keeps a verification-only check.
  One-shot layout transitions (`withAnimation(.snappy)` toggles)
  are unchanged: Apple's mandatory guidance covers automatic and repetitive
  motion (the pulses), while de-motioning transitions is a best practice we
  partially meet already — `.snappy` is a stiff, low-bounce spring, and none
  of the gated toggles animate large positional or scale changes.
  Implementation should verify that last point per call site.
- **Increase Contrast:** covered in §1 (flat fill + 7:1 threshold).
- **Reduce Transparency:** no change needed; the page's `.ultraThinMaterial`
  is a system material that adapts automatically.
- **Differentiate Without Color:** no change needed; every color-coded fact on
  the page (route identity, schedule status) is already duplicated in text.

### 3. Opt-in reduced-color mode

**Setting storage:** new `Bool` property on `UserDataStore`, registered
default `false`, following the existing `debugMode` pattern — but with the
deliberately dot-free defaults key `stopUIReducedColors` (not
`UserDataStore.stopUIReducedColors`): the stop page reads it via
`@AppStorage`, which observes UserDefaults through KVO, and KVO treats dots
in a key as key-path separators, silently breaking live updates. The page
already uses dot-free `@AppStorage` keys for this reason
(`stopViewShowsServiceAlerts`).

**Settings UI:** a `SwitchRow` in the existing **Accessibility** section of
`SettingsViewController` ("Reduce colors on stop page"), seeded in
`form.setValues` and persisted in the save path like its neighbors.

**Presentation:** when enabled, the stop page's `RouteBadgeView` renders as:
- a vertical capsule bar in the route color, ~5 pt wide × badge height, and
- the route short name in `.primary` label color beside it,
- inside the same frame width as the standard badge, so the departure rows
  keep their column alignment.

Both the bar width and the frame scale with Dynamic Type via `@ScaledMetric`,
matching the standard badge's existing scaling — fixed points would undercut
the low-vision users this mode serves.

The mode is read by the SwiftUI stop page via the app's `UserDefaults` suite
(the same suite `UserDataStore` writes to) so the page updates when the
setting changes. The widget keeps the standard badge; this mode is app-only.

Scope: route badge only. Status colors are untouched (see Non-Goals).

## Testing

Unit tests in `OBAKitTests`:
- Relative luminance and contrast ratio against known WCAG reference values
  (e.g. white/black = 21:1, white on #767676 ≈ 4.54:1).
- Decision function: white-on-yellow rejected → black chosen; agency text
  color honored when passing; rejected when failing; 7:1 threshold behavior.

Manual verification in the simulator: standard badge with a yellow route,
Increase Contrast on/off, Reduce Motion on/off, and the reduced-color toggle.

## Decisions Log

- Agency `route_text_color` is respected when it passes WCAG, otherwise
  computed black/white — always-on, not behind a setting. (Approved)
- Reduced-color mode affects the badge only, not status colors. (Approved)
- Reduced-color mode is a manual toggle only; it does not auto-engage from
  Differentiate Without Color. Increase Contrast independently hardens the
  standard badge. (Approved)
