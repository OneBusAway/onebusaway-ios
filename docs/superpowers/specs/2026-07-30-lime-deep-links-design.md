# Synthesized Rental Deep Links

The rental detail sheet already has an "Open in %@" button. It has never once
rendered, because the only thing that can populate it — GBFS `rental_uris` —
is absent from every feed we consume.

This spec adds a fallback: when the feed publishes no deep link, synthesize one
from the operator's known URL scheme and the vehicle's ID.

## Why the button never appears

Verified 2026-07-30 against live feeds:

- Surveyed **all 48 Lime systems** in MobilityData's `systems.csv` (41 fetched
  successfully, ~87,000 vehicles across Seattle, Paris, Chicago, Tel Aviv, DC,
  and 36 more). **Zero** publish `rental_uris` on any vehicle. **Zero** publish
  `rental_apps` in `system_information`.
- This is not OTP dropping data and not OTPKit failing to request it. OTPKit's
  query already asks for `rentalUris { ios android web }`; the upstream feed has
  nothing to give.
- Deep links are a Lime **Transit Partnership Program** feature. The public
  `data.lime.bike` tier omits them worldwide.
- `rentalNetwork.url` — the existing second-choice fallback — is also null for
  `lime_seattle`, so branch two of `deepLinkURL` is dead as well.

Bird is a partial exception worth recording: it publishes `rental_apps` with
`ios.discovery_uri: "bird://"` and a store URI. But OTP's schema has no
`rental_apps` field at all (`VehicleRentalNetwork` exposes only `networkId` and
`url`), so it is discarded before it reaches the app. Bird's scheme is
app-level regardless — it cannot target an individual vehicle.

## What we know about the schemes

