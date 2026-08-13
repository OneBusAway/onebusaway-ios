# Onboarding Rethink — Design

**Date:** 2026-07-17
**Design source:** Claude Design project "OBA iOS" → `OBA Onboarding Rethink.html` (project `275aeb1b-41b1-4f4e-8e11-79cb6237f1ec`)
**Status:** Approved

## Goal

Rebuild OBAKit's onboarding as a versioned, ordered **step registry** so that:

1. First-run users get a redesigned five-screen flow (Welcome → Location → Region → Notifications → All set) with shared visual chrome.
2. **Existing users are shown any step they have never seen** — specifically the new push-notifications step — exactly once, at launch, regardless of how long they have used the app, then land back in the app.
3. Adding a future step is one registry entry, with no changes to flow logic.

## Current state (what this replaces)

- `OnboardingNavigationController` (duplicated byte-for-byte in `Apps/OneBusAway/Onboarding/` and `Apps/KiedyBus/Onboarding/`): a UIKit `UINavigationController` with a hardcoded page enum (`migration → location → regionPicker`) and `nextPage()` transition table, hosting SwiftUI steps in `UIHostingController`s.
- No completion flag exists; onboarding shows whenever `currentRegion == nil || shouldPerformMigration`. No per-step "seen" tracking.
- Push permission is never surfaced at onboarding; it is requested lazily by `OBACloudPushService.requestPushID` when the user first creates an arrival alarm.
- Presented from `AppDelegate.m` (`applicationReloadRootInterface:`) as the window root, swapping to the real root controller on completion.

## Decisions made during brainstorming

| Question | Decision |
| --- | --- |
| What does "Turn On Notifications" do? | OS permission + APNs registration only, via the existing `OBACloudPushService.requestPushID` path. No new subscription logic; the server decides what to send. |
| Region step vs. existing `RegionPickerView`? | New detected-region card UI as the onboarding step; "See all regions" pushes the existing full `RegionPickerView` (custom regions, Settings usage untouched). |
| Presentation for existing users? | Full-screen at launch, same root-swap mechanism as today; single step, then hand-off to the app. |
| Architecture | Approach A: shared step registry + SwiftUI flow container in OBAKit, deleting the per-app `OnboardingNavigationController` copies. |
| HIG pre-alert screen rule (one "Continue"-style button, no skip)? | **Deliberately not followed.** Keep the design's two-button layout ("Use My Location"/"Turn On Notifications" + "Not Now"/"Maybe Later"). Rationale: declining marks the step seen forever, which respects the user more than forcing the OS prompt. Risk accepted as low-but-nonzero (HIG guidance, not the automatic-rejection rule — that applies only to tracking prompts). |
| Provisional notification authorization? | Rejected. `UNAuthorizationOptions.provisional` delivers silently to Notification Center only, which defeats time-sensitive region-wide service alerts. |

## 1 · Registry & persistence

New code in `OBAKit/Onboarding/`:

```swift
struct OnboardingStep {
    let id: OnboardingStepID     // .migration, .welcome, .location, .region, .notifications, .done
    let weight: Int              // 10, 20, 30, 40, 50, 99
    let version: Int             // bump to re-show a changed step
    let isEligible: (Application) -> Bool
    let makeView: (OnboardingStepContext) -> AnyView
}
```

`OnboardingStepStore` persists `[stepID: seenVersion]` under a single UserDefaults key, `OBAOnboardingSeenStepVersions`.

**Flow computation (per launch):**

```swift
flow = steps
    .filter { $0.isEligible(app) && store.seenVersion($0.id) < $0.version }
    .sorted { $0.weight < $1.weight }
```

Onboarding is needed iff `flow` is non-empty. This replaces `needsToOnboard(application:)`.

Note: the notifications eligibility check requires an async fetch (`await UNUserNotificationCenter.current().notificationSettings()`), so flow computation is `async`. It is the only async predicate; the ObjC entry point wraps it (compute the flow, then decide root controller).

### Seen semantics

Steps mark themselves seen at their own completion point, not on display:

| Step | Marked seen when |
| --- | --- |
| welcome | "Get Started" tapped |
| location | Either button tapped ("Use My Location" after the auth request resolves, or "Not Now") |
| region | A region is actually confirmed (interrupted flow re-shows it) |
| notifications | Either button tapped ("Turn On Notifications" after the request resolves, or "Not Now"/"Maybe Later"). One pitch, ever — declining still counts as seen. |
| done | "Start Exploring" tapped |
| migration | Never via the store. Its eligibility predicate (`shouldPerformMigration`) governs re-prompting, preserving today's behavior of re-prompting until migration succeeds. |

### Existing-user seeding (backfill)

On first flow evaluation: if the store is empty **and** `currentRegion != nil`, backfill the explicit set `{welcome, location, region, done}` as seen at version 1. `notifications` is deliberately absent, so every existing user's computed flow is exactly `[notifications]`. Backfill runs once (a non-empty store never backfills again) and is idempotent. Future steps need no backfill changes — they are simply never in the set.

### Eligibility predicates

