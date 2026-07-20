# Harden `BulletinOverlayWindow` — Design

Fast-follow to PR #1163. Fixes GitHub issue [#1170](https://github.com/OneBusAway/onebusaway-ios/issues/1170).

## Background

PR #1163 introduced `BulletinOverlayWindow`, a dedicated `.alert`-level `UIWindow` for hosting `BLTNItemManager` presentations, and routed every OBA bulletin (`AgencyAlertBulletin`, `ErrorBulletin`, `ReachabilityBulletin`, `RegionMismatchBulletin`) through it.

The bug that motivated the window path — `UISheetPresentationController` clamping a bulletin to the map-panel home sheet's detent — only exists when `FeatureFlags.useMapPanelExperienceKey` is enabled. The fix, however, was applied globally, so it ships to classic (production) users too. On top of that, the current implementation has two latent issues that only bite the flag-enabled path but grow in severity under real-world use:

1. `dismissalHandler` chaining accumulates closures across presentations for long-lived reusable page items (notably `ReachabilityBulletin.connectivityPage`, re-shown on every connectivity flap).
2. Cross-manager coordination is absent: two `BLTNItemManager` instances can race and orphan a live bulletin's window.

## Goals

- Restrict the new overlay-window presentation path to the map-panel experience.
- Eliminate the `dismissalHandler` chaining growth on reused page items.
- Add a regression test proving the flap loop no longer accumulates handlers.

## Non-goals

- Cross-manager coordination / queueing (issue work-item 3). After gating, this only affects flag-enabled testers, and the DEBUG `assertionFailure` in `install` catches the condition in development. A follow-up issue may be filed.
- Routing bulletin-drop paths (`no foreground scene`) through `analytics?.reportError`. Optional per acceptance criteria; not addressed here.

## Design

### Change 1 — Gate the overlay window on the map-panel flag

**File:** `OBAKit/BLTNBoard/OBABulletinPage.swift`

`BLTNItemManager.show(in:rootItem:)` branches on `UserDefaults.standard.bool(forKey: FeatureFlags.useMapPanelExperienceKey)`:

- **Flag ON** — current behavior: `BulletinOverlayWindow.shared.install(in:rootItem:)` then `showBulletin(above: host)`.
- **Flag OFF** — restore the pre-#1163 presentation: walk `keyWindowFromScene?.topViewController` and `showBulletin(above: rootVC)`. The `rootItem` parameter is unused in this branch but stays in the signature so all four call sites are untouched.

The `isShowingBulletin` re-entrancy guard and the "no foreground scene" `Logger.error` drop diagnostic run before the branch — they are shared prerequisites.

**Which `UserDefaults` here:** the OBA app persists this flag to an app-group suite (`AppDelegate.m` initializes `NSUserDefaults` via `initWithSuiteName:` using `Bundle.main.appGroup`), and `SettingsViewController` + `ApplicationRootControllerFactory` both read/write it through `application.userDefaults`. Because this extension only receives `UIApplication` (not the OBA-specific `Application`) and we can't change the four call sites, we resolve the same suite ourselves via `Bundle.main.appGroup` — matching the pattern `CoreApplicationKey.defaultValue` uses. If the suite can't be resolved (unlikely outside test hosts without an app group entitlement), the code treats the flag as OFF and falls through to the classic path, which is the safe production default.

### Change 2 — Stop chaining `dismissalHandler` on reused items

**File:** `OBAKit/BLTNBoard/BulletinOverlayWindow.swift`

**Current shape (the bug):**

```swift
let originalDismissal = rootItem.dismissalHandler
rootItem.dismissalHandler = { [weak self] item in
    originalDismissal?(item)
    self?.teardown()
}
```

On a persisted item like `ReachabilityBulletin.connectivityPage`, `dismissalHandler` is never reset between presentations, so each `install` wraps the previous cycle's closure. After N flaps the chain is N deep and `teardown()` runs N times per dismissal. Idempotent and bounded by flap count, but unbounded in principle on a shared singleton.

**Fix:** snapshot and *restore* rather than wrap.

`BulletinOverlayWindow` grows two private stored properties:
```swift
private weak var savedRootItem: BLTNItem?
private var savedDismissalHandler: ((BLTNItem) -> Void)?
```