| Fact | Value | Source |
| --- | --- | --- |
| Lime scheme | `limebike://map?selected_vehicle_id=<uuid>&generated_at=<ts>` | [ubahnverleih/WoBike](https://github.com/ubahnverleih/WoBike/blob/master/Lime.md) — reverse-engineered, **not** official |
| Lime bundle / App Store ID | `com.limebike` / `1199780189` | iTunes lookup API |
| Lime universal links | `limebike.app.link`, AASA registered to `5NK4W853JQ.com.limebike` | fetched AASA directly |
| Bird scheme | `bird://` (app-level only) | Bird GBFS `system_information.rental_apps` |
| Bird App Store ID | `1260842311` | Bird GBFS `rental_apps.ios.store_uri` |

The Lime scheme is the weak link: community-documented, undocumented by Lime,
and liable to change without notice. Every decision below is shaped by that.

`limebike.app.link` is deliberately unused. Branch links are opaque and
generated server-side; we cannot mint a per-vehicle one without Lime's Branch
key, and a bare domain hit is an interstitial, not a deep link.

## Decisions

| Question | Decision |
| --- | --- |
| Where the logic lives | OBAKit only — OTPKit stays spec-pure |
| App not installed | Never gate on it; fall back to the App Store |
| Operator coverage | Small table, seeded with Lime and Bird |
| Feed vs. synthesized | Feed data always wins |
| Stations | App-level link; never vehicle-targeted |
| Before merge | Manual on-device verification |

### Why host-side and not OTPKit

OTPKit is consumed by other agencies. Baking an unofficial, reverse-engineered
scheme into a library means every host inherits our guess, and correcting it
requires a package tag plus a host bump in every downstream app. Host-side, a
broken scheme is fixed in an app release.

The cost is that another OTPKit host wanting the same feature reimplements it.
That is acceptable for one operator's undocumented scheme.

### Why always-show rather than `canOpenURL`

Gating on `canOpenURL` would need `limebike` in `LSApplicationQueriesSchemes`
and would hide the button from riders who do not have Lime — which is precisely
the population an App Store fallback serves. `application.open`'s completion
handler already distinguishes the two cases at zero cost and requires no
Info.plist declaration.

## Architecture

One new file, `OBAKit/Mapping/Layers/RentalDeepLink.swift`, sibling to
`RentalFormat.swift` and following the same shape: a plain enum of static
helpers that views call, with no MapKit, no UIKit, and no async — so it is
directly unit-testable.

```swift
enum RentalDeepLink {
    /// What the sheet should open, and where to land if that fails.
    struct Target: Equatable {
        let url: URL
        let storeFallback: URL?
        let operatorName: String?
    }

    /// A known operator's app-launch surface.
    private struct Operator {
        /// Format string taking the raw vehicle ID and a timestamp.
        /// Nil when the app cannot target an individual vehicle.
        let vehicleURLFormat: String?
        /// Plain app-launch URL, used for stations and untargetable operators.
        let appURL: String
        let appStoreID: String
    }

    private static let operators: [String: Operator] = [
        "lime": Operator(
            vehicleURLFormat: "limebike://map?selected_vehicle_id=%@&generated_at=%d",
            appURL: "limebike://map",
            appStoreID: "1199780189"
        ),
        "bird": Operator(
            vehicleURLFormat: nil,
            appURL: "bird://",
            appStoreID: "1260842311"
        )
    ]

    static func target(for rental: VehicleRental, now: Date = Date()) -> Target?
}
```

`now` is injected so tests are deterministic; production callers omit it.

### Resolution order

1. **`rentalUris.ios`, when present.** Feed data always beats a guess.
   Fallback stays `rentalNetwork.url`. This preserves today's behavior byte for
   byte on any feed that ever starts publishing deep links.
2. **Synthesized, when the network is in the table.** A `.vehicle` whose
   operator has a `vehicleURLFormat` gets the targeted URL; a `.station`, or an
   operator like Bird that cannot target, gets `appURL`. Fallback is
   `https://apps.apple.com/app/id<appStoreID>`.
3. **`rentalNetwork.url`, when present.** Today's second branch, unchanged.
4. **Otherwise nil** — the button does not render, exactly as now.

To be explicit about a distinction the decisions table compresses: whether the
rider has the app installed never affects whether the button appears. Whether
we can construct *any* URL for the operator does. An unknown network with no
`rentalNetwork.url` still yields no button.

`operatorName` is `rentalNetwork?.displayName`, falling back to the resolved
URL's host — the same derivation `deepLinkURL` uses today, so the button text
does not change for any feed that already produced one.

### Operator lookup

The table is keyed by the leading token of the GBFS network ID: split
`networkId` on `_` or `-`, take the first element, lowercase it. So
`lime_seattle` → `lime` and `bird-seattle-washington` → `bird`.

This is the same rule OTPKit already applies in `RentalNetwork.displayName`,
which is what renders "Lime" in the sheet header. Reusing it means the button's
operator and the header's operator can never disagree.

### Vehicle ID extraction

OTP returns `vehicleId` in the form `network:id` —
`lime_seattle:e0762983-6769-4191-903e-7a9e44444ea3`. Everything up to and
including the first `:` is stripped, leaving the raw GBFS `bike_id`. Verified:
the UUIDs OTP returns match `free_bike_status.bike_id` exactly.

An ID with no colon is used whole. The result is percent-encoded for the query
slot — UUIDs need no escaping, but the input is a third-party string and we
should not assume its shape.

`generated_at` is included as epoch seconds because the documented format
carries it. Its purpose is unknown; omitting it risks Lime ignoring the whole
query string, and including it costs nothing.

## Error handling

Nothing new is required. `MapViewController+MapLayers.swift:215` already does
the right thing:

```swift
application.open(url, options: [:]) { [weak self] success in
    guard !success else { return }
    Logger.info("Rental deep link failed to open: \(url)")
    if let webFallback { self?.application.open(webFallback, ...) }
}
```

No app claims `limebike://` ⇒ `success` is false ⇒ the App Store page opens. A
wrong scheme degrades to "Lime's App Store listing," never a crash or a dead
tap. That property is what makes shipping an unofficial scheme defensible.

## Call site

`RentalDetailView.deepLinkURL` collapses from its current two-branch body into
a call to `RentalDeepLink.target(for: rental)`, mapped onto the existing
`rental_detail.open_in_fmt` ("Open in %@") string. The button, its styling, and
`onOpenURL` are untouched.

The cluster list is untouched — its rows push to the detail sheet and have
never shown a deep-link button.

**No new localized strings.** `rental_detail.open_in_fmt` already covers both
operators via `rentalNetwork.displayName`.

## Testing

New `OBAKitTests/Mapping/RentalDeepLinkTests.swift`:

| Case | Expectation |
| --- | --- |
| Lime vehicle, null `rentalUris` | `limebike://map?selected_vehicle_id=<uuid>&generated_at=<ts>`, App Store fallback `id1199780189` |
| Feed publishes `rentalUris.ios` | Feed URI wins; synthesis is not consulted |
| Bird vehicle | `bird://`, store ID `1260842311`, no `selected_vehicle_id` |
| Lime station | App-level `limebike://map` — never a station ID in `selected_vehicle_id` |
| `vehicleId` with no colon | Whole string used as the ID |
| Unknown network with `rentalNetwork.url` | Falls through to the web URL |
| Unknown network, no URL | Returns nil |
| Fixed `now` | Timestamp renders deterministically |

`RentalFixtures` needs two additions: `vehicle(...)` currently hardcodes
`networkId: "lime_seattle"` and `rentalUris: NSNull()`, so both become
parameters with those values as defaults; `station(...)` gains `networkId:`.
Existing call sites are unaffected.

### Manual verification, before merge

The unit tests prove we construct the URL we intend. They cannot prove Lime
honors it. Required on a real device:

1. Install Lime alongside the OBA build.
2. Open a Lime vehicle sheet, tap "Open in Lime".
3. Confirm Lime opens **and focuses that specific vehicle** — not a generic map.
4. Delete Lime, repeat, confirm the App Store fallback fires.
5. Record the findings in the PR.

If step 3 opens Lime but lands on a generic map, the scheme works and the
parameter does not: keep the button, drop to `appURL`, and note it.

One assumption rides on this pass: that bare `limebike://map` — the station and
fallback form — launches the app at all. It is the documented path with its
query string removed, which is usually safe but is not attested anywhere. If it
fails, stations get no button rather than a broken one.

## Out of scope

- Any change to OTPKit.
- `canOpenURL` gating and the `LSApplicationQueriesSchemes` entry.
- Branch / universal-link handling.
- Pricing. Bird publishes `system_pricing_plans` and Lime publishes none;
  neither reaches us through OTP. Answering "what will this cost" means talking
  to GBFS directly, which is its own project.
- Pursuing a Lime Transit Partnership feed. Worth doing — it would make this
  entire spec obsolete — but it is a business conversation, not a code change.

## Base branch

`main`. It already contains the full rental stack including the range filter
(squash-merged, so the local `bikeshare-range-filter` branch shows 31 unmerged
commits despite the content having landed). `main` is ahead of that branch;
branch fresh from it.

Note that `Apps/Shared/app_shared.yml` carries an uncommitted local `path:`
override pointing at the OTPKit working copy. It must stay uncommitted.
