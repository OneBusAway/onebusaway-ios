# Feedback Prompt: Sentiment-Routed Reviews & Complaints

**Date:** 2026-07-25
**Branch:** `feedback`
**Status:** Draft

## Background

OneBusAway has no in-app mechanism for soliciting App Store ratings. Riders who
love the app have no nudge to say so; riders who are frustrated have no path to
tell us other than digging through More → Contact Us. The result is a ratings
profile driven by self-selection, which skews negative — motivated complainers
outnumber motivated praisers.

The app already interrupts users in two other ways, each with its own
independent gate and no knowledge of the other:

- **Donations** — `DonationsManager.shouldRequestDonations` (launch count ≥ 3,
  not dismissed, past any reminder date) drives an inline card on the stop page.
- **Surveys** — `SurveyService.shouldShowSurvey()` (launch count divisible by
  an interval, past a 3-day reminder date) drives an inline stop card and a map
  prompt, mediated by `SurveyOrchestrator`.

Nothing prevents a rider from being asked for money and asked for research
participation in the same sitting. Adding a third ask without coordination
would make that worse.

`ContactUsHelper` already builds a fully-populated `MFMailComposeViewController`
targeting `Bundle.main.appDevelopersEmailAddress ?? "iphone-app@onebusaway.org"`,
with a debug-info block and a `buildCantSendEmailAlert` fallback for devices
without Mail.app configured. The complaint path is a wiring job, not new code.

## Goals

1. Ask engaged riders for an App Store rating at a moment when the app has
   just demonstrably worked for them.
2. Route dissatisfied riders to email instead of to the App Store.
3. Guarantee that a rider is never asked for feedback and money in the same
   sitting, and never asked for two things in close succession.
4. Cap lifetime interruptions so a rider who ignores us is left alone.
5. Ship dark, with per-app opt-out and debug affordances sufficient to QA it.

## Non-Goals

- **Legacy `StopViewController`.** `FeatureFlags.isNewStopPageEnabled` defaults
  to `true`; the classic page is an opt-out toggle on its way to removal. A
  rider who has explicitly turned the new page off will never accumulate
  successes and will never be prompted. Acceptable.
- **Bookmarks tab as a success signal.** Bookmark rows refresh in bulk on a
  timer without per-stop user intent, so counting them would inflate the
  counter without evidence of engagement. Stop views only.
- **Custom rating UI.** All ratings go through `AppStore.requestReview`. See
  §1.
- **Changing donation or survey cadence relative to each other.** The new
  coordinator constrains only the interactions involving the review prompt.
- **Server-side or remote configuration.** The kill switch is a build-time
  Info.plist key plus a local debug toggle.

## Apple's constraints

From the Human Interface Guidelines (`/design/human-interface-guidelines/ratings-and-reviews`)
and `StoreKit.RequestReviewAction`:

- Ask only after demonstrated engagement, at a natural stopping point, never
  mid-task.
- Prefer the system-provided prompt. It self-limits to **three displays per app
  per 365-day period** and provides **no callback** — the app cannot learn
  whether the prompt appeared or whether a rating was left.
- Allow at least a week or two between requests.

App Store Review Guideline 5.6.1 disallows *custom review prompts* — custom
star-rating UI that substitutes for the API. A sentiment question that collects
no rating, posts nothing, and routes to `AppStore.requestReview` on one branch
and to a genuine support channel on the other is the widely-shipped
interpretation. The risk is low but nonzero, which is why §6 specifies a
build-time kill switch.

## Design

### 1. The two-step ask

**Step 1 — sentiment alert.** A native `UIAlertController` with three actions:

> **Enjoying OneBusAway?**
> [ Yes! ] [ Not really ] [ Ask Me Later ]

An alert (not a sheet, not a custom view) so it cannot be dismissed by tapping
outside — every path produces a recorded outcome, which is what makes the
backoff logic meaningful.

**Step 2a — "Yes!"** → call `AppStore.requestReview(in: scene)` immediately,
record `.positive`, and **never prompt again on this device**. One affirmative
answer exhausts the value of the feature for that rider; the system's 3-per-365
budget is not ours to spend twice.

