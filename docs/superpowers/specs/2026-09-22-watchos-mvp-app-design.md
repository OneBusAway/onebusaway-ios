# watchOS MVP App (step 4)

The first running watch app: an independent OneBusAway companion that shows
nearby stops and their arrivals from the watch's own location, built on the
OBAKitCore that steps 1–3 made portable. It creates the watch targets, the
white-label opt-in, and the CI checks that every later watch step builds on.

This spec is a child of
[`2026-09-20-watchos-architecture-design.md`](2026-09-20-watchos-architecture-design.md)
(the "architecture spec"). It changes that spec's sequencing — the app arrives
before bookmark sync — and one of its design choices — the watch app does not
build a `CoreApplication`. Everything it does not mention is unchanged there.

Revised 2026-09-22 after an adversarial review that read every claim against
the code; the review's must-fixes (location updates, one-shot pruning, region
notification behavior, localization coverage, the release lane, CI ordering)
and should-fixes are folded in below.

## Decisions

Made with the maintainer, 2026-09-22.

| Decision | Choice |
|---|---|
| MVP scope | **Nearby stops and their arrivals, from the watch's own location. No bookmarks, no phone sync, no complications.** Bookmarks need WatchConnectivity, the riskiest code in the design; it should not sit on the critical path of the first launch. |
| Target shape | **The architecture spec's shape, from the start:** `OBAKitWatch` framework, thin `WatchApp` shell, per-app opt-in through `Apps/<App>/watch.yml`. |
| Core host | **No `CoreApplication` on the watch.** A `WatchAppHost` assembles the standalone services the step 3 widget path already proved. Reverses the architecture spec's "configured with surveys, Obaco, and agency alerts disabled". |
| Verification hardware | **Simulator only.** Runtime on a 32-bit watch stays in "Still unknown". |
| Release lane | **The TestFlight lane passes `--no-watch`** until a hardware pass and App Store Connect setup exist. The watch app never ships by accident. |
| Sequencing | Step 4 = this app. Step 5 = sync plus the Bookmarks tab. Step 6 = the widget, unchanged. |

## What steps 1–3 left the watch to stand on

