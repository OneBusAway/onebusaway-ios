# GTFS-Flex iOS (OBAKit) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface maglev's `/api/ondemand` on-demand (GTFS-Flex) services in the iOS app: zone polygons on the map, an on-demand section on the stop page, an agency browse list, and a service page that tells the rider when the service runs and by when they must book.

**Architecture:** OBAKitCore gains the wire models (`OnDemandService` and its four new reference types), three `RESTAPIService` calls, a process-wide `OnDemandSupport` probe cache keyed by server base URL, the normative `BookingDeadlineEvaluator` (verified against the shared `flex-booking-vectors.json`), and an `OnDemandServiceSummary` presenter. OBAKit adds an `OnDemandMapLayer` conforming to the existing `MapLayer` protocol, a SwiftUI `OnDemandServiceView` hosted for UIKit routing, a stop-page section in both stop-page implementations, and an Agencies action-sheet entry. Everything network-facing is tested against JSON captured from a real maglev server running the flex test feeds.

**Tech Stack:** Swift 6 language mode (strict concurrency), SwiftUI + MapKit (`Map`/`MapPolygon`, `MKPolygon`), Swift Testing, XcodeGen, SwiftLint 0.65.1, `Synchronization.Mutex`.

**Spec:** `/private/tmp/claude-501/-Users-aaron-repos-onebusaway-maglev/215fa362-5529-43a3-9cb6-317b7d70341f/scratchpad/spec.md` (§0, §1, §6, §7, §9) and the wire contract `/private/tmp/claude-501/-Users-aaron-repos-onebusaway-maglev/215fa362-5529-43a3-9cb6-317b7d70341f/scratchpad/wiki/GTFS-Flex-Support.md` (§2.1, §2.2, §2.4, §2.5, §3, §3.1, §3.3, §3.4). Copy both into `docs/superpowers/specs/2026-09-24-gtfs-flex-ios-spec.md` and `docs/superpowers/specs/2026-09-24-gtfs-flex-wiki.md` in Task 0 so they travel with the branch. The JSON shapes in wiki §3.4 are normative; the booking algorithm in spec §6 is normative.

## Global Constraints

- Worktree `/Users/aaron/repos/onebusaway/.worktrees/ios-gtfs-flex`, branch `gtfs-flex` off `origin/main` 68925b53. Every `cd` below means this directory.
- iOS deployment target **18.0**; watchOS deployment target 11.0 for OBAKitCore (unchanged).
- **Swift 6 strict concurrency.** OBAKitCore is `nonisolated` by default; OBAKit is `MainActor` by default. The five concurrency diagnostic groups are errors.
- **OBAKitCore has no UIKit** and must compile for watchOS: `xcodebuild build -scheme OBAKitCore -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO`. Never decode an epoch value as `Int` in OBAKitCore — use `Int64` or `Date` (SwiftLint `epoch_decoded_as_int` is an error). Seconds-since-midnight (`GTFSTimeOfDay.seconds`) is `Int` on purpose: it never exceeds ~200,000.
- **Every new `OBALoc` key is added to all 13 locale files** of the framework that declares it (`ar en es fil fr it ko pl pt-BR ru vi zh-Hans zh-Hant`), with the English value in every locale. `LocalizationTests` fails otherwise. All keys in this plan live in `OBAKit/Strings/*.lproj/Localizable.strings`; OBAKitCore gains no strings.
- **Regenerate the Xcode project** with `scripts/generate_project OneBusAway` after adding files (required for `OBAKitCoreiOS/`, which is an XcodeGen group; every other directory is a synced folder, but regenerating is cheap and the standard command below always does it). `--no-watch` is acceptable on a machine without the watchOS platform.
- **Tests are Swift Testing**: `@Suite(.serialized)`, `@Test`, `#expect`, subclassing `OBATestCase` (override `init() async throws`, call `try await super.init()`). Fixtures load through `Fixtures.loadData(file:)` from `OBAKitTests/fixtures/`. Network stubs go through `MockDataLoader`; the REST service under test is `restService` (base URL `https://www.example.com`, region identifier `pugetSoundRegionIdentifier == 1`).
- `SwiftLint` clean: `scripts/swiftlint.sh` (or `swiftlint lint`). No `OneBusAway` string literal in framework code (`hardcoded_app_name` is an error).
- **Commit style:** imperative sentence case, no conventional-commit prefixes, no `Co-Authored-By` lines. Example: `Add on-demand service models`.
- No `TODO`/placeholder code; every branch introduced gets a test in the task that introduces it.
- Do not modify `Apps/Shared/app_shared.yml`, `OBAKitCore/project.yml` or `OBAKit/project.yml`.

### Standard commands

Run one suite (substitute `SUITE_NAME`):

```bash
cd /Users/aaron/repos/onebusaway/.worktrees/ios-gtfs-flex && \
scripts/generate_project OneBusAway && \
SIMULATOR_UDID=$(scripts/resolve_simulator_udid) && \
set -o pipefail && \
xcodebuild build-for-testing -project OBAKit.xcodeproj -scheme App \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" -quiet 2>&1 | tail -30 && \
xcodebuild test-without-building -project OBAKit.xcodeproj -scheme App \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -only-testing:OBAKitTests/SUITE_NAME 2>&1 | tail -40
```

The whole unit suite: same command with `-only-testing:OBAKitTests`.

watchOS portability check for OBAKitCore (run after every task that touches `OBAKitCore/`):

```bash
cd /Users/aaron/repos/onebusaway/.worktrees/ios-gtfs-flex && set -o pipefail && \
xcodebuild build -project OBAKit.xcodeproj -scheme OBAKitCore \
  -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO -quiet 2>&1 | tail -20
```

Lint: `cd /Users/aaron/repos/onebusaway/.worktrees/ios-gtfs-flex && swiftlint lint --quiet | tail -30`

## Review Focus

1. **`serviceArea.geometry` omitted** (`geometryDetail=none`, or a server that simplifies a zone away): `ServiceArea.polygons` must decode to `[]`, the map layer must draw nothing for that area and still place its marker at the bbox centre, and the service page must hide its map. Pinned in Task 1 (`Service area without geometry decodes with no polygons`) and Task 8 (`Service with no polygons renders no map section` via `OnDemandServiceView.showsMap`).
2. **Unknown enum strings from a newer server** (`serviceKind: "curbToCurb"`, `matchReason: "somethingNew"`): decode to `.unknown`, never throw — one unknown value must not blank the whole list. Pinned in Task 1 (`Unknown service kind and match reason fall back to unknown`).
3. **A rule whose `pickupBookingRuleId` is not in `references.bookingRules`**: this is not "no notice required"; the presenter must report `.unknown` (no deadline line) rather than tell the rider they can book any time. Pinned in Task 7 (`Dangling booking rule id yields unknown`).
4. **Support is per server, not global**: marking `https://a.example.com` as lacking `/api/ondemand` must not hide the layer on `https://b.example.com` after a region switch. Pinned in Task 5 (`Absence is recorded per base URL`).
5. **MultiPolygon with holes**: ring 0 is the exterior, rings 1… are holes; the MKPolygon must carry them as `interiorPolygons` or the fill renders inverted. Pinned in Task 1 (`MultiPolygon with a hole decodes exterior and interior rings`) and Task 8 (`MKPolygon carries interior rings`).

---

## File Structure

**OBAKitCore (portable, no UIKit)**
- Create `OBAKitCore/Models/REST/OnDemand/GTFSTimeOfDay.swift` — `"HH:MM:SS"` (may exceed 24 h) value type.
- Create `OBAKitCore/Models/REST/OnDemand/ServiceDate.swift` — `"YYYY-MM-DD"` value type and `Weekday`.
- Create `OBAKitCore/Models/REST/OnDemand/ServiceKind.swift` — `ServiceKind`, `MatchReason` enums with `.unknown` fallback.
- Create `OBAKitCore/Models/REST/OnDemand/OnDemandBookingRule.swift`, `OnDemandCalendar.swift`, `OnDemandLocationGroup.swift`, `ServiceArea.swift`, `AvailabilityRule.swift`, `OnDemandService.swift` — wire models (wiki §3.4).
- Modify `OBAKitCore/Models/REST/References/References.swift` — four new arrays + finders.
- Modify `OBAKitCore/Models/REST/References/Stop.swift`, `Route.swift` — `onDemandServiceIDs`.
- Create `OBAKitCore/Models/REST/OnDemand/OnDemandGeometryDetail.swift` — `geometryDetail` query enum.
- Modify `OBAKitCore/Network/RESTAPIURLBuilder.swift` — three URL builders.
- Create `OBAKitCore/Network/RESTAPIService/RESTAPIService+OnDemand.swift` — three service calls; the `services-for-location` probe records absence.
- Create `OBAKitCore/Network/OnDemandSupport.swift` — `Sendable` class over `Mutex<Set<String>>`.
- Modify `OBAKitCore/Network/RESTAPIService/RESTAPIService.swift` — inject `OnDemandSupport`, expose `baseURL`.
- Create `OBAKitCore/Models/OnDemand/BookingDeadlineEvaluator.swift` — spec §6 algorithm.
- Create `OBAKitCore/Models/OnDemand/OnDemandServiceSummary.swift` — presenter (formatted, locale-aware pieces; no strings of its own).

**OBAKit (UI, MainActor)**
- Create `OBAKit/Strings/Strings+OnDemand.swift` — every on-demand `OBALoc` key, once.
- Create `OBAKit/OnDemand/ServiceArea+MapKit.swift` — `ServiceArea.mkPolygons` shared by the map layer and the service page.
- Create `OBAKit/OnDemand/OnDemandServiceView.swift`, `OnDemandServiceViewController.swift` — the service page and its UIKit host.
- Modify `OBAKit/ViewRouting/Router.swift` — `navigateTo(onDemandService:from:)`.
- Create `OBAKit/Mapping/Layers/OnDemand/OnDemandMapLayer.swift`, `OnDemandZoneAnnotation.swift`; modify `MapLayerRegistrar.swift`, `MapViewController+MapLayers.swift`.
- Create `OBAKit/Stops/StopPage/OnDemandServicesSection.swift`; modify `StopViewModel.swift`, `StopPageView.swift` (handler struct), `StopPageActionPresenter.swift`, `StopPageViewController.swift`, `Shared/StopDeparturesSections.swift`, `Shared/StopDeparturesBuilder.swift`, `StopViewController.swift`.
- Create `OBAKit/OnDemand/OnDemandServicesListView.swift`, `OnDemandServicesListViewController.swift`; modify `OBAKit/Agencies/AgenciesViewController.swift`.

**Tests (`OBAKitTests/`)**
- `fixtures/` — ten captured JSON files + `flex-booking-vectors.json` (Task 0).
- `Modeling/Model Unit Tests/OnDemandModelTests.swift`, `OnDemandReferencesTests.swift`, `StopTests.swift` (+cases), `RouteOnDemandPointerTests.swift`.
- `Network/RESTAPIURLBuilderTests.swift` (+cases), `Modeling/REST Model Service Tests/OnDemandModelOperationTests.swift`, `Network/OnDemandSupportTests.swift`.
- `OnDemand/BookingDeadlineEvaluatorTests.swift`, `OnDemand/OnDemandServiceSummaryTests.swift`, `OnDemand/OnDemandServiceViewTests.swift`, `OnDemand/OnDemandServicesListTests.swift`.
- `Mapping/OnDemandMapLayerTests.swift`, `Mapping/MapLayerRegistrarTests.swift` (+case).
- `ViewModels/StopViewModelTests.swift` (+cases), `Stops/StopDeparturesSectionsOnDemandTests.swift`.

---

### Task 0: Capture fixtures from a running maglev

**Precondition:** the maglev worktree at `/Users/aaron/repos/onebusaway/maglev` (branch `gtfs-flex`) must already serve `/api/ondemand/*` and contain `testdata/flex-booking-vectors.json`, `testdata/alexandria-flex.zip`, `testdata/charlevoix-flex.zip`. If `grep -n ondemand /Users/aaron/repos/onebusaway/maglev/internal/restapi/routes.go` prints nothing, stop: the maglev plan has not landed and these fixtures cannot be captured yet.

**Files:**
- Create: `OBAKitTests/fixtures/ondemand_service_alexandria.json`
- Create: `OBAKitTests/fixtures/ondemand_services_for_location_point.json`
- Create: `OBAKitTests/fixtures/ondemand_services_for_location_viewport.json`
- Create: `OBAKitTests/fixtures/ondemand_services_for_agency_alexandria.json`
- Create: `OBAKitTests/fixtures/ondemand_services_for_agency_charlevoix.json`
- Create: `OBAKitTests/fixtures/stop_alexandria_4258639.json` (stop **without** a pointer, from the flex server)
- Create: `OBAKitTests/fixtures/stop_with_ondemand_pointer.json` (Charlevoix `CC_CC_Ironton_Ferry_West`)
- Create: `OBAKitTests/fixtures/route_with_ondemand_pointer.json` (Charlevoix `CC_CC3`)
- Create: `OBAKitTests/fixtures/flex-booking-vectors.json` (verbatim copy)
- Create: `docs/superpowers/specs/2026-09-24-gtfs-flex-ios-spec.md`, `docs/superpowers/specs/2026-09-24-gtfs-flex-wiki.md` (copies of the two inputs)

**Interfaces:**
- Consumes: maglev `/api/ondemand/service/{id}.json`, `/api/ondemand/services-for-location.json`, `/api/ondemand/services-for-agency/{id}.json`, `/api/where/stop/{id}.json`, `/api/where/route/{id}.json`.
- Produces: the fixture file names above; every later test loads them by these exact names. Expected values (from wiki §3.4 worked example): service id `"5088_77652"`, `serviceKind` `"zone"`, two rules (`05:00:00–24:50:00` / drop-off `25:00:00` on `5088_c_71675_b_85952_d_63`, `07:00:00–24:50:00` / `25:00:00` on `5088_c_71675_b_85952_d_64`), booking rule `5088_booking_route_77652` with `phoneNumber` `"703-746-5222"`, `priorNoticeLastDay` 1, `priorNoticeLastTime` `"17:00:00"`, `priorNoticeStartDay` 14, calendar `…d_63` days `["mon","tue","wed","thu","fri","sat"]`, `…d_64` days `["sun"]`, both `2025-12-01`…`2026-12-01`, area `5088_area_1449` bbox `[-77.5372039, 38.617508, -76.9092198, 39.057831]`, agency timezone `"America/Los_Angeles"`. Charlevoix: four services `CC_CC1`, `CC_CC2_med`, `CC_CC3` (`stopGroup`, one location group of two stops), `CC_CC4`; stop `CC_CC_Ironton_Ferry_West` and route `CC_CC3` carry `onDemandServiceIds: ["CC_CC3"]`.

- [x] **Step 1: Build maglev and write the Alexandria config**

```bash
cd /Users/aaron/repos/onebusaway/maglev && make build && \
mkdir -p /private/tmp/claude-501/-Users-aaron-repos-onebusaway-maglev/215fa362-5529-43a3-9cb6-317b7d70341f/scratchpad/flexcap && \
cat > /private/tmp/claude-501/-Users-aaron-repos-onebusaway-maglev/215fa362-5529-43a3-9cb6-317b7d70341f/scratchpad/flexcap/alexandria.json <<'EOF'
{
  "port": 4000,
  "env": "development",
  "api-keys": ["test"],
  "rate-limit": 1000,
  "log-level": "info",
  "gtfs-static-feed": { "url": "testdata/alexandria-flex.zip" },
  "gtfs-rt-feeds": [],
  "data-path": "/private/tmp/claude-501/-Users-aaron-repos-onebusaway-maglev/215fa362-5529-43a3-9cb6-317b7d70341f/scratchpad/flexcap/alexandria.db"
}
EOF
sed 's/alexandria/charlevoix/g' /private/tmp/claude-501/-Users-aaron-repos-onebusaway-maglev/215fa362-5529-43a3-9cb6-317b7d70341f/scratchpad/flexcap/alexandria.json \
  > /private/tmp/claude-501/-Users-aaron-repos-onebusaway-maglev/215fa362-5529-43a3-9cb6-317b7d70341f/scratchpad/flexcap/charlevoix.json
```

- [x] **Step 2: Run maglev on Alexandria and capture six responses**

Run the server in the background (`bin/maglev --config <path>` — check `bin/maglev --help` for the flag name if it differs), wait for `curl -sf http://localhost:4000/healthz`, then:

```bash
cd /Users/aaron/repos/onebusaway/maglev && \
( bin/maglev --config /private/tmp/claude-501/-Users-aaron-repos-onebusaway-maglev/215fa362-5529-43a3-9cb6-317b7d70341f/scratchpad/flexcap/alexandria.json > /private/tmp/claude-501/-Users-aaron-repos-onebusaway-maglev/215fa362-5529-43a3-9cb6-317b7d70341f/scratchpad/flexcap/alexandria.log 2>&1 & echo $! > /private/tmp/claude-501/-Users-aaron-repos-onebusaway-maglev/215fa362-5529-43a3-9cb6-317b7d70341f/scratchpad/flexcap/pid ) && \
for i in $(seq 1 60); do curl -sf http://localhost:4000/healthz >/dev/null && break; sleep 1; done && \
F=/Users/aaron/repos/onebusaway/.worktrees/ios-gtfs-flex/OBAKitTests/fixtures && \
curl -sf 'http://localhost:4000/api/ondemand/service/5088_77652.json?key=test' > "$F/ondemand_service_alexandria.json" && \
curl -sf 'http://localhost:4000/api/ondemand/services-for-location.json?key=test&lat=38.83&lon=-77.05&radius=600' > "$F/ondemand_services_for_location_point.json" && \
curl -sf 'http://localhost:4000/api/ondemand/services-for-location.json?key=test&lat=38.83&lon=-77.05&latSpan=0.1&lonSpan=0.1' > "$F/ondemand_services_for_location_viewport.json" && \
curl -sf 'http://localhost:4000/api/ondemand/services-for-agency/5088.json?key=test' > "$F/ondemand_services_for_agency_alexandria.json" && \
curl -sf 'http://localhost:4000/api/where/stop/5088_4258639.json?key=test' > "$F/stop_alexandria_4258639.json" && \
kill "$(cat /private/tmp/claude-501/-Users-aaron-repos-onebusaway-maglev/215fa362-5529-43a3-9cb6-317b7d70341f/scratchpad/flexcap/pid)"
```

- [x] **Step 3: Run maglev on Charlevoix and capture three responses**

```bash
cd /Users/aaron/repos/onebusaway/maglev && \
( bin/maglev --config /private/tmp/claude-501/-Users-aaron-repos-onebusaway-maglev/215fa362-5529-43a3-9cb6-317b7d70341f/scratchpad/flexcap/charlevoix.json > /private/tmp/claude-501/-Users-aaron-repos-onebusaway-maglev/215fa362-5529-43a3-9cb6-317b7d70341f/scratchpad/flexcap/charlevoix.log 2>&1 & echo $! > /private/tmp/claude-501/-Users-aaron-repos-onebusaway-maglev/215fa362-5529-43a3-9cb6-317b7d70341f/scratchpad/flexcap/pid ) && \
for i in $(seq 1 60); do curl -sf http://localhost:4000/healthz >/dev/null && break; sleep 1; done && \
F=/Users/aaron/repos/onebusaway/.worktrees/ios-gtfs-flex/OBAKitTests/fixtures && \
curl -sf 'http://localhost:4000/api/ondemand/services-for-agency/CC.json?key=test' > "$F/ondemand_services_for_agency_charlevoix.json" && \
curl -sf 'http://localhost:4000/api/where/stop/CC_CC_Ironton_Ferry_West.json?key=test' > "$F/stop_with_ondemand_pointer.json" && \
curl -sf 'http://localhost:4000/api/where/route/CC_CC3.json?key=test' > "$F/route_with_ondemand_pointer.json" && \
kill "$(cat /private/tmp/claude-501/-Users-aaron-repos-onebusaway-maglev/215fa362-5529-43a3-9cb6-317b7d70341f/scratchpad/flexcap/pid)" && \
cp /Users/aaron/repos/onebusaway/maglev/testdata/flex-booking-vectors.json "$F/flex-booking-vectors.json"
```

(`agency.txt` in `charlevoix-flex.zip` declares `agency_id` `CC`; `stops.txt` ids are `CC_Ironton_Ferry_West`/`CC_Ironton_Ferry_East`, so the combined ids are `CC_CC_Ironton_Ferry_West`. The route is `CC3` → `CC_CC3`.)

- [x] **Step 4: Verify the fixtures carry the contract values**

```bash
cd /Users/aaron/repos/onebusaway/.worktrees/ios-gtfs-flex/OBAKitTests/fixtures && \
jq -r '.data.entry | "\(.id) \(.serviceKind) rules=\(.rules|length)"' ondemand_service_alexandria.json && \
jq -r '.data.references.bookingRules[0] | "\(.phoneNumber) lastDay=\(.priorNoticeLastDay) lastTime=\(.priorNoticeLastTime) startDay=\(.priorNoticeStartDay)"' ondemand_service_alexandria.json && \
jq -c '.data.references.serviceAreas[0].bbox' ondemand_service_alexandria.json && \
jq -c '[.data.references.calendars[] | {id, days}]' ondemand_service_alexandria.json && \
jq -r '.data.list[0].matchReason' ondemand_services_for_location_point.json ondemand_services_for_location_viewport.json && \
jq -r '[.data.list[] | "\(.id):\(.serviceKind)"] | join(" ")' ondemand_services_for_agency_charlevoix.json && \
jq -c '.data.entry.onDemandServiceIds' stop_with_ondemand_pointer.json route_with_ondemand_pointer.json && \
jq -c '.data.entry | has("onDemandServiceIds")' stop_alexandria_4258639.json && \
jq -r '.vectors | length' flex-booking-vectors.json
```

Expected, line by line: `5088_77652 zone rules=2`; `703-746-5222 lastDay=1 lastTime=17:00:00 startDay=14`; `[-77.5372039,38.617508,-76.9092198,39.057831]`; two calendars (`…d_63` Mon–Sat, `…d_64` `["sun"]`); `areaContainsPoint` then `areaIntersectsViewport`; `CC_CC1:zone CC_CC2_med:zoneToZone CC_CC3:stopGroup CC_CC4:zone`; `["CC_CC3"]` twice; `false`; a vector count of at least 12. If any line differs, the maglev branch is not at the contract; do not "fix" the JSON by hand.

- [x] **Step 5: Copy the spec and wiki next to the plan**

```bash
cd /Users/aaron/repos/onebusaway/.worktrees/ios-gtfs-flex && mkdir -p docs/superpowers/specs && \
cp /private/tmp/claude-501/-Users-aaron-repos-onebusaway-maglev/215fa362-5529-43a3-9cb6-317b7d70341f/scratchpad/spec.md docs/superpowers/specs/2026-09-24-gtfs-flex-ios-spec.md && \
cp /private/tmp/claude-501/-Users-aaron-repos-onebusaway-maglev/215fa362-5529-43a3-9cb6-317b7d70341f/scratchpad/wiki/GTFS-Flex-Support.md docs/superpowers/specs/2026-09-24-gtfs-flex-wiki.md
```

- [x] **Step 6: Run the existing test suite once to prove the fixtures broke nothing**

Run the standard command with `-only-testing:OBAKitTests/StopsModelOperationTests`. Expected: PASS.

- [x] **Step 7: Commit**

```bash
cd /Users/aaron/repos/onebusaway/.worktrees/ios-gtfs-flex && \
git add OBAKitTests/fixtures/ondemand_*.json OBAKitTests/fixtures/stop_alexandria_4258639.json OBAKitTests/fixtures/stop_with_ondemand_pointer.json OBAKitTests/fixtures/route_with_ondemand_pointer.json OBAKitTests/fixtures/flex-booking-vectors.json docs/superpowers/specs/2026-09-24-gtfs-flex-ios-spec.md docs/superpowers/specs/2026-09-24-gtfs-flex-wiki.md docs/superpowers/plans/2026-09-24-gtfs-flex-ios.md && \
git commit -m "Add on-demand API fixtures captured from maglev"
```

---

### Task 1: OBAKitCore on-demand models

**Files:**
- Create: `OBAKitCore/Models/REST/OnDemand/GTFSTimeOfDay.swift`
- Create: `OBAKitCore/Models/REST/OnDemand/ServiceDate.swift`
- Create: `OBAKitCore/Models/REST/OnDemand/ServiceKind.swift`
- Create: `OBAKitCore/Models/REST/OnDemand/OnDemandBookingRule.swift`
- Create: `OBAKitCore/Models/REST/OnDemand/OnDemandCalendar.swift`
- Create: `OBAKitCore/Models/REST/OnDemand/OnDemandLocationGroup.swift`
- Create: `OBAKitCore/Models/REST/OnDemand/ServiceArea.swift`
- Create: `OBAKitCore/Models/REST/OnDemand/AvailabilityRule.swift`
- Create: `OBAKitCore/Models/REST/OnDemand/OnDemandService.swift`
- Test: `OBAKitTests/Modeling/Model Unit Tests/OnDemandModelTests.swift`

**Interfaces:**
- Consumes: `References` (unchanged until Task 2 — `loadReferences` uses only `routeWithID`/`agencyWithID` here; the four new finders are added in Task 2 and `OnDemandService.loadReferences` is completed there), `String.nilifyBlankValue`, `HasReferences`.
- Produces (all `public`, all in module `OBAKitCore`):
  - `struct GTFSTimeOfDay: Hashable, Comparable, Sendable, Decodable, CustomStringConvertible { let seconds: Int; init(seconds: Int); init?(_ string: String); static let midnight; static let endOfServiceDay /* 86_400 */; var description: String /* "HH:MM:SS" */ }`
  - `struct ServiceDate: Hashable, Comparable, Sendable, Decodable, CustomStringConvertible { let year: Int, month: Int, day: Int; init(year:month:day:); init?(_ string: String); var description /* "YYYY-MM-DD" */ }`
  - `enum Weekday: String, CaseIterable, Sendable { case mon, tue, wed, thu, fri, sat, sun; init(calendarWeekday: Int) /* 1 = Sunday … 7 = Saturday */; var calendarWeekday: Int }`
  - `enum ServiceKind: String, Decodable, Sendable { case zone, zoneToZone, stopGroup, deviatedRoute, unknown }` (unknown fallback)
  - `enum MatchReason: String, Decodable, Sendable { case areaContainsPoint, stopWithinRadius, areaNearby, areaIntersectsViewport, stopWithinViewport, unknown }` (unknown fallback)
  - `struct OnDemandBookingRule: Decodable, Identifiable, Hashable, Sendable { id: String; bookingType: Int; priorNoticeDurationMin: Int?; priorNoticeDurationMax: Int?; priorNoticeLastDay: Int?; priorNoticeLastTime: GTFSTimeOfDay?; priorNoticeStartDay: Int?; priorNoticeStartTime: GTFSTimeOfDay?; priorNoticeCalendarID: String?; message: String?; pickupMessage: String?; dropOffMessage: String?; phoneNumber: String?; infoURL: URL?; bookingURL: URL? }`
  - `struct OnDemandCalendar: Decodable, Identifiable, Hashable, Sendable { id: String; days: [Weekday]; startDate: ServiceDate; endDate: ServiceDate; exceptedDates: [ServiceDate] }`
  - `struct OnDemandLocationGroup: Decodable, Identifiable, Hashable, Sendable { id: String; name: String?; stopIDs: [String] }`
  - `struct BoundingBox: Hashable, Sendable { minLongitude, minLatitude, maxLongitude, maxLatitude: Double; var center: CLLocationCoordinate2D }`
  - `struct ServiceArea: Decodable, Identifiable, Sendable { id: String; name: String?; areaDescription: String?; bbox: BoundingBox; polygons: [[[CLLocationCoordinate2D]]] /* polygons[p][ring][i]; ring 0 exterior */; var hasGeometry: Bool; distanceToArea: Double?; nearestPointOnBoundary: CLLocationCoordinate2D? }`
  - `struct AvailabilityRule: Decodable, Hashable, Sendable { fromIDs: [String]; toIDs: [String]; startPickupTime: GTFSTimeOfDay?; endPickupTime: GTFSTimeOfDay?; endDropOffTime: GTFSTimeOfDay?; calendarIDs: [String]; pickupType: Int; dropOffType: Int; pickupBookingRuleID: String?; dropOffBookingRuleID: String?; safeDurationFactor: Double?; safeDurationOffset: Double?; public init(fromIDs:toIDs:startPickupTime:endPickupTime:endDropOffTime:calendarIDs:pickupType:dropOffType:pickupBookingRuleID:dropOffBookingRuleID:safeDurationFactor:safeDurationOffset:) }`
  - `final class OnDemandService: NSObject, Identifiable, Decodable, HasReferences, @unchecked Sendable { id, agencyID: String; routeID: String?; name: String; serviceKind: ServiceKind; serviceDescription: String?; url: URL?; rules: [AvailabilityRule]; matchReason: MatchReason?; private(set) var route: Route?; agency: Agency?; areas: [ServiceArea]; locationGroups: [OnDemandLocationGroup]; bookingRules: [OnDemandBookingRule]; calendars: [OnDemandCalendar]; regionIdentifier: Int?; func bookingRule(id: String?) -> OnDemandBookingRule?; var timeZone: TimeZone? }`

