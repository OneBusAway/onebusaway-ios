# Feedback Prompt: Sentiment-Routed Reviews & Complaints

**Date:** 2026-07-25
**Branch:** `feedback`
**Status:** Approved

## Background

OneBusAway has no in-app mechanism for soliciting App Store ratings. Riders who
love the app have no nudge to say so; riders who are frustrated have no path to
tell us other than digging through More → Contact Us. The result is a ratings
profile driven by self-selection, which skews negative — motivated complainers
outnumber motivated praisers.

The app already interrupts riders in two other ways, each with its own
independent gate and no knowledge of the other:

- **Donations** — `DonationsManager.shouldRequestDonations` (launch count ≥ 3,
  not dismissed, past any reminder date) drives an inline card on the stop page.
- **Surveys** — `SurveyService.shouldShowSurvey()` (launch count divisible by an
  interval, past a 3-day reminder date) drives an inline stop card and a map
  prompt, mediated by `SurveyOrchestrator`.

Nothing prevents a rider from being asked for money and asked for research
participation in the same sitting. Adding a third ask without coordination would
make that worse.

`ContactUsHelper` already builds a fully-populated `MFMailComposeViewController`
targeting `Bundle.main.appDevelopersEmailAddress ?? "iphone-app@onebusaway.org"`,
with a debug-info block and a `buildCantSendEmailAlert` fallback for devices
without Mail.app configured. The complaint path is a wiring job, not new code.

## Goals

1. Ask engaged riders for an App Store rating at a moment when the app has just
   demonstrably worked for them.
2. Route dissatisfied riders to email instead of to the App Store.
3. Guarantee that a rider is never asked for feedback and money in the same
   sitting.
4. Cap lifetime interruptions so a rider who ignores us is left alone.
5. Ship with a per-app kill switch and debug affordances sufficient to QA it.

## Non-Goals

- **Legacy `StopViewController`.** `FeatureFlags.isNewStopPageEnabled` defaults
  to `true`; the classic page is an opt-out toggle on its way to removal. The
  gate is *presentation*, not accrual: `StopViewController` builds the same
  `StopViewModel`, so a rider who has turned the new page off goes on recording
  successes and errors normally — there is simply no stop-sheet dismissal to
  present from, so they are never prompted. Acceptable.
- **Bookmarks tab as a success signal.** Bookmark rows refresh in bulk on a
  timer without per-stop rider intent, so counting them would inflate the
  counter without evidence of engagement. Stop views only.
- **Custom rating UI.** We never render stars, never collect a rating, and never
  transmit review text. See §1 and §10.
- **Changing donation or survey cadence relative to each other.** The new
  coordinator constrains only the interactions involving the review prompt.
- **Server-side or staged rollout.** The kill switch is a build-time config key
  plus a local debug toggle; the app has no percentage-rollout infrastructure.

## Apple's constraints

Verified against `/design/human-interface-guidelines/ratings-and-reviews` and
`/documentation/storekit/requesting-app-store-reviews`:

- Ask only after demonstrated engagement, at a natural stopping point.
- **"Avoid showing a request for a review immediately when a user launches your
  app, even if it isn't the first time it launches."** This directly shapes §4.
- **"Avoid requesting a review as the result of a user action."** `requestReview`
  may display nothing, so a tap that expects a response can produce silence.
  This is the constraint that shapes §1 and is stronger, more specific, and more
  clearly documented than the Guideline 5.6.1 question everyone reaches for
  first.
