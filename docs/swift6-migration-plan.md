# Swift 6 Language Mode Migration Plan

*Written 2026-07-16, revised same day after an adversarial documentation review.
Measurements taken on `main` @ `0ae45cb3` with Xcode 27.0 beta 3 (Swift 6.4
toolchain). CI runs Xcode 26.6 — see the toolchain caveat in the Phase 4
status section: Xcode 26.2's compiler crashes the Swift 6 test suite at
runtime. Contributors need a recent Xcode 26.4+ / 27 toolchain.*

## Where we started (2026-07-16; see the Sequencing summary for current status)

Every target builds in the Swift 5 language mode (`SWIFT_VERSION = 5.0`) with
`SWIFT_STRICT_CONCURRENCY = minimal` — the Xcode defaults. Nothing in the
XcodeGen YAML files sets a language mode or checking level today.

The codebase is already partway there in spirit: `RESTAPIService` and
`ObacoAPIService` are actors, there are ~134 `@MainActor` annotations and ~153
`async` functions, and scattered `@preconcurrency` / `nonisolated(unsafe)`
markers show earlier prep work. The remaining gap is the parts of the code the
compiler has never checked.

## What the compiler says (measured, not guessed)

Three configurations of the `App` scheme were built to scope the work. All
counts are **unique diagnostics in our code** (deduplicated; SPM dependencies
excluded).

| Configuration | OBAKitCore | OBAKit | OBAWidget | Apps | Total |
|---|---|---|---|---|---|
| A. `complete` checking only (today's isolation defaults) | 119 | 467 | 10 | 12 | **608** |
| B. A + MainActor-by-default **everywhere** | 200 + 2 errors | did not compile | — | — | worse |
| C. A + MainActor-by-default **in OBAKit only** | 119 | 80 + 22 errors | 10 | n/a* | **~231** |
| D. A, `build-for-testing` (adds OBAKitTests) | — | — | — | +394 | **~1,002** |

*\* App target didn't compile in run C because OBAKit failed; its baseline is 12.*

Run D fills the test-target gap: OBAKitTests contributes 394 diagnostics, but
they're highly mechanical — 132 are "main actor-isolated property … in a
nonisolated autoclosure" (i.e. `XCTAssert` expressions touching UIView
properties), concentrated in the `Controls/` view tests. `@MainActor` on those
test classes clears them wholesale. The OBAKit count reproduced exactly (467)
across two independent builds, so the baseline is stable.

Run B's two hard errors (`LiveActivityRegistry.swift:279`, a
`nonisolated(nonsending)` closure passed where `@isolated(any)` is expected)
come from approachable concurrency's `NonisolatedNonsendingByDefault`, not
from MainActor defaulting — meaning **enabling approachable concurrency on
OBAKitCore breaks its build until that call site is fixed**. Phase 0 therefore
enables checking only; approachable concurrency turns on per-module as each
phase starts.

Two conclusions fall out of this:

1. **Default MainActor isolation is the right call for the UI layer and the
   wrong call for OBAKitCore.** It eliminates ~78% of OBAKit's diagnostics
   (467 → ~102), because most of them were "main actor-isolated X referenced
   from nonisolated context" noise in code that only ever runs on the main
   thread. Applied to OBAKitCore it *adds* diagnostics (119 → 200 + 2 hard
   errors), because Core's actor-based networking, `Operation` subclasses, and
   background decoding genuinely aren't main-actor code.
2. **The hard problems are countable and specific.** The 22 errors in run C
   and the 119 Core warnings cluster into a handful of patterns listed below —
   this is a few weeks of focused work, not an open-ended rewrite.

## Target architecture

