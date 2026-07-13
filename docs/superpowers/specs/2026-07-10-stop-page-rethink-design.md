# Stop Page Rethink — Design

**Date:** 2026-07-10
**Branch:** `new-stop`
**Deployment target:** iOS 18.0 (`Apps/Shared/app_shared.yml`; CLAUDE.md's "17.0+" is stale). All API choices below assume 18.0 — `@Observable`, `@Entry`, `symbolEffect`, `contextMenu(preview:)`, `.swipeActions` are all available; `LazyVStack` swipe actions (iOS 26) are not.
**Source of truth for visuals/behavior:** Claude Design project "OBA iOS" — `Stop Page Rethink - Implementation Brief.md` + `OBA Stop Page Rethink.html` (components `oba-dep-core.jsx`, `oba-dep-chrome.jsx`, `oba-dep-views.jsx`).

## Summary

A ground-up SwiftUI rebuild of the Stop screen shipping two co-equal list modes behind one segmented toggle — **Chronological** (flat, time-sorted, with a walk-reachability line) and **By route** (one expandable card per route) — plus an inline per-departure **trip-detail panel** with a live approach timeline, and **one-tap alarms** reachable from four surfaces. Three data points are elevated everywhere: real-time vs. scheduled, schedule adherence, and alarms.

Ships behind a **default-ON flag** with fallback to the existing `StopViewController`. Reuses the existing `StopViewModel` (built for exactly this), Obaco server-push alarms, and OBA's existing status color conventions (early = red, late = blue).

## Decisions made (with rationale)

| Decision | Choice | Why |
|---|---|---|
| UI framework | SwiftUI, hosted in `UIHostingController` | `StopViewModel` was explicitly built for a future SwiftUI stop screen; accordions/animated glyphs/toggle are cheap in SwiftUI; matches app direction (sheets, schedules, vehicles are SwiftUI). |
| Rollout | Feature flag, default ON | De-risks white-label variants; fallback while parity gaps get found; like the existing map-panel experimental toggle. |
| Alarm engine | Obaco server-push (existing) | Server tracks prediction and pushes at the right moment even when the app is killed. The brief's local-notification approach cannot reschedule reliably from a suspended app. **Deliberate deviation from brief §4.7's mechanism; its UX requirements all still hold.** |
| Chrome scope | Header card + live status; standard `UINavigationBar` and tab bar | Most of the visual payoff without custom-nav risk. Prototype's floating nav pills and floating tab bar are out of scope. |
| Data layer | Reuse `StopViewModel`, extend | One source of truth for old + new screens while the flag exists; keeps fetch/refresh/pagination/survey/preference logic single-copy. |
| Mode persistence | Existing per-stop `StopPreferences.sortType` (`.time` = Chronological, `.route` = By route) | Round-trips with the old screen; per-stop is richer than the brief's global suggestion. New stops default from a new global "last-used mode" UserDefaults key. |
| V1 parity | Service alerts, surveys + donations, route filter, context menus + previews | Flag defaults ON, so these can't regress. |

## Architecture

### Entry point & flag

- `ViewRouter.navigateTo(stop:)` — already the chokepoint for map taps, bookmarks, deep links, search — instantiates `StopPageViewController` when the flag is on, `StopViewController` when off.
- Flag: UserDefaults bool, default `true`, toggle in Settings → Experimental (pattern: existing map-panel flag).
- `StopPageViewController` is a thin `UIHostingController<StopPageView>` subclass owning nav-bar items and `Previewable` conformance (so stop peeks from map/bookmarks keep working).

### View model

`StopPageView` observes the **existing** `StopViewModel` (`OBAKit/ViewModels/StopViewModel.swift`), which already owns: arrivals fetch, 15 s refresh timer, load-more + auto-extension (35 → +30 min, cap 720), per-stop `StopPreferences` (sortType + hiddenRoutes), survey state, alarm gating (`canCreateAlarm`). It grows four things:

1. **`walkTime: (minutes: Int, distance: Measurement)?`** — computed as `StopViewController` does today (`WalkingDirections.travelTime` straight-line ÷ `userDataStore.walkingSpeedMetersPerSecond`; nil when no location or distance ≤ 40 m). Published; the header chip and walk line read this one value (brief §4.5).
2. **Alarm lookup + mutation** — `alarm(for: ArrivalDeparture) -> Alarm?` matched via `Alarm.deepLink` (tripID + serviceDate + stopID + stopSequence); `setAlarm(departure:leadTime:)` (`ObacoAPIService.postAlarm`), `cancelAlarm(_:)` (`deleteAlarm(url:)` + `userDataStore.delete`), `changeAlarm(_:leadTime:)` (= delete + re-post; Obaco has no update). All alarm UI everywhere calls these three.
3. **`approach(for: ArrivalDeparture) async -> TripDetails?`** — `apiService.getTrip(tripID:vehicleID:serviceDate:)` on trip-panel open, live trips only, cached per trip and invalidated each refresh tick.
4. **`lastUpdated` relative string** for the live status row (largely exists).

**Observation discipline (validated risk).** `StopViewModel` is a Combine `ObservableObject`, whose invalidation is coarse: any `@Published` mutation invalidates every observing view, and this VM churns (`stopArrivals` every ~15 s, `isLoading` twice per refresh, `statusText` on its own 15 s timer). Mitigation for v1: **`StopPageView` is the only view that observes the VM**; every subview (header, status row, both mode lists, rows, panel) takes plain value inputs, so a timer tick re-evaluates one shallow root body and SwiftUI's value diffing stops the propagation. The live status row is its own child taking only the status string, so its churn is isolated. Migrating the VM to `@Observable` (per-property tracking) is the right end state but breaks `StopViewController`'s Combine sinks — deferred until the legacy screen retires.

### Presentation layer

`DepartureStatus` — a value type wrapping `ArrivalDeparture`, the single home of the brief's visual rules:

- `statusColor`: via existing `Formatters.colorForScheduleStatus` → `ThemeColors` (`departureOnTime` green, `departureLate` blue, `departureEarly` red), **gray when `!predicted`**.
- `statusLabel`: "on time" / "{n} min late" / "{n} min early" / **"schedule data"** when `!predicted`.
- The §4.1 hard gate: when `!predicted` → clock glyph (not waves), gray countdown, **occupancy suppressed entirely**, no approach timeline, "scheduled only" notice in the panel.
- Route color (`route.color`, GTFS/agency) is used **only** for the badge and grouped-card stripe — never the countdown (§4.3).

### File layout

```
OBAKit/Stops/StopPage/
  StopPageViewController.swift      hosting shell, nav menus, Previewable, flag glue
  StopPageView.swift                root List: header, status, surveys/donations,
                                    alerts, toggle, mode switch, footer
  StopPageHeaderView.swift          map-snapshot card + walk chip
  Departures/
    ChronologicalListView.swift     past block, walk partition, rows
    GroupedListView.swift           route grouping + card ordering
    RouteCardView.swift             card header, chips, expansion
    DepartureRowView.swift          shared chrono/expanded row
    UpcomingChipsView.swift
  Shared/
    DepartureStatus.swift           status color/label/gate (unit-tested)
    RealtimeGlyph.swift             3-wave pulse / static clock
                                    (one shared animation clock for all instances —
                                    a single list-level TimelineView/phase driver, or
                                    symbolEffect(.variableColor.iterative); never
                                    ~15 independent repeatForever loops)
    CountdownView.swift             "{n}m" + glyph, monospaced digits
    RouteBadgeView.swift
    WalkLineDivider.swift           dashed "N MIN WALK — CATCH BELOW"
  TripPanel/
    TripDetailPanelView.swift       vehicle strip, timeline, alarm, actions
    ApproachTimelineView.swift
    AlarmControlView.swift          set button / info row / stepper
```

`OBAKitCore` changes: `UserDataStore.defaultAlarmLeadTime` (default 5 min) and, if needed, the "schedule data" label in `Formatters`. Nothing else.

## Screen structure

Root is a SwiftUI `List`, inset-grouped styling (rounded cards on `systemGroupedBackground`; native `.swipeActions` — the deciding constraint: on iOS 18 only `List` provides them). Structural rules from validation:

- **Section model differs per mode**: in inset-grouped `List` the rounded card *is* the `Section`. Chronological mode = a few `Section`s (past card, missed card, reachable card); grouped mode = **one `Section` per route card**. Don't hand-draw card backgrounds on composite rows.
- **Row identity**: `ForEach` keyed on `ArrivalDeparture.id` (the composite string — verified stable across prediction refreshes, so diffs animate in place). Never `id: \.self` — `ArrivalDeparture` is an `NSObject` whose equality walks ~30 fields.
- **Rows stay unary**: the predicted/scheduled branching lives *inside* each row's single root `HStack` — no `AnyView`, no top-level `if`/`switch` at the row root, preserving `List`'s templating fast path.
- **Out-of-card rows** (walk-line divider, `— UPCOMING —` divider, live status row) escape the card chrome via `.listRowInsets(EdgeInsets())` + `.listRowBackground(Color.clear)` + `.listRowSeparator(.hidden)`.

Top to bottom:

1. **Header card** (`StopPageHeaderView`): `MapSnapshotter` image as card background (rounded, inset), top-down white scrim, stop name (bold ~22 pt), `Stop #### · {direction} bound` subhead, **walk chip** pinned bottom-left (`{n} min walk · {distance}`, brand green) — rendered only when `walkTime != nil`. Tapping the card toggles the routes-served line, matching today's header behavior. `MapSnapshotter` is callback-based and needs concrete dimensions: bridge via `.task` + continuation into `@State` image, and commit to a fixed card aspect ratio rather than a layout-derived size.
2. **Live status row**: centered `● Updated {relative}` with pulsing dot (static under Reduce Motion), fed by the VM refresh clock.
3. **Surveys / donations** cards — same relative positions as today.
4. **Service alerts** card — icon + title rows, tap → existing alert detail via `ViewRouter`; collapses to a summary row beyond two alerts; honors `stopViewShowsServiceAlerts`.
5. **Segmented toggle** `Chronological ⇄ By route` — custom capsule matching the prototype, `Picker`-equivalent semantics and VoiceOver traits; writes `viewModel.updateSortType(_:)`; mode switch collapses any open accordion.
6. **Mode content** (below).
7. **Footer**: `Load more` (existing pagination/auto-extend; hidden when exhausted) + data-attribution line.

### Chronological mode

- Filtered (`hiddenRoutes`) departures sorted by `arrivalDepartureMinutes`.
- **Past block**: section header `ARRIVALS & DEPARTURES` with trailing `Past · N / Hide past` toggle (persists existing `pastDeparturesCollapsed` key). Past rows are **dimmed only** — no strikethrough (§4.2) — in their own card above an `— UPCOMING —` divider.
- **Walk partition** (only when `walkTime != nil`): rows with `minutesAway < walkMinutes` form the "missed" card — **dimmed + strikethrough destination + gray countdown** — followed by the dashed green **`{n} MIN WALK — CATCH BELOW`** divider, then the reachable card. No walk data → no partition, no divider, no chip (same nil source).
- **Row** (`DepartureRowView`): route badge · destination (2-line wrap) · `{sched time} · {adherence}` line (time secondary, adherence in status color) · trailing `CountdownView` (big `{n}m` in status color + `RealtimeGlyph`). Bell-on glyph appears in the second line when the departure has an alarm.
- **Swipe actions**: Alarm (green, only if `canCreateAlarm`) · Schedule (teal, region-gated) · Save (orange → bookmark editor). Same gating as today's `trailingContextualActions`.
- Row tap toggles the inline trip panel.

### Grouped ("By route") mode

- Group filtered list by route, preserving first-appearance order after the time sort → routes ranked by soonest departure (§4.9).
- **Card header** = the route's next departure: 5 pt route-color accent stripe (left edge), badge, destination, `sched · adherence`, big countdown + glyph.
- **Upcoming chips**: up to 3 pills (`12m`, `27m`, …), each tinted by *its own* status color; empty state reads **"later trips not loaded"** — never "no later trips" (§4.4).
- Header right side: compact **Alarm pill** (bell; shows `{n}m` when the next departure has an alarm; toggles it) + rotating disclosure chevron.
- **Expansion** (one route at a time): every loaded departure for the route — far-left icon-only alarm toggle (filled when set), `{time} · {adherence}` with occupancy beneath (or "schedule data"), right-aligned compact countdown, chevron. Tapping a row opens the trip panel beneath it.
- No walk line or past block in grouped mode (matches prototype and today). Header walk chip still shows.

### Shared visual rules

- Countdown, glyph, and chips colored by **adherence status only**; route color confined to badge + stripe (§4.3).
- OBA convention: **early = red, late = blue** (existing `ThemeColors`).
- Monospaced digits on all countdowns and chips.
- Occupancy rendered **only** when `predicted` (§4.1).
- Two kinds of dimmed rows (§4.2): *missed* = dim + strikethrough; *past* = dim only.

## Trip-detail panel

`TripDetailPanelView` renders inline beneath the opening row (chrono row or grouped expanded row) on the grouped-background tint. One panel open per screen; mode switch or the departure dropping from the feed closes it. Input is `(ArrivalDeparture, DepartureStatus, alarm state)` + callbacks — entry-point-agnostic (§4.6).

**Accordion mechanics (validated risk):** the panel is a **separate row inserted into the `ForEach` after the opening row** (keyed off the selected departure id), not content growing inside the tapped row — `List` animates row insert/remove smoothly but handles self-sizing row-height growth poorly (clipping/cross-fade). Same mechanism for the grouped card's expanded departure rows. **This interaction gets prototyped first** (spike task in the plan) since it shapes the row structure.

- **Live vehicle strip** (predicted): route-colored wave glyph + `Live · vehicle {id}` + occupancy.
- **Scheduled-only notice** (unpredicted): static clock + *"Scheduled time only — no live signal from this bus yet; this is when it's supposed to arrive. It may run early, late, or not at all."* No vehicle, occupancy, or timeline.
- **Approach timeline** (live only): from the on-open `TripDetails` fetch, take the user's stop (`stopID` + departure `stopSequence`) and the **4 preceding stops**; vehicle marker at `tripStatus.closestStopID` (same flag `TripStopListItem` uses). Vertical line-and-dot: stops at/behind the bus gray, stops between bus and user in route color, user's stop a larger route-color dot labeled `· your stop`, tinted `bus here · {n}m away` pill at the vehicle row. Loading → compact shimmer placeholder; fetch failure or vehicle past the 5-stop window → drop the timeline silently, keep the strip. Cache invalidated per refresh tick so the marker advances.
- **Alarm control**: default full-width green **"Set an alarm"**; once set, info row *"Alarm set · Buzz {n} min before it arrives"* with **Change** (inline −/+ stepper) and **Cancel**.
- **Actions**: half-width **Schedule** (existing `ScheduleForStopView`, region-gated) and **View full trip** (existing `TripViewController` via `ViewRouter`).

## Alarms

Four entry points, one state (§4.7): chrono swipe, grouped header pill, grouped expanded-row icon, trip-panel control — all render from `alarm(for:)` and call the same three VM methods, so any surface's change is instantly visible everywhere.

- **Set**: `postAlarm` with `UserDataStore.defaultAlarmLeadTime` (default 5 min; new Settings row offering the prototype's 2/5/10). No picker interruption (replaces the `AlarmBuilder` bulletin flow on this screen).
- **Clamp**: stepper 1–15 min, additionally capped at `arrivalDepartureMinutes − 1`. Departures ≤ 1 min away: alarm affordances disabled (existing `canCreateAlarm` gating requires `arrivalDepartureMinutes > 1`; the same gate covers regions without Obaco/push — there, alarm UI is absent from all four surfaces).
- **Change**: delete + re-post, optimistic UI, rollback + toast on failure.
- **Cancel**: `deleteAlarm(url:)` + local removal — Stop screen finally gains cancel (today: Recents only).
- **Push permission**: first set runs the existing `PushService` registration; denial shows the existing guidance alert.
- Expired alarms purge on refresh via existing `deleteExpiredAlarms()`.
- **No client-side rescheduling** — the Obaco server owns prediction tracking (deliberate deviation from brief §4.7's local-notification mechanism).

## Chrome parity

- **Nav bar**: standard `UINavigationBar`, stop name as small title (small title deliberately avoids large-title-collapse coordination with a hosted `List`; configure the scroll-edge appearance so the bar background behaves on scroll). Bar items live on the hosting VC (UIKit), sidestepping the deprecated SwiftUI `navigationBarItems` path. Menus carry over as bar items on the hosting VC: **Filter** (route filter → existing `StopPreferencesView` sheet) and **More** pulldown (Add Bookmark, Share, Report a Problem, Nearby Stops, All Service Alerts, Walking Directions) calling the same VM/router methods as today. The **Sort menu is removed** — the toggle supersedes it.
- **Context menus**: rows get `.contextMenu(menuItems:preview:)` mirroring swipe actions + "Show Trip Details". The preview embeds `TripViewController` via `UIViewControllerRepresentable` **constructed lazily inside the preview closure** (SwiftUI builds it on long-press, not per row) with an explicit frame — a representable has no intrinsic size. If the live-map preview proves heavy, fall back to a static snapshot + trip-summary preview.
- Prototype's floating nav pills and floating tab bar: **out of scope** (v1 uses standard chrome).

## Error & empty states

- Fetch failure with data: keep last-good data visible (VM already does); failure with none: existing error card + retry.
- Zero upcoming departures: "No departures in the next {n} minutes" above Load more — never wording implying no more service exists (§4.4).
- Everything filtered out: "All routes at this stop are filtered" + button opening the filter sheet.
- No location permission: chip and walk line simply absent.

## Accessibility

- Each row is one VoiceOver element: "Route 132 to Downtown Seattle, departs in 5 minutes, 4 minutes late, live tracking" / "…scheduled time only, no live data." Glyph decorative/hidden. Swipe actions surface as custom actions via `List`.
- Replaces the old screen's dedicated accessibility layout with combined elements + Dynamic Type (rows scale; destination line-limit relaxes at accessibility sizes; chips wrap).
- Reduce Motion: wave glyph and status pulse render static; accordion uses opacity fade.
- Color never the sole signal — every status color pairs with a text label; palette is `ThemeColors`' dynamic (dark-mode-aware) colors. `ThemeColors`/`Formatters` return `UIColor` — bridge with `Color(uiColor:)`, not the soft-deprecated `Color(_:)`. Reduce Motion is read from `@Environment(\.accessibilityReduceMotion)`.

## Testing

Unit tests in `OBAKitTests` against pure logic (no UI tests, per repo convention):

- **`DepartureStatus`**: `!predicted` ⇒ gray + "schedule data" + occupancy suppressed; deviation → color/label mapping incl. early=red/late=blue.
- **Chronological partition**: missed/reachable split at walk threshold; nil walk ⇒ no partition; past vs missed distinction.
- **Grouping**: soonest-departure route order; hiddenRoutes respected; chips = departures 2–4; "later trips not loaded" when a route has one loaded trip.
- **Alarms**: `alarm(for:)` deep-link identity matching; clamp math (1–15 ∧ minutes−1); change = delete-then-post ordering.
- **Approach slice**: 5-stop window by stopSequence; vehicle index from `closestStopID`; past-the-window ⇒ nil.
- Existing `StopViewModel` tests keep passing (extensions only add surface).

Verification: `scripts/generate_project OneBusAway`, build-for-testing + `OBAKitTests` on the iPhone 17 simulator (TEST BUILD SUCCEEDED is the local bar; the runner crashes under Xcode 27's UIScene issue), plus a manual simulator walkthrough of both modes against a live region.

## Validation

An independent review (Opus agent, swiftui-specialist skill + Apple docs) confirmed the architecture with no blockers, and verified against the codebase: `ArrivalDeparture.id` is stable across prediction refreshes (animated diffs work), `canCreateAlarm` gating and `ArrivalDepartureDeepLink` matching exist exactly as this spec assumes, and `tripStatus.closestStopID` is the same vehicle-position field the Trip screen uses. Its should-fix findings are incorporated above (observation discipline, accordion-as-inserted-row + spike, per-mode section models, out-of-card row modifiers, lazy context-menu preview, shared glyph animation clock, `MapSnapshotter` bridging, `Color(uiColor:)` bridging, iOS 18.0 target). The two items to prototype before broad build-out: the inserted-row accordion animation, and root-only VM observation under the 15 s refresh churn.

## Out of scope

- Prototype Tweaks panel (design-tool control only).
- Floating nav pills / floating tab bar chrome.
- Changes to the Trip screen, Schedule screen, map rendering, or past-departures data source (existing surfaces we link into).
- Local-notification alarms.
- Removing `StopViewController` (happens after the flag proves out, separate effort).