- [x] **Step 1: Write the failing tests**

Create `OBAKitTests/Modeling/Model Unit Tests/OnDemandModelTests.swift`:

```swift
//
//  OnDemandModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

@Suite(.serialized)
final class OnDemandModelTests: OBATestCase {

    private func decodeService(_ json: String) throws -> OnDemandService {
        try JSONDecoder.RESTDecoder().decode(OnDemandService.self, from: Data(json.utf8))
    }

    // MARK: - GTFSTimeOfDay

    @Test func `Time of day parses plain and post-midnight values`() {
        #expect(GTFSTimeOfDay("05:00:00")?.seconds == 18_000)
        #expect(GTFSTimeOfDay("24:50:00")?.seconds == 89_400)
        #expect(GTFSTimeOfDay("25:00:00")?.seconds == 90_000)
        #expect(GTFSTimeOfDay("7:05:09")?.seconds == 25_509)
        #expect(GTFSTimeOfDay("05:00") == nil)
        #expect(GTFSTimeOfDay("05:60:00") == nil)
        #expect(GTFSTimeOfDay("abc") == nil)
        #expect(GTFSTimeOfDay(seconds: 89_400).description == "24:50:00")
        #expect(GTFSTimeOfDay.midnight < GTFSTimeOfDay.endOfServiceDay)
    }

    // MARK: - ServiceDate / Weekday

    @Test func `Service date parses and compares`() {
        let date = ServiceDate("2026-03-11")
        #expect(date == ServiceDate(year: 2026, month: 3, day: 11))
        #expect(date?.description == "2026-03-11")
        #expect(ServiceDate("2026-3-11") == nil)
        #expect(ServiceDate("20260311") == nil)
        #expect(ServiceDate(year: 2026, month: 3, day: 11)! < ServiceDate(year: 2026, month: 12, day: 1)!)
        #expect(Weekday(calendarWeekday: 1) == .sun)
        #expect(Weekday(calendarWeekday: 7) == .sat)
        #expect(Weekday.mon.calendarWeekday == 2)
    }

    // MARK: - Enums

    @Test func `Unknown service kind and match reason fall back to unknown`() throws {
        let service = try decodeService("""
        {"id":"x_1","agencyId":"x","routeId":null,"name":"X","serviceKind":"curbToCurb",
         "description":null,"url":null,"rules":[],"matchReason":"somethingNew"}
        """)
        #expect(service.serviceKind == .unknown)
        #expect(service.matchReason == .unknown)
        #expect(service.routeID == nil)
        #expect(service.rules.isEmpty)
    }

    // MARK: - Entry decoding (wiki §3.4 worked example)

    @Test func `Alexandria service decodes`() throws {
        let data = Fixtures.loadData(file: "ondemand_service_alexandria.json")
        let response = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<OnDemandService>.self, from: data)
        let service = response.entry

        #expect(service.id == "5088_77652")
        #expect(service.agencyID == "5088")
        #expect(service.routeID == "5088_77652")
        #expect(service.name == "DOT Paratransit")
        #expect(service.serviceKind == .zone)
        #expect(service.serviceDescription == nil)
        #expect(service.url == nil)
        #expect(service.matchReason == nil)
        #expect(service.rules.count == 2)

        let first = service.rules[0]
        #expect(first.fromIDs == ["5088_area_1449"])
        #expect(first.toIDs == ["5088_area_1449"])
        #expect(first.startPickupTime == GTFSTimeOfDay("05:00:00"))
        #expect(first.endPickupTime == GTFSTimeOfDay("24:50:00"))
        #expect(first.endDropOffTime == GTFSTimeOfDay("25:00:00"))
        #expect(first.calendarIDs == ["5088_c_71675_b_85952_d_63"])
        #expect(first.pickupType == 2)
        #expect(first.dropOffType == 2)
        #expect(first.pickupBookingRuleID == "5088_booking_route_77652")
        #expect(first.dropOffBookingRuleID == "5088_booking_route_77652")
        #expect(first.safeDurationFactor == 1.0)
        #expect(first.safeDurationOffset == 0.0)

        #expect(service.rules[1].startPickupTime == GTFSTimeOfDay("07:00:00"))
        #expect(service.rules[1].calendarIDs == ["5088_c_71675_b_85952_d_64"])
    }

    @Test func `Service area decodes bbox and polygon geometry`() throws {
        let data = Fixtures.loadData(file: "ondemand_service_alexandria.json")
        let container = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let areasJSON = try JSONSerialization.data(withJSONObject: ((container["data"] as! [String: Any])["references"] as! [String: Any])["serviceAreas"]!)
        let areas = try JSONDecoder().decode([ServiceArea].self, from: areasJSON)

        #expect(areas.count == 1)
        let area = areas[0]
        #expect(area.id == "5088_area_1449")
        #expect(area.name == nil)
        #expect(area.areaDescription == nil)
        expectClose(area.bbox.minLongitude, -77.5372039)
        expectClose(area.bbox.minLatitude, 38.617508)
        expectClose(area.bbox.maxLongitude, -76.9092198)
        expectClose(area.bbox.maxLatitude, 39.057831)
        #expect(area.hasGeometry)
        #expect(area.polygons.count == 1)
        #expect(area.polygons[0].count == 1, "Alexandria's zone has no holes")
        #expect(area.polygons[0][0].count > 100)
        #expect(area.distanceToArea == nil)
        #expect(area.nearestPointOnBoundary == nil)
        expectClose(area.bbox.center.latitude, (38.617508 + 39.057831) / 2)
    }

    @Test func `Service area without geometry decodes with no polygons`() throws {
        let json = """
        {"id":"x_a","name":"Zone","description":"d","bbox":[-1.0,2.0,3.0,4.0]}
        """
        let area = try JSONDecoder().decode(ServiceArea.self, from: Data(json.utf8))
        #expect(!area.hasGeometry)
        #expect(area.polygons.isEmpty)
        #expect(area.name == "Zone")
        #expect(area.areaDescription == "d")
    }

    @Test func `MultiPolygon with a hole decodes exterior and interior rings`() throws {
        let json = """
        {"id":"x_m","name":null,"description":null,"bbox":[0.0,0.0,10.0,10.0],
         "geometry":{"type":"MultiPolygon","coordinates":[
           [[[0,0],[10,0],[10,10],[0,10],[0,0]],[[4,4],[6,4],[6,6],[4,6],[4,4]]],
           [[[20,20],[21,20],[21,21],[20,20]]]
         ]},
         "distanceToArea":1234.5,"nearestPointOnBoundary":[-77.1,38.8]}
        """
        let area = try JSONDecoder().decode(ServiceArea.self, from: Data(json.utf8))
        #expect(area.polygons.count == 2)
        #expect(area.polygons[0].count == 2)
        #expect(area.polygons[0][0].count == 5)
        #expect(area.polygons[0][1].count == 5)
        expectClose(area.polygons[0][1][0].latitude, 4)
        expectClose(area.polygons[0][1][0].longitude, 4)
        #expect(area.polygons[1].count == 1)
        #expect(area.distanceToArea == 1234.5)
        expectClose(area.nearestPointOnBoundary?.latitude, 38.8)
        expectClose(area.nearestPointOnBoundary?.longitude, -77.1)
    }

    @Test func `Unsupported geometry type decodes with no polygons`() throws {
        let json = """
        {"id":"x_p","name":null,"description":null,"bbox":[0,0,1,1],"geometry":{"type":"Point","coordinates":[0.5,0.5]}}
        """
        let area = try JSONDecoder().decode(ServiceArea.self, from: Data(json.utf8))
        #expect(area.polygons.isEmpty)
        #expect(!area.hasGeometry)
    }

    @Test func `Booking rule and calendar decode`() throws {
        let data = Fixtures.loadData(file: "ondemand_service_alexandria.json")
        let container = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let refs = (container["data"] as! [String: Any])["references"] as! [String: Any]

        let rules = try JSONDecoder().decode([OnDemandBookingRule].self, from: JSONSerialization.data(withJSONObject: refs["bookingRules"]!))
        #expect(rules.count == 1)
        let rule = rules[0]
        #expect(rule.id == "5088_booking_route_77652")
        #expect(rule.bookingType == 2)
        #expect(rule.priorNoticeDurationMin == nil)
        #expect(rule.priorNoticeDurationMax == nil)
        #expect(rule.priorNoticeLastDay == 1)
        #expect(rule.priorNoticeLastTime == GTFSTimeOfDay("17:00:00"))
        #expect(rule.priorNoticeStartDay == 14)
        #expect(rule.priorNoticeStartTime == GTFSTimeOfDay("00:00:00"))
        #expect(rule.priorNoticeCalendarID == nil)
        #expect(rule.message?.hasPrefix("DOT is the City of Alexandria") == true)
        #expect(rule.pickupMessage == nil)
        #expect(rule.phoneNumber == "703-746-5222")
        #expect(rule.infoURL == URL(string: "https://www.alexandriava.gov/Paratransit"))
        #expect(rule.bookingURL?.host() == "spare-rider-alexandriadot-production.vercel.app")

        let calendars = try JSONDecoder().decode([OnDemandCalendar].self, from: JSONSerialization.data(withJSONObject: refs["calendars"]!))
        #expect(calendars.map(\.id) == ["5088_c_71675_b_85952_d_63", "5088_c_71675_b_85952_d_64"])
        #expect(calendars[0].days == [.mon, .tue, .wed, .thu, .fri, .sat])
        #expect(calendars[1].days == [.sun])
        #expect(calendars[0].startDate == ServiceDate("2025-12-01"))
        #expect(calendars[0].endDate == ServiceDate("2026-12-01"))
        #expect(calendars[0].exceptedDates.isEmpty)
    }

    @Test func `Location group decodes`() throws {
        let json = """
        {"id":"CC_group","name":null,"stopIds":["CC_CC_Ironton_Ferry_West","CC_CC_Ironton_Ferry_East"]}
        """
        let group = try JSONDecoder().decode(OnDemandLocationGroup.self, from: Data(json.utf8))
        #expect(group.id == "CC_group")
        #expect(group.name == nil)
        #expect(group.stopIDs.count == 2)
    }

    @Test func `Calendar skips unknown day names`() throws {
        let json = """
        {"id":"c","days":["mon","funday","sun"],"startDate":"2026-01-01","endDate":"2026-12-31","exceptedDates":["2026-07-04"]}
        """
        let calendar = try JSONDecoder().decode(OnDemandCalendar.self, from: Data(json.utf8))
        #expect(calendar.days == [.mon, .sun])
        #expect(calendar.exceptedDates == [ServiceDate("2026-07-04")!])
    }
}
```

- [x] **Step 2: Run the tests to verify they fail**

Run the standard command with `-only-testing:OBAKitTests/OnDemandModelTests`. Expected: the build fails with `cannot find 'GTFSTimeOfDay' in scope` (and siblings).

- [x] **Step 3: Create `GTFSTimeOfDay.swift`**

```swift
//
//  GTFSTimeOfDay.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// A GTFS `"HH:MM:SS"` time of day, measured from the service-day anchor
/// (local noon minus twelve hours — see `BookingDeadlineEvaluator`). May exceed
/// `24:00:00`: the Alexandria feed accepts pickups until `24:50:00`.
///
/// `Int` on purpose, not `Int64`: seconds since midnight never approaches the
/// 32-bit limit that makes epoch values unsafe on `arm64_32` watches.
public struct GTFSTimeOfDay: Hashable, Comparable, Sendable, Decodable, CustomStringConvertible {
    public let seconds: Int

    public init(seconds: Int) {
        self.seconds = seconds
    }

    /// Parses `"H:MM:SS"` or `"HH:MM:SS"`; hours are unbounded, minutes and
    /// seconds must be `0...59`. Returns `nil` for anything else.
    public init?(_ string: String) {
        let parts = string.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let hours = Int(parts[0]), hours >= 0,
              let minutes = Int(parts[1]), (0..<60).contains(minutes),
              let seconds = Int(parts[2]), (0..<60).contains(seconds)
        else {
            return nil
        }
        self.seconds = hours * 3600 + minutes * 60 + seconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = GTFSTimeOfDay(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid GTFS time of day: \(raw)")
        }
        self = value
    }

    public static let midnight = GTFSTimeOfDay(seconds: 0)

    /// `24:00:00` — the wiki's default `endPickupTime` when a rule has none.
    public static let endOfServiceDay = GTFSTimeOfDay(seconds: 24 * 3600)

    public var description: String {
        String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }

    public static func < (lhs: GTFSTimeOfDay, rhs: GTFSTimeOfDay) -> Bool {
        lhs.seconds < rhs.seconds
    }
}
```

- [x] **Step 4: Create `ServiceDate.swift`**

```swift
//
//  ServiceDate.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// A calendar date in the agency's service-day sense (`"YYYY-MM-DD"` on the
/// wire). Deliberately not a `Date`: a service day has no instant until it is
/// anchored in a time zone by `BookingDeadlineEvaluator`.
public struct ServiceDate: Hashable, Comparable, Sendable, Decodable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses exactly `"YYYY-MM-DD"`.
    public init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day)
        else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = ServiceDate(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid service date: \(raw)")
        }
        self = value
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: ServiceDate, rhs: ServiceDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// The `days` vocabulary of an on-demand calendar (wiki §2.4).
public enum Weekday: String, CaseIterable, Sendable {
    case mon, tue, wed, thu, fri, sat, sun

    /// `Calendar.component(.weekday, from:)` numbering: 1 = Sunday … 7 = Saturday.
    public init(calendarWeekday: Int) {
        switch calendarWeekday {
        case 1: self = .sun
        case 2: self = .mon
        case 3: self = .tue
        case 4: self = .wed
        case 5: self = .thu
        case 6: self = .fri
        default: self = .sat
        }
    }

    public var calendarWeekday: Int {
        switch self {
        case .sun: return 1
        case .mon: return 2
        case .tue: return 3
        case .wed: return 4
        case .thu: return 5
        case .fri: return 6
        case .sat: return 7
        }
    }
}
```

- [x] **Step 5: Create `ServiceKind.swift`**

```swift
//
//  ServiceKind.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// How an on-demand service is shaped (wiki §2.3). Classified by the server at
/// import; clients never infer it from `rules`.
public enum ServiceKind: String, Decodable, Sendable {
    case zone
    case zoneToZone
    case stopGroup
    case deviatedRoute
    /// Any value this build doesn't know — a newer server, or the wiki's own
    /// reserved fallback.
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ServiceKind(rawValue: raw) ?? .unknown
    }
}

/// Why `services-for-location` matched a service (wiki §3.4). Present only on
/// that endpoint's list elements.
public enum MatchReason: String, Decodable, Sendable {
    case areaContainsPoint
    case stopWithinRadius
    case areaNearby
    case areaIntersectsViewport
    case stopWithinViewport
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MatchReason(rawValue: raw) ?? .unknown
    }
}
```

- [x] **Step 6: Create `OnDemandBookingRule.swift`, `OnDemandCalendar.swift`, `OnDemandLocationGroup.swift`**

`OnDemandBookingRule.swift`:

```swift
//
//  OnDemandBookingRule.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// GTFS-Flex `booking_rules.txt` as the API exposes it (wiki §2.4). Nullable
/// conditionally-required fields do ship from real feeds; the evaluator
/// (spec §6.2) decides what each null means.
public struct OnDemandBookingRule: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    /// 0 real-time, 1 same-day, 2 prior-day(s).
    public let bookingType: Int
    /// Minutes. `bookingType` 1 only.
    public let priorNoticeDurationMin: Int?
    /// Minutes.
    public let priorNoticeDurationMax: Int?
    /// Days before travel. `bookingType` 2 only.
    public let priorNoticeLastDay: Int?
    public let priorNoticeLastTime: GTFSTimeOfDay?
    public let priorNoticeStartDay: Int?
    public let priorNoticeStartTime: GTFSTimeOfDay?
    /// Combined calendar ID whose service days `priorNoticeLastDay` and
    /// `priorNoticeStartDay` count (spec §6.1). `bookingType` 2 only.
    public let priorNoticeCalendarID: String?
    public let message: String?
    public let pickupMessage: String?
    public let dropOffMessage: String?
    /// As published in the feed, unformatted.
    public let phoneNumber: String?
    public let infoURL: URL?
    public let bookingURL: URL?

    private enum CodingKeys: String, CodingKey {
        case id, bookingType, priorNoticeDurationMin, priorNoticeDurationMax
        case priorNoticeLastDay, priorNoticeLastTime, priorNoticeStartDay, priorNoticeStartTime
        case priorNoticeCalendarID = "priorNoticeCalendarId"
        case message, pickupMessage, dropOffMessage, phoneNumber
        case infoURL = "infoUrl"
        case bookingURL = "bookingUrl"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        bookingType = try container.decode(Int.self, forKey: .bookingType)
        priorNoticeDurationMin = try container.decodeIfPresent(Int.self, forKey: .priorNoticeDurationMin)
        priorNoticeDurationMax = try container.decodeIfPresent(Int.self, forKey: .priorNoticeDurationMax)
        priorNoticeLastDay = try container.decodeIfPresent(Int.self, forKey: .priorNoticeLastDay)
        priorNoticeLastTime = try container.decodeIfPresent(GTFSTimeOfDay.self, forKey: .priorNoticeLastTime)
        priorNoticeStartDay = try container.decodeIfPresent(Int.self, forKey: .priorNoticeStartDay)
        priorNoticeStartTime = try container.decodeIfPresent(GTFSTimeOfDay.self, forKey: .priorNoticeStartTime)
        priorNoticeCalendarID = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .priorNoticeCalendarID))
        message = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .message))
        pickupMessage = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .pickupMessage))
        dropOffMessage = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .dropOffMessage))
        phoneNumber = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .phoneNumber))
        infoURL = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .infoURL)).flatMap(URL.init(string:))
        bookingURL = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .bookingURL)).flatMap(URL.init(string:))
    }
}
```

`OnDemandCalendar.swift`:

```swift
//
//  OnDemandCalendar.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// A service calendar in GOFS shape (wiki §2.4): active weekdays inside a date
/// range, minus explicit exceptions. Dates are service days in the agency's
/// time zone.
public struct OnDemandCalendar: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let days: [Weekday]
    public let startDate: ServiceDate
    public let endDate: ServiceDate
    public let exceptedDates: [ServiceDate]

    private enum CodingKeys: String, CodingKey {
        case id, days, startDate, endDate, exceptedDates
    }

    public init(id: String, days: [Weekday], startDate: ServiceDate, endDate: ServiceDate, exceptedDates: [ServiceDate]) {
        self.id = id
        self.days = days
        self.startDate = startDate
        self.endDate = endDate
        self.exceptedDates = exceptedDates
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        // A day name this build doesn't know is dropped rather than failing the
        // whole response; the calendar just has fewer active days.
        days = try container.decode([String].self, forKey: .days).compactMap(Weekday.init(rawValue:))
        startDate = try container.decode(ServiceDate.self, forKey: .startDate)
        endDate = try container.decode(ServiceDate.self, forKey: .endDate)
        exceptedDates = try container.decodeIfPresent([ServiceDate].self, forKey: .exceptedDates) ?? []
    }
}
```

`OnDemandLocationGroup.swift`:

```swift
//
//  OnDemandLocationGroup.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// A named set of stops an on-demand rule can start or end at (wiki §2.4).
/// Members also appear in `references.stops`.
public struct OnDemandLocationGroup: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String?
    public let stopIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case id, name
        case stopIDs = "stopIds"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .name))
        stopIDs = try container.decodeIfPresent([String].self, forKey: .stopIDs) ?? []
    }
}
```

- [x] **Step 7: Create `ServiceArea.swift`**

```swift
//
//  ServiceArea.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation

/// `[minLon, minLat, maxLon, maxLat]` on the wire (RFC 7946 order).
public struct BoundingBox: Hashable, Sendable {
    public let minLongitude: Double
    public let minLatitude: Double
    public let maxLongitude: Double
    public let maxLatitude: Double

    public init(minLongitude: Double, minLatitude: Double, maxLongitude: Double, maxLatitude: Double) {
        self.minLongitude = minLongitude
        self.minLatitude = minLatitude
        self.maxLongitude = maxLongitude
        self.maxLatitude = maxLatitude
    }

    public var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
    }
}

/// A zone an on-demand service covers (wiki §3.4 `serviceArea`).
///
/// `geometry` is endpoint policy (`geometryDetail=none|simplified|full`), so
/// `polygons` may be empty even for a real zone; `bbox` is always present.
/// Simplified geometry is for display only — containment and distance come
/// from the server as `distanceToArea`/`nearestPointOnBoundary`, never from
/// testing these polygons.
public struct ServiceArea: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let areaDescription: String?
    public let bbox: BoundingBox
    /// `polygons[p][ring][i]`: ring 0 is the exterior, rings 1… are holes.
    /// One element for a GeoJSON `Polygon`, several for a `MultiPolygon`,
    /// empty when the key was omitted or the type is unsupported.
    public let polygons: [[[CLLocationCoordinate2D]]]
    /// Meters from the query point to the nearest boundary; `0` inside.
    /// Non-nil only in `services-for-location` point mode.
    public let distanceToArea: Double?
    /// Closest boundary point; nil inside the area or outside point mode.
    public let nearestPointOnBoundary: CLLocationCoordinate2D?

    public var hasGeometry: Bool { !polygons.isEmpty }

    private enum CodingKeys: String, CodingKey {
        case id, name, bbox, geometry, distanceToArea, nearestPointOnBoundary
        case areaDescription = "description"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .name))
        areaDescription = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .areaDescription))

        let box = try container.decode([Double].self, forKey: .bbox)
        guard box.count == 4 else {
            throw DecodingError.dataCorruptedError(forKey: .bbox, in: container, debugDescription: "bbox must have four numbers, got \(box.count)")
        }
        bbox = BoundingBox(minLongitude: box[0], minLatitude: box[1], maxLongitude: box[2], maxLatitude: box[3])

        polygons = try container.decodeIfPresent(GeoJSONGeometry.self, forKey: .geometry)?.polygons ?? []
        distanceToArea = try container.decodeIfPresent(Double.self, forKey: .distanceToArea)

        if let point = try container.decodeIfPresent([Double].self, forKey: .nearestPointOnBoundary), point.count == 2 {
            nearestPointOnBoundary = CLLocationCoordinate2D(latitude: point[1], longitude: point[0])
        } else {
            nearestPointOnBoundary = nil
        }
    }
}

/// The subset of GeoJSON geometry the contract allows: `Polygon` and
/// `MultiPolygon`, positions as `[lon, lat]`.
private struct GeoJSONGeometry: Decodable {
    let polygons: [[[CLLocationCoordinate2D]]]

    private enum CodingKeys: String, CodingKey {
        case type, coordinates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "Polygon":
            polygons = [Self.rings(try container.decode([[[Double]]].self, forKey: .coordinates))]
        case "MultiPolygon":
            polygons = try container.decode([[[[Double]]]].self, forKey: .coordinates).map(Self.rings)
        default:
            polygons = []
        }
    }

    private static func rings(_ rings: [[[Double]]]) -> [[CLLocationCoordinate2D]] {
        rings.map { ring in
            ring.compactMap { position in
                position.count >= 2 ? CLLocationCoordinate2D(latitude: position[1], longitude: position[0]) : nil
            }
        }
    }
}
```

- [x] **Step 8: Create `AvailabilityRule.swift`**

```swift
//
//  AvailabilityRule.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// One "from these places, to these places, in this daily window, on this
/// calendar" statement of an on-demand service (wiki §2.2). All three time
/// fields nil means the service runs all hours of its service days.
public struct AvailabilityRule: Decodable, Hashable, Sendable {
    /// Shared stop / location / location-group ID namespace.
    public let fromIDs: [String]
    public let toIDs: [String]
    public let startPickupTime: GTFSTimeOfDay?
    public let endPickupTime: GTFSTimeOfDay?
    /// Nil when it equals `endPickupTime`.
    public let endDropOffTime: GTFSTimeOfDay?
    /// At least one element on the wire; → `references.calendars`.
    public let calendarIDs: [String]
    /// 0 scheduled, 2 must book, 3 coordinate with driver.
    public let pickupType: Int
    public let dropOffType: Int
    /// The pickup side governs booking (spec §6); → `references.bookingRules`.
    public let pickupBookingRuleID: String?
    public let dropOffBookingRuleID: String?
    public let safeDurationFactor: Double?
    /// Seconds.
    public let safeDurationOffset: Double?

    private enum CodingKeys: String, CodingKey {
        case fromIds, toIds, startPickupTime, endPickupTime, endDropOffTime, calendarIds
        case pickupType, dropOffType, pickupBookingRuleId, dropOffBookingRuleId
        case safeDurationFactor, safeDurationOffset
    }

    public init(
        fromIDs: [String],
        toIDs: [String],
        startPickupTime: GTFSTimeOfDay?,
        endPickupTime: GTFSTimeOfDay?,
        endDropOffTime: GTFSTimeOfDay?,
        calendarIDs: [String],
        pickupType: Int,
        dropOffType: Int,
        pickupBookingRuleID: String?,
        dropOffBookingRuleID: String?,
        safeDurationFactor: Double?,
        safeDurationOffset: Double?
    ) {
        self.fromIDs = fromIDs
        self.toIDs = toIDs
        self.startPickupTime = startPickupTime
        self.endPickupTime = endPickupTime
        self.endDropOffTime = endDropOffTime
        self.calendarIDs = calendarIDs
        self.pickupType = pickupType
        self.dropOffType = dropOffType
        self.pickupBookingRuleID = pickupBookingRuleID
        self.dropOffBookingRuleID = dropOffBookingRuleID
        self.safeDurationFactor = safeDurationFactor
        self.safeDurationOffset = safeDurationOffset
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fromIDs = try container.decode([String].self, forKey: .fromIds)
        toIDs = try container.decode([String].self, forKey: .toIds)
        startPickupTime = try container.decodeIfPresent(GTFSTimeOfDay.self, forKey: .startPickupTime)
        endPickupTime = try container.decodeIfPresent(GTFSTimeOfDay.self, forKey: .endPickupTime)
        endDropOffTime = try container.decodeIfPresent(GTFSTimeOfDay.self, forKey: .endDropOffTime)
        calendarIDs = try container.decode([String].self, forKey: .calendarIds)
        pickupType = try container.decode(Int.self, forKey: .pickupType)
        dropOffType = try container.decode(Int.self, forKey: .dropOffType)
        pickupBookingRuleID = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .pickupBookingRuleId))
        dropOffBookingRuleID = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .dropOffBookingRuleId))
        safeDurationFactor = try container.decodeIfPresent(Double.self, forKey: .safeDurationFactor)
        safeDurationOffset = try container.decodeIfPresent(Double.self, forKey: .safeDurationOffset)
    }
}
```

- [x] **Step 9: Create `OnDemandService.swift`**

The `loadReferences` body below resolves only `route` and `agency`; Task 2 adds the four reference finders and extends this method.