- The system prompt self-limits to **three displays per app per 365 days** (for
  riders who haven't already reviewed) and provides **no callback** — its
  signature returns `Void`.
- For rider-initiated reviews, Apple's own sample designates a deep link:
  `https://apps.apple.com/app/id<ID>?action=write-review`, opened with
  `openURL`. This is the sanctioned path for "a person to initiate a review as a
  result of an action in the UI" — exactly our positive branch.

`SKStoreReviewController` is deprecated in favor of `RequestReviewAction`.

## Design

### 1. The two-step ask

**Step 1 — sentiment alert.** A native `UIAlertController` with three actions,
presented by the app at a natural stopping point (§4), never in response to a
tap:

> **Enjoying OneBusAway?**
> [ Yes! ] [ Not really ] [ Ask Me Later ]

An alert rather than a sheet so it cannot be dismissed by tapping outside.

**Step 2a — "Yes!"** → open the write-review deep link for the configured
`AppStoreID` via `UIApplication.open(_:)`. Record `.positive` and **never prompt
again on this device**.

We deliberately do **not** call `AppStore.requestReview(in:)` here. That would
be "requesting a review as the result of a user action," which Apple's
documentation tells us to avoid, and it can silently display nothing — leaving a
rider who just enthusiastically tapped "Yes!" staring at an unchanged screen.
The deep link is guaranteed to land them on the review form, is not rate-limited
by the 3-per-365 budget, and is the mechanism Apple's own sample code uses for
this exact interaction. The cost is that it leaves the app; a rider who just
opted in is the one rider for whom that cost is acceptable. See §10 for the
alternative we rejected and why the choice is genuinely arguable.

**Step 2b — "Not really"** → a second alert:

> **Sorry about that.**
> Would you tell us what's wrong? We read every message.
> [ Send Feedback ] [ No Thanks ]

"Send Feedback" presents `ContactUsHelper.buildMailComposer(target: .appDevelopers)`,
falling back to `buildCantSendEmailAlert(target:)` when
`MFMailComposeViewController.canSendMail()` returns false (the builder returns
`nil` in that case). Record `.negative` on either button — the rider told us
they're unhappy, and declining to write an email doesn't retract that — then
back off **180 days**.

**Step 2c — "Ask Me Later"** → record `.deferred`, back off **60 days**.

**Outcome is written at presentation time, not at answer time.** The presenter
writes `.deferred` and increments `askCount` the moment the alert appears, then
overwrites `outcome` with the real answer. Otherwise a rider who backgrounds and
kills the app mid-alert leaves `lastAskedDate` set with a stale or absent
`outcome`, matching none of the backoff rules. Treating abandonment as a
deferral is both well-defined and the correct reading of the behavior.

**Every ask resets the success counter to zero**, so each backoff is a floor,
not a schedule: the rider must both wait out the interval *and* demonstrate five
fresh successes.

**Lifetime cap: three asks.** Once `askCount` reaches 3 the feature goes
permanently silent, whatever mix of outcomes got it there. `.positive` silences
immediately regardless of count.

**Version gating.** Following Apple's sample, record
`lastVersionPromptedForReview` and never prompt twice for the same
`CFBundleShortVersionString`. This is a second floor under the backoffs, not a
replacement for them.

### 2. The always-available path

Add a permanent **"Rate OneBusAway"** row to the More tab, opening the same
write-review deep link. This serves riders who want to review on their own
schedule and never happen to hit the prompt.

`MoreTabConfiguration.customLinks` already exists and could carry a row with no
new code, but it can't interpolate `Bundle.main.appName` into the title or read
the App Store ID, so this gets a dedicated row. The row is hidden when
`AppStoreID` is absent, so white-label apps without one configured are
unaffected.

### 3. Qualifying: success moments

A **success** is a stop-arrivals load that succeeded *and* surfaced at least one
`ArrivalDeparture` with `predicted == true` — the server claims real-time data
for that trip. Scheduled-only results do not count: they are the case most
likely to disappoint.

`ArrivalDeparture.predicted` is the right flag rather than `TripStatus.isRealTime`.
Both decode the same JSON key `"predicted"`, but `isRealTime` hangs off the
optional `tripStatus` and is unreachable when it's nil, whereas `predicted` is
present on every arrival.

Two honest caveats. `predicted == true` does not guarantee a *usable* time —
`predictedArrival` and `predictedDeparture` are independently nilified by
`ModelHelpers.nilifyDate`. And the count must run against the arrivals the page
actually **displays**, after the rider's hidden-route preferences are applied,
not the raw `arrivals.arrivalsAndDepartures`; otherwise a success can be
credited for a route the rider has deliberately hidden and never saw.

**Threshold: 5 successes.**

**Debounce: at most one success per stop view.** `StopViewModel.refresh()` runs
on a 15-second timer gated by a 30-second staleness threshold, so without this a
rider who leaves one stop open for a few minutes would qualify on a single
screen. The debounce is a `hasRecordedSuccess` flag on the `StopViewModel`
instance — verified safe, because `StopPageViewController.init` constructs
exactly one view model per stop presentation and it stays bound to a single
`stopID` for its lifetime. This is not a tenure gate; it is what makes the
counter mean "five lookups" rather than "two minutes."

Deliberately **no tenure floor**: no minimum days installed, launch count, or
bookmark count. At typical usage (one to two stop checks per trip) five
successes lands around the second or third day of real use.

**Hook:** `StopViewModel.applySuccessfulFetch(stop:arrivals:)` (private, called
only when `result.stop != nil`).

### 4. Presenting: natural stopping points

The prompt **never appears on the stop screen**, and **never at launch**.

The original hook — `MapViewController.viewDidAppear` — does not work and would
have produced exactly the behavior Apple warns against. `MapViewController.present(stopController:)`
routes the new stop page through `StopSheetPresenter`, which calls
`panel.addPanel(toParent:animated:)`. That is a **child view controller**, not a
modal presentation, so `MapViewController` never leaves the hierarchy and
`viewDidAppear` does not re-fire when the sheet is dismissed. In the map-panel
experience it's worse: `MapPanelRootController` is the window's root, so its
`viewDidAppear` fires roughly once per process. The prompt would have surfaced
at cold launch.

**The correct hook already exists.** `StopSheetPresenter.present(_:from:onDismiss:)`
takes a dismissal handler documented to run "once this presentation leaves the
screen, however it leaves." `MapViewController` already supplies one (it
deselects the map annotation). The review prompt is presented from there, after
the sheet's dismissal animation completes.

