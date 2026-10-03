# GTFS-Flex Support & the `/api/ondemand` Namespace

## Summary

Maglev will ingest GTFS-Flex data (merged into the GTFS Schedule spec in March 2024)
and expose demand-responsive transit (DRT) through a new, separate API namespace:
`/api/ondemand`. The namespace speaks the existing OneBusAway wire dialect — same
response envelope, same `references` system, same combined-ID convention, same API-key
and rate-limit middleware — but models on-demand mobility as its own product, distinct
from fixed-route service. The core abstraction, the **on-demand service**, is
provider-agnostic: GTFS-Flex populates it today, and GOFS (General On-demand Feed
Specification) can populate the identical model and endpoints later with zero contract
changes.

## Goals

1. Ingest all four GTFS-Flex files (`locations.geojson`, `location_groups.txt`,
   `location_group_stops.txt`, `booking_rules.txt`) plus the new `stop_times.txt` and
   `trips.txt` fields.
2. Serve three rider-facing jobs in the OBA iOS/Android apps:
   - **Zone discovery near me** — "what on-demand services cover this point/viewport,
     when do they run, how do I book?"
   - **Flex awareness on existing entities** — deviated-route trips and
     location-group stops surface their on-demand overlays.
   - **Agency/route browsing** — an agency's dial-a-ride offerings are enumerable.
3. Design the public surface so GOFS is a natural, non-conflicting extension.

## Non-Goals

- **Booking transactions.** Read-only discovery only. Booking happens out-of-band via
  the phone number or URL in the booking rule. No POST endpoints, no provider
  integrations, no state.
- **Trip planning.** Maglev has no routing engine; nothing here computes DRT
  itineraries or travel times.
- **GTFS-RT for flex trips.** Out of scope for v1.
- **GOFS ingestion.** Designed for, not built.

## Decisions of Record

| Decision | Choice |
|---|---|
| Scope | Read-only discovery |
| OpenAPI/sdk-config | Implement first, propose spec upstream after the design proves out |
| Compatibility | Strictly additive: existing response shapes never change meaning; flex-only entities are excluded where they would be misleading |
| Namespace | Separate `/api/ondemand` family, OBA wire conventions throughout |
| `/where` coupling | Additive pointer fields (`onDemandServiceIds`) on stop and route entries; omitted when empty |
| Geometry encoding | Embedded GeoJSON (not encoded polylines) |
| Parsing | Extend `OneBusAway/go-gtfs` upstream |
| Test data | Real feed: City of Alexandria VA flex v2 (Trillium), plus minimal synthetic fixtures only for patterns Alexandria doesn't exercise |

### Why a separate namespace (and why it is not "two protocols")

URL namespace and wire format are independent axes. `/api/ondemand` reuses the OBA
envelope (`code`/`currentTime`/`text`/`version`/`data` with `entry`|`list` +
`references`), agency-prefixed IDs, `.json` + HTTP GET, and the existing key/rate-limit
middleware. Client networking and reference-resolution code is reused wholesale; the
only new client code is the new model types, which any approach would require.

DRT is a distinct product: pure-zone dial-a-ride and every GOFS service have no stops,
no schedule, and no arrivals. A separate namespace also keeps `/api/where` conformant
with the upstream sdk-config OpenAPI contract while `/api/ondemand` iterates freely —
the only `/where` divergence in this design is the pointer fields.

The GTFS-Flex spec itself sanctions the split for interwoven patterns: its routing
rule instructs consumers computing fixed-route timing to **ignore** windowed
stop_times records. `/api/where/trip-details` returning only the fixed records is
therefore the spec's own fixed-route view, not a lossy compromise; the deviation
overlay is a legitimately separate resource.

## 1. Ingestion & Storage

### 1.1 Parsing: extend `OneBusAway/go-gtfs`

The new flex columns live inside `stop_times.txt`, which go-gtfs already parses;
parsing stop_times a second time in Maglev would be wasteful and fragile. The work
lands in the org's own fork (closing the ❌ rows in its README) as a prerequisite PR:

- `stop_times.txt`: `location_id`, `location_group_id`, `start_pickup_drop_off_window`,
  `end_pickup_drop_off_window`, `pickup_booking_rule_id`, `drop_off_booking_rule_id`
- `trips.txt`: `safe_duration_factor`, `safe_duration_offset`
- New files: `locations.geojson` (GeoJSON FeatureCollection; Polygon/MultiPolygon
  only), `location_groups.txt`, `location_group_stops.txt`, `booking_rules.txt`

Maglev consumes the new structs through its existing `ParseStatic` → bulk-insert path
(`gtfsdb/helpers.go`).

Reviewing the go-gtfs source (`static.go`, `interpolate.go`) pins down what the
upstream change actually is — it is more than adding optional columns:

- **Flex rows are dropped entirely today — and flex-only feeds fail import.**
  `stop_id` is a required column, so an empty-`stop_id` row dies at the
  `MissingRowKeys` check (`static.go:838-841`, with a `log.Printf`); the separate
  `Stop == nil` skip only catches non-empty IDs that don't resolve. Downstream,
  Maglev's `ValidateAndFilterGTFSData` (`gtfsdb/helpers.go:1448`) then drops every
  trip left with zero stop_times and **hard-fails the whole import when all trips
  are filtered** — so the Alexandria feed doesn't import degraded today, it
  doesn't import at all. Upstream fix: `stop_id` becomes an optional column (a
  pure zone-based feed may omit it entirely), and because the `csv` package has no
  conditionally-required concept, the exactly-one-of stop/location/location-group
  validation is hand-rolled in `parseScheduledStopTimes`, emitting
  `Static.Warnings` for rows that resolve to none.
- **`stops.txt` is a hard-required *file* in `ParseStatic`** (`static.go:213-218`,
  no `Optional` flag), but flex makes it conditionally required — optional when
  `locations.geojson` defines zones. The dispatch entry becomes optional in that
  case, and Maglev must tolerate a feed with zero stops.
- **The pickup/drop-off enum default is wrong for flex compilation.**
  `parsePickupDropOffPolicy` (`enums.go:130-141`) maps empty/absent values to
  `No` (1); per GTFS, an empty `pickup_type` means 0 (regularly scheduled). The
  default is correct for `continuous_pickup` (empty = 1) but wrong for
  `pickup_type`/`drop_off_type` — and since most real feeds omit those columns on
  ordinary timed stops, §2.3's timed-stop capability test would see 1 and compile
  deviated routes to zero rules. The upstream PR gives the parser per-field
  defaults.
- **Two pre-existing upstream bugs sit in the rewritten code path; fix both in
  the same PR.** (a) The arrival/departure fallback assignments are swapped
  (`static.go:802-807`: `if !departureOk { arrival = departure }` zeroes both
  times when exactly one is present, then interpolation fabricates replacements).
  (b) A stop_times row referencing an unknown `trip_id` panics on
  `cap(thisTrip.StopTimes)` with a nil trip (`static.go:830-834`), reachable with
  real malformed feeds because trips are droppable upstream.
- **Struct surface:** `Static` gains `Locations`, `LocationGroups`, and
  `BookingRules` slices; `ScheduledStopTime` gains `Location`/`LocationGroup`
  pointers (alongside the existing `Stop`), the two window durations, and
  pickup/drop-off booking-rule references; `ScheduledTrip` gains the two
  safe-duration fields.