Verified by reading branch `watchos/step-3-stateless-arrivals` (PRs #1446,
#1447, #1448) on 2026-09-22. [code]

- `OBAKitCore` compiles for `generic/platform=watchOS` (`arm64` + `arm64_32`)
  from `OBAKitCore/` plus the sibling iOS-only `OBAKitCoreiOS/`, and CI keeps it
  that way.
- `RESTAPIService.standalone(region:apiKey:appVersion:uuid:dataLoader:)`
  (`BookmarkArrivalsLoader.swift:129`) builds an API service without a
  `CoreApplication`. `getStops(coordinate:) -> RESTAPIResponse<[Stop]>`
  (`RESTAPIService+Get.swift:77`; no radius parameter, the server default
  applies) and `getArrivalsAndDeparturesForStop(id:minutesBefore:minutesAfter:)`
  (`:170`) are `nonisolated` and portable.
- `BookmarkArrivalsLoader.arrivals(for:using:)` streams per-stop results and
  accepts a single stop request; `BookmarkArrivalsRequest.matching(_:)` drops
  past departures and sorts by date.
- `UserUUID.value(in:)` gives a process its own client identity over a defaults
  suite.
- `RegionsService` runs without a `CoreApplication`: it needs a
  `LocationService`, a defaults suite, and a bundled regions file, and it
  auto-selects the region containing `locationService.currentLocation`
  (`RegionsService.swift:66`, `updateCurrentRegionFromLocation()` `:543`, driven
  by `locationChanged` `:533`). Its `apiService` may be nil, in which case the
  list never refreshes. `bundledRegions(path:)` is `try!` (`:466-472`): a
  mis-wired `regions.json` resource crashes at launch, which the smoke test in
  §5 is what catches.
- Portable SwiftUI in core, all `public`: `RouteBadgeView`,
  `CountdownView(departure:isRealTime:color:emphasized:)` (ticks, stops at zero,
  and already embeds `RealtimeGlyph`), `DepartureTimeText`,
  `TickingCountdownText`. OBAKit has same-named `internal` types under
  `OBAKit/Stops/StopPage/Shared/`; the watch uses OBAKitCore's.
  `ThemeColors.shared` carries the fixed watch palette and resolves the brand
  color from the **main bundle only** on watchOS (`ThemeColors.swift:188-194`),
  falling back to a hard-coded green.
- `Formatters(locale:calendar:themeColors:)` is portable; `timeFormatter` gives
  a locale-short time.
- `ResolvedRegionPersister(regionsService:store:)` writes the resolved `Region`
  to a suite on the four triggers; `ResolvedRegionStore` reads it. The step 6
  watch widget will read it on the watch, so the watch app writes it now.

What is missing, and what this step adds to core:

- `LocationManager` has no `requestLocation()` or `desiredAccuracy`, and
  `LocationService` **starts continuous location and heading updates the
  moment it is authorized** (`applyAuthorizationState`, `LocationService.swift:204-218`,
  reached from the authorization callback Core Location fires when the delegate
  is assigned in `init`). It also **prunes a fix** whose accuracy is worse than
  the previous one within a 60-second window (`:518-526`) with no delegate
  call. Both must change for a one-shot watch flow.
- `APIServiceConfiguration`'s initializers are internal, so
  `RegionsAPIService` cannot be built outside the module; the watch could never
  refresh its regions list.
- `RegionsService.currentRegion`'s setter returns early on an unchanged
  identifier (`:220`) and ignores nil (`:217`), so `updatedRegion` is **not
  delivered on a warm launch** and nothing ever clears the stored identifier. A
  fix outside every region fires `regionsServiceUnableToSelectRegion` (`:553-557`)
  while `currentRegion` keeps the previous launch's region. The host and the
  Nearby rule are written against this behavior, below.
- `EnvironmentValues.coreApplication`'s default value constructs a full
  `CoreApplication` from `Bundle.main` with force-unwraps
  (`CoreApplicationKey.swift:10-20`). Watch code never reads it.
- `OBALoc` is `internal` per module (`CoreLocalization.swift:14`); OBAKitWatch
  needs its own over a class in the watch module.
- `scripts/generate_project` takes no flags (`app = ARGV[0]`);
  `scripts/extract_strings` is two hard-coded blocks; `scripts/version` stamps
  a hard-coded plist list; `fastlane/Fastfile` generates with no flag.
- No watch targets, no `watch.yml`, no launch smoke test, no watch simulator in
  CI.

## §1 Targets and project wiring

Follows the OBAWidget convention: a target's shape lives in `<Target>/project.yml`;
each app's file includes it and overrides identity.

| Target | Type | Contents | Depends on |
|---|---|---|---|
| `OBAKitWatch` | framework, watchOS | `WatchAppHost`, `WatchRootView` (owns navigation and the scene-phase driver), the two models, all screens, `WatchLocalization.swift`, `Strings/` in 13 locales | OBAKitCore |
| `WatchApp` | application, watchOS | `WatchApp.swift` (the `@main` struct: builds one host, shows `WatchRootView`), `Info.plist`, `<locale>.lproj/InfoPlist.strings` ×13 | OBAKitWatch, OBAKitCore |

Both directories are white-label: no app name, no brand asset, no bundle ID in
them. There is no `Apps/Shared/WatchClient/`; the `@main` struct is already
app-neutral and lives in `WatchApp/`. Per-app content comes in through
`watch.yml` (below).

`OBAKitWatch` sets `APPLICATION_EXTENSION_API_ONLY: true` so the step 6 widget
can link it, and declares `scheme:` so `xcodebuild -scheme OBAKitWatch` exists
on a fresh checkout (XcodeGen writes shared schemes only for targets that
declare one; OBAWidget has none). `WatchApp` declares `scheme:` for the same
reason: CI builds `-scheme WatchApp`. Both targets inherit Swift 6, complete
checking, and MainActor-default isolation from `Apps/Shared/app_shared.yml`,
which is not modified. The `OBAWatchWidget` target is **not** created in this
step.

### Settings the architecture spec proved necessary

- `WatchApp`: `LD_RUNPATH_SEARCH_PATHS: "$(inherited) @executable_path/Frameworks"`.
  XcodeGen's watchOS application preset omits it; without it the app installs
  and dies in dyld with `Library not loaded: @rpath/OBAKitWatch.framework`.
  [built, architecture spec §2]
- Single-platform watch targets use `deploymentTarget: "11.0"` normally; the
  `WATCHOS_DEPLOYMENT_TARGET` build-setting workaround is only for the
  `supportedDestinations` core target, which already has it.
- No `package:` dependencies on either watch target. GRDB and SwiftProtobuf
  reach the watch once, dynamically, inside OBAKitCore.
- Both targets exclude their own `project.yml` from sources, as OBAKitCore does.

### `Info.plist` for `WatchApp` (in `WatchApp/Info.plist`, white-label)

`WKApplication: true`, `WKRunsIndependentlyOfCompanionApp: true`,
`CFBundleShortVersionString: $(MARKETING_VERSION)` (`Bundle.appVersion`
force-unwraps it), `CFBundleVersion` (stamped by `scripts/version`, which gains
`WatchApp` and `OBAKitWatch` in its plist list), `CFBundleLocalizations` for the
13 locales (the App inherits its list from `app_shared.yml`; a watch target
does not), and `NSLocationWhenInUseUsageDescription` with the same app-neutral
English body the iOS app uses. Its translations live in
`WatchApp/<locale>.lproj/InfoPlist.strings`, one key each, copied from
`Apps/OneBusAway/<locale>.lproj/InfoPlist.strings` — the body names no app, so
every white-label app gets them. `WKSupportsLiveActivityLaunchAttributeTypes`
waits for step 0. `OBAKitWatch/Info.plist` mirrors OBAKit's (version only).
Both files are generated by XcodeGen from each target's `info.properties` and
gitignored like the other targets' plists; `scripts/version` stamps the
generated copies.

Per-app keys (`WKCompanionAppBundleIdentifier`, `CFBundleDisplayName`,
`OBAKitConfig`, ATS exceptions) come from `watch.yml`.

### Opt-in: `Apps/OneBusAway/watch.yml`

One file holds every line of watch wiring for an app:

- `include:` of `OBAKitWatch/project.yml` and `WatchApp/project.yml`.
- `WatchApp` overrides: `PRODUCT_BUNDLE_IDENTIFIER:
  org.onebusaway.iphone.watchkitapp`, `DEVELOPMENT_TEAM`,
  `WKCompanionAppBundleIdentifier: org.onebusaway.iphone`, the app-group
  entitlement `group.org.onebusaway.iphone`, `CFBundleDisplayName: OneBusAway`,
  ATS exceptions mirrored from the iOS app, the same `OBAKitConfig` block
  `OBAWidget` carries (`AppGroup`, `BundledRegionsFileName`, `RESTServerAPIKey`,
  `RegionsServerBaseAddress`, `RegionsServerAPIPath`), and two extra sources:
  `Apps/OneBusAway/Resources/regions.json` and
  `Apps/OneBusAway/Assets.xcassets`.
- `targets.App.dependencies: [- target: WatchApp]`. XcodeGen merges included
  arrays additively, so this appends. [doc, built: architecture spec §2, and
  re-reproduced by the review with `relativePaths: false`]

The watch app compiles the app's existing `Apps/OneBusAway/Assets.xcassets`
rather than a separate catalog. Its new `WatchAppIcon.appiconset` (a single
1024×1024 watchOS icon) is selected by
`ASSETCATALOG_COMPILER_APPICON_NAME: WatchAppIcon` on the `WatchApp` target, so
the brand color (`Colors/brand.colorset`) is found once, in the watch's main
bundle, which is the only place `ThemeColors` looks on watchOS, and the iOS app
compiles no duplicate icon or color.

`Apps/OneBusAway/project.yml`'s **existing** `include:` list (there must be
exactly one; `generate_project` splices `local.yml` by matching it) gains:

```yaml
  - path: Apps/OneBusAway/watch.yml
    relativePaths: false
    enable: ${OBA_WATCH}
```

### `scripts/generate_project`

Gains argument parsing: the app name stays positional (default `OneBusAway`);
`--no-watch` is the one flag. It sets `ENV["OBA_WATCH"] = "true"` before
`system("xcodegen")` unless `--no-watch` was passed; an unset variable disables
the include. The four existing callers (`scripts/setup`, `scripts/docs`,
`fastlane/Fastfile`, `tests.yml`) keep working unchanged, except the Fastfile,
which now passes `--no-watch` (Decisions).

Consequences, documented in `CLAUDE.md` and README: with the watch enabled,
building the iOS `App` scheme also builds the watch stack's simulator slices,
so a machine without the watchOS platform installed must use `--no-watch`.

`local.yml` handling changes so a personal team can still build the embedding
`App`: `local.yml` is spliced as the **last** include (today it is first, so a
later `watch.yml` would win), and `replace_development_team` skips targets that
are not in the root `project.yml` instead of aborting. `Apps/OneBusAway/local.yml.example`
gains a `WatchApp` block.

KiedyBus has no `watch.yml` and generates exactly today's project; §5 asserts it.

**The bundled regions file is the app's, not the widget's.**
`OBAWidget/Resources/regions.json` has already drifted from
`Apps/OneBusAway/Resources/regions.json` (17 regions versus 7, 2026-09-22
[code]); the watch references the app's file so a third copy cannot drift.
The first watch launch sees the other regions only after
`updateRegionsList()` succeeds, which is once-per-day gated.