Additional suppressions at presentation time:

- Any presented view controller, or a survey prompt already onscreen → skip and
  retry at the next opportunity.
- No region selected, or onboarding in progress → skip.
- **A stop load errored during the current foreground session** → suppress for
  the remainder of that session. A rider who just watched the app fail is not a
  rider to ask for five stars. This is `sawErrorThisSession` on
  `PromptCoordinator` (§5). Reaching it from `StopViewModel` requires a second
  `StopViewModelEnvironment` member beyond `reviewPromptPolicy` — the view model
  reaches everything through that protocol. The general `catch` sets it, and so
  does `catch APIError.requestNotFound` **when there is no `bookmarkContext`**:
  with a bookmark behind it a 404 is the broken-bookmark path, which explains
  itself and offers a way out, but from a deep link, a search result, or a map
  pin the same 404 leaves the page with no arrivals, no error, and no recovery.
  That is a failure the rider watched.
- A short delay (~1–2 s) after dismissal before presenting, per Apple's sample,
  so the alert doesn't race the sheet animation. The delay is a cancellable
  `DispatchWorkItem` on `MapViewController`, and the suppressions above are
  re-checked **when it fires**, not when it is armed. `StopSheetPresenter.present`
  tears the outgoing sheet down as its first statement, so the dismissal handler
  also runs when one sheet *replaces* another — without re-validation the alert
  would land on top of the incoming stop sheet, over a map-item place card, on
  another tab, or on a freshly resumed app. `presentIfEligible` takes a
  caller-supplied `canPresent` closure for exactly this: its own
  `presentedViewController == nil` check is blind to FloatingPanel children,
  which is what all of those are.

### 5. `PromptCoordinator`: never two asks at once

New `@MainActor` type in `OBAKit/Feedback/`:

```swift
enum PromptKind { case review, donationModal, surveyPrompt }

final class PromptCoordinator {
    func canShowReviewPrompt() -> Bool
    func canShowInlineCards() -> Bool
    func noteShown(_ kind: PromptKind)
    func noteSurveyEngaged()
    var sawErrorThisSession: Bool { get set }
}
```

**The critical design rule: only interruptions and engagements are registered.
Inline card renders are not.** The first draft had `noteShown(.donation)` fire
whenever the donation card appeared, which is broken twice over:

- `DonationsManager.shouldRequestDonations` has no per-session throttle. It
  returns `true` continuously once launch count ≥ 3 until the rider explicitly
  dismisses or defers, and `StopPageView` renders the card on every stop page
  with loaded arrivals. So `lastPromptShownDate` would never be more than
  minutes old and the review prompt could **never** fire. Goal 3 would be met by
  never asking at all.
- `StopViewModel.shouldRequestDonations` is a computed passthrough re-read on
  every refresh tick. Feeding `canShow` back into it would make the card the
  rider is looking at **vanish** on the next refresh.

There is also no "the card rendered" signal to hook even if we wanted one:
`donationHidden` is `@State` set by the card's close button, a dismissal flag,
not a render observation.

So what registers:

| Event | Call site | Registers |
| --- | --- | --- |
| Donation modal opened | `StopPageViewController.showDonationUI()` | `.donationModal` |
| Survey answered or dismissed | `SurveyOrchestrator.submitHero` / `dismiss` | `noteSurveyEngaged()` |
| Survey map prompt shown | `MapViewModel` present path | `.surveyPrompt` |
| Review prompt shown | `FeedbackPromptPresenter` | `.review` |

