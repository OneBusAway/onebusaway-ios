# GTFS-Flex Implementation Design (maglev, go-gtfs, iOS, Android)

**Status:** approved for planning (autonomous run, 2026-09-24; revised after design review)
**Contract:** the maglev wiki page *GTFS-Flex Support & the `/api/ondemand` Namespace*
(https://github.com/OneBusAway/maglev/wiki/GTFS-Flex%20Support), snapshot identical to
`docs/superpowers/specs/2026-07-26-gtfs-flex-ondemand-api-design.md` on branch `flex-spec`.

This document does not restate the wire contract. It records how the contract is
implemented against the code as it exists today in four repositories, the decisions the
wiki leaves open, and the places where this implementation deliberately deviates from
the wiki. Wire-level behaviour (paths, parameters, JSON shapes, ordering, error codes)
follows the wiki exactly except where §9 says otherwise.

## 0. Repositories, branches and worktrees

| Repo | Base | Work location | Branch |
|---|---|---|---|
| `OneBusAway/go-gtfs` | `origin/main` @ 50d893a | `../.worktrees/go-gtfs-gtfs-flex` | `gtfs-flex` |
| `OneBusAway/maglev` | `main` @ e70bd6ba | this checkout (already on `gtfs-flex`) | `gtfs-flex` |
| `OneBusAway/ios` | `origin/main` @ 68925b53 | `../.worktrees/ios-gtfs-flex` | `gtfs-flex` |
| `OneBusAway/android` | `origin/main` @ 8046352b | `../.worktrees/android-gtfs-flex` | `gtfs-flex` |

Sequencing: go-gtfs first (maglev depends on it), then maglev, then iOS and Android in
parallel. iOS and Android client fixtures are **captured from the running maglev
server** against the test feeds, so the maglev API must be complete before client work
starts. The go-gtfs branch is pushed to `origin` so maglev can pin a pseudo-version with
`go get github.com/OneBusAway/go-gtfs@gtfs-flex` (no `replace` directive; CI stays
green). If the push is refused, fall back to a `replace` directive and flag it.

**maglev PR decomposition (CONTRIBUTING):** three stacked PRs matching wiki §6.
(A) storage/import: go-gtfs bump + validator + `st.Stop` guards in one commit (the wiki
requires these to land together); schema + `user_version` migration; flex inserts +
warning logging; `CompileOnDemand` + tests; simplification. (B) `/ondemand`:
`polygon.go`; FlexIndex; models; one commit per endpoint. (C) `/where`: pointer fields;
legacy exclusions; additive regression. Each commit is a single logical change with an
imperative subject ≤50 chars and a body explaining why.

## 1. Test data

- **`testdata/alexandria-flex.zip`** (maglev): real Trillium feed, one route, two
  flex-only trips, one 4,239-point zone, `booking_type=2`, draft-era columns
  (`mean_duration_*`, `safe_duration_*` on stop_times), header-only
  `location_groups.txt`/`location_group_stops.txt`, `America/Los_Angeles` agency
  timezone vs `America/New_York` stop timezone. Copied from the `flex-spec` branch.
- **`testdata/manistee-flex.zip`** (maglev): real Michigan feed. On the wire it
  exercises zone and zone→zone services across six referenced zones (a seventh,
  `grand_traverse_county`, is stored but never referenced), a timed-only fixed route
  (`MC3`) alongside flex routes, and `booking_type=1` with `prior_notice_duration_min=60`.
  At the DB level only (referenced by no stop_time): `booking_type=0`
  (`booking_rule_MC3_college`) and a `booking_type=2` rule with `prior_notice_last_day`
  but no `prior_notice_last_time` (`booking_rule_MC4_med`; route MC4 has no trips). Four
  real stops, shapes, 16 removed-service `calendar_dates`.
- **`testdata/charlevoix-flex.zip`** (maglev): real Michigan feed with a real
  `location_groups.txt` / `location_group_stops.txt` (one group of two stops used by
  windowed group records) alongside zone records, `booking_type` 0 and 1, and a
  `booking_type=0` rule carrying a forbidden `prior_notice_duration_min=90`
  (`booking_rule_CC4`). This is the real `stopGroup` case.
- **Synthetic `flex-zero-stops`** fixture (in-memory `map[string]string` via
  `createTestApiWithGTFSFixture`, reduced from the 8 MB Arenac feed): header-only
  `stops.txt`, pure zone→zone, `booking_type=1` rules with **neither**
  `prior_notice_duration_min` nor `_max` (AP1), a `booking_type=2` rule with
  `prior_notice_last_day=7` and no `prior_notice_last_time` (AP2_med) referenced by a
  trip so it reaches the wire, a stray `location.geojson` file that must be ignored,
  and one Polygon with a clockwise interior ring (hole).
- **Synthetic `flex-group-deviated`** fixture: one location-group route modelled on
  gtfs.org RufBus (group of 3 stops, group→group windows, `pickup_type`/`drop_off_type`
  columns **omitted**) and one deviated route modelled on gtfs.org Hermann (timed stop,
  zone `pickup_type=1 drop_off_type=3`, timed stop, zone, timed stop), one MultiPolygon
  zone, and one **windowed stop-id record** (documents §9.1). Also used by go-gtfs parser
  tests in reduced form.
- **`testdata/flex-booking-vectors.json`** (maglev, mirrored verbatim into
  `OBAKitTests/fixtures/` and `onebusaway-android/src/androidTest/res/raw/`): booking
  deadline vectors per §6.
- go-gtfs parser tests use its in-memory `zipBuilder`, with fixtures reduced from the
  gtfs.org examples and Alexandria excerpts.

### 1.1 Expected compilation results (assert these in tests)

- **Alexandria:** one service `5088_77652`, `serviceKind: zone`, two rules exactly as
  wiki §3.4: 05:00–24:50 / drop-off 25:00 on `…d_63` (Mon–Sat); 07:00–24:50 / 25:00 on
  `…d_64` (Sun). `safeDurationFactor` 1.0 / offset 0.0 via the stop_times fallback.
  Stop `4258639` gets no pointer; route `77652` gets `["5088_77652"]`.
- **Manistee:** two services. `MC_MC1` (`zone`): 2 rules, manistee_city→manistee_city
  05:30–18:00 on `mon-tues-wed-thurs-fri` and 10:00–17:00 on `sat`; `endDropOffTime`
  null; booking MC1/MC1; safe duration 2 / 30. `MC_MC2` (`zoneToZone`): 18 rules (9 per
  calendar: county→county plus both directions for benzie, wexford, lake, mason, each
  with its own booking rule). MC3 and MC4 are not services. No stop gets a pointer. The
  weekday calendar carries 16 `exceptedDates`.
- **Charlevoix:** four services. `CC_CC1` (`zone`): 1 rule with `calendarIds`
  `["CC_mon-tues-wed-thurs-fri","CC_sat"]` (merged). `CC_CC2_med` (`zoneToZone`): 4
  rules, each with 2 calendars. `CC_CC3` (`stopGroup`): 1 rule group→group 06:30–22:30
  on `mon-tues-wed-thurs-fri-sat-sun`; stop pointers `["CC_CC3"]` on
  `CC_Ironton_Ferry_West` and `CC_Ironton_Ferry_East`. `CC_CC4` (`zone`): 1 rule with
  merged calendars.
- **flex-zero-stops:** AP1 `zoneToZone` (9 rules per calendar), AP2_med `zoneToZone`.

## 2. go-gtfs changes (branch `gtfs-flex`)

Go 1.18 compatible (CI pins 1.18): no `slices`, `maps`, `min`/`max` builtins,
`errors.Join`, `strings.CutPrefix`.

### 2.1 Structs

```go
type Static struct {
    // ...existing...
    Locations      []Location       // nil when locations.geojson absent
    LocationGroups []LocationGroup  // nil when location_groups.txt absent
    BookingRules   []BookingRule    // nil when booking_rules.txt absent
}

// Location is a GeoJSON Feature from locations.geojson (Polygon or MultiPolygon only).
type Location struct {
    Id          string
    Name        string // properties.stop_name
    Description string // properties.stop_desc
    Geometry    LocationGeometry
}

// LocationGeometry normalises Polygon and MultiPolygon to one shape.
// Polygons[p][r][i] = [lon, lat]; ring 0 is the exterior, rings 1.. are holes.
type LocationGeometry struct {
    Type     string            // "Polygon" | "MultiPolygon"
    Polygons [][][][2]float64
    Raw      json.RawMessage   // the geometry object verbatim
}

type LocationGroup struct {
    Id    string
    Name  string
    Stops []*Stop // resolved members; unknown stop ids are skipped with a warning
}

type BookingType int32 // 0 RealTime, 1 SameDay, 2 PriorDays

type BookingRule struct {
    Id                     string
    Type                   BookingType
    PriorNoticeDurationMin *int32          // minutes
    PriorNoticeDurationMax *int32
    PriorNoticeLastDay     *int32
    PriorNoticeLastTime    *time.Duration
    PriorNoticeStartDay    *int32
    PriorNoticeStartTime   *time.Duration
    PriorNoticeServiceId   string
    Message, PickupMessage, DropOffMessage string
    PhoneNumber, InfoUrl, BookingUrl       string
}

type ScheduledStopTime struct {
    // ...existing (Stop may now be nil)...
    Location                 *Location
    LocationGroup            *LocationGroup
    StartPickupDropOffWindow *time.Duration
    EndPickupDropOffWindow   *time.Duration
    PickupBookingRule        *BookingRule
    DropOffBookingRule       *BookingRule
    // Draft-era placement tolerated for real feeds; adopted spec puts these on trips.
    SafeDurationFactor       *float64
    SafeDurationOffset       *float64
}

type ScheduledTrip struct {
    // ...existing...
    SafeDurationFactor *float64
    SafeDurationOffset *float64
}

func (st ScheduledStopTime) IsWindowed() bool  // both window pointers non-nil
func (st ScheduledStopTime) IsFlex() bool      // windowed || Location != nil || LocationGroup != nil
```

### 2.2 Parsing

- `locations.geojson` is parsed **before** the CSV dispatch loop (it depends on nothing
  and its presence decides whether `stops.txt` is optional), with `encoding/json` into
  a FeatureCollection. Feature `id` may be a JSON string or number; when absent, fall
  back to `properties.id` then `properties.location_id` (draft-era). Features with
  unsupported geometry types produce a warning and are skipped. Only the exact name
  `locations.geojson` is read; `location.geojson` is ignored.
- Dispatch table gains `booking_rules.txt` (optional, before trips), `location_groups.txt`
  (optional, after stops), `location_group_stops.txt` (optional, after location_groups),
  and reads `safe_duration_factor`/`safe_duration_offset` in `parseTrips`. A zero-byte
  optional file is treated as absent (today `csv.New` errors on it and aborts the parse).
- `stops.txt` becomes optional **when `locations.geojson` is present**; otherwise it
  stays required. A header-only `stops.txt` parses to zero stops.
- `parseScheduledStopTimes`:
  - `stop_id` becomes an `OptionalColumn`; new optional columns `location_id`,
    `location_group_id`, `start_pickup_drop_off_window`, `end_pickup_drop_off_window`,
    `pickup_booking_rule_id`, `drop_off_booking_rule_id`, `safe_duration_factor`,
    `safe_duration_offset`. Draft `mean_duration_*` columns are simply not read.
  - Exactly-one-of validation: a row that resolves to zero or more than one of
    stop/location/group emits `warnings.StopTimeInvalidReference` and is skipped.
    A referenced id that does not resolve is the same warning.
  - Windows: both present → windowed; exactly one present → `StopTimeInvalidWindow`,
    skipped. A location or group row without windows → `StopTimeInvalidWindow`,
    skipped. Windows together with a non-empty `arrival_time`/`departure_time` →
    `StopTimeInvalidWindow`, skipped (wiki §1.4.3; no feed in the corpus does this).
    An unknown booking-rule id → `StopTimeInvalidReference`, skipped (wiki §1.4.5).
  - Pickup/drop-off blank-cell default: **already fixed upstream** (go-gtfs 50d893a,
    `parsePickupDropOffPolicyOrYes`). Flex tests still assert it because rule
    compilation depends on it.
  - `ExactTimes` is `false` on windowed rows regardless of the `timepoint` column
    (blank `timepoint` now means exact upstream).
  - Bug fixes: the swapped arrival/departure fallback (`!departureOk → departure =
    arrival`, `!arrivalOk → arrival = departure`); the nil-trip panic (unknown `trip_id`
    → skip row with a log line, never dereference).
  - Interpolation runs over the **timed records only**: partition each trip's
    stop_times into windowed and timed, interpolate the timed slice, then merge back in
    `stop_sequence` order. `interpolateStopTimesByShapeDist` also gets a nil guard on
    `ShapeDistanceTraveled` (falls back to even interpolation for that gap).
- New warning kinds in `warnings/`: `StopTimeInvalidReference{Reason string}`,
  `StopTimeInvalidWindow{Reason string}`, `LocationGroupUnknownStop{GroupID, StopID}`,
  `LocationInvalidGeometry{LocationID, Reason}`, `BookingRuleInvalid{BookingRuleID,
  Reason}`. GeoJSON warnings are built by hand (no `*csv.File`).
- `booking_rules.txt` tolerance: rows import even when conditionally-required fields are
  missing (real Michigan feeds omit `prior_notice_duration_min` on type 1 and
  `prior_notice_last_time` on type 2); an unparsable `booking_type` skips the row with a
  warning.
- README table rows for the four files flip to ✅.

### 2.3 Tests (go-gtfs)

Table cases in `static_test.go` plus a new `flex_test.go`: pure zone (Heartland-style),
zone→zone, location group with `pickup_type` columns omitted (asserts `Yes`), deviated
route with mixed records (asserts interpolation left the windowed rows alone and the
timed rows got interpolated), stops.txt absent with locations present, header-only
stops.txt, draft-era `safe_duration_*` on stop_times, MultiPolygon and hole geometry,
numeric Feature id, `location.geojson` ignored, zero-byte optional file, each warning
class, swapped-fallback regression, unknown trip_id regression, header-only flex files.
`interpolate_test.go` gains the nil-distance guard case.

## 3. maglev storage and import

### 3.1 Schema (`gtfsdb/schema.sql`, appended `-- migrate` chunks, all `STRICT`)

```sql
locations (id TEXT PK, name TEXT, description TEXT,
           geometry TEXT NOT NULL, geometry_simplified TEXT,
           min_lat REAL NOT NULL, max_lat REAL NOT NULL, min_lon REAL NOT NULL, max_lon REAL NOT NULL)
location_groups (id TEXT PK, name TEXT)
location_group_stops (location_group_id TEXT NOT NULL REFERENCES location_groups(id),
                      stop_id TEXT NOT NULL REFERENCES stops(id), PK(location_group_id, stop_id))
booking_rules (id TEXT PK, booking_type INTEGER NOT NULL CHECK (0..2),
               prior_notice_duration_min INTEGER, prior_notice_duration_max INTEGER,
               prior_notice_last_day INTEGER, prior_notice_last_time INTEGER,
               prior_notice_start_day INTEGER, prior_notice_start_time INTEGER,
               prior_notice_service_id TEXT, message TEXT, pickup_message TEXT,
               drop_off_message TEXT, phone_number TEXT, info_url TEXT, booking_url TEXT)
flex_stop_times (trip_id TEXT NOT NULL REFERENCES trips(id), stop_sequence INTEGER NOT NULL,
                 stop_id TEXT, location_id TEXT, location_group_id TEXT,
                 start_pickup_drop_off_window INTEGER NOT NULL, end_pickup_drop_off_window INTEGER NOT NULL,
                 pickup_type INTEGER NOT NULL, drop_off_type INTEGER NOT NULL,
                 pickup_booking_rule_id TEXT, drop_off_booking_rule_id TEXT,
                 safe_duration_factor REAL, safe_duration_offset REAL,
                 PK(trip_id, stop_sequence),
                 CHECK ((stop_id IS NOT NULL) + (location_id IS NOT NULL) + (location_group_id IS NOT NULL) = 1))
ondemand_services (id TEXT PK /* route id */, agency_id TEXT NOT NULL, route_id TEXT NOT NULL,
                   service_kind TEXT NOT NULL CHECK (in zone|zoneToZone|stopGroup|deviatedRoute|unknown))
ondemand_rules (id INTEGER PK, service_id TEXT NOT NULL REFERENCES ondemand_services(id),
                trip_id TEXT NOT NULL, from_id TEXT NOT NULL, from_kind INTEGER NOT NULL,
                to_id TEXT NOT NULL, to_kind INTEGER NOT NULL,
                start_pickup_time INTEGER, end_pickup_time INTEGER, end_drop_off_time INTEGER,
                gtfs_service_id TEXT NOT NULL, pickup_type INTEGER NOT NULL, drop_off_type INTEGER NOT NULL,
                pickup_booking_rule_id TEXT, drop_off_booking_rule_id TEXT,
                safe_duration_factor REAL, safe_duration_offset REAL)
ondemand_stop_services (stop_id TEXT NOT NULL, service_id TEXT NOT NULL, PK(stop_id, service_id))
```

Indexes: `flex_stop_times(trip_id)`, `ondemand_rules(service_id)`,
`ondemand_services(agency_id)`, `ondemand_stop_services(service_id)`. No new columns on
`trips` (SQLite has no `ADD COLUMN IF NOT EXISTS` and the migrate chunks re-run on every
open; safe duration is resolved per rule at compile time instead).

**Deviation from wiki §1.2 (deliberate):** `stop_times` keeps `stop_id`, `arrival_time`
and `departure_time` `NOT NULL`. Windowed records (any record with windows, whether it
references a stop, a location or a group) are stored in `flex_stop_times` instead. This
satisfies wiki §3.2 (windowed rows never appear in arrivals, schedules, trip-details or
block responses) with zero changes to the ~20 `/where` consumers of `StopTime.ArrivalTime`
and no nullable-column migration. `trips.min_arrival_time`/`max_departure_time` stay
NULL for flex-only trips exactly as the wiki intends. The rule compiler and
`serviceKind` classifier read `gtfs.Static` at import, so they see both kinds of record
in `stop_sequence` order regardless of table.

**Existing databases:** new tables are `CREATE IF NOT EXISTS`. Because flex tables are
populated only inside `StoreGtfsData`, which is skipped when the import metadata hash
matches, `NewClient` (after `performDatabaseMigration`, before `backfillStopAgencyIndex`,
following the `hasLegacyStopAgenciesTable` precedent) reads `PRAGMA user_version`; if it
is below `flexImportVersion = 1` it runs, in one transaction,
`UPDATE import_metadata SET file_hash = 'invalidated:flex-import-v1'` and
`PRAGMA user_version = 1`. The sentinel keeps `hasExisting = true` so the next import
clears old rows first (a deleted metadata row would make `StoreGtfsData` skip the clear
and then collide on `stop_times`' primary key); it is ≥8 characters because the log line
slices `FileHash[:8]`. Every deployment re-imports exactly once on upgrade. Migration
test: open a pre-flex DB, assert the sentinel and `user_version = 1`, then assert the
next `StoreGtfsData` succeeds and populates the flex tables.

### 3.2 Import (`gtfsdb/helpers.go` + new `gtfsdb/flex_import.go`, `gtfsdb/flex_compile.go`)

- `ValidateAndFilterGTFSData`: zero stops is fatal **only** when there are also zero
  locations; a trip is kept when every stop_time satisfies exactly-one-of
  stop/location/group; timed records still require `st.Stop != nil`. The "all trips
  filtered" hard-fail stays.
- `StoreGtfsData` inserts, in FK order: booking_rules, locations (computing bbox and
  simplified geometry), location_groups, location_group_stops, trips, then **timed**
  stop_times into `stop_times` and **windowed** records into `flex_stop_times`, then
  `ondemand_services`, `ondemand_rules` and `ondemand_stop_services` from
  `CompileOnDemand(static)`. `clearAllGTFSDataWithQueries`, `TableCounts` and
  `staticDataCounts` learn the new tables.
- `BuildStopAgencies` also `UNION`s `ondemand_stop_services ⋈ ondemand_services(agency_id)`
  so group-member stops that appear in no `stop_times` row still get an agency
  (search-stop reads this index with no fallback). `stops-for-location` keeps skipping
  route-less stops (no `/where` change in v1).
- Block indexing (`buildBlockTripIndex`, `buildBlockLayoverIndex`) operates on trips'
  timed records only; a trip with no timed records is skipped by both.
- Individual `Static.Warnings` are logged at `warn` (kind + file + row), capped at 200
  lines per import with a "… and N more" summary, alongside the existing count.
- `CompileOnDemand(static *gtfs.Static) CompiledOnDemand` is a pure function
  (`flex_compile.go`) implementing wiki §2.3: per flex-involved trip, records in
  `stop_sequence` order, capability tests, all later-pairs, side-split provenance,
  timed-stop point windows, `endDropOffTime` nulled when equal to `endPickupTime`, safe
  duration resolved per pair (`trip.SafeDuration*` first, then the pickup record, then
  the drop-off record), dedup by (from, to, windows, types, booking, safe, calendar)
  producing **one row per (tuple, gtfs_service_id)** with a representative `trip_id`,
  then `serviceKind` classification from records (a route with no flex record is never a
  service). Output also includes the stop→service pointer set (rule-referenced stops
  plus members of referenced groups) and route→service set. Unit-tested against every
  pattern in §1 with the §1.1 expectations.
- Simplification (`internal/utils/simplify.go`): Douglas–Peucker per ring, run on the
  open ring split at the vertex farthest from vertex 0 and re-closed afterwards (standard
  DP degenerates when first == last). Tolerance starts at 10 m (converted to degrees at
  the ring's mean latitude) and doubles until every ring has ≤256 points; the **≤256
  bound wins** (Alexandria's ring needs ~160 m; see §9.6). Holes below four distinct
  points are dropped; the exterior ring is never dropped; winding preserved;
  `geometry_simplified` NULL when no ring changed. Tests assert ≤256 points per ring,
  max vertex deviation ≤ final tolerance, exterior kept, holes kept when ≥4 points.

### 3.3 In-memory flex index (`internal/gtfs/flex_index.go`)

Built in `ReloadStatic` next to `computeRegionBounds`, stored under `staticMutex`:

```go
type FlexIndex struct {
    Areas           map[string]*FlexArea     // bare location id → parsed polygons, bbox, simplified JSON
    StopServiceIDs  map[string][]string      // bare stop id → sorted COMBINED service ids
    RouteServiceIDs map[string][]string      // bare route id → sorted COMBINED service ids
    ServiceBounds   map[string]utils.CoordinateBounds // combined service id → union of its
                    // area bboxes and rule-referenced stop coordinates (incl. group members)
}
```

Combined service ids are built from `ondemand_services.agency_id` (the service's own
agency), never from the requesting stop's or route's agency. **Stop ids** in
`/ondemand` responses (`references.stops[].id`, `locationGroups[].stopIds`, and
stop-kind `fromIds`/`toIds`) keep the stop's own `/where` agency (the same
`MIN(stop_agencies.agency_id)` rule search-stop uses), falling back to the service
agency only for a stop with no `stop_agencies` row; `BuildStopAgencies`' flex UNION
adds rows only for stops that have no stop_times-derived agency, so a fixed-route
stop referenced by another agency's flex service never changes its `/where` id.
Accessors take bare ids:
`OnDemandServiceIDsForStop(stopID)`, `OnDemandServiceIDsForRoute(routeID)`,
`FlexArea(id)`, `ServiceBoundsOverlapping(bounds) []serviceID`, `IsFlexEmpty()`.
Queries for rules, services, booking rules, groups and calendars go to sqlc. Zone,
group, booking-rule and calendar ids in a response are prefixed with the agencyId of the
service whose rule references them.

### 3.4 Geometry (`internal/utils/polygon.go`)

`PointInPolygon(lat, lon, polygons [][][][2]float64) bool` (ray casting, holes,
MultiPolygon), `NearestPointOnBoundary(lat, lon, polygons) (distanceMeters float64, lon,
lat float64)` (haversine point-to-segment over every ring), `PolygonIntersectsBounds(polygons,
bounds) bool` (any vertex inside bounds, any bounds corner inside polygon, or any
edge–edge crossing).

## 4. maglev API

Files: `internal/models/ondemand.go` (OnDemandService, AvailabilityRule, ServiceArea,
LocationGroupReference, BookingRule, OnDemandCalendar, OnDemandReferences embedding
`ReferencesModel`), `internal/restapi/ondemand_references.go` (builder),
`internal/restapi/ondemand_service_handler.go`, `ondemand_services_for_agency_handler.go`,
`ondemand_services_for_location_handler.go`, `ondemand_params.go` (`geometryDetail`).

Routes (all `CacheControlMiddleware(CacheDurationLong)` + `rateLimitAndValidateAPIKey` +
`etagStatic`):

```
GET /api/ondemand/service/{id}
GET /api/ondemand/services-for-agency/{id}
GET /api/ondemand/services-for-location.json
```

`OnDemandReferences` embeds `models.ReferencesModel` and adds `serviceAreas`,
`locationGroups`, `bookingRules`, `calendars`; `/where` handlers keep using
`ReferencesModel`, so no new keys leak there.

**Service fields:** `name` = route `long_name`, else `short_name`, else the bare route
id; `description` = `route_desc`; `url` = `route_url`; empty strings → `null`.

**Rules from rows:** group `ondemand_rules` rows by tuple-minus-calendar. `calendarIds`
= sorted union of (each base `gtfs_service_id` that has a `calendar` row) ∪
(`{serviceId}_added_{YYYYMMDD}` for each `calendar_dates` type-1 date of each
service). An added-date calendar is `{days: [that date's weekday], startDate = endDate =
date, exceptedDates: []}`. A service with no `calendar` row emits only added-date
calendars. Type-2 dates go into `exceptedDates` only when a base calendar exists. The
same compilation serves `priorNoticeCalendarId`.

A rule whose merged `calendarIds` would be empty (its service has no calendar row with
active days and no added dates) is dropped from the response — wiki §3.4 requires ≥1
element — and logged once at index build.

**Rule ordering (total order, wiki §3.4 clarification):** `rules` sort by
`startPickupTime` (nulls first), `endPickupTime` (nulls first), `calendarIds[0]`,
`fromIds` joined with `\u0000`, `toIds` likewise, `endDropOffTime` (nulls first),
`pickupType`, `dropOffType`, `pickupBookingRuleId` (nulls first),
`dropOffBookingRuleId` (nulls first). `calendarIds`, `fromIds` and `toIds` are each
sorted ascending before rules are sorted.

**`services-for-location`:** parse via `parseLocationParams`; viewport mode iff
`radius <= 0 && latSpan > 0 && lonSpan > 0` (exactly `BoundsFromParams`' predicate),
else point mode with the stop default radius (600 m, clamped to 20 km). Viewport bounds
are **not** clamped (zones are few and 50 km zones must survive a zoomed-out map).
Candidates = services whose `ServiceBounds` intersect the search bounds. Per candidate,
point mode: `areaContainsPoint` if any area contains the point; else `stopWithinRadius`
if any rule-referenced stop (incl. group members) is within haversine `radius`; else
`areaNearby` if any area's `NearestPointOnBoundary` distance ≤ `radius`; else not
matched. Viewport mode: `areaIntersectsViewport` if any area intersects the viewport
bounds; else `stopWithinViewport` if any referenced stop is inside the bounds. Each
`serviceArea` reference carries `distanceToArea`/`nearestPointOnBoundary` in point mode
(0 / null when inside), null otherwise. `outOfRange` = search bounds intersect neither
any agency stop bounds nor any `ServiceBounds`; no bounds at all → `false`. An invalid
`geometryDetail` → 400 with `fieldErrors.geometryDetail`.

**Pointer fields:** `OnDemandServiceIDs []string \`json:"onDemandServiceIds,omitempty"\``
on `models.Route` and `models.Stop`, populated by `api.attachOnDemandPointers` in the
central builders (`buildStopModel`, `buildRouteModels`, `routeReferenceFromStopRow`,
`utils.FilterRoutes`/`GetAllRoutesRefs` call sites, the stop and route entry handlers,
`stops-for-location`, `routes-for-location`, `routes-for-agency`, `stops-for-route`,
`stops-for-agency`, `search-stop`, `search-route`). The oracle is a table-driven test
over every `/where` route in `routes.go` that serializes a Route or Stop, run on
Charlevoix and the deviated fixture, asserting `onDemandServiceIds` on every
serialization of a flex route or stop (22 non-test files construct these models).

**Legacy exclusions:** `GetTripsForRouteInActiveServiceIDs` and `GetAllTripsForRoute`
gain `AND t.min_arrival_time IS NOT NULL` ("has timed stop_times" is the timed-trip
predicate); `schedule-for-route` returns the existing `noTripsResponse` for an all-flex
route; `stops-for-route` returns its usual single direction grouping with empty
stop groups (the same envelope as a route with no service that day). The
block-scoped queries (`GetTripSpansForBlocks`, `GetTripsByBlockIDs`,
`GetNextAndPreviousTripsInBlock`, `GetFirstStopOfNextTripInBlock`) also filter
on `min_arrival_time IS NOT NULL`: the wiki's claim that NULL bounds drop
flex-only trips "naturally" is false when a flex-only trip shares a `block_id`
with timed trips (SQLite sorts NULLs first, and trips-for-location's block
anchoring would then hide the whole block). `trip/{id}` already ignores
stop_times. `trip-details/{id}` for a flex-only trip returns the entity with
`schedule.stopTimes: []` and the `status` key omitted (existing untracked behaviour) —
requires a zero-stop-times guard in `BuildTripStatus`/`BuildTripSchedule`.

**OpenAPI:** the `/ondemand` paths are added to a **local** `testdata/openapi-ondemand.yml`
consumed by a new conformance test; `testdata/openapi.yml` stays upstream-synced.

## 5. maglev tests

Per wiki §5, plus: import of each real fixture succeeds with expected table counts and
the §1.1 compilation expectations; the synthetic zero-stops feed imports; `/where`
additive regression on `raba.zip` (committed goldens generated from `main` for a fixed
endpoint set, compared structurally, plus an assertion that no response contains
`onDemandServiceIds` or the four new reference keys); the pointer-coverage table test;
`trip/{id}`, `trip-details/{id}`, `schedule-for-route`, `stops-for-route`,
`trips-for-route` against Alexandria's flex-only route; the windowed-stop-record test
(§9.1); the `user_version` migration test.

## 6. Booking deadline evaluation (normative, shared by clients)

Wiki §2.5 applies with these clarifications:

1. **Calendar counting (correction):** gtfs.org states that `prior_notice_service_id`
   "indicates the service days on which `prior_notice_last_day` **or**
   `prior_notice_start_day` are counted", and it is allowed only for `booking_type=2`.
   Therefore `countBack(D, n, calendarId)` is used for **both** `priorNoticeLastDay` and
   `priorNoticeStartDay` when `priorNoticeCalendarId` is set, and
   `priorNoticeCalendarId` is honoured only for `bookingType 2`.
2. **Null conditionally-required fields (real feeds ship them):**
   - `bookingType 1` with null `priorNoticeDurationMin` → `state = unknown`,
     `cutoffInstant = null`, `openInstant = null` (client-only state; never on the
     wire). UI shows the booking message and phone with no deadline line. Inventing a
     0-minute notice would produce the latest possible deadline, the worst failure.
   - `bookingType 2` with `priorNoticeLastDay` but null `priorNoticeLastTime` → cutoff
     at `instant(lastDayDate, 00:00:00)` (conservative: never later than any real
     deadline). Null `priorNoticeLastDay` on type 2 → `unknown`.
   - Fields GTFS forbids for the booking type are ignored (Charlevoix `booking_rule_CC4`:
     type 0 with `prior_notice_duration_min=90` → cutoff = `latestPickup`).
3. **Count-back exhaustion:** if `countBack` cannot consume `n` active days before
   reaching the referenced calendar's `startDate` (on either the last-day or the
   start-day count), or the calendar has no active days, or its `startDate` is
   missing/unparseable, the evaluation is `state = unknown` with null cutoff, open
   and `nextBookableServiceDate` (the date search yields null because every
   candidate date is `unknown`). `countBack(D, 0, …)` = D unconditionally (no
   calendar validation). Implementations also cap the walk at 400 calendar days:
   a count that completes on or before D − 400 succeeds; one that would need to
   walk further fails. (A permissive open instant would be the wrong direction,
   and one rule is easier for three clients to mirror than a per-side sentinel.)
4. **`nextBookableServiceDate` starts at the agency-local today** (wiki-literal): at
   00:30 on the day after D, a rule whose 24:50 window on D is still open reports
   `open` for D but `nextBookableServiceDate` = today, never D. Candidate dates that
   evaluate to `unknown` are skipped and the search continues to the latest `endDate`.
5. **Unresolvable booking rules:** a NON-null `pickupBookingRuleId` that is absent from
   `references.bookingRules`, or resolves to a `bookingType` outside 0–2, evaluates as
   `unknown`. The wiki's "no pickup booking rule → `open`" applies only to a null id.
6. **`now` is the device wall clock**, never the envelope `currentTime` (responses sit on
   the long-cache tier and `currentTime` can be hours stale). Android mints it from
   `WallTime.now()`; the evaluator itself takes `java.time.Instant` + `LocalDate` +
   `ZoneId` with no epoch-ms arithmetic. iOS uses `Date()` with a `Calendar(identifier:
   .gregorian)` in the agency `TimeZone`.

`testdata/flex-booking-vectors.json` schema (agency timezone; Alexandria is
`America/Los_Angeles`):

```jsonc
{
  "timezone": "America/Los_Angeles",           // default; a vector may override
  "calendars": [ { "id": "...", "days": [...], "startDate": "...", "endDate": "...", "exceptedDates": [] } ],
  "vectors": [
    {
      "name": "alexandria prior-day just before 17:00",
      "timezone": "America/Los_Angeles",       // optional override
      "bookingRule": { /* wire bookingRule shape */ },
      "rule": { "startPickupTime": "05:00:00", "endPickupTime": "24:50:00", "calendarIds": ["..."] },
      "travelDate": "2026-03-11",
      "now": "2026-03-10T16:59:00-07:00",
      "expected": { "state": "open", "cutoffInstant": "2026-03-10T17:00:00-07:00",
                    "openInstant": "2026-02-25T00:00:00-08:00", "nextBookableServiceDate": "2026-03-11" }
    }
  ]
}
```

Minimum vectors: Alexandria prior-day before/after 17:00; post-midnight window (24:50);
same-day `bookingType=1` with `durationMin=60` (open, and closed 30 min before end);
real-time `bookingType=0`; Charlevoix type 0 with forbidden `durationMin` ignored;
`priorNoticeCalendarId` weekday-only calendar skipping a weekend (for both last-day and
start-day); `priorNoticeStartDay=14` far-out date → `notYetOpen`; no pickup booking
rule → `open` with null cutoff; type 1 with null `durationMin` → `unknown`; type 2
`lastDay=7` with null `lastTime` (AP2) → cutoff at 00:00 of the last day; a
DST-transition travel date (2026-03-08 US, `America/Detroit`) proving noon-anchor math.

## 7. iOS (OBAKit)

**Core (`OBAKitCore`, no UIKit, Swift 6 strict concurrency):**
- Models in `OBAKitCore/Models/REST/OnDemand/`: `OnDemandService` (final class,
  `Decodable`, `HasReferences`, resolves `route`, `agency`, `areas`, `bookingRules`,
  `calendars`), `AvailabilityRule`, `ServiceArea` (bbox + optional `geometry` decoded to
  `[[[CLLocationCoordinate2D]]]` polygons, plus `distanceToArea`/`nearestPointOnBoundary`),
  `OnDemandLocationGroup`, `OnDemandBookingRule`, `OnDemandCalendar`, `ServiceKind`,
  `MatchReason` (enums with an `unknown` fallback for forward compatibility).
- `References` gains `serviceAreas`, `locationGroups`, `bookingRules`, `calendars`
  (`decodeIfPresent ?? []`, sorted by id) and finders.
- `Stop` and `Route` gain `onDemandServiceIDs: [String]` (`decodeIfPresent ?? []`,
  encoded only when non-empty so cached blobs stay unchanged, included in
  `isEqual`/`hash`).
- `RESTAPIURLBuilder` + `RESTAPIService+OnDemand.swift`: `getOnDemandServices(region:
  geometryDetail:)`, `getOnDemandServices(agencyID: geometryDetail:)`,
  `getOnDemandService(id: geometryDetail:)`. Screens request `simplified` (the default
  `full` can be ~750 KB for a county zone).
- `OnDemandSupport`: `public final class OnDemandSupport: Sendable` backed by
  `Mutex<Set<String>>` (`Synchronization`, already used by `DecodingErrorReporter`) with
  nonisolated synchronous `isKnownUnsupported(baseURL:)` / `recordAbsent(baseURL:)`.
  **Only `services-for-location` is the probe**: `.requestNotFound` on it (a real HTTP
  404, or the legacy blank-200 shape) → unsupported for that base URL for the process
  lifetime. Every other error, including `.invalidContentType` and decode failures, is
  transient (layer `.unavailable(reason:)`, retried on the next viewport change). Keyed
  by resolved base URL so custom regions and region switches work; on region change the
  layer re-reads support and posts `.mapLayerAvailabilityDidChange`.
- `BookingDeadlineEvaluator` (`OBAKitCore/Models/OnDemand/BookingDeadlineEvaluator.swift`):
  §6 algorithm; returns `BookingEvaluation { state (notYetOpen|open|closedForDate|
  unknown), cutoffInstant, openInstant }` and `nextBookableServiceDate`. Tested with
  the shared vectors file.
- `OnDemandServiceSummary` presenter: "Book by …" line, service-day windows, phone/URL.

**UI (`OBAKit`):**
- `OnDemandMapLayer: MapLayer` (`@MainActor`, `private(set) var availability`) — id
  `on-demand-zones`, viewport-driven fetch of `services-for-location` in viewport mode
  with `geometryDetail=simplified`, renders `MKPolygon`s (route colour at 20 % fill),
  availability `.unsupported` once `OnDemandSupport` marks the server, `.unavailable`
  on transient failure, `.available` otherwise, following the `RentalLayerCoordinator`
  pattern; tapping a zone opens the service page. Registered by `MapLayerRegistrar` for
  every region (no region flag).
- Stop page (SwiftUI `StopDeparturesSections`): `OnDemandServicesSection` after
  `ServiceAlertsSection` when `stop.onDemandServiceIDs` is non-empty; rows fetched via
  `getOnDemandService` and cached in `StopViewModel`. Legacy `StopViewController`
  gets the equivalent `OBAListViewSection`.
- `OnDemandServiceView` (SwiftUI): name, kind badge, map snippet with polygon(s),
  "When" (rules grouped by calendar → days + window), "How to book" (deadline line from
  the evaluator for the next bookable date, phone via `tel:`, booking/info URLs),
  messages. Hosted by `OnDemandServiceViewController` for UIKit routing.
- Agencies screen: action sheet gains "On-demand services" → `OnDemandServicesListView`
  for that agency (hidden when unsupported or empty).
- Strings added to all 13 `OBAKit/Strings/*.lproj/Localizable.strings` (English values in
  every locale, per `LocalizationTests`).

**Tests:** decoding of captured fixtures (`ondemand_service_alexandria.json`,
`ondemand_services_for_location_*.json`, `ondemand_services_for_agency_manistee.json`,
`stop_with_ondemand_pointer.json`), 404 on services-for-location → unsupported and 404
on service/{id} → **not** unsupported, old `stops_for_location_seattle.json` still
decodes with empty pointer arrays, evaluator vectors, URL builder tests, `Stop`
round-trip with and without pointers.

## 8. Android

**API/data (`org.onebusaway.android.api`):**
- `ObaWebService` gains `onDemandService(id, geometryDetail)`, `onDemandServicesForAgency
  (id, geometryDetail)`, `onDemandServicesForLocation(lat, lon, radius, latSpan, lonSpan,
  geometryDetail)`; `DemoObaWebService` answers with empty lists / a 404 envelope.
- `OnDemandApiModels.kt`: `OnDemandServiceDto`, `AvailabilityRuleDto`, `ServiceAreaDto`
  (`geometry: JsonElement? = null` decoded lazily to `List<List<List<GeoPoint>>>`),
  `LocationGroupDto`, `BookingRuleDto`, `FlexCalendarDto`; `References` gains the four
  lists with defaults; `StopReference`/`RouteReference` gain
  `onDemandServiceIds: List<String> = emptyList()`; domain `ObaStop`/`ObaRoute` expose
  `onDemandServiceIds`. Screens request `geometryDetail=simplified`.
- `OnDemandDataSource` (Hilt, `runCatchingCancellable`) with sealed `OnDemandResult
  { Loaded, Unsupported, Failed }` and `OnDemandSupport` `@Singleton` keyed by base URL,
  in-memory. **Only `services-for-location` probes**; unsupported iff the existing
  `isEndpointAbsent` (raw HTTP 404). Everything else is `Failed` (transient). A 404 from
  `service/{id}` or `services-for-agency` is an ordinary not-found.
- `BookingDeadlineEvaluator` (`java.time`; `Instant` + `LocalDate` + `ZoneId`, no
  epoch-ms arithmetic), tested with the vectors file; callers mint `now` from
  `WallTime.now()`.

**UI:**
- `OnDemandLayerController` (mirrors `RentalLayerController`): viewport-driven
  `services-for-location` in viewport mode, `MapRenderSnapshot.onDemandZones:
  List<ZonePolygon>`; rendering added to `GoogleMapRenderer` (Polygon) and
  `MapLibreRenderer` (FillLayer); tap opens the service screen. Preference toggle
  `preference_key_show_ondemand_zones` (default on). Hidden when unsupported.
- Arrivals screen: `ArrivalsUiState.Content.onDemandServices` → `item(key = "ondemand")`
  card between alerts and direction rows; `firstRouteIndex` arithmetic updated.
- `OnDemandServiceScreen` (Compose destination): same content as iOS; booking phone via
  `ACTION_DIAL`, URLs via Custom Tabs/`ACTION_VIEW`.
- Strings in `values/strings.xml`.

**Tests:** decode tests reading the captured fixtures, `OnDemandSupport` classification
(`HttpException(Response.error(404, …))` on the probe → unsupported; the same on
`service/{id}` → not-found only), evaluator vectors, `OnDemandLayerController` unit test
with a fake data source, arrivals view-model test for the new card, `StopsMapDecodeTest`
regression for old payloads.

## 9. Deviations from and clarifications to the wiki (for the reviewer)

1. Windowed records live in `flex_stop_times`, not in nullable `stop_times` columns
   (§3.1). One observable consequence: **windowed stop-id records do not contribute
   stop↔route relations** (`routeIds`, stops-for-route, stop_agencies, region bounds);
   such stops surface only through `onDemandServiceIds`. No feed in the corpus has
   windowed stop records; a synthetic test documents the behaviour.
2. `prior_notice_service_id` counts service days for both last-day and start-day (§6).
3. `stops.txt` is optional only when `locations.geojson` exists.
4. Booking rules with missing conditionally-required fields import with nulls rather
   than being skipped; client evaluation of those nulls is normative in §6.2.
5. Locations whose Feature `id` is only in `properties`, or is a JSON number, are accepted.
6. Simplification: the ≤256-points-per-ring bound wins over the ≤10 m deviation target
   (Alexandria's ring needs ~160 m tolerance to fit; the two wiki §5 assertions are
   jointly unsatisfiable on its own fixture).
7. Rule ordering is extended to a total order (§4) so goldens are deterministic.
8. Calendar merging: one stored row per (tuple, gtfs_service_id); `calendarIds` merged
   at the API layer; added-date calendars join the merged array rather than producing
   rule copies (§4).

## 10. Out of scope (unchanged from wiki)

Booking transactions, trip planning, GTFS-RT for flex trips, GOFS ingestion,
`agencies-with-coverage` bounds, watchOS UI (models compile for watchOS; no watch screens).
