# Rental Range Filter and Fuel Labels

Two related additions to the rental map layers:

1. A **minimum-range filter** in the Map sheet, so riders never have to tap a
   scooter only to discover it has two miles left in it.
2. A **fuel label** under each rental annotation, so the same judgment can be
   made at a glance without tapping anything.

Both act on `FuelInfo`, which carries `percent` (a 0...1 charge ratio) and
`range` (estimated remaining meters). Either may be nil, and on the launch feed
`percent` is null across the entire fleet while `range` is populated — every
decision below is shaped by that asymmetry.

## Decisions

| Question | Decision |
| --- | --- |
| Label content | `percent` when present, else `range`, else no label |
| Filter control | Menu-style picker with discrete presets |
| Entities without range data | Fail open — always shown |
| Label density | Gated on a zoom threshold tighter than the layer's own |
| Threshold scope | One shared value for Bikes and Scooters |

## Architecture

### Filtering model

Three new types, all pure Swift with no MapKit and no async.

**`RentalRangeFilter`** — the predicate.

```swift
struct RentalRangeFilter: Equatable {
    /// Threshold in meters. Zero means "Any" — no filtering at all.
    let minimumRangeMeters: Int

    static let any = RentalRangeFilter(minimumRangeMeters: 0)
    var isActive: Bool { minimumRangeMeters > 0 }

    func allows(_ rental: VehicleRental) -> Bool {
        guard isActive,
              case .vehicle(let vehicle) = rental,
              let range = vehicle.fuel?.range else {
            return true
        }
        return range >= minimumRangeMeters
    }
}
```

The single `guard` encodes fail-open: docked stations, pedal bikes, and powered
vehicles whose feed omits `range` all leave through the same early return. This
matches the fail-open convention already established by
`VehicleRental.matches(formFactors:)`, and it means the filter can never empty
the map on a feed that doesn't publish range.