- **`locations.geojson` is not CSV.** `ParseStatic`'s dispatch is a table of
  CSV-file handlers; the GeoJSON file needs its own parse path outside that loop.
- **Time interpolation must exempt windowed records — by removing them from the
  interpolation input, not by skipping writes.** go-gtfs interpolates missing
  arrival/departure times across each trip (`interpolateStopTimes`, by-shape-dist
  variant included). On a deviated trip this would fabricate times for the zone
  records sitting between timed stops. Worse, the shape-dist variant dereferences
  `ShapeDistanceTraveled` without a nil check (`interpolate.go:87`) and its
  trigger flag is file-global, so a kept windowed record (zero time, nil distance)
  between two distance-bearing stops is a nil-pointer panic. Interpolate over the
  timed records only, then reassemble.
- **Missing vs. midnight:** `ScheduledStopTime.ArrivalTime` is a non-pointer
  `time.Duration`, so a zero value is ambiguous between "absent" and "00:00:00".
  No breaking pointer change is needed: window presence is the discriminator
  (the spec forbids times when windows are set), and Maglev's importer writes NULL
  arrival/departure exactly when a record carries windows. The **new** window
  fields themselves must not inherit the same ambiguity — a `00:00:00` window
  start is legal — so they are pointer-typed (`*time.Duration`) from the start.

Real-world feeds still carry draft-era GTFS-Flex columns. The Alexandria test feed
puts `mean_duration_factor`/`mean_duration_offset` (dropped from the adopted spec)
and `safe_duration_factor`/`safe_duration_offset` (adopted, but on `trips.txt`) in
`stop_times.txt`. The parser must tolerate the unknown draft columns, and the
importer reads `safe_duration_*` from `trips.txt` first, falling back to the
draft-era `stop_times.txt` placement when the trips columns are absent.

### 1.2 Schema (sqlc; `gtfsdb/schema.sql`)

Four new tables:

```sql
locations (
    id            TEXT PRIMARY KEY,   -- shared namespace with stops.stop_id, location_groups.id
    name          TEXT,               -- properties.stop_name
    description   TEXT,               -- properties.stop_desc
    geometry      TEXT NOT NULL,      -- GeoJSON geometry object, verbatim
    geometry_simplified TEXT,         -- display-detail geometry computed at import (§1.3);
                                      -- NULL when the original already meets the target
    min_lat REAL NOT NULL, max_lat REAL NOT NULL,
    min_lon REAL NOT NULL, max_lon REAL NOT NULL   -- computed bounding box
)

location_groups (
    id    TEXT PRIMARY KEY,
    name  TEXT
)

location_group_stops (
    location_group_id TEXT NOT NULL REFERENCES location_groups(id),
    stop_id           TEXT NOT NULL REFERENCES stops(id),
    PRIMARY KEY (location_group_id, stop_id)
)

booking_rules (
    id                        TEXT PRIMARY KEY,
    booking_type              INTEGER NOT NULL CHECK (booking_type BETWEEN 0 AND 2),
    prior_notice_duration_min INTEGER,          -- minutes
    prior_notice_duration_max INTEGER,          -- minutes
    prior_notice_last_day     INTEGER,
    prior_notice_last_time    INTEGER,          -- ns since midnight, matching stop_times convention
    prior_notice_start_day    INTEGER,
    prior_notice_start_time   INTEGER,
    prior_notice_service_id   TEXT,
    message                   TEXT,
    pickup_message            TEXT,
    drop_off_message          TEXT,
    phone_number              TEXT,
    info_url                  TEXT,
    booking_url               TEXT
)
```

Additive columns:

- `stop_times`: the six flex columns above (times as int64 ns-since-midnight,
  matching the existing convention). `stop_id` becomes nullable with a CHECK that
  exactly one of `stop_id` / `location_id` / `location_group_id` is set.
  **`arrival_time` and `departure_time` also become nullable** — the spec forbids
  them on windowed records, and every windowed row in a real feed has them empty —
  with the existing `arrival_time <= departure_time` CHECK applying only when both
  are present. Downstream effects to handle explicitly: the cached
  `trips.min_arrival_time`/`max_departure_time` columns stay NULL for flex-only
  trips (which correctly drops them from time-window queries like
  trips-for-location), every query ordering or filtering on `arrival_time`
  must exclude NULL rows rather than sort phantom zeros, the sqlc-generated Go
  types for the two columns change to nullable (touching consumers like
  `internal/restapi/trips_helper.go`), and `timepoint` is written NULL on
  windowed rows — GTFS requires times when `timepoint=1`, and go-gtfs's
  `ExactTimes` default would otherwise mark timeless flex rows as exact.
- `trips`: `safe_duration_factor REAL`, `safe_duration_offset REAL`.

Plus the compiled-rule table produced at import (§2.3):

```sql
ondemand_rules (
    id                        INTEGER PRIMARY KEY,
    service_id_key            TEXT NOT NULL,     -- the owning on-demand service (route id for flex)
    trip_id                   TEXT NOT NULL,
    from_id                   TEXT NOT NULL,     -- shared namespace: stop | location | location group
    from_kind                 INTEGER NOT NULL,  -- 0 stop, 1 location, 2 location group
    to_id                     TEXT NOT NULL,
    to_kind                   INTEGER NOT NULL,
    start_pickup_time         INTEGER,           -- all three: ns since midnight, may
    end_pickup_time           INTEGER,           -- exceed 24h; all NULL = service runs
    end_drop_off_time         INTEGER,           -- all hours (GOFS windowless rules)
    gtfs_service_id           TEXT NOT NULL,     -- calendar reference; one row per calendar
    pickup_type               INTEGER NOT NULL,
    drop_off_type             INTEGER NOT NULL,
    pickup_booking_rule_id    TEXT,
    drop_off_booking_rule_id  TEXT,
    safe_duration_factor      REAL,
    safe_duration_offset      REAL
)
```

And one materialized row per on-demand service (one per flex-involved route),
giving import-derived facts a home that rule rows cannot provide — a zero-rule
degenerate service (§2.3) still has a kind:

```sql
ondemand_services (
    id            TEXT PRIMARY KEY,   -- route id for flex; feed-prefixed id for GOFS
    service_kind  TEXT NOT NULL       -- zone | zoneToZone | stopGroup | deviatedRoute | unknown (§2.3)
)
```

**ID namespace.** The GTFS spec requires location IDs, location-group IDs, and stop
IDs to share one uniqueness namespace. The existing `{agencyId}_{id}` combined-ID
convention therefore extends without disambiguation: zone and group IDs are
agency-prefixed exactly like stop IDs.

### 1.3 Spatial strategy

No SpatiaLite, no new R-tree. Flex feeds contain dozens of zones, not thousands.
`services-for-location` filters candidates by the bounding-box columns in SQL, then
runs an exact test in Go against the stored GeoJSON:

- **Point mode**: ray-casting point-in-polygon, honoring holes (right-hand-rule
  interior rings) and MultiPolygon members, plus a nearest-boundary search:
  haversine point-to-segment distance over every ring segment, yielding both
  the distance and the closest boundary point.
- **Region mode**: polygon–rectangle intersection against the viewport.

