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

## Decisions

Made with the maintainer, 2026-09-22.

| Decision | Choice |
|---|---|
| MVP scope | **Nearby stops and their arrivals, from the watch's own location. No bookmarks, no phone sync, no complications.** Bookmarks need WatchConnectivity, the riskiest code in the design; it should not sit on the critical path of the first launch. |
| Target shape | **The architecture spec's shape, from the start:** `OBAKitWatch` framework, thin `WatchApp` shell, per-app opt-in through `Apps/<App>/watch.yml`. |
| Core host | **No `CoreApplication` on the watch.** A `WatchAppHost` assembles the standalone services the step 3 widget path already proved. Reverses the architecture spec's "configured with surveys, Obaco, and agency alerts disabled". |
| Verification hardware | **Simulator only.** Runtime on a 32-bit watch stays in "Still unknown". |
| Sequencing | Step 4 = this app. Step 5 = sync plus the Bookmarks tab. Step 6 = the widget, unchanged. |

## What steps 1–3 left the watch to stand on

Verified by reading branch `watchos/step-3-stateless-arrivals` (PRs #1446,
#1447, #1448) on 2026-09-22. [code]

- `OBAKitCore` compiles for `generic/platform=watchOS` (`arm64` + `arm64_32`)
  from `OBAKitCore/` plus the sibling iOS-only `OBAKitCoreiOS/`, and CI keeps it
  that way.
- `RESTAPIService.standalone(region:apiKey:appVersion:uuid:dataLoader:)` builds
  an API service without a `CoreApplication`.
  `getStops(coordinate:) -> RESTAPIResponse<[Stop]>` and
  `getArrivalsAndDeparturesForStop(id:minutesBefore:minutesAfter:)` are
  `nonisolated` and portable (`RESTAPIService+Get.swift`).
- `BookmarkArrivalsLoader.arrivals(for:using:)` streams per-stop results and
  accepts a single stop request; `BookmarkArrivalsRequest.matching(_:)` drops
  past departures.
- `UserUUID.value(in:)` gives a process its own client identity over a defaults
  suite.
- `RegionsService` runs without a `CoreApplication`: it needs a
  `LocationService`, a defaults suite, and a bundled regions file, and it
  auto-selects the region containing `locationService.currentLocation`
  (`RegionsService.swift:66`, `updateCurrentRegionFromLocation()`). Its
  `apiService` may be nil, in which case the list never refreshes.
- Portable SwiftUI in core: `RouteBadgeView`, `CountdownView(departure:…)`
  (ticks, stops at zero), `RealtimeGlyph`, `DepartureTimeText`,
  `TickingCountdownText`. `ThemeColors.shared` carries the fixed watch palette.
- `Formatters(locale:calendar:themeColors:)` is portable.

What is missing, and what this step adds to core:

- `LocationManager` has no `requestLocation()` or `desiredAccuracy`.
- `APIServiceConfiguration`'s initializers are internal, so
  `RegionsAPIService` cannot be built outside the module; the watch could never
  refresh its regions list.
- `EnvironmentValues.coreApplication`'s default value constructs a full
  `CoreApplication` from `Bundle.main` with force-unwraps
  (`CoreApplicationKey.swift:10-20`). Watch views must never read it.
- No watch targets, no `watch.yml`, no `--no-watch`, no launch smoke test.

## §1 Targets and project wiring

Follows the OBAWidget convention: a target's shape lives in `<Target>/project.yml`;
each app's file includes it and overrides identity.

| Target | Type | Contents | Depends on |
|---|---|---|---|
| `OBAKitWatch` | framework, watchOS | `WatchAppHost`, environment key, all screens, `Strings/` in 13 locales | OBAKitCore |
| `WatchApp` | application, watchOS | `@main` struct, root view, `Info.plist`, `Assets.xcassets`; shared shell code in `Apps/Shared/WatchClient/` (mirrors `CommonClient`) | OBAKitWatch, OBAKitCore |

`OBAKitWatch` sets `APPLICATION_EXTENSION_API_ONLY: true` so the step 6 widget
can link it. Both targets inherit Swift 6, complete checking, and
MainActor-default isolation from `Apps/Shared/app_shared.yml`, which is not
modified. The `OBAWatchWidget` target is **not** created in this step.

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

### `Info.plist` for `WatchApp`

`WKApplication: true`, `WKRunsIndependentlyOfCompanionApp: true`,
`WKCompanionAppBundleIdentifier` (per app), `NSLocationWhenInUseUsageDescription`
with `InfoPlist.strings` in all 13 locales (an independent watch app shows the
prompt on the watch itself), ATS exceptions mirrored from the iOS app, and the
`OBAKitConfig` dictionary (per app). `WKSupportsLiveActivityLaunchAttributeTypes`
waits for step 0.

### Opt-in: `Apps/OneBusAway/watch.yml`

One file holds every line of watch wiring for an app:

- `include:` of `OBAKitWatch/project.yml` and `WatchApp/project.yml`.
- `WatchApp` overrides: `PRODUCT_BUNDLE_IDENTIFIER:
  org.onebusaway.iphone.watchkitapp`, `DEVELOPMENT_TEAM`,
  `WKCompanionAppBundleIdentifier: org.onebusaway.iphone`, the app-group
  entitlement `group.org.onebusaway.iphone`, `CFBundleDisplayName`, the same
  `OBAKitConfig` block `OBAWidget` carries (`AppGroup`,
  `BundledRegionsFileName`, `RESTServerAPIKey`, `RegionsServerBaseAddress`,
  `RegionsServerAPIPath`), and `Apps/OneBusAway/Resources/regions.json` as a
  resource.
- `targets.App.dependencies: [- target: WatchApp]`. XcodeGen merges included
  arrays additively, so this appends. [doc, built: architecture spec §2]

`Apps/OneBusAway/project.yml` gains:

```yaml
include:
  - path: Apps/OneBusAway/watch.yml
    relativePaths: false
    enable: ${OBA_WATCH}
```

`scripts/generate_project` exports `OBA_WATCH=true` unless given `--no-watch`,
the fast path for iOS-only work (once `App` depends on `WatchApp`, every iOS
build compiles the watch stack's simulator slices). KiedyBus has no `watch.yml`
and generates exactly today's project; a test in the plan asserts its resolved
spec has no watch targets.

**The bundled regions file is the app's, not the widget's.**
`OBAWidget/Resources/regions.json` has already drifted from
`Apps/OneBusAway/Resources/regions.json` (17 regions versus 7, 2026-09-22
[code]); the watch references the app's file so a third copy cannot drift.

### Identity check

Simulator builds accept a non-prefixed watch bundle ID and a wrong
`WKCompanionAppBundleIdentifier`; a mistake surfaces only at device install or
App Store validation. [built, architecture spec §2] `scripts/generate_project`
therefore reads the app's resolved spec after generation and fails when
`WKCompanionAppBundleIdentifier` differs from the `App` bundle ID or the watch
bundle ID is not prefixed by it. It runs only when `OBA_WATCH` is set.

## §2 `WatchAppHost` and data flow

`WatchAppHost` is a `@MainActor @Observable final class` in OBAKitWatch, built
once by the `@main` struct and injected through its own environment key
(`\.watchAppHost`). Nothing in OBAKitWatch reads `\.coreApplication`.

It owns:

| Piece | Built from |
|---|---|
| `UserDefaults` suite | `Bundle.main.appGroup` (the on-watch app-group container, shared with the step 6 widget) |
| `LocationService` | `LocationService(userDefaults:locationManager: CLLocationManager())` |
| `RegionsService` | bundled `regions.json` path, the suite, the location service, and a `RegionsAPIService` from the new `standalone` factory; `automaticallySelectRegion` stays on |
| `RESTAPIService?` | `RESTAPIService.standalone(region:apiKey:appVersion:uuid:)`; `uuid` from `UserUUID.value(in:)` over the suite, so the watch has its own client identity |
| `Formatters` | `Locale.current`, `Calendar.current`, `ThemeColors.shared` |

The host exposes `region: Region?` and `apiService: RESTAPIService?` as
observable state and nothing about wiring. It calls
`regionsService.updateRegionsList()` once at launch.

### Core additions

All portable, all in `OBAKitCore/`, all tested in OBAKitTests:

1. **`RegionsAPIService.standalone(baseURL:apiPath:apiKey:appVersion:uuid:dataLoader:)`**
   — the regions-list counterpart of `RESTAPIService.standalone`. The only
   reason it is needed is that `APIServiceConfiguration.init` is internal.
2. **`LocationManager.requestLocation()` and `desiredAccuracy`** — added to the
   protocol with **no default implementation**, so both test mocks
   (`MockAuthorizedLocationManager`, `LocationServiceMocks`) must implement them
   and cannot silently no-op. `LocationService` gains
   `requestLocation(desiredAccuracy:)`, guarded by authorization like
   `startUpdatingLocation()`, delivering through the existing `locationChanged` /
   `errorReceived` delegate path. (Architecture spec §3, "Watch networking and
   location".)
3. **`StandaloneAPIServiceProvider`** — a `@MainActor` `RegionsServiceDelegate`
   holding `apiService: RESTAPIService?`, rebuilt on `updatedRegion` and
   `updatedRegionsList` and set to nil when there is no region. It is the
   region-to-service rule extracted from `CoreApplication.refreshRESTAPIService`
   minus the survey and Obaco branches. `WatchAppHost` observes it.
4. **`NearbyStopsLoader`** — `func stops(near coordinate: CLLocationCoordinate2D,
   limit: Int = 20, using: RESTAPIService) async throws -> [Stop]`, sorted by
   distance from the coordinate, capped. Thin over `getStops(coordinate:)`; it
   exists so sorting and capping are tested and so the watch never calls the
   service directly.
5. **`StopArrivalsPoller`** — `func arrivals(for stopID: StopID, every: Duration,
   using: RESTAPIService, clock: some Clock) -> AsyncStream<Result<[ArrivalDeparture], Error>>`.
   Emits immediately, then on each tick, until the consumer cancels. Each fetch
   goes through `BookmarkArrivalsLoader` with one stop request and
   `minutesAfter: 60`, and `BookmarkArrivalsRequest.matching(_:)` drops past
   departures. A fetch error is delivered as a `.failure` value, never thrown,
   so the stream survives it (the same convention as `BookmarkArrivalsLoader`);
   the consumer keeps its last good value.

### Watch-side flow

```
scene → .active ─┐
refresh button ──┴→ locationService.requestLocation(hundredMeters)
                         │ locationChanged
                         ▼
               RegionsService selects the containing region
                         │ updatedRegion
                         ▼
               StandaloneAPIServiceProvider rebuilds RESTAPIService
                         │ observed by WatchAppHost
                         ▼
   NearbyStopsModel.load(coordinate)   ──►  NearbyStopsLoader
   StopArrivalsModel.start(stopID)     ──►  StopArrivalsPoller (30 s while .active)
```

The watch takes **one-shot fixes only**, at `kCLLocationAccuracyHundredMeters`,
on foreground entry and on the refresh button. It never starts continuous
updates. The arrivals poll matches the iOS 30-second cadence and is cancelled
when the scene leaves `.active`. Nothing writes to `UserDataStore`; nothing
opens the GRDB stop cache; the launch counter is untouched.

**Timeout.** Core's `URLRequest(timeoutInterval: 10)` stays as is. The
architecture spec's configurable timeout is deferred to step 5 with background
refresh, which is what motivated it; a foreground pull on the simulator cannot
evaluate the Bluetooth-proxied path either way.

## §3 Screens

One `NavigationStack`, no tab bar. Bookmarks get a tab in step 5.

**Nearby (root).** A `List` of up to 20 stops sorted by distance. Row:
`stop.nameWithLocalizedDirectionAbbreviation`, a secondary line of the stop's
route short names joined with ", ", and the distance as a `Measurement<UnitLength>`
formatted for the locale. A toolbar refresh button re-requests location and
refetches. The navigation title is the resolved region's name, so the user can
see which region the watch chose; before a region resolves it is the app name.

**Stop arrivals (pushed on tap).** A `List` of departures for the next 60
minutes, sorted by `arrivalDepartureDate`. Row: `RouteBadgeView` at a small
size, `tripHeadsign`, `CountdownView(departure:isRealTime:color:)` (ticks, stops
at zero), `RealtimeGlyph` for realtime versus scheduled. Footer: "Updated at"
from the last successful fetch, through `Formatters`.

**Strings.** Every watch-only string lives in `OBAKitWatch/Strings/<locale>.lproj`
for all 13 locales; `scripts/extract_strings` scans `OBAKitWatch` too, and
`LocalizationTests` covers the new bundle. `NSLocationWhenInUseUsageDescription`
is localized in `WatchApp`'s `InfoPlist.strings`.

## §4 States and the region rule

Each view holds one `Phase` enum, not a set of optionals, so every state renders
something deliberate:

| Situation | Nearby shows |
|---|---|
| First launch, not yet authorized | The when-in-use prompt, fired from the watch, with an explanation row above it |
| Location denied or restricted | Text explaining that nearby stops need location. watchOS has no Settings deep link, so no button |
| Fix pending | A progress row |
| Fix outside every region | "No transit region here" |
| Region resolved, fetch failed | The error's localized description and a retry button |
| Zero stops returned | "No stops nearby" |

| Situation | Stop arrivals shows |
|---|---|
| Loading | A progress row |
| Empty | "No departures in the next 60 minutes" |
| Failed, no prior data | The error and a retry button |
| Failed after a good fetch | The last good list, with the stale "Updated at" |

**Region rule for this step.** The watch selects a region from its own fix via
`RegionsService`'s containment logic. There is no phone fallback yet: "no fix,
or a fix in no region" is a terminal empty state. Step 5 adds the synced region
as the fallback the architecture spec describes. Custom regions do not exist on
the watch until step 5 either.

## §5 Testing and CI

**Logic in core, views in the framework.** OBAKitTests is iOS-hosted and cannot
import a watchOS framework; an `OBAKitWatchTests` target stays deferred
(architecture spec §5). So every branch lives in OBAKitCore and OBAKitWatch
holds only `WatchAppHost` (assembly), two thin `@Observable` models that map a
loader result to a `Phase`, and views. Each view gets a SwiftUI preview per
phase.

New suites in OBAKitTests:

- `RegionsAPIService.standalone`: builds; the resulting service fetches the
  regions fixture through a mock loader.
- `LocationManager.requestLocation` / `desiredAccuracy`: both mocks implement
  them; `LocationService.requestLocation(desiredAccuracy:)` is refused before
  authorization and forwards after; the delivered location reaches
  `locationChanged`.
- `StandaloneAPIServiceProvider`: rebuilt on `updatedRegion`; rebuilt on
  `updatedRegionsList` when the current region's base URL changed; nil with no
  region.
- `NearbyStopsLoader`: sorted by distance; capped; empty passes through; error
  propagates.
- `StopArrivalsPoller`: emits on start; emits per tick under a test clock; a
  failed tick delivers `.failure` and the next tick delivers `.success` again;
  cancellation stops fetches.
- `LocalizationTests`: the `OBAKitWatch` bundle has all 13 locales with parity
  to `en`.

Project-generation checks are shell steps, not test suites: `scripts/generate_project`
fails on a wrong companion ID or an unprefixed watch bundle ID (§1), and CI
generates the KiedyBus project and asserts, via `xcodegen dump`, that its
resolved spec names no watch target.

**CI**, in the existing `build` job:

- The watch device compile step widens from the `OBAKitCore` scheme to
  `WatchApp`, so every watch target is compiled for `arm64` and `arm64_32`.
- A **launch smoke test** on an unpaired watch simulator: build for the
  simulator, `simctl install`, `simctl launch`, sleep 8 s, then assert
  `kill -0 $pid` **and** that `simctl spawn … launchctl list` shows the bundle
  ID; on failure dump `log show` filtered for "Library not loaded".
  `simctl launch` and XcodeBuildMCP's `build_run_sim` both report success for an
  app dyld kills [built, architecture spec §5], so the delay and the two
  assertions are the test. It runs the OneBusAway configuration only.

**Local verification before the PR opens** (recorded in the PR body):

- A paired-simulator run through XcodeBuildMCP with a simulated Seattle
  location: Nearby populates, a stop pushes its arrivals, the countdown ticks,
  the refresh button refetches. Screenshots of each `Phase`.
- The Release device build (`generic/platform=watchOS`,
  `CODE_SIGNING_ALLOWED=NO`) `.app` size, unthinned, against the architecture
  spec's 25 MB budget. A local archive is not used (it stalls on a keychain ACL
  on this machine).
- `scripts/generate_project --no-watch` yields the pre-step project for
  OneBusAway; `scripts/generate_project KiedyBus` is byte-identical to before.

Not verified in this step: runtime on 32-bit hardware; the three network routes
(phone proxy, Wi-Fi, cellular); the size of the thinned app.

## Sequencing, revised

Each step is one PR that leaves `main` green. Steps 0–3 are unchanged from the
architecture spec (0 independent; 1–3 open as #1446, #1447, #1448).

4. **This spec.** OBAKitWatch, WatchApp, `watch.yml`, `--no-watch`, the
   identity check, the five core additions, nearby stops and arrivals, the
   launch smoke test.
5. The architecture spec's step 4 and the rest of its step 5: `WatchSyncPayload`,
   `WatchBookmark`, `WatchSessionBridge`, the phone-side sender,
   `.bookmarkGroupsDidChange`, the watch receiver, a Bookmarks tab, the
   synced-region fallback, background refresh with its arrivals cache, the
   configurable timeout, and the size measurement of the thinned app.
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
foreground, and continuous updates cost battery on a watch for nothing.

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

- Whether `RegionsService`'s containment check selects a region from a
  hundred-meter one-shot fix reliably on hardware, or whether the first fix
  arrives too coarse and the watch needs a second request.
- The CI wall time of the `WatchApp` device compile and the smoke test.