### Identity check

Simulator builds accept a non-prefixed watch bundle ID and a wrong
`WKCompanionAppBundleIdentifier`; a mistake surfaces only at device install or
App Store validation. [built, architecture spec §2] `scripts/generate_project`
therefore runs `xcodegen dump --type json` on the resolved root spec after
generation, when `OBA_WATCH` is set, and fails when
`WKCompanionAppBundleIdentifier` differs from the `App` bundle ID or the watch
bundle ID is not `<App bundle ID>.` followed by a suffix.

## §2 `WatchAppHost` and data flow

`WatchAppHost` is a `@MainActor @Observable final class` in OBAKitWatch, built
once by the `@main` struct and passed down with `.environment(host)`; screens
that need it read `@Environment(WatchAppHost.self)`. There is no environment
key with a default value, which is the `CoreApplicationKey` trap. Screens take
a model, not the host, so previews construct a model in any `Phase` without a
`CLLocationManager` or network.

It owns:

| Piece | Built from |
|---|---|
| `UserDefaults` suite | `Bundle.main.appGroup` (the on-watch app-group container, shared with the step 6 widget) |
| `LocationService` | `LocationService(userDefaults:locationManager: CLLocationManager(), startsUpdatesOnAuthorization: false)` |
| `RegionsService` | bundled `regions.json` path, the suite, the location service, and a `RegionsAPIService` from the new `standalone` factory; `automaticallySelectRegion` stays on (its registered default) |
| `StandaloneAPIServiceProvider` | see Core additions; retained by the host (RegionsService holds delegates weakly) |
| `ResolvedRegionPersister` | `ResolvedRegionPersister(regionsService:store:)` over the suite, retained by the host |
| `Formatters` | `Locale.current`, `Calendar.current`, `ThemeColors.shared` |

The host is an `NSObject` `LocationServiceDelegate` implementing
`authorizationStatusChanged`, republished as observable
`authorizationStatus: CLAuthorizationStatus`. It exposes the provider's
service as a computed passthrough, `apiService: RESTAPIService?`, and exposes
`regionsService` for the Nearby rule. It calls
`regionsService.updateRegionsList()` once at launch.

### Core additions

All portable, all in `OBAKitCore/`, all tested in OBAKitTests:

1. **`RegionsAPIService.standalone(baseURL:apiKey:appVersion:uuid:dataLoader:)`**
   — the regions-list counterpart of `RESTAPIService.standalone`, mirroring
   `CoreApplication.swift:322-336` with `regionIdentifier: nil`. `apiPath` is a
   per-call argument of `getRegions(apiPath:)` and stays out of the factory. A
   factory rather than a public `APIServiceConfiguration.init`, to match the
   existing REST factory and keep the configuration's invariants inside the
   module.
2. **One-shot location.** `LocationManager` gains `func requestLocation()` and
   `var desiredAccuracy: CLLocationAccuracy { get set }` with **no default
   implementation**, so `LocationManagerMock` (`LocationServiceMocks.swift:15`)
   and `MockAuthorizedLocationManager` must implement them and cannot silently
   no-op. `CLLocationManager` already has both. `LocationService` gains:
   - `init(userDefaults:locationManager:startsUpdatesOnAuthorization: Bool = true)`.
     With `false`, `applyAuthorizationState` never calls `startUpdates()`; it
     still calls `stopUpdates()` on revocation. The watch passes `false`. iOS
     callers are unchanged by the default.
   - `func requestLocation(desiredAccuracy: CLLocationAccuracy) async throws -> CLLocation`.
     Throws `LocationServiceError.notAuthorized` unless `isLocationUseAuthorized`.
     Otherwise sets the manager's accuracy, calls `requestLocation()`, and
     suspends until the next `didUpdateLocations` (resolves with the newest
     location, **which also becomes `currentLocation` without the accuracy
     prune**, so `locationChanged` reaches `RegionsService`) or
     `didFailWithError` (throws the error). Multiple concurrent callers all
     resolve on the same callback. The prune stays for continuous updates.
3. **`StandaloneAPIServiceProvider`** — `@MainActor final class: NSObject,
   RegionsServiceDelegate` (the delegate protocol is `@objc`). Holds
   `private(set) var apiService: RESTAPIService?`.
   Takes `apiKey`, `appVersion`, `uuid`, and the `RegionsService`; **seeds from
   `regionsService.currentRegion` at init** (the `ResolvedRegionPersister`
   precedent) and rebuilds on `updatedRegion` and `updatedRegionsList`, setting
   nil when `currentRegion` is nil. No `@Observable` in core; the host exposes
   the provider's service as a computed passthrough.
4. **`NearbyStopsLoader`** — `func stops(near coordinate: CLLocationCoordinate2D,
   limit: Int = 20, using: RESTAPIService) async throws -> [Stop]`, sorted by
   distance from the coordinate, capped. Thin over `getStops(coordinate:)`; it
   exists so sorting and capping are tested and so the watch never calls the
   service directly.
5. **`StopArrivalsPoller`** — `func arrivals(for stopID: StopID, every: Duration,
   using: RESTAPIService, clock: some Clock<Duration>) -> AsyncStream<Result<[ArrivalDeparture], Error>>`.
   Emits immediately, then after each `clock.sleep(for:)`, until the consumer
   cancels. Each fetch goes through `BookmarkArrivalsLoader` with one stop
   request and `minutesAfter: 60`, and `BookmarkArrivalsRequest.matching(_:)`
   drops past departures. A fetch error is delivered as a `.failure` value,
   never thrown, so the stream survives it (the same convention as
   `BookmarkArrivalsLoader`); the consumer keeps its last good value. Tests use
   a hand-written `TestClock` in OBAKitTests (manual advance); no package.

### Watch-side flow

```
scene → .active ─┐
refresh button ──┴→ NearbyStopsModel.refresh()
      │ authorization .notDetermined → requestInUseAuthorization(); phase .awaitingAuthorization
      │   (host's authorizationStatusChanged → WatchRootView calls refresh() again)
      │ denied/restricted → phase .locationDenied
      ▼
   try await locationService.requestLocation(desiredAccuracy: hundredMeters)
      │ error → phase .failed(error)
      │ fix → currentLocation set → RegionsService.locationChanged → currentRegion
      ▼
   regionsService.physicallyLocatedRegion == nil → phase .noRegion   (never fetches)
      │ else, host.apiService (rebuilt by the provider on updatedRegion)
      ▼
   NearbyStopsLoader.stops(near:)  → phase .loaded([Stop]) / .empty / .failed

   tap a stop → StopArrivalsModel.start(stopID)
      → StopArrivalsPoller (30 s, ContinuousClock) while the scene is .active
      → cancelled when the scene leaves .active
```