Rules:

| Rule | Effect |
| --- | --- |
| Review requires nothing else registered this foreground session | No stacking within a sitting |
| Review requires 14 days clear of a donation modal or survey engagement | Honors the HIG's "week or two"; never review-right-after-money |
| After a review prompt, `canShowInlineCards()` is false **for the rest of that session only** | Never money-right-after-review, with no multi-day donation revenue cost |
| Donation vs. survey | **Unchanged** |

`canShowInlineCards()` is safe to read from `shouldRequestDonations` because it
is session-scoped and set by an event that fires at most once per session — no
feedback loop.

State: in-memory `shownThisSession: Set<PromptKind>` and `sawErrorThisSession`,
plus `lastEngagementDate` and `lastPromptKind` in `UserDefaults`.

A **foreground session** begins at launch and at each
`UIApplication.willEnterForegroundNotification`. Two known imprecisions, both
accepted: an app-switcher round trip re-arms a session within seconds, and
`MapViewModel` already has its own `hasShownSurveyThisSession` — a plain
instance var with no foreground reset and a rollback path for a prompt that
fails to present. `noteShown` gets a matching `noteNotShown(_:)` so a survey
that's gated but never presented doesn't burn the coordinator's session budget.

### 6. Types, ownership, and configuration

All new code in `OBAKit/Feedback/`, matching `OBAKit/Donations/`:

- **`ReviewPromptPolicy`** — pure logic, no UIKit. Constructed with
  `UserDefaults` and a `now: () -> Date` clock, following `DonationsManager`'s
  precedent of owning its own keys rather than widening `UserDataStore`.
- **`FeedbackPromptPresenter`** — `@MainActor`. Builds the alerts, opens the
  deep link, hands off to `ContactUsHelper`. Conforms to
  `MFMailComposeViewControllerDelegate` so it can dismiss the composer and
  distinguish a sent mail from a cancellation; `MoreViewController` currently
  holds the only such conformance in the tree.
- **`PromptCoordinator`** — §5.

`ReviewPromptPolicy` and `PromptCoordinator` are owned by `Application` as
`lazy var` properties beside `donationsManager`. `FeedbackPromptPresenter` is a
`private lazy var` on `MapViewController` instead — it is only ever presented
from there, and the map is a tab root, so it outlives every alert and composer
it puts up and the weak `mailComposeDelegate` stays valid.
`CoreApplication` is `@MainActor` and OBAKit builds with
`SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` under Swift 6 complete checking, so
`DonationsManager` is implicitly `@MainActor` and can call the coordinator
directly. **`OBAKitTests` builds Swift 5 with `nonisolated` default isolation**,
so the new test classes need explicit `@MainActor`, as `StopSheetPresenterTests`
already does.

Persisted keys, `ReviewPrompt.`-prefixed:

| Key | Type | Meaning |
| --- | --- | --- |
| `successCount` | Int | Successes since the last reset |
| `askCount` | Int | Lifetime asks presented |
| `lastAskedDate` | Date? | Drives the 60/180-day backoffs |
| `outcome` | String? | `positive` \| `negative` \| `deferred` |
| `lastVersionPrompted` | String? | Apple's version gate |

`isPromptPending` is **derived, never stored**:

```
successCount >= threshold && backoffSatisfied && !silenced && versionGateSatisfied
```

An edge-triggered flag set when the counter crosses the threshold would be lost
on termination and could never be re-set, because `recordSuccess()` would never
again *cross* a threshold it's already past — stranding the rider at five
successes and no prompt, permanently.

**Configuration** goes in the nested `OBAKitConfig` dictionary, not top-level
Info.plist — every helper this spec builds on (`appDevelopersEmailAddress`,
`donationsEnabled`) reads from there:

- `OBAKitConfig.AppStoreID` (String). **No App Store ID exists anywhere in the
  repo today** — zero hits for `apps.apple.com`, `AppStoreID`, or `itms-apps` —
  so this is genuinely new configuration for each white-label app.
- `OBAKitConfig.FeedbackPromptEnabled` (Bool), **defaulting to `true` when
  absent**, unlike `donationsEnabled` which defaults to `false` because
  donations require further configuration to function.

Accessors go in `OBAKitCore/Extensions/FoundationExtensions.swift` beside their
siblings. KiedyBus inherits the feature and routes complaints to its own
`info@goeuropa.eu` with no extra work, but needs its own `AppStoreID` before the
positive branch does anything.