```swift
//
//  OnDemandService.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// A bookable on-demand service (wiki §2.1): the entry of
/// `/api/ondemand/service/{id}` and the list element of the two list endpoints.
///
/// `@unchecked Sendable` per the `HasReferences` contract in `References.swift`:
/// every `var` below is written only by `init(from:)` and `loadReferences`,
/// before the instance crosses an isolation boundary.
public final class OnDemandService: NSObject, Identifiable, Decodable, HasReferences, @unchecked Sendable {
    /// Combined ID; for flex services equal to the route's combined ID.
    public let id: String
    public let agencyID: String
    /// Nil for future GOFS-sourced services.
    public let routeID: String?
    public let name: String
    public let serviceKind: ServiceKind
    public let serviceDescription: String?
    public let url: URL?
    /// May be empty for degenerate feeds (wiki §2.3).
    public let rules: [AvailabilityRule]
    /// Only on `services-for-location` list elements.
    public let matchReason: MatchReason?

    // Resolved by `loadReferences`.
    public private(set) var route: Route?
    public private(set) var agency: Agency?
    /// Areas any rule starts or ends in, sorted by id.
    public private(set) var areas: [ServiceArea] = []
    public private(set) var locationGroups: [OnDemandLocationGroup] = []
    public private(set) var bookingRules: [OnDemandBookingRule] = []
    public private(set) var calendars: [OnDemandCalendar] = []
    public private(set) var regionIdentifier: Int?

    private enum CodingKeys: String, CodingKey {
        case id, name, serviceKind, url, rules, matchReason
        case agencyID = "agencyId"
        case routeID = "routeId"
        case serviceDescription = "description"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        agencyID = try container.decode(String.self, forKey: .agencyID)
        routeID = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .routeID))
        name = try container.decode(String.self, forKey: .name)
        serviceKind = try container.decodeIfPresent(ServiceKind.self, forKey: .serviceKind) ?? .unknown
        serviceDescription = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .serviceDescription))
        url = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .url)).flatMap(URL.init(string:))
        rules = try container.decodeIfPresent([AvailabilityRule].self, forKey: .rules) ?? []
        matchReason = try container.decodeIfPresent(MatchReason.self, forKey: .matchReason)
        super.init()
    }

    // MARK: - HasReferences

    public func loadReferences(_ references: References, regionIdentifier: Int?) {
        self.regionIdentifier = regionIdentifier
        route = references.routeWithID(routeID)
        agency = references.agencyWithID(agencyID)
    }

    // MARK: - Lookups

    /// The booking rule with `id`, or nil when `id` is nil or the reference is
    /// missing. Callers must treat "referenced but missing" as unknown, not as
    /// "no notice required" — see `OnDemandServiceSummary`.
    public func bookingRule(id: String?) -> OnDemandBookingRule? {
        guard let id else { return nil }
        return bookingRules.first { $0.id == id }
    }

    /// The agency's time zone — the zone every service-day value is interpreted
    /// in (wiki §2.4). Nil until references load, or when the agency publishes
    /// an unknown identifier.
    public var timeZone: TimeZone? {
        agency?.resolvedTimeZone
    }

    // MARK: - CustomDebugStringConvertible

    public override var debugDescription: String {
        var builder = DebugDescriptionBuilder(baseDescription: super.debugDescription)
        builder.add(key: "id", value: id)
        builder.add(key: "name", value: name)
        builder.add(key: "serviceKind", value: serviceKind.rawValue)
        return builder.description
    }
}
```

- [x] **Step 10: Run the tests to verify they pass**

Run the standard command with `-only-testing:OBAKitTests/OnDemandModelTests`. Expected: all 11 tests PASS. Then run the watchOS portability check. Expected: `BUILD SUCCEEDED`.

- [x] **Step 11: Lint and commit**

```bash
cd /Users/aaron/repos/onebusaway/.worktrees/ios-gtfs-flex && swiftlint lint --quiet | tail -20 && \
git add OBAKitCore/Models/REST/OnDemand "OBAKitTests/Modeling/Model Unit Tests/OnDemandModelTests.swift" && \
git commit -m "Add on-demand service wire models"
```

---

### Task 2: References gains the four on-demand reference arrays

**Files:**
- Modify: `OBAKitCore/Models/REST/References/References.swift:12-63` (properties, `CodingKeys`, `init`) and the `Finders` extension at the bottom
- Modify: `OBAKitCore/Models/REST/OnDemand/OnDemandService.swift` (`loadReferences`)
- Test: `OBAKitTests/Modeling/Model Unit Tests/OnDemandReferencesTests.swift`

**Interfaces:**
- Consumes: Task 1 types.
- Produces: on `References`: `public let serviceAreas: [ServiceArea]`, `public let locationGroups: [OnDemandLocationGroup]`, `public let bookingRules: [OnDemandBookingRule]`, `public let calendars: [OnDemandCalendar]` (each sorted by `id`); finders `serviceAreaWithID(_ id: String?) -> ServiceArea?`, `locationGroupWithID(_:) -> OnDemandLocationGroup?`, `bookingRuleWithID(_:) -> OnDemandBookingRule?`, `calendarWithID(_:) -> OnDemandCalendar?`. On `OnDemandService`: `areas`, `locationGroups`, `bookingRules`, `calendars` populated after `loadReferences`.

- [x] **Step 1: Write the failing tests**

Create `OBAKitTests/Modeling/Model Unit Tests/OnDemandReferencesTests.swift`:

```swift
//
//  OnDemandReferencesTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class OnDemandReferencesTests: OBATestCase {

    private func decodeEntry(_ file: String) throws -> RESTAPIResponse<OnDemandService> {
        try JSONDecoder.RESTDecoder(regionIdentifier: pugetSoundRegionIdentifier)
            .decode(RESTAPIResponse<OnDemandService>.self, from: Fixtures.loadData(file: file))
    }

    private func decodeList(_ file: String) throws -> RESTAPIResponse<[OnDemandService]> {
        try JSONDecoder.RESTDecoder(regionIdentifier: pugetSoundRegionIdentifier)
            .decode(RESTAPIResponse<[OnDemandService]>.self, from: Fixtures.loadData(file: file))
    }

    @Test func `References carry the four on-demand arrays`() throws {
        let references = try decodeEntry("ondemand_service_alexandria.json").references!
        #expect(references.serviceAreas.map(\.id) == ["5088_area_1449"])
        #expect(references.locationGroups.isEmpty)
        #expect(references.bookingRules.map(\.id) == ["5088_booking_route_77652"])
        #expect(references.calendars.map(\.id) == ["5088_c_71675_b_85952_d_63", "5088_c_71675_b_85952_d_64"])
        #expect(references.agencies.first?.timeZone == "America/Los_Angeles")
        #expect(references.routes.first?.longName == "DOT Paratransit")
    }

    @Test func `Finders resolve by id and return nil for unknown or nil ids`() throws {
        let references = try decodeEntry("ondemand_service_alexandria.json").references!
        #expect(references.serviceAreaWithID("5088_area_1449")?.id == "5088_area_1449")
        #expect(references.bookingRuleWithID("5088_booking_route_77652")?.phoneNumber == "703-746-5222")
        #expect(references.calendarWithID("5088_c_71675_b_85952_d_64")?.days == [.sun])
        #expect(references.locationGroupWithID("nope") == nil)
        #expect(references.serviceAreaWithID(nil) == nil)
        #expect(references.bookingRuleWithID(nil) == nil)
        #expect(references.calendarWithID(nil) == nil)
    }

    @Test func `Legacy references decode with empty on-demand arrays`() throws {
        let data = Fixtures.loadData(file: "references.json")
        let references = try JSONDecoder.RESTDecoder().decode(References.self, from: data)
        #expect(references.serviceAreas.isEmpty)
        #expect(references.locationGroups.isEmpty)
        #expect(references.bookingRules.isEmpty)
        #expect(references.calendars.isEmpty)
    }

    @Test func `Entry response resolves the service's references`() throws {
        let service = try decodeEntry("ondemand_service_alexandria.json").entry
        #expect(service.route?.id == "5088_77652")
        #expect(service.agency?.id == "5088")
        #expect(service.timeZone?.identifier == "America/Los_Angeles")
        #expect(service.areas.map(\.id) == ["5088_area_1449"])
        #expect(service.bookingRules.map(\.id) == ["5088_booking_route_77652"])
        #expect(service.calendars.map(\.id) == ["5088_c_71675_b_85952_d_63", "5088_c_71675_b_85952_d_64"])
        #expect(service.locationGroups.isEmpty)
        #expect(service.regionIdentifier == pugetSoundRegionIdentifier)
        #expect(service.bookingRule(id: "5088_booking_route_77652")?.bookingType == 2)
        #expect(service.bookingRule(id: "missing") == nil)
        #expect(service.bookingRule(id: nil) == nil)
    }

    @Test func `Location list response resolves every element and carries match reasons`() throws {
        let response = try decodeList("ondemand_services_for_location_viewport.json")
        #expect(response.list.map(\.id) == ["5088_77652"])
        #expect(response.list[0].matchReason == .areaIntersectsViewport)
        #expect(response.list[0].areas.count == 1)
        #expect(response.list[0].areas[0].hasGeometry, "list endpoints default to simplified geometry")
        #expect(response.list[0].areas[0].distanceToArea == nil, "viewport mode carries no distance")
        #expect(response.outOfRange == false)
        #expect(response.limitExceeded == false)

        let point = try decodeList("ondemand_services_for_location_point.json")
        #expect(point.list[0].matchReason == .areaContainsPoint)
        #expect(point.list[0].areas[0].distanceToArea == 0)
        #expect(point.list[0].areas[0].nearestPointOnBoundary == nil)
    }

    @Test func `Charlevoix agency list resolves a stop group and its stops`() throws {
        let response = try decodeList("ondemand_services_for_agency_charlevoix.json")
        #expect(response.list.map(\.id) == ["CC_CC1", "CC_CC2_med", "CC_CC3", "CC_CC4"])
        #expect(response.list.map(\.serviceKind) == [.zone, .zoneToZone, .stopGroup, .zone])

        let ferry = response.list[2]
        #expect(ferry.locationGroups.count == 1)
        #expect(ferry.locationGroups[0].stopIDs.count == 2)
        #expect(ferry.areas.isEmpty)
        let members = response.references!.stopsWithIDs(ferry.locationGroups[0].stopIDs)
        #expect(members.count == 2)
        #expect(ferry.agency?.timeZone == "America/Detroit")
        #expect(ferry.calendars.count >= 1)
        #expect(response.list[0].calendars.map(\.id).sorted() == ["CC_mon-tues-wed-thurs-fri", "CC_sat"])
    }
}
```

- [x] **Step 2: Run the tests to verify they fail**

Run the standard command with `-only-testing:OBAKitTests/OnDemandReferencesTests`. Expected: build failure `value of type 'References' has no member 'serviceAreas'`.

- [x] **Step 3: Extend `References`**

In `References.swift`, add after `public let trips: [Trip]`:

```swift
    // `/api/ondemand` responses only (wiki §2.4); every `/where` response
    // decodes these as empty.
    public let serviceAreas: [ServiceArea]
    public let locationGroups: [OnDemandLocationGroup]
    public let bookingRules: [OnDemandBookingRule]
    public let calendars: [OnDemandCalendar]
```

Change `CodingKeys` to:

```swift
    private enum CodingKeys: String, CodingKey {
        case agencies, routes, stops, trips
        case alerts = "situations"
        case serviceAreas, locationGroups, bookingRules, calendars
    }
```

In `init(from:)`, after the `trips` assignment and before `super.init()`:

```swift
        let serviceAreas = try container.decodeIfPresent([ServiceArea].self, forKey: .serviceAreas) ?? []
        self.serviceAreas = serviceAreas.sorted(by: \.id)

        let locationGroups = try container.decodeIfPresent([OnDemandLocationGroup].self, forKey: .locationGroups) ?? []
        self.locationGroups = locationGroups.sorted(by: \.id)

        let bookingRules = try container.decodeIfPresent([OnDemandBookingRule].self, forKey: .bookingRules) ?? []
        self.bookingRules = bookingRules.sorted(by: \.id)

        let calendars = try container.decodeIfPresent([OnDemandCalendar].self, forKey: .calendars) ?? []
        self.calendars = calendars.sorted(by: \.id)
```

Append to the `Finders` extension:

```swift
    // MARK: - On-demand

    public func serviceAreaWithID(_ id: String?) -> ServiceArea? {
        guard let id else { return nil }
        return serviceAreas.binarySearch(sortedBy: \.id, element: id)?.element
    }

    public func locationGroupWithID(_ id: String?) -> OnDemandLocationGroup? {
        guard let id else { return nil }
        return locationGroups.binarySearch(sortedBy: \.id, element: id)?.element
    }

    public func bookingRuleWithID(_ id: String?) -> OnDemandBookingRule? {
        guard let id else { return nil }
        return bookingRules.binarySearch(sortedBy: \.id, element: id)?.element
    }

    public func calendarWithID(_ id: String?) -> OnDemandCalendar? {
        guard let id else { return nil }
        return calendars.binarySearch(sortedBy: \.id, element: id)?.element
    }
```

- [x] **Step 4: Complete `OnDemandService.loadReferences`**

Replace the method body in `OnDemandService.swift` with:

```swift
    public func loadReferences(_ references: References, regionIdentifier: Int?) {
        self.regionIdentifier = regionIdentifier
        route = references.routeWithID(routeID)
        agency = references.agencyWithID(agencyID)

        // Rules are the only link from a service to its areas and groups; the
        // ID namespace is shared, so each endpoint ID is tried against both.
        let endpointIDs = Set(rules.flatMap { $0.fromIDs + $0.toIDs }).sorted()
        areas = endpointIDs.compactMap { references.serviceAreaWithID($0) }
        locationGroups = endpointIDs.compactMap { references.locationGroupWithID($0) }

        let bookingRuleIDs = Set(rules.flatMap { [$0.pickupBookingRuleID, $0.dropOffBookingRuleID].compactMap { $0 } }).sorted()
        bookingRules = bookingRuleIDs.compactMap { references.bookingRuleWithID($0) }

        // Booking rules may reference a notice calendar of their own (spec §6.1).
        let calendarIDs = Set(rules.flatMap(\.calendarIDs) + bookingRules.compactMap(\.priorNoticeCalendarID)).sorted()
        calendars = calendarIDs.compactMap { references.calendarWithID($0) }
    }
```

- [x] **Step 5: Run the tests to verify they pass**

Run the standard command with `-only-testing:OBAKitTests/OnDemandReferencesTests` and then with `-only-testing:OBAKitTests/ReferencesTests`. Expected: PASS for both. Run the watchOS portability check. Expected: `BUILD SUCCEEDED`.

- [x] **Step 6: Commit**

```bash
cd /Users/aaron/repos/onebusaway/.worktrees/ios-gtfs-flex && swiftlint lint --quiet | tail -20 && \
git add OBAKitCore/Models/REST/References/References.swift OBAKitCore/Models/REST/OnDemand/OnDemandService.swift "OBAKitTests/Modeling/Model Unit Tests/OnDemandReferencesTests.swift" && \
git commit -m "Resolve on-demand references on service models"
```

---

### Task 3: `onDemandServiceIDs` pointer on `Stop` and `Route`

**Files:**
- Modify: `OBAKitCore/Models/REST/References/Stop.swift:111-201, 218-249`
- Modify: `OBAKitCore/Models/REST/References/Route.swift:17-82, 103-134`
- Test: `OBAKitTests/Modeling/Model Unit Tests/StopTests.swift`
- Test: `OBAKitTests/Modeling/Model Unit Tests/RouteOnDemandPointerTests.swift`

**Interfaces:**
- Produces: `Stop.onDemandServiceIDs: [String]` and `Route.onDemandServiceIDs: [String]` (`public let`; empty when the key is absent; encoded only when non-empty; part of `isEqual`/`hash`).

- [x] **Step 1: Write the failing tests**

Append to `StopTests` in `OBAKitTests/Modeling/Model Unit Tests/StopTests.swift` (inside the class):

```swift
    @Test func `Stop with an on-demand pointer decodes it`() throws {
        let data = Fixtures.loadData(file: "stop_with_ondemand_pointer.json")
        let stop = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<Stop>.self, from: data).entry
        #expect(stop.id == "CC_CC_Ironton_Ferry_West")
        #expect(stop.onDemandServiceIDs == ["CC_CC3"])
    }

    @Test func `Stop without the key decodes an empty pointer list`() throws {
        let flexServerStop = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<Stop>.self, from: Fixtures.loadData(file: "stop_alexandria_4258639.json")).entry
        #expect(flexServerStop.onDemandServiceIDs.isEmpty)

        let legacyStop = try Fixtures.loadSomeStops().first!
        #expect(legacyStop.onDemandServiceIDs.isEmpty)
    }

    @Test func `Pointer round-trips and is omitted when empty`() throws {
        let data = Fixtures.loadData(file: "stop_with_ondemand_pointer.json")
        let stop = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<Stop>.self, from: data).entry
        let copy = try Fixtures.roundtripCodable(type: Stop.self, model: stop)
        #expect(copy.onDemandServiceIDs == ["CC_CC3"])
        #expect(copy == stop)

        let legacy = try Fixtures.loadSomeStops().first!
        let encoded = try JSONEncoder.RESTEncoder().encode(legacy)
        let keys = (try JSONSerialization.jsonObject(with: encoded) as! [String: Any]).keys
        #expect(!keys.contains("onDemandServiceIds"), "cached blobs must stay byte-identical for non-flex stops")
    }

    @Test func `Pointer participates in equality`() throws {
        let withPointer = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<Stop>.self, from: Fixtures.loadData(file: "stop_with_ondemand_pointer.json")).entry
        let json = try JSONSerialization.jsonObject(with: Fixtures.loadData(file: "stop_with_ondemand_pointer.json")) as! [String: Any]
        var dataDict = json["data"] as! [String: Any]
        var entry = dataDict["entry"] as! [String: Any]
        entry.removeValue(forKey: "onDemandServiceIds")
        dataDict["entry"] = entry
        var stripped = json
        stripped["data"] = dataDict
        let withoutPointer = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<Stop>.self, from: JSONSerialization.data(withJSONObject: stripped)).entry
        #expect(withPointer != withoutPointer)
        #expect(withPointer.hash != withoutPointer.hash)
    }
```

Create `OBAKitTests/Modeling/Model Unit Tests/RouteOnDemandPointerTests.swift`:

```swift
//
//  RouteOnDemandPointerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class RouteOnDemandPointerTests: OBATestCase {

    @Test func `Route with an on-demand pointer decodes it`() throws {
        let route = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<Route>.self, from: Fixtures.loadData(file: "route_with_ondemand_pointer.json")).entry
        #expect(route.id == "CC_CC3")
        #expect(route.onDemandServiceIDs == ["CC_CC3"])
    }

    @Test func `Legacy route decodes an empty pointer list and omits it when encoding`() throws {
        let route = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<Route>.self, from: Fixtures.loadData(file: "route_1_10.json")).entry
        #expect(route.onDemandServiceIDs.isEmpty)
        let encoded = try JSONEncoder.RESTEncoder().encode(route)
        let keys = (try JSONSerialization.jsonObject(with: encoded) as! [String: Any]).keys
        #expect(!keys.contains("onDemandServiceIds"))
    }

    @Test func `Route pointer round-trips`() throws {
        let route = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<Route>.self, from: Fixtures.loadData(file: "route_with_ondemand_pointer.json")).entry
        let copy = try Fixtures.roundtripCodable(type: Route.self, model: route)
        #expect(copy.onDemandServiceIDs == ["CC_CC3"])
        #expect(copy == route)
    }

    @Test func `Reference routes inside an on-demand response carry the pointer`() throws {
        let response = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<OnDemandService>.self, from: Fixtures.loadData(file: "ondemand_service_alexandria.json"))
        #expect(response.entry.route?.onDemandServiceIDs == ["5088_77652"])
    }
}
```

- [x] **Step 2: Run the tests to verify they fail**

Run the standard command with `-only-testing:OBAKitTests/StopTests` then `-only-testing:OBAKitTests/RouteOnDemandPointerTests`. Expected: build failure `has no member 'onDemandServiceIDs'`.

- [x] **Step 3: Add the pointer to `Stop`**

In `Stop.swift`, after `public let routeIDs: [String]`:

```swift
    /// IDs of `/api/ondemand` services that reference this stop — a
    /// location-group member, or a deviated route's timed stop (wiki §3.1).
    /// Empty for servers and feeds without flex data; the key is omitted on the
    /// wire when empty and this property is encoded only when non-empty, so
    /// cached stop blobs for non-flex regions are byte-identical to before.
    public let onDemandServiceIDs: [String]
```

Add `case onDemandServiceIDs = "onDemandServiceIds"` to `CodingKeys`. In `init(from:)`, after `routeIDs = …`:

```swift
        onDemandServiceIDs = try container.decodeIfPresent([String].self, forKey: .onDemandServiceIDs) ?? []
```

In `encode(to:)`, after `try container.encode(routeIDs, forKey: .routeIDs)`:

```swift
        if !onDemandServiceIDs.isEmpty {
            try container.encode(onDemandServiceIDs, forKey: .onDemandServiceIDs)
        }
```

In `isEqual`, add `onDemandServiceIDs == rhs.onDemandServiceIDs &&` before `wheelchairBoarding == rhs.wheelchairBoarding`. In `hash`, add `hasher.combine(onDemandServiceIDs)` after `hasher.combine(routeIDs)`.

- [x] **Step 4: Add the pointer to `Route`**

In `Route.swift`, after `public let routeURL: URL?`:

```swift
    /// IDs of `/api/ondemand` services compiled from this route's trips (wiki
    /// §3.1). Empty and omitted from encoding for non-flex routes.
    public let onDemandServiceIDs: [String]
```

Add `case onDemandServiceIDs = "onDemandServiceIds"` to `CodingKeys`. In `init(from:)`, after `routeURL = …`:

```swift
        onDemandServiceIDs = try container.decodeIfPresent([String].self, forKey: .onDemandServiceIDs) ?? []
```

In `encode(to:)`, after the `routeURL` line:

```swift
        if !onDemandServiceIDs.isEmpty {
            try container.encode(onDemandServiceIDs, forKey: .onDemandServiceIDs)
        }
```

In `isEqual`, add `onDemandServiceIDs == rhs.onDemandServiceIDs &&` before `routeURL == rhs.routeURL`. In `hash`, add `hasher.combine(onDemandServiceIDs)`.

- [x] **Step 5: Run the tests to verify they pass**

Run the standard command with `-only-testing:OBAKitTests/StopTests`, `-only-testing:OBAKitTests/RouteOnDemandPointerTests`, `-only-testing:OBAKitTests/StopsModelOperationTests`, and `-only-testing:OBAKitTests/ReferencesTests`. Expected: PASS. Run the watchOS portability check. Expected: `BUILD SUCCEEDED`.

- [x] **Step 6: Commit**

```bash
cd /Users/aaron/repos/onebusaway/.worktrees/ios-gtfs-flex && swiftlint lint --quiet | tail -20 && \
git add OBAKitCore/Models/REST/References/Stop.swift OBAKitCore/Models/REST/References/Route.swift "OBAKitTests/Modeling/Model Unit Tests/StopTests.swift" "OBAKitTests/Modeling/Model Unit Tests/RouteOnDemandPointerTests.swift" && \
git commit -m "Decode on-demand service pointers on stops and routes"
```

---

### Task 4: URL builder and `RESTAPIService+OnDemand`

**Files:**
- Create: `OBAKitCore/Models/REST/OnDemand/OnDemandGeometryDetail.swift`
- Modify: `OBAKitCore/Network/RESTAPIURLBuilder.swift` (append to the `REST API URL Builders` extension, before `// MARK: - Survey API URL Builders`)
- Create: `OBAKitCore/Network/RESTAPIService/RESTAPIService+OnDemand.swift`
- Test: `OBAKitTests/Network/RESTAPIURLBuilderTests.swift`
- Test: `OBAKitTests/Modeling/REST Model Service Tests/OnDemandModelOperationTests.swift`

**Interfaces:**
- Consumes: Tasks 1–3 types; `RESTAPIURLBuilder.generateURL(path:params:)`, `NetworkHelpers.escapePathVariable`, `RESTAPIService.getData(for:decodeRESTAPIResponseAs:)`.
- Produces:
  - `public enum OnDemandGeometryDetail: String, Sendable { case none, simplified, full }`
  - `RESTAPIURLBuilder.getOnDemandService(id: String, geometryDetail: OnDemandGeometryDetail) -> URL`, `.getOnDemandServices(agencyID: String, geometryDetail:) -> URL`, `.getOnDemandServices(region: MKCoordinateRegion, geometryDetail:) -> URL`
  - `RESTAPIService.getOnDemandService(id: String, geometryDetail: OnDemandGeometryDetail = .full) async throws -> RESTAPIResponse<OnDemandService>`, `.getOnDemandServices(agencyID: String, geometryDetail: = .simplified) async throws -> RESTAPIResponse<[OnDemandService]>`, `.getOnDemandServices(region: MKCoordinateRegion, geometryDetail: = .simplified) async throws -> RESTAPIResponse<[OnDemandService]>` (all `public nonisolated`).

- [x] **Step 1: Write the failing URL builder tests**

Append inside `RESTAPIURLBuilderTests` in `OBAKitTests/Network/RESTAPIURLBuilderTests.swift`:

```swift
    // MARK: - On-demand

    private func queryValue(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    @Test func testGetOnDemandService() {
        let url = builder.getOnDemandService(id: "5088_77652", geometryDetail: .full)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.path == "/api/ondemand/service/5088_77652.json")
        #expect(queryValue(url, "geometryDetail") == "full")
        #expect(queryValue(url, "key") == "TEST")
    }

    @Test func testGetOnDemandServiceEscapesID() {
        let url = builder.getOnDemandService(id: "CC_CC2 med/x", geometryDetail: .simplified)
        #expect(url.absoluteString.contains("/api/ondemand/service/CC_CC2%20med%2Fx.json"))
    }

    @Test func testGetOnDemandServicesForAgency() {
        let url = builder.getOnDemandServices(agencyID: "CC", geometryDetail: .none)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.path == "/api/ondemand/services-for-agency/CC.json")
        #expect(queryValue(url, "geometryDetail") == "none")
        #expect(queryValue(url, "key") == "TEST")
    }

    @Test func testGetOnDemandServicesForRegion() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 38.83, longitude: -77.05),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.2)
        )
        let url = builder.getOnDemandServices(region: region, geometryDetail: .simplified)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.path == "/api/ondemand/services-for-location.json")
        #expect(queryValue(url, "lat").flatMap(Double.init) == 38.83)
        #expect(queryValue(url, "lon").flatMap(Double.init) == -77.05)
        #expect(queryValue(url, "latSpan").flatMap(Double.init) == 0.1)
        #expect(queryValue(url, "lonSpan").flatMap(Double.init) == 0.2)
        #expect(queryValue(url, "radius") == nil, "viewport mode must not send a radius; radius wins the server tiebreak")
        #expect(queryValue(url, "geometryDetail") == "simplified")
    }
```

Add `import MapKit` to the file's imports.

- [x] **Step 2: Write the failing service tests**

Create `OBAKitTests/Modeling/REST Model Service Tests/OnDemandModelOperationTests.swift`:

```swift
//
//  OnDemandModelOperationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

@Suite(.serialized)
final class OnDemandModelOperationTests: OBATestCase {
    var dataLoader: MockDataLoader!

    override init() async throws {
        try await super.init()
        dataLoader = (restService.dataLoader as! MockDataLoader)
    }

    @Test func `Loading a service by id`() async throws {
        dataLoader.mock(
            URLString: "https://www.example.com/api/ondemand/service/5088_77652.json",
            with: Fixtures.loadData(file: "ondemand_service_alexandria.json")
        )

        let response = try await restService.getOnDemandService(id: "5088_77652")
        let service = response.entry
        #expect(service.id == "5088_77652")
        #expect(service.serviceKind == .zone)
        #expect(service.rules.count == 2)
        #expect(service.areas.map(\.id) == ["5088_area_1449"])
        #expect(service.bookingRules.first?.phoneNumber == "703-746-5222")
        #expect(service.calendars.count == 2)
        #expect(service.route?.longName == "DOT Paratransit")
        #expect(service.agency?.timeZone == "America/Los_Angeles")
        #expect(service.regionIdentifier == pugetSoundRegionIdentifier)

        let requested = dataLoader.recordedRequestURLs.last!
        #expect(URLComponents(url: requested, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "geometryDetail", value: "full")) == true)
    }

    @Test func `Loading services for a region`() async throws {
        dataLoader.mock(
            URLString: "https://www.example.com/api/ondemand/services-for-location.json",
            with: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json")
        )
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 38.83, longitude: -77.05),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )

        let response = try await restService.getOnDemandServices(region: region)
        #expect(response.list.map(\.id) == ["5088_77652"])
        #expect(response.list[0].matchReason == .areaIntersectsViewport)
        #expect(response.outOfRange == false)

        let requested = dataLoader.recordedRequestURLs.last!
        #expect(URLComponents(url: requested, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "geometryDetail", value: "simplified")) == true)
    }

    @Test func `Loading services for an agency`() async throws {
        dataLoader.mock(
            URLString: "https://www.example.com/api/ondemand/services-for-agency/CC.json",
            with: Fixtures.loadData(file: "ondemand_services_for_agency_charlevoix.json")
        )

        let response = try await restService.getOnDemandServices(agencyID: "CC")
        #expect(response.list.map(\.id) == ["CC_CC1", "CC_CC2_med", "CC_CC3", "CC_CC4"])
        #expect(response.list[2].serviceKind == .stopGroup)
        #expect(response.list[2].locationGroups.first?.stopIDs.count == 2)
    }
}
```

- [x] **Step 3: Run the tests to verify they fail**

Run the standard command with `-only-testing:OBAKitTests/RESTAPIURLBuilderTests`. Expected: build failure `has no member 'getOnDemandService'`.

- [x] **Step 4: Create `OnDemandGeometryDetail.swift`**

```swift
//
//  OnDemandGeometryDetail.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// The `geometryDetail` query parameter every `/api/ondemand` endpoint accepts
/// (wiki §3). `bbox` is always present at every level.
public enum OnDemandGeometryDetail: String, Sendable {
    /// `geometry` key omitted. Cheapest; enough for a list row.
    case none
    /// Import-time display geometry (≤256 points per ring, ~15 KB for an
    /// Alexandria-sized zone). What every screen in the app requests: the
    /// verbatim `full` geometry can reach ~750 KB for a county zone.
    case simplified
    /// The feed's verbatim geometry. Never used by the app's screens.
    case full
}
```

- [x] **Step 5: Add the URL builders**

Insert into `RESTAPIURLBuilder.swift` immediately before `// MARK: - Survey API URL Builders`:

```swift
    // MARK: - On-demand

    /// Creates a full URL for the `getOnDemandService` API call.
    ///
    /// - API Endpoint: `/api/ondemand/service/{id}.json`
    ///
    /// - Parameters:
    ///   - id: The combined on-demand service ID.
    ///   - geometryDetail: How much zone geometry to embed in the references.
    /// - Returns: An URL suitable for making a request to retrieve information.
    public func getOnDemandService(id: String, geometryDetail: OnDemandGeometryDetail) -> URL {
        generateURL(
            path: String(format: "/api/ondemand/service/%@.json", NetworkHelpers.escapePathVariable(id)),
            params: ["geometryDetail": geometryDetail.rawValue]
        )
    }

    /// Creates a full URL for the `getOnDemandServices(agencyID:)` API call.
    ///
    /// - API Endpoint: `/api/ondemand/services-for-agency/{id}.json`
    public func getOnDemandServices(agencyID: String, geometryDetail: OnDemandGeometryDetail) -> URL {
        generateURL(
            path: String(format: "/api/ondemand/services-for-agency/%@.json", NetworkHelpers.escapePathVariable(agencyID)),
            params: ["geometryDetail": geometryDetail.rawValue]
        )
    }

    /// Creates a full URL for the `getOnDemandServices(region:)` API call, in
    /// the server's viewport mode (`latSpan`/`lonSpan`, no `radius`).
    ///
    /// - API Endpoint: `/api/ondemand/services-for-location.json`
    public func getOnDemandServices(region: MKCoordinateRegion, geometryDetail: OnDemandGeometryDetail) -> URL {
        generateURL(path: "/api/ondemand/services-for-location.json", params: [
            "lat": region.center.latitude,
            "lon": region.center.longitude,
            "latSpan": region.span.latitudeDelta,
            "lonSpan": region.span.longitudeDelta,
            "geometryDetail": geometryDetail.rawValue
        ])
    }
```

- [x] **Step 6: Create `RESTAPIService+OnDemand.swift`**

```swift
//
//  RESTAPIService+OnDemand.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit

extension RESTAPIService {

    // MARK: - On-demand services (`/api/ondemand`, GTFS-Flex)

    /// Retrieves one on-demand service with its full rules and references.
    ///
    /// - API Endpoint: `/api/ondemand/service/{id}.json`
    ///
    /// - parameter id: The combined service ID (for flex, the route's combined ID).
    /// - parameter geometryDetail: Defaults to the server default, `full`.
    ///   Screens pass `.simplified`.
    /// - throws: ``APIError`` or other errors. A 404 here means an unknown
    ///   service ID, never that the server lacks the namespace.
    /// - returns: The ``RESTAPIResponse`` for ``OnDemandService``.
    public nonisolated func getOnDemandService(id: String, geometryDetail: OnDemandGeometryDetail = .full) async throws -> RESTAPIResponse<OnDemandService> {
        return try await getData(
            for: urlBuilder.getOnDemandService(id: id, geometryDetail: geometryDetail),
            decodeRESTAPIResponseAs: OnDemandService.self
        )
    }

    /// Retrieves every on-demand service of an agency.
    ///
    /// - API Endpoint: `/api/ondemand/services-for-agency/{id}.json`
    ///
    /// - throws: ``APIError`` or other errors. A 404 means an unknown agency
    ///   ID (wiki §3.3); a known agency with no services returns an empty list.
    /// - returns: The ``RESTAPIResponse`` for [``OnDemandService``].
    public nonisolated func getOnDemandServices(agencyID: String, geometryDetail: OnDemandGeometryDetail = .simplified) async throws -> RESTAPIResponse<[OnDemandService]> {
        return try await getData(
            for: urlBuilder.getOnDemandServices(agencyID: agencyID, geometryDetail: geometryDetail),
            decodeRESTAPIResponseAs: [OnDemandService].self
        )
    }

    /// Retrieves the on-demand services whose zones or stops intersect `region`
    /// (the server's viewport mode).
    ///
    /// - API Endpoint: `/api/ondemand/services-for-location.json`
    ///
    /// - throws: ``APIError`` or other errors.
    /// - returns: The ``RESTAPIResponse`` for [``OnDemandService``]; each
    ///   element carries a ``MatchReason``.
    public nonisolated func getOnDemandServices(region: MKCoordinateRegion, geometryDetail: OnDemandGeometryDetail = .simplified) async throws -> RESTAPIResponse<[OnDemandService]> {
        return try await getData(
            for: urlBuilder.getOnDemandServices(region: region, geometryDetail: geometryDetail),
            decodeRESTAPIResponseAs: [OnDemandService].self
        )
    }
}
```

- [x] **Step 7: Run the tests to verify they pass**

Run the standard command with `-only-testing:OBAKitTests/RESTAPIURLBuilderTests` and `-only-testing:OBAKitTests/OnDemandModelOperationTests`. Expected: PASS. Run the watchOS portability check. Expected: `BUILD SUCCEEDED`.

- [x] **Step 8: Commit**

```bash
cd /Users/aaron/repos/onebusaway/.worktrees/ios-gtfs-flex && swiftlint lint --quiet | tail -20 && \
git add OBAKitCore/Models/REST/OnDemand/OnDemandGeometryDetail.swift OBAKitCore/Network/RESTAPIURLBuilder.swift OBAKitCore/Network/RESTAPIService/RESTAPIService+OnDemand.swift OBAKitTests/Network/RESTAPIURLBuilderTests.swift "OBAKitTests/Modeling/REST Model Service Tests/OnDemandModelOperationTests.swift" && \
git commit -m "Add on-demand endpoints to the REST API service"
```

---

### Task 5: `OnDemandSupport` and the `services-for-location` probe

**Files:**
- Create: `OBAKitCore/Network/OnDemandSupport.swift`
- Modify: `OBAKitCore/Network/RESTAPIService/RESTAPIService.swift:12-30`
- Modify: `OBAKitCore/Network/RESTAPIService/RESTAPIService+OnDemand.swift` (`getOnDemandServices(region:)`)
- Modify: `OBAKitTests/Helpers/OBATestCase.swift:126-128` (`buildRESTService` gains an `onDemandSupport:` parameter)
- Test: `OBAKitTests/Network/OnDemandSupportTests.swift`

**Interfaces:**
- Produces:
  - `public final class OnDemandSupport: Sendable { public static let shared: OnDemandSupport; public init(); public func isKnownUnsupported(baseURL: URL) -> Bool; public func recordAbsent(baseURL: URL) }`
  - `RESTAPIService.init(_ configuration: APIServiceConfiguration, dataLoader: URLDataLoader = URLSession.shared, onDemandSupport: OnDemandSupport = .shared)`; `public nonisolated let onDemandSupport: OnDemandSupport`; `public nonisolated let baseURL: URL` (the configuration's base URL, readable without hopping to the actor).
  - Behaviour: only `getOnDemandServices(region:)` calls `recordAbsent` and only on `APIError.requestNotFound` (a real 404 or the blank-200 shape `APIService+GetData` maps to it). Every other error on that call, and every error on the other two calls, leaves support untouched.

- [x] **Step 1: Write the failing tests**

Create `OBAKitTests/Network/OnDemandSupportTests.swift`:

```swift
//
//  OnDemandSupportTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class OnDemandSupportTests: OBATestCase {
    private var support: OnDemandSupport!
    private var dataLoader: MockDataLoader!
    private var service: RESTAPIService!

    private let region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 38.83, longitude: -77.05),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )

    override init() async throws {
        try await super.init()
        support = OnDemandSupport()
        dataLoader = MockDataLoader(testName: name)
        service = buildRESTService(dataLoader: dataLoader, onDemandSupport: support)
    }

    private func mock(path: String, statusCode: Int, data: Data = Data()) {
        dataLoader.mock(data: data, statusCode: statusCode) { request in
            request.url?.path.contains(path) ?? false
        }
    }

    @Test func `Fresh support knows nothing`() {
        #expect(!support.isKnownUnsupported(baseURL: baseURL))
    }

    @Test func `Trailing slash does not change the key`() {
        support.recordAbsent(baseURL: URL(string: "https://www.example.com/")!)
        #expect(support.isKnownUnsupported(baseURL: URL(string: "https://www.example.com")!))
    }

    @Test func `404 on the location probe marks the server unsupported`() async {
        mock(path: "/api/ondemand/services-for-location", statusCode: 404)
        await #expect(throws: APIError.self) {
            _ = try await service.getOnDemandServices(region: region)
        }
        #expect(support.isKnownUnsupported(baseURL: baseURL))
    }

    @Test func `Blank 200 on the location probe marks the server unsupported`() async {
        // Legacy servers answer unknown paths with an empty 200; APIService maps
        // that to requestNotFound for GETs.
        mock(path: "/api/ondemand/services-for-location", statusCode: 200)
        await #expect(throws: APIError.self) {
            _ = try await service.getOnDemandServices(region: region)
        }
        #expect(support.isKnownUnsupported(baseURL: baseURL))
    }

    @Test func `404 on service by id is not-found, not unsupported`() async {
        mock(path: "/api/ondemand/service/", statusCode: 404)
        await #expect(throws: APIError.self) {
            _ = try await service.getOnDemandService(id: "nope")
        }
        #expect(!support.isKnownUnsupported(baseURL: baseURL))
    }

    @Test func `404 on services for agency is not-found, not unsupported`() async {
        mock(path: "/api/ondemand/services-for-agency/", statusCode: 404)
        await #expect(throws: APIError.self) {
            _ = try await service.getOnDemandServices(agencyID: "nope")
        }
        #expect(!support.isKnownUnsupported(baseURL: baseURL))
    }

    @Test func `Server error on the probe is transient`() async {
        mock(path: "/api/ondemand/services-for-location", statusCode: 500)
        await #expect(throws: APIError.self) {
            _ = try await service.getOnDemandServices(region: region)
        }
        #expect(!support.isKnownUnsupported(baseURL: baseURL))
    }

    @Test func `Decode failure on the probe is transient`() async {
        mock(path: "/api/ondemand/services-for-location", statusCode: 200, data: Data("{\"code\":200,\"version\":2,\"data\":{\"list\":\"not-an-array\"}}".utf8))
        await #expect(throws: (any Error).self) {
            _ = try await service.getOnDemandServices(region: region)
        }
        #expect(!support.isKnownUnsupported(baseURL: baseURL))
    }

    @Test func `Success leaves support untouched`() async throws {
        dataLoader.mock(
            URLString: "https://www.example.com/api/ondemand/services-for-location.json",
            with: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json")
        )
        _ = try await service.getOnDemandServices(region: region)
        #expect(!support.isKnownUnsupported(baseURL: baseURL))
    }

    @Test func `Absence is recorded per base URL`() async {
        mock(path: "/api/ondemand/services-for-location", statusCode: 404)
        await #expect(throws: APIError.self) {
            _ = try await service.getOnDemandServices(region: region)
        }
        #expect(support.isKnownUnsupported(baseURL: baseURL))
        #expect(!support.isKnownUnsupported(baseURL: URL(string: "https://other.example.com")!))

        let otherConfig = APIServiceConfiguration(baseURL: URL(string: "https://other.example.com")!, apiKey: apiKey, uuid: uuid, appVersion: appVersion, regionIdentifier: 2)
        let otherService = RESTAPIService(otherConfig, dataLoader: dataLoader, onDemandSupport: support)
        #expect(otherService.baseURL == URL(string: "https://other.example.com")!)
        #expect(!support.isKnownUnsupported(baseURL: otherService.baseURL))
    }
}
```

- [x] **Step 2: Run the tests to verify they fail**

Run the standard command with `-only-testing:OBAKitTests/OnDemandSupportTests`. Expected: build failure `cannot find 'OnDemandSupport' in scope`.

- [x] **Step 3: Create `OnDemandSupport.swift`**

```swift
//
//  OnDemandSupport.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Synchronization

/// Remembers which servers have proven they lack the `/api/ondemand`
/// namespace, so the on-demand map layer can hide itself instead of probing on
/// every pan.
///
/// Keyed by the resolved REST base URL rather than by region, so custom
/// regions work and a region switch consults the right entry. Only the
/// `services-for-location` call records here (it is the cheap probe every map
/// pan already makes); a 404 from `service/{id}` or `services-for-agency` is an
/// ordinary not-found and must never mark a server. Absence lasts for the
/// process lifetime: nothing clears an entry, because a server does not grow
/// the namespace between launches.
///
/// `Mutex` (as in `DecodingErrorReporter`) keeps the class `Sendable` with
/// compiler-checked exclusivity; the readers are nonisolated and synchronous so
/// `@MainActor` layers can consult it without an await.
public final class OnDemandSupport: Sendable {

    public static let shared = OnDemandSupport()

    private let absentBaseURLs = Mutex<Set<String>>([])

    public init() {}

    public func isKnownUnsupported(baseURL: URL) -> Bool {
        let key = Self.key(for: baseURL)
        return absentBaseURLs.withLock { $0.contains(key) }
    }

    public func recordAbsent(baseURL: URL) {
        let key = Self.key(for: baseURL)
        absentBaseURLs.withLock { _ = $0.insert(key) }
    }

    /// `https://host/api/` and `https://host/api` are the same server.
    private static func key(for baseURL: URL) -> String {
        var key = baseURL.absoluteString
        while key.hasSuffix("/") {
            key.removeLast()
        }
        return key
    }
}
```

- [x] **Step 4: Inject support into `RESTAPIService`**

Replace the body of `RESTAPIService.swift` (the actor declaration) with:

```swift
/// Makes API calls to the OBA REST service and converts the server's responses into model objects.
public actor RESTAPIService: @preconcurrency APIService {
    public let configuration: APIServiceConfiguration
    public nonisolated let dataLoader: URLDataLoader

    /// The configuration's base URL, readable without an actor hop. `OnDemandSupport`
    /// keys on it, and `@MainActor` callers consult support synchronously.
    public nonisolated let baseURL: URL

    /// Where the `services-for-location` probe records a server that lacks
    /// `/api/ondemand`. Injectable so tests never share the process-wide cache.
    public nonisolated let onDemandSupport: OnDemandSupport

    public let logger = os.Logger(subsystem: "org.onebusaway.iphone", category: "RESTAPIService")

    nonisolated let urlBuilder: RESTAPIURLBuilder
    nonisolated let decoder: JSONDecoder

    public init(
        _ configuration: APIServiceConfiguration,
        dataLoader: URLDataLoader = URLSession.shared,
        onDemandSupport: OnDemandSupport = .shared
    ) {
        self.configuration = configuration
        self.dataLoader = dataLoader
        self.baseURL = configuration.baseURL
        self.onDemandSupport = onDemandSupport
        self.urlBuilder = RESTAPIURLBuilder(
            baseURL: configuration.baseURL,
            defaultQueryItems: configuration.defaultQueryItems,
            surveyBaseURL: configuration.surveyBaseURL
        )
        self.decoder = JSONDecoder.RESTDecoder(regionIdentifier: configuration.regionIdentifier)
    }
}
```

- [x] **Step 5: Make the location call record absence**

In `RESTAPIService+OnDemand.swift`, replace `getOnDemandServices(region:geometryDetail:)` with:

```swift
    /// Retrieves the on-demand services whose zones or stops intersect `region`
    /// (the server's viewport mode).
    ///
    /// This is the **only** call that probes for the namespace: a
    /// `.requestNotFound` here — a real HTTP 404, or the blank 200 that
    /// `APIService+GetData` maps to the same case — records the server in
    /// ``onDemandSupport`` for the rest of the process. Every other failure,
    /// including `.invalidContentType` and decode errors, is transient and is
    /// simply rethrown.
    ///
    /// - API Endpoint: `/api/ondemand/services-for-location.json`
    ///
    /// - throws: ``APIError`` or other errors.
    /// - returns: The ``RESTAPIResponse`` for [``OnDemandService``]; each
    ///   element carries a ``MatchReason``.
    public nonisolated func getOnDemandServices(region: MKCoordinateRegion, geometryDetail: OnDemandGeometryDetail = .simplified) async throws -> RESTAPIResponse<[OnDemandService]> {
        do {
            return try await getData(
                for: urlBuilder.getOnDemandServices(region: region, geometryDetail: geometryDetail),
                decodeRESTAPIResponseAs: [OnDemandService].self
            )
        } catch let error as APIError {
            if case .requestNotFound = error {
                onDemandSupport.recordAbsent(baseURL: baseURL)
            }
            throw error
        }
    }
```

- [x] **Step 6: Let tests inject support through `OBATestCase`**

In `OBAKitTests/Helpers/OBATestCase.swift`, replace `buildRESTService`:

```swift
    func buildRESTService(dataLoader: MockDataLoader? = nil, onDemandSupport: OnDemandSupport = OnDemandSupport()) -> RESTAPIService {
        let config = APIServiceConfiguration(baseURL: baseURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, regionIdentifier: pugetSoundRegionIdentifier, surveyBaseURL: surveyBaseURL)
        return RESTAPIService(config, dataLoader: dataLoader ?? MockDataLoader(testName: name), onDemandSupport: onDemandSupport)
    }
```

(A fresh `OnDemandSupport()` per test service by default, so no suite can taint another through `.shared`.)

- [x] **Step 7: Run the tests to verify they pass**

Run the standard command with `-only-testing:OBAKitTests/OnDemandSupportTests` and `-only-testing:OBAKitTests/OnDemandModelOperationTests`. Expected: PASS. Run the watchOS portability check. Expected: `BUILD SUCCEEDED`.

- [x] **Step 8: Commit**

```bash
cd /Users/aaron/repos/onebusaway/.worktrees/ios-gtfs-flex && swiftlint lint --quiet | tail -20 && \
git add OBAKitCore/Network/OnDemandSupport.swift OBAKitCore/Network/RESTAPIService/RESTAPIService.swift OBAKitCore/Network/RESTAPIService/RESTAPIService+OnDemand.swift OBAKitTests/Helpers/OBATestCase.swift OBAKitTests/Network/OnDemandSupportTests.swift && \
git commit -m "Record servers that lack the on-demand namespace"
```

---

### Task 6: `BookingDeadlineEvaluator` verified against the shared vectors

**Files:**
- Create: `OBAKitCore/Models/OnDemand/BookingDeadlineEvaluator.swift`
- Test: `OBAKitTests/OnDemand/BookingDeadlineEvaluatorTests.swift`

**Interfaces:**
- Consumes: `OnDemandCalendar`, `OnDemandBookingRule`, `AvailabilityRule`, `GTFSTimeOfDay`, `ServiceDate`, `Weekday` (Task 1).
- Produces (all `public`):
  - `enum BookingState: String, Sendable { case notYetOpen, open, closedForDate, unknown }`
  - `struct BookingEvaluation: Equatable, Sendable { let state: BookingState; let cutoffInstant: Date?; let openInstant: Date?; init(state:cutoffInstant:openInstant:); static let unknown }`
  - `struct BookingDeadlineEvaluator: Sendable { let timeZone: TimeZone; init(timeZone: TimeZone, calendars: [OnDemandCalendar]); func noon(_: ServiceDate) -> Date; func anchor(_: ServiceDate) -> Date; func instant(_: ServiceDate, _: GTFSTimeOfDay) -> Date; func serviceDate(for: Date) -> ServiceDate; func adding(days: Int, to: ServiceDate) -> ServiceDate; func weekday(of: ServiceDate) -> Weekday; func isActive(calendarID: String, on: ServiceDate) -> Bool; func countBack(from: ServiceDate, days: Int, calendarID: String?) -> ServiceDate; func evaluate(rule: AvailabilityRule, bookingRule: OnDemandBookingRule?, travelDate: ServiceDate, now: Date) -> BookingEvaluation; func nextBookableServiceDate(rule: AvailabilityRule, bookingRule: OnDemandBookingRule?, now: Date) -> ServiceDate?; func nextActiveServiceDate(rule: AvailabilityRule, from: ServiceDate) -> ServiceDate? }`

Spec §6 rules implemented here, restated so the implementer needs no other document:
- `anchor(D) = local noon of D − 12 h`; `instant(D, hms) = anchor(D) + hms.seconds`. Never "midnight of D": DST days make midnight-based math off by an hour.
- `now` is whatever the caller passes (the UI passes `Date()`, never the envelope `currentTime`).
- `latestPickup = instant(D, rule.endPickupTime ?? 24:00:00)`.
- No pickup booking rule → `open`, cutoff nil, open nil.
- Type 0 → cutoff = latestPickup, open nil. Fields GTFS forbids for the type are ignored (Charlevoix `booking_rule_CC4`).
- Type 1 → `priorNoticeDurationMin` nil → `unknown`. cutoff = latestPickup − min minutes. open = `durationMax` set ? `instant(D, startPickupTime ?? 00:00:00) − max minutes` : `startDay` set ? `instant(D − startDay calendar days, startTime ?? 00:00:00)` : nil.
- Type 2 → `priorNoticeLastDay` nil → `unknown`. `lastDayDate = countBack(D, lastDay, priorNoticeCalendarID)`; cutoff = `instant(lastDayDate, lastTime ?? 00:00:00)` (null last time → 00:00, conservative). open = `startDay` set ? `instant(countBack(D, startDay, priorNoticeCalendarID), startTime ?? 00:00:00)` : nil. **`countBack` applies to both day fields** (spec §6.1 correction of the wiki).
- Any other type → `unknown`.
- state: `now < open` → `notYetOpen`; else `now > cutoff` → `closedForDate`; else `open`.
- `countBack(D, n, nil)` = D − n calendar days; with a calendar: step back one day at a time counting only days active on that calendar (its days, range and `exceptedDates`) until n are consumed. `countBack(D, 0, _) = D`. An unknown calendar ID falls back to calendar days.
- `nextBookableServiceDate` = earliest D′ from agency-local today (`serviceDate(for: now)`) through the latest `endDate` of the rule's calendars, active on at least one of the rule's calendars, with `evaluate(D′).state == .open`. Bounded at 400 days.

- [x] **Step 1: Write the failing vectors-driven test**

Create `OBAKitTests/OnDemand/BookingDeadlineEvaluatorTests.swift`:

```swift
//
//  BookingDeadlineEvaluatorTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

/// Runs the shared `flex-booking-vectors.json` (mirrored verbatim from maglev's
/// `testdata/`) so iOS, Android and the server agree on one algorithm.
@Suite(.serialized)
final class BookingDeadlineEvaluatorTests: OBATestCase {

    // MARK: - Vectors file schema (spec §6)

    private struct VectorsFile: Decodable {
        let timezone: String
        let calendars: [OnDemandCalendar]
        let vectors: [Vector]
    }

    private struct VectorRule: Decodable {
        let startPickupTime: GTFSTimeOfDay?
        let endPickupTime: GTFSTimeOfDay?
        let calendarIds: [String]
    }

    private struct Expected: Decodable {
        let state: String
        let cutoffInstant: String?
        let openInstant: String?
        let nextBookableServiceDate: String?
    }

    private struct Vector: Decodable {
        let name: String
        let timezone: String?
        let bookingRule: OnDemandBookingRule?
        let rule: VectorRule
        let travelDate: ServiceDate
        let now: String
        let expected: Expected
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private func parse(_ instant: String) -> Date {
        guard let date = Self.iso8601.date(from: instant) else {
            Issue.record("Unparseable instant in vectors file: \(instant)")
            return .distantPast
        }
        return date
    }

    private func loadVectors() throws -> VectorsFile {
        try JSONDecoder().decode(VectorsFile.self, from: Fixtures.loadData(file: "flex-booking-vectors.json"))
    }

    private func availabilityRule(_ rule: VectorRule, bookingRuleID: String?) -> AvailabilityRule {
        AvailabilityRule(
            fromIDs: ["x"], toIDs: ["x"],
            startPickupTime: rule.startPickupTime,
            endPickupTime: rule.endPickupTime,
            endDropOffTime: nil,
            calendarIDs: rule.calendarIds,
            pickupType: 2, dropOffType: 2,
            pickupBookingRuleID: bookingRuleID, dropOffBookingRuleID: bookingRuleID,
            safeDurationFactor: nil, safeDurationOffset: nil
        )
    }

    @Test func `Vectors file is present and non-trivial`() throws {
        let file = try loadVectors()
        #expect(file.vectors.count >= 12)
        #expect(!file.calendars.isEmpty)
        #expect(TimeZone(identifier: file.timezone) != nil)
    }

    @Test func `Every shared vector evaluates as expected`() throws {
        let file = try loadVectors()
        for vector in file.vectors {
            let zoneIdentifier = vector.timezone ?? file.timezone
            guard let timeZone = TimeZone(identifier: zoneIdentifier) else {
                Issue.record("\(vector.name): unknown time zone \(zoneIdentifier)")
                continue
            }
            let evaluator = BookingDeadlineEvaluator(timeZone: timeZone, calendars: file.calendars)
            let rule = availabilityRule(vector.rule, bookingRuleID: vector.bookingRule?.id)
            let now = parse(vector.now)

            let evaluation = evaluator.evaluate(rule: rule, bookingRule: vector.bookingRule, travelDate: vector.travelDate, now: now)

            #expect(evaluation.state.rawValue == vector.expected.state, "\(vector.name): state")
            #expect(evaluation.cutoffInstant == vector.expected.cutoffInstant.map(parse), "\(vector.name): cutoffInstant")
            #expect(evaluation.openInstant == vector.expected.openInstant.map(parse), "\(vector.name): openInstant")

            let next = evaluator.nextBookableServiceDate(rule: rule, bookingRule: vector.bookingRule, now: now)
            #expect(next?.description == vector.expected.nextBookableServiceDate, "\(vector.name): nextBookableServiceDate")
        }
    }