**The Nearby "no region" rule keys off `physicallyLocatedRegion`, not
`currentRegion`**, because `currentRegion` keeps the previous launch's region
when a fix lands outside every region. The watch takes **one-shot fixes only**,
at `kCLLocationAccuracyHundredMeters`, on foreground entry and on the refresh
button. It never starts continuous updates or heading. The arrivals poll
matches the iOS 30-second cadence. Nothing writes to `UserDataStore`; nothing
opens the GRDB stop cache; the launch counter is untouched.

**Timeout.** Core's `URLRequest(timeoutInterval: 10)` stays as is. The
architecture spec's configurable timeout is deferred to step 5 with background
refresh, which is what motivated it.

## §3 Screens

One `NavigationStack` in `WatchRootView`, no tab bar. Bookmarks get a tab in
step 5. `WatchRootView` owns the `scenePhase` observer and the models.

**Nearby (root).** A `List` of up to 20 stops sorted by distance. Row:
`stop.nameWithLocalizedDirectionAbbreviation`, a secondary line of the stop's
route short names joined with ", ", and the distance as a `Measurement<UnitLength>`
formatted for the locale. A toolbar refresh button re-requests location and
refetches (`.refreshable` has no gesture on watchOS). The navigation title is
`physicallyLocatedRegion?.name` once a region resolves; before that it is
"Nearby".

**Stop arrivals (pushed on tap).** A `List` of departures for the next 60
minutes, sorted by `arrivalDepartureDate`. Row: OBAKitCore's `RouteBadgeView`
at size 32, `tripHeadsign`, and OBAKitCore's
`CountdownView(departure:isRealTime:color:emphasized: false)`, which already
carries the realtime glyph. Footer: "Updated at" from the last successful fetch,
through `Formatters.timeFormatter`.

**Strings.** Every watch-only string goes through `OBALoc` defined in
`OBAKitWatch/WatchLocalization.swift` over `Bundle(for:)` a class in the watch
module, and lives in `OBAKitWatch/Strings/<locale>.lproj/Localizable.strings`
for all 13 locales; `scripts/extract_strings` gains a third block for
`OBAKitWatch`. `NSLocationWhenInUseUsageDescription` is localized in
`WatchApp/<locale>.lproj/InfoPlist.strings`.

## §4 States and the region rule

Each model holds one `Phase` enum, not a set of optionals, so every state
renders something deliberate:

| `NearbyStopsModel.Phase` | Nearby shows |
|---|---|
| `.awaitingAuthorization` | The when-in-use prompt, fired from the watch, with an explanation row above it |
| `.locationDenied` | Text explaining that nearby stops need location. watchOS has no Settings deep link, so no button |
| `.locating` | A progress row |
| `.noRegion` | "No transit region here" |
| `.failed(String)` | The error's localized description and a retry button |
| `.empty` | "No stops nearby" |
| `.loaded([Stop])` | The list |

| `StopArrivalsModel.Phase` | Stop arrivals shows |
|---|---|
| `.loading` | A progress row |
| `.empty(updatedAt:)` | "No departures in the next 60 minutes" |
| `.failed(String)` (no prior data) | The error and a retry button |
| `.loaded([ArrivalDeparture], updatedAt:, stale: Bool)` | The list; `stale` after a failed poll keeps the last good list with its old "Updated at" |

**Region rule for this step.** After each fix, `.noRegion` iff
`regionsService.physicallyLocatedRegion == nil`. `currentRegion` follows the
fix through `RegionsService`'s existing `locationChanged` path, so
`host.apiService` is rebuilt for the new region before the fetch. There is no
phone fallback yet: "no fix, or a fix in no region" is a terminal empty state.
Step 5 adds the synced region as the fallback the architecture spec describes.
Custom regions do not exist on the watch until step 5 either.

