# Stop sheet: plain header and a fixed bottom toolbar

**Date:** 2026-08-07
**Branch:** `feature/stop-page-view-sheet`
**Supersedes parts of:** `2026-07-31-stop-details-sheet-design.md`, `2026-08-02-scroll-to-top-design.md`

## Summary

Two changes to `StopDetailsSheetView`, the SwiftUI stop sheet over the map panel:

1. Replace the dark full-bleed map header (`StopPageHeaderView`) with the existing
   light, map-free `StopPageSheetHeaderView`.
2. Remove the collapsing-header behaviour, and move the action row from a
   scroll-tracking overlay to a fixed glass capsule pinned at the bottom.

Both views already exist and are used by the pushed `StopPageView`. This change
adopts them in the sheet; it does not create a new header or a new toolbar.

## Motivation

The map header repeats what the rider can already see. The sheet sits over a
live map, so a dark map card inside it spends the sheet's scarce vertical space
showing the same thing twice. `StopPageSheetHeaderView` was written for exactly
this reason and says so in its own doc comment.

The collapsing behaviour exists to keep the action row reachable while a tall
header scrolls past. With a short header there is nothing tall to collapse, and
a permanently-visible bottom toolbar makes the actions reachable at every scroll
position without any scroll-position arithmetic at all.

## Decisions

These were settled during brainstorming and are not open in implementation:

| Question | Decision |
| --- | --- |
| Pinned top bar | **Stays.** Keeps title, Refresh and Close. |
| Refresh | **Stays in the top bar**, not the capsule. |
| Capsule contents | The four actions: Schedule, Filter, Bookmark, More. |
| Capsule form | **Keeps captions** under each glyph, so it spans most of the width. |
| Header position | **Scrolls away** as an ordinary list row. Not pinned. |
| Title fade | **Kept.** The bar names the stop once the header has scrolled off. |
| Scroll-to-top | **Kept**, bottom-trailing, floating above the capsule. |

## Design

### 1. Header swap

`StopDetailsSheetView.headerRows(showsLoadingState:navigation:)` builds
`StopPageSheetHeaderView` where it currently builds `StopPageHeaderView`, and
`StopPageSheetHeaderPlaceholderView` where it builds
`StopPageHeaderPlaceholderView`.

The header stays inside the same `Section`, keeps the section's
`.id(Self.topRowID)` so `ScrollViewReader` can still scroll to it, and keeps the
`listRowInsets`/`listRowBackground`/`listRowSeparator` treatment the map card
had. It draws its own background and trailing `Divider`, so nothing else is
needed to separate it from the departures.

Two additions, both defaulted so the pushed `StopPageView` is untouched:

- `StopPageSheetHeaderView.showsCloseButton: Bool = true` and the same on
  `StopPageSheetHeaderPlaceholderView`. The sheet passes `false`, because the
  top bar already carries Close. Without this the rider sees two ✕ roughly 10pt
  apart.
- The sheet owns a plain `StopMapFocus()` and passes it in.

`isCollapsed` is left at its default `false`. It exists for the old FloatingPanel
`.tip` detent, which `.stopDetails` (`[.large]` only) does not have.

`StopPageActionPresenter.loadSnapshot` is **not** removed — the pushed
`StopPageView` still renders the map card and still needs it.

#### Accepted consequence: inert route chips

`StopPageSheetHeaderView`'s route chips decorate themselves from `StopMapFocus`
— route colour, live-vehicle dot, tap-to-focus. Map focus is wired only through
the UIKit `MapViewController`, which calls `StopPageViewController.attach(focus:)`.
The sheet sits over the SwiftUI `MapPanelRootView`, which has no such channel.

With an unwired `StopMapFocus()` the chips render as plain grey capsules,
`isFocusable` returns `false` for every route, so they carry no `.isButton`
trait and their tap gesture is a no-op. This is a documented, intended mode:
*"Always non-nil, even for presentations that never attach to a map — an inert
instance is simpler than an Optional"*, and *"a chip with no match renders plain
and is inert."*

So in the sheet the chips are a static list of routes served. From the pushed
page they remain fully interactive. Building a focus channel for the SwiftUI map
panel is a separate feature and is explicitly out of scope here.

### 2. Collapsing removed

Deleted from `StopDetailsSheetView`:

- `actionRowOffset`
- `mapCardHeight`, `topBarHeight`, `actionRowHeight` and the three
  `onGeometryChange` modifiers that feed them
- the `Color.clear` spacer row in `headerRows` — it existed only to reserve
  space for an overlaid action row
- `.overlay(alignment: .top) { actionRowOverlay(navigation:) }`
- `snapshotTraits` and the `@Environment(\.displayScale)` that feeds it
- `.contentMargins(.bottom, Self.scrollToTopClearance, for: .scrollContent)` and
  the `scrollToTopClearance` constant