    // MARK: - Primitives the vectors exercise only indirectly

    private var losAngeles: TimeZone { TimeZone(identifier: "America/Los_Angeles")! }

    private var weekdayCalendar: OnDemandCalendar {
        OnDemandCalendar(
            id: "wk", days: [.mon, .tue, .wed, .thu, .fri],
            startDate: ServiceDate("2026-01-01")!, endDate: ServiceDate("2026-12-31")!,
            exceptedDates: [ServiceDate("2026-03-10")!]
        )
    }

    @Test func `Instant is anchored at noon minus twelve hours across a DST change`() {
        let evaluator = BookingDeadlineEvaluator(timeZone: TimeZone(identifier: "America/Detroit")!, calendars: [])
        // 2026-03-08 is the US spring-forward day: the local day is 23 hours long.
        let transition = ServiceDate("2026-03-08")!
        let anchor = evaluator.anchor(transition)
        let noon = evaluator.noon(transition)
        #expect(noon.timeIntervalSince(anchor) == 12 * 3600)
        #expect(evaluator.instant(transition, GTFSTimeOfDay("25:00:00")!) == anchor.addingTimeInterval(25 * 3600))
        #expect(evaluator.serviceDate(for: noon) == transition)
    }

    @Test func `Count back over a calendar skips inactive and excepted days`() {
        let evaluator = BookingDeadlineEvaluator(timeZone: losAngeles, calendars: [weekdayCalendar])
        // Wed 2026-03-11: one service day back skips Tue 03-10 (excepted) → Mon 03-09.
        #expect(evaluator.countBack(from: ServiceDate("2026-03-11")!, days: 1, calendarID: "wk") == ServiceDate("2026-03-09")!)
        // Mon 2026-03-16: one service day back skips the weekend → Fri 03-13.
        #expect(evaluator.countBack(from: ServiceDate("2026-03-16")!, days: 1, calendarID: "wk") == ServiceDate("2026-03-13")!)
        // Calendar days when no calendar is given, or the id is unknown.
        #expect(evaluator.countBack(from: ServiceDate("2026-03-16")!, days: 1, calendarID: nil) == ServiceDate("2026-03-15")!)
        #expect(evaluator.countBack(from: ServiceDate("2026-03-16")!, days: 1, calendarID: "missing") == ServiceDate("2026-03-15")!)
        #expect(evaluator.countBack(from: ServiceDate("2026-03-16")!, days: 0, calendarID: "wk") == ServiceDate("2026-03-16")!)
        // Month boundary, calendar days.
        #expect(evaluator.countBack(from: ServiceDate("2026-03-01")!, days: 1, calendarID: nil) == ServiceDate("2026-02-28")!)
    }

    @Test func `Active days honour range, weekday and exceptions`() {
        let evaluator = BookingDeadlineEvaluator(timeZone: losAngeles, calendars: [weekdayCalendar])
        #expect(evaluator.isActive(calendarID: "wk", on: ServiceDate("2026-03-11")!))
        #expect(!evaluator.isActive(calendarID: "wk", on: ServiceDate("2026-03-10")!), "excepted")
        #expect(!evaluator.isActive(calendarID: "wk", on: ServiceDate("2026-03-14")!), "Saturday")
        #expect(!evaluator.isActive(calendarID: "wk", on: ServiceDate("2027-01-04")!), "after endDate")
        #expect(!evaluator.isActive(calendarID: "nope", on: ServiceDate("2026-03-11")!))
    }

    @Test func `Next active service date starts at the given day`() {
        let evaluator = BookingDeadlineEvaluator(timeZone: losAngeles, calendars: [weekdayCalendar])
        let rule = AvailabilityRule(fromIDs: [], toIDs: [], startPickupTime: nil, endPickupTime: nil, endDropOffTime: nil, calendarIDs: ["wk"], pickupType: 2, dropOffType: 2, pickupBookingRuleID: nil, dropOffBookingRuleID: nil, safeDurationFactor: nil, safeDurationOffset: nil)
        #expect(evaluator.nextActiveServiceDate(rule: rule, from: ServiceDate("2026-03-14")!) == ServiceDate("2026-03-16")!)
        #expect(evaluator.nextActiveServiceDate(rule: rule, from: ServiceDate("2026-03-11")!) == ServiceDate("2026-03-11")!)
        #expect(evaluator.nextActiveServiceDate(rule: rule, from: ServiceDate("2027-06-01")!) == nil)
    }

    @Test func `Unknown booking type is unknown`() {
        let evaluator = BookingDeadlineEvaluator(timeZone: losAngeles, calendars: [weekdayCalendar])
        let rule = AvailabilityRule(fromIDs: [], toIDs: [], startPickupTime: nil, endPickupTime: nil, endDropOffTime: nil, calendarIDs: ["wk"], pickupType: 2, dropOffType: 2, pickupBookingRuleID: "b", dropOffBookingRuleID: nil, safeDurationFactor: nil, safeDurationOffset: nil)
        let bookingRule = try! JSONDecoder().decode(OnDemandBookingRule.self, from: Data("{\"id\":\"b\",\"bookingType\":7}".utf8))
        let evaluation = evaluator.evaluate(rule: rule, bookingRule: bookingRule, travelDate: ServiceDate("2026-03-11")!, now: Date())
        #expect(evaluation == .unknown)
        #expect(evaluator.nextBookableServiceDate(rule: rule, bookingRule: bookingRule, now: Date()) == nil)
    }
}
```

- [x] **Step 2: Run the test to verify it fails**

Run the standard command with `-only-testing:OBAKitTests/BookingDeadlineEvaluatorTests`. Expected: build failure `cannot find 'BookingDeadlineEvaluator' in scope`.

- [x] **Step 3: Create `BookingDeadlineEvaluator.swift`**

```swift
//
//  BookingDeadlineEvaluator.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// The rider-facing booking state of one rule on one travel date.
public enum BookingState: String, Sendable {
    /// `priorNoticeStartDay`/`priorNoticeDurationMax` says booking hasn't opened yet.
    case notYetOpen
    case open
    /// The cutoff has passed for this date.
    case closedForDate
    /// The feed omitted a conditionally-required field, so no deadline can be
    /// computed. A client-only state, never on the wire (spec §6.2).
    case unknown
}

public struct BookingEvaluation: Equatable, Sendable {
    public let state: BookingState
    public let cutoffInstant: Date?
    public let openInstant: Date?

    public init(state: BookingState, cutoffInstant: Date?, openInstant: Date?) {
        self.state = state
        self.cutoffInstant = cutoffInstant
        self.openInstant = openInstant
    }

    public static let unknown = BookingEvaluation(state: .unknown, cutoffInstant: nil, openInstant: nil)
}

/// The normative booking-deadline algorithm (wiki §2.5 as corrected by spec
/// §6), shared with Android and verified by `flex-booking-vectors.json`.
///
/// Every value is a **service day in the agency's time zone**. Service days
/// are anchored GTFS-style at local noon minus twelve hours, so a `25:00:00`
/// window and a DST transition both come out right. `now` is supplied by the
/// caller: the UI passes the device wall clock, never the envelope
/// `currentTime` (responses are long-cached and it can be hours stale).
public struct BookingDeadlineEvaluator: Sendable {
    public let timeZone: TimeZone
    private let calendar: Calendar
    private let calendarsByID: [String: OnDemandCalendar]

    /// Caps every day-stepping loop: a calendar with no active days, or a
    /// rule whose calendars end years out, must not spin.
    private static let maximumLookaheadDays = 400