## §5 Testing and CI

**Logic in core, views in the framework.** OBAKitTests is iOS-hosted and cannot
import a watchOS framework; an `OBAKitWatchTests` target stays deferred
(architecture spec §5). So every branch lives in OBAKitCore and OBAKitWatch
holds only `WatchAppHost` (assembly), two thin `@Observable` models that map a
loader result to a `Phase`, and views. Each view gets a SwiftUI preview per
phase, built from a model in that phase.

New suites in OBAKitTests:

- `RegionsAPIService.standalone`: builds; the resulting service fetches the
  regions fixture through a mock loader.
- `LocationService` one-shot: both mocks implement `requestLocation` /
  `desiredAccuracy`; `requestLocation(desiredAccuracy:)` throws before
  authorization and resolves after; a worse-accuracy fix inside the prune
  window still resolves and still reaches `locationChanged`; a manager error
  throws; with `startsUpdatesOnAuthorization: false` a grant starts neither
  location nor heading updates, and revocation still stops them.
- `StandaloneAPIServiceProvider`: seeded from `currentRegion` at init; rebuilt
  on `updatedRegion`; rebuilt on `updatedRegionsList` when the current
  region's base URL changed; nil with no region.
- `NearbyStopsLoader`: sorted by distance; capped; empty passes through; error
  propagates.
- `StopArrivalsPoller`: emits on start; emits per tick under `TestClock`; a
  failed tick delivers `.failure` and the next tick delivers `.success` again;
  cancellation stops fetches.
- `WatchLocalizationTests`: a **source-tree** suite. The iOS-hosted test cannot
  load a watchOS bundle, so it locates `OBAKitWatch/Strings/` relative to
  `#filePath`, parses each `Localizable.strings` with `NSDictionary(contentsOf:)`,
  and asserts key parity and format-specifier parity with `en` for all 13
  locales, plus that `WatchApp/<locale>.lproj/InfoPlist.strings` exists for each.

Project-generation checks are shell steps, not test suites: `scripts/generate_project`
fails on a wrong companion ID or an unprefixed watch bundle ID (§1), and CI
generates the KiedyBus project and asserts, via `xcodegen dump`, that its
resolved spec names no watch target.

**CI**, in the existing `build` job, in this order:

1. The "Download watchOS platform" guard **moves ahead of `Build OneBusAway`**,
   because the iOS build now compiles the watch stack.
2. `Build OneBusAway` and the unit tests, unchanged.
3. The watch device compile step widens from the `OBAKitCore` scheme to
   `WatchApp`, so every watch target is compiled for `arm64` and `arm64_32`.
4. A **launch smoke test** on an unpaired watch simulator, resolved by a new
   `scripts/resolve_watch_simulator_udid` (first Apple Watch on the newest
   watchOS runtime, created from a dynamically listed device type if none
   exists, mirroring `scripts/resolve_simulator_udid`): build `WatchApp` for
   the simulator, `simctl install`, `simctl launch`, sleep 8 s, then assert
   `kill -0 $pid` **and** that `simctl spawn … launchctl list` shows the
   bundle ID; on failure dump `log show` filtered for "Library not loaded".
   `simctl launch` and XcodeBuildMCP's `build_run_sim` both report success for
   an app dyld kills [built, architecture spec §5]. The script lives in
   `scripts/watch_smoke_test` so it runs locally too.
5. `scripts/generate_project KiedyBus` followed by the no-watch-target
   assertion, last, because generation replaces the root `project.yml` and
   `OBAKit.xcodeproj`.

`.swiftlint.yml` `included:` gains `OBAKitWatch` and `WatchApp`, so
`hardcoded_app_name` runs on the new white-label code.

**Local verification before the PR opens** (recorded in the PR body):

- A watch-simulator run through XcodeBuildMCP with `simctl location set` to
  Seattle: Nearby populates, a stop pushes its arrivals, the countdown ticks,
  the refresh button refetches. Screenshots of each `Phase`.