### 7. Debug affordances

Without these the feature cannot be QA'd: reaching the threshold organically
takes days and the terminal states are permanent.

These do **not** go in Settings → Experimental. That section holds exactly the
two `FeatureFlags` toggles and carries the footer "Restart the app to apply.",
which is wrong copy for a live debug switch. Built as implemented: a dedicated
"Feedback" section following the Surveys section's precedent
(`alwaysShowSurveysOnStops` lives in its own feature section), placed between
Surveys and Debug in `SettingsViewController`. The whole section — header,
rows, and footer — is hidden behind `hiddenUnlessDebugMode`, the same condition
the Debug section's rows use, so riders never see it. Gating at the section
rather than the rows is what keeps the footer's implementation detail out of
the shipping UI too.

- **Always show feedback prompt** (`ReviewPromptPolicy.alwaysShowPrompt`) —
  bypasses the counter, backoffs, version gate, and lifetime ask cap inside
  `ReviewPromptPolicy.isPromptPending`. It does **not** bypass the
  `FeedbackPromptEnabled` kill switch, and it does **not** bypass
  `PromptCoordinator.canShowReviewPrompt()` — `FeedbackPromptPresenter.presentIfEligible`
  ANDs both checks unconditionally, so the coordinator's session-scoped
  interruption budget and 14-day engagement cooldown still apply while the
  toggle is on. In practice this only matters across repeated presentations in
  one foreground session (or one following a donation/survey engagement); the
  reset button's `promptCoordinator.reset()` call clears the persisted
  cooldown and starts a fresh session, so a single QA pass in a fresh session
  is unaffected. Debug presentations do **not** spend the real ask budget:
  because `alwaysShowPrompt` short-circuits `isPromptPending` ahead of the
  ask-cap and version gates, `recordPromptPresented()` skips the matching
  `askCount` and `lastVersionPrompted` writes while the toggle is on. It still
  stamps `lastAskedDate`, zeroes `successCount`, and writes `.deferred` up
  front, so an abandoned debug alert lands in the same defined state a real one
  would. `ReviewPromptPolicy.reset()` deliberately does not clear the
  `alwaysShow` key itself, so the toggle stays on across a reset; the Feedback
  section's footer says so, since that isn't visible anywhere else in the UI.
- **Reset feedback prompt state** — clears all five `ReviewPrompt.` keys **and**
  calls `PromptCoordinator.reset()`, which clears `lastEngagementDate` and
  `lastPromptKind` and starts a fresh in-memory session. Omitting the latter
  would leave a QA tester blocked for 14 days after a reset.

### 8. Analytics

New `AnalyticsLabels` constants reported through the existing
`Analytics.reportEvent(pageURL:label:value:)`:

`feedback_prompt_shown`, `feedback_positive`, `feedback_negative`,
`feedback_deferred`, `feedback_email_opened`, `feedback_email_sent`,
`rate_app_row_tapped`.

The ratio of `feedback_positive` to `feedback_prompt_shown` is the health
metric. If it drops below roughly two thirds, the threshold is firing too early
and should be raised. Unlike the system prompt, the deep-link path also gives us
a real conversion signal at the point of departure.

### 9. Strings

All copy via `OBALoc` in `OBAKit/Strings`, per the in-repo localization workflow
(13 locales, UTF-8 `.strings`).

| Key | English |
| --- | --- |
| `feedback_prompt.title` | Enjoying %@? |
| `feedback_prompt.positive_button` | Yes! |
| `feedback_prompt.negative_button` | Not really |
| `feedback_prompt.later_button` | Ask Me Later |
| `feedback_prompt.negative.title` | Sorry about that. |
| `feedback_prompt.negative.body` | Would you tell us what's wrong? We read every message. |
| `feedback_prompt.negative.send_button` | Send Feedback |
| `feedback_prompt.negative.decline_button` | No Thanks |
| `more_controller.rate_app` | Rate %@ |

`%@` is `Bundle.main.appName`, so white-label builds read correctly.

### 10. Compliance, stated accurately

App Store Review Guideline **5.6.1, "App Store Reviews"** (under 5.6, Developer
Code of Conduct) reads:

> "Use the provided API to prompt users to review your app; this functionality
> allows customers to provide an App Store rating and review without the
> inconvenience of leaving your app, and we will disallow custom review prompts."

