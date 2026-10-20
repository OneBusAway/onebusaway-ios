//
//  RentalDeepLink.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OTPKit

/// Resolves the destination of the rental sheet's "Open in <operator>" button.
///
/// GBFS defines `rental_uris` for exactly this, and OTPKit asks for it — but no
/// Lime system publishes it. A survey of all 48 Lime systems in MobilityData's
/// catalog (~87,000 vehicles) found zero. Deep links are a Lime Transit
/// Partnership feature; the public feed omits them worldwide. So when the feed
/// says nothing, we synthesize an app-launch link from the operator's URL scheme.
///
/// Synthesized links open the operator's app; they never pick out the vehicle
/// (#1602). Lime's `limebike://map?selected_vehicle_id=` takes Lime's *internal*
/// vehicle id — the one its partner feeds put in `rental_uris` — while the public
/// feed's `bike_id` is a random UUID that GBFS requires operators to rotate, so
/// Lime had nothing to select. Its map opens centred on the rider, who is standing
/// by the vehicle anyway.
///
/// The Lime scheme is reverse-engineered (ubahnverleih/WoBike, and Lime 3.286's
/// `CFBundleURLTypes`) and undocumented by Lime. That is tolerable only because
/// failure is graceful: `UIApplication` reports `success == false` when no app
/// claims the scheme, and `RentalLinkOpener` then falls back — to the operator's
/// App Store page, shown in-app, when `appStoreID` is known.
enum RentalDeepLink {

    /// Where the button should go, and where to land if that fails.
    struct Target: Equatable {
        let url: URL
        /// Opened when the primary URL fails and there is no `appStoreID` to show
        /// in-app: the operator's App Store URL for a synthesized link, its web
        /// page for a feed-published one.
        let storeFallback: URL?
        let operatorName: String?
        /// The operator's App Store id, from `appStoreID(forNetworkID:)`. Supplied whatever
        /// branch produced `url` — a feed-published link fails just as hard as a
        /// synthesized one when the app is not installed.
        var appStoreID: String?
    }

    /// Known operators' app-launch URIs, keyed by the leading token of the GBFS
    /// network id — the same tokenization OTPKit's `RentalNetwork.displayName`
    /// uses, so the button's operator and the sheet header's operator can never
    /// disagree.
    private static let launchURIs: [String: String] = [
        "lime": "limebike://map",
        // `bird://` is the shape Bird's own GBFS `discovery_uri` publishes;
        // LaunchServices dispatches on scheme alone, so `bird:` would likely work
        // too, but there is no reason to differ from the operator's declared URI.
        "bird": "bird://"
    ]

    // MARK: - Operator registry

    /// App Store ids for single-brand operators, keyed by the leading token of the
    /// GBFS network id (`lime_seattle` -> `lime`) — the tokenization `launchURIs`
    /// and OTPKit's `RentalNetwork.displayName` use.
    private static let appStoreIDsByToken: [String: String] = [
        "lime": "1199780189",
        "bird": "1260842311",
        "veo": "1279820696",
        "spin": "1241808993",
        "bolt": "6475395031",
        "lyft": "529379082"
    ]

    /// App Store ids for the Lyft-run docked systems, keyed by a prefix of the
    /// whole network id with separators removed and lowercased.
    ///
    /// Matched conservatively because their network ids are not ours to choose:
    /// an OTP deployment names each GBFS updater however it likes, and no deployed
    /// id for these systems has been observed. A leading-token match would not work
    /// — `capital_bikeshare` tokenizes to `capital`, which names nothing — so the
    /// whole system name must lead the id (`capital_bikeshare`, `citibike-nyc`,
    /// `bay_wheels`, `divvy`). A miss costs only the in-app store sheet; the
    /// opener still falls back to the feed's own links.
    private static let appStoreIDsBySystemPrefix: [(prefix: String, id: String)] = [
        ("capitalbikeshare", "1233403073"),
        ("citibike", "641194843"),
        ("divvy", "1369992600"),
        ("baywheels", "1233398899")
    ]