The pass's results are response data, not just filter predicates: the
containment/intersection outcome is surfaced as `matchReason`, and the
nearest-boundary search as `distanceToArea` / `nearestPointOnBoundary`
(§3.4). Computing these and discarding them would force every client to
re-download full geometry and reimplement the identical tests — the iOS bbox
containment fallback is actively wrong (Alexandria's bbox is ~55 km × 49 km,
mostly Maryland and DC that the polygon does not cover).

**Display geometry** is simplified once at import into
`locations.geometry_simplified` (§1.2): Douglas–Peucker per ring, tolerance
chosen so simplified vertices stay within ~10 m of the original, target ≤256
points per ring. Interior rings simplify independently; ring winding and hole
structure are preserved (a hole that degenerates below four points is
dropped), or the map fill renders inverted. `bbox` is always computed from
the full geometry. Simplified geometry is for display only — containment and
distance always run against the full stored geometry.

Revisit with an R-tree only if profiling demands it.

### 1.4 Import invariants

Enforced at import, mirroring the spec's presence rules; violations are logged and the
offending row skipped — never a failed import (consistent with existing malformed-GTFS
handling):

1. Exactly one of `stop_id` / `location_id` / `location_group_id` per stop_time.
2. Windows required when a location or location group is referenced; both ends
   present together.
3. Windows and `arrival_time`/`departure_time` are mutually exclusive.
4. With windows: `pickup_type` ∈ {1, 2}; `drop_off_type` ∈ {1, 2, 3} (the spec's
   asymmetry: drop-off 3 legal, pickup 3 not).
5. Dangling booking-rule / location / group references: row skipped, logged.
6. Feeds violating the spec's same-trip overlap prohibition are imported anyway
   (log-only) — consumers, not validators.

Skips surface through go-gtfs's `Static.Warnings`, which `ParseStatic` does return
to callers — but Maglev currently logs only the warning *count*
(`gtfsdb/helpers.go:234`); the import work includes iterating them so individual
skipped rows are visible in logs.

## 2. The On-Demand Service Model

### 2.1 `onDemandService` (the entry)

The rider-facing unit: "a bookable service that covers these areas, during these
windows, booked this way." Provider-agnostic by construction. For flex data, one
service exists per route that has at least one flex stop_time record (a windowed
record, or any record referencing a location or location group) — even when rule
compilation yields nothing (§2.3).

```jsonc
{
  "id": "25_dial-a-ride",        // flex: the route's combined ID
  "agencyId": "25",
  "routeId": "25_dial-a-ride",   // null for future GOFS services — they have no routes
  "name": "Brown County Dial-a-Ride",
  "serviceKind": "zone",         // §2.3: zone | zoneToZone | stopGroup | deviatedRoute | unknown
  "description": null,
  "url": null,
  "rules": [ /* availabilityRule, below */ ]
}
```

### 2.2 `availabilityRule`

Deliberately shaped like a GOFS `operating_rule` — origin areas, destination areas,
a daily time window, a calendar:

```jsonc
{
  "fromIds": ["25_area_708"],          // shared stop/location/locationGroup namespace
  "toIds": ["25_area_708"],
  "startPickupTime": "08:00:00",       // "HH:MM:SS", >24h legal (both specs' semantics)
  "endPickupTime": "17:00:00",
  "endDropOffTime": "17:30:00",        // null when it matches endPickupTime
  "calendarIds": ["25_weekday"],
  "pickupType": 2,                     // 2 = must book; 3 = coordinate with driver
  "dropOffType": 2,
  "pickupBookingRuleId": "25_booking_route_74362",
  "dropOffBookingRuleId": "25_booking_route_74362",
  "safeDurationFactor": null,          // optional; clients with routing engines can
  "safeDurationOffset": null           // compute the spec's 95th-percentile estimate
}
```