    public init(timeZone: TimeZone, calendars: [OnDemandCalendar]) {
        self.timeZone = timeZone
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        self.calendar = gregorian
        self.calendarsByID = Dictionary(calendars.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Service-day arithmetic

    /// Local noon of `date`. Always exists in the Gregorian calendar, which is
    /// why noon — not midnight, which DST can skip — is the anchor.
    public func noon(_ date: ServiceDate) -> Date {
        var components = DateComponents()
        components.year = date.year
        components.month = date.month
        components.day = date.day
        components.hour = 12
        guard let noon = calendar.date(from: components) else {
            preconditionFailure("Gregorian noon must exist for \(date)")
        }
        return noon
    }

    /// `anchor(date, tz) = local noon of date in tz, minus 12 hours`.
    public func anchor(_ date: ServiceDate) -> Date {
        noon(date).addingTimeInterval(-12 * 3600)
    }

    /// `instant(date, hms, tz) = anchor(date, tz) + hms`; `hms` may exceed 24 h.
    public func instant(_ date: ServiceDate, _ time: GTFSTimeOfDay) -> Date {
        anchor(date).addingTimeInterval(TimeInterval(time.seconds))
    }

    /// The agency-local calendar date containing `instant`.
    public func serviceDate(for instant: Date) -> ServiceDate {
        let components = calendar.dateComponents([.year, .month, .day], from: instant)
        return ServiceDate(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
    }

    /// `date` shifted by `days` calendar days, stepping through noon so DST
    /// changes cannot land on the wrong day.
    public func adding(days: Int, to date: ServiceDate) -> ServiceDate {
        guard let shifted = calendar.date(byAdding: .day, value: days, to: noon(date)) else {
            return date
        }
        return serviceDate(for: shifted)
    }

    public func weekday(of date: ServiceDate) -> Weekday {
        Weekday(calendarWeekday: calendar.component(.weekday, from: noon(date)))
    }

    // MARK: - Calendars

    /// Whether `calendarID` runs on `date`: inside its range, on one of its
    /// weekdays, and not an `exceptedDates` entry. Unknown ids are never active.
    public func isActive(calendarID: String, on date: ServiceDate) -> Bool {
        guard let serviceCalendar = calendarsByID[calendarID] else { return false }
        guard date >= serviceCalendar.startDate, date <= serviceCalendar.endDate else { return false }
        guard serviceCalendar.days.contains(weekday(of: date)) else { return false }
        return !serviceCalendar.exceptedDates.contains(date)
    }

    /// `countBack(D, n, calendarId)` from spec §6: calendar days when there is
    /// no (known) calendar, otherwise the n-th preceding day active on it.
    public func countBack(from date: ServiceDate, days count: Int, calendarID: String?) -> ServiceDate {
        guard count > 0 else { return date }
        guard let calendarID, calendarsByID[calendarID] != nil else {
            return adding(days: -count, to: date)
        }

        var remaining = count
        var cursor = date
        var stepped = 0
        while remaining > 0 && stepped < Self.maximumLookaheadDays {
            cursor = adding(days: -1, to: cursor)
            stepped += 1
            if isActive(calendarID: calendarID, on: cursor) {
                remaining -= 1
            }
        }
        return cursor
    }

    // MARK: - Evaluation

    /// `evaluate(rule, bookingRule, D, now, tz, calendars)` from spec §6.
    /// `bookingRule` is the rule's *pickup* booking rule; pass nil when the
    /// rule has no `pickupBookingRuleId` (no notice required).
    public func evaluate(
        rule: AvailabilityRule,
        bookingRule: OnDemandBookingRule?,
        travelDate: ServiceDate,
        now: Date
    ) -> BookingEvaluation {
        let latestPickup = instant(travelDate, rule.endPickupTime ?? .endOfServiceDay)

        guard let bookingRule else {
            return BookingEvaluation(state: .open, cutoffInstant: nil, openInstant: nil)
        }

        let cutoff: Date
        let open: Date?

        switch bookingRule.bookingType {
        case 0:
            // Real-time: booked at ride time. Notice fields are forbidden for
            // this type and ignored even when a feed ships them.
            cutoff = latestPickup
            open = nil

        case 1:
            // Same-day, minutes-based. A missing minimum would invent the latest
            // possible deadline — the worst failure — so it is unknown instead.
            guard let minimumMinutes = bookingRule.priorNoticeDurationMin else {
                return .unknown
            }
            cutoff = latestPickup.addingTimeInterval(-Double(minimumMinutes) * 60)
            if let maximumMinutes = bookingRule.priorNoticeDurationMax {
                open = instant(travelDate, rule.startPickupTime ?? .midnight)
                    .addingTimeInterval(-Double(maximumMinutes) * 60)
            } else if let startDay = bookingRule.priorNoticeStartDay {
                open = instant(adding(days: -startDay, to: travelDate), bookingRule.priorNoticeStartTime ?? .midnight)
            } else {
                open = nil
            }

        case 2:
            // Prior day(s). The notice calendar counts service days for both the
            // last day and the start day (spec §6.1).
            guard let lastDay = bookingRule.priorNoticeLastDay else {
                return .unknown
            }
            let noticeCalendarID = bookingRule.priorNoticeCalendarID
            let lastDayDate = countBack(from: travelDate, days: lastDay, calendarID: noticeCalendarID)
            // A missing last time means 00:00 — never later than any real deadline.
            cutoff = instant(lastDayDate, bookingRule.priorNoticeLastTime ?? .midnight)
            open = bookingRule.priorNoticeStartDay.map { startDay in
                instant(countBack(from: travelDate, days: startDay, calendarID: noticeCalendarID), bookingRule.priorNoticeStartTime ?? .midnight)
            }

        default:
            return .unknown
        }

        let state: BookingState
        if let open, now < open {
            state = .notYetOpen
        } else if now > cutoff {
            state = .closedForDate
        } else {
            state = .open
        }
        return BookingEvaluation(state: state, cutoffInstant: cutoff, openInstant: open)
    }

    /// The earliest active service day of `rule`, on or after `date`, bounded
    /// by the rule's latest calendar `endDate`.
    public func nextActiveServiceDate(rule: AvailabilityRule, from date: ServiceDate) -> ServiceDate? {
        guard let lastDate = rule.calendarIDs.compactMap({ calendarsByID[$0]?.endDate }).max() else {
            return nil
        }
        var cursor = date
        var stepped = 0
        while cursor <= lastDate && stepped < Self.maximumLookaheadDays {
            if rule.calendarIDs.contains(where: { isActive(calendarID: $0, on: cursor) }) {
                return cursor
            }
            cursor = adding(days: 1, to: cursor)
            stepped += 1
        }
        return nil
    }

    /// `nextBookableServiceDate` from spec §6: the earliest active service day
    /// from the agency-local today whose evaluation is `open`.
    public func nextBookableServiceDate(
        rule: AvailabilityRule,
        bookingRule: OnDemandBookingRule?,
        now: Date
    ) -> ServiceDate? {
        var cursor: ServiceDate? = serviceDate(for: now)
        var stepped = 0
        while let candidate = cursor.flatMap({ nextActiveServiceDate(rule: rule, from: $0) }), stepped < Self.maximumLookaheadDays {
            let evaluation = evaluate(rule: rule, bookingRule: bookingRule, travelDate: candidate, now: now)
            if evaluation.state == .open {
                return candidate
            }
            if evaluation.state == .unknown {
                return nil
            }
            cursor = adding(days: 1, to: candidate)
            stepped += 1
        }
        return nil
    }
}
```

- [x] **Step 4: Run the tests to verify they pass**

Run the standard command with `-only-testing:OBAKitTests/BookingDeadlineEvaluatorTests`. Expected: PASS. If a shared vector fails, compare the vector's `expected` against spec §6 by hand before touching the evaluator — the vectors are the contract; the maglev-side file wins over a hunch, and a genuine vectors bug is reported back to the maglev plan rather than papered over here. Run the watchOS portability check. Expected: `BUILD SUCCEEDED`.

- [x] **Step 5: Commit**

```bash
cd /Users/aaron/repos/onebusaway/.worktrees/ios-gtfs-flex && swiftlint lint --quiet | tail -20 && \
git add OBAKitCore/Models/OnDemand/BookingDeadlineEvaluator.swift OBAKitTests/OnDemand/BookingDeadlineEvaluatorTests.swift && \
git commit -m "Add the shared booking deadline evaluator"
```

---

### Task 7: `OnDemandServiceSummary` presenter

**Files:**
- Create: `OBAKitCore/Models/OnDemand/OnDemandServiceSummary.swift`
- Test: `OBAKitTests/OnDemand/OnDemandServiceSummaryTests.swift`

**Interfaces:**
- Consumes: `OnDemandService`, `BookingDeadlineEvaluator`, `Weekday`, `GTFSTimeOfDay`.
- Produces (`public`):
  - `struct OnDemandServiceSummary: Equatable, Sendable { enum BookingLine: Equatable, Sendable { case bookBy(deadline: String, travelDate: String); case opensAt(String); case noNoticeRequired; case closed; case unknown }; struct ServiceWindow: Equatable, Hashable, Sendable { let days: String; let hours: String? /* nil = all service hours */ }; let bookingLine: BookingLine; let windows: [ServiceWindow]; let phoneNumber: String?; let phoneURL: URL?; let bookingURL: URL?; let infoURL: URL?; let message: String?; init(service: OnDemandService, timeZone: TimeZone, now: Date, locale: Locale) }`
  - All strings are Foundation-formatted (`DateFormatter`, weekday symbols); the presenter declares no `OBALoc` keys. OBAKit wraps them in sentence templates (Task 8).

Behaviour:
- `windows`: one per distinct (days, hours) pair across the rules, in rule order. `days` collapses contiguous Mon…Sun runs with an en dash (`Mon–Sat`, `Sun`, `Mon, Wed, Fri`) using the locale's `shortWeekdaySymbols`; `hours` is `"\(start) – \(end)"` in the locale's short time style in the agency zone, computed as `anchor(today) + seconds`, or nil when the rule has no pickup times.
- `bookingLine`: evaluate every rule against its pickup booking rule for `nextBookableServiceDate`. If any rule has a `pickupBookingRuleID` that `service.bookingRule(id:)` cannot resolve → `.unknown`. If no rules → `.unknown`. Otherwise pick the candidate with the earliest date, ties broken by earliest cutoff (conservative, wiki §2.5 multi-rule note): cutoff nil → `.noNoticeRequired`; else `.bookBy(deadline: relative medium-date short-time in agency zone, travelDate: "EEE, MMM d"-template on the travel date)`. If no rule is bookable: if any rule's next active date evaluates `.notYetOpen` → `.opensAt(formatted openInstant)` for the earliest such open instant; if any rule evaluates `.unknown` → `.unknown`; else `.closed`.
- `phoneNumber`/`message`/URLs come from the first resolved pickup booking rule (rules are already server-sorted); `phoneURL` = `tel://` + the digits and `+` of `phoneNumber` (same cleaning as `Agency.callURL`).

- [x] **Step 1: Write the failing tests**

Create `OBAKitTests/OnDemand/OnDemandServiceSummaryTests.swift`:

```swift
//
//  OnDemandServiceSummaryTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

@Suite(.serialized)
final class OnDemandServiceSummaryTests: OBATestCase {

    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    private let enUS = Locale(identifier: "en_US")

    /// 2026-03-10 16:00 in Los Angeles (a Tuesday), one hour before Alexandria's 17:00 cutoff.
    private let now = ISO8601DateFormatter().date(from: "2026-03-10T23:00:00Z")!

    private func alexandria(transform: ((inout [String: Any]) -> Void)? = nil) throws -> OnDemandService {
        let data = Fixtures.loadData(file: "ondemand_service_alexandria.json")
        guard let transform else {
            return try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<OnDemandService>.self, from: data).entry
        }
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        transform(&json)
        return try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<OnDemandService>.self, from: JSONSerialization.data(withJSONObject: json)).entry
    }

    private func summary(_ service: OnDemandService, now: Date? = nil) -> OnDemandServiceSummary {
        OnDemandServiceSummary(service: service, timeZone: losAngeles, now: now ?? self.now, locale: enUS)
    }

    @Test func `Windows collapse contiguous days and format hours in the agency zone`() throws {
        let summary = summary(try alexandria())
        #expect(summary.windows.count == 2)
        #expect(summary.windows[0].days == "Mon–Sat")
        #expect(summary.windows[1].days == "Sun")
        let monSat = summary.windows[0].hours ?? ""
        #expect(monSat.contains("5:00"), monSat)
        #expect(monSat.contains("12:50"), "24:50 renders as the next day's 12:50; got \(monSat)")
        #expect(monSat.contains("–"))
        #expect(summary.windows[1].hours?.contains("7:00") == true)
    }

    @Test func `Book-by line uses the next bookable date and its cutoff`() throws {
        let summary = summary(try alexandria())
        guard case .bookBy(let deadline, let travelDate) = summary.bookingLine else {
            Issue.record("expected bookBy, got \(summary.bookingLine)")
            return
        }
        // Cutoff = 2026-03-10 17:00 LA for a ride on Wed 2026-03-11.
        #expect(deadline.contains("5:00"), deadline)
        #expect(deadline.localizedCaseInsensitiveContains("today"), deadline)
        #expect(travelDate.contains("Mar 11"), travelDate)
        #expect(travelDate.contains("Wed"), travelDate)
    }

    @Test func `Contact details come from the pickup booking rule`() throws {
        let summary = summary(try alexandria())
        #expect(summary.phoneNumber == "703-746-5222")
        #expect(summary.phoneURL == URL(string: "tel://7037465222"))
        #expect(summary.infoURL == URL(string: "https://www.alexandriava.gov/Paratransit"))
        #expect(summary.bookingURL?.host() == "spare-rider-alexandriadot-production.vercel.app")
        #expect(summary.message?.hasPrefix("DOT is the City of Alexandria") == true)
    }

    @Test func `Degenerate service with no rules is unknown with no windows`() throws {
        let service = try alexandria { json in
            var data = json["data"] as! [String: Any]
            var entry = data["entry"] as! [String: Any]
            entry["rules"] = []
            data["entry"] = entry
            json["data"] = data
        }
        let summary = summary(service)
        #expect(summary.bookingLine == .unknown)
        #expect(summary.windows.isEmpty)
        #expect(summary.phoneNumber == nil)
    }

    @Test func `Dangling booking rule id yields unknown`() throws {
        let service = try alexandria { json in
            var data = json["data"] as! [String: Any]
            var references = data["references"] as! [String: Any]
            references["bookingRules"] = []
            data["references"] = references
            json["data"] = data
        }
        let summary = summary(service)
        #expect(summary.bookingLine == .unknown)
        #expect(summary.windows.count == 2, "windows do not depend on booking rules")
    }

    @Test func `No pickup booking rule means no notice required`() throws {
        let service = try alexandria { json in
            var data = json["data"] as! [String: Any]
            var entry = data["entry"] as! [String: Any]
            entry["rules"] = (entry["rules"] as! [[String: Any]]).map { rule in
                var rule = rule
                rule["pickupBookingRuleId"] = NSNull()
                return rule
            }
            data["entry"] = entry
            json["data"] = data
        }
        #expect(summary(service).bookingLine == .noNoticeRequired)
    }

    @Test func `Calendar that starts in the future yields opens-at`() throws {
        let service = try alexandria { json in
            var data = json["data"] as! [String: Any]
            var references = data["references"] as! [String: Any]
            references["calendars"] = (references["calendars"] as! [[String: Any]]).map { calendar in
                var calendar = calendar
                calendar["startDate"] = "2026-04-01"
                return calendar
            }
            data["references"] = references
            json["data"] = data
        }
        // First active day is Wed 2026-04-01; booking opens 14 days before, 2026-03-18 00:00 LA.
        guard case .opensAt(let text) = summary(service).bookingLine else {
            Issue.record("expected opensAt, got \(summary(service).bookingLine)")
            return
        }
        #expect(text.contains("Mar 18"), text)
    }

    @Test func `Calendar that has ended yields closed`() throws {
        let service = try alexandria { json in
            var data = json["data"] as! [String: Any]
            var references = data["references"] as! [String: Any]
            references["calendars"] = (references["calendars"] as! [[String: Any]]).map { calendar in
                var calendar = calendar
                calendar["endDate"] = "2026-01-31"
                return calendar
            }
            data["references"] = references
            json["data"] = data
        }
        #expect(summary(service).bookingLine == .closed)
    }

    @Test func `Rule without pickup times reports all-hours`() throws {
        let service = try alexandria { json in
            var data = json["data"] as! [String: Any]
            var entry = data["entry"] as! [String: Any]
            entry["rules"] = (entry["rules"] as! [[String: Any]]).map { rule in
                var rule = rule
                rule["startPickupTime"] = NSNull()
                rule["endPickupTime"] = NSNull()
                rule["endDropOffTime"] = NSNull()
                return rule
            }
            data["entry"] = entry
            json["data"] = data
        }
        let summary = summary(service)
        #expect(summary.windows.count == 2)
        #expect(summary.windows[0].hours == nil)
    }

    @Test func `Day runs render as ranges and lists`() {
        let symbols = DateFormatter().shortWeekdaySymbols!  // en_US in the GMT-pinned test process
        #expect(OnDemandServiceSummary.daysText([.mon, .tue, .wed, .thu, .fri, .sat], shortWeekdaySymbols: symbols) == "Mon–Sat")
        #expect(OnDemandServiceSummary.daysText([.mon, .wed, .fri], shortWeekdaySymbols: symbols) == "Mon, Wed, Fri")
        #expect(OnDemandServiceSummary.daysText([.sat, .sun], shortWeekdaySymbols: symbols) == "Sat–Sun")
        #expect(OnDemandServiceSummary.daysText([.mon, .tue, .thu, .fri, .sat, .sun], shortWeekdaySymbols: symbols) == "Mon–Tue, Thu–Sun")
        #expect(OnDemandServiceSummary.daysText([], shortWeekdaySymbols: symbols) == "")
    }
}
```

- [x] **Step 2: Run the tests to verify they fail**

Run the standard command with `-only-testing:OBAKitTests/OnDemandServiceSummaryTests`. Expected: build failure `cannot find 'OnDemandServiceSummary' in scope`.

- [x] **Step 3: Create `OnDemandServiceSummary.swift`**

```swift
//
//  OnDemandServiceSummary.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// The rider-facing facts about an on-demand service, formatted for a locale
/// in the agency's time zone: when it runs, by when to book, how to book.
///
/// Carries no localized sentences of its own — only Foundation-formatted
/// dates, times and day names — so OBAKit (and the watch, later) wrap the
/// pieces in their own templates and OBAKitCore adds no strings.
public struct OnDemandServiceSummary: Equatable, Sendable {

    public enum BookingLine: Equatable, Sendable {
        /// "Book by `deadline` for a ride on `travelDate`."
        case bookBy(deadline: String, travelDate: String)
        /// Booking for the next service day hasn't opened yet.
        case opensAt(String)
        /// The next service day's rule has no pickup booking rule.
        case noNoticeRequired
        /// Every remaining service day's deadline has passed (or the calendars ended).
        case closed
        /// A missing field or an unresolved booking rule; show contact details
        /// and no deadline line (spec §6.2).
        case unknown
    }

    public struct ServiceWindow: Equatable, Hashable, Sendable {
        /// e.g. "Mon–Sat".
        public let days: String
        /// e.g. "5:00 AM – 12:50 AM"; nil when the rule runs all service hours.
        public let hours: String?
    }

    public let bookingLine: BookingLine
    public let windows: [ServiceWindow]
    public let phoneNumber: String?
    public let phoneURL: URL?
    public let bookingURL: URL?
    public let infoURL: URL?
    public let message: String?

    public init(service: OnDemandService, timeZone: TimeZone, now: Date, locale: Locale) {
        let evaluator = BookingDeadlineEvaluator(timeZone: timeZone, calendars: service.calendars)
        let formatters = SummaryFormatters(timeZone: timeZone, locale: locale)

        windows = Self.windows(for: service, evaluator: evaluator, formatters: formatters, now: now)
        bookingLine = Self.bookingLine(for: service, evaluator: evaluator, formatters: formatters, now: now)

        let contact = service.rules.lazy.compactMap { service.bookingRule(id: $0.pickupBookingRuleID) }.first
        phoneNumber = contact?.phoneNumber
        phoneURL = contact?.phoneNumber.flatMap(Self.telephoneURL)
        bookingURL = contact?.bookingURL
        infoURL = contact?.infoURL
        message = contact?.message ?? contact?.pickupMessage
    }

    // MARK: - Windows

    private static func windows(for service: OnDemandService, evaluator: BookingDeadlineEvaluator, formatters: SummaryFormatters, now: Date) -> [ServiceWindow] {
        let calendarsByID = Dictionary(service.calendars.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Hours are a time-of-day; any day works, today keeps DST offsets current.
        let today = evaluator.serviceDate(for: now)
        var seen = Set<ServiceWindow>()
        var result: [ServiceWindow] = []

        for rule in service.rules {
            let days = Set(rule.calendarIDs.compactMap { calendarsByID[$0] }.flatMap(\.days))
            let hours: String?
            if let start = rule.startPickupTime, let end = rule.endPickupTime {
                hours = "\(formatters.time(evaluator.instant(today, start))) – \(formatters.time(evaluator.instant(today, end)))"
            } else {
                hours = nil
            }
            let window = ServiceWindow(days: daysText(Array(days), shortWeekdaySymbols: formatters.shortWeekdaySymbols), hours: hours)
            if seen.insert(window).inserted {
                result.append(window)
            }
        }
        return result
    }

    /// Collapses weekdays into localized runs: `Mon–Sat`, `Sat–Sun`,
    /// `Mon, Wed, Fri`, `Mon–Tue, Thu–Sun`. `shortWeekdaySymbols` is indexed
    /// Sunday-first, as `DateFormatter` supplies it.
    public static func daysText(_ days: [Weekday], shortWeekdaySymbols: [String]) -> String {
        let ordered = Weekday.allCases.filter { days.contains($0) }
        guard !ordered.isEmpty else { return "" }

        func symbol(_ day: Weekday) -> String {
            let index = day.calendarWeekday - 1
            return shortWeekdaySymbols.indices.contains(index) ? shortWeekdaySymbols[index] : day.rawValue
        }

        var runs: [[Weekday]] = []
        for day in ordered {
            if let last = runs.last?.last, Weekday.allCases.firstIndex(of: day) == Weekday.allCases.firstIndex(of: last)! + 1 {
                runs[runs.count - 1].append(day)
            } else {
                runs.append([day])
            }
        }
        return runs.map { run in
            run.count >= 2 ? "\(symbol(run[0]))–\(symbol(run[run.count - 1]))" : symbol(run[0])
        }.joined(separator: ", ")
    }

    // MARK: - Booking line

    private struct Candidate {
        let travelDate: ServiceDate
        let evaluation: BookingEvaluation
    }

    private static func bookingLine(for service: OnDemandService, evaluator: BookingDeadlineEvaluator, formatters: SummaryFormatters, now: Date) -> BookingLine {
        guard !service.rules.isEmpty else { return .unknown }

        var bookable: [Candidate] = []
        var notYetOpen: [Date] = []
        var sawUnknown = false

        for rule in service.rules {
            let bookingRule = service.bookingRule(id: rule.pickupBookingRuleID)
            // Referenced but missing is not "no notice": nothing can be promised.
            if rule.pickupBookingRuleID != nil && bookingRule == nil {
                return .unknown
            }

            if let date = evaluator.nextBookableServiceDate(rule: rule, bookingRule: bookingRule, now: now) {
                bookable.append(Candidate(travelDate: date, evaluation: evaluator.evaluate(rule: rule, bookingRule: bookingRule, travelDate: date, now: now)))
                continue
            }

            if let nextActive = evaluator.nextActiveServiceDate(rule: rule, from: evaluator.serviceDate(for: now)) {
                let evaluation = evaluator.evaluate(rule: rule, bookingRule: bookingRule, travelDate: nextActive, now: now)
                switch evaluation.state {
                case .notYetOpen:
                    if let open = evaluation.openInstant { notYetOpen.append(open) }
                case .unknown:
                    sawUnknown = true
                case .open, .closedForDate:
                    break
                }
            }
        }

        // Earliest date wins; on the same date the earliest cutoff is the one
        // to show — never later than any real deadline the rider might hit.
        if let best = bookable.min(by: { lhs, rhs in
            if lhs.travelDate != rhs.travelDate { return lhs.travelDate < rhs.travelDate }
            return (lhs.evaluation.cutoffInstant ?? .distantFuture) < (rhs.evaluation.cutoffInstant ?? .distantFuture)
        }) {
            guard let cutoff = best.evaluation.cutoffInstant else { return .noNoticeRequired }
            return .bookBy(deadline: formatters.deadline(cutoff), travelDate: formatters.travelDate(evaluator.noon(best.travelDate)))
        }

        if let earliestOpen = notYetOpen.min() {
            return .opensAt(formatters.deadline(earliestOpen))
        }
        return sawUnknown ? .unknown : .closed
    }

    // MARK: - Formatting

    /// Named to avoid shadowing OBAKitCore's `Formatters` inside this type.
    private struct SummaryFormatters {
        let timeFormatter: DateFormatter
        let deadlineFormatter: DateFormatter
        let travelDateFormatter: DateFormatter
        let shortWeekdaySymbols: [String]

        init(timeZone: TimeZone, locale: Locale) {
            timeFormatter = DateFormatter()
            timeFormatter.locale = locale
            timeFormatter.timeZone = timeZone
            timeFormatter.dateStyle = .none
            timeFormatter.timeStyle = .short

            deadlineFormatter = DateFormatter()
            deadlineFormatter.locale = locale
            deadlineFormatter.timeZone = timeZone
            deadlineFormatter.dateStyle = .medium
            deadlineFormatter.timeStyle = .short
            deadlineFormatter.doesRelativeDateFormatting = true

            travelDateFormatter = DateFormatter()
            travelDateFormatter.locale = locale
            travelDateFormatter.timeZone = timeZone
            travelDateFormatter.setLocalizedDateFormatFromTemplate("EEEMMMd")

            let symbols = DateFormatter()
            symbols.locale = locale
            shortWeekdaySymbols = symbols.shortWeekdaySymbols ?? Weekday.allCases.map(\.rawValue)
        }

        func time(_ date: Date) -> String { timeFormatter.string(from: date) }
        func deadline(_ date: Date) -> String { deadlineFormatter.string(from: date) }
        func travelDate(_ date: Date) -> String { travelDateFormatter.string(from: date) }
    }

    /// Same cleaning as `Agency.callURL`: keep digits and `+`.
    private static func telephoneURL(_ raw: String) -> URL? {
        let cleaned = raw.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        guard !cleaned.isEmpty else { return nil }
        return URL(string: "tel://\(cleaned)")
    }
}
```

- [x] **Step 4: Run the tests to verify they pass**

Run the standard command with `-only-testing:OBAKitTests/OnDemandServiceSummaryTests`. Expected: PASS. If `deadline.localizedCaseInsensitiveContains("today")` fails, print `deadline` in the failure and check that the test process's `now` (16:00 LA on 2026-03-10) and the cutoff (17:00 LA the same day) share a local date — they must; do not loosen the assertion. Run the watchOS portability check. Expected: `BUILD SUCCEEDED`.

- [x] **Step 5: Commit**

```bash
cd /Users/aaron/repos/onebusaway/.worktrees/ios-gtfs-flex && swiftlint lint --quiet | tail -20 && \
git add OBAKitCore/Models/OnDemand/OnDemandServiceSummary.swift OBAKitTests/OnDemand/OnDemandServiceSummaryTests.swift && \
git commit -m "Add the on-demand service summary presenter"
```

---

### Task 8: Strings, `OnDemandServiceView`, its UIKit host and the router entry

**Files:**
- Create: `OBAKit/Strings/Strings+OnDemand.swift`
- Modify: `OBAKit/Strings/{ar,en,es,fil,fr,it,ko,pl,pt-BR,ru,vi,zh-Hans,zh-Hant}.lproj/Localizable.strings` (append the same block to all 13)
- Create: `OBAKit/OnDemand/ServiceArea+MapKit.swift`
- Create: `OBAKit/OnDemand/OnDemandServiceView.swift`
- Create: `OBAKit/OnDemand/OnDemandServiceViewController.swift`
- Modify: `OBAKit/ViewRouting/Router.swift` (after `navigateTo(alert:locale:from:)`)
- Test: `OBAKitTests/OnDemand/OnDemandServiceViewTests.swift`
- Test: `OBAKitTests/Strings/LocalizationTests.swift` (existing; must stay green)

**Interfaces:**
- Consumes: `OnDemandService`, `OnDemandServiceSummary`, `ServiceArea`, `ServiceKind`, `Application.open(_:options:completionHandler:)`, `ViewRouter.navigate(to:from:)`.
- Produces:
  - `extension Strings` (OBAKit, `static let`): `onDemandZonesLayer`, `onDemandZonesUnavailable`, `onDemandSectionTitle`, `onDemandWhenHeader`, `onDemandBookingHeader`, `onDemandBookByFormat` (`%1$@` deadline, `%2$@` travel date), `onDemandBookingOpensFormat` (`%@`), `onDemandNoNoticeRequired`, `onDemandBookingClosed`, `onDemandCallFormat` (`%@`), `onDemandBookOnline`, `onDemandMoreInfo`, `onDemandAllHours`, `onDemandNoServices`, `onDemandListTitle`, `agenciesOnDemandServices`; `static func onDemandKindTitle(_ kind: ServiceKind) -> String`.
  - `extension ServiceArea { var mkPolygons: [MKPolygon] }` — one `MKPolygon` per polygon, exterior ring first, holes as `interiorPolygons`; empty rings skipped.
  - `struct OnDemandServiceView: View { init(service: OnDemandService, summary: OnDemandServiceSummary?, onOpenURL: @escaping (URL) -> Void); var showsMap: Bool; var bookingLineText: String? }`
  - `final class OnDemandServiceViewController: UIHostingController<OnDemandServiceView> { init(application: Application, service: OnDemandService) }`
  - `ViewRouter.navigateTo(onDemandService: OnDemandService, from: UIViewController)`

- [x] **Step 1: Write the failing tests**

Create `OBAKitTests/OnDemand/OnDemandServiceViewTests.swift`:

```swift
//
//  OnDemandServiceViewTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

@MainActor
@Suite(.serialized)
final class OnDemandServiceViewTests: OBATestCase {

    private func alexandria() throws -> OnDemandService {
        try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<OnDemandService>.self, from: Fixtures.loadData(file: "ondemand_service_alexandria.json")).entry
    }

    private func charlevoixFerry() throws -> OnDemandService {
        let list = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<[OnDemandService]>.self, from: Fixtures.loadData(file: "ondemand_services_for_agency_charlevoix.json")).list
        return list.first { $0.id == "CC_CC3" }!
    }

    private var now: Date { ISO8601DateFormatter().date(from: "2026-03-10T23:00:00Z")! }

    @Test func `MKPolygon carries interior rings`() throws {
        let json = """
        {"id":"x","name":null,"description":null,"bbox":[0,0,10,10],
         "geometry":{"type":"Polygon","coordinates":[[[0,0],[10,0],[10,10],[0,10],[0,0]],[[4,4],[6,4],[6,6],[4,6],[4,4]]]}}
        """
        let area = try JSONDecoder().decode(ServiceArea.self, from: Data(json.utf8))
        let polygons = area.mkPolygons
        #expect(polygons.count == 1)
        #expect(polygons[0].pointCount == 5)
        #expect(polygons[0].interiorPolygons?.count == 1)
        #expect(polygons[0].interiorPolygons?.first?.pointCount == 5)
    }

    @Test func `Area without geometry yields no polygons`() throws {
        let area = try JSONDecoder().decode(ServiceArea.self, from: Data("{\"id\":\"x\",\"bbox\":[0,0,1,1]}".utf8))
        #expect(area.mkPolygons.isEmpty)
    }

    @Test func `Service with polygons shows the map section`() throws {
        let service = try alexandria()
        let summary = OnDemandServiceSummary(service: service, timeZone: service.timeZone!, now: now, locale: Locale(identifier: "en_US"))
        let view = OnDemandServiceView(service: service, summary: summary, onOpenURL: { _ in })
        #expect(view.showsMap)
        #expect(view.bookingLineText?.contains("Mar 11") == true)
    }

    @Test func `Service with no polygons renders no map section`() throws {
        let service = try charlevoixFerry()
        let view = OnDemandServiceView(service: service, summary: nil, onOpenURL: { _ in })
        #expect(!view.showsMap)
        #expect(view.bookingLineText == nil, "no summary → no deadline line")
    }

    @Test func `Booking line templates cover every case`() {
        #expect(OnDemandServiceView.bookingLineText(for: .bookBy(deadline: "D", travelDate: "T")) == String(format: Strings.onDemandBookByFormat, "D", "T"))
        #expect(OnDemandServiceView.bookingLineText(for: .opensAt("O")) == String(format: Strings.onDemandBookingOpensFormat, "O"))
        #expect(OnDemandServiceView.bookingLineText(for: .noNoticeRequired) == Strings.onDemandNoNoticeRequired)
        #expect(OnDemandServiceView.bookingLineText(for: .closed) == Strings.onDemandBookingClosed)
        #expect(OnDemandServiceView.bookingLineText(for: .unknown) == nil)
    }

    @Test func `Kind titles are distinct and non-empty`() {
        let kinds: [ServiceKind] = [.zone, .zoneToZone, .stopGroup, .deviatedRoute, .unknown]
        let titles = kinds.map(Strings.onDemandKindTitle)
        #expect(titles.allSatisfy { !$0.isEmpty })
        #expect(Set(titles).count == kinds.count)
    }

    @Test func `Hosting controller titles itself with the service name`() throws {
        let dataLoader = MockDataLoader(testName: name)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        let controller = OnDemandServiceViewController(application: application, service: try alexandria())
        #expect(controller.title == "DOT Paratransit")
    }
}
```

- [x] **Step 2: Run the tests to verify they fail**

Run the standard command with `-only-testing:OBAKitTests/OnDemandServiceViewTests`. Expected: build failure `cannot find 'OnDemandServiceView' in scope`.

- [x] **Step 3: Create `Strings+OnDemand.swift`**

```swift
//
//  Strings+OnDemand.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Localized strings for the on-demand (GTFS-Flex) surfaces: the map layer, the
/// service page, the stop-page section and the agency list.
public extension Strings {

    // MARK: - Map layer

    static let onDemandZonesLayer = OBALoc("map_layers.on_demand_zones", value: "On-demand zones", comment: "Map sheet row for the on-demand (dial-a-ride) service zones layer")

    static let onDemandZonesUnavailable = OBALoc("map_layers.on_demand_unavailable", value: "Not available right now", comment: "Reason shown on a dimmed on-demand zones layer row when the server is unreachable")

    // MARK: - Service page

    static let onDemandSectionTitle = OBALoc("on_demand.section_title", value: "On-demand service", comment: "Header of the stop page card listing dial-a-ride services that cover this stop")

    static let onDemandWhenHeader = OBALoc("on_demand.when_header", value: "When", comment: "Section header on the on-demand service page listing service days and hours")

    static let onDemandBookingHeader = OBALoc("on_demand.booking_header", value: "How to book", comment: "Section header on the on-demand service page with the booking deadline, phone number and links")

    static let onDemandBookByFormat = OBALoc("on_demand.book_by_fmt", value: "Book by %1$@ for a ride on %2$@", comment: "Booking deadline line. %1$@ is a formatted date and time (e.g. 'Today at 5:00 PM'), %2$@ is the travel date (e.g. 'Wed, Mar 11')")

    static let onDemandBookingOpensFormat = OBALoc("on_demand.booking_opens_fmt", value: "Booking opens %@", comment: "Shown when the next service day cannot be booked yet. %@ is a formatted date and time")

    static let onDemandNoNoticeRequired = OBALoc("on_demand.no_notice_required", value: "No advance booking required", comment: "Shown when a service can be booked at ride time")

    static let onDemandBookingClosed = OBALoc("on_demand.booking_closed", value: "Booking has closed for the upcoming service days", comment: "Shown when every upcoming service day's booking deadline has passed")

    static let onDemandCallFormat = OBALoc("on_demand.call_fmt", value: "Call %@", comment: "Button that dials the booking phone number. %@ is the phone number as published")

    static let onDemandBookOnline = OBALoc("on_demand.book_online", value: "Book online", comment: "Button that opens the agency's online booking page")

    static let onDemandMoreInfo = OBALoc("on_demand.more_info", value: "More information", comment: "Button that opens the agency's information page about the service")

    static let onDemandAllHours = OBALoc("on_demand.all_hours", value: "All service hours", comment: "Shown in place of a time window when a service runs all hours of its service days")

    // MARK: - Lists

    static let onDemandNoServices = OBALoc("on_demand.no_services", value: "No on-demand services", comment: "Empty state of the list of an agency's on-demand services")

    static let onDemandListTitle = OBALoc("on_demand.list_title", value: "On-demand services", comment: "Title of the list of an agency's on-demand services")

    static let agenciesOnDemandServices = OBALoc("agencies_controller.on_demand_services", value: "On-demand services", comment: "Action on the agency action sheet that opens the agency's on-demand services")

    // MARK: - Service kinds

    /// A short badge for the shape of a service (wiki §2.3).
    static func onDemandKindTitle(_ kind: ServiceKind) -> String {
        switch kind {
        case .zone:
            return OBALoc("on_demand.kind.zone", value: "Zone service", comment: "Badge for an on-demand service that serves anywhere inside one zone")
        case .zoneToZone:
            return OBALoc("on_demand.kind.zone_to_zone", value: "Zone to zone", comment: "Badge for an on-demand service that travels between zones")
        case .stopGroup:
            return OBALoc("on_demand.kind.stop_group", value: "Stop group", comment: "Badge for an on-demand service that serves a set of stops")
        case .deviatedRoute:
            return OBALoc("on_demand.kind.deviated_route", value: "Route deviation", comment: "Badge for a fixed route that can deviate into a zone on request")
        case .unknown:
            return OBALoc("on_demand.kind.unknown", value: "On-demand", comment: "Badge for an on-demand service of unknown shape")
        }
    }
}
```

- [x] **Step 4: Append the keys to all 13 locale files**

```bash
cd /Users/aaron/repos/onebusaway/.worktrees/ios-gtfs-flex && \
for locale in ar en es fil fr it ko pl pt-BR ru vi zh-Hans zh-Hant; do
cat >> "OBAKit/Strings/$locale.lproj/Localizable.strings" <<'EOF'

/* Action on the agency action sheet that opens the agency's on-demand services */
"agencies_controller.on_demand_services" = "On-demand services";

/* Reason shown on a dimmed on-demand zones layer row when the server is unreachable */
"map_layers.on_demand_unavailable" = "Not available right now";

/* Map sheet row for the on-demand (dial-a-ride) service zones layer */
"map_layers.on_demand_zones" = "On-demand zones";

/* Shown in place of a time window when a service runs all hours of its service days */
"on_demand.all_hours" = "All service hours";

/* Button that opens the agency's online booking page */
"on_demand.book_online" = "Book online";

/* Booking deadline line. %1$@ is a formatted date and time (e.g. 'Today at 5:00 PM'), %2$@ is the travel date (e.g. 'Wed, Mar 11') */
"on_demand.book_by_fmt" = "Book by %1$@ for a ride on %2$@";

/* Shown when every upcoming service day's booking deadline has passed */
"on_demand.booking_closed" = "Booking has closed for the upcoming service days";

/* Section header on the on-demand service page with the booking deadline, phone number and links */
"on_demand.booking_header" = "How to book";

/* Shown when the next service day cannot be booked yet. %@ is a formatted date and time */
"on_demand.booking_opens_fmt" = "Booking opens %@";

/* Button that dials the booking phone number. %@ is the phone number as published */
"on_demand.call_fmt" = "Call %@";

/* Badge for a fixed route that can deviate into a zone on request */
"on_demand.kind.deviated_route" = "Route deviation";

/* Badge for an on-demand service that serves a set of stops */
"on_demand.kind.stop_group" = "Stop group";

/* Badge for an on-demand service of unknown shape */
"on_demand.kind.unknown" = "On-demand";

/* Badge for an on-demand service that serves anywhere inside one zone */
"on_demand.kind.zone" = "Zone service";

/* Badge for an on-demand service that travels between zones */
"on_demand.kind.zone_to_zone" = "Zone to zone";

/* Title of the list of an agency's on-demand services */
"on_demand.list_title" = "On-demand services";

/* Button that opens the agency's information page about the service */
"on_demand.more_info" = "More information";

/* Shown when a service can be booked at ride time */
"on_demand.no_notice_required" = "No advance booking required";

/* Empty state of the list of an agency's on-demand services */
"on_demand.no_services" = "No on-demand services";

/* Header of the stop page card listing dial-a-ride services that cover this stop */
"on_demand.section_title" = "On-demand service";

/* Section header on the on-demand service page listing service days and hours */
"on_demand.when_header" = "When";
EOF
done && grep -c 'on_demand' OBAKit/Strings/*.lproj/Localizable.strings
```

Expected: every file reports `21`.

- [x] **Step 5: Create `ServiceArea+MapKit.swift`**

```swift
//
//  ServiceArea+MapKit.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore

extension ServiceArea {

    /// One `MKPolygon` per polygon of the area, holes attached as
    /// `interiorPolygons` so the fill renders the ring structure rather than
    /// painting over the holes. Empty when the area carries no geometry.
    var mkPolygons: [MKPolygon] {
        polygons.compactMap { rings in
            guard let exterior = rings.first, exterior.count >= 3 else { return nil }
            let holes = rings.dropFirst()
                .filter { $0.count >= 3 }
                .map { MKPolygon(coordinates: $0, count: $0.count) }
            return MKPolygon(coordinates: exterior, count: exterior.count, interiorPolygons: holes)
        }
    }
}
```

- [x] **Step 6: Create `OnDemandServiceView.swift`**

```swift
//
//  OnDemandServiceView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore
import SwiftUI

/// The on-demand service page: name and kind, a map of its zones, when it runs,
/// and how to book. Reached from a zone tap on the map, the stop page's
/// on-demand card, and the agency's service list.
///
/// A plain-value view: everything is computed by `OnDemandServiceSummary`
/// before construction, so the body is a straight rendering of its inputs.
struct OnDemandServiceView: View {
    let service: OnDemandService
    /// Nil when the agency's time zone is unknown; the page then shows contact
    /// details with no deadline or hours.
    let summary: OnDemandServiceSummary?
    let onOpenURL: (URL) -> Void

    init(service: OnDemandService, summary: OnDemandServiceSummary?, onOpenURL: @escaping (URL) -> Void) {
        self.service = service
        self.summary = summary
        self.onOpenURL = onOpenURL
    }

    private var polygons: [MKPolygon] {
        service.areas.flatMap(\.mkPolygons)
    }

    /// The map section renders only when at least one area has geometry.
    var showsMap: Bool {
        service.areas.contains { $0.hasGeometry }
    }

    var bookingLineText: String? {
        summary.flatMap { Self.bookingLineText(for: $0.bookingLine) }
    }

    /// Wraps the presenter's formatted pieces in the localized sentence
    /// templates. `unknown` deliberately renders nothing (spec §6.2).
    static func bookingLineText(for line: OnDemandServiceSummary.BookingLine) -> String? {
        switch line {
        case .bookBy(let deadline, let travelDate):
            return String(format: Strings.onDemandBookByFormat, deadline, travelDate)
        case .opensAt(let opens):
            return String(format: Strings.onDemandBookingOpensFormat, opens)
        case .noNoticeRequired:
            return Strings.onDemandNoNoticeRequired
        case .closed:
            return Strings.onDemandBookingClosed
        case .unknown:
            return nil
        }
    }

    private var tint: Color {
        Color(service.route?.color ?? ThemeColors.shared.brand)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(service.name)
                        .font(.title2.weight(.semibold))
                    Text(Strings.onDemandKindTitle(service.serviceKind))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(tint.opacity(0.15), in: Capsule())
                        .foregroundStyle(tint)
                    if let description = service.serviceDescription {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowSeparator(.hidden)
            }

            if showsMap {
                Section {
                    Map(initialPosition: .region(mapRegion)) {
                        ForEach(Array(polygons.enumerated()), id: \.offset) { _, polygon in
                            MapPolygon(polygon)
                                .foregroundStyle(tint.opacity(0.2))
                                .stroke(tint, lineWidth: 2)
                        }
                    }
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets())
                    .accessibilityHidden(true)
                }
            }

            if let summary {
                Section(Strings.onDemandWhenHeader) {
                    if summary.windows.isEmpty {
                        Text(Strings.onDemandAllHours).foregroundStyle(.secondary)
                    }
                    ForEach(summary.windows, id: \.self) { window in
                        HStack {
                            Text(window.days).font(.body.weight(.medium))
                            Spacer()
                            Text(window.hours ?? Strings.onDemandAllHours).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section(Strings.onDemandBookingHeader) {
                if let bookingLineText {
                    Label(bookingLineText, systemImage: "clock")
                }
                if let phone = summary?.phoneNumber, let phoneURL = summary?.phoneURL {
                    Button { onOpenURL(phoneURL) } label: {
                        Label(String(format: Strings.onDemandCallFormat, phone), systemImage: "phone.fill")
                    }
                }
                if let bookingURL = summary?.bookingURL {
                    Button { onOpenURL(bookingURL) } label: {
                        Label(Strings.onDemandBookOnline, systemImage: "safari")
                    }
                }
                if let infoURL = summary?.infoURL ?? service.url {
                    Button { onOpenURL(infoURL) } label: {
                        Label(Strings.onDemandMoreInfo, systemImage: "info.circle")
                    }
                }
            }

            if let message = summary?.message {
                Section {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// The union of the areas' bounding boxes, padded so the outline is not
    /// flush with the map edge.
    private var mapRegion: MKCoordinateRegion {
        let boxes = service.areas.filter(\.hasGeometry).map(\.bbox)
        guard let first = boxes.first else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 0), span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1))
        }
        let minLat = boxes.map(\.minLatitude).min() ?? first.minLatitude
        let maxLat = boxes.map(\.maxLatitude).max() ?? first.maxLatitude
        let minLon = boxes.map(\.minLongitude).min() ?? first.minLongitude
        let maxLon = boxes.map(\.maxLongitude).max() ?? first.maxLongitude
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: (maxLat - minLat) * 1.2 + 0.01, longitudeDelta: (maxLon - minLon) * 1.2 + 0.01)
        )
    }
}
```

- [x] **Step 7: Create `OnDemandServiceViewController.swift`**

```swift
//
//  OnDemandServiceViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import SwiftUI
import UIKit

/// UIKit host for `OnDemandServiceView`, so `ViewRouter` can push it and the
/// map can present it as a sheet like the rental detail.
///
/// `now` is the device wall clock, taken once at construction: the deadline
/// line is a snapshot, and the page is short-lived enough that a timer would
/// be noise (spec §6.3).
final class OnDemandServiceViewController: UIHostingController<OnDemandServiceView> {

    init(application: Application, service: OnDemandService) {
        let summary = service.timeZone.map {
            OnDemandServiceSummary(service: service, timeZone: $0, now: Date(), locale: .current)
        }
        weak var weakApplication = application
        super.init(rootView: OnDemandServiceView(
            service: service,
            summary: summary,
            onOpenURL: { url in weakApplication?.open(url, options: [:], completionHandler: nil) }
        ))
        title = service.name
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
```

- [x] **Step 8: Add the router entry**

In `OBAKit/ViewRouting/Router.swift`, after `navigateTo(alert:locale:from:)`:

```swift
    /// Pushes the on-demand service page.
    public func navigateTo(onDemandService service: OnDemandService, from fromController: UIViewController) {
        navigate(to: OnDemandServiceViewController(application: application, service: service), from: fromController)
    }
```

- [x] **Step 9: Run the tests to verify they pass**

Run the standard command with `-only-testing:OBAKitTests/OnDemandServiceViewTests` and then `-only-testing:OBAKitTests/LocalizationTests`. Expected: PASS for both.

- [x] **Step 10: Commit**

```bash
cd /Users/aaron/repos/onebusaway/.worktrees/ios-gtfs-flex && swiftlint lint --quiet | tail -20 && \
git add OBAKit/Strings OBAKit/OnDemand OBAKit/ViewRouting/Router.swift OBAKitTests/OnDemand/OnDemandServiceViewTests.swift && \
git commit -m "Add the on-demand service page"
```

---

### Task 9: `OnDemandMapLayer` and its registration

**Files:**
- Create: `OBAKit/Mapping/Layers/OnDemand/OnDemandZoneAnnotation.swift`
- Create: `OBAKit/Mapping/Layers/OnDemand/OnDemandMapLayer.swift`
- Modify: `OBAKit/Mapping/Layers/MapLayerRegistrar.swift:36-61`
- Modify: `OBAKit/Mapping/MapViewController+MapLayers.swift:95-112` (`attachRentalLayerHost`)
- Test: `OBAKitTests/Mapping/OnDemandMapLayerTests.swift`
- Test: `OBAKitTests/Mapping/MapLayerRegistrarTests.swift` (+1 case)

**Interfaces:**
- Consumes: `MapLayer`, `MapLayerAvailability`, `Notification.Name.mapLayerAvailabilityDidChange`, `MapRegionManager.registerMapLayer/removeMapLayer/mapView`, `RESTAPIService.getOnDemandServices(region:geometryDetail:)`, `RESTAPIService.baseURL`, `OnDemandSupport`, `ServiceArea.mkPolygons`, `OnDemandServiceViewController`, `Strings.onDemandZonesLayer/onDemandZonesUnavailable`, `Error.isCancellation`.
- Produces:
  - `nonisolated final class OnDemandZoneAnnotation: NSObject, MKAnnotation { let service: OnDemandService; let coordinate: CLLocationCoordinate2D; var title: String? }`
  - `@MainActor final class OnDemandMapLayer: NSObject, MapLayer { static let layerID = "on-demand-zones"; init(application: Application, support: OnDemandSupport = .shared); weak var mapView: MKMapView?; private(set) var availability: MapLayerAvailability; private(set) var services: [OnDemandService]; private(set) var overlays: [MKPolygon]; private(set) var annotations: [OnDemandZoneAnnotation]; private(set) var fetchTask: Task<Void, Never>?; func apply(services:); func handle(_ error: Error) }`
  - `MapLayerRegistrar.onDemandLayer: OnDemandMapLayer?` (rebuilt on every `configure()`).

Design notes (decisions, so the implementer doesn't relitigate them):
- Zones are polygons; MapKit has no overlay tap. Each area also gets an `OnDemandZoneAnnotation` marker at its bbox centre, so a tap flows through the existing `presentLayerDetail(for:in:)` → `detailViewController(for:)` path exactly like rentals. The polygon is the picture; the marker is the button.
- The layer is rebuilt per `configure()` (per region), like the rental layers, so it re-reads `OnDemandSupport` for the new base URL on `activate()`.
- Overlays render only on the UIKit `MKMapView`; the SwiftUI panel cannot draw `MKOverlay`s (same limitation as the route-focus layers). `mapView` is nil there and the layer still tracks its state.
- Availability: `.unsupported` once `OnDemandSupport` knows the base URL (or the probe 404s); `.unavailable(reason:)` on a transient failure **only when nothing is on the map** (rental precedent: a stale but drawn zone with a dimmed row would contradict itself); `.available` on any success.

- [x] **Step 1: Write the failing tests**

Create `OBAKitTests/Mapping/OnDemandMapLayerTests.swift`:

```swift
//
//  OnDemandMapLayerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class OnDemandMapLayerTests: OBATestCase {

    private var application: Application!
    private var dataLoader: MockDataLoader!
    private var support: OnDemandSupport!

    /// A ~50 km viewport over Alexandria.
    private let viewport = MKMapRect(
        origin: MKMapPoint(CLLocationCoordinate2D(latitude: 39.1, longitude: -77.6)),
        size: MKMapSize(width: 600_000, height: 600_000)
    )

    override init() async throws {
        try await super.init()
        dataLoader = MockDataLoader(testName: name)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        support = OnDemandSupport()
    }

    private func makeLayer() -> OnDemandMapLayer {
        OnDemandMapLayer(application: application, support: support)
    }

    private func mockProbe(statusCode: Int, data: Data = Data()) {
        dataLoader.mock(data: data, statusCode: statusCode) { request in
            request.url?.path.contains("/api/ondemand/services-for-location") ?? false
        }
    }

    private var baseURL: URL { application.apiService!.baseURL }

    @Test func `Successful fetch draws one polygon and one marker per area`() async {
        mockProbe(statusCode: 200, data: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json"))
        let layer = makeLayer()
        layer.activate()
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value

        #expect(layer.availability == .available)
        #expect(layer.services.map(\.id) == ["5088_77652"])
        #expect(layer.overlays.count == 1)
        #expect(layer.annotations.count == 1)
        #expect(layer.annotations[0].title == "DOT Paratransit")
        expectClose(layer.annotations[0].coordinate.latitude, (38.617508 + 39.057831) / 2)
    }

    @Test func `404 on the probe marks the layer unsupported and empties it`() async {
        mockProbe(statusCode: 404)
        let layer = makeLayer()
        layer.activate()
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value

        #expect(layer.availability == .unsupported)
        #expect(layer.overlays.isEmpty)
        #expect(support.isKnownUnsupported(baseURL: baseURL))
    }

    @Test func `Server error with nothing drawn dims the layer`() async {
        mockProbe(statusCode: 500)
        let layer = makeLayer()
        layer.activate()
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value

        guard case .unavailable = layer.availability else {
            Issue.record("expected unavailable, got \(layer.availability)")
            return
        }
        #expect(!support.isKnownUnsupported(baseURL: baseURL))
    }

    @Test func `Server error after a success keeps the drawn zones and stays available`() async {
        mockProbe(statusCode: 200, data: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json"))
        let layer = makeLayer()
        layer.activate()
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value
        #expect(layer.overlays.count == 1)

        dataLoader.replaceMappedResponses { staging in
            staging.mock(data: Data(), statusCode: 500) { $0.url?.path.contains("/api/ondemand/services-for-location") ?? false }
        }
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value

        #expect(layer.availability == .available)
        #expect(layer.overlays.count == 1)
    }

    @Test func `A known-unsupported server is unsupported on activate and never fetches`() {
        support.recordAbsent(baseURL: baseURL)
        let layer = makeLayer()
        layer.activate()
        #expect(layer.availability == .unsupported)

        layer.viewportDidChange(viewport)
        #expect(layer.fetchTask == nil)
        #expect(dataLoader.recordedRequestURLs.allSatisfy { !$0.path.contains("/api/ondemand") })
    }

    @Test func `Nil viewport removes overlays without refetching`() async {
        mockProbe(statusCode: 200, data: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json"))
        let layer = makeLayer()
        layer.activate()
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value
        #expect(layer.overlays.count == 1)

        dataLoader.resetRecordedRequestURLs()
        layer.viewportDidChange(nil)
        #expect(layer.overlays.isEmpty)
        #expect(layer.annotations.isEmpty)
        #expect(dataLoader.recordedRequestURLs.isEmpty)
    }

    @Test func `Deactivate cancels and clears`() async {
        mockProbe(statusCode: 200, data: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json"))
        let layer = makeLayer()
        layer.activate()
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value
        layer.deactivate()
        #expect(layer.services.isEmpty)
        #expect(layer.overlays.isEmpty)

        layer.viewportDidChange(viewport)
        #expect(layer.fetchTask == nil, "an inactive layer ignores viewports")
    }

    @Test func `Renderer claims only its own polygons and fills at 20 percent`() async {
        mockProbe(statusCode: 200, data: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json"))
        let layer = makeLayer()
        layer.activate()
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value

        let mapView = MKMapView()
        let renderer = layer.renderer(for: layer.overlays[0], in: mapView) as? MKPolygonRenderer
        #expect(renderer != nil)
        #expect(renderer?.lineWidth == 2)
        var alpha: CGFloat = 0
        renderer?.fillColor?.getRed(nil, green: nil, blue: nil, alpha: &alpha)
        expectClose(Double(alpha), 0.2)

        let foreign = MKPolygon(coordinates: [CLLocationCoordinate2D(latitude: 0, longitude: 0), CLLocationCoordinate2D(latitude: 1, longitude: 0), CLLocationCoordinate2D(latitude: 1, longitude: 1)], count: 3)
        #expect(layer.renderer(for: foreign, in: mapView) == nil)
    }

    @Test func `Detail controller is the service page for a zone marker`() async {
        mockProbe(statusCode: 200, data: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json"))
        let layer = makeLayer()
        layer.activate()
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value

        let controller = layer.detailViewController(for: layer.annotations[0])
        #expect(controller is OnDemandServiceViewController)
        #expect(controller?.title == "DOT Paratransit")
        #expect(layer.detailViewController(for: MKPointAnnotation()) == nil)
        #expect(layer.recedesBehindStopSheet(layer.annotations[0]))
        #expect(!layer.recedesBehindStopSheet(MKPointAnnotation()))
    }

    @Test func `Availability change posts the layer notification`() async {
        mockProbe(statusCode: 404)
        let layer = makeLayer()
        layer.activate()

        var posted: [String] = []
        let observer = NotificationCenter.default.addObserver(forName: .mapLayerAvailabilityDidChange, object: nil, queue: .main) { note in
            if let id = note.object as? String { posted.append(id) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value
        #expect(posted.contains(OnDemandMapLayer.layerID))
    }

    @Test func `Attaching a map view late re-adds what is already loaded`() async {
        mockProbe(statusCode: 200, data: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json"))
        let layer = makeLayer()
        layer.activate()
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value

        let mapView = MKMapView()
        layer.mapView = mapView
        #expect(mapView.overlays.count == 1)
        #expect(mapView.annotations.contains { $0 is OnDemandZoneAnnotation })
    }
}
```

Append to `MapLayerRegistrarTests` in `OBAKitTests/Mapping/MapLayerRegistrarTests.swift`:

```swift
    /// No region flag gates on-demand zones: every server is probed once, and
    /// `OnDemandSupport` hides the row where the namespace is missing.
    @Test func `Registers the on-demand layer for every region`() {
        registrar = MapLayerRegistrar(application: application) { _ in }
        registrar.configure()
        #expect(application.mapRegionManager.mapLayer(id: OnDemandMapLayer.layerID) != nil)
        #expect(registrar.onDemandLayer != nil)

        application.regionsService.currentRegion = Fixtures.tampaRegion
        registrar.configure()
        let layers = application.mapRegionManager.mapLayers.filter { $0.id == OnDemandMapLayer.layerID }
        #expect(layers.count == 1)
        #expect(layers.first === registrar.onDemandLayer)
    }
```

- [x] **Step 2: Run the tests to verify they fail**

Run the standard command with `-only-testing:OBAKitTests/OnDemandMapLayerTests`. Expected: build failure `cannot find 'OnDemandMapLayer' in scope`.

- [x] **Step 3: Create `OnDemandZoneAnnotation.swift`**

```swift
//
//  OnDemandZoneAnnotation.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore

/// The tappable marker at the centre of an on-demand zone. MapKit reports no
/// overlay taps, so this annotation is what routes a tap to the service page;
/// the polygon overlay is only the picture.
///
/// `nonisolated`: `MKAnnotation`'s requirements are nonisolated Objective-C
/// declarations, and every stored value here is immutable and `Sendable`.
nonisolated final class OnDemandZoneAnnotation: NSObject, MKAnnotation {
    let service: OnDemandService
    let coordinate: CLLocationCoordinate2D

    var title: String? { service.name }

    init(service: OnDemandService, coordinate: CLLocationCoordinate2D) {
        self.service = service
        self.coordinate = coordinate
        super.init()
    }
}
```

- [x] **Step 4: Create `OnDemandMapLayer.swift`**

```swift
//
//  OnDemandMapLayer.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore

/// On-demand (GTFS-Flex) service zones on the main map.
///
/// Fetches `services-for-location` in the server's viewport mode on every map
/// region change and draws each zone as a filled `MKPolygon` in its route's
/// colour, with a marker at the zone's bounding-box centre that opens the
/// service page. Follows `RentalLayerCoordinator` for availability: the first
/// `.requestNotFound` from the probe marks the server in `OnDemandSupport` and
/// the row disappears; any other failure dims the row only while nothing is
/// drawn, and the next region change retries.
@MainActor final class OnDemandMapLayer: NSObject, MapLayer {

    static let layerID = "on-demand-zones"

    private let application: Application
    private let support: OnDemandSupport

    /// Attached by `MapViewController` after registration; nil on the SwiftUI
    /// panel, which cannot render overlays. Re-adds whatever is already loaded,
    /// because the first fetch usually lands before the host attaches.
    weak var mapView: MKMapView? {
        didSet {
            guard let mapView, mapView !== oldValue else { return }
            mapView.addOverlays(overlays, level: .aboveRoads)
            mapView.addAnnotations(annotations)
        }
    }

    private(set) var availability: MapLayerAvailability = .available
    private(set) var services: [OnDemandService] = []
    private(set) var overlays: [MKPolygon] = []
    private(set) var annotations: [OnDemandZoneAnnotation] = []
    /// Which service drew each overlay, by identity — the renderer claims only these.
    private var serviceIDByOverlay: [ObjectIdentifier: String] = [:]

    /// Exposed so tests can await the in-flight fetch instead of polling.
    private(set) var fetchTask: Task<Void, Never>?
    private var isActive = false

    init(application: Application, support: OnDemandSupport = .shared) {
        self.application = application
        self.support = support
        super.init()
    }

    // MARK: - MapLayer

    var id: String { Self.layerID }
    var title: String { Strings.onDemandZonesLayer }
    var iconName: String { "car.circle" }
    var tintColor: UIColor { ThemeColors.shared.brand }
    var group: MapLayerGroup { .transit }
    var isEnabledByDefault: Bool { true }

    /// Ten times the stop gate: county-sized zones must survive a zoomed-out map.
    var zoomWindow: MapLayerZoomWindow { MapLayerZoomWindow(maxVisibleHeight: 400_000) }
    var densityBudget: Int { 50 }
    var isClusterable: Bool { false }
    var refreshPolicy: MapLayerRefreshPolicy { .onViewportChange }
    var staleAfter: Duration? { nil }

    func activate() {
        isActive = true
        refreshSupportState()
    }

    func deactivate() {
        isActive = false
        fetchTask?.cancel()
        fetchTask = nil
        removeAllFromMap()
        services = []
    }

    func viewportDidChange(_ mapRect: MKMapRect?) {
        guard isActive else { return }
        guard let mapRect else {
            removeAllFromMap()
            return
        }
        guard availability != .unsupported else { return }
        fetch(region: MKCoordinateRegion(mapRect))
    }

    func mapAnnotationsWereCleared() {
        mapView?.addAnnotations(annotations)
    }

    func mapOverlaysWereCleared() {
        mapView?.addOverlays(overlays, level: .aboveRoads)
    }

    func renderer(for overlay: MKOverlay, in mapView: MKMapView) -> MKOverlayRenderer? {
        guard let polygon = overlay as? MKPolygon,
              let serviceID = serviceIDByOverlay[ObjectIdentifier(polygon)] else {
            return nil
        }
        let color = self.color(forServiceID: serviceID)
        let renderer = MKPolygonRenderer(polygon: polygon)
        renderer.fillColor = color.withAlphaComponent(0.2)
        renderer.strokeColor = color
        renderer.lineWidth = 2
        return renderer
    }

    private static let markerReuseIdentifier = "OnDemandZoneMarker"

    func annotationView(for annotation: MKAnnotation, in mapView: MKMapView) -> MKAnnotationView? {
        guard let zone = annotation as? OnDemandZoneAnnotation else { return nil }
        let marker = (mapView.dequeueReusableAnnotationView(withIdentifier: Self.markerReuseIdentifier) as? MKMarkerAnnotationView)
            ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: Self.markerReuseIdentifier)
        marker.annotation = annotation
        marker.glyphImage = UIImage(systemName: "car.fill")
        marker.markerTintColor = color(forServiceID: zone.service.id)
        marker.canShowCallout = false
        marker.displayPriority = .defaultLow
        return marker
    }

    /// Zones are ambient context, like rentals: they recede while a stop sheet
    /// owns the map. Recognizes exactly what `annotationView(for:in:)` claims.
    func recedesBehindStopSheet(_ annotation: MKAnnotation) -> Bool {
        annotation is OnDemandZoneAnnotation
    }

    func detailViewController(for annotation: MKAnnotation) -> UIViewController? {
        guard let zone = annotation as? OnDemandZoneAnnotation else { return nil }
        return OnDemandServiceViewController(application: application, service: zone.service)
    }

    // MARK: - Fetching

    private func fetch(region: MKCoordinateRegion) {
        guard let apiService = application.apiService else { return }
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            do {
                let response = try await apiService.getOnDemandServices(region: region, geometryDetail: .simplified)
                guard !Task.isCancelled else { return }
                self?.apply(services: response.list)
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                self?.handle(error)
            }
        }
    }

    /// Not `private`: tests feed results straight in.
    func apply(services newServices: [OnDemandService]) {
        services = newServices.sorted { $0.id < $1.id }
        setAvailability(.available)
        rebuildMapContent()
    }

    /// Not `private`: tests feed failures straight in.
    func handle(_ error: Error) {
        if let apiError = error as? APIError, case .requestNotFound = apiError {
            // The service layer has already recorded the absence; mirror it here
            // so the row disappears without a second probe.
            removeAllFromMap()
            services = []
            setAvailability(.unsupported)
            return
        }

        Logger.error("On-demand zones fetch failed: \(error)")
        if services.isEmpty {
            setAvailability(.unavailable(reason: Strings.onDemandZonesUnavailable))
        }
    }

    /// Reads `OnDemandSupport` for the current server. Called on activate; the
    /// registrar rebuilds this layer on region change, so a new region starts
    /// here again.
    private func refreshSupportState() {
        if let baseURL = application.apiService?.baseURL, support.isKnownUnsupported(baseURL: baseURL) {
            setAvailability(.unsupported)
        } else if availability == .unsupported {
            setAvailability(.available)
        }
    }

    private func setAvailability(_ newValue: MapLayerAvailability) {
        guard availability != newValue else { return }
        availability = newValue
        NotificationCenter.default.post(name: .mapLayerAvailabilityDidChange, object: id)
    }

    // MARK: - Map content

    private func rebuildMapContent() {
        removeAllFromMap()

        for service in services {
            for area in service.areas {
                for polygon in area.mkPolygons {
                    serviceIDByOverlay[ObjectIdentifier(polygon)] = service.id
                    overlays.append(polygon)
                }
                annotations.append(OnDemandZoneAnnotation(service: service, coordinate: area.bbox.center))
            }
        }

        mapView?.addOverlays(overlays, level: .aboveRoads)
        mapView?.addAnnotations(annotations)
    }

    private func removeAllFromMap() {
        mapView?.removeOverlays(overlays)
        mapView?.removeAnnotations(annotations)
        overlays = []
        annotations = []
        serviceIDByOverlay = [:]
    }

    private func color(forServiceID serviceID: String) -> UIColor {
        services.first { $0.id == serviceID }?.route?.color ?? tintColor
    }
}
```

- [x] **Step 5: Register the layer in `MapLayerRegistrar`**

Add after `private(set) var rentalLayers: [RentalMapLayer] = []`:

```swift
    /// The on-demand zones layer built by the most recent `configure()`.
    /// Registered for every region: the server, not a region flag, decides
    /// support (`OnDemandSupport`).
    private(set) var onDemandLayer: OnDemandMapLayer?
```

Change `configure()` to:

```swift
    func configure() {
        if mapRegionManager.mapLayer(id: StopsMapLayer.layerID) == nil {
            mapRegionManager.registerMapLayer(StopsMapLayer(manager: mapRegionManager))
        }
        configureRentalLayers()
        configureOnDemandLayer()
        onDidConfigure(self)
    }
```

Add after `configureRentalLayers()`:

```swift
    /// Rebuilt per region like the rental layers, so the fresh layer re-reads
    /// `OnDemandSupport` for the new server on activation.
    private func configureOnDemandLayer() {
        mapRegionManager.removeMapLayer(id: OnDemandMapLayer.layerID)
        let layer = OnDemandMapLayer(application: application)
        onDemandLayer = layer
        mapRegionManager.registerMapLayer(layer)
    }
```

- [x] **Step 6: Attach the map view in `MapViewController+MapLayers.swift`**

Replace the start of `attachRentalLayerHost(_:)` so the on-demand layer is wired before the rental guard can return early:

```swift
    private func attachRentalLayerHost(_ registrar: MapLayerRegistrar) {
        // Overlay layers draw straight onto the MKMapView; the registrar builds
        // the layer without one because the SwiftUI panel has none to give.
        registrar.onDemandLayer?.mapView = mapRegionManager.mapView

        guard let coordinator = registrar.rentalCoordinator else {
            rentalAnnotationSyncer = nil
            updateMapLayerBadge()
            return
        }
```

(The rest of the method is unchanged.)

- [x] **Step 7: Run the tests to verify they pass**

Run the standard command with `-only-testing:OBAKitTests/OnDemandMapLayerTests`, then `-only-testing:OBAKitTests/MapLayerRegistrarTests`, `-only-testing:OBAKitTests/MapLayerRendererDispatchTests`, `-only-testing:OBAKitTests/MapLayerViewportForwardingTests`, and `-only-testing:OBAKitTests/MapPanelLayersModelTests`. Expected: PASS. If `MapPanelLayersModelTests` counts enabled layers, the new default-on layer changes the count; update that expectation by exactly one and say so in the commit body.

- [x] **Step 8: Commit**

```bash
cd /Users/aaron/repos/onebusaway/.worktrees/ios-gtfs-flex && swiftlint lint --quiet | tail -20 && \
git add OBAKit/Mapping/Layers/OnDemand OBAKit/Mapping/Layers/MapLayerRegistrar.swift OBAKit/Mapping/MapViewController+MapLayers.swift OBAKitTests/Mapping/OnDemandMapLayerTests.swift OBAKitTests/Mapping/MapLayerRegistrarTests.swift && \
git commit -m "Draw on-demand service zones as a map layer"
```

---

### Task 10: Stop page on-demand section (SwiftUI page and legacy controller)

**Files:**
- Modify: `OBAKit/ViewModels/StopViewModel.swift` (published state near line 71; `applySuccessfulFetch` at 387–404; `isolated deinit` at 290)
- Create: `OBAKit/Stops/StopPage/OnDemandServicesSection.swift`
- Modify: `OBAKit/Stops/StopPage/StopPageView.swift:38-40` (`StopPageNavigationHandler`)
- Modify: `OBAKit/Stops/StopPage/StopPageActionPresenter.swift:98-131, 186-216` (`makeNavigationHandler`, `StopClosures`, `makeStopClosures`)
- Modify: `OBAKit/Stops/StopPage/StopPageViewController.swift:213-235` (`placeholderNavigation`)
- Modify: `OBAKit/Stops/StopPage/Shared/StopDeparturesSections.swift:28, 59, 140-142`
- Modify: `OBAKit/Stops/StopPage/Shared/StopDeparturesBuilder.swift:45-80`
- Modify: `OBAKit/Stops/StopViewController.swift:40-62 (ListSections), 532-553 (itemsForRegularMode), 1059-1062 (sections), 1344-1352 (bindings)`
- Test: `OBAKitTests/ViewModels/StopViewModelTests.swift` (+cases)
- Test: `OBAKitTests/Stops/StopDeparturesSectionsOnDemandTests.swift`

**Interfaces:**
- Consumes: `Stop.onDemandServiceIDs`, `RESTAPIService.getOnDemandService(id:geometryDetail:)`, `ViewRouter.navigateTo(onDemandService:from:)`, `Strings.onDemandSectionTitle`, `Strings.onDemandKindTitle`, `OBAListViewSection`, `OBAListRowView.DefaultViewModel`.
- Produces:
  - `StopViewModel`: `@Published private(set) var onDemandServices: [OnDemandService]`, `private(set) var onDemandFetchTask: Task<Void, Never>?`.
  - `StopPageNavigationHandler.showOnDemandService: (OnDemandService) -> Void` (new stored property, after `showAlertDetail`).
  - `struct OnDemandServicesSection: View { let services: [OnDemandService]; let onSelect: (OnDemandService) -> Void }`.
  - `StopDeparturesSections.onDemandServices: [OnDemandService]` and `.onSelectOnDemandService: (OnDemandService) -> Void`.
  - `StopViewController.ListSections.onDemandServices`.

Fetch policy: on every successful arrivals fetch the view model compares `stop.onDemandServiceIDs` to the ID set it last loaded; a changed set (including the first) fetches each service with `geometryDetail: .simplified` (the service page needs polygons, and the row costs nothing extra). Services that fail to load are logged and skipped; if every load fails the recorded set is cleared so the next 15 s refresh retries. Nothing here blocks or fails the arrivals list.

- [x] **Step 1: Write the failing view-model tests**

Append inside `StopViewModelTests` in `OBAKitTests/ViewModels/StopViewModelTests.swift`:

```swift
    // MARK: - On-demand services

    /// The arrivals fixture's stop references, with `onDemandServiceIds` stamped on
    /// every stop so the fetched `Stop` carries the pointer.
    private func arrivalsDataWithPointer(_ ids: [String]) throws -> Data {
        var json = try JSONSerialization.jsonObject(with: Fixtures.loadData(file: "arrivals_and_departures_for_stop_1_10020.json")) as! [String: Any]
        var data = json["data"] as! [String: Any]
        var references = data["references"] as! [String: Any]
        references["stops"] = (references["stops"] as! [[String: Any]]).map { stop in
            var stop = stop
            if ids.isEmpty { stop.removeValue(forKey: "onDemandServiceIds") } else { stop["onDemandServiceIds"] = ids }
            return stop
        }
        data["references"] = references
        json["data"] = data
        return try JSONSerialization.data(withJSONObject: json)
    }

    private func onDemandRequestCount(_ dataLoader: MockDataLoader) -> Int {
        dataLoader.recordedRequestURLs.filter { $0.path.contains("/api/ondemand/service/") }.count
    }

    @Test func `Stop with a pointer loads its on-demand services once`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: Fixtures.loadData(file: "ondemand_service_alexandria.json")) { $0.url?.path.contains("/api/ondemand/service/5088_77652") ?? false }
        let app = createApplication(dataLoader: dataLoader, analytics: AnalyticsMock(), arrivalsData: try arrivalsDataWithPointer(["5088_77652"]))
        let viewModel = StopViewModel(application: app, stopID: "1_10020")

        await viewModel.refresh()
        await viewModel.onDemandFetchTask?.value
        #expect(viewModel.onDemandServices.map(\.id) == ["5088_77652"])
        #expect(viewModel.onDemandServices[0].areas.first?.hasGeometry == true, "rows fetch simplified geometry for the service page")
        #expect(onDemandRequestCount(dataLoader) == 1)

        await viewModel.refresh()
        await viewModel.onDemandFetchTask?.value
        #expect(onDemandRequestCount(dataLoader) == 1, "same pointer set → no refetch")
    }

    @Test func `Stop without a pointer has no on-demand services and makes no request`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, analytics: AnalyticsMock(), arrivalsData: try arrivalsDataWithPointer([]))
        let viewModel = StopViewModel(application: app, stopID: "1_10020")

        await viewModel.refresh()
        #expect(viewModel.onDemandFetchTask == nil)
        #expect(viewModel.onDemandServices.isEmpty)
        #expect(onDemandRequestCount(dataLoader) == 0)
    }

    @Test func `Failed on-demand load leaves the list empty and retries on the next refresh`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: Data(), statusCode: 500) { $0.url?.path.contains("/api/ondemand/service/") ?? false }
        let app = createApplication(dataLoader: dataLoader, analytics: AnalyticsMock(), arrivalsData: try arrivalsDataWithPointer(["5088_77652"]))
        let viewModel = StopViewModel(application: app, stopID: "1_10020")

        await viewModel.refresh()
        await viewModel.onDemandFetchTask?.value
        #expect(viewModel.onDemandServices.isEmpty)
        #expect(viewModel.operationError == nil, "on-demand failures never fail the arrivals page")
        #expect(onDemandRequestCount(dataLoader) == 1)

        await viewModel.refresh()
        await viewModel.onDemandFetchTask?.value
        #expect(onDemandRequestCount(dataLoader) == 2)
    }
```

- [x] **Step 2: Write the failing section test**

Create `OBAKitTests/Stops/StopDeparturesSectionsOnDemandTests.swift`:

```swift
//
//  StopDeparturesSectionsOnDemandTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import SwiftUI
import Testing
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class StopDeparturesSectionsOnDemandTests: OBATestCase {

    private func alexandria() throws -> OnDemandService {
        try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<OnDemandService>.self, from: Fixtures.loadData(file: "ondemand_service_alexandria.json")).entry
    }

    @Test func `Section exposes one row per service and forwards selection`() throws {
        let service = try alexandria()
        var selected: OnDemandService?
        let section = OnDemandServicesSection(services: [service], onSelect: { selected = $0 })

        #expect(section.rows.map(\.id) == ["5088_77652"])
        #expect(section.rows[0].title == "DOT Paratransit")
        #expect(section.rows[0].subtitle == Strings.onDemandKindTitle(.zone))
        section.select(section.rows[0])
        #expect(selected?.id == "5088_77652")
    }

    @Test func `Navigation handler carries the on-demand callback`() throws {
        var shown: OnDemandService?
        let handler = StopPageNavigationHandler(
            showTrip: { _ in }, showScheduleForStop: {}, showScheduleForRoute: { _ in }, canScheduleForRoute: true,
            showWalkingDirections: {}, showDirectionsToHere: nil, showDirectionsFromHere: nil,
            showAlertDetail: { _ in }, showOnDemandService: { shown = $0 },
            showBookmarkEditor: { _ in }, shareTrip: { _ in }, showAlarmPicker: { _ in }, startLiveActivity: { _ in },
            showExternalSurveyError: {}, showDonation: {}, dismissDonation: { _ in },
            makeTripPreview: { _ in AnyView(EmptyView()) },
            showRouteFilter: {}, showServiceAlerts: {}, showNearbyStops: {}, showReportProblem: {}, closeSheet: {}
        )
        let service = try alexandria()
        handler.showOnDemandService(service)
        #expect(shown?.id == "5088_77652")
    }
}
```

- [x] **Step 3: Run the tests to verify they fail**

Run the standard command with `-only-testing:OBAKitTests/StopViewModelTests`. Expected: build failure `has no member 'onDemandFetchTask'` / `onDemandServices`.

- [x] **Step 4: Extend `StopViewModel`**

After `@Published private(set) var stopArrivals: StopArrivals?` add:

```swift
    /// On-demand services referencing this stop (`Stop.onDemandServiceIDs`),
    /// loaded once per distinct pointer set and rendered as the on-demand card.
    /// Empty for non-flex stops and while a load is in flight or has failed.
    @Published private(set) var onDemandServices: [OnDemandService] = []

    /// The in-flight on-demand load; held for cancellation and so tests can await it.
    private(set) var onDemandFetchTask: Task<Void, Never>?

    /// The pointer set the last completed load was for. Nil after a load that
    /// produced nothing, so the next refresh retries.
    private var loadedOnDemandServiceIDs: [String]?
```

In `isolated deinit`, add `onDemandFetchTask?.cancel()`.

In `applySuccessfulFetch(stop:arrivals:)`, after `stopArrivals = arrivals`, add `refreshOnDemandServices(for: stop)`. Then add the method (in `// MARK: - Private Helpers`):

```swift
    /// Loads the services behind `stop.onDemandServiceIDs` when the set changes.
    /// Failures never surface as `operationError`: the departures list is the
    /// page; this card is an overlay on it.
    private func refreshOnDemandServices(for stop: Stop) {
        let ids = stop.onDemandServiceIDs
        guard ids != loadedOnDemandServiceIDs else { return }

        onDemandFetchTask?.cancel()
        onDemandFetchTask = nil

        guard !ids.isEmpty, let apiService = environment.apiService else {
            loadedOnDemandServiceIDs = ids
            onDemandServices = []
            return
        }

        onDemandFetchTask = Task { [weak self] in
            var loaded: [OnDemandService] = []
            for id in ids {
                do {
                    loaded.append(try await apiService.getOnDemandService(id: id, geometryDetail: .simplified).entry)
                } catch {
                    if error.isCancellation { return }
                    Logger.error("On-demand service \(id) failed to load: \(error)")
                }
            }
            guard !Task.isCancelled, let self else { return }
            self.onDemandServices = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            self.loadedOnDemandServiceIDs = loaded.isEmpty ? nil : ids
        }
    }
```

- [x] **Step 5: Create `OnDemandServicesSection.swift`**

```swift
//
//  OnDemandServicesSection.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import SwiftUI

/// The stop page's on-demand card: one row per service that covers this
/// stop, styled like `ServiceAlertsSection` (a self-contained tinted card with
/// a header row) but never collapsible — there are one or two rows at most.
struct OnDemandServicesSection: View {
    let services: [OnDemandService]
    let onSelect: (OnDemandService) -> Void

    /// What the rows render; exposed so tests assert the projection without a host.
    struct Row: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
    }

    var rows: [Row] {
        services.map { Row(id: $0.id, title: $0.name, subtitle: Strings.onDemandKindTitle($0.serviceKind)) }
    }

    func select(_ row: Row) {
        guard let service = services.first(where: { $0.id == row.id }) else { return }
        onSelect(service)
    }

    @ScaledMetric(relativeTo: .subheadline) private var badgeSize: CGFloat = 30

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    var body: some View {
        Section {
            VStack(spacing: 0) {
                headerRow
                ForEach(rows) { row in
                    Divider().padding(.leading, 14)
                    serviceRow(row)
                }
            }
            .background(cardShape.fill(Color.accentColor.opacity(0.08)))
            .overlay(cardShape.strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 1))
            .clipShape(cardShape)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "car.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: badgeSize, height: badgeSize)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(Strings.onDemandSectionTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityAddTraits(.isHeader)
    }

    private func serviceRow(_ row: Row) -> some View {
        Button {
            select(row)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(row.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

- [x] **Step 6: Thread the callback through the SwiftUI page**

In `StopPageView.swift`, add to `StopPageNavigationHandler` directly after `let showAlertDetail: (ServiceAlert) -> Void`:

```swift
    /// Pushes the on-demand service page for a row of the stop's on-demand card.
    let showOnDemandService: (OnDemandService) -> Void
```

In `StopPageActionPresenter.swift`: add `let showOnDemandService: (OnDemandService) -> Void` to the `StopClosures` struct after `showAlertDetail`; in `makeStopClosures` add after the `showAlertDetail` closure:

```swift
            showOnDemandService: { [weak self] service in
                guard let self, let host = self.presentationHost(for: "on-demand service") else { return }
                self.application.viewRouter.navigateTo(onDemandService: service, from: host)
            },
```

and in `makeNavigationHandler` add `showOnDemandService: stop.showOnDemandService,` after `showAlertDetail: stop.showAlertDetail,`.

In `StopPageViewController.swift`'s `placeholderNavigation`, add `showOnDemandService: { _ in },` after `showAlertDetail: { _ in },`.

Then confirm no other constructor was missed:

```bash
cd /Users/aaron/repos/onebusaway/.worktrees/ios-gtfs-flex && grep -rn 'StopPageNavigationHandler(' OBAKit OBAKitTests
```

Expected: exactly `StopPageActionPresenter.swift`, `StopPageViewController.swift` and the new test file.

- [x] **Step 7: Insert the section into `StopDeparturesSections` and the builder**

In `StopDeparturesSections.swift`, add `let onDemandServices: [OnDemandService]` after `let serviceAlerts: [ServiceAlert]`, and `let onSelectOnDemandService: (OnDemandService) -> Void` after `let onSelectAlert: (ServiceAlert) -> Void`. Replace the alerts block with:

```swift
        if !serviceAlerts.isEmpty {
            ServiceAlertsSection(alerts: serviceAlerts, onSelect: onSelectAlert)
        }

        // After alerts, before the departures: a rider who can't take the bus
        // needs to see the dial-a-ride option before scrolling.
        if !onDemandServices.isEmpty {
            OnDemandServicesSection(services: onDemandServices, onSelect: onSelectOnDemandService)
        }
```

In `StopDeparturesBuilder.sections(content:walkTime:)`, add `onDemandServices: viewModel.onDemandServices,` after the `serviceAlerts:` argument and `onSelectOnDemandService: navigation.showOnDemandService,` after `onSelectAlert: navigation.showAlertDetail,`. Then:

```bash
cd /Users/aaron/repos/onebusaway/.worktrees/ios-gtfs-flex && grep -rn 'StopDeparturesSections(' OBAKit OBAKitTests
```

Expected: only `StopDeparturesBuilder.swift`. Any other call site (a preview) gets the two new arguments too.

- [x] **Step 8: Add the legacy `StopViewController` section**

In `ListSections`, add `case onDemandServices` after `case serviceAlerts`. In `itemsForRegularMode()`, after `sections.append(serviceAlertsSection)` add `sections.append(onDemandServicesSection)`. After `serviceAlertsSection` (line ~1062) add:

```swift
    // MARK: - Data/On-demand services

    private var onDemandServicesSection: OBAListViewSection? {
        let services = viewModel.onDemandServices
        guard !services.isEmpty else { return nil }

        let rows = services.map { service -> OBAListRowView.DefaultViewModel in
            OBAListRowView.DefaultViewModel(
                title: service.name,
                accessoryType: .disclosureIndicator,
                onSelectAction: { [weak self] _ in
                    guard let self else { return }
                    self.application.viewRouter.navigateTo(onDemandService: service, from: self)
                }
            )
        }
        return listViewSection(for: .onDemandServices, title: Strings.onDemandSectionTitle, items: rows)
    }
```

In the view-model bindings (next to the `viewModel.$stopArrivals` sink around line 1344), add:

```swift
        viewModel.$onDemandServices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.listView.applyData(animated: false) }
            .store(in: &cancellables)
```

(If the sinks in that method are stored in a differently named set, use that name; `grep -n 'store(in:' OBAKit/Stops/StopViewController.swift` shows it.)

- [x] **Step 9: Run the tests to verify they pass**

Run the standard command with `-only-testing:OBAKitTests/StopViewModelTests`, `-only-testing:OBAKitTests/StopDeparturesSectionsOnDemandTests`, and `-only-testing:OBAKitTests/StopPageContentTests` (if present; `ls OBAKitTests/Stops`). Expected: PASS.

- [x] **Step 10: Commit**

```bash
cd /Users/aaron/repos/onebusaway/.worktrees/ios-gtfs-flex && swiftlint lint --quiet | tail -20 && \
git add OBAKit/ViewModels/StopViewModel.swift OBAKit/Stops OBAKitTests/ViewModels/StopViewModelTests.swift OBAKitTests/Stops/StopDeparturesSectionsOnDemandTests.swift && \
git commit -m "Show on-demand services on the stop page"
```

---

### Task 11: Agencies action sheet and `OnDemandServicesListView`

**Files:**
- Create: `OBAKit/OnDemand/OnDemandServicesListView.swift`
- Create: `OBAKit/OnDemand/OnDemandServicesListViewController.swift`
- Modify: `OBAKit/Agencies/AgenciesViewController.swift:72-98` (`showAgencyOptions`)
- Test: `OBAKitTests/OnDemand/OnDemandServicesListTests.swift`

**Interfaces:**
- Consumes: `RESTAPIService.getOnDemandServices(agencyID:geometryDetail:)`, `OnDemandSupport.isKnownUnsupported(baseURL:)`, `RESTAPIService.baseURL`, `ViewRouter.navigateTo(onDemandService:from:)`, `Strings.onDemandListTitle/onDemandNoServices/agenciesOnDemandServices/onDemandKindTitle`.
- Produces:
  - `@MainActor final class OnDemandServicesListModel: ObservableObject { enum State: Equatable { case loading, loaded([OnDemandService]), failed(String) }; @Published private(set) var state: State; init(agencyID: String, apiService: RESTAPIService?, regionName: String?); func load() async }`
  - `struct OnDemandServicesListView: View { init(model: OnDemandServicesListModel, onSelect: @escaping (OnDemandService) -> Void) }`
  - `final class OnDemandServicesListViewController: UIHostingController<OnDemandServicesListView> { init(application: Application, agency: Agency) }`
  - `AgenciesViewController.onDemandSupport: OnDemandSupport` (defaults to `.shared`; tests inject a fresh one) and `showsOnDemandAction: Bool` (hidden when the current server is known-unsupported).

The wiki (§3.3) returns 404 for an unknown agency; the list treats `.requestNotFound` as an empty list rather than an error, because the agency came from `agencies-with-coverage` a moment ago and "no services" is the honest reading. Whether the list is empty cannot be known before fetching, so the action shows whenever the server is not known-unsupported and the list itself shows the empty state.

- [x] **Step 1: Write the failing tests**

Create `OBAKitTests/OnDemand/OnDemandServicesListTests.swift`:

```swift
//
//  OnDemandServicesListTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

@MainActor
@Suite(.serialized)
final class OnDemandServicesListTests: OBATestCase {
    private var dataLoader: MockDataLoader!

    override init() async throws {
        try await super.init()
        dataLoader = (restService.dataLoader as! MockDataLoader)
    }

    @Test func `Loads an agency's services sorted by id`() async {
        dataLoader.mock(URLString: "https://www.example.com/api/ondemand/services-for-agency/CC.json", with: Fixtures.loadData(file: "ondemand_services_for_agency_charlevoix.json"))
        let model = OnDemandServicesListModel(agencyID: "CC", apiService: restService, regionName: "Test")
        #expect(model.state == .loading)
        await model.load()
        guard case .loaded(let services) = model.state else {
            Issue.record("expected loaded, got \(model.state)")
            return
        }
        #expect(services.map(\.id) == ["CC_CC1", "CC_CC2_med", "CC_CC3", "CC_CC4"])
    }

    @Test func `404 for an agency is an empty list`() async {
        dataLoader.mock(data: Data(), statusCode: 404) { $0.url?.path.contains("/api/ondemand/services-for-agency/") ?? false }
        let model = OnDemandServicesListModel(agencyID: "nope", apiService: restService, regionName: "Test")
        await model.load()
        #expect(model.state == .loaded([]))
    }

    @Test func `Server error is a failure with rider-facing text`() async {
        dataLoader.mock(data: Data(), statusCode: 500) { $0.url?.path.contains("/api/ondemand/services-for-agency/") ?? false }
        let model = OnDemandServicesListModel(agencyID: "CC", apiService: restService, regionName: "Test")
        await model.load()
        guard case .failed(let text) = model.state else {
            Issue.record("expected failed, got \(model.state)")
            return
        }
        #expect(!text.isEmpty)
    }

    @Test func `Missing API service is a failure`() async {
        let model = OnDemandServicesListModel(agencyID: "CC", apiService: nil, regionName: nil)
        await model.load()
        guard case .failed = model.state else {
            Issue.record("expected failed, got \(model.state)")
            return
        }
    }

    @Test func `Agencies controller hides the on-demand action for a known-unsupported server`() {
        let loader = MockDataLoader(testName: name)
        Fixtures.stubAllAgencyAlerts(dataLoader: loader)
        let application = buildApplication(queue: OperationQueue(), dataLoader: loader)
        let controller = AgenciesViewController(application: application)
        let support = OnDemandSupport()
        controller.onDemandSupport = support
        #expect(controller.showsOnDemandAction)

        support.recordAbsent(baseURL: application.apiService!.baseURL)
        #expect(!controller.showsOnDemandAction)
    }
}
```

`OnDemandServicesListModel.State` must be `Equatable`; `OnDemandService` is an `NSObject`, so `[OnDemandService]` equality is identity-based, which is what `.loaded([])` needs.

- [x] **Step 2: Run the tests to verify they fail**

Run the standard command with `-only-testing:OBAKitTests/OnDemandServicesListTests`. Expected: build failure `cannot find 'OnDemandServicesListModel' in scope`.

- [x] **Step 3: Create `OnDemandServicesListView.swift`**

```swift
//
//  OnDemandServicesListView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import SwiftUI

/// Loads one agency's on-demand services (`services-for-agency`).
@MainActor final class OnDemandServicesListModel: ObservableObject {

    enum State: Equatable {
        case loading
        case loaded([OnDemandService])
        case failed(String)
    }

    @Published private(set) var state: State = .loading

    private let agencyID: String
    private let apiService: RESTAPIService?
    private let regionName: String?

    init(agencyID: String, apiService: RESTAPIService?, regionName: String?) {
        self.agencyID = agencyID
        self.apiService = apiService
        self.regionName = regionName
    }

    func load() async {
        guard let apiService else {
            state = .failed(UnstructuredError("No API Service").localizedDescription)
            return
        }
        do {
            let list = try await apiService.getOnDemandServices(agencyID: agencyID, geometryDetail: .simplified).list
            state = .loaded(list.sorted { $0.id < $1.id })
        } catch let error as APIError {
            // An unknown agency ID is a 404 (wiki §3.3); the agency was listed a
            // moment ago, so "no services" is the honest reading.
            if case .requestNotFound = error {
                state = .loaded([])
            } else {
                state = .failed(ErrorClassifier.classify(error, regionName: regionName).localizedDescription)
            }
        } catch {
            state = .failed(ErrorClassifier.classify(error, regionName: regionName).localizedDescription)
        }
    }
}

/// The agency's on-demand services, one row each, pushing the service page.
struct OnDemandServicesListView: View {
    @ObservedObject var model: OnDemandServicesListModel
    let onSelect: (OnDemandService) -> Void

    init(model: OnDemandServicesListModel, onSelect: @escaping (OnDemandService) -> Void) {
        self.model = model
        self.onSelect = onSelect
    }

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                ProgressView()
            case .failed(let text):
                ContentUnavailableView(text, systemImage: "exclamationmark.triangle")
            case .loaded(let services) where services.isEmpty:
                ContentUnavailableView(Strings.onDemandNoServices, systemImage: "car")
            case .loaded(let services):
                List(services, id: \.id) { service in
                    Button {
                        onSelect(service)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(service.name).foregroundStyle(.primary)
                                Text(Strings.onDemandKindTitle(service.serviceKind))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .task { await model.load() }
    }
}
```

- [x] **Step 4: Create `OnDemandServicesListViewController.swift`**

```swift
//
//  OnDemandServicesListViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import SwiftUI
import UIKit

/// UIKit host for `OnDemandServicesListView`, pushed from the Agencies screen.
final class OnDemandServicesListViewController: UIHostingController<OnDemandServicesListView> {

    init(application: Application, agency: Agency) {
        let model = OnDemandServicesListModel(
            agencyID: agency.id,
            apiService: application.apiService,
            regionName: application.currentRegionName
        )
        weak var weakApplication = application
        // `self` isn't available before super.init; the closure resolves the
        // host lazily through the hosting controller it is installed in.
        var pushFromHost: ((OnDemandService) -> Void)?
        super.init(rootView: OnDemandServicesListView(model: model, onSelect: { service in pushFromHost?(service) }))
        pushFromHost = { [weak self] service in
            guard let self, let application = weakApplication else { return }
            application.viewRouter.navigateTo(onDemandService: service, from: self)
        }
        title = Strings.onDemandListTitle
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
```

- [x] **Step 5: Add the action to `AgenciesViewController`**

Add to the class:

```swift
    /// Where the on-demand action reads server support. Injectable so tests
    /// never touch the process-wide `.shared`.
    var onDemandSupport: OnDemandSupport = .shared

    /// Hidden once the current server has proven it lacks `/api/ondemand`.
    /// Whether an agency has zero services is only known after fetching, so
    /// the list itself shows the empty state in that case.
    var showsOnDemandAction: Bool {
        guard let baseURL = application.apiService?.baseURL else { return false }
        return !onDemandSupport.isKnownUnsupported(baseURL: baseURL)
    }

    func showOnDemandServices(_ agency: AgencyWithCoverage) {
        let controller = OnDemandServicesListViewController(application: application, agency: agency.agency)
        application.viewRouter.navigate(to: controller, from: self)
    }
```

In `showAgencyOptions(_:)`, before `alert.addAction(UIAlertAction.cancelAction)`:

```swift
        if showsOnDemandAction {
            alert.addAction(UIAlertAction(title: Strings.agenciesOnDemandServices, style: .default) { [weak self] _ in
                self?.showOnDemandServices(agency)
            })
        }
```

- [x] **Step 6: Run the tests to verify they pass**

Run the standard command with `-only-testing:OBAKitTests/OnDemandServicesListTests` and `-only-testing:OBAKitTests/AgenciesViewModelTests`. Expected: PASS.

- [x] **Step 7: Commit**

```bash
cd /Users/aaron/repos/onebusaway/.worktrees/ios-gtfs-flex && swiftlint lint --quiet | tail -20 && \
git add OBAKit/OnDemand/OnDemandServicesListView.swift OBAKit/OnDemand/OnDemandServicesListViewController.swift OBAKit/Agencies/AgenciesViewController.swift OBAKitTests/OnDemand/OnDemandServicesListTests.swift && \
git commit -m "List an agency's on-demand services"
```

---

### Task 12: Full verification and documentation note

**Files:**
- Modify: `CLAUDE.md` (Architecture → Core Components list; one bullet)
- Modify: `docs/superpowers/plans/2026-09-24-gtfs-flex-ios.md` (tick the boxes; record any deviation under a final "Execution notes" heading)

**Interfaces:** none new.

- [x] **Step 1: Run the entire unit suite**

Run the standard command with `-only-testing:OBAKitTests`. Expected: every suite passes, including `LocalizationTests`, `StopsModelOperationTests`, `ReferencesTests`, `MapPanelLayersModelTests`, `MapLayerRegistrarTests`. Fix any regression in the task that owns the code, as a new commit.

- [x] **Step 2: watchOS device build and SwiftLint**

```bash
cd /Users/aaron/repos/onebusaway/.worktrees/ios-gtfs-flex && set -o pipefail && \
xcodebuild build -project OBAKit.xcodeproj -scheme WatchApp -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO -quiet 2>&1 | tail -20 && \
swiftlint lint --quiet | tail -30
```

Expected: `BUILD SUCCEEDED` (or, on a machine without the watchOS platform, the OBAKitCore-only check from Standard commands) and no SwiftLint errors or warnings in new files.

- [x] **Step 3: Project generation is clean for both apps**

```bash
cd /Users/aaron/repos/onebusaway/.worktrees/ios-gtfs-flex && scripts/generate_project KiedyBus && scripts/assert_no_watch_target && scripts/generate_project OneBusAway && git status --short
```

Expected: `git status` shows no tracked-file changes (the generated project and root `project.yml` are gitignored).

- [x] **Step 4: Document the feature in `CLAUDE.md`**

Under `### Core Components`, after the `- **Models**` bullet, add:

```markdown
- **On-demand (GTFS-Flex)**: `OBAKitCore/Models/REST/OnDemand/` holds the `/api/ondemand` wire models; `OBAKitCore/Models/OnDemand/` holds `BookingDeadlineEvaluator` (normative; verified against `OBAKitTests/fixtures/flex-booking-vectors.json`, mirrored from maglev) and the `OnDemandServiceSummary` presenter. `OnDemandSupport` remembers servers without the namespace; only `services-for-location` may record there. UI lives in `OBAKit/OnDemand/` and `OBAKit/Mapping/Layers/OnDemand/`.
```

- [x] **Step 5: Commit**

```bash
cd /Users/aaron/repos/onebusaway/.worktrees/ios-gtfs-flex && \
git add CLAUDE.md docs/superpowers/plans/2026-09-24-gtfs-flex-ios.md && \
git commit -m "Document the on-demand modules"
```

---

## Self-review record

- **Spec coverage (§7):** Core models → Task 1; `References` arrays + finders → Task 2; `Stop`/`Route` pointers → Task 3; URL builder + service calls (`simplified` on screens) → Tasks 4, 8, 9, 10, 11; `OnDemandSupport` with the location-only probe → Task 5; evaluator + vectors → Task 6; presenter → Task 7; `OnDemandMapLayer` registered for every region, availability transitions, tap → service page → Task 9; stop page section in both presentations, cached in `StopViewModel` → Task 10; service page + host + router → Task 8; agencies action sheet + list → Task 11; strings in 13 locales → Task 8; tests listed in §7 → Tasks 1–6, 9, 10. Out of scope per spec §10: watch screens, booking transactions.
- **Resolved ambiguities:** (1) Tap on a polygon: MapKit reports no overlay taps, so each zone gets a marker at its bbox centre that routes through the existing `presentLayerDetail` path. (2) `.unavailable` only when nothing is drawn (rental precedent) rather than on every transient failure. (3) A degenerate zero-rule service resolves no areas (rules are the only link), so its page shows contact info and no map. (4) `services-for-agency` 404 → empty list, not an error. (5) "Hidden when empty" on the agencies sheet is unknowable before fetching; the action shows unless the server is known-unsupported and the list carries the empty state. (6) Spec §7 names `ondemand_services_for_agency_manistee.json`; the caller's capture list uses Charlevoix (the real `stopGroup` case), so the fixture is `ondemand_services_for_agency_charlevoix.json`. (7) `priorNoticeStartTime` nil with a start day → `00:00:00`; an unknown `priorNoticeCalendarId` → calendar days. (8) Task order swaps the caller's 8 and 9: the map layer's `detailViewController` needs the service page to exist first.

## Execution notes

Deviations from the steps above, as built:

- **Task 6, evaluator.** `countBack` returns `ServiceDate?`. It returns nil when the calendar has no active weekdays, when the walk passes the calendar's `startDate` before `n` days are used up, or when the 400-day cap trips. `evaluate` maps nil to `.unknown` (spec §6.3), which matches Android. `nextBookableServiceDate` skips unknown candidates and doesn't stop at the first one (spec §6.4, Android, maglev). A parity vector for that case went into maglev's shared file, so the mirrored file has 22 vectors. `evaluate` is split into one helper per booking type to stay inside SwiftLint's complexity limit.
- **Task 7, presenter.** `bookingLine` is split for complexity. Foundation's relative formatting ignores the injected `now`. So the deadline borrows "Today"/"Tomorrow" from a probe date anchored to the real clock. It falls back to a non-relative formatter when the date is outside ±1 day or when a DST gap would shift the probe's clock time. An internal `deadlineForTesting` seam pins that case.
- **Task 8, service page.** Contact details never depend on the time zone. `OnDemandServiceSummary.init` takes `TimeZone?`. With nil, the booking line is `.unknown`, and the windows are formatted through a fixed UTC calendar. The host always builds a summary.
- **Task 9, map layer.** `AppConfig` gains `onDemandSupport` (default `.shared`), which is passed through `refreshRESTAPIService`. `OBATestCase.buildApplication` injects a fresh instance. The layer reads support from `application.apiService` so the layer and the service always agree. "Nothing on the map" means no overlays or annotations are drawn, not an empty service list. Tests cover a nil viewport followed by a 500, and both cancellation guards.
- **Task 10, stop page.** The pointer set is recorded when the fetch starts, which stops refresh churn on flex-only stops. A missing stop clears the card. Cancellation is checked with `Task.isCancelled`. The on-demand code moved out of the long types, and its tests live in `StopViewModelOnDemandTests.swift`. The existing length warnings on `StopViewController` and `StopViewModel` grew slightly but don't cross the error limit.
- **Task 11, agencies.** Every `.requestNotFound` from `services-for-agency` becomes an empty list, whether it's a real 404 or the blank-200 shape. The list has a Retry button with loading feedback and a localized no-service state.
- **Task 12, presenter parity.** When a rule has nothing bookable, the opens line now comes from the first date that evaluates `.notYetOpen`, through `BookingDeadlineEvaluator.nextServiceDate(in:rule:bookingRule:now:)`. `nextBookableServiceDate` delegates to it with `.open`. Before, only the next active date was checked, so a one-day notice window viewed in the evening showed "closed". This matches Android's `nextServiceDateInState`. A rule with no open or not-yet-open date is unknown if any remaining date can't be evaluated, and closed otherwise.
