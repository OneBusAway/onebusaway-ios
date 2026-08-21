# Stop Sheet Scroll-to-Top Button — Design

**Date:** 2026-08-02
**Branch:** `feature/stop-page-view-sheet`

## Summary

Add a floating scroll-to-top button to the stop details sheet. It appears once
the rider has scrolled roughly a full viewport down, sits bottom-trailing over
the list, and returns the list to the top when tapped.

## Context

`StopDetailsSheetView` already tracks scroll position: `onScrollGeometryChange`
feeds `scrollOffset`, which drives the pinned title's opacity and the action
row's overlay offset. Both are read-only observations — nothing derived from
scroll position affects layout that the scroll view can observe.

**That constraint is the most important thing in this document.** An earlier
version of this sheet drove the height of a top `safeAreaInset` from scroll
position. Measured on device, collapsing a 170 pt header shifted
`contentOffset.y + contentInsets.top` by exactly 170 — the metric is not
inset-invariant — so any mid-range value oscillated (progress → inset → offset →
progress) until the main thread was pegged and the whole app stopped responding.
Anything added here must not reintroduce that cycle.

The sheet's chrome is three glass surfaces: the pinned top bar, the pinned action
row overlay, and the map card. A fourth surface should match them.

## Decisions

| Decision | Choice | Rationale |
| --- | --- | --- |
| Trigger | Scrolled more than one viewport height | The convention (Safari, App Store); useful through the whole list, not just at the end |
| Cell-count gate | None | Redundant — short content cannot scroll a viewport, so the button cannot appear. See below |
| Placement | Floating circle, bottom-trailing | Thumb-reachable, no permanent layout cost, matches the existing glass chrome |
| Scroll mechanism | `ScrollPosition` (iOS 18) | No sentinel row and no ids; `ScrollViewReader` needs something to scroll to |
| Bottom content margin | Fixed constant | A conditional margin would be layout driven by scroll position — the hang |

### Why no cell-count gate

The original request asked to "show it at reasonable cells count". With a
one-viewport trigger that gate is redundant: a stop with three departures cannot
scroll a full viewport, so the button never appears. Scroll distance measures the
real thing, and adapts automatically to everything that changes how much content
a screenful holds — Dynamic Type, expanded trip panels, the survey and donation
cards, and grouped-versus-chronological mode.

An explicit count would be a magic number that can disagree with reality: eight
departures with expanded panels scroll further than twelve collapsed ones, so a
count threshold can suppress the button exactly when it would help most.

## Architecture

### New: `ScrollToTopVisibility` (`OBAKit/Sheet/Content/Stop/Details/`)

A `nonisolated enum` with one pure function:

```swift
static func shouldShow(scrollOffset: CGFloat, viewportHeight: CGFloat) -> Bool
```

Returns `true` when `scrollOffset > viewportHeight`, and `false` when
`viewportHeight <= 0` so a sheet that has not been laid out yet cannot show the
button.

Extracted from the view for the reason `StopSheetHeaderCollapse` and
`StopPageActionRowState` were: it is the only part of this feature a unit test
can reach, and it is where an off-by-one would live.

### New: `ScrollToTopButton` (`OBAKit/Sheet/Content/Stop/Details/`)

A plain-value view:

```swift
ScrollToTopButton(isVisible: Bool, action: () -> Void)
```

A glass circle containing `chevron.up`, styled with
`liquidGlassButtonStyle(borderShape: .circle, fallbackShape: Circle())` and
`.tint(.primary)` — the same treatment `StopPageActionRow` and
`StopDetailsSheetTopBar` use, so the sheet's chrome reads as one system rather
than three unrelated surfaces.

Icon-only, so it carries a localised `accessibilityLabel` through
`OBALoc`. Hidden from accessibility entirely when not visible, so VoiceOver users
do not land on an invisible control.

### Modified: `StopDetailsSheetView`

Four additions:

1. `@State private var scrollPosition = ScrollPosition()`, applied to the list
   with `.scrollPosition($scrollPosition)`.
2. `@State private var viewportHeight: CGFloat`, fed by a **second**
   `onScrollGeometryChange` reading `containerSize.height`. Kept separate from the
   existing offset tracker so each observation stays single-purpose; both are
   read-only and neither affects layout.
3. `.overlay(alignment: .bottomTrailing) { scrollToTopButton }`, following the
   action row's precedent — an overlay takes no part in the list's layout, so it
   cannot feed back into scroll geometry.
4. A **constant** `contentMargins(.bottom, …)` so the button does not permanently
   cover the footer's attribution line at the end of the list.

Point 4 is deliberately a fixed value. Making the margin conditional on
visibility would make layout a function of scroll position, which is the exact
shape of the bug that hung the app.

## Behaviour

**Appearing.** `ScrollToTopVisibility.shouldShow(scrollOffset:viewportHeight:)`,
evaluated from the state the view already tracks. Animated with opacity and a
small scale, keyed on the boolean so it fades rather than popping.

**Tapping.** `withAnimation { scrollPosition.scrollTo(edge: .top) }`. The list
returns to the top, the map card comes back into view, the pinned title fades out
as `scrollOffset` returns to zero, and the button hides itself as the same
predicate flips false. No extra state to reset.

**Rubber-banding.** Overscrolling past the top yields a negative `scrollOffset`,
which fails the predicate — the button stays hidden, no special case needed.

## Testing

**New — `ScrollToTopVisibilityTests`.** Swift Testing, a plain `@Suite(.serialized)`
struct with no `OBATestCase` superclass since it needs no fixtures:

- hidden at rest (`scrollOffset == 0`)
- hidden just below one viewport
- shown just above one viewport
- shown far past it
- hidden when rubber-banding (negative offset)
- hidden when `viewportHeight` is zero — the pre-layout case that would otherwise
  divide the world into "everything is more than nothing" and show the button on
  a blank sheet

**Previews.** `ScrollToTopButton` in both visible and hidden states.

**Not unit-testable, and stated plainly:** that the overlay actually appears at
the right scroll position, and that tapping scrolls. Both need a real scroll view.
They go on the manual checklist, along with one specific check — that scrolling
down through the mid-range still does not hang, since this feature adds a second
scroll observer to a view with that history.

## Out of scope

- The pushed Stop page and the FloatingPanel sheet. This is the map sheet only.
- Any scroll-to-top affordance on other sheet routes.
- Auto-hiding the button after a period of inactivity.
