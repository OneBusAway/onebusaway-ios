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
after the first validation pass described below; **(rev. 2)** after the second;
**(rev. 3)** on 2026-09-22, when the step 4 MVP app was designed
([`2026-09-22-watchos-mvp-app-design.md`](2026-09-22-watchos-mvp-app-design.md)).

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
| WatchConnectivity placement **(rev. 2)** | **One shared `WatchSessionBridge` in OBAKitCore,** used by both sides. Was: WatchConnectivity kept out of core, with separate sender and receiver delegates. |
| CI **(rev., rev. 2)** | A **device-architecture** compile guardrail, kept permanently, **plus an install-and-launch smoke test** from step 5. |
| Complication content | The top favorited bookmark. Per-complication picker deferred. |
| Implementation plans | Step 0 gets its own short plan. The first main plan covers steps 1–3 (core portability). Steps 4–6 are follow-on plans. |
| Watch app host **(rev. 3)** | **No `CoreApplication` on the watch.** A `WatchAppHost` in OBAKitWatch assembles the standalone services the step 3 widget path proved. Was: a `CoreApplication` with surveys, Obaco, and alerts switched off. |
| Order of steps 4 and 5 **(rev. 3)** | **The app comes first.** Step 4 is an MVP watch app — nearby stops and arrivals, no sync. Step 5 is bookmark sync plus the Bookmarks tab. Was: sync (inert) in step 4, the app in step 5. |

## How this spec was validated

Three rounds, all outside the repo, which was never modified.

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

**Round 3 (2026-09-20)** attacked the revision itself, using Apple's
documentation, XcodeGen's documentation, XcodeBuildMCP for simulator builds, and
raw `xcodebuild` for what XcodeBuildMCP cannot do (device architectures, paired
simulators). It found one new blocker that no simulator-based check can see —
32-bit `Int` on real watches, below — and several errors the round 2 rewrite
introduced: a reload policy that overspent its own cited budget, a test placed in
a target that cannot host it, and a payload field that would break sync across
the 64-bit/32-bit boundary. Its load-bearing claims were again spot-checked: the
affected declarations, the `arm64_32` compile error in its build log,
`ARCHS_STANDARD`, and its decode demonstration, which was re-run. That
demonstration substitutes `Int32` for `Int` on a 64-bit host, because no 32-bit
simulator exists; the compile failure is from a real `arm64_32` build.

Evidence tags used below: **[built]** verified by building/running,
**[doc]** stated in Apple or library documentation, **[code]** established by
reading this repo, **[recalled]** not verified.

Apple's `xcode` MCP server was unreachable for all rounds (a stale
`DEVELOPER_DIR` pin and a stopped service). XcodeBuildMCP supports watch
simulators but not device-architecture builds, and its `build_run_sim` reports
success for an app that dies in dyld, as does `simctl launch`.

## Where OBAKitCore stands today

- **`Int` is 32 bits on most watches this app will run on, and the simulator
  hides it.** `ARCHS_STANDARD` for the watchOS device SDK is `arm64 arm64_32`.
  [built] Only Series 9 and later and Ultra 2 moved to `arm64`, and only on
  watchOS 26; "the Apple Watch Simulator always uses the arm64 architecture on
  Apple Silicon." [doc, WWDC25-334] So every watch on watchOS 11, and Series 6–8,
  SE 2, and Ultra 1 on any version, has a 32-bit `Int`, and nothing run in a
  simulator can reveal a problem with it.
  - **OBAKitCore does not compile for `arm64_32` today:**
    `ServiceAlert.swift:138: integer literal '10000000000' overflows when stored
    into 'Int'`. [built] GRDB and SwiftProtobuf do link for `arm64_32`. [built]
  - **Every REST response would fail to decode.** The OBA API sends epoch
    milliseconds, which overflow 32 bits. `RESTAPIResponse.currentTime` — the
    base of every response — is `Int?` (`RESTAPIResponse.swift:18,29`);
    `TripStatus.lastLocationUpdateTime`, carried by every realtime arrival, is
    `Int` (`TripStatus.swift:64,172`); `ServiceAlert.TimeWindow` decodes `from`
    and `to` as `Int` (`ServiceAlert.swift:136-150`). [code] Against a real
    fixture these decode as `Int` and fail as `Int32` with "Number 1589553926433
    is not representable". [built]
  - Already safe [code]: `ArrivalDeparture` times decode through the
    `.millisecondsSince1970` `Date` strategy; `ScheduleForStop`,
    `RESTAPIURLBuilder`, and `ObacoAPIService` use `Int64`; GTFS-RT uses
    `UInt64`; GRDB columns and region, survey, and sort identifiers are small.
  - The audit was grep-based, and files that failed to compile for other reasons
    may hide further overflowing literals. The device-architecture CI compile in
    §5 is what finds the rest.
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
   `LocationService+ProximityAlerts.swift` in the iOS tree. `LocationService`
   holds no proximity *stored* state, so the extension split works, but
   `locationManager` and `delegates` are `private` (`LocationService.swift:44,107`)
   and must become internal for a cross-file extension to reach them. [code]
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
6. **32-bit `Int`.** Change the epoch-valued `Int` fields listed under "Where
   OBAKitCore stands today" to `Int64` (or decode them as `Date`), and fix the
   `10_000_000_000` literal by typing `decodeUnixTimestamp` over `Int64`. These
   are source-compatible on 64-bit platforms, so iOS behavior is unchanged. Add a
   SwiftLint custom rule flagging `decode(IfPresent)?(Int.self` under
   `Models/REST` and `Int(…timeIntervalSince1970`, so the pattern cannot return.

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