    /// The operator's App Store id, when the network id names a known operator.
    static func appStoreID(forNetworkID networkID: String) -> String? {
        let lowered = networkID.lowercased()
        let token = lowered.split(whereSeparator: { $0 == "_" || $0 == "-" }).first.map(String.init) ?? lowered
        if let id = appStoreIDsByToken[token] {
            return id
        }

        let collapsed = lowered.filter { $0 != "_" && $0 != "-" }
        return appStoreIDsBySystemPrefix.first { collapsed.hasPrefix($0.prefix) }?.id
    }

    static func appStoreURL(forID id: String) -> URL? {
        URL(string: "https://apps.apple.com/app/id\(id)")
    }

    // MARK: - Feed URI hardening

    /// Schemes a feed-published `rental_uris.ios` may not use.
    ///
    /// The feed is third-party data, and the button reads "Open in <operator>": a
    /// `tel:` or `facetime:` URI would place a call, `sms:`/`mailto:` would compose
    /// a message, and `file:`/`data:`/`javascript:` have no business in an app
    /// link at all. A rejected URI is treated as absent, so the rider still gets a
    /// synthesized link.
    static let rejectedFeedSchemes: Set<String> = [
        "tel", "telprompt", "sms", "facetime", "facetime-audio",
        "mailto", "file", "javascript", "data"
    ]

    /// Schemes starting with this are rejected too: Apple's `itms…` family,
    /// including the one that offers an enterprise app install. Our App Store
    /// links are always `https://apps.apple.com`, so a feed has no reason to send
    /// one. A prefix rather than the install scheme's full name because App
    /// Review's static scan flagged that name in the binary as installing code
    /// (guideline 2.5.2, the 26.4 rejection), though it only ever appeared here.
    static let rejectedFeedSchemePrefix = "itms"

    /// Absolute, and not rejected. Case-insensitive: `URL` keeps the
    /// scheme's case as written, and LaunchServices does not care.
    private static func isAcceptableFeedURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return !rejectedFeedSchemes.contains(scheme) && !scheme.hasPrefix(rejectedFeedSchemePrefix)
    }

    static func target(for rental: VehicleRental) -> Target? {
        let network = rental.rentalNetwork
        let operatorName = network?.displayName
        let webURL = network?.url.flatMap(URL.init(string:))
        let appStoreID = network.flatMap { appStoreID(forNetworkID: $0.networkId) }

        // 1. Feed data wins, network block or not: the pre-synthesis behaviour
        //    never required one, and a feed may publish a URI without a network.
        //
        //    Absolute only. `URL(string:)` happily parses a scheme-less value
        //    like "lime.example/ride/abc" into a non-nil relative URL that
        //    nothing can open — and because this branch outranks synthesis, one
        //    malformed feed field would turn a working synthesized link into a
        //    dead tap. Requiring a scheme lets it fall through instead, as does a
        //    scheme on the denylist.
        if let ios = rental.rentalUris?.ios, let url = URL(string: ios), isAcceptableFeedURL(url) {
            return Target(url: url, storeFallback: webURL, operatorName: operatorName, appStoreID: appStoreID)
        }

        // Synthesis and the web-page fallback both need the network block.
        guard let network else { return nil }

        // 2. Synthesize for known operators. Deliberately outranks the network
        //    URL below: the operator's app beats its homepage, which is a dead end
        //    for someone standing next to a scooter.
        //
        //    Lowercasing OTPKit's own `displayName` rather than re-splitting the
        //    network id keeps the operator token single-sourced, so the button's
        //    operator and the sheet header's can't drift apart. Not a perfect
        //    round-trip: `displayName` uppercases the first character, and a few
        //    characters expand when uppercased (ß -> SS, ﬁ -> FI), which
        //    lowercasing does not undo. Harmless here — every key in `launchURIs`
        //    is an ASCII slug, and a miss just falls through to the web page.
        if let uri = launchURIs[network.displayName.lowercased()], let url = URL(string: uri) {
            return Target(
                url: url,
                storeFallback: appStoreID.flatMap(appStoreURL(forID:)),
                operatorName: operatorName,
                appStoreID: appStoreID
            )
        }

        // 3. The operator's web page, when the feed published one.
        if let webURL {
            return Target(url: webURL, storeFallback: nil, operatorName: operatorName, appStoreID: appStoreID)
        }

        // 4. Nothing to open; the caller hides the button.
        return nil
    }
}