| Target | Default isolation | Rationale |
|---|---|---|
| OBAKit | `MainActor` | UIKit/SwiftUI framework; everything is main-thread anyway |
| App, OBAWidget | `MainActor` | App/extension entry points; Apple's recommended default |
| OBAKitCore | `nonisolated` (today's default) | Owns actors, networking, background decode; must stay extension-safe |

All targets get `SWIFT_STRICT_CONCURRENCY = complete` first (warnings in
Swift 5 mode). Each module then enables `SWIFT_APPROACHABLE_CONCURRENCY = YES`
(plus `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` for the UI layer) when its
phase starts, and flips to `SWIFT_VERSION = 6.0` when it reaches zero
concurrency warnings. Module-by-module adoption per Apple's
[Adopting strict concurrency in Swift 6 apps](https://developer.apple.com/documentation/swift/adoptingswift6)
and the [swift.org migration guide](https://www.swift.org/migration/documentation/migrationguide/).

Two rules that come straight from the review of those sources:

- **`SWIFT_APPROACHABLE_CONCURRENCY` stays on permanently, including after
  the Swift 6 flip.** Two of its five upcoming features
  (`InferIsolatedConformances`, `NonisolatedNonsendingByDefault`) are *not*
  part of the Swift 6 language mode — dropping the setting after migrating
  would silently revert isolation semantics the Phase 2 fixes depend on.
- **Ordering is a deliberate deviation.** Apple's article and the migration
  guide both suggest starting from the outermost module (the app) because
  annotations flow downward more easily. We invert that (Core first) on
  measured evidence: most of OBAKit's hard errors are overrides of
  *unannotated OBAKitCore declarations*, so annotating Core's base classes
  and delegate protocols is the bottleneck either way. The guide's wording is
  soft ("It can be easier to start with the outer-most root module"), and it
  explicitly allows any order. Note also the guide does not require zero
  warnings before flipping a module ("You don't have to eliminate all
  warnings to move on") — our zero-warnings exit criterion is stricter by
  choice; the CI ratchet is what makes it workable.

## Phase 0 — Turn the lights on (1 PR, no code changes required to land)

1. In `Apps/Shared/app_shared.yml` (applies project-wide):
   ```yaml
   settings:
     base:
       SWIFT_STRICT_CONCURRENCY: complete
   ```
   Approachable concurrency and MainActor defaulting are deliberately *not*
   enabled here — `NonisolatedNonsendingByDefault` produces hard errors in
   `LiveActivityRegistry.swift:279` (measured, run B), and MainActor-default
   produces 22 hard errors in OBAKit (run C). Each module's phase enables
   them together with the fixes.
2. Add a CI ratchet so the warning count only goes down: grep
   `xcodebuild` output for concurrency diagnostic tags
   (`#ActorIsolatedCall`, `#SendableClosureCaptures`, `#RegionIsolation`,
   `#ConformanceIsolation`, `#MutableGlobalVariable`, "Swift 6 language
   mode") and fail if the count exceeds a checked-in baseline number.
   Once a module hits zero, set `SWIFT_WARNINGS_AS_ERRORS_GROUPS` for the
   concurrency groups on that target so it can't regress (all five tags are
   real diagnostic groups in `swiftlang/swift`'s `DiagnosticGroups.def`, and
   the setting passes them via `-Werror <group>`).
3. Fix the committed `Package.resolved` staleness: the GRDB entries are now
   pinned in both `Apps/OneBusAway/Package.resolved` and
   `Apps/KiedyBus/Package.resolved` (`minorVersion: 7.11.0` in
   `app_shared.yml`, resolving to 7.11.1; done alongside the Phase 1 GRDB
   upgrade, issue #1195). KiedyBus still lacks an OTPKit pin (and its
   transitives) — run `scripts/update_package_resolved` to finish this step.

Do **not** set these via `xcodebuild` command-line overrides or a global
xcconfig — they leak into SPM package compilation (measured: `swift-http-types`
fails to compile under forced MainActor isolation). Target-level settings in
the generated project are safe.

## Phase 1 — OBAKitCore to zero warnings, then Swift 6 mode (119 diagnostics)

Core goes first: it's the dependency root, and several of OBAKit's hard errors
exist only because Core's types aren't annotated yet.

Start the phase by enabling `SWIFT_APPROACHABLE_CONCURRENCY: YES` on the
OBAKitCore target and fixing the known `LiveActivityRegistry.swift:279`
error, then run the compiler's **migration mode** for automated fix-its
before hand-fixing: each upcoming feature accepts a `:migrate` variant
(`-enable-upcoming-feature InferIsolatedConformances:migrate`, likewise
`NonisolatedNonsendingByDefault:migrate`) documented in the swift.org guide's
feature-migration article.

Hot spots, largest first:

| File | Count | Pattern |
|---|---|---|
| `DataMigration/DataMigrator.swift` | 35 | non-Sendable models crossing task boundaries |
| `Models/AgencyAlertsStore.swift` | 19 | NSLock + DispatchQueue + mutable shared state → convert to actor or @MainActor |
| `Network/RESTAPIService/RESTAPIService+Get.swift` | 16 | `RESTAPIURLBuilder` (NSObject class) exiting the actor → make it a Sendable struct |
| `Network/Operations/NetworkOperation.swift` | ~14 | `Operation` subclass isolation |
| `Utilities/DecodingErrorReporter.swift` | ~7 | mutable statics → `OSAllocatedUnfairLock`/actor, or main-actor confine |
| `Utilities/Logger.swift`, `Theme/Theme.swift` | few | `static let shared` NSObject singletons → make Sendable (immutable) or actor-confine |

The structural decision that drives most of the count: **REST model
Sendability.** The models (`ArrivalDeparture`, `StopArrivals`, `TripStatus`, …)
are mutable `NSObject` subclasses (`class X: NSObject, Decodable,
HasReferences`) that are decoded inside the `RESTAPIService` actor and then
handed to the main actor — the exact hop strict checking flags. Options:

- **(a) Effectively-immutable + `@unchecked Sendable`** *(recommended)*:
  models are only mutated during decode + `loadReferences(_:regionIdentifier:)`
  wiring, then treated as read-only. Audit that invariant, convert stored
  `var`s to `private(set)` where possible, document it, and conform the model
  base types to `@unchecked Sendable`. Low-risk, preserves ObjC compat and
  reference identity. Two caveats the migration guide insists on: the
  conformance is **inherited by subclasses**, and the compiler can only
  validate immutability for `final` classes — so make each model `final`
  before marking it, or a future subclass silently inherits the unchecked
  promise. And "immutable" here really means "immutable after
  `loadReferences` completes" — that handoff ordering (mutation finishes
  before the object crosses an isolation boundary) is the actual invariant;
  enforce it with an assertion or at minimum a doc comment on
  `HasReferences`, not just a one-time audit.
- **(b) Struct conversion**: the honest fix, but touches every consumer of 21
  model classes plus `HasReferences`' post-decode mutation design. Do this
  opportunistically per-type later, not as a migration blocker.
- **(c) Main-actor confinement**: decode on main. Simple but regresses
  scrolling/refresh performance; rejected.

Also in this phase: annotate `CoreApplication`, `CoreAppConfig`, and the
delegate protocols that are UI-facing (`RegionsServiceDelegate`,
`AgencyAlertsDelegate`, … — note `PushServiceDelegate` lives in OBAKit, so it
belongs to Phase 2, where MainActor-default covers it anyway) as
`@MainActor`. They are
implemented by view controllers and `Application` today; annotating them in
Core removes most of OBAKit's "different actor isolation from nonisolated
overridden declaration" errors at the source. `SurveyService`'s
`nonisolated(unsafe)` properties and `LiveActivityTracker`'s
`nonisolated(unsafe) let registry` get revisited here too.

Exit criterion: `SWIFT_VERSION: "6.0"` on the OBAKitCore target, zero errors.

## Phase 2 — OBAKit with MainActor default, then Swift 6 mode (~102 diagnostics)

Enable `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` (if not already on from
Phase 0) and fix the 22 hard errors first — they're three patterns:

One SE-0470 caveat before touching conformances: on OS releases older than
the 2025 (v26) generation, the runtime doesn't know about isolated
conformances, so **dynamic casts through an isolated conformance succeed even
off the conformance's actor** — with an iOS 18 deployment target this is a
real (if narrow) soundness hole. Prefer making the conformances genuinely
`nonisolated` (as below) over leaning on isolated conformances for anything
that flows through `as?`/`is` checks.

1. **Diffable data source identifiers (11 errors)**:
   `UICollectionViewDiffableDataSource` requires `Sendable` +
   nonisolated-`Hashable` identifier types. `OBAListViewSection`,
   `AnyOBAListViewItem`, and `NearbyStopsListViewController`'s `Item`/`Section`
   become MainActor-isolated under the new default, so their `Hashable`
   conformances no longer satisfy it. Fix: mark these value types (or just
   their `Hashable`/`Equatable` conformances) `nonisolated`, and where the
   payload is genuinely main-actor-bound, hash/compare by stable identifier
   fields only. Files: `Controls/ListView/OBAListView.swift`,
   `Mapping/NearbyStopsListViewController.swift`.
2. **Overrides of nonisolated Core/third-party declarations (9 errors)**:
   `Application: CoreApplication` (init, `apiServicesRefreshed`,
   `regionsService(_:updatedRegion:)`), `AppConfig: CoreAppConfig.init`,
   BLTNBoard's `ThemedBulletinPage.init(title:)`
   (in `OBAKit/BLTNBoard/OBABulletinPage.swift`), FloatingPanel's
   `Layouts.initialState`, `MapFloatingPanelController.deinit`,
   `AlarmBuilder.makeViewsUnderDescription(with:)`. Most disappear once Core's
   base classes are `@MainActor` (Phase 1); the third-party ones take
   `nonisolated` on the override plus an internal `MainActor.assumeIsolated`
   where needed.
3. **One-offs (2 errors)**: a default argument that's both main-actor-isolated
   and `@concurrent` (`Application.swift:99`), and an inference break in
   `NearbyStopsListViewController.swift:124`.

Then burn down the remaining ~80 warnings (biggest files under the new
default: `AlarmBuilder`, `SearchRequest`, `ContactUsHelper`,
`MapRegionManager`, `RegionPickerCoordinator`). Third-party UIKit libraries
(Eureka, BLTNBoard, FloatingPanel, MarqueeLabel, Hyperconnectivity) are all
pre-Swift-6 packages — they don't block us (each compiles in its own language
mode) but their APIs are unannotated; use `@preconcurrency import` at the use
sites rather than sprinkling `@unchecked Sendable` wrappers.

Exit criterion: `SWIFT_VERSION: "6.0"` on the OBAKit target.

### Phase 2 implementation notes (done 2026-07-16)

The 128-warning burn-down resolved into a handful of structural moves rather
than 128 point fixes:

- **The `OBAListView` view-model layer went `nonisolated` wholesale** — the
  `OBAListViewItem` protocol, its default-implementation extension, all 23
  conforming item structs, all 14 `OBAContentConfiguration` conformers, and
  the support types (`OBAListViewItemConfiguration`,
  `OBAListViewContextualAction`, `OBAListRowSeparatorConfiguration`,
  `OBAListSectionConfiguration`, `OBALabelConfiguration`,
  `OBAImageViewConfiguration`, the `UIListContentConfiguration` helper
  extension). These are value-type view models whose `Hashable` witnesses the
  diffable data source exercises; isolating them was never meaningful. Where a
  member genuinely needs UIKit (`OBAListViewContextualAction.contextualAction`)
  or reads `Application` state (`StopHeaderItem.init`), that one member is
  `@MainActor`.
- **Watch for extensions**: `nonisolated` on a type does NOT flow to its
  extensions under MainActor-default — `AppSheetRoute` was nonisolated while
  its `id`/`detentConfiguration` extensions silently stayed MainActor,
  poisoning four conformances. Every extension of a nonisolated type needs its
  own `nonisolated`.
- **`OBALoc` and `Icons` became nonisolated** — pure bundle/UIImage lookups;
  this alone cleared ~20 diagnostics. `Icons.iconCache` became a
  thread-safe `NSCache` (it really is cross-isolation shared state now).
- **Main-thread callbacks got `MainActor.assumeIsolated`**: CLGeocoder
  completion, main-run-loop `Timer`s (MapViewController, SearchInteractor,
  ProgressHUD), FloatingPanel layout callbacks. Background-queue callbacks got
  `Task { @MainActor in }` instead: `UNUserNotificationCenter`
  authorization, `NSItemProvider.loadFileRepresentation` (which was a real
  pre-existing race — it mutated SwiftUI `@State` off-main).
- **REST-model Sendable audit extended** per the HasReferences contract:
  `ServiceAlert`, `TripDetails`, `ArrivalDeparture`, `VehicleStatus`,
  `Agency`, plus `TripConvertible` and `TripAttributes`/`ContentState`
  (needed by ActivityKit sends).
- **Region-isolation errors after the flip** (they were warnings under
  Swift 5) needed value re-fetching rather than actor-entering:
  a task-isolated Eureka `row` can't be captured by any main-actor closure
  even inside `MainActor.assumeIsolated` — re-fetch via `form.rowBy(tag:)`
  inside the task; a non-Sendable `Activity` fetched on the main actor can't
  be sent to ActivityKit's `@concurrent update` — re-fetch by ID inside
  `Task.detached`.
- **`@MainActor` can't be spelled on a typealias'd function type**
  (`@escaping @MainActor VoidBlock` → "unknown attribute"); write the function
  type out. `DispatchQueue.debounce/throttle` became main-actor-only APIs with
  main-actor global bookkeeping (they were only ever used from main).
- Annotating OBAKit types pushed 48 more test classes to `@MainActor`
  (every remaining plain-`XCTestCase` class in OBAKitTests is annotated now).

## Phase 3 — App targets, widget, ObjC shims (~22 diagnostics)

- OBAWidget: 10 warnings; already extension-safe and mostly SwiftUI. MainActor
  default + fixes, flip to 6.
- Apps (OneBusAway + KiedyBus + CommonClient): 12 warnings, plus the small
  ObjC layer (`AppDelegate.m`, `SceneDelegate.m`, `main.m`) which is untouched
  by Swift language mode. ObjC imports are automatically treated as
  `@preconcurrency`, and the headers can carry concurrency attributes with no
  ABI impact — annotate the `OBAApplicationDelegate`-facing ObjC surface with
  `NS_SWIFT_UI_ACTOR` where it's main-thread-bound rather than merely
  verifying the bridging still compiles.
- Flip the remaining targets and make `SWIFT_VERSION: "6.0"` the project-wide
  base setting in `app_shared.yml`. Verify the KiedyBus flavor with
  `scripts/generate_project KiedyBus` — it shares all of this via
  `app_shared.yml`.

### Phase 3 implementation notes (done 2026-07-16)

`app_shared.yml` now sets `SWIFT_VERSION: "6.0"`,
`SWIFT_APPROACHABLE_CONCURRENCY: YES`, and
`SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` project-wide;
`OBAKitCore/project.yml` pins `SWIFT_DEFAULT_ACTOR_ISOLATION: nonisolated`
against the new base (a project-wide MainActor default would otherwise leak
into Core). Actual code fixes were tiny: the widget's AppIntent `static var
title`/`description` metadata became `let`; `PlausibleAnalytics` prop
plumbing went `[String: Any?]` → `[String: (any Sendable)?]` (AviaryInsights'
`Event` requires it — the `Any?` arriving through the @objc `Analytics`
protocol is stringified at the boundary); `AnalyticsOrchestrator.userDefaults`
is `nonisolated(unsafe)` for the nonisolated `reportingEnabled()` path;
`AnalyticsKeys` is a nonisolated constants namespace. The `sending`
warnings in `AnalyticsOrchestrator`'s fire-and-forget `Task`s disappeared
with `NonisolatedNonsendingByDefault` on the App target, as predicted.
The ObjC `AppDelegate`/`SceneDelegate` headers carry `NS_SWIFT_UI_ACTOR`.

## Phase 4 — Tests (394 diagnostics, measured)

OBAKitTests (168 files, all XCTest) contributes 394 diagnostics under
complete checking (run D). The bulk is mechanical: 132 "main actor-isolated
property in a nonisolated autoclosure" (i.e. `XCTAssert(view.someProperty…)`)
concentrated in `Controls/` view tests — `@MainActor` on those test classes
clears them in batches. The rest: mocks like `MockDataLoader` need Sendable
treatment, and 26 diagnostics just ask for `@preconcurrency import`. Fix
alongside each phase (the ratchet counts tests too, via
`build-for-testing`), flip the target last. The in-repo `modernize-tests`
tooling can piggyback Swift Testing migration on files that get touched
anyway, but don't couple the two efforts.

### Phase 4 status: blocked on the toolchain (2026-07-16)

Every test class is `@MainActor` and the warning count is down to 39, but the
Swift 6 flip itself is **blocked on Xcode 27 beta 3**: its XCTest declares
`XCTestCase`'s designated initializers nonisolated, and in the Swift 6
language mode every `@MainActor` test class fails with "main actor-isolated
initializer 'init(invocation:)' has different actor isolation from
nonisolated overridden declaration" on its *synthesized* initializer
overrides. There is no source-level fix: `init(invocation:)` takes
`NSInvocation`, which is unavailable in Swift, so an explicit `nonisolated
override` cannot be written, and the mismatch re-materializes in every
subclass (verified with a standalone `swiftc -typecheck` probe). The
`nonisolated class` + `@MainActor`-per-member shape does compile, but that's
a ~70-file rewrite fighting a beta toolchain — `@MainActor XCTestCase`
subclasses are the standard pattern everywhere else.

`OBAKitTests/project.yml` therefore pins the test target to
`SWIFT_VERSION: "5.0"` with `SWIFT_DEFAULT_ACTOR_ISOLATION: nonisolated` and
`SWIFT_APPROACHABLE_CONCURRENCY: NO` (its measured, ratcheted status quo).
Re-try the flip on the next Xcode release; if it still errors, file feedback.

**Toolchain caveat (2026-07-16, cost two CI cycles to isolate):** building
with **Xcode 26.2** crashes the Swift 6 test suite at runtime — a
deterministic malloc abort in the isolated-deinit machinery
(`swift_task_deinitOnExecutorMainActorBackDeploy` →
`TaskLocal::StopLookupScope` →
`BUG_IN_CLIENT_OF_LIBMALLOC_POINTER_BEING_FREED_WAS_NOT_ALLOCATED`). Xcode
26.2's compiler emits implicitly-isolated deinits for MainActor-default
classes, and that path double-frees when objects deallocate inside tasks
carrying task-locals (XCTest's async lifecycle guarantees exactly that). It
reproduces on both iOS 18.5 and iOS 26.2 simulators, so it's codegen, not
the runtime. Xcode 27 beta 3 (Swift 6.4) does not emit implicit isolated
deinits and is unaffected — CI is pinned to Xcode 26.6, the newest
same-generation compiler on GitHub's runner images. Watch the 11 explicit
`isolated deinit` sites on iOS 18 devices regardless: they use the
back-deploy shim compiled by whatever Xcode builds the release.

Consequence of the pin worth remembering: the test target compiles with only
`complete`-checking warnings, not Swift 6 enforcement — concurrency
regressions in test-only helpers and mocks (e.g. the `@unchecked Sendable`
mocks in `OBAKitTests/Helpers/Mocks/`) won't be compiler errors until the pin
is lifted. The ratchet still counts their warnings.

## Dependency notes

| Package | Pinned | Swift 6 posture |
|---|---|---|
| GRDB.swift | `minorVersion: 7.11.0` range (resolves to 7.11.1) | Done (issue #1195): GRDB 7 is the Sendable-annotated major; `StopCacheDatabase`/`StopCacheRepository` now declare compiler-checked `Sendable` instead of `@unchecked Sendable` |
| Eureka, BLTNBoard, FloatingPanel, MarqueeLabel, Hyperconnectivity | 5.x-era | Unmaintained or slow-moving; plan on `@preconcurrency import` indefinitely. BLTNBoard is archived upstream — the existing `OBAKit/BLTNBoard` wrapper layer is the eventual replacement seam |
| SwiftProtobuf | 1.32 | Generated `gtfs-realtime.pb.swift` is already `@unchecked Sendable`-annotated; regenerate with a current plugin if warnings appear |
| firebase-ios-sdk, OTPKit, swift-openapi-* | current | Already tools-6.x; no action |

## Measurement gotchas (for whoever re-runs the numbers)

- Reproduce the baseline with:
  `xcodebuild build -project OBAKit.xcodeproj -scheme App -destination 'platform=iOS Simulator,name=iPhone 17 Pro' SWIFT_STRICT_CONCURRENCY=complete`
  then count `sort -u`'d `warning:` lines under the repo path. Don't pass
  `SWIFT_DEFAULT_ACTOR_ISOLATION` on the command line — it breaks SPM package
  compilation (see Phase 0).
- If Xcode has the project open, CLI builds race the IDE over
  `SourcePackages/artifacts` after a `scripts/generate_project` run and fail
  with "There is no XCFramework found…". Use `-derivedDataPath` for CLI
  measurement builds, or close Xcode.
- Xcode 27 beta 3's issue navigator (and MCP `GetBuildLog`) under-reports
  compiler diagnostics; trust the raw `xcodebuild` log.

## Sequencing summary

| Phase | Scope | Diagnostics | Exit | Status |
|---|---|---|---|---|
| 0 | Build settings + CI ratchet + Package.resolved fix | 0 fixed | warnings visible, count frozen | ✅ done |
| 1 | OBAKitCore (+ approachable concurrency) | 119 → 0 | Core in Swift 6 mode | ✅ done |
| 2 | OBAKit (+ MainActor default) | 467 → 0 | OBAKit in Swift 6 mode | ✅ done |
| 3 | App, OBAWidget, KiedyBus | 14 → 0 | whole project `SWIFT_VERSION = 6.0` | ✅ done |
| 4 | OBAKitTests | 39 remain* | tests in Swift 6 mode | ⛔ blocked on Xcode 27 b3 XCTest (see Phase 4 status) |

*\* The test count spiked to 596 after Phase 1 (`OBATestCase` going
`@MainActor` surfaced autoclosure warnings), then collapsed once every
remaining plain-`XCTestCase` class was annotated `@MainActor`.
Ratchet baseline: 999 → 733 (Phase 1) → 57 (Phase 2) → 39 (Phase 3; all 39
are in the pinned OBAKitTests target).*

### Phase 1 implementation notes (2026-07-16)

Phase 1 could not land without starting Phase 2: making `CoreApplication`
`@MainActor` turns OBAKit's synchronous references to it into hard errors even
in Swift 5 mode, so OBAKit's MainActor-default settings and its 22 hard-error
fixes shipped in the same change. Notable patterns used:

- Delegate protocols (`RegionsServiceDelegate`, `LocationServiceDelegate`,
  `ObacoServiceDelegate`, `AgencyAlertsDelegate`, `DataMigrationDelegate`,
  `BookmarkDataDelegate`) are `@MainActor` (+ `Sendable` where existentials
  cross tasks). `RegionsService` and `LocationService` are `@MainActor`
  classes; `LocationService` uses `@preconcurrency CLLocationManagerDelegate`.
- A `@MainActor` protocol conformance declared on the class *declaration*
  infers isolation for the whole class; declare it in an extension to isolate
  only the witness (see `AgencyAlertsStore`).
- Diffable data source identifier types (`OBAListViewSection`,
  `AnyOBAListViewItem`, NearbyStops `Section`/`Item`) are `nonisolated` +
  `@unchecked Sendable` — only ever touched on main.
- Subclasses of nonisolated third-party classes (BLTNBoard, FloatingPanel):
  `nonisolated` members/overrides, `MainActor.assumeIsolated` where the body
  builds UI, and explicit unavailable `nonisolated override init(title:)` to
  suppress isolated synthesized initializers.
- `deinit` bodies touching main-actor state use `isolated deinit`.
- XCTest: `OBATestCase` is `@MainActor`; every sync `setUp`/`tearDown`
  override became `async throws` (async overrides may legally change
  isolation; the sync overrides stay nonisolated and can't touch isolated
  state).
- The `lazy var x = { … }()` pattern trips a "default argument cannot be both
  main actor-isolated and @concurrent" diagnostic under approachable
  concurrency; hoist the closure into a method.

Each phase is independently landable and independently revertible (drop the
target back to Swift 5 mode without losing fixes, per Apple's guidance).
