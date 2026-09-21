# watchOS Architecture

We want a watchOS app for OneBusAway that reuses OBAKitCore rather than
reimplementing it. OBAKitCore does not build for watchOS today, but it is far
closer than its import list suggests: the services half is nearly portable and
the breakage is concentrated in UIKit view code the watch does not need.

This spec covers the architectural changes that make OBAKitCore a two-platform
module, and the target structure, data flow, and complications design that a
watch app builds on top of it.

## Decisions

Made with the maintainer, 2026-09-19/20. Rows marked **(rev.)** were changed
after the validation pass described below.

| Decision | Choice |
|---|---|
| Relationship to the iPhone app | **Independent companion.** Ships with the iOS app, runs without the phone nearby. |
| v1 scope | Bookmarks + arrivals, nearby stops, complications / Smart Stack. **Map deferred.** |
| White-label | **Yes, from the start.** Watch UI in a framework; apps opt in. |
| Core strategy | **One OBAKitCore module, two destinations,** iOS-only files fenced off. |
| Bookmark sync | **One-way, phone → watch** in v1, over WatchConnectivity. No bookmark editing on the watch. |
| Sync payload **(rev.)** | **A trimmed `WatchBookmark` DTO,** no timestamp, content-hash revision. Was: reuse the full `Bookmark` encoding. |
| Complication data path **(rev.)** | **A stateless loader; the widget never builds a `CoreApplication`.** Was: mirror `WidgetDataProvider`. |
| Live Activities on the watch **(rev.)** | **Added as step 0:** `supplementalActivityFamilies` on the existing iOS Live Activity. |
| CI **(rev.)** | Compile guardrail **plus an install-and-launch smoke test** from step 5. |
| Complication content | The top favorited bookmark. Per-complication picker deferred. |
| Implementation plans | Step 0 gets its own short plan. The first main plan covers steps 1–3 (core portability). Steps 4–6 are follow-on plans. |

## How this spec was validated

Two rounds, both outside the repo, which was never modified.

**Round 1 (2026-09-19/20)** compiled `OBAKitCore/` for
`generic/platform=watchOS Simulator` from a throwaway XcodeGen project (watchOS
27.0 SDK, XcodeGen 2.46.0, Swift 6 mode, `nonisolated` default isolation) and
probed XcodeGen's destination filters.

