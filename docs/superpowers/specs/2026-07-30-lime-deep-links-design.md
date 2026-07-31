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

### Risks we are accepting

- **Scheme rot.** If Lime renames or drops `limebike://`, a rider who *has* Lime
  installed gets bounced to the App Store page of an app they already own. This
  is the most likely real-world failure and it is not detectable client-side —
  `open` reports false either way. Analytics (below) is the only early warning.
- **Scheme squatting.** Any app may register `limebike://`. `open` would report
  success into the wrong app. Not mitigable; `canOpenURL` would not help.
- **App Store URL form.** `https://apps.apple.com/app/id<id>` is the standard
  form Apple's own marketing tools emit, but the current Apple documentation
  attesting it is archived (QA1633 still shows `itunes.apple.com`). Manual
  verification step 4 is what actually confirms it.

## Decisions

| Question | Decision |
| --- | --- |
| Where the logic lives | OBAKit only — OTPKit stays spec-pure |
| App not installed | Never gate on it; fall back to the App Store |
| Operator coverage | Small table, seeded with Lime and Bird |
| Feed vs. synthesized | Feed `rentalUris` wins; synthesis outranks `rentalNetwork.url` |
| Stations | App-level link; never vehicle-targeted |
| URL construction | `URLComponents`, never `String(format:)` |
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

    /// A known operator's app-launch surface, expressed as URL *components*
    /// rather than a format string — see "Vehicle ID extraction" for why.
    private struct Operator {
        let scheme: String
        /// Host of the vehicle-targeting URL. Nil when the app cannot target an
        /// individual vehicle, in which case only `appHost` is ever used.
        let vehicleHost: String?
        /// Query key carrying the vehicle ID, e.g. `selected_vehicle_id`.
        let vehicleIDKey: String?
        /// Host for the plain app-launch URL: stations, untargetable operators.
        let appHost: String?
        let appStoreID: String
    }

    private static let operators: [String: Operator] = [
        "lime": Operator(
            scheme: "limebike",
            vehicleHost: "map",
            vehicleIDKey: "selected_vehicle_id",
            appHost: "map",
            appStoreID: "1199780189"
        ),
        "bird": Operator(
            scheme: "bird",
            vehicleHost: nil,
            vehicleIDKey: nil,
            appHost: nil,
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

   This branch must not require a `rentalNetwork` block. `rentalNetwork` and
   `rentalUris` are independently optional, the pre-synthesis code never
   required one, and a feed could publish a URI without a network. Only steps 2
   and 3 need the network — step 2 to identify the operator, step 3 for the URL
   itself. A guard placed above step 1 would silently hide the button for
   exactly the feeds this branch exists to serve.
2. **Synthesized, when the network is in the table.** A `.vehicle` whose
   operator has a `vehicleHost` gets the targeted URL; a `.station`, or an
   operator like Bird that cannot target, gets the bare `scheme://appHost`.
   Fallback is `https://apps.apple.com/app/id<appStoreID>`.
3. **`rentalNetwork.url`, when present.** Today's second branch, unchanged.
4. **Otherwise nil** — the button does not render, exactly as now.

**Step 2 deliberately outranks step 3.** For a table operator that publishes
`rentalNetwork.url` but no `rentalUris` — no Lime system does today, but a feed
update could — the synthesized app link wins and the published web URL is never
used. This is a real narrowing of "feed data always wins," and it is
intentional: `rentalNetwork.url` is an operator *homepage*, and a marketing page
is a dead end for someone standing next to a scooter, which is the same
reasoning behind choosing the App Store over `li.me` as the fallback. A targeted
app link serves the rider better than a generic web page.

The consequence to accept: if a feed ever starts publishing a genuinely useful
`rentalNetwork.url`, this ordering hides it, and reversing the decision means
editing this file. A test pins the ordering so the choice can never drift
silently.

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

An ID with no colon is used whole. An ID that is *empty* after stripping (a bare
`lime_seattle:`) is treated as untargetable: fall through to the app-launch URL
rather than emitting `selected_vehicle_id=` with no value.

**Build the URL with `URLComponents` and `URLQueryItem`, never `String(format:)`.**
This is load-bearing, not style. The obvious encoding call,
`addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)`, does *not*
make a string safe as a query **value**: `urlQueryAllowed` is the set legal in
the whole query component, so `&`, `=`, `?`, `/`, and `+` all survive unescaped.
An ID containing `&` or `=` would inject or corrupt parameters, and `+` may be
read as a space by the receiver. `URLComponents` escapes those correctly inside
a value. Compounding it, on iOS 17+ `URL(string:)` silently percent-encodes
invalid characters instead of returning nil, so a malformed construction yields
a plausible-looking wrong URL rather than a visible failure.

That is why the operator table above holds `scheme`/`host`/`key` components
rather than a format string: the type makes the unsafe construction
unexpressible.

`generated_at` is included because the documented format carries it, and
omitting it risks Lime ignoring the query string. **The unit is a guess.** The
cited WoBike source documents an untyped `<timestamp>` placeholder; epoch
seconds is our inference, not attested. Emit it as `String(Int(now.timeIntervalSince1970))` —
using `%d` with `String(format:)` would additionally be a 32-bit specifier,
correct for epoch seconds only until 2038 and silently wrong for milliseconds.

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

`rentalUris.web` stays unconsulted. The model carries it
(`VehicleRentalSupportingTypes.swift:40-44`) and `deepLinkURL` has never read
it; this change does not alter that. Recorded so the omission reads as a
decision rather than an oversight.

### Analytics

`rentalLayer(planTripUsing:)` reports an event
(`MapViewController+MapLayers.swift:200`); `rentalLayer(open:webFallback:)`
reports nothing. Add two: the tap, and the fallback firing. For a
reverse-engineered scheme these counts are the only field signal that Lime
changed something — a fallback rate that jumps from near-zero to near-total is
exactly the scheme-rot alarm the risk register has no other way to raise.

## Testing

New `OBAKitTests/Mapping/RentalDeepLinkTests.swift`:

| Case | Expectation |
| --- | --- |
| Lime vehicle, null `rentalUris` | `limebike://map?selected_vehicle_id=<uuid>&generated_at=<ts>`, App Store fallback `id1199780189` |
| Feed publishes `rentalUris.ios` | Feed URI wins; synthesis is not consulted |
| Feed publishes `rentalUris.ios` **and** `rentalNetwork.url` | Fallback is the web URL, not the App Store — branch 1's fallback is preserved |
| Bird vehicle | `bird://`, store ID `1260842311`, no `selected_vehicle_id` |
| Lime station | App-level `limebike://map` — never a station ID in `selected_vehicle_id` |
| `vehicleId` with no colon | Whole string used as the ID |
| `vehicleId` of `"lime_seattle:"` | Empty after stripping ⇒ app-launch URL, no empty `selected_vehicle_id=` |
| ID containing `&`, `=`, a space, non-ASCII | Escaped inside the value; round-trips through `URLComponents(url:)` to the original ID |
| Lime vehicle **with** `rentalNetwork.url` | Synthesis still wins — pins the deliberate step-2-over-step-3 ordering |
| Vehicle with no `rentalNetwork` at all | Returns nil; no crash, no host-derived title |
| Feed publishes `rentalUris.ios` but there is no `rentalNetwork` | Still resolves to the feed URI — the network block is not required for branch 1 |
| Unknown network with `rentalNetwork.url` | Falls through to the web URL |
| Unknown network, no URL | Returns nil |
| Fixed `now` | Timestamp renders deterministically |

`RentalFixtures` needs three additions to `vehicle(...)`, which currently
hardcodes `"rentalNetwork": ["networkId": "lime_seattle", "url": NSNull()]` and
`"rentalUris": NSNull()` (`RentalFixtures.swift:57-58`): `networkId`,
`networkURL`, and `rentalUris` all become parameters defaulting to today's
values. `networkId` must accept nil to express "no rentalNetwork at all".
`station(...)` gains `networkId:`. Existing call sites are unaffected.

### Manual verification, before merge

The unit tests prove we construct the URL we intend. They cannot prove Lime
honors it. Required on a real device:

1. Install Lime alongside the OBA build.
2. Open a Lime vehicle sheet, tap "Open in Lime".
3. Confirm Lime opens **and focuses that specific vehicle** — not a generic map.
4. Delete Lime, repeat, confirm the App Store fallback fires.
5. Record the findings in the PR.

If step 3 opens Lime but lands on a generic map, do **not** immediately conclude
the parameter is useless. Because the `generated_at` unit is a guess, a stale
timestamp could make Lime discard the targeting — indistinguishable from the
parameter being unsupported. Before dropping to the app-launch URL, retry with
(a) milliseconds and (b) `generated_at` omitted entirely. Only if all three fail
does the vehicle-targeting come out.

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