The window is split into pickup and drop-off ends because both the real world and
GOFS require it: the Alexandria feed permits pickups until 24:50 but drop-offs until
25:00, and GOFS models exactly this as `end_dropoff_window`. A single intersected
window would silently discard the drop-off tail. All three time fields null means
the service runs all hours of its service days (GOFS's windowless-rule semantics).
`calendarIds` is an array because GOFS operating rules carry calendar arrays; flex
compilation emits one element, and rules identical except for calendar merge their
`calendarIds`.

### 2.3 Rule compilation (import time)

Rules are compiled from flex trips using the spec's reachability model — travel is
possible from any pickup-capable record to any *later* drop-off-capable record on the
same trip:

1. For each trip with at least one flex record, order records by `stop_sequence`.
2. A record is **pickup-capable** when it permits boarding: `pickup_type` = 2 for
   windowed records (1 means no pickup; 0 and 3 are forbidden with windows), or
   `pickup_type` ∈ {0, 2, 3} for timed-stop records. Symmetrically, a record is
   **drop-off-capable** when `drop_off_type` ∈ {2, 3} for windowed records or
   ∈ {0, 2, 3} for timed-stop records. Pair each pickup-capable record with each
   subsequent drop-off-capable record. Pairs where both records are timed fixed
   stops are skipped — that is ordinary fixed-route travel, not an on-demand rule.
3. Each pair emits one rule, with field provenance split by side: all
   pickup-side fields — `fromIds`, `pickupType`, `startPickupTime`/
   `endPickupTime` (for a timed fixed stop, a point window at its departure
   time), and `pickupBookingRuleId` — come from the pickup-capable record; all
   drop-off-side fields — `toIds`, `dropOffType`, `endDropOffTime` (window end,
   or arrival time for a timed stop; nulled when equal to `endPickupTime`), and
   `dropOffBookingRuleId` — from the drop-off-capable record. (Both records
   carry both booking-rule columns in real feeds; the side split disambiguates.)
   Calendar = the trip's `service_id`. `safeDuration*` comes from the trip, with
   the §1.1 stop_times fallback reading the pickup record first, then the
   drop-off record.
4. Rules identical except for `trip_id` collapse to one row per distinct
   (from, to, windows, calendar, types, booking) tuple, and rules identical except
   for calendar merge their `calendarIds`; the stored `trip_id` is a representative
   retained for traceability only and is not exposed in the API.

Pattern projections:

| Flex pattern | Compiles to | `serviceKind` |
|---|---|---|
| Dial-a-ride, single zone (Heartland Express) | zone→same zone, one rule per trip/window variant | `zone` |
| Zone-to-zone (Minnesota River Valley) | zone A→zone B | `zoneToZone` |
| Location group (RufBus) | group→same group; members via references | `stopGroup` |
| Deviated fixed route (Hermann Express) | fixed stop ↔ deviation zone pairs per segment | `deviatedRoute` |

A degenerate feed (e.g. the published Hermann example, which technically permits no
pickups anywhere) compiles to a service with areas and booking info but few or no
rules — still renderable. The algorithm is all-pairs by construction (that is what
the GTFS reachability rule requires — a deviated route's zones pair with every later
capable record, not just adjacent ones), but counts stay small in practice because
flex trips have few records (pure-zone trips have two; deviated trips a couple dozen),
and compilation happens once at import, so queries stay cheap.

**`serviceKind` classification (import time, normative).** Clients must not
infer the service's shape from `rules[]` — three clients would produce three
divergent heuristics, and the zero-rule degenerate case defeats all of them.
The importer classifies each service from its flex stop_time **records**
(which exist even when compilation yields no rules), first match wins:

1. any flex-involved trip mixes timed-stop records with location or
   location-group records → `deviatedRoute`;
2. any record references a location group → `stopGroup`;
3. records reference two or more distinct locations → `zoneToZone`;
4. records reference exactly one location → `zone`;
5. otherwise → `unknown` (unreachable for well-formed flex feeds; reserved
   for future providers).

Because classification reads records rather than compiled rules, the
degenerate Hermann example reports `deviatedRoute`, not `unknown` — its
records still carry the signal even though no rule survives compilation. The
value is stored in `ondemand_services.service_kind` (§1.2) and exposed on
`onDemandService` (§3.4).

### 2.4 New reference types

Added to the `references` block of `/api/ondemand` responses alongside
`agencies`/`routes`/`stops`/etc. **Mechanism:** the `/ondemand` handlers use an
extended references model that embeds the existing `ReferencesModel` struct and adds
the four new sections; the `/where` struct is untouched, so no new (even empty)
JSON keys ever appear in `/where` responses — that would violate the byte-identical
guarantee, and §5's regression test asserts it.

**`serviceAreas`** — GeoJSON Features with an always-present bounding box:

```jsonc
{
  "id": "25_area_708",
  "name": "Brown County",
  "bbox": [-94.87, 44.10, -94.25, 44.53],   // [minLon, minLat, maxLon, maxLat]
  "geometry": { "type": "Polygon", "coordinates": [ /* … */ ] }   // presence per §3
}
```

Real zone geometries are large — Alexandria's single polygon is a 4,239-point ring,
~340 KB of JSON — so `geometry` content is endpoint policy (§3), selected by
`geometryDetail=none|simplified|full`: `full` embeds the verbatim feed geometry,
`simplified` embeds the import-time display geometry (§1.3; ~15 KB for the
Alexandria ring, drawable straight onto a map), `none` omits the key entirely.
Simplified geometry is for **display only and must not be used for containment
or distance tests** — that is what `matchReason` and `distanceToArea` (§3.4)
exist for. `bbox` is always present and always derives from the full geometry.
Gzip (already in the middleware chain) does the rest.

**`locationGroups`**:

```jsonc
{ "id": "25_476_stops", "name": "RufBus 476 stops", "stopIds": ["25_4149546", "…"] }
```

**`bookingRules`** — the flex vocabulary camelCased verbatim; this field set is
already the shared Flex/GOFS dialect:

```jsonc
{
  "id": "25_booking_route_74362",
  "bookingType": 2,                    // 0 real-time | 1 same-day | 2 prior-day(s)
  "priorNoticeDurationMin": null,      // minutes; booking_type 1
  "priorNoticeDurationMax": null,
  "priorNoticeLastDay": 1,
  "priorNoticeLastTime": "15:00:00",
  "priorNoticeStartDay": 14,
  "priorNoticeStartTime": "00:00:00",
  "priorNoticeCalendarId": null,       // exposed under GOFS's field name; sourced from
                                       // GTFS prior_notice_service_id
  "message": null,
  "pickupMessage": null,
  "dropOffMessage": null,
  "phoneNumber": "+15073591717",
  "infoUrl": null,
  "bookingUrl": null
}
```

**`calendars`** — GOFS's shape, compiled from GTFS `calendar` + `calendar_dates`:

```jsonc
{
  "id": "25_weekday",
  "days": ["mon", "tue", "wed", "thu", "fri"],
  "startDate": "2026-01-05",
  "endDate": "2026-12-18",
  "exceptedDates": ["2026-09-07"]
}
```

Removed-service exceptions (`calendar_dates` type 2) become `exceptedDates`;
added-service exceptions (type 1) become standalone single-range calendars referenced
by additional rules — the GOFS idiom. The *structure* matches GOFS; the date *format*
deliberately does not (GOFS uses `YYYYMMDD`) — a future GOFS importer normalizes on
ingest rather than passing dates through.

**Time semantics, stated once for the whole API:** dates are `YYYY-MM-DD` strings and
times of day are `"HH:MM:SS"` strings that may exceed `24:00:00`, both interpreted as
service-day values in the timezone of the service's referenced agency
(`references.agencies[].timezone` — per GTFS this is `agency.agency_timezone`, never
`stops.stop_timezone`; the Alexandria feed, which declares a Los Angeles agency
timezone alongside a New York stop timezone, is imported exactly per that rule). For
future GOFS services the synthesized agency (§4) carries
`system_information.timezone`.

Stops referenced by rules or group memberships appear in `references.stops` in the
standard shape; routes and agencies likewise.

### 2.5 Booking deadline evaluation (normative)

The rider-facing line every client renders — "Book by 5:00 PM tomorrow, for a
ride on Wed, Jul 29" — is computed **client-side, never server-side**. All
three endpoints sit on the long-cache/static-ETag tier (§3) precisely because
they are static-data surfaces; a server-computed cutoff changes value at the
deadline itself, so caches would quietly serve stale deadlines — the single
worst failure mode this feature has, since a wrong deadline means a missed
ride. The computation is therefore specified here normatively, with shared
test vectors in §5, so iOS, Android, and Wayfinder implement one algorithm
instead of three silently-divergent ones.

All arithmetic is in **service days in the agency timezone** (§2.4) — never
the device wall clock, never a stop timezone (the Alexandria feed's LA-agency
/ NY-stop split exercises this deliberately). The service-day anchor is
GTFS's DST-safe convention:

```
anchor(date, tz)       = local noon of date in tz, minus 12 hours
instant(date, hms, tz) = anchor(date, tz) + hms      // hms may exceed 24:00:00
```

Evaluation is per **(availabilityRule, travel date D)**, where D is an active
service day of one of the rule's `calendarIds`. The **pickup side governs
booking**: use the rule's `pickupBookingRuleId`; the drop-off booking rule is
informational. A rule with no pickup booking rule requires no notice:
`state = open`, `cutoffInstant = null`.

```
evaluate(rule, bookingRule, D, now, tz, calendars)
    → (state ∈ {notYetOpen, open, closedForDate}, cutoffInstant, openInstant)

latestPickup = instant(D, rule.endPickupTime ?? "24:00:00", tz)

switch bookingRule.bookingType:
  case 0:  // real-time: booked at ride time
    cutoffInstant = latestPickup
    openInstant   = null
  case 1:  // same-day, minutes-based
    cutoffInstant = latestPickup − priorNoticeDurationMin minutes
    openInstant   =                          // GTFS forbids both bounds at once
      priorNoticeDurationMax != null:
        instant(D, rule.startPickupTime ?? "00:00:00", tz)
          − priorNoticeDurationMax minutes
      priorNoticeStartDay != null:
        instant(D − priorNoticeStartDay calendar days, priorNoticeStartTime, tz)
      else: null
    // refinement for a chosen pickup instant P:
    //   bookable iff  P − durationMax ≤ now ≤ P − durationMin
  case 2:  // prior day(s)
    lastDayDate   = countBack(D, priorNoticeLastDay, priorNoticeCalendarId)
    cutoffInstant = instant(lastDayDate, priorNoticeLastTime, tz)
    openInstant   = priorNoticeStartDay == null ? null :
      instant(D − priorNoticeStartDay calendar days, priorNoticeStartTime, tz)

state = now < openInstant   → notYetOpen
        now > cutoffInstant → closedForDate
        otherwise           → open

countBack(D, n, calendarId):
    calendarId == null → D − n calendar days
    otherwise: step back from D one calendar day at a time, counting only
    days on which calendarId is active (its §2.4 calendar, including
    exceptedDates), until n such days are consumed; return the n-th.
    countBack(D, 0, _) = D.
```

Normative notes:

- **`closingSoon` is a client presentation state, not part of `state`**:
  `open` with `cutoffInstant − now` under a client-chosen threshold (iOS
  plans ~2 h). Deliberately left to the client so products can tune urgency
  copy without a spec change — this is a decision, not an omission.
- **`notYetOpen` is a distinct state**, not a flavor of `closedForDate`:
  Alexandria's `priorNoticeStartDay` of 14 makes it reachable for any travel
  date more than two weeks out, and it needs different copy ("Booking opens
  …") than a missed deadline.
- **`priorNoticeCalendarId` counts service days for `priorNoticeLastDay`
  only**; `priorNoticeStartDay` always counts calendar days (per GTFS). A
  holiday on the referenced calendar shifts the deadline earlier.
- **`nextBookableServiceDate`** = the earliest active service day D′ of the
  rule's `calendarIds` (searching from the agency-local today forward,
  bounded by the calendar's `endDate`) with `evaluate(D′).state = open`.
- **Multi-rule resolution:** evaluate only rules whose calendars are active
  on D. When summarizing at service level for a date, display the earliest
  `cutoffInstant` among those rules — conservative: never later than any
  real deadline the rider might hit.

## 3. Endpoints & Contracts

All endpoints: HTTP GET, `.json`, API-key validation, rate limiting, gzip, standard
OBA envelope. Registered in `internal/restapi/routes.go` next to the `/where` routes.

| Endpoint | Contract |
|---|---|
| `/api/ondemand/services-for-location.json` | `lat` + `lon` (required floats); two **peer** matching modes. **Point mode** (default): services whose areas contain the point, whose area boundaries lie within `radius` meters of it (near-miss), **or** whose rule-referenced stops fall within `radius` meters (`radius` optional; same default as `stops-for-location`) — without the radius, stop-based services (location groups, windowed stops) would be unreachable from a point query, and near-miss matching is what lets a client explain "you're just outside the zone" instead of showing nothing. **Viewport mode** (`latSpan` + `lonSpan`): area-intersects-viewport and stop-within-viewport, mirroring `stops-for-location` conventions; the expected default for map-driven clients — both OBA mobile apps fetch per map region on every pan, not per radius. Each list element carries `matchReason` (§3.4); a service matching on several grounds reports the strongest (`areaContainsPoint` > `stopWithinRadius` > `areaNearby`; `areaIntersectsViewport` > `stopWithinViewport`). List response. |
| `/api/ondemand/services-for-agency/{id}.json` | All on-demand services for the agency. List response. |
| `/api/ondemand/service/{id}.json` | Single service, full rules + references. Entry response. |

Geometry policy (§2.4): all three endpoints accept
`geometryDetail=none|simplified|full`. Defaults: `full` on `service/{id}` (the
rider has expressed intent; a one-time large payload is fine), `simplified` on
the two list endpoints (~15 KB per Alexandria-sized zone — drawable straight
onto the map with no second request). `bbox` is always present at every detail
level. There is no boolean `includeGeometry` — the tri-state replaces it
before anything ships. List responses use the standard
list envelope with `limitExceeded: false` and no `maxCount` in v1 — on-demand
service counts are small (most feeds have a handful; Alexandria has one).

Point mode and viewport mode are **peers** — neither is a fallback. Radius is
the right primary for a "near me" button; viewport is the right primary for a
map-first client, which is what both mobile apps are. Parameter precedence
follows the existing `BoundsFromParams` conventions as a tiebreak only: when
both `radius` and `latSpan`/`lonSpan` are supplied, radius wins. In viewport
mode the stop-based test becomes stops-within-viewport, area matching becomes
area-intersects-viewport, and near-miss (`areaNearby`) matching does not
apply. All three endpoints are static-data surfaces and get the same
middleware tier as `/where` static routes:
`CacheControlMiddleware(CacheDurationLong)` plus the static ETag — responses
vary only by URL and dataset version, which is why per-query values like
`matchReason` and `distanceToArea` are cache-safe while a server-computed
booking deadline would not be (§2.5).

That is the entire v1 surface. `services-for-stop` / `services-for-route` lookups are
deliberately omitted — pointer fields make them redundant (YAGNI).

Service IDs for flex services equal the underlying route's combined ID. OBA entity
types have separate ID spaces, so this collides with nothing.

### 3.1 Pointer fields on `/api/where` (the entire coupling surface)

- **Stop entries** gain `"onDemandServiceIds": [...]` when the stop is referenced by
  any compiled rule or location-group membership — this includes a deviated route's
  ordinary timed stops, which participate in rules without having windowed records
  themselves.
- **Route entries** gain the same when any trip of the route is flex-involved.

The field is **omitted when empty**: non-flex feeds produce byte-identical `/where`
responses to today. Trips need no pointer — every trip screen knows its route.
These two additive fields are the only `/where` divergence from the upstream OpenAPI
spec, to be proposed upstream together with the namespace once proven.

### 3.2 Legacy-surface policy for flex data

- Flex-only routes (dial-a-ride) **continue to appear** in `routes-for-agency` — the
  status quo for imported flex feeds; old apps see a route with no stops, new apps
  see the pointer and render zone UI.
- Flex-only (windowed) stop_times records are **excluded** from
  arrivals-and-departures, schedule-for-stop/route, and trip-details stop-time lists
  — no phantom arrival times. This follows the spec's own consumer routing rule.
- **Flex-only trips** (every record windowed — e.g. both Alexandria trips) have no
  timed stop_times at all, so each trip-serving `/where` endpoint gets an explicit
  disposition: excluded from `trips-for-route`, `trips-for-location`, and
  `block/{id}` (their NULL min/max arrival caches drop them from time-window
  queries naturally — see §1.2); `trip/{id}` and `trip-details/{id}` return the
  trip entity with an empty schedule and no status rather than 404, since the ID
  is real and referenceable. Deviated trips (mixed records) appear everywhere,
  showing only their timed records.
- Zones are not stops: `stops-for-location` and stop-ID surfaces never contain
  locations or location groups.

### 3.3 Errors

Standard OBA semantics: `404` entry-not-found for unknown service IDs **and for
unknown agency IDs on `services-for-agency`** (matching `routes-for-agency`; a
known agency with zero on-demand services returns an empty list); `400` with
`fieldErrors` for missing/invalid coordinates (existing `utils.ParseFloatParam`
path); an empty `list` (not an error) when nothing matches a location. "Matches"
includes the near-miss ground (§3): a rider just outside a zone still receives
the service with `matchReason: "areaNearby"` plus `distanceToArea` /
`nearestPointOnBoundary` (§3.4) — the difference between "not available here"
and "the zone starts 1.2 mi north." A point inside no area still returns a
non-empty `list` whenever stop-radius or near-miss matching found services. A
client wanting a richer negative state after a genuinely empty response may
re-query with a larger explicit `radius` — one extra round-trip in the
negative case only, rather than `services-for-agency` plus client-side
geometry. The namespace is always mounted — a feed with zero flex data yields
empty lists, never 404s, so clients can probe cheaply.

### 3.4 Response schemas

All responses use the standard Maglev envelope (`internal/models/response.go`):

```jsonc
{
  "code": 200,
  "currentTime": 1753560000000,      // Unix ms
  "text": "OK",
  "version": 2,
  "data": { /* entry-or-list payload below */ }
}
```

`service/{id}` uses the entry payload `{ "entry": <onDemandService>, "references":
<references> }`. The two list endpoints use `{ "limitExceeded": false, "list":
[<onDemandService>], "references": <references> }`; `services-for-location`
additionally carries `"outOfRange"`. **`outOfRange` cannot simply reuse the
`/where` computation**: `CheckIfOutOfBounds` derives per-agency region bounds
from stops only, and a flex agency like Alexandria has one stop inside a ~50 km
zone — a point inside the zone would match services yet read as out of range.
For `/ondemand`, `outOfRange` is computed against the union of the agency stop
bounds and all `serviceAreas` bboxes — in point **and** viewport mode alike;
the motivating Alexandria case (one stop inside a ~50 km zone) breaks
identically in both. `agencies-with-coverage` (which uses the
same stop-derived bounds) is deliberately left untouched in v1 per the additive
rule, noted as a future improvement for flex-heavy agencies.

Convention for the new object types: absent optional values are JSON `null`
(not omitted keys and not empty strings), except where a field is explicitly
documented as omitted-when-empty.

**Ordering is part of the contract** (golden files and caching need determinism):
`rules` sort by (`startPickupTime` ascending, nulls first; then `endPickupTime`;
then `calendarIds[0]`); `list` sorts by service `id`; every reference array sorts
by `id`. Golden-file comparison in §5 is structural (parsed JSON), not byte
order — Go struct serialization fixes key order anyway.

#### Field schemas

**`onDemandService`** (entry and list element):

| Field | Type | Nullable | Notes |
|---|---|---|---|
| `id` | string | no | Combined ID; for flex, equals the route's combined ID |
| `agencyId` | string | no | For GOFS: the synthesized agency (§4) |
| `routeId` | string | yes | `null` for GOFS-sourced services |
| `name` | string | no | Route short/long name; GOFS: brand/system name |
| `serviceKind` | string enum | no | `zone` \| `zoneToZone` \| `stopGroup` \| `deviatedRoute` \| `unknown`; derived at import (§2.3), independent of provider |
| `description` | string | yes | |
| `url` | string | yes | |
| `rules` | array of `availabilityRule` | no | May be empty (degenerate feeds, §2.3) |
| `matchReason` | string enum | — | **`services-for-location` list elements only; key omitted everywhere else.** Point mode: `areaContainsPoint` \| `stopWithinRadius` \| `areaNearby`; viewport mode: `areaIntersectsViewport` \| `stopWithinViewport`. Strongest ground wins (§3) |

**`availabilityRule`**:

| Field | Type | Nullable | Notes |
|---|---|---|---|
| `fromIds` | array of string | no | IDs in the shared stop/location/locationGroup namespace |
| `toIds` | array of string | no | |
| `startPickupTime` | string `"HH:MM:SS"` | yes | May exceed `24:00:00`; all three time fields `null` = all service-day hours |
| `endPickupTime` | string `"HH:MM:SS"` | yes | |
| `endDropOffTime` | string `"HH:MM:SS"` | yes | Also `null` when equal to `endPickupTime` |
| `calendarIds` | array of string | no | ≥1 element; → `references.calendars` |
| `pickupType` | integer | no | 0 scheduled, 2 must book, 3 coordinate with driver (1 cannot appear: pickup-capable records only) |
| `dropOffType` | integer | no | Same value set |
| `pickupBookingRuleId` | string | yes | → `references.bookingRules` |
| `dropOffBookingRuleId` | string | yes | |
| `safeDurationFactor` | number | yes | §2.2 |
| `safeDurationOffset` | number | yes | Seconds |

**`serviceArea`** (reference):

| Field | Type | Nullable | Notes |
|---|---|---|---|
| `id` | string | no | Combined ID |
| `name` | string | yes | `properties.stop_name` |
| `description` | string | yes | `properties.stop_desc` |
| `bbox` | `[number, number, number, number]` | no | `[minLon, minLat, maxLon, maxLat]` (RFC 7946 order); always derived from the full geometry |
| `geometry` | GeoJSON geometry object | — | `Polygon` or `MultiPolygon`; **key omitted** (not null) at `geometryDetail=none`; simplified display geometry (§1.3, never for containment tests) at `simplified`; verbatim feed geometry at `full` |
| `distanceToArea` | number | yes | Meters from the query point to this area's nearest boundary; `0` when the point is inside. Non-null only in `services-for-location` point mode; `null` in viewport mode and on the other two endpoints |
| `nearestPointOnBoundary` | `[number, number]` | yes | `[lon, lat]` of the closest boundary point; same presence rules as `distanceToArea`, and additionally `null` when the point is inside. Gives clients a bearing ("1.2 mi **north**"), which a scalar distance cannot |

**`locationGroup`** (reference): `id` string, `name` string nullable,
`stopIds` array of string (members also appear in `references.stops`).

**`bookingRule`** (reference):

| Field | Type | Nullable | Notes |
|---|---|---|---|
| `id` | string | no | Combined ID; synthesized for GOFS (§4) |
| `bookingType` | integer | no | 0 real-time, 1 same-day, 2 prior-day(s) |
| `priorNoticeDurationMin` | integer | yes | Minutes; `bookingType` 1 only |
| `priorNoticeDurationMax` | integer | yes | Minutes |
| `priorNoticeLastDay` | integer | yes | Days before travel; `bookingType` 2 |
| `priorNoticeLastTime` | string `"HH:MM:SS"` | yes | |
| `priorNoticeStartDay` | integer | yes | |
| `priorNoticeStartTime` | string `"HH:MM:SS"` | yes | |
| `priorNoticeCalendarId` | string | yes | Combined ID → `references.calendars` (the import compiles a calendar for any `prior_notice_service_id` it sees); GOFS field name, sourced from GTFS `prior_notice_service_id` |
| `message` / `pickupMessage` / `dropOffMessage` | string | yes | |
| `phoneNumber` | string | yes | As published in the feed |
| `infoUrl` / `bookingUrl` | string | yes | |

**`calendar`** (reference): `id` string; `days` array drawn from
`["mon","tue","wed","thu","fri","sat","sun"]`; `startDate`/`endDate`
`"YYYY-MM-DD"`; `exceptedDates` array of `"YYYY-MM-DD"` (possibly empty).
Time semantics per §2.4.

**References block** (`/ondemand` responses only): the six standard keys
(`agencies`, `routes`, `situations`, `stopTimes`, `stops`, `trips` — shapes
unchanged from `/where`) plus `serviceAreas`, `locationGroups`, `bookingRules`,
`calendars`. All ten keys always present, empty arrays when unused.

**Pointer field**: `"onDemandServiceIds"`, array of string, on **any
serialization of the Route and Stop models** — entries and references, in both
namespaces, explicitly including `references.stops` and `references.routes`
inside `/ondemand` responses. (References reuse `models.Route`/`models.Stop`,
so this falls out of the type system — but clients may rely on it as contract:
a location-group member row can know whether a stop page will carry a flex
overlay before fetching it.) Like `matchReason`, it is omitted-when-empty
rather than null, preserving byte-identical output for non-flex feeds.

#### Worked example: `GET /api/ondemand/service/5088_77652.json` (Alexandria)

```jsonc
{
  "code": 200,
  "currentTime": 1785096000000,     // keys follow ResponseModel struct order:
  "data": {                         // code, currentTime, data, text, version
    "entry": {
      "id": "5088_77652",
      "agencyId": "5088",
      "routeId": "5088_77652",
      "name": "DOT Paratransit",
      "serviceKind": "zone",
      "description": null,
      "url": null,
      "rules": [                    // sorted per §3.4: startPickupTime ascending
        {
          "fromIds": ["5088_area_1449"],
          "toIds": ["5088_area_1449"],
          "startPickupTime": "05:00:00",
          "endPickupTime": "24:50:00",
          "endDropOffTime": "25:00:00",
          "calendarIds": ["5088_c_71675_b_85952_d_63"],   // Mon–Sat
          "pickupType": 2,
          "dropOffType": 2,
          "pickupBookingRuleId": "5088_booking_route_77652",
          "dropOffBookingRuleId": "5088_booking_route_77652",
          "safeDurationFactor": 1.0,
          "safeDurationOffset": 0.0
        },
        {
          "fromIds": ["5088_area_1449"],
          "toIds": ["5088_area_1449"],
          "startPickupTime": "07:00:00",
          "endPickupTime": "24:50:00",
          "endDropOffTime": "25:00:00",
          "calendarIds": ["5088_c_71675_b_85952_d_64"],   // Sunday only (§5)
          "pickupType": 2,
          "dropOffType": 2,
          "pickupBookingRuleId": "5088_booking_route_77652",
          "dropOffBookingRuleId": "5088_booking_route_77652",
          "safeDurationFactor": 1.0,
          "safeDurationOffset": 0.0
        }
      ]
    },
    "references": {
      "agencies": [ { /* standard AgencyReference: id "5088", name "Alexandria DOT",
                       timezone "America/Los_Angeles", … */ } ],
      "routes":   [ { /* standard Route: id "5088_77652", longName "DOT Paratransit",
                       onDemandServiceIds ["5088_77652"], … */ } ],
      "situations": [], "stopTimes": [], "stops": [], "trips": [],
      "serviceAreas": [
        {
          "id": "5088_area_1449",
          "name": null,
          "description": null,
          "bbox": [-77.5372039, 38.617508, -76.9092198, 39.057831],
          "geometry": { "type": "Polygon", "coordinates": [ /* 4,239-point ring */ ] }
        }
      ],
      "locationGroups": [],
      "bookingRules": [
        {
          "id": "5088_booking_route_77652",
          "bookingType": 2,
          "priorNoticeDurationMin": null,
          "priorNoticeDurationMax": null,
          "priorNoticeLastDay": 1,
          "priorNoticeLastTime": "17:00:00",
          "priorNoticeStartDay": 14,
          "priorNoticeStartTime": "00:00:00",
          "priorNoticeCalendarId": null,
          "message": "DOT is the City of Alexandria's paratransit program, …",
          "pickupMessage": null,
          "dropOffMessage": null,
          "phoneNumber": "703-746-5222",
          "infoUrl": "https://www.alexandriava.gov/Paratransit",
          "bookingUrl": "https://spare-rider-alexandriadot-production.vercel.app/…"
        }
      ],
      "calendars": [
        {
          "id": "5088_c_71675_b_85952_d_63",
          "days": ["mon", "tue", "wed", "thu", "fri", "sat"],
          "startDate": "2025-12-01",
          "endDate": "2026-12-01",
          "exceptedDates": []
        },
        {
          "id": "5088_c_71675_b_85952_d_64",
          "days": ["sun"],
          "startDate": "2025-12-01",
          "endDate": "2026-12-01",
          "exceptedDates": []
        }
      ]
    }
  },
  "text": "OK",
  "version": 2
}
```

The list endpoints return the same `onDemandService` objects (full `rules`
included — rule counts are small, §3) inside the list payload; their
`serviceAreas` references carry `bbox` plus simplified `geometry` by default
(`geometryDetail`, §3), and `services-for-location` elements additionally
carry `matchReason`. This worked example doubles as the golden-file shape for
the §5 Alexandria endpoint tests.

## 4. GOFS Forward Compatibility

GOFS (v1.0, MobilityData-stewarded since 2025) is **a second importer, not a second
API**. The mapping:

| GOFS file | Lands as |
|---|---|
| `zones.json` | `serviceAreas` (accept `zone_id` Feature placement; Polygon-only is a subset of what we store) |
| `operating_rules.json` | `availabilityRules` — the reason rules are shaped as (from, to, pickup window + `endDropOffTime`, calendar array); GOFS's `end_dropoff_window` and windowless all-hours rules map directly |
| `calendars.json` | `calendars` — same structure; dates normalized from GOFS's `YYYYMMDD` on ingest |
| `booking_rules.json` | `bookingRules` — the *field vocabulary* is shared near-verbatim (`prior_notice_calendar_id` is already our exposed name), but the *linkage* is not: GOFS entries have no ID and anchor to zones via `from_zone_ids`/`to_zone_ids`. The importer synthesizes one `bookingRule` (with a generated ID) per GOFS entry and attaches it to every availabilityRule whose from/to zones match. |
| `system_information.json` + `service_brands.json` | `onDemandService` entries with `routeId: null` |

**Identity for GOFS feeds:** GOFS has no agency concept and its IDs are not globally
unique. Each GOFS feed gets a synthesized agency built from
`system_information.json` (name, timezone, url, configured feed ID), registered in
`references.agencies`; that feed ID becomes the combined-ID prefix for its services,
zones, booking rules, and calendars, and is what `services-for-agency/{id}`
addresses. With that in place, all three endpoints serve GOFS-sourced services with
zero contract changes. GOFS services classify into the same `serviceKind` enum
from their operating rules (`zone` / `zoneToZone`); the enum needs no
GOFS-specific member.

**Reserved extension points** — documented here, absent from v1 responses, never to
be occupied with different semantics:

- `brand` (object on `onDemandService`) **and `brandId` (string on
  `availabilityRule`)**: GOFS attaches `brand_id` per operating rule (absent = all
  brands), so the rule-level slot must be reserved too or a GOFS importer would be
  forced into service-per-brand duplication.
- `eligibility` (object on `onDemandService`):
  `{ "requirement": "open" | "certificationRequired" | "unknown", "infoUrl": string|null }`.
  Neither GTFS-Flex nor GOFS models rider eligibility, yet ADA paratransit is a
  large fraction of real-world flex service — today the only signal is prose
  inside `bookingRules[].message`, which no client can safely pattern-match
  (and which fails entirely for non-English feeds). Absent from v1 responses;
  **normative client rule: a missing `eligibility` means "no eligibility
  information published," never "open to all."** The real fix is proposing the
  field upstream alongside the namespace (§Decisions of Record).
- `vehicleTypes` (array on `onDemandService` or rules): capacity, wheelchair enum.
- `waitTime` / `fares`: GOFS dynamic and metered-fare data.
- `deepLinks` (object on `bookingRules`): `iosUri` / `androidUri` / `webUri` /
  `phoneNumber` with GOFS's standardized pickup/drop-off handoff query params.
- Endpoint: `/api/ondemand/quote.json` — future proxy for GOFS `wait_time` /
  `realtime_booking`.

## 5. Testing

The primary integration fixture is a **real feed**: `testdata/alexandria-flex.zip`,
the City of Alexandria VA DOT Paratransit flex-v2 feed published by Trillium
(https://data.trilliumtransit.com/gtfs/cityofalexandria-va-us/cityofalexandria-va-us--flex-v2.zip,
snapshot committed to the repo). It is tiny (one route, two trips, four stop_times
rows, one zone) yet exercises exactly the quirks synthetic fixtures wouldn't:
draft-era `mean_duration_*` columns, `safe_duration_*` on stop_times instead of
trips, >24h windows, asymmetric pickup/drop-off ends (24:50 vs 25:00), header-only
empty `location_groups.txt`/`location_group_stops.txt`, a 4,239-point polygon, and
a mismatched agency-vs-stop timezone.

- **Parser tests** live upstream in go-gtfs, using fixtures built from the gtfs.org
  flex examples (all four patterns: Heartland, MRVT, RufBus, Hermann) plus
  Alexandria excerpts for draft-column tolerance and empty flex files.
- **Rule compilation**: unit tests mapping each pattern's stop_times to expected
  rules, including the degenerate no-pickup case, the dedup/merge steps, and a
  deviated-route fixture with `pickup_type`/`drop_off_type` columns omitted
  entirely — guarding the enum-default fix (§1.1) that the always-explicit
  Alexandria feed cannot catch.
  Alexandria end-to-end: exactly two rules (zone→same zone; 07:00–24:50 pickup /
  25:00 drop-off on the Sunday-only calendar, 05:00 start on the no-Sunday one —
  note the counterintuitive pairing; it is what the feed says),
  `safeDurationFactor` 1.0 / offset 0.0 via the stop_times fallback, and the
  `booking_type=2` rule (start day 14, last day 1 at 17:00) attached to both.
- **Geometry**: point-in-polygon with holes, MultiPolygon, viewport-intersection
  mode, points on boundaries; nearest-boundary distance and point (inside → 0,
  known outside fixtures); import-time simplification (≤256 points per ring,
  ≤10 m vertex deviation, hole structure and winding preserved).
- **Integration**: endpoint tests via `serveApiAndRetrieveEndpoint` against the
  Alexandria fixture for all three endpoints — point containment inside/outside the
  zone, the three `geometryDetail` levels, `matchReason` values (inside →
  `areaContainsPoint`, just outside → `areaNearby` with `distanceToArea` /
  `nearestPointOnBoundary`, viewport values), `serviceKind`, and route pointer
  fields. Location-group and deviated-route *endpoint* coverage (stop pointer
  fields, stop-radius matching) uses one minimal synthetic fixture derived from the
  gtfs.org RufBus/Hermann examples, since Alexandria exercises neither pattern.
- **Booking evaluation vectors**: `testdata/flex-booking-vectors.json` — a
  table of (`bookingRule`, rule window, calendars, travel date, reference
  instant) → expected (`state`, `cutoffInstant`, `nextBookableServiceDate`)
  per §2.5, committed next to `alexandria-flex.zip` and mirrored into the
  iOS/Android/Wayfinder test suites so all three clients verify against the
  same vectors instead of against each other. Minimum cases: Alexandria's
  `booking_type=2` evaluated just before and just after 17:00; a
  post-midnight service day (the 24:50/25:00 windows); a `bookingType=1`
  same-day rule; a `priorNoticeCalendarId` that excludes the intervening day;
  and a `priorNoticeStartDay=14` travel date far enough out to yield
  `notYetOpen`.
- **Additive-guarantee regression**: importing plain `raba.zip` must produce `/where`
  responses containing no flex fields and no new references keys anywhere.
- **Import invariants**: fixtures with each violation class (two location refs, a
  window plus arrival_time, dangling booking rule) assert log-and-skip behavior.

## 6. Implementation Sequencing (for the plan)

1. go-gtfs: parse the four files + new fields, tolerating draft-era columns
   (upstream PR; prerequisite).
2. Maglev schema (including the `stop_times` arrival/departure nullability
   migration and its query fallout) + import + rule compilation, geometry
   simplification, and `service_kind` classification (no API changes;
   testable via DB). The gatekeeper to change **first** is
   `ValidateAndFilterGTFSData` (`gtfsdb/helpers.go:1448`): today it drops any
   trip with zero stop_times or any nil/empty-stop record and hard-fails when
   all trips are filtered — it must accept exactly-one-of stop/location/group
   records and not treat a flex-only feed as fatally empty. Only once it admits
   stop-less records does the second-order audit matter: every `st.Stop`
   dereference and timed-first-record assumption — `gtfsdb/helpers.go:419`
   (`st.Stop.Id` at insert), `:1284` (first-stop lookup), `:1404` (block sort by
   `StopTimes[0].DepartureTime`, which would sort zeroed times), `:1414`/`:1422`
   (block layover pairing). The go-gtfs version bump, the validator change, and
   these guards must land in the same change.
3. `/api/ondemand` endpoints + extended references model.
4. `/where` pointer fields + legacy-surface exclusions + additive regression test.
5. Test fixtures (`alexandria-flex.zip`, the minimal synthetic group/deviated
   fixture, and `flex-booking-vectors.json`) threaded through 2–4.

## Appendix: Source Material

- GTFS Schedule reference (Flex merged March 2024): https://gtfs.org/documentation/schedule/reference/
- Flex examples (all four patterns): https://gtfs.org/documentation/schedule/examples/flex/
- Original merge PR: https://github.com/google/transit/pull/433
- GOFS spec: https://github.com/MobilityData/GOFS (v1.0 `reference.md`)
- GOFS positioning: https://mobilitydata.org/gofs-a-new-chapter-for-on-demand-transportation-data/
- Real test feed: City of Alexandria VA flex v2 (Trillium),
  https://data.trilliumtransit.com/gtfs/cityofalexandria-va-us/cityofalexandria-va-us--flex-v2.zip
  — snapshot at `testdata/alexandria-flex.zip`
- Notable spec facts relied on above: shared ID namespace across stops/locations/groups;
  windows forbid `arrival_time`/`departure_time` and `pickup_type` ∈ {0,3}
  (`drop_off_type` 3 allowed); `prior_notice_*` durations are minutes;
  `location_group_name` optional; `safe_duration_*` live on trips.txt (the draft-era
  `mean_duration_*` fields were dropped); consumers ignore windowed records when
  computing fixed-route timing; `prior_notice_service_id` counts service days for
  `prior_notice_last_day` only (start day counts calendar days).
- Gap flagged for the upstream proposal: neither GTFS-Flex nor GOFS models rider
  eligibility (ADA certification), despite paratransit being a large fraction of
  real-world flex data — see the reserved `eligibility` extension point (§4).