**Round 2 (2026-09-20)** was an adversarial review by a separate agent using
Apple's documentation, XcodeGen's documentation, and a structurally faithful
scratch replica of this architecture — multi-destination core, sibling iOS-only
directory, watch framework, watch app, watch widget, iOS app and widget, with
the repo's include structure — which it **built, embedded, installed, launched,
and synced between paired simulators.** It found three defects that would have
shipped a non-working app, all corrected below, and reversed two design
decisions on measured evidence. Its code-reading claims were spot-checked
against the repo, and the two build-setting defects (§2, "Two XcodeGen defaults
that must be overridden") were reproduced independently by removing its fixes
from a copy of its probe and reading the generated build settings.

Evidence tags used below: **[built]** verified by building/running,
**[doc]** stated in Apple or library documentation, **[code]** established by
reading this repo, **[recalled]** not verified.

The `xcode` MCP server was unreachable for both rounds; `xcodebuild` and
`simctl` were used instead.

## Where OBAKitCore stands today

- **GRDB 7.11 and SwiftProtobuf 1.38.1 both build for watchOS.** [built]
- **ActivityKit is iOS/iPadOS only** ([doc]: `ActivityAttributes` is "iOS 16.1+,
  iPadOS 16.1+"). `import ActivityKit` fails watchOS dependency scanning
  outright, before any type-checking, so the six files that import it must be
  excluded from the watchOS build rather than guarded at use sites.
  `#if canImport(ActivityKit)` evaluates false on the watchOS SDK. [built]
- With those six files excluded, all 149 remaining compile steps ran and
  **20 files had errors**; 206 of ~245 were `'X' is unavailable in watchOS`.
  [built]
  - **14 are UIKit view code** the watch does not need:
    `Extensions/UIKitExtensions`, `Extensions/AutoLayoutExtensions`,
    `Collections/EmptyDataSetView`, `Collections/ActivityIndicatedButton`,
    `Collections/ListKitExtensions`, `Theme/Theme`, `UI/DepartureTimeBadge`,
    `UI/TripLiveActivityCardView`, `UI/TripActivityPresenter`,
    `UI/ProminentButton`, `UI/PaddingLabel`, `UI/ArrivalDepartureDrivenUI`,
    `Utilities/UIViewPreview`, `Utilities/ImageBadgeRenderer`.
  - **6 are in the services layer** the watch does need; each is a small,
    specific seam (see [Seam fixes](#seam-fixes)).
- The portable remainder (~120 files) includes the SwiftUI views the watch UI
  wants: `RouteBadgeView`, `CountdownView`, `DepartureTimeDisplay`,
  `RealtimeGlyph`.
- `UIColor` is available on watchOS 2.0+ [doc], so `Route.swift`'s `UIColor`
  properties — the only UIKit use in the model layer — are fine.

**This is one compile pass.** Fixing these errors may reveal a second layer the
first pass masked. Neither validation round touched that; the first plan
budgets for it.

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
`supportedDestinations: [iOS, watchOS]`, adds the second source entry, and sets
the watchOS deployment target explicitly (see §2).

Because both directories are the same module, **no `import` statement changes
anywhere** — 567 files import OBAKitCore today (318 in OBAKit, 239 in
OBAKitTests, 8 in OBAWidget, 2 in Apps). OBAKitTests is iOS-hosted, so moved
files stay visible to it.

The ActivityKit fence concerns *compilation for watchOS only*. It does not stop
Live Activities reaching the watch; see step 0.

### Why a sibling directory, and why `group`

XcodeGen 2.46.0 [built]:

| Layout | Result |
|---|---|
| `iOS/` nested in the synced folder, `inferDestinationFiltersByPath: true` | **Filter silently ignored.** XcodeGen exits 0, emits no `platformFilter`, and the watchOS build compiles the iOS file and fails. |
| Nested, explicit `destinationFilters: [iOS]` on a synced source | Same silent no-op. |
| Nested, `type: group` + `destinationFilters` | watchOS builds, but **iOS breaks**: the file reference is a dangling `TEMP_…` ID resolved against the project root. |
| **Sibling directory, `type: group` + `destinationFilters: [iOS]`** | **Both platforms build.** |

Round 2 extended the sibling result beyond the original one-file toy: nested
subfolders **and resources** all receive `platformFilters = (ios, )`, with zero
dangling refs; iOS-only symbols are absent from the watch binary and present in
the iOS one; and a carved-out public umbrella header, `Strings/*.lproj`
(resolved at runtime on the watch), and a `.docc` catalog inside the synced
multi-destination target all build on both platforms. [built] It is still not
proven at full OBAKitCore scale.

Cost: files under `OBAKitCoreiOS/` need `scripts/generate_project` to be picked
up, which the workflow already requires before building.

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

### Step 2 checklist for the new directory

Closed by round 2 [code]:

- **`scripts/extract_strings`** is `find OBAKitCore -name "*.swift" | genstrings`.
  After the move, strings in `OBAKitCoreiOS/` would silently vanish from
  `en.lproj` on the next regeneration. One is at risk today
  (`LiveActivities/LiveActivityStaleChrome.swift`; the 14 UIKit files have
  none). Change it to `find OBAKitCore OBAKitCoreiOS`, regenerate, and require an
  empty diff.
- **`.swiftlint.yml`** `included:` lists OBAKit, OBAKitCore, OBAWidget. Add
  `OBAKitCoreiOS`, or the moved files go unlinted.
- **`scripts/docs`** finds the archive by name and is unaffected.

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
`type: application` + `platform: watchOS`, plus a watchOS `app-extension` widget,
and they **build, embed** (`App.app/Watch/WatchApp.app/PlugIns/…appex`),
**install, and launch**; the system registers the widget's complication
descriptors. [built] `WKApplication`, `WKCompanionAppBundleIdentifier`, and
`WKRunsIndependentlyOfCompanionApp` are the correct keys [doc] and sufficient:
the paired phone reported `isPaired` and `isWatchAppInstalled` true. [built]
Frameworks embed once, in `WatchApp.app/Frameworks`; the appex links to them
without duplication. [built]

(Context7's XcodeGen snippets claim only the legacy `watchapp2` +
`watchkit2-extension` form exists. That caption is wrong for 2.46.0.)

### Two XcodeGen defaults that must be overridden

Both build green and fail later. Both reproduced independently. [built]

- **`WatchApp` needs
  `settings.base.LD_RUNPATH_SEARCH_PATHS: "$(inherited) @executable_path/Frameworks"`.**
  XcodeGen's watchOS application preset omits it (the iOS preset includes it).
  Without it the app installs and then dies at dyld load:
  `Library not loaded: @rpath/OBAKitWatch.framework/OBAKitWatch`. A compile
  cannot catch this, which is why §5 adds a launch test.
- **OBAKitCore needs `settings.base.WATCHOS_DEPLOYMENT_TARGET: "11.0"` set
  explicitly.** A per-target `deploymentTarget: {iOS: …, watchOS: …}` map on a
  `supportedDestinations` target is silently dropped; watchOS then falls to the
  SDK default (27.0) and dependents fail with "module 'OBAKitCore' has a minimum
  deployment target of watchOS 27.0". Single-platform watch targets may use
  `deploymentTarget: "11.0"` normally.

watchOS 11.0 is the release paired with the iOS 18.0 floor.
`Apps/Shared/app_shared.yml` is not modified; its project-wide Swift 6 and
MainActor-default settings apply to the new targets automatically.

### Opt-in

An app gets a watch app by adding three includes, a `WatchApp` override block,
and `- target: WatchApp` to its `App` dependencies. XcodeGen merges included
arrays **additively** ([built], and [doc]: "merged additively by default…
`:REPLACE`"), so the app's one line appends to the shared `App` dependency list.
KiedyBus — and any agency that never wants a watch app — generates exactly the
project it generates today.

### Per-app overrides

- `PRODUCT_BUNDLE_IDENTIFIER`: `<ios bundle id>.watchkitapp`; widget:
  `<…>.watchkitapp.OBAWatchWidget`.
- `WKCompanionAppBundleIdentifier` (must equal the iOS app's bundle ID [doc]),
  `WKRunsIndependentlyOfCompanionApp: true`.
- An app-group entitlement; the watch app and its widget share an on-watch
  container (§3).
- `NSLocationWhenInUseUsageDescription` for the watch app, with
  `InfoPlist.strings` in all 13 locales. Independent watch apps present the
  authorization prompt on the watch itself. [doc]
- ATS exceptions mirrored from the iOS app (custom regions may be plain HTTP).
- The `OBAKitConfig` block the iOS widget carries, and a per-app `regions.json`.
  (Today `OBAWidget/Resources/regions.json` is OneBusAway-specific content inside
  a white-label target, and already differs from
  `Apps/OneBusAway/Resources/regions.json`; do not repeat that for the watch.)

**The build does not validate watch identity.** Simulator builds succeed with a
non-prefixed watch bundle ID and with a wrong `WKCompanionAppBundleIdentifier`.
[built] No Apple document stating the prefix rule was found; the
`.watchkitapp` convention is [recalled]. A white-label misconfiguration would
surface only at device install or App Store validation, so step 5 adds a check
(in `scripts/generate_project` or a test) that `WKCompanionAppBundleIdentifier`
equals the `App` bundle ID and that the watch ID is prefixed by it.

### A consequence for every iOS build

Once `App` depends on `WatchApp`, building the iOS `App` scheme builds the entire
watch stack too. [built] So after step 5 the existing CI build already compiles
the watch targets for OneBusAway, and every local iOS build pays for it. Step 5
should provide a scheme or configuration without the watch dependency for fast
local iteration.

## §3 How data reaches the watch

App groups do not span the phone/watch boundary, so the iOS widget's mechanism —
reading the app's `UserDefaults` suite — is unavailable. Apple's guidance for
independent watch apps: such an app "can't use Watch Connectivity as its main
source of data, so it needs to be capable of accessing information on its own,"
but "can use Watch Connectivity to transfer information from its companion iOS
app when the iOS device is available." [doc]

**Principle.** The watch app is an independent OBAKitCore host with its own
`RegionsService`, `LocationService`, and `RESTAPIService`. **Only bookmarks and a
region hint cross the device boundary, one way, phone → watch.**

### Payload

`WatchSyncPayload` lives in OBAKitCore (portable, no WatchConnectivity import):

```
WatchSyncPayload { schemaVersion, revision, bookmarks: [WatchBookmark],
                   groups: [WatchBookmarkGroup], region: Region? }
WatchBookmark    { id, groupID, name, regionIdentifier, stopID, stopName,
                   stopDirection, latitude, longitude, isFavorite, sortOrder,
                   routeID?, routeShortName?, tripHeadsign? }
```

**Why a DTO, reversing the original "no parallel DTO layer."** `Bookmark` embeds
a full `Stop`, which encodes its `[Route]`, each of which encodes a full
`Agency`. Measured against real fixture data (51 stops, 8.35 routes per stop),
50 bookmarks [built]:

| Encoding | Size |
|---|---|
| Full `Bookmark` models, binary plist (what `encodeUserDefaultsObjects` produces today) | 56,982 B |
| Full models, JSON | 238,772 B |
| **Trimmed `WatchBookmark`, binary plist** | **8,695 B** (~170 B per bookmark) |

Apple publishes no size limit for the application context; `WCError.Code`
includes `payloadTooLarge`. [doc] The simulator accepted and delivered 4 MB, so
it enforces nothing and says nothing about hardware. Community figures of
65–262 KB are [recalled]. The trimmed payload stays under 64 KB to roughly 370
bookmarks.

**Encoding is binary plist,** which is byte-stable across processes; default
`JSONEncoder` output is not. [built]

**The payload contains no timestamp.** The system drops an application context
identical to the previous one: six identical `updateApplicationContext` calls
across two phone launches produced exactly one watch delivery. [built] A
`generatedAt` field would make every send unique, turning each phone launch into
a transfer, a watch background wake, and a complication reload. `revision` is a
hash of the payload's content. The sender skips the call when `revision` matches
what `session.applicationContext` already holds; the receiver discards a payload
whose revision it has already applied.

Because the watch stores `WatchBookmark`, not `Bookmark`, it does **not** write
into `UserDataStore.bookmarks`. The receiver persists the payload in the
on-watch app-group suite; the watch UI and the watch widget both read it there.

### Sender (OBAKit) and receiver (OBAKitWatch)

The sender observes `.bookmarksDidChange` — following
`BookmarkWidgetRefresher` — and `RegionsServiceDelegate.updatedRegion`.

**Change plumbing is incomplete today** [code]: `.bookmarksDidChange` is posted
from only three sites (`add(_:to:index:)`, `setPinned`, `delete(bookmark:)`).
Nothing is posted for `upsert(bookmarkGroup:)`, `replaceBookmarkGroups`, the
`bookmarks` / `bookmarkGroups` setters, or `updateBookmarksWithStop` — so a group
rename, reorder, or creation never reaches an observer. Conversely `deleteGroup`
re-adds its bookmarks in a loop and posts once per bookmark. Step 4 adds a
`.bookmarkGroupsDidChange` post from the group mutators; the debounce below
absorbs the burst.

**Sends are debounced** (1–2 s trailing) and skipped when `revision` is
unchanged. With the watch reachable, nine rapid updates were each delivered
individually [built]; the system does not coalesce for you.

`updateApplicationContext` is the right primitive among the five [doc]: it is
latest-state-wins and deliverable while the counterpart is unreachable.
`transferUserInfo` queues every version; `sendMessage` requires reachability;
`transferCurrentComplicationUserInfo` is budgeted and unsupported in the
simulator; `transferFile` is for documents.

### Concurrency

OBAKit and OBAKitWatch build with `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`.
WatchConnectivity calls its delegate on "a non-main serial queue" [doc], and the
SDK header carries no Swift concurrency annotations.

**A naive conformance compiles with zero diagnostics — even with this repo's five
escalated diagnostic groups — and traps at runtime** in
`_checkExpectedExecutor → dispatch_assert_queue_fail`. [built; demonstrated by
invoking the delegate's `@objc` entry point from a background queue, since an
unpaired simulator never fires the callback]

Required design, verified between paired simulators [built]:

- Every `WCSessionDelegate` method on both sides is declared `nonisolated`.
- Inside the callback, extract the `Data` blob (which is `Sendable`) from the
  `[String: Any]` dictionary (which is not). The dictionary never crosses an
  isolation boundary.
- Then hop: `Task { @MainActor in … }`.
- A unit test invokes each delegate method from a background queue, so the trap
  cannot return unnoticed.

### Session lifecycle

| Rule | Why |
|---|---|
| Guard on `WCSession.isSupported()` | False on iPad. |
| Never call `updateApplicationContext` before `activationState == .activated` | Documented programmer error. [doc] |
| Gate sends on `isPaired && isWatchAppInstalled`, valid only while activated; handle `WCError.watchAppNotInstalled` / `.deviceNotPaired` | This is also what makes the OBAKit sender a no-op for apps with no watch target (KiedyBus). |
| iOS delegate implements `sessionDidBecomeInactive` and `sessionDidDeactivate`, and calls `activate()` again | Otherwise the app opts out of multiple-watch support and the system terminates it on a watch switch. [doc] |
| Re-send the current payload after re-activation and when `sessionWatchStateDidChange` reports a newly installed watch app | Otherwise a new or switched watch stays empty until the next bookmark edit. |
| `updateApplicationContext` throws; handle `payloadTooLarge` | Log and surface; do not crash. |
| The receiver is idempotent and order-safe | On the watch, the pending context arrived via `didReceiveApplicationContext` *before* `activationDidComplete`, and `receivedApplicationContext` read inside `activationDidComplete` was empty in one run. [built] Unstructured main-actor `Task`s do not guarantee FIFO; `revision` makes re-application harmless. |

WatchConnectivity compiles inside an `APPLICATION_EXTENSION_API_ONLY` framework
on both platforms [built], so keeping it out of OBAKitCore is a choice, not a
constraint: it keeps core free of a framework only two targets use.

### Region rule

The watch selects a region from its own location and falls back to the phone's
synced region when watch location is unavailable or matches no region. The
payload carries a full `Region` because custom regions added via the
`add-region` deep link exist only on the phone.

**The resolved region is persisted in the app-group container, not re-derived
per process.** `RegionsService.currentRegion` stores only an identifier and
resolves it via `find(id:)` against `regions + customRegions`, and custom regions
are files under the *process's* Documents directory
(`RegionsFileStorage.customRegionsDirectoryURL`). [code] A widget extension has
its own sandbox, so its `RegionsService` resolves a custom region to `nil`, gets
no API service, and renders nothing. **The iOS widget has this same latent gap
today.** The fix — the app writes the resolved `Region` to the app-group suite,
and loaders take a region as input — lands in step 3 and repairs both.

### Transport seam and known limitation

The sync boundary is a `WatchSyncTransport` protocol in OBAKit/OBAKitWatch, with
WatchConnectivity as the only v1 implementation. Apple steers independent apps
toward CloudKit [doc], and the weakness of WatchConnectivity is real: a cellular
watch whose phone is off never receives bookmark edits, and Family Setup watches
never sync. But CloudKit needs an iCloud entitlement and container per agency
bundle ID and an iCloud-signed-in user — a poor default for a white-label
open-source framework. The protocol lets an agency add a CloudKit transport
later without touching the rest.

**Known limitation, v1:** no bookmark sync without the paired phone. Nearby
still works.

### Failure behavior

| Situation | Behavior |
|---|---|
| Never synced | Bookmarks shows an empty state. Nearby works. |
| Unknown `schemaVersion` | Ignore the payload; keep last good data; log. |
| Decode failure | Keep last good data; log. |
| Already-applied `revision` | Discard silently. |
| Watch switched, or watch app installed later | Re-activate; re-send the current payload. |
| No location and no synced region | Region-required empty state. |

**Non-goal for v1:** editing bookmarks on the watch.

### Watch networking and location

- `APIService+GetData` hardcodes `URLRequest(timeoutInterval: 10)` [code], short
  for a Bluetooth-proxied or cold-LTE path. Make the timeout configurable; the
  watch uses 20–30 s.
- `LocationService` does not start updates in `init` [code], but the
  `LocationManager` protocol exposes only continuous updates. Add
  `requestLocation()` (watchOS 2.0+ [doc]); the watch takes one-shot fixes at
  `kCLLocationAccuracyHundredMeters`.
- The iOS arrivals cadence is a 30 s timer (`BookmarkDataLoader`). On the watch,
  foreground polling stops when the scene leaves `.active`.
- The watch app's `CoreApplication` is configured with surveys, Obaco, and
  agency alerts disabled; step 5 adds the `CoreAppConfig` switches that needs.
- Test all three network routes: phone proxy, Wi-Fi, cellular. [doc]

## §4 Complications and widget code sharing

### What the original plan got wrong

The first draft proposed sharing the iOS widget's timeline provider. Reading it
[code] shows that would not compile and would not be worth sharing:

- `BookmarkTimelineProvider` is an `AppIntentTimelineProvider` over
  `ConfigurationAppIntent`, defined in `Main/OBAAppIntents.swift` — a file the
  draft left behind in OBAWidget.
- `BookmarkEntry` carries only `[Bookmark]`, **no arrivals.** Views read arrivals
  from the `WidgetDataProvider.shared` singleton at render time. The timeline is
  12 identical entries 30 minutes apart with `.atEnd`, so data refreshes roughly
  every **6 hours**.
- Core already has `OBAKitCore/Bookmarks/BookmarkDataLoader.swift` (30 s timer,
  delegate, batching), which the draft's "three consumers" analysis missed.
  Neither loader dedupes by stop, so two trip bookmarks at one stop make two
  identical requests.
- `CoreApplication` is too heavy for a complication: its `init` starts a regions
  network task, builds REST, Obaco, and survey services, opens the GRDB stop
  cache and runs migrations, and calls `incrementAppLaunchCount()` — which, from
  an extension, inflates the counter survey gating reads. `WidgetDataProvider`
  additionally calls `refreshServices()` on every timeline load. [code]

### The loader

**`BookmarkArrivalsLoader`, in OBAKitCore, is a stateless async function:**

```
(region, apiConfiguration, [BookmarkArrivalsRequest]) async -> [Request.ID: [ArrivalDeparture]]
```

`apiConfiguration` is whatever `RESTAPIService` needs beyond the region's base
URL (API key and client identity today); the step 3 plan fixes its exact shape
from `RESTAPIService`'s initializer. `BookmarkArrivalsRequest` is a stop ID plus
an optional trip key; both `Bookmark` and `WatchBookmark` map to it. Requests are **deduped by stop ID.** It requires no
`CoreApplication`. It has four callers: the existing `BookmarkDataLoader`, the iOS
widget, the watch widget, and the watch app's Bookmarks screen.

**The watch widget never instantiates `CoreApplication`.** It reads bookmarks and
the resolved region from the app-group suite and calls the loader. The GRDB stop
cache stays per-process by design; do not share the SQLite file between app and
extension (cross-process WAL and data protection while locked are avoidable risk
for a cache).

### Entries and timeline glue

Entries carry their data:

```
BookmarkEntry(date, bookmarks, departures: [ID: [DepartureSnapshot]], fetchedAt)
```

`OBAWidgetShared/` — a folder compiled into both widget extensions, a mechanism
verified to work across an iOS and a watchOS app-extension [built] — holds
`BookmarkEntry`, `DepartureSnapshot`, and the entry-generation logic. The
provider *types* stay per-platform: the iOS widget keeps its
`AppIntentTimelineProvider`; the watch widget uses `StaticConfiguration`. Views
stay per-platform (iOS: `.systemMedium` / `.systemLarge`; watch: accessory
families). `TripLiveActivity`, `RefreshButton`, and the AppIntents stay in
OBAWidget.

Adopting this in the iOS widget **fixes its six-hour staleness**, a user-visible
improvement that arrives with step 3.

### Families

`WidgetFamily` is available on watchOS 9.0+ [doc]. v1:

- `accessoryRectangular` (also serves the Smart Stack): route badge, next two
  departures
- `accessoryCircular`: minutes to next departure
- `accessoryInline`: one line of text

`accessoryCorner` is deferred; it needs its own curved-label design.

**Content.** The top favorited bookmark: the first favorited `WatchBookmark` by
`sortOrder`, which is the order the user already controls on the phone. A
per-complication picker is deferred.

### Freshness

Date-relative `Text` keeps a countdown ticking toward a *fixed* predicted time.
It cannot show a bus getting later, and it counts *up* once the date passes.
[doc] It is necessary, not sufficient.

Budgets [doc]: a widget gets "from 40 to 70 refreshes" a day, roughly one every
15–60 minutes; entries should be "at least about 5 minutes apart"; reloads while
the containing app is foreground are free. watchOS background refresh requires a
complication on the active face, allows up to four tasks an hour, and gives "a
few seconds" of runtime.

Strategy:

- Each reload fetches about 60 minutes of arrivals for the top bookmark and
  emits **one entry per departure boundary** — entry N shows the departures that
  remain after departure N−1 has left — so the display advances with no reload.
- Reload policy: `.after(min(nextDeparture + 1 min, now + 15 min))`.
- Entries show scheduled-versus-realtime state and an "as of" time from
  `fetchedAt`; an entry older than a threshold degrades to schedule styling.
- The watch app schedules `backgroundTask(.appRefresh)` at least 15 minutes
  apart and calls `reloadTimelines(ofKind:)` **only when fetched data changed.**
- After a sync, timelines reload only when `revision` changed.

The widget does not request location (`NSWidgetWantsLocation` stays off); it
relies on the persisted region.

### Smart Stack relevance

On watchOS the Smart Stack takes its cue from the provider's `relevance()`
callback and `RelevantContext`; `TimelineEntryRelevance` scores are not used on
watchOS. [doc] v1 implements `relevance()` with a `RelevantContext.location`
around the top bookmark's stop. Date-range relevance for commute times, and
`RelevanceConfiguration`, are deferred. (Apple's sample annotates
`RelevanceConfiguration` with `watchOS 12`, a surprising number; treat its
availability as unverified.)

## §5 Testing, CI, and staying watch-clean

**A compile guardrail, then a launch test.**

- *Steps 2–4:* one step in the existing `build` job, after the iOS build, builds
  the `OBAKitCore` scheme for `generic/platform=watchOS Simulator`. This is what
  stops a contributor adding a `UIView` to the portable tree and merging on green
  iOS CI.
- *From step 5:* the iOS `App` build already compiles the whole watch stack (§2),
  so the separate compile step is dropped and replaced by a **smoke test**:
  `simctl install` and `simctl launch` `WatchApp` on a watch simulator, asserting
  it stays up. A compile cannot catch dyld, `Info.plist`, or embedding failures;
  the launch crash in §2 built green.

The runner is a GitHub-hosted image, not self-hosted. Its published manifest
lists the `watchos27.0` and `watchsimulator27.0` SDKs and installed watchOS 27.0
simulators [doc], so no platform download is needed today; add a guard like the
existing iOS one regardless. CI cost of these steps is unmeasured.

**Tests live where the logic lives, and the logic lives in core.** OBAKitWatch
holds views and thin observable models; anything with a branch in it goes in
OBAKitCore, where the existing iOS-hosted Swift Testing suite covers it. New
suites in OBAKitTests:

- `WatchSyncPayload`: round-trip; byte-stable encoding; `revision` stable for
  equal content and different for changed content; unknown version ignored;
  corrupt payload keeps last good data
- `Bookmark` → `WatchBookmark` mapping
- `BookmarkArrivalsLoader`, including dedupe by stop
- Entry generation: one entry per departure boundary; reload-policy arithmetic
- The region fallback rule, and region resolution from the app-group suite for a
  custom region
- Both `WCSessionDelegate` conformances invoked from a background queue
- `.bookmarkGroupsDidChange` posted by each group mutator

An `OBAKitWatchTests` target is deferred until logic exists that cannot live in
core.

**Size.** App Store Connect lists a 75 MB maximum uncompressed size for watchOS
apps ([doc], read via a summarizing fetch; worth a human glance). A debug,
unstripped simulator build of `OBAKitCore.framework` is 27 MB; all 13 locales of
strings total about 250 KB, so strings are not the concern. [built] The release,
thinned size is unknown until the seams are fixed and the module links. Step 5's
exit criteria record it against a 25 MB budget. Mergeable libraries are not
needed unless that measurement says so. Separately, every `sources: ["."]` target
ships its own `project.yml` as a bundle resource today [built]; add it to
`excludes`.

**Localization is scope, not an afterthought.** Arrival formatting is already
localized in core and carries over. Watch-only strings, and the watch app's
location usage description, need all 13 locales; the plan tracks each as its own
item.

### Sequencing

Each step is one PR that leaves `main` green.

0. **Live Activities on the watch.** Add
   `.supplementalActivityFamilies([.small, .medium])` and an
   `activityFamily`-aware compact layout to the existing `TripLiveActivity`.
   Since watchOS 11, iPhone Live Activities appear in the paired watch's Smart
   Stack automatically; `ActivityFamily.small` is the watch's size family, and
   the modifier is available from iOS 18.0, this repo's floor. [doc] The repo
   uses neither API today. [code] This is iOS-widget work only, needs no watch
   target, depends on nothing below, and gives every paired watch a tracked-trip
   view before any watch app exists.
1. The five seam fixes, in place. Pure refactors; iOS behavior unchanged. Files
   that §1 assigns to the iOS tree (`LocationService+ProximityAlerts.swift`, the
   `RegionMonitoringLocationManager` protocol, the non-color half of
   `Theme.swift`) are created inside `OBAKitCore/` here and relocated in step 2,
   so this PR contains no directory moves.
2. Move files to `OBAKitCoreiOS/`; add `supportedDestinations` and the explicit
   `WATCHOS_DEPLOYMENT_TARGET`; update `extract_strings` and `.swiftlint.yml`;
   add the CI watch-compile step.
3. Extract the stateless `BookmarkArrivalsLoader`; `BookmarkDataLoader` and the
   iOS widget adopt it; entries carry their data; the app persists the resolved
   `Region` to the app-group suite and the iOS widget reads it. Fixes the iOS
   widget's six-hour staleness and its custom-region gap.
4. `WatchSyncPayload` and `WatchBookmark`; the phone-side sender with its
   lifecycle, debounce, and `nonisolated` delegate; `.bookmarkGroupsDidChange`.
5. OBAKitWatch and WatchApp — bookmarks, arrivals, nearby stops — with the
   receiver, `requestLocation()`, the configurable timeout, the `CoreAppConfig`
   switches, the identity check, the no-watch local scheme, the launch smoke
   test, and the size measurement.
6. OBAWatchWidget: accessory families, entry generation, `relevance()`.

Step 0 is independent and gets its own short plan; it can land first. Steps 1–3
make OBAKitCore watch-ready, improve the iOS widget, and stand on their own even
if the watch app slips. **The first main implementation plan covers steps 1–3.**
Steps 4–6 get follow-on plans, written once the core port has shown what the
second layer of compile errors looks like.

## Still unknown

- **The real-device size ceiling for `updateApplicationContext`.** Needs a paired
  iPhone and Apple Watch and a size ladder. Design to stay under 64 KB.
- Whether identical-context suppression and no-coalescing-when-reachable, both
  observed in the simulator, hold on hardware.
- Bundle-ID prefix enforcement at device install and App Store Connect.
- The release, thinned size of OBAKitCore for watchOS.
- The second layer of watchOS compile errors.
- The watchOS widget-extension memory ceiling (a ~30 MB figure is [recalled]).
- Whether a `generic/platform=watchOS Simulator` build needs the simulator
  runtime or only the SDK. Untestable without uninstalling a runtime, and moot
  for the current CI image.
- `RelevanceConfiguration` availability.

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

**Send the full `Bookmark` encoding, minus the timestamp.** No DTO to maintain,
but 6.5 times the bytes on every change and far closer to a device limit nobody
has measured. Rejected.

**Mirror `WidgetDataProvider` in the watch widget.** Least new code, but every
timeline reload pays for a regions network call, a GRDB open, and a launch-count
bump, and custom-region users get an empty complication. Rejected.

**CloudKit or `NSUbiquitousKeyValueStore` as the sync channel.** Syncs without
the phone present, but requires an iCloud entitlement and container per agency
and an iCloud-signed-in user. Deferred behind the `WatchSyncTransport` seam.

**Dependent watch app** (phone fetches, watch displays). Needs only core's
models on the watch, but the app is useless out of phone range and it contradicts
Apple's guidance. **Watch-only app.** Discards the user's existing bookmarks and
the white-label pairing with each agency's iOS app.