Comparison is `>=`, so a 5 mi threshold keeps a vehicle reporting exactly
5 mi (8,047 m at the preset's stored value).

**`RentalRangePreset`** — the menu ladder.

```swift
struct RentalRangePreset: Equatable, Identifiable {
    let meters: Int     // 0 == Any
    let title: String   // "Any", "5 mi", "10 km"
    var id: Int { meters }

    static func presets(measurementSystem: Locale.MeasurementSystem) -> [RentalRangePreset]
    static func nearest(toMeters: Int, in presets: [RentalRangePreset]) -> RentalRangePreset
}
```

Rungs are whole numbers in the rider's own units rather than a metric ladder
converted from miles — "8 km" reads as a bug:

- Imperial: Any, 1 mi, 2 mi, 5 mi, 10 mi, 15 mi
- Metric: Any, 2 km, 5 km, 10 km, 15 km, 25 km

`Locale.MeasurementSystem` is a **struct**, not an enum — it has `.metric`,
`.us`, and `.uk`, and can be constructed from any BCP-47 identifier, so it can
never be switched exhaustively. The selection is therefore written to make the
mile ladder the *explicit* case and metric the fallback:

```swift
let system = Locale.current.measurementSystem
let usesMiles = system == .us || system == .uk
```

The `.uk` case genuinely wants miles — UK road distances are in miles even
though the UK is otherwise metric — and any unrecognized or future system falls
through to metric, which is right for most of the world. Testing `== .metric`
and defaulting the other branch to miles would get `.uk` right by accident and
every unknown system wrong.

Titles come from a `MeasurementFormatter` with `unitOptions = .providedUnit` and
zero fraction digits, so the displayed number matches the rung exactly. Verified
empirically: this yields exactly "5 mi" and "10 km" under `en_US`, `de_DE`, and
`en_GB` — `.providedUnit` suppresses both conversion and locale substitution, and
mutating `formatter.numberFormatter` in place takes effect. "Any" is a localized
string, not a formatted measurement.

The persisted value is always meters. When it doesn't match a rung in the
current ladder — the rider's locale changed after they chose one — the menu
highlights the nearest rung via `nearest(toMeters:in:)` while filtering
continues to use the stored value. Snapping and rewriting on read would silently
alter a preference the rider set deliberately.

**`RentalVisibility`** — the cache that makes the filter work at all.

`VehicleRentalSource` emits only diffs (`added` / `removed` / `updated`) against
what it has previously delivered. If the coordinator simply declined to create
an annotation for an under-threshold vehicle, that vehicle would never reappear
when the threshold was lowered — it isn't in `added` anymore. So the client needs
its own complete cache of delivered entities, with visibility derived from it.

```swift
struct RentalVisibility {
    struct Changes: Equatable {
        var added: [VehicleRental] = []
        var removed: [VehicleRental.ID] = []
        var updated: [VehicleRental] = []
        var isEmpty: Bool { added.isEmpty && removed.isEmpty && updated.isEmpty }
    }

    private(set) var formFactors: Set<VehicleFormFactor> = []
    private(set) var filter: RentalRangeFilter = .any

    mutating func apply(_ snapshot: VehicleRentalSnapshot) -> Changes
    mutating func setFormFactors(_ formFactors: Set<VehicleFormFactor>) -> Changes
    mutating func setFilter(_ filter: RentalRangeFilter) -> Changes
}
```

An entity is visible when it matches the current form factors **and** passes the
filter. Every mutation returns the exact set of changes to apply to the map, so
the caller never has to recompute anything.

It needs no isolation annotation and no explicit `Sendable` conformance. OBAKit
defaults to main-actor isolation, so `RentalVisibility` is implicitly main-actor
isolated; it lives as a `var` on the `@MainActor` `RentalLayerCoordinator` and is
mutated only from that class's main-actor methods. The existing
`Task { for await snapshot in snapshots }` pattern already inherits the
enclosing main-actor context, which is why the current `apply(_:)` call compiles
today, and `Changes` never crosses an isolation boundary — it is returned to a
main-actor caller. A struct is preferable to a class here precisely because it
cannot be captured and mutated from somewhere else.

Memory stays bounded without extra work: the source replaces its `delivered` map
wholesale on each fetch and reports everything absent as `removed`, so the cache
tracks the padded viewport rather than growing across a session.

The case that needs the most care is an `updated` entity that **crosses** the
threshold — a scooter that drained below it, or fresh data that lifts one above
it. Such an entity must be translated into an add or a remove, not an update:

| Was visible | Now visible | Emitted as |
| --- | --- | --- |
| yes | yes | `updated` |
| yes | no | `removed` |
| no | yes | `added` |
| no | no | nothing |

For determinism, `apply` preserves snapshot order, while the wholesale
recomputations in `setFormFactors` and `setFilter` sort by id — mirroring how
`VehicleRentalSource` sorts its own `removed` array.

This type also absorbs `RentalLayerCoordinator.pruneAnnotations(notMatching:)`,
which does a subset of the same job today. The coordinator is left with what it
should have been all along: translating `Changes` into `MKMapView` calls.

### Ownership and wiring

The threshold is one shared value across both rental layers, so it lives on
`MapRegionManager` beside the existing per-layer enablement, under
`mapLayer.rentals.minimumRangeMeters`:

```swift
public static let rentalMinimumRangeDefaultsKey = "mapLayer.rentals.minimumRangeMeters"
public var rentalRangeFilter: RentalRangeFilter { get set }  // setter persists + posts
```

Putting it here makes the Map sheet's Reset button work without new machinery:
`mapLayersDifferFromDefaults` ORs in `rentalRangeFilter != .any`, and
`resetMapLayersToDefaults()` sets it back to `.any`. The manager already
references `StopsMapLayer.layerID` directly, so a rental-specific property is
not a new kind of coupling.

The alternative — a dedicated `RentalRangeFilterStore` — was rejected because
the Map sheet and the coordinator would each need an instance, and keeping two
instances in sync through `UserDefaults` is more moving parts than the property
it replaces.

`MapViewController` is the composition root. It observes a new
`.rentalRangeFilterDidChange` notification and forwards to the coordinator,
exactly as it already handles `.mapLayerEnabledStateDidChange`:

```swift
rentalLayerCoordinator?.setRangeFilter(mapRegionManager.rentalRangeFilter)
```

`RentalLayerCoordinator` is seeded with the persisted value at construction, so
a filter set in a previous session applies to the first fetch rather than
arriving one notification late.

### Map sheet row

A `Picker` with an explicit `.pickerStyle(.menu)` appended to the "Other ways to
get around" section, below the Bikes and Scooters rows. The style is stated
explicitly rather than left to `.automatic`, which Apple documents as "based on
the picker's context" — in a `List` that has resolved to a navigation link in some
OS versions and a menu in others. It appears whenever at least one rental layer row
is visible — deliberately *not* gated on those layers being enabled, so the row
doesn't jump in and out of the sheet as the rider toggles them, and so the
filter can be set before turning a layer on.

New strings:

- `map_sheet.minimum_range` — "Minimum range"
- `map_sheet.minimum_range_any` — "Any"

### Fuel label

`RentalFormat` moves out of `RentalDetailViewController.swift` into its own
`RentalFormat.swift`. It is shared formatting logic that was never
detail-sheet-specific, and this change adds a third consumer. It gains:

```swift
/// Battery percent when the feed provides it, else remaining range, else nil.
static func fuelLabelText(for rental: VehicleRental) -> String?
```

Percent is clamped to 0...1 before formatting — a feed can report 1.2 — and
reuses the existing `batteryText(_:)`. Stations return nil: they have no fuel of
their own.

The range fallback needs its **own** `MKDistanceFormatter` with
`unitStyle = .abbreviated`. The existing shared `RentalFormat.distanceFormatter`
uses the default style, which spells the unit out — verified: 5,470 m renders as
`"3.4 miles"` under `en_US`, where `.abbreviated` gives `"3.4 mi"`. Only the
abbreviated form is short enough to sit under a map pin. The detail sheet's
existing spelled-out rendering is deliberate and stays as it is, so the two
surfaces need two formatters rather than one mutated in place.

`RentalAnnotation` gains `showsFuelLabel: Bool`, defaulting to false.

#### Why not MapKit's built-in text

`MKMarkerAnnotationView` already has `titleVisibility` and `subtitleVisibility`,
documented as "the visibility of the title text rendered beneath the marker
balloon", with `MKFeatureVisibility.adaptive` letting MapKit place the text
according to current map state — collision-aware, which a custom subview is not.
It was considered and rejected:

- The text can only come from the annotation's `title` or `subtitle`. `title` is
  the rider-facing display label ("Lime e-bike"), used by the callout and by
  VoiceOver; `subtitle` is station availability. Putting "62%" in either means
  giving up the thing that's there now.
- `subtitleVisibility`'s documentation says "MapKit shows the text when the user
  selects a marker" — selection-driven, not the always-on glance the mockup
  wants.
- Styling is not exposed: the built-in text is Maps-app styled, not bold purple.

So the custom label stands, with the collision caveat below accepted knowingly
rather than by omission.

#### The label

`RentalAnnotationView` gains a `UILabel`:

- pinned `centerXAnchor` to the view's `centerXAnchor`, `topAnchor` to the
  view's `bottomAnchor` + 1, with `clipsToBounds = false`
- bold `.caption1` via a symbolic trait, so Dynamic Type applies
- `.rentalPurple` when operative, `.systemGray` when not, matching
  `markerTintColor`
- a white shadow, so the text stays legible over satellite basemaps
- hidden when the text is nil or `showsFuelLabel` is false
- cleared in `prepareForReuse()`, alongside the existing reuse resets —
  `MKAnnotationView`'s default implementation is documented as doing nothing, so
  every piece of subclass state must be reset by hand or it leaks across reuse

**The zoom gate lives on the annotation, not the view.**
`RentalMapLayer.annotationView(for:)` only dequeues a view and has no access to
viewport state. So `RentalLayerCoordinator` sets `showsFuelLabel` on its
annotations from the `mapRect` it already receives in `viewportDidChange`, and
re-assigns `view.annotation` to re-run `configure()` — the same mechanism the
existing update path uses to refresh glyphs without disturbing selection. New
annotations are created with the current value, so they render correctly on
first appearance.

Re-assigning `annotation` is not a *documented* reconfigure hook; it works
because the subclass observes it with `didSet`. It is retained here only because
the existing update path already relies on it and a second mechanism for the same
job would be worse than one unofficial one. `prepareForDisplay()` is the
documented pre-display hook and is the fallback if the re-assignment turns out to
disturb selection or clustering.

The threshold is **8,000 map points**, against the layer's own `zoomWindow` of
20,000. These are `MKMapRect` units, not meters. Confirmed against
`MKMapPointsPerMeterAtLatitude`: at latitude 47.6 there are 9.9464 map points per
metre, so 20,000 map points is a **2,011 m**-tall viewport and 8,000 is
**804 m** — a few blocks, where markers are far enough apart for labels to read.
The exact number is a starting estimate and should be checked against a real
dense fleet on device.

**The geometry has to be measured, not assumed.** Apple documents neither what
occupies `MKMarkerAnnotationView.bounds` (balloon only, balloon plus tip, or
balloon plus shadow) nor its default `centerOffset`; `MKAnnotationView` only
states that the map places the view's *center* at the annotation's coordinate
unless `centerOffset` says otherwise. So "top pinned to `bottomAnchor` + 1"
is an intent, not a guarantee — the first implementation step is to log the
view's `bounds` and `centerOffset` after layout and set the constant from that.
Budget for a gap or an overlap needing correction.

The label is a plain subview, so it does not participate in MapKit's marker
collision logic: `collisionMode` interprets a collision frame derived from the
view's own frame, and a subview drawn outside `bounds` is invisible to it. Some
overlap in an unusually dense block is accepted rather than solved. The
alternative — growing the view's frame to enclose the label and compensating
with `centerOffset` so decluttering accounts for it — means fighting
`MKMarkerAnnotationView`'s internally managed balloon layout, and is out of scope
unless overlap proves bad in practice.

Cluster annotations never get a label — a cluster has no single fuel value.

**VoiceOver ignores the density gate.** The view's `accessibilityLabel`
incorporates the fuel text even when the visual label is hidden by zoom: a
visual-clutter rule should not cost a VoiceOver user information. The label
itself is `isAccessibilityElement = false` so it isn't announced twice.

Apple documents no default VoiceOver derivation for `MKAnnotationView` — a
documentation search turns up nothing on how (or whether) it builds a label from
the annotation's `title`/`subtitle`. What *is* documented, in "Supporting
VoiceOver in your app", is the general UIKit rule: `accessibilityLabel` is a
single property supplying the text VoiceOver reads, and duplicate announcements
come from *child* accessibility elements rather than from a set label being
appended to a derived one. So composing the full string ourselves and setting
`isAccessibilityElement = false` on the child label is the right shape.

The one residual unknown is narrow: whether `MKAnnotationView` is an
accessibility element at all by default, and whether MapKit synthesizes anything
around it. Confirm with VoiceOver on device, focusing a rental pin and checking
that exactly one announcement is heard containing both the vehicle name and the
fuel figure.

### Analytics

One event when the threshold changes, reported from the same place the filter is
persisted, alongside the existing `AnalyticsLabels.mapLayerToggled`. The value is
the chosen threshold in meters.

## Testing

The rental layer currently has no test coverage at all, so this is greenfield.
The architecture above is shaped to put nearly all of the logic in types that
need neither a map view nor an async pipeline to exercise.

Swift Testing throughout, `.serialized` suites, per the conventions in
`CLAUDE.md`.

**Isolation must come from the fixtures, not from the schedule.** Swift Testing's
own documentation states that tests "run in parallel with respect to each other
using task groups, generally within the same process," with `.serialized`
serializing only *within* a suite; global parallelization is off only under
`--no-parallel` or `SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH=1`. The
`parallelizable: false` on the `OBAKitTests` scheme target governs XCTest's
multi-process parallel testing, and nothing in the documentation establishes that
it disables Swift Testing's in-process task-group parallelism. So the plan does
not rely on it.

Concretely, the `MapRegionManager` persistence suite must never touch
`UserDefaults.standard`. It inherits `OBATestCase`, whose
`userDefaultsSuiteName` is already `"OBAKitTests.\(UUID().uuidString)"` — a
per-instance scratch domain, torn down in `deinit`. That gives real isolation
regardless of what runs concurrently, which is the only kind worth having.

Suites that construct UIKit views (`RentalAnnotationViewTests`) or touch
`RentalLayerCoordinator` are `@MainActor`. This is not merely a UIKit
requirement: OBAKit builds with main-actor default isolation, so
`RentalVisibility` and `RentalRangeFilter` are themselves implicitly main-actor
isolated and unreachable from a `nonisolated` test context.

| Suite | Covers |
| --- | --- |
| `RentalRangeFilterTests` | the allow matrix: station, pedal bike, unknown range, below / exactly at / above threshold, and an inactive filter admitting everything |
| `RentalRangePresetTests` | both ladders, meters conversion, titles, nearest-rung selection for an off-ladder stored value |
| `RentalVisibilityTests` | snapshot add/remove/update diffs; raising the threshold hides; **lowering it restores from cache with no refetch**; updates that cross the threshold in both directions; form-factor pruning; deterministic ordering |
| `RentalFormatTests` | percent rounding and out-of-range clamping, range fallback when percent is nil, nil for stations and for vehicles with no fuel |
| `RentalAnnotationViewTests` | label text and hidden state per `showsFuelLabel`, gray when non-operative, accessibility label present while the visual label is hidden |
| `MapRegionManager` persistence | default is Any, round-trip through a scratch `UserDefaults`, `mapLayersDifferFromDefaults`, reset |

`RentalLayerCoordinator` ships without a suite of its own — but the original
justification for that was wrong, and is corrected here so the next maintainer
isn't misled by it.

The claim was that what remains is plumbing "behind a 250 ms debounce and an
`AsyncStream`." That describes the *snapshot* path only. The **filter** path is
fully synchronous and touches neither: sheet write → `MapRegionManager` setter →
synchronous notification → `MapViewController` observer → `setRangeFilter` →
`RentalVisibility.setFilter` → `apply(_ changes:)` → `MKMapView`. There is no
`await` anywhere in it. The debounce and the stream govern only how the cache
gets *seeded*.

So a coordinator test is far cheaper than implied: stub the one-method
`VehicleRentalService`, drop `private` from `apply(_ snapshot:)`, and drive the
whole thing synchronously in roughly 40 lines. Two things currently have **no
coverage at any level** and would be closed by it:

1. The invariant that `Set(annotations.keys)` equals `RentalVisibility`'s visible
   id set. It holds today only because `mapView` is never nil while the
   coordinator lives. Any future early return in `apply(_ changes:)` — "skip
   while a sheet is presented", "coalesce during a pan" — silently breaks cache
   restore, with the whole suite still green, because the bug would live in the
   translation layer rather than the value type.
2. `updateFuelLabelVisibility` and the `fuelLabelMaxVisibleHeight` constant. A
   wrong threshold or a flipped comparison means labels that never appear or
   always appear, and nothing fails: `RentalAnnotationViewTests` sets
   `showsFuelLabel` by hand, so the `MKMapRect` → gate mapping is unverified.

Filed as a follow-up rather than a blocker, since neither is a bug today.

`scripts/generate_project` must be re-run after adding each new source or test
file. XcodeGen picks files up from disk, and a test file the project doesn't know
about doesn't fail — it silently runs zero tests, which reads as passing.

Test fixtures need `VehicleRental` values with controlled `FuelInfo`. OTPKit's
own `TestFixtures` are not visible to this target, so a small local builder for
station / pedal bike / powered vehicle with a given range and percent goes in
the test helpers.

## Out of scope

- Server-side range filtering. The OTP `vehicleRentalsByBbox` query has no such
  parameter; this is a client-side display filter over data already fetched.
- Separate thresholds per layer. One shared value, per the request.
- Mirroring the filter into Settings. The Map sheet owns rental layer
  configuration.
- Filtering by operator, price, or vehicle type.