The first draft glossed "custom review prompts" as "custom star-rating UI that
substitutes for the API." **Apple's text contains no such narrowing** and the
term is undefined; that gloss was an assertion about common market practice, not
about the guideline. Stating the position honestly instead:

- We render no rating UI, collect no rating, and transmit no review text. The
  sentiment alert asks a yes/no question and routes.
- The positive branch uses Apple's documented deep link, which their own sample
  code presents as the correct mechanism for a rider-initiated review.
- The tension is that 5.6.1 says "use the provided API," and this design uses
  the deep link rather than `RequestReviewAction` in the prompting flow.

**The alternative we rejected:** keep `AppStore.requestReview(in:)` on the
positive branch, but decouple it from the tap — record `.positive`, arm a
pending request, and fire it at the *next* stop-sheet dismissal. That satisfies
5.6.1 literally and keeps the rider in the app, at the cost of more machinery
and a real chance the prompt silently displays nothing (rate limit spent,
ratings disabled in Settings), so a rider who said "Yes!" is never actually
asked. It also cannot be exercised in TestFlight at all — `requestReview` "has
no effect in apps that you distribute for beta testing using TestFlight."

**Decided 2026-07-25: the deep link.** The trade is guideline-literalism against
conversion, and both readings are defensible; we take the branch that reliably
delivers a warm rider to the review form and can be exercised in every build
configuration.

Also relevant and satisfied: guideline 3.2.2(x) forbids forcing riders to rate
the app. Nothing here is required, gates functionality, or offers an incentive.

## Testing

`OBAKitTests/Feedback/ReviewPromptPolicyTests.swift` — `@MainActor`, injected
clock, isolated `UserDefaults` suite:

- Counter reaches 5 → pending; 4 → not pending.
- `isPromptPending` survives a simulated relaunch at `successCount == 7`
  (the derived-not-stored requirement).
- `.positive` → permanently silenced regardless of later successes.
- `.negative` → silent 180 days, then requires 5 fresh successes.
- `.deferred` → silent 60 days, then requires 5 fresh successes.
- Every outcome resets the counter, so elapsed time alone never re-arms.
- Abandoned ask (outcome never overwritten) behaves as `.deferred`.
- `askCount` reaching 3 → permanently silenced, across outcome permutations.
- Same-version gate blocks a second prompt; a version bump releases it.
- `FeedbackPromptEnabled == false` → never pending.
- Presentations made under `alwaysShowPrompt` spend no ask budget and stamp no
  version, but still write `.deferred` and zero the counter.

`OBAKitTests/Feedback/PromptCoordinatorTests.swift`:

- Second interruption in one foreground session refused, in both orderings.
- Foreground notification clears the session set and `sawErrorThisSession`.
- Review refused within 14 days of a donation modal or survey engagement.
- `canShowInlineCards()` false after a review prompt, true again next session.
- **An inline donation card rendering repeatedly never affects `canShowReviewPrompt()`**
  — the regression test for the starvation bug.
- `noteNotShown` releases a session slot claimed by a prompt that didn't present.

`StopViewModelTests`:

- A successful fetch with a predicted arrival records exactly one success, and
  repeated refreshes on the same view model record no more.
- Scheduled-only arrivals record none. (This lives here, not in the policy
  tests — the `predicted` filter is view-model logic.)
- An arrival predicted only on a hidden route records none.
- An errored fetch records no success and sets `sawErrorThisSession`.
  `APIError.requestNotFound` sets it too unless there is a `bookmarkContext`;
  both branches are pinned.

Alerts, deep-link opening, and the mail composer are not unit tested — the
XCUITest runner is unreliable under Xcode 27. Verify manually with the debug
toggles.

## Rollout

1. Land with `FeedbackPromptEnabled` on. Exercise both branches manually using
   the debug toggles. The deep-link positive branch works in TestFlight and
   release builds alike — one practical advantage over the `requestReview`
   alternative in §10, which cannot be tested in TestFlight.
2. Configure `AppStoreID` for OneBusAway; decide with the KiedyBus maintainers
   whether they want the feature and an ID of their own.
3. Watch `feedback_positive` / `feedback_prompt_shown` for one release cycle.
4. Tune the threshold if the positive ratio disappoints; it's a single constant.

## Open questions

None blocking. The positive-branch mechanism is settled (§10, deep link).

Two smaller decisions taken without explicit sign-off, each reversible in one
line: the threshold of **5** successes, and debouncing per stop view rather than
per refresh tick.