On `install`:
1. Snapshot `rootItem.dismissalHandler` into `savedDismissalHandler` **before** replacing it.
2. Store `savedRootItem = rootItem` (weak).
3. Replace (not wrap) `rootItem.dismissalHandler` with:
   ```swift
   { [weak self] item in
       self?.savedDismissalHandler?(item)
       self?.teardown()
   }
   ```

On `teardown`:
1. Restore `savedRootItem?.dismissalHandler = savedDismissalHandler`.
2. Clear both saved references (`savedRootItem = nil`, `savedDismissalHandler = nil`).
3. Perform existing window teardown (root VC nil, hidden, scene nil, main-window key reclaim).

This restores the item to exactly the state it had before `install` ran, so the next `install` sees the pristine original handler — no matter how many prior presentations occurred.

DEBUG assertions are preserved: `assert(rootItem.next == nil, ...)` and the "already in use" `assertionFailure` on re-entry.

### Call sites

The four bulletin call sites (`AgencyAlertBulletin`, `ErrorBulletin`, `ReachabilityBulletin`, `RegionMismatchBulletin`) are **not touched**. All flag-gating and handler-management logic lives inside the two files above.

## Testing

New file: `OBAKitTests/BLTNBoard/BulletinOverlayWindowTests.swift`.

Both tests are `@MainActor`. They exercise `BulletinOverlayWindow` directly against a synthesized `BLTNPageItem`; the presentation path itself is not driven — only handler management and teardown restoration.

1. **`test_reachability_flapping_does_not_accumulate_handlers`** — the direct regression test for the item-2 bug.
   - Create a `BLTNPageItem`. Assign a `dismissalHandler` whose closure captures a counter.
   - Loop 5×: acquire an installable scene, call `install(in:rootItem:)`, then invoke the item's new `dismissalHandler` (simulating BLTN dispatching dismissal), which triggers `teardown()`.
   - After the loop, invoke `dismissalHandler` one final time on a fresh install cycle.
   - Assert the counter incremented exactly the expected number of times (1 per cycle, no compounding).

2. **`test_teardown_restores_original_handler`** — asserts item-state restoration.
   - Create a `BLTNPageItem` with a known original handler.
   - Install, then teardown.
   - Assert `rootItem.dismissalHandler` is either the original object (via `ObjectIdentifier` if reference identity survives the round-trip) or, more robustly, invoke it and assert a spy-flag captured in the original closure fires — proving the restored handler is the pre-`install` one, not the overlay's wrapper.

**Fallback:** if synthesizing a `UIWindowScene` in the test host proves fragile (`OBAKitTests` runs headless), extract the handler-management steps into a small helper on `BulletinOverlayWindow` — e.g. `internal func swapDismissalHandler(on: BLTNItem)` and `internal func restoreDismissalHandler()` — and drive those directly, sidestepping scene synthesis. The `install`/`teardown` public API keeps its current signature.

**Flag-gating is not unit-tested.** It's a two-line branch on `UserDefaults.standard.bool(forKey:)` with no logic beyond it. Manual verification: toggle `OBAUseMapPanelExperience` in Settings, force a reachability drop, confirm classic mode gets the pre-#1163 presentation and map-panel gets the overlay window.

## Acceptance criteria mapping

| Criterion | Where met |
| --- | --- |
| Blast radius decision made and reflected in code | Change 1 (flag gate in `show(in:rootItem:)`) |
| Reachability flapping no longer accumulates nested `dismissalHandler` closures | Change 2 + regression test 1 |
| Concurrent bulletins from different managers can't orphan/corrupt each other | **Deferred.** Scoped to flag-on testers post-Change 1; DEBUG asserts still fire in development. Follow-up. |
| Bulletin drops route through analytics | Not addressed (optional in the issue) |

## Risks

- **Flag read timing.** `UserDefaults.standard.bool` reflects the current value; if a user flips the flag mid-session, the next bulletin's presentation path could switch. This matches how the flag behaves everywhere else in the app (a relaunch is expected), and both paths present a valid bulletin — the visible result is a slightly different visual/hosting behavior, not a broken state.
- **Test-host scene availability.** If `OBAKitTests` can't synthesize a scene, the fallback helper-method approach is documented above. This is a minor implementation detail, not a design change.
- **Item identity assumption in test 2.** `BLTN` may or may not preserve exact handler identity across reassignment — the spy-flag alternative avoids depending on identity semantics.