- The Release device build (`generic/platform=watchOS`,
  `CODE_SIGNING_ALLOWED=NO`) `.app` size, unthinned, against the architecture
  spec's 25 MB budget. A local archive is not used (it stalls on a keychain ACL
  on this machine).
- `scripts/generate_project --no-watch` yields a project whose `pbxproj` has
  no watch targets; `scripts/generate_project KiedyBus` yields a `pbxproj`
  identical to the one generated from `main` (the `Info.plist` version stamp
  is excluded from the comparison).

Not verified in this step: runtime on 32-bit hardware; the three network routes
(phone proxy, Wi-Fi, cellular); the size of the thinned app; App Store Connect
identifiers and profiles for the watch bundle ID.

## Sequencing, revised

Each step is one PR that leaves `main` green. Steps 0–3 are unchanged from the
architecture spec (0 independent; 1–3 open as #1446, #1447, #1448).

4. **This spec.** OBAKitWatch, WatchApp, `watch.yml`, `--no-watch`, the
   identity check, the five core additions, nearby stops and arrivals, the
   launch smoke test, the release lane guard.
5. The architecture spec's step 4 and the rest of its step 5: `WatchSyncPayload`,
   `WatchBookmark`, `WatchSessionBridge`, the phone-side sender,
   `.bookmarkGroupsDidChange`, the watch receiver, a Bookmarks tab, the
   synced-region fallback, background refresh with its arrivals cache, the
   configurable timeout, App Store Connect setup and removing `--no-watch`
   from the release lane after a hardware pass, and the size measurement of
   the thinned app.
6. OBAWatchWidget, unchanged.

## Alternatives considered

**`CoreApplication` on the watch with `CoreAppConfig` switches** (the
architecture spec's text). Regions refresh, region time-zone formatters, and
the `coreApplication` environment key would work unchanged. Rejected for this
step: `CoreApplication.init` starts a regions fetch, builds Obaco and survey
services, opens and purges the GRDB stop cache, and bumps the launch counter
[code], and every switch to stop one of those is a change to iOS orchestration
and its tests on the critical path of the first watch launch. The switches can
be added later if a watch feature needs something only `CoreApplication`
provides.

**Refactor `CoreApplication` into a shared services base.** The cleanest end
state; deferred until the watch host shows which pieces both platforms share.

**Single `WatchApp` target for OneBusAway only, views inside it.** Smallest
project diff, no framework embedding. Rejected: the white-label split would
later move every view, and the framework's one real cost (`LD_RUNPATH`) is
already characterized.

**Continuous location updates instead of one-shot fixes.** Already supported by
`LocationManager`, so no core change. Rejected: a nearby list needs one fix per
foreground, and continuous updates cost battery on a watch for nothing. The
async `requestLocation` was chosen over a delegate-observed one-shot because
the accuracy prune could otherwise swallow the fix with no signal.

**Delegate-observed one-shot with `successiveLocationComparisonWindow = 0`.**
Works, but leaves the model subscribing to a delegate for a request it made;
the async form is what the caller wants and is testable with a mock that
delivers on the callback.

**Bookmarks first, via sync.** Matches the complication content model, but puts
the `WCSessionDelegate` — which compiles clean and traps at runtime — ahead of
any proof that the watch targets build, embed, launch, and reach the network.

## Still unknown

Inherited from the architecture spec and untouched here: runtime on a 32-bit
watch; the real-device `updateApplicationContext` ceiling; WidgetKit's handling
of dense timelines; `RelevantContext.location` without `NSWidgetWantsLocation`;
bundle-ID prefix enforcement at install; OBAKitCore's thinned size and
cold-launch cost.

New to this step:

- Whether a hundred-meter one-shot fix arrives fast enough on hardware, or
  whether Core Location's own `requestLocation` timeout (about ten seconds)
  fires indoors and the user needs a second tap.
- The CI wall time of the `WatchApp` device compile and the smoke test.
- Whether `xcodegen`'s single-size watchOS app icon needs the `.appiconset`
  JSON in a specific form; verified only by the simulator build, since no
  device install happens in this step.
