# watchOS Architecture

We want a watchOS app for OneBusAway that reuses OBAKitCore rather than
reimplementing it. OBAKitCore does not build for watchOS today, but it is far
closer than its import list suggests: the services half is nearly portable and
the breakage is concentrated in UIKit view code the watch does not need.

This spec covers the architectural changes that make OBAKitCore a two-platform
module, and the target structure, data flow, and complications design that a
watch app builds on top of it.

## Decisions

Made with the maintainer during brainstorming, 2026-09-19/20:

| Decision | Choice |
|---|---|
| Relationship to the iPhone app | **Independent companion.** Ships with the iOS app, runs without the phone nearby. |
| v1 scope | Bookmarks + arrivals, nearby stops, complications / Smart Stack. **Map deferred.** |
| White-label | **Yes, from the start.** Watch UI in a framework; apps opt in. |
| Core strategy | **One OBAKitCore module, two destinations,** iOS-only files fenced off. |
| Bookmark sync | **One-way, phone → watch** in v1. No bookmark editing on the watch. |
| Complication content | The top favorited bookmark. Per-complication picker deferred. |
| First implementation plan | Steps 1–3 of [Sequencing](#sequencing) (core portability). Steps 4–6 are follow-on plans. |

## Where OBAKitCore stands today

Measured 2026-09-19/20 by compiling `OBAKitCore/` for
`generic/platform=watchOS Simulator` from a throwaway XcodeGen project outside
the repo (watchOS 27.0 SDK, XcodeGen 2.46.0, Swift 6 mode, `nonisolated` default
isolation — the target's real settings). The repo was not modified.

- **GRDB 7.11 and SwiftProtobuf 1.38.1 both build for watchOS.** GRDB documents
  watchOS 7+ support; SwiftProtobuf was confirmed by the build.
- **ActivityKit is iOS/iPadOS only** (Apple docs: `ActivityAttributes` is
  "iOS 16.1+, iPadOS 16.1+"). `import ActivityKit` fails watchOS dependency
  scanning outright, before any type-checking, so the six files that import it
  must be excluded from the watchOS build rather than merely guarded at use
  sites.
- With those six files excluded, all 149 remaining compile steps ran and
  **20 files had errors**; 206 of ~245 errors were `'X' is unavailable in
  watchOS`.
  - **14 are UIKit view code** the watch does not need:
    `Extensions/UIKitExtensions`, `Extensions/AutoLayoutExtensions`,
    `Collections/EmptyDataSetView`, `Collections/ActivityIndicatedButton`,
    `Collections/ListKitExtensions`, `Theme/Theme`, `UI/DepartureTimeBadge`,
    `UI/TripLiveActivityCardView`, `UI/TripActivityPresenter`,
    `UI/ProminentButton`, `UI/PaddingLabel`, `UI/ArrivalDepartureDrivenUI`,
    `Utilities/UIViewPreview`, `Utilities/ImageBadgeRenderer`.
  - **6 are in the services layer** the watch does need, and each is a small,
    specific seam (see [Seam fixes](#seam-fixes)).
- The portable remainder (~120 files) includes the SwiftUI views the watch UI
  wants: `RouteBadgeView`, `CountdownView`, `DepartureTimeDisplay`,
  `RealtimeGlyph`.
- `UIColor` is available on watchOS 2.0+ (Apple docs), so `Route.swift`'s
  `UIColor` properties — the only UIKit use in the model layer — are fine.

**This is one compile pass.** Fixing these errors may reveal a second layer that
the first pass masked. The first implementation plan budgets for that.

## §1 Making OBAKitCore build for watchOS

### Layout

One module, two directories, both compiled into the `OBAKitCore` target:

```
OBAKitCore/        syncedFolder, iOS + watchOS     portable; ~120 files, unchanged
OBAKitCoreiOS/     group, destinationFilters:[iOS]  same module, iOS-only
  ├─ UIKit/          the 14 UIView-based files
  ├─ LiveActivities/ moved wholesale, plus TripAttributes.swift,
  │                  TripActivityPresenter.swift, TripLiveActivityCardView.swift
  └─ Location/       LocationService+ProximityAlerts.swift
```

`OBAKitCore/project.yml` changes `platform: iOS` to
`supportedDestinations: [iOS, watchOS]` and adds the second source entry.

Because both directories are the same module, **no `import` statement changes
anywhere** — 567 files import OBAKitCore today (318 in OBAKit, 239 in
OBAKitTests, 8 in OBAWidget, 2 in Apps).

### Why a sibling directory, and why `group`

Verified 2026-09-20 with XcodeGen 2.46.0 in a throwaway project:

| Layout | Result |
|---|---|
| `iOS/` nested in the synced folder, `inferDestinationFiltersByPath: true` | **Filter silently ignored.** XcodeGen exits 0, emits no `platformFilter`, and the watchOS build compiles the iOS file and fails. |
| Nested, explicit `destinationFilters: [iOS]` on a synced source | Same silent no-op. |
| Nested, `type: group` + `destinationFilters` | watchOS builds, but **iOS breaks**: the file reference is a dangling `TEMP_…` ID resolved against the project root. |
| **Sibling directory, `type: group` + `destinationFilters: [iOS]`** | **Both platforms build.** One `platformFilters = (ios, )` entry, zero dangling refs; the symbol is present in the iOS binary and absent from the watchOS one. |

So destination filters do not work on `syncedFolder` sources, and a classic
group cannot nest under a synced root. The sibling layout is the one that works.
Cost: files under `OBAKitCoreiOS/` need `scripts/generate_project` to be picked
up, which the workflow already requires before building.

This was proven on a one-file toy project, not at OBAKitCore's scale.

### Seam fixes

1. **Geofencing.** `LocationManager` (`LocationManagerProtocol.swift`) requires
   `startMonitoring(for:)`, `stopMonitoring(for:)`, `monitoredRegions`, and
   `maximumRegionMonitoringDistance`, none of which exist on watchOS's
   `CLLocationManager`. Move those four requirements to a
   `RegionMonitoringLocationManager` refinement in the iOS tree. Move
   `LocationService`'s proximity-alert methods and its `didEnterRegion` /
   `monitoringDidFailFor` delegate callbacks into
   `LocationService+ProximityAlerts.swift` in the iOS tree.
2. **Live Activities.** `CoreApplication.liveActivityRegistry` and
   `.liveActivityTracker` are stored lazy properties, so they cannot move to an
   extension. Guard them with `#if canImport(ActivityKit)`. Apart from a
   possible color conditional in seam 3, this is the only conditional the
   portable tree gains.
3. **`ThemeColors`.** `Formatters` takes a `ThemeColors`, and `Theme.swift`
   fails on `UIColor.systemRed`, `.systemBlue`, `.systemGreen`, `.systemGray`,
   `.systemFill`, `.label`, and `UITraitCollection`. Split `ThemeColors` into its
   own portable file with watch-safe values for those colors; the
   trait-collection and metrics code moves to the iOS tree. If watch-safe values
   need a platform conditional, it lives in that one file.
4. **`kCFErrorDomainCFNetwork`** (`APIService+GetData.swift:116`) requires
   CFNetwork, which watchOS lacks. Replace with the literal domain string.
5. **`Polyline.mkPolyline`.** The vendored library fences the property with
   `#if !os(watchOS)`; `PolylineEntity.swift` and `StopsForRoute.swift` call it.
   Apple's docs list `MKPolyline` as available on watchOS, so first try lifting
   the fence; if the compiler disagrees, fence the two callers instead. The map
   is out of v1 scope either way.

### To verify at the start of the plan

- Whether `scripts/extract_strings`, `.swiftlint.yml`, `scripts/docs` (DocC), and
  the OBAKitTests source paths need to learn about `OBAKitCoreiOS/`.
- Whether a second layer of watchOS compile errors appears once the first is
  fixed.

## §2 Watch targets and white-label opt-in

Follows the convention OBAWidget already establishes: the target's shape lives in
`<Target>/project.yml`; each app's `project.yml` includes it and overrides
identity and configuration.

| Target | Type | Role | Depends on |
|---|---|---|---|
| `OBAKitWatch` | framework, watchOS | All watch screens and view models (SwiftUI). OBAKit's counterpart. | OBAKitCore |
| `WatchApp` | application, watchOS | Thin shell: `@main` struct, assets, `Info.plist`. Shared code in `Apps/Shared/WatchClient/`, mirroring `CommonClient`. | OBAKitWatch, OBAKitCore, OBAWatchWidget |
| `OBAWatchWidget` | app-extension, watchOS | Complications and Smart Stack (§4). | OBAKitCore only |

XcodeGen 2.46.0 generates a modern single-target watch app from
`type: application` + `platform: watchOS` (product type
`com.apple.product-type.application`, no WatchKit extension) and adds the "Embed
Watch Content" phase to the host app automatically from the target dependency.
Verified 2026-09-19 by generating a throwaway project; that project was generated
but not built. (Context7's XcodeGen snippets claim only the legacy two-target
`watchapp2` + `watchkit2-extension` form exists. That caption is wrong for 2.46.0.)

**Shared views go in OBAKitCore.** Glanceable SwiftUI views needed by both the
watch app and its complication live beside `RouteBadgeView` and `CountdownView`,
which already compile for watchOS. OBAKitWatch therefore need not be
extension-safe, and the two widgets can share row views across platforms.

**Opt-in.** An app gets a watch app by adding three includes, a `WatchApp`
override block, and `- target: WatchApp` to its `App` dependencies.
`Apps/Shared/app_shared.yml` does not change, so KiedyBus — and any agency that
never wants a watch app — generates exactly the project it generates today.

**Per-app overrides**, following the widget's block:

- `PRODUCT_BUNDLE_IDENTIFIER`: `<ios bundle id>.watchkitapp`; widget:
  `<…>.watchkitapp.OBAWatchWidget`. The companion-prefix requirement is recalled,
  not verified this session; confirm against Apple's current docs in the step 5
  plan.
- `WKCompanionAppBundleIdentifier`, `WKRunsIndependentlyOfCompanionApp: true`
- An app-group entitlement (the watch app and its widget share an on-watch
  container; see §3)
- The `OBAKitConfig` block the iOS widget carries: `AppGroup`,
  `BundledRegionsFileName`, `RESTServerAPIKey`, `RegionsServerBaseAddress`,
  `RegionsServerAPIPath`

**Deployment target:** watchOS 11.0, the release paired with the iOS 18.0 floor.
Declared per target (`deploymentTarget` on each watch target, and
`deploymentTarget: {iOS: "18.0", watchOS: "11.0"}` on OBAKitCore), so
`app_shared.yml` is untouched. The project-wide Swift 6 and MainActor-default
settings in that file apply to the new targets automatically.

**To verify:** opt-in relies on XcodeGen *appending* an app's `dependencies`
array to the shared `App` target's rather than replacing it. If it replaces, the
app's `project.yml` restates the full dependency list (four lines).

## §3 How data reaches the watch

App groups do not span the phone/watch boundary, so the iOS widget's mechanism —
reading the app's `UserDefaults` suite — is unavailable. And Apple's guidance for
independent watch apps is explicit: such an app "can't use Watch Connectivity as
its main source of data, so it needs to be capable of accessing information on
its own."

**Principle.** The watch is a full, independent OBAKitCore host. It builds its
own `CoreApplication` over its own on-watch app-group `UserDefaults` — the
`WidgetDataProvider` pattern, unchanged — with its own `RegionsService` and its
own `RESTAPIService`. **Only bookmarks and a region hint cross the device
boundary, one way, phone → watch.**

### Components

- **`WatchSyncPayload`** — OBAKitCore, portable. A versioned `Codable`:
  `schemaVersion`, `bookmarks`, `bookmarkGroups`, the phone's current `Region`,
  `generatedAt`. `Bookmark` and `BookmarkGroup` are already `Codable` and already
  persisted as encoded `Data`, so the payload is one `Data` blob using the
  existing model coding. No parallel DTO layer.
- **Sender** — OBAKit. Activates `WCSession`; calls
  `updateApplicationContext(["payload": data])` on activation and whenever
  bookmarks, groups, or the current region change.
- **Receiver** — OBAKitWatch. Reads `receivedApplicationContext` at launch and
  handles `session(_:didReceiveApplicationContext:)` thereafter. Decodes, writes
  into the watch's `UserDataStore`, stores the region hint, and reloads
  complication timelines.

`updateApplicationContext` is the right primitive: Apple documents it as
replacing the previous dictionary, callable while the counterpart is
unreachable, with "the goal of having the data ready to use by the time the
counterpart wakes up."

WatchConnectivity appears only in OBAKit and OBAKitWatch. **OBAKitCore never
imports it**, which keeps core free of it and avoids depending on whether
`WCSession` is permitted under `APPLICATION_EXTENSION_API_ONLY` (not checked).

### Region rule

The watch selects a region from its own location. It falls back to the phone's
synced region when watch location is unavailable or matches no region. The
fallback is why the payload carries a full `Region` rather than an identifier:
custom regions added via the `add-region` deep link exist only on the phone, and
without the hint a custom-region user's watch could not reach their server.

### Failure behavior

| Situation | Behavior |
|---|---|
| Never synced (phone app never launched, or not yet delivered) | Bookmarks shows an empty state. Nearby works. |
| Unknown `schemaVersion` | Ignore the payload; keep last good data; log. |
| Decode failure | Keep last good data; log. |
| No location and no synced region | Region-required empty state. |

**Non-goal for v1:** editing bookmarks on the watch. One-way sync has no
conflicts to resolve.

**To verify:** the documentation for `updateApplicationContext` states no size
limit. If `Bookmark` embeds full `Stop` objects, a heavy user's payload may be
large. Measure a realistic payload early; fallbacks are a trimmed payload or
`transferUserInfo`.

## §4 Complications and widget code sharing

Of OBAWidget's 13 files, the data and timeline code is portable and the views are
not:

| File | Lines | Imports | Disposition |
|---|---|---|---|
| `Provider/WidgetDataProvider.swift` | 119 | Foundation, OBAKitCore, CoreLocation | **Move into OBAKitCore** as `BookmarkArrivalsLoader` |
| `Provider/BookmarkTimelineProvider.swift`, `Entries/BookmarkEntry.swift` | 88 | + WidgetKit | **Move to `OBAWidgetShared/`**, compiled into both widget extensions |
| `Views/*`, `Widgets/OBAWidget*.swift` | — | built for `.systemMedium` / `.systemLarge` | Stay in OBAWidget |
| `Widgets/TripLiveActivity.swift`, `Components/RefreshButton.swift`, `Main/OBAAppIntents.swift` | — | ActivityKit / AppIntents | Stay in OBAWidget |

**`BookmarkArrivalsLoader` in core.** "Favorited bookmarks → their upcoming
arrivals" is not widget logic. In core it has three consumers: the iOS widget,
the watch widget, and the watch app's Bookmarks screen. The move replaces
`Bundle.main.appGroup!` and `static let shared` with injected configuration.

**Timeline glue shared by source, not by framework.** ~90 lines that need
WidgetKit do not justify a third framework in a size-constrained watch bundle,
and keep WidgetKit out of core.

**Families.** `WidgetFamily` is available on watchOS 9.0+ (Apple docs). v1:

- `accessoryRectangular` (also serves the Smart Stack): route badge, next two
  departures
- `accessoryCircular`: minutes to next departure
- `accessoryInline`: one line of text

`accessoryCorner` is deferred; it needs its own curved-label design.

**Content.** The top favorited bookmark: the first element of
`userDataStore.favoritedBookmarks` as synced, which is the order the user already
controls on the phone. A per-complication picker (`AppEntity` + query over bookmarks) is
deferred.

**Freshness.** Entries render countdowns with date-relative `Text` so minutes
tick without spending reload budget. The watch app reloads timelines after each
sync and each foreground fetch. watchOS reload budget figures were not verified
and are not relied on here.

## §5 Testing, CI, and staying watch-clean

**The guardrail is a compile.** Add one step to the existing `build` job in
`.github/workflows/tests.yml`, after the iOS build so the package cache is warm:
build the `WatchApp` scheme for `generic/platform=watchOS Simulator`. It covers
OBAKitCore-on-watchOS, OBAKitWatch, and the watch widget, and it is what stops a
contributor adding a `UIView` to the portable tree and merging on green iOS CI.
Until step 5 creates `WatchApp`, the step builds the `OBAKitCore` scheme for
watchOS instead.

Not yet known: the step's CI cost, and whether the self-hosted `xcode-27` runner
needs `xcodebuild -downloadPlatform watchOS` the way it does for iOS. (The local
probe ran with a watchOS runtime installed, so it does not answer this.)

**Tests live where the logic lives, and the logic lives in core.** Design rule:
OBAKitWatch holds views and thin observable models; anything with a branch in it
goes in OBAKitCore. The existing iOS-hosted Swift Testing suite then covers the
watch's logic without a second test host. New suites in OBAKitTests:

- `WatchSyncPayload`: round-trip; unknown version ignored; corrupt payload keeps
  last good data
- `BookmarkArrivalsLoader`
- The region fallback rule

An `OBAKitWatchTests` target is deferred until logic exists that cannot live in
core.

**Localization is scope, not an afterthought.** Arrival formatting is already
localized in core and carries over. Watch-only strings need all 13 locales; the
plan tracks that as its own item.

### Sequencing

Each step is one PR that leaves `main` green.

1. The five seam fixes, in place. Pure refactors; iOS behavior unchanged. Files
   that §1 assigns to the iOS tree (`LocationService+ProximityAlerts.swift`, the
   `RegionMonitoringLocationManager` protocol, the non-color half of `Theme.swift`)
   are created inside `OBAKitCore/` here and relocated in step 2, so this PR
   contains no directory moves.
2. Move files to `OBAKitCoreiOS/`; add `supportedDestinations`; add the CI
   watch-compile step.
3. Extract `BookmarkArrivalsLoader`; the iOS widget adopts it.
4. `WatchSyncPayload` and the phone-side sender.
5. OBAKitWatch and WatchApp: bookmarks, arrivals, nearby stops.
6. OBAWatchWidget.

Steps 1–3 make OBAKitCore watch-ready and stand on their own even if the watch
app slips. **The first implementation plan covers steps 1–3.** Steps 4–6 get
follow-on plans, written once the core port has shown what the second layer of
compile errors looks like.

## Alternatives considered

**Split the UIKit half into a new `OBAKitCoreUI` framework.** The cleanest end
state: OBAKitCore becomes genuinely platform-neutral and the compiler, not a
build filter, enforces it. The new framework must be extension-safe, because
OBAWidget uses `TripLiveActivityCardView`, `TripActivityPresenter`, and
`ThemeColors`. Rejected for now on cost: `AutoLayoutExtensions` and
`UIKitExtensions` are used throughout OBAKit, so up to 318 files could need a
second import (an upper bound; actual usage was not measured), landing against 9
open PRs. It stays available later and is not meaningfully harder then.

**In-place `#if os(iOS)` guards, no file moves.** Smallest diff, but scatters
conditional compilation across 20 files and leaves nothing marking which part of
core is portable. Retained only as the fallback if the sibling-directory
mechanism fails at scale.

**Dependent watch app** (phone fetches, watch displays). Needs only core's
models on the watch, but the app is useless out of phone range and it contradicts
Apple's guidance. **Watch-only app.** Discards the user's existing bookmarks and
the white-label pairing with each agency's iOS app.