**Step 2b — "Not really"** → a second alert:

> **Sorry about that.**
> Would you tell us what's wrong? We read every message.
> [ Send Feedback ] [ No Thanks ]

"Send Feedback" presents `ContactUsHelper.buildMailComposer(target: .appDevelopers)`,
falling back to `buildCantSendEmailAlert(target:)` when `MFMailComposeViewController.canSendMail()`
is false. Record `.negative` either way and back off **180 days**.

**Step 2c — "Ask Me Later"** → record `.deferred` and require both 60 days and
a fresh set of successes before asking again. (A negative-path "No Thanks"
still records `.negative`, not `.deferred` — the rider told us they're
unhappy; declining to write an email doesn't retract that.)

**Every ask resets the success counter to zero**, so each of the backoffs above
is a floor, not a schedule: the rider must both wait out the interval *and*
demonstrate five fresh successes.

**Lifetime cap: three asks.** Once `askCount` reaches 3 the feature goes
permanently silent, whatever the mix of outcomes that got it there. `.positive`
silences immediately regardless of count.

### 2. The silent no-op, and the always-available path

If the rider has disabled in-app ratings in Settings, or the 3-per-365 budget
is spent, `requestReview` does nothing and the rider who just tapped "Yes!"
sees nothing happen. Rather than stacking a second modal on the positive path,
add a permanent **"Rate OneBusAway"** row to the More tab that opens:

```
https://apps.apple.com/app/id<APP_STORE_ID>?action=write-review
```

This is user-initiated, not rate-limited, and serves riders who want to review
on their own schedule. It requires a new per-app Info.plist key `AppStoreID`
(string), surfaced via a `Bundle.appStoreID` helper in
`OBAKitCore/Extensions/FoundationExtensions.swift` alongside the existing
`appDevelopersEmailAddress`. The row is hidden when the key is absent, so
white-label apps without an ID configured are unaffected.

### 3. Qualifying: success moments

A **success** is a stop-arrivals load that succeeded *and* returned at least one
`ArrivalDeparture` with `predicted == true` — real-time data actually reached
the rider. Scheduled-only results do not count: they are the case most likely
to disappoint.

**Threshold: 5 successes.**

**Debounce: at most one success per stop view.** `StopViewModel.refresh()` runs
on a ~30-second timer, so without this a rider who leaves one stop open for
three minutes would qualify on a single screen. The debounce is a
`hasRecordedSuccess` flag on the `StopViewModel` instance, which is constructed
per stop presentation. This is not a tenure gate — it is what makes the counter
mean "five lookups" rather than "two and a half minutes."

Deliberately **no tenure floor**: no minimum days installed, launch count, or
bookmark count. At typical usage (one to two stop checks per trip) five
successes lands around the second or third day of real use.

**Hook:** `StopViewModel.applySuccessfulFetch(stop:arrivals:)`.

```swift
if !hasRecordedSuccess, arrivals.arrivalsAndDepartures.contains(where: \.predicted) {
    hasRecordedSuccess = true
    environment.reviewPromptPolicy.recordSuccess()
}
```

`ReviewPromptPolicy` is reached through `StopViewModelEnvironment`, the narrow
protocol the view model already uses instead of `Application`.

### 4. Presenting: natural stopping points

The prompt **never appears on the stop screen**. Interrupting someone reading
departure times is the worst available moment and the one the HIG names
explicitly.

When `recordSuccess()` pushes the counter to the threshold, the policy sets a
**pending** flag. The prompt is presented the next time the map becomes visible
with nothing modal on top of it — that is, when the rider has backed out of a
successful stop view and is at rest.

Hook sites, one line each, gated on whichever map experience is active
(`FeatureFlags.useMapPanelExperienceKey`):

- `MapViewController.viewDidAppear(_:)` (classic tab experience)
- `MapPanelRootController` equivalent (map panel experience)

Additional suppressions at presentation time:

- Any presented view controller → skip, retry on the next opportunity.
- No region selected, or onboarding in progress → skip.
- **A stop load errored during the current foreground session** → suppress for
  the remainder of that session. A rider who just watched the app fail is not a
  rider to ask for five stars. This lives as `sawErrorThisSession` on
  `PromptCoordinator` (§5), alongside the other session-scoped state and
  cleared by the same foreground notification; `StopViewModel`'s `catch` path
  sets it.

### 5. `PromptCoordinator`: never two asks at once

New `@MainActor` type in `OBAKit/Feedback/`, owning the cross-feature
interruption budget:

```swift
enum PromptKind { case review, donation, survey }

final class PromptCoordinator {
    func canShow(_ kind: PromptKind) -> Bool
    func noteShown(_ kind: PromptKind)
}
```

State: in-memory `shownThisSession: Set<PromptKind>` and `sawErrorThisSession:
Bool`, plus `lastPromptShownDate` and `lastPromptKind` in `UserDefaults`.

A **foreground session** begins at launch and at each
`UIApplication.willEnterForegroundNotification`. `shownThisSession` clears
then. Process lifetime is the wrong unit — an iOS app can stay resident for
days, which would make a per-process rule far too permissive at the start of a
sitting and far too strict across sittings.

Rules, deliberately asymmetric so the blast radius stays on the new feature:

| Rule | Effect |
| --- | --- |
| One prompt of any kind per foreground session | No stacking within a sitting |
| Review prompt requires 14 days clear of any donation or survey prompt | Honors the HIG's "week or two"; never review-after-money |
| Donation and survey cards suppressed for 7 days after a review prompt | Never money-after-review |
| Donation vs. survey | **Unchanged** — existing cadence preserved |

Integration: `DonationsManager.shouldRequestDonations` and
`SurveyOrchestrator.isEligible()` each gain a `promptCoordinator.canShow(...)`
conjunct, and their existing display paths call `noteShown(...)`. For the
inline cards, "shown" means the card actually rendered, not merely that the
gate opened — `StopPageView` already tracks this for the donation card via
`donationHidden`/`shouldRequestDonations`.

### 6. Types, ownership, and configuration

All new code lives in `OBAKit/Feedback/`, matching `OBAKit/Donations/`:

- **`ReviewPromptPolicy`** — pure logic, no UIKit. Constructed with
  `UserDefaults` and a `now: () -> Date` clock, following `DonationsManager`'s
  precedent of owning its own defaults keys rather than widening the
  `UserDataStore` protocol. Exposes `recordSuccess()`, `isPromptPending`,
  `recordOutcome(_:)`, and `isPermanentlySilenced`.
- **`FeedbackPromptPresenter`** — `@MainActor`. Builds the alerts, calls
  `AppStore.requestReview(in:)`, hands off to `ContactUsHelper`. Conforms to
  `MFMailComposeViewControllerDelegate` so it can dismiss the composer and
  report `feedback_email_sent` versus a cancellation — `MoreViewController`
  currently owns the only such conformance, and the presenter needs its own
  rather than routing through a view controller.
- **`PromptCoordinator`** — §5.

Owned by `Application` as `lazy var` properties beside `donationsManager`.

Persisted keys (own namespace, `ReviewPrompt.` prefixed):

| Key | Type | Meaning |
| --- | --- | --- |
| `successCount` | Int | Successes since the last reset |
| `askCount` | Int | Lifetime asks presented |
| `lastAskedDate` | Date? | Drives the 60/180-day backoffs |
| `outcome` | String? | `positive` \| `negative` \| `deferred` |

**Kill switch:** a per-app Info.plist boolean `FeedbackPromptEnabled`, read via
a `Bundle.feedbackPromptEnabled` helper, **defaulting to `true` when absent**.
This differs from `donationsEnabled` (which defaults to `false` because
donations require additional configuration to function); the feedback prompt
needs no configuration, so opt-out is the right default. KiedyBus inherits the
feature and routes complaints to its own `AppDevelopersEmailAddress`
(`info@goeuropa.eu`) with no additional work.

### 7. Debug affordances

Without these the feature cannot be QA'd — reaching the threshold organically
takes days and the terminal states are permanent.

In Settings → Experimental, mirroring `alwaysShowSurveysOnStops`:

- **Always show feedback prompt** — bypasses the counter, backoffs, and
  coordinator, but not the `FeedbackPromptEnabled` kill switch.
- **Reset feedback prompt state** — clears all four persisted keys.

### 8. Analytics

Apple gives no signal about the system prompt, so these events are the only
instrument for whether the feature works. New `AnalyticsLabels` constants
reported through the existing `Analytics.reportEvent(pageURL:label:value:)`:

`feedback_prompt_shown`, `feedback_positive`, `feedback_negative`,
`feedback_deferred`, `feedback_email_opened`, `feedback_email_sent`,
`rate_app_row_tapped`.

The ratio of `feedback_positive` to `feedback_prompt_shown` is the health
metric. If it drops below roughly two thirds, the threshold is firing too
early and should be raised.

### 9. Strings

All user-facing copy via `OBALoc` in `OBAKit/Strings`, per the in-repo
localization workflow (13 locales, UTF-8 `.strings`).

| Key | English |
| --- | --- |
| `feedback_prompt.title` | Enjoying OneBusAway? |
| `feedback_prompt.positive_button` | Yes! |
| `feedback_prompt.negative_button` | Not really |
| `feedback_prompt.later_button` | Ask Me Later |
| `feedback_prompt.negative.title` | Sorry about that. |
| `feedback_prompt.negative.body` | Would you tell us what's wrong? We read every message. |
| `feedback_prompt.negative.send_button` | Send Feedback |
| `feedback_prompt.negative.decline_button` | No Thanks |
| `more_controller.rate_app` | Rate OneBusAway |

The title and the "Rate" row interpolate `Bundle.main.appName` rather than
hardcoding "OneBusAway", so white-label builds read correctly.

## Testing

`OBAKitTests/Feedback/ReviewPromptPolicyTests.swift`, using an injected clock
and an isolated `UserDefaults` suite:

- Counter reaches 5 → pending; 4 successes → not pending.
- Repeated `recordSuccess()` within one stop view counts once (view-model-level
  debounce, verified in `StopViewModelTests`).
- Scheduled-only arrivals (`predicted == false`) do not count.
- `.positive` → permanently silenced regardless of subsequent successes.
- `.negative` → silent for 180 days, then requires 5 fresh successes.
- `.deferred` → silent for 60 days, then requires 5 fresh successes.
- Any outcome resets the counter, so elapsed time alone never re-arms the
  prompt.
- `askCount` reaching 3 → permanently silenced, for every mix of outcomes.
- `FeedbackPromptEnabled == false` → never pending.

`OBAKitTests/Feedback/PromptCoordinatorTests.swift`:

- Second prompt in the same foreground session is refused, any kind ordering.
- Foreground notification clears the session set.
- Review refused within 14 days of a donation or survey prompt.
- Donation and survey refused within 7 days of a review prompt.
- Donation vs. survey interactions unchanged from today's behavior.

`StopViewModelTests`: a successful fetch containing a predicted arrival records
exactly one success; an errored fetch records none.

Presentation logic (alerts, `requestReview`, mail composer) is not unit tested
— per the memory note on Xcode 27, the XCUITest runner is unreliable. Verify
manually with the debug toggles.

## Rollout

1. Land with `FeedbackPromptEnabled` on and exercise both branches in TestFlight
   using the debug toggles before the first App Store build carries it. The key
   exists so a white-label app can opt out and so the feature can be disabled
   in a hotfix without reverting code — not as a staged percentage rollout,
   which the app has no infrastructure for.
2. Watch `feedback_positive` / `feedback_prompt_shown` for one release cycle.
3. Tune the threshold if the positive ratio disappoints; the constant is a
   single value in `ReviewPromptPolicy`.

## Open questions

None blocking. The two decisions taken without explicit sign-off, both
reversible in one line:

- Threshold of **5** successes.
- Success counting debounced **per stop view** rather than per refresh tick.