An opting-in app keeps all its watch wiring in one file, `Apps/<App>/watch.yml`:
the three target includes, the `WatchApp` and `OBAWatchWidget` override blocks,
and `- target: WatchApp` added to `App`'s dependencies. XcodeGen merges included
arrays **additively** ([built], and [doc]: "merged additively by default…
`:REPLACE`"), so that one line appends to the shared dependency list.

The app's `project.yml` includes it conditionally:

```yaml
include:
  - path: Apps/OneBusAway/watch.yml
    relativePaths: false
    enable: ${OBA_WATCH}
```

`scripts/generate_project` exports `OBA_WATCH=true` unless given `--no-watch`.
An unset variable disables the include. [doc, built: `true` yields six targets
with the watch app embedded; unset yields three, with `App` depending only on the
widget and core, and builds green.] XcodeGen has no config-conditional
dependency form, only platform filters, so an include switch is the mechanism.

KiedyBus — and any agency that never wants a watch app — has no `watch.yml` and
generates exactly the project it generates today.

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
- `NSWidgetWantsLocation` on the watch widget, used for Smart Stack relevance
  only (§4).
- `WKSupportsLiveActivityLaunchAttributeTypes` on the watch app, so tapping the
  iPhone's Live Activity in the Smart Stack opens the watch app rather than
  nothing. [doc]
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
watch stack too [built] — but **only its simulator slices**, which are 64-bit.
That build therefore does not replace the device-architecture guardrail in §5.
Every local iOS build pays for the watch stack; `scripts/generate_project
--no-watch` (above) is the fast path for iOS-only work. In the scratch replica it
cut a clean build from 11.0 s to 7.0 s, which says little about the real
project.

**Link OBAKitCore dynamically, once.** Never add `package:` dependencies to the
watch app or its widget: linking GRDB and SwiftProtobuf statically into both
binaries costs 10.8 MB against about 5 MB for one embedded dynamic framework
(§5). [built]

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

`WatchSyncPayload` lives in OBAKitCore:

```
WatchSyncPayload   { schemaVersion: Int32, revision, bookmarks: [WatchBookmark],
                     groups: [WatchBookmarkGroup], region: Region? }
WatchBookmark      { id, groupID?, name, regionIdentifier: Int32, stopID,
                     stopName, stopDirection?, latitude, longitude, isFavorite,
                     routeID?, routeShortName?, tripHeadsign? }
WatchBookmarkGroup { id, name }
```

**Array order is display order.** The phone flattens bookmarks into the order it
shows them — groups by `BookmarkGroup.sortOrder`, then bookmarks by `sortOrder`,
ungrouped last — and `groups` likewise. The DTO carries **no `sortOrder`**:
`Bookmark.sortOrder` defaults to `Int.max` (`Bookmark.swift:56,132`), which a
64-bit phone would encode and a 32-bit watch could not decode, failing the entire
sync [built]; and it is a per-group index, not comparable across groups [code],
so "first by `sortOrder`" was never well defined.

**Every integer in the payload is declared `Int32`,** and **the payload contains
no `Set`** (see Encoding).

The fields are sufficient [code]: `TripBookmarkKey` keys on `stopID +
routeShortName + routeID + tripHeadsign` (`TripBookmarkKey.swift:13-18`), all
present, so the watch matches a trip bookmark to its arrivals exactly as iOS
does; a bookmark is a trip bookmark when `routeID` is non-nil. `latitude` and
`longitude` serve Nearby and relevance. Route color for an empty-state badge is
an optional later addition.

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

**Encoding is binary plist,** which is byte-stable across processes for structs,
arrays, and dictionaries — and **not once a `Set` is encoded**: across four
processes the plain and dictionary encodings hashed identically while the `Set`
encoding differed every run, as did default `JSONEncoder`. [built] A test encodes
the payload in two subprocesses and compares bytes.

**`revision` is SHA-256 over the binary plist of the payload with `revision`
omitted.** Never Swift's `Hasher`, which is seeded per process. The receiver
compares revisions and never recomputes one, so byte stability across OS
versions, or between iOS's and watchOS's Foundation, is not required.

**The payload contains no timestamp.** The system drops an application context
identical to the previous one: six identical `updateApplicationContext` calls
across two phone launches produced exactly one watch delivery. [built] A
`generatedAt` field would make every send unique, turning each phone launch into
a transfer, a watch background wake, and a complication reload. A
content-derived `revision` inside the payload preserves that dedupe: six separate
phone processes sending content 1, 1, 1, 2, 2, 1 produced exactly four watch
deliveries — one per change, none for repeats (one lagged 18 s). [built, paired
simulators]

The sender skips the call when `revision` matches what
`session.applicationContext` already holds — the property Apple documents as "a
copy of your dictionary… so that you can determine what data you last sent", and
which persists across phone launches [doc, built]; not
`receivedApplicationContext`. The receiver discards a payload whose revision it
has already applied.

**Forced re-sends bypass that check.** After re-activation, or when a watch app
is newly installed, the sender must deliver even though its own revision is
unchanged, and it is unknown whether `applicationContext` and the system's dedupe
are tracked per watch. A forced re-send adds a top-level `resendNonce` *outside*
the hashed blob so the system cannot suppress it; the receiver's revision check
makes a redundant one free.

Because the watch stores `WatchBookmark`, not `Bookmark`, it does **not** write
into `UserDataStore.bookmarks`. The receiver persists the payload in the
on-watch app-group suite; the watch UI and the watch widget both read it there.

### One bridge, two thin clients

**`WatchSessionBridge` lives in OBAKitCore** and is the only type that imports
WatchConnectivity or conforms to `WCSessionDelegate`. It owns activation and
re-activation, the `nonisolated` delegate methods, the `isSupported` / `isPaired`
/ `isWatchAppInstalled` gating, and one ordered stream of incoming payloads (see
Concurrency). This reverses the earlier "WatchConnectivity never enters
OBAKitCore." The reasons: the delegate is the most dangerous code in the design
— it compiles clean and traps at runtime — so it should exist once; a watch-side
delegate in OBAKitWatch could not be unit-tested without a watchOS test host,
whereas core is covered by the existing iOS-hosted suite; and it is the
least-duplication answer. WatchConnectivity compiles inside an
`APPLICATION_EXTENSION_API_ONLY` framework on both platforms. [built]

The clients stay where their dependencies are. The **sender** (OBAKit) maps
`Bookmark` → `WatchBookmark`, debounces, and calls the bridge. The **receiver**
(OBAKitWatch) consumes the bridge's stream, persists the payload, and reloads
timelines.

The sender observes four triggers, the same four that write the persisted region
(see Region rule): `.bookmarksDidChange` — following `BookmarkWidgetRefresher` —
plus `.bookmarkGroupsDidChange`, `RegionsServiceDelegate.updatedRegion`, and
`updatedRegionsList`.

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

WatchConnectivity calls its delegate on "a non-main serial queue" [doc], and the
SDK header carries no Swift concurrency annotations.

**In a MainActor-default module, a naive conformance compiles with zero
diagnostics — even with this repo's five escalated diagnostic groups — and traps
at runtime** in
`_checkExpectedExecutor → dispatch_assert_queue_fail`. [built; demonstrated by
invoking the delegate's `@objc` entry point from a background queue, since an
unpaired simulator never fires the callback]

OBAKitCore is the one target whose default isolation is `nonisolated`, so the
bridge does not inherit the trap by default — but the trap was demonstrated in a
MainActor-default module, which is where a well-meaning refactor or a second
delegate in OBAKit would land. The rules are therefore explicit rather than
reliant on the module default.

Required design, verified between paired simulators [built]:

- Every `WCSessionDelegate` method is declared `nonisolated` explicitly.
- Inside the callback, extract the `Data` blob (which is `Sendable`) from the
  `[String: Any]` dictionary (which is not). The dictionary never crosses an
  isolation boundary.
- Then **yield into one long-lived `AsyncStream<Data>`, consumed by a single
  main-actor task.** Do not spawn a `Task { @MainActor in … }` per callback:
  unstructured tasks carry no FIFO guarantee, and a content hash carries no
  order, so if update B ran before update A the stale A would overwrite B.
  `revision` protects against duplicates, not reordering. The delegate queue is
  serial, so the stream's order is the arrival order.
- A unit test in OBAKitTests invokes each delegate method from a background
  queue, so the trap cannot return unnoticed; another feeds the stream A then B
  and asserts B wins.

### Session lifecycle

| Rule | Why |
|---|---|
| Guard on `WCSession.isSupported()` | False on iPad. |
| Never call `updateApplicationContext` before `activationState == .activated` | Documented programmer error. [doc] |
| Gate sends on `isPaired && isWatchAppInstalled`, valid only while activated; handle `WCError.watchAppNotInstalled` / `.deviceNotPaired` | This is also what makes the OBAKit sender a no-op for apps with no watch target (KiedyBus). |
| iOS delegate implements `sessionDidBecomeInactive` and `sessionDidDeactivate`, and calls `activate()` again | Otherwise the app opts out of multiple-watch support and the system terminates it on a watch switch. [doc] |
| Re-send the current payload after re-activation and when `sessionWatchStateDidChange` reports a newly installed watch app | Otherwise a new or switched watch stays empty until the next bookmark edit. |
| `updateApplicationContext` throws; handle `payloadTooLarge` | Log and surface; do not crash. |
| The receiver is idempotent **and** order-safe | On the watch, the pending context arrived via `didReceiveApplicationContext` *before* `activationDidComplete`, and `receivedApplicationContext` read inside `activationDidComplete` was empty in one run. [built] `revision` makes duplicates harmless; the single ordered stream (Concurrency) makes reordering impossible. Both are needed. |

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

**When it is written.** `updatedRegion` alone is not enough: the `currentRegion`
setter returns early when the identifier is unchanged
(`RegionsService.swift:207-208`), so a regions-server change to the *current*
region — a new base URL, say — fires only `updatedRegionsList`, and a persisted
copy would go stale. [code] The app writes the resolved `Region` on four
triggers: launch, `updatedRegion`, `updatedRegionsList`, and custom-region add,
edit, or delete; and clears the key when there is no region. **Readers fall back
to today's identifier lookup when the key is absent,** which covers the first
widget reload after the update ships and before the app has launched. An encoded
`Region` is about 1–2 KB. [built, approximate]

### Transport seam and known limitation

The sync boundary is a `WatchSyncTransport` protocol in OBAKitCore, with
`WatchSessionBridge` as the only v1 implementation. Apple steers independent apps
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
  for a Bluetooth-proxied or cold-LTE path. Make the timeout configurable: 20–30 s
  in the **foreground**, and **at most 8 s inside background refresh** (below).
- `LocationService` does not start updates in `init` [code], but the
  `LocationManager` protocol exposes only continuous updates and **has no
  `desiredAccuracy`** (`LocationManagerProtocol.swift:13-72`). Add both
  `requestLocation()` (watchOS 2.0+ [doc]; `LocationService` already implements
  the two delegate callbacks it requires) and `desiredAccuracy`; the watch takes
  one-shot fixes at `kCLLocationAccuracyHundredMeters`. Both test mocks
  (`MockAuthorizedLocationManager`, `LocationServiceMocks`) must implement them;
  do not give the protocol a default implementation, or the mocks would silently
  no-op. `requestLocation()` is not dated for a delegate-based service;
  `CLLocationUpdate.liveUpdates` and `CLServiceSession` also compile at the 11.0
  floor [built] but would mean a second location path.
- **Background refresh.** A plain `URLSession` data task is permitted inside
  `backgroundTask(.appRefresh)`, but runtime is "a few seconds", and overrunning
  it can get the app killed (`EXC_CRASH (SIGKILL)`). [doc] So: a timeout of at
  most 8 s inside `withTaskCancellationHandler`; schedule the next refresh via
  `WKApplication.shared().scheduleBackgroundRefresh(…)` before returning; write
  arrivals to an app-group cache that the widget's provider uses when it is under
  60 s old, so the app and the widget do not fetch the same thing twice. These
  APIs compile at the 11.0 floor under MainActor-default isolation. [built]
- **Client identity.** `userUUID` is an instance property of `CoreApplication`
  that lazily creates the UUID in `UserDefaults` (`CoreApplication.swift:252-260`).
  Extract it into a static helper over a suite. The watch gets its own UUID in the
  on-watch app-group suite, shared by the watch app and its widget; the phone's
  UUID is not synced.
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

**`BookmarkArrivalsLoader`, in OBAKitCore, is stateless, takes an injected
service, and streams per-stop results:**

```
func arrivals(for: [BookmarkArrivalsRequest], using: RESTAPIService)
    -> AsyncStream<(StopID, Result<[ArrivalDeparture], Error>)>
```

`BookmarkArrivalsRequest` is a stop ID plus an optional trip key; both `Bookmark`
and `WatchBookmark` map to it. Requests are **deduped by stop ID.** Callers that
want a dictionary collect the stream.

**Why a stream and not `async -> [ID: [ArrivalDeparture]]`,** as first drafted:
`BookmarkDataLoader` today delivers `dataLoaderDidUpdate` per stop as each fetch
lands, distinguishes missing-stop errors (settled as "no departures") from others
(`displayError`, `lastBatchHadError`), tracks `fetchedStopIDs`, and is mocked in
tests through the injected `dataLoader` on `application.apiService`
(`BookmarkDataLoader.swift:188-243`). [code] A dictionary-returning function
would return only after the slowest stop's timeout and would drop the errors —
changing iOS behavior. The stream preserves all four properties, and **step 3's
exit criterion is that every test body and assertion in `BookmarkDataLoaderTests`
passes unmodified.** Its private bookmark *builder* does change: it built every
bookmark at one stop and asserted one request per bookmark, which dedupe by stop
(above) deliberately breaks, so the builder now gives each bookmark its own stop.
[code; found while writing the implementation plan]

**Building the service without `CoreApplication` is cheap.** [code]
`RESTAPIService` is an `actor` whose init only builds a URL builder and a
decoder; it needs `APIServiceConfiguration(baseURL, apiKey, uuid, appVersion,
regionIdentifier, surveyBaseURL?)` plus a `dataLoader` (`APIService.swift:21-36`).
`getArrivalsAndDeparturesForStop(id:minutesBefore:minutesAfter:)` is
`nonisolated` and every caller already passes `minutesAfter: 60`. In a widget,
take `apiKey` and `appVersion` from `Bundle` accessors, the UUID from the static
helper (§3), and the base URL from the persisted region. **Do not use
`CoreAppConfig(appBundle:)` in a widget:** it constructs a `LocationService` and
a `CLLocationManager` (`CoreAppConfig.swift:58`).

The loader has four callers: the existing `BookmarkDataLoader`, the iOS widget,
the watch widget, and the watch app's Bookmarks screen.

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

**Content.** The top favorited bookmark: the first `WatchBookmark` in the synced
array with `isFavorite` set. The array is already in the phone's display order
(§3), which the user controls. A per-complication picker is deferred.

### Freshness

Date-relative `Text` keeps a countdown ticking toward a *fixed* predicted time.
It cannot show a bus getting later, and `style: .timer` counts *up* once the date
passes. [doc] Render countdowns with `Text(timerInterval:countsDown:)`, which
stops at zero. It is necessary, not sufficient.

Budgets [doc]: a widget gets "from 40 to 70 refreshes" a day, roughly one every
15–60 minutes; entries should be "at least about 5 minutes apart"; reloads while
the containing app is foreground are free. watchOS background refresh requires a
complication on the active face, allows up to four tasks an hour, and gives "a
few seconds" of runtime.

Strategy:

- Each reload fetches 60 minutes of arrivals for the top bookmark and emits
  **one entry per departure boundary** — entry N shows the departures that remain
  after departure N−1 has left — so the display advances with no reload.
- **Reload policy: `.after(now + 30 min)` when departures exist; `now + 60 min`
  when there are none; overnight, at the first scheduled departure minus 15
  minutes. Never key the reload to the next departure.** Thirty-minute reloads
  over 18 waking hours is 36 a day, inside the 40–70 budget with room left for
  reloads triggered by sync and background refresh.

  The previous draft's `.after(min(nextDeparture + 1 min, now + 15 min))` was
  wrong twice over: it requested a reload after *every* departure — 15 to 20 an
  hour on a 3-minute headway, against a budget of 40–70 a *day* — contradicting
  the "no reload" point of per-departure entries; and even its 15-minute floor
  is 72 a day.
- **Entry spacing.** On a frequent route, per-departure entries fall closer than
  the "about 5 minutes apart" Apple recommends. The documentation states no
  consequence, and Apple's own Smart Stack sample emits entries one minute apart.
  [doc] What WidgetKit does with closer entries on watchOS is **unknown**: a probe
  compiled and installed a dense-timeline widget but could not place it on a face
  or in the Smart Stack from the command line, so it tested nothing. If closer
  entries prove to be dropped, coalesce departures under 5 minutes apart into one
  entry.
- Entries show scheduled-versus-realtime state and an "as of" time from
  `fetchedAt`; an entry older than a threshold degrades to schedule styling.
  Empty arrivals, a failed fetch, and a missing region each get a distinct entry
  rather than a blank complication.
- The watch app's background refresh (§3) calls `reloadTimelines(ofKind:)` **only
  when fetched data changed** — the departure set, or any minute value.
- After a sync, timelines reload only when `revision` changed.

The widget's *timeline* does not use location; it relies on the persisted
region.

### Smart Stack relevance

On watchOS the Smart Stack takes its cue from the provider's `relevance()`
callback and `RelevantContext`; `TimelineEntryRelevance` scores are not used on
watchOS. [doc] v1 implements `relevance()` with a `RelevantContext.location`
around the top bookmark's stop.

Availability, from the SDK's swiftinterface and a compile at the watchOS 11.0
deployment target [built]: `relevance()`, `WidgetRelevance`, and
`WidgetRelevanceAttribute` are watchOS 11.0; `RelevantContext` is watchOS 10.0
and now lives in **RelevanceKit** (`@_originallyDefinedIn(module: "AppIntents",
watchOS 26.0)`) — write `import RelevanceKit`; the symbols back-deploy.
`RelevanceConfiguration` and `RelevanceEntriesProvider` are **watchOS 26.0** (the
"watchOS 12" in Apple's sample is stale) and are deferred. `date(from:to:)` is
deprecated in 26; use `date(interval:kind:)` behind `#available` when commute-time
relevance is added.

**Location relevance requires the widget to request location.** Apple: "make sure
your app **and your widget extension** request a person's permission to access
location." [doc] So the watch widget sets `NSWidgetWantsLocation`, for relevance
only. Whether the location clue works without the key is unknown.

## §5 Testing, CI, and staying watch-clean

**A device-architecture compile guardrail, permanently; plus a launch test.**

- *From step 2, and kept for good:* one step in the existing `build` job, after
  the iOS build, builds for **`-destination 'generic/platform=watchOS'
  CODE_SIGNING_ALLOWED=NO`** — device architectures, `arm64` and `arm64_32` — the
  `OBAKitCore` scheme at first and the `WatchApp` scheme from step 5. It does two
  jobs: it stops a contributor adding a `UIView` to the portable tree and merging
  on green iOS CI, and it is the **only** check that compiles for 32-bit `Int`.
  A simulator build cannot: in the scratch replica an overflowing literal built
  green for the simulator (exit 0) and failed for the device (exit 65). [built]
  The iOS `App` build compiles the watch stack from step 5 (§2) but only its
  64-bit simulator slices, so it never replaces this step. Its CI wall time for
  the real OBAKitCore is unmeasured.
- *From step 5:* a **smoke test** on a watch simulator. A compile cannot catch
  dyld, `Info.plist`, or embedding failures; the launch crash in §2 built green.
  **`simctl launch` exits 0 and prints a PID even when dyld kills the app, and so
  does XcodeBuildMCP's `build_run_sim`,** so liveness must be asserted after a
  delay: `simctl install` and `simctl launch` on an *unpaired* watch simulator,
  sleep 8 s, then assert `kill -0 $pid` **and** that `simctl spawn … launchctl
  list` shows the bundle ID; on failure dump `log show` for "Library not loaded".
  Against the scratch replica this script passed on the fixed build and failed on
  the one missing `LD_RUNPATH_SEARCH_PATHS`, in about 30 s including a 19 s cold
  boot. [built] It does not exercise the widget appex.

Neither check covers **runtime on a 32-bit watch**, for which no simulator
exists. Step 5's exit criteria include a manual pass on a physical Series 6–8,
SE 2, or Ultra 1.

The runner is a GitHub-hosted image, not self-hosted. Its published manifest
lists the `watchos27.0` and `watchsimulator27.0` SDKs and installed watchOS 27.0
simulators [doc], so no platform download is needed today; add a guard like the
existing iOS one regardless. CI cost of these steps is unmeasured.

**Tests live where the logic lives, and the logic lives in core.** OBAKitWatch
holds views and thin observable models; anything with a branch in it goes in
OBAKitCore, where the existing iOS-hosted Swift Testing suite covers it. New
suites in OBAKitTests:

- `WatchSyncPayload`: round-trip; encoding byte-identical across two
  subprocesses; `revision` stable for equal content and different for changed
  content; unknown version ignored; corrupt payload keeps last good data; every
  integer field is `Int32`, and a payload built from a `Bookmark` whose
  `sortOrder` is `Int.max` still decodes
- `Bookmark` → `WatchBookmark` mapping, including flattening to display order
- `WatchSessionBridge`: each delegate method invoked from a background queue;
  stream fed A then B applies B; a forced re-send carries a nonce
- `BookmarkArrivalsLoader`: dedupe by stop; per-stop delivery; missing-stop
  versus other errors; and `BookmarkDataLoaderTests`' assertions passing unmodified
- Entry generation: one entry per departure boundary; reload-policy arithmetic;
  distinct entries for empty, failed, and no-region
- The region fallback rule; the four write triggers; region resolution from the
  app-group suite for a custom region; fallback to identifier lookup when the key
  is absent
- `.bookmarkGroupsDidChange` posted by each group mutator
- Decoding the REST fixtures with the seam 6 types; the SwiftLint rule

Because the bridge now lives in core, the earlier problem — a watch-side delegate
test that no iOS-hosted target could contain — no longer arises. An
`OBAKitWatchTests` target stays deferred until logic exists that cannot live in
core.

**Size.** App Store Connect's "Maximum uncompressed app size" for watchOS, all
versions, is **75 MB** ([doc], read from the page's raw HTML). The heavy
dependencies were measured in release, for device, stripped, per architecture
(`arm64_32`) [built]: GRDB 2.62 MB, SwiftProtobuf 1.50 MB, the generated
GTFS-realtime code plus GRDB usage 0.72 MB — **a floor of about 5 MB** with one
dynamic framework embedded once, against 10.8 MB if linked statically into both
the app and the widget (dead-stripping barely helps). All 13 locales of strings
total about 250 KB. OBAKitCore's own release size is unknown until the seams are
fixed and it links; step 5's exit criteria record the thinned app against a
**25 MB budget**, which the measured floor makes comfortable. Mergeable libraries
are not needed. Cold-launch time was not measured: a trivial scratch app in a
simulator says nothing about OBAKitCore. Separately, every `sources: ["."]` target
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
   uses neither API today. [code] Both compile in an iOS widget at the iOS 18.0
   target. [built] **Paired watches already show something today:** without the
   modifier the Smart Stack shows the Dynamic Island compact leading and trailing
   views and the app name, so review those first. `.small` swaps in the Lock
   Screen closure, so `TripLiveActivityCardView` (158 lines) needs an
   `activityFamily == .small` branch of roughly 40–60 lines, `isLuminanceReduced`
   handling, and previews. Push updates reach the watch with no extra tokens —
   "Live Activity updates are synchronized automatically" — though an over-budget
   update "may not immediately appear when someone's wrist is down." [doc] This
   is iOS-widget work only, needs no watch target, and depends on nothing below.
1. The six seam fixes, in place. Pure refactors; iOS behavior unchanged. Files
   that §1 assigns to the iOS tree (`LocationService+ProximityAlerts.swift`, the
   `RegionMonitoringLocationManager` protocol, the non-color half of
   `Theme.swift`) are created inside `OBAKitCore/` here and relocated in step 2,
   so this PR contains no directory moves.
2. Move files to `OBAKitCoreiOS/`; add `supportedDestinations` and the explicit
   `WATCHOS_DEPLOYMENT_TARGET`; update `extract_strings` and `.swiftlint.yml`;
   add the **device-architecture** CI compile step. This is the step where the
   second layer of compile errors, and any further 32-bit overflows, surface.
3. Extract the streaming `BookmarkArrivalsLoader`; `BookmarkDataLoader` and the
   iOS widget adopt it, with `BookmarkDataLoaderTests`' assertions unmodified; entries
   carry their data; extract the `userUUID` helper; the app persists the resolved
   `Region` to the app-group suite on its four triggers and the iOS widget reads
   it, falling back to identifier lookup. Fixes the iOS widget's six-hour
   staleness and its custom-region gap.
4. `WatchSyncPayload`, `WatchBookmark`, and `WatchSessionBridge` in core; the
   phone-side sender with its debounce and forced re-sends;
   `.bookmarkGroupsDidChange`. With no watch app installed the bridge's gating
   makes this inert, so it is safe to land ahead of step 5.
5. OBAKitWatch and WatchApp — bookmarks, arrivals, nearby stops — with the
   receiver, `requestLocation()` and `desiredAccuracy`, the configurable timeout,
   background refresh and its arrivals cache, the `CoreAppConfig` switches,
   `watch.yml` and `generate_project --no-watch`, the identity check, the launch
   smoke test, the size measurement, and a manual pass on a 32-bit watch.
6. OBAWatchWidget: accessory families, entry generation, `relevance()`.

Step 0 is independent and gets its own short plan; it can land first. Steps 1–3
make OBAKitCore watch-ready, improve the iOS widget, and stand on their own even
if the watch app slips. **The first main implementation plan covers steps 1–3.**
Steps 4–6 get follow-on plans, written once the core port has shown what the
second layer of compile errors looks like.

**Revised 2026-09-22 (rev. 3), after steps 1–3 were implemented.** Steps 4 and
5 above are superseded by the sequencing in
[`2026-09-22-watchos-mvp-app-design.md`](2026-09-22-watchos-mvp-app-design.md):
step 4 is an MVP watch app (targets, opt-in, nearby stops and arrivals, launch
smoke test) that builds no `CoreApplication`; step 5 is the sync work listed
under step 4 above plus the Bookmarks tab, the synced-region fallback,
background refresh, the configurable timeout, and the `CoreAppConfig` switches
if a watch feature ever needs them. Step 6 is unchanged.

## Still unknown

- **Runtime behavior on a 32-bit watch.** No 32-bit simulator exists. Needs a
  physical Series 6–8, SE 2, or Ultra 1. The `Int` audit was grep-based, and the
  decode failure was demonstrated with `Int32` on a 64-bit host.
- **The real-device size ceiling for `updateApplicationContext`.** Needs a paired
  iPhone and Apple Watch and a size ladder. Design to stay under 64 KB.
- Whether identical-context suppression and no-coalescing-when-reachable, both
  observed in the simulator, hold on hardware; and whether `applicationContext`
  and that suppression are tracked per watch after a watch switch.
- **What WidgetKit does with timeline entries under 5 minutes apart on watchOS,**
  and how `Text(timerInterval:)` renders in `accessoryInline` and
  `accessoryCircular`. Needs a widget placed on a face or in the Smart Stack by
  hand, or a device.
- Whether `RelevantContext.location` works without `NSWidgetWantsLocation`.
- Bundle-ID prefix enforcement at device install and App Store Connect.
- The release, thinned size of OBAKitCore itself, its cold-launch cost, and the
  CI wall time of the device-architecture compile.
- The second layer of watchOS compile errors.
- The watchOS widget-extension memory ceiling (a ~30 MB figure is [recalled]).

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

**Keep WatchConnectivity out of OBAKitCore,** with a sender delegate in OBAKit
and a receiver delegate in OBAKitWatch. The original design. It keeps core free
of a framework only two clients use, but duplicates the one piece of code that
compiles clean and traps at runtime, and the watch-side copy cannot be
unit-tested without standing up a watchOS test host. Rejected in favor of one
shared bridge.

**CloudKit or `NSUbiquitousKeyValueStore` as the sync channel.** Syncs without
the phone present, but requires an iCloud entitlement and container per agency
and an iCloud-signed-in user. Deferred behind the `WatchSyncTransport` seam.

**Dependent watch app** (phone fetches, watch displays). Needs only core's
models on the watch, but the app is useless out of phone range and it contradicts
Apple's guidance. **Watch-only app.** Discards the user's existing bookmarks and
the white-label pairing with each agency's iOS app.