Kept: `scrollOffset`, `viewportHeight`, both `onScrollGeometryChange`
observations, `ScrollToTopVisibility`, `titleProgress` and `titleFadeDistance`.

#### Rename: `StopSheetHeaderCollapse` → `StopSheetTitleFade`

`StopSheetHeaderCollapse.progress(scrollOffset:collapsibleHeight:)` is a clamped
`scrollOffset / height`. Its only caller is the top bar's title fade, and after
this change nothing collapses, so the name describes something that no longer
exists.

Rename the type to `StopSheetTitleFade` and the method to
`progress(scrollOffset:fadeDistance:)`. The file and
`OBAKitTests/Sheet/StopSheetHeaderCollapseTests.swift` are renamed to match. The
arithmetic and the tests' assertions do not change.

Its doc comment must be rewritten rather than carried over: the existing text
explains the oscillation hazard in terms of a collapsing header and an overlaid
action row, neither of which will exist. The hazard itself is still worth
recording — a `safeAreaInset` whose *height* tracks scroll position feeds back on
itself and pegs the main thread — so the note stays, re-aimed at the fixed-height
insets this design introduces.

### 3. Fixed bottom capsule

`StopPageActionRow` keeps its four caption-under-glyph columns and its
accessibility-size horizontal scrolling. It loses
`.background(Color(uiColor: .systemBackground))` and its bottom `Divider()`, and
gains a glass capsule surface — `regularGlassEffectIfAvailable(in: Capsule())`,
which already falls back to `.regularMaterial` below iOS 26 — plus horizontal
and bottom padding so it floats clear of the sheet's edges.

It is attached with `.safeAreaInset(edge: .bottom, spacing: 0)`.

**Why `safeAreaInset` and not an overlay.** Earlier work on this branch
established that a scroll-driven `safeAreaInset` hangs the app. The hazard was
specifically an inset whose *height* was a function of scroll position: the
inset shifted the offset, which changed progress, which resized the inset. A
constant-height inset has no such loop, and is how the pushed `StopPageView`
already mounts `StopPageToolbar`. Using it here means the list reserves the
capsule's height automatically, which is what lets the hand-tuned 72pt
`scrollToTopClearance` and its `contentMargins` call be deleted: the last
departure can no longer sit under the capsule.

The capsule renders whether or not the stop has loaded. `StopPageActionRowState`
already gates each item — including `hasStop`, added earlier — so a failed first
fetch shows a capsule of correctly-disabled controls rather than no chrome.

`scrollToTopOverlay` keeps its `.overlay(alignment: .bottomTrailing)`. Because
the capsule is now a bottom safe-area inset, the overlay's own bottom edge is
already above it, and its existing `.padding(.bottom, 24)` becomes clearance
above the capsule rather than above the sheet's edge.

## Testing

| Suite | Change |
| --- | --- |
| `StopSheetHeaderCollapseTests` | Renamed to `StopSheetTitleFadeTests`; assertions unchanged. |
| `StopPageActionRowStateTests` | Unchanged. |
| `ScrollToTopVisibilityTests` | Unchanged. |
| `StopPageSheetHeaderLayoutTests` | Unchanged — it exercises the collapsed-height budget, which this does not touch. |
| `AppSheetViewFactoryTests` | Unchanged. |

New coverage: the sheet hides the header's close button while the pushed page
keeps it. This is the one regression neither call site makes visible on its own,
and it is what stands between the rider and two stacked ✕ buttons. Assert it on
the value, not by inspecting a rendered view — `showsCloseButton` is a plain
`Bool` on both header views.

No new test is added for the capsule's glass surface or its position; those are
appearance, and the branch does not snapshot-test.

## Out of scope

- Wiring `StopMapFocus` through the SwiftUI map panel (see above).
- Any change to the pushed `StopPageView` or `StopPageViewController`.
- Any change to `StopPageToolbar`, which remains the pushed page's bottom chrome.
- A medium detent for `.stopDetails`, which stays `[.large]`-only.

## Risks

**The capsule and the home indicator.** `safeAreaInset(edge: .bottom)` composes
with the existing bottom safe area, so the capsule sits above the home
indicator. Worth confirming on a device with one, since the sheet is
`[.large]`-only and reaches the bottom edge.

**Dynamic Type.** At accessibility sizes `StopPageActionRow` becomes a
horizontal scroll view. Inside a capsule that clips to its shape, the scroll
must still work and must not show a scroll indicator over the glass. The row
already sets `showsIndicators: false`.

**Title fade with a short header.** The header is roughly 110pt; the fade
completes over `titleFadeDistance` = 120pt. These are independent by design —
the fade drives opacity only and has nothing to stay registered with — but the
title will finish fading in at roughly the moment the header leaves. That is the
intended effect and needs no coupling between the two numbers.