| Step | `isEligible` |
| --- | --- |
| migration | `hasDataToMigrate && shouldPerformMigration` |
| welcome | always |
| location | OS location authorization is `.notDetermined` |
| region | always |
| notifications | `application.pushService != nil` (push provider configured — white-label apps without push, and the Simulator, skip it) **and** notification authorization is `.notDetermined` (users who already granted/denied via the alarm flow are not re-pitched) |
| done | always (backfill marks it seen, so returning single-step users skip it naturally) |

## 2 · Flow container & launch integration

- `OnboardingFlowView` (SwiftUI): renders the computed flow inside the shared scaffold. Progress segments are sized to **this run's** step count. When the flow has exactly one step: no progress bar, "NEW" badge, "Maybe Later" secondary label.
- `OBAOnboardingFlowController` (`@objc`, a `UIHostingController` wrapper): exposes `+needsToOnboard(application:)` and an init taking a completion block. Drop-in replacement at the ObjC call site in `AppDelegate.m` (`applicationReloadRootInterface:`). Presentation is unchanged: root controller before the map, flip transition to the real root on completion.
- Delete `Apps/OneBusAway/Onboarding/OnboardingNavigationController.swift` and `Apps/KiedyBus/Onboarding/OnboardingNavigationController.swift` (and the MTA copy if one exists); all app targets use the shared controller. Regenerate the project with `scripts/generate_project` after file changes.

## 3 · Screens

Shared `OnboardingScaffold` (SwiftUI): segmented progress bar, ringed hero circle, centered title/body, 56-pt primary button dock, optional footnote and "NEW" badge. Built with semantic colors so light/dark adapts automatically; the accent comes from the app's theme accent color (not a hardcoded lime) for white-label safety.

- **Welcome** — new screen: brand hero, "Get Started", footnote about worldwide regions.
- **Location** — replaces `RegionPickerLocationAuthorizationView` content; same behavior underneath: "Use My Location" sets `automaticallySelectRegion = true` and calls `requestInUseAuthorization()` via the existing `RegionPickerCoordinator`; "Not Now" sets it false. Benefit rows: nearby stops, map centering. Footnote: while-in-use only.
- **Region** — detected-region card (auto-detect via `RegionPickerCoordinator`; map preview via the existing live `RegionPickerMap`, preferred over `MKMapSnapshotter` because snapshots don't adapt to dark-mode trait changes without re-snapshotting and don't capture overlays/annotations), short nearest-regions list, "See all regions" pushes the existing `RegionPickerView`. Region confirmed via `regionProvider.setCurrentRegion(to:)`.
- **Notifications** — pitch screen for region-wide service alerts with illustrative (localized, static) alert cards. Primary button drives the existing `OBACloudPushService.requestPushID` path: `UNUserNotificationCenter.requestAuthorization` + `registerForRemoteNotifications`. Nothing else ships client-side.
- **All set** — recap rows reflecting actual outcomes (region name, location on/off, alerts on/off), "Start Exploring".
- **Migration** — existing `DataMigrationView` wrapped in the new chrome; not rebuilt.

New user-facing strings go through the normal `OBAKit/Strings` localization flow (`scripts/extract_strings`).

## 4 · Error handling & edge cases

- Push authorization/registration failure: log via CocoaLumberjack, mark seen, advance. Never traps the user. APNs registration can be retried silently on a later launch even after the step is seen (authorization already granted → no UI); device tokens are never cached in local storage, per Apple's guidance.
- "Allow Once" location grants revert to `.notDetermined` when the app is no longer in use, making the location step *eligible* again on a later launch — the seen-store is what prevents a re-show. Covered by a dedicated test.
- Regions fail to load on the region step: existing `RegionPickerCoordinator` error handling applies; the step remains usable (retry/list).
- App killed mid-flow: steps not yet marked seen reappear next launch; region cannot be skipped by force-quit because it is only marked seen on confirmation.
- `TEST_ONBOARDING` env var (DEBUG): forces the full flow ignoring the store, keeping the flow previewable on Simulator (where the notifications step is otherwise ineligible).

## 5 · Testing

Unit tests in `OBAKitTests` covering the registry math:

- New user (empty store, no region): full ordered flow.
- Seeded existing user (region set, empty store): flow is exactly `[notifications]`.
- Version bump on one step re-shows only that step.
- Eligibility gates: no push provider → no notifications step; already-determined notification permission → no notifications step; determined location permission → no location step.
- Backfill runs once, never with a non-empty store, and is idempotent.
- "Allow Once" scenario: location authorization back to `.notDetermined` after a temporary grant expires, but step already seen → not re-shown.
- `OnboardingStepStore` round-trips seen versions through UserDefaults.

Manual verification via `TEST_ONBOARDING` on the iPhone 17 simulator (light and dark).

## Out of scope

- Any server-side or client-side region-alert subscription logic.
- Redesigning the full `RegionPickerView` / custom-region form.
- Changes to the ObjC AppDelegate/SceneDelegate architecture beyond swapping the onboarding entry point.
- The legacy `LocationPermissionBulletin` and `RegionMismatchBulletin` (post-onboarding map prompt) remain untouched.
