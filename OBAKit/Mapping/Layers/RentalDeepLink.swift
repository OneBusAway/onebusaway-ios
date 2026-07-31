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
/// says nothing, we synthesize the link from the operator's URL scheme and the
/// vehicle's own id.
///
/// The Lime scheme is reverse-engineered (ubahnverleih/WoBike) and undocumented
/// by Lime. That is tolerable only because failure is graceful: `UIApplication`
/// reports `success == false` when no app claims the scheme, and the caller then
/// opens `storeFallback`.
enum RentalDeepLink {

    /// Where the button should go, and where to land if that fails.
    struct Target: Equatable {
        let url: URL
        let storeFallback: URL?
        let operatorName: String?
    }

    /// A known operator's app-launch surface, expressed as URL *components*.
    ///
    /// Deliberately not a format string: `String(format:)` would bypass
    /// percent-encoding, and `.urlQueryAllowed` does not escape `&` or `=`
    /// inside a query value. Holding components makes the unsafe construction
    /// unexpressible.
    private struct Operator {
        let scheme: String
        /// Host of the vehicle-targeting URL. Nil when the app cannot target an
        /// individual vehicle, in which case only `appHost` is ever used.
        let vehicleHost: String?
        /// Query key carrying the vehicle id.
        let vehicleIDKey: String?
        /// Host for the plain app-launch URL: stations, untargetable operators.
        /// Empty string for an operator whose launch URI carries no host, so the
        /// URL keeps its `//` (`bird://`) rather than collapsing to `bird:`.
        let appHost: String?
        let appStoreID: String
    }

    /// Keyed by the leading token of the GBFS network id — the same tokenization
    /// OTPKit's `RentalNetwork.displayName` uses, so the button's operator and
    /// the sheet header's operator can never disagree.
    private static let operators: [String: Operator] = [
        "lime": Operator(
            scheme: "limebike",
            vehicleHost: "map",
            vehicleIDKey: "selected_vehicle_id",
            appHost: "map",
            appStoreID: "1199780189"
        ),
        // Bird cannot target an individual vehicle, so it only ever gets the
        // app-launch form. `bird://` is the shape Bird's own GBFS
        // `discovery_uri` publishes; LaunchServices dispatches on scheme alone,
        // so `bird:` would likely work too, but there is no reason to differ
        // from the operator's declared URI.
        "bird": Operator(
            scheme: "bird",
            vehicleHost: nil,
            vehicleIDKey: nil,
            appHost: "",
            appStoreID: "1260842311"
        )
    ]

    /// - Parameter now: injected so `generated_at` is deterministic in tests.
    static func target(for rental: VehicleRental, now: Date = Date()) -> Target? {
        let network = rental.rentalNetwork
        let operatorName = network?.displayName
        let webURL = network?.url.flatMap(URL.init(string:))

        // 1. Feed data wins, network block or not: the pre-synthesis behaviour
        //    never required one, and a feed may publish a URI without a network.
        //
        //    Absolute only. `URL(string:)` happily parses a scheme-less value
        //    like "lime.example/ride/abc" into a non-nil relative URL that
        //    nothing can open — and because this branch outranks synthesis, one
        //    malformed feed field would turn a working synthesized link into a
        //    dead tap. Requiring a scheme lets it fall through instead.
        if let ios = rental.rentalUris?.ios, let url = URL(string: ios), url.scheme != nil {
            return Target(url: url, storeFallback: webURL, operatorName: operatorName)
        }

        // Synthesis and the web-page fallback both need the network block.
        guard let network else { return nil }

        // 2. Synthesize for known operators. Deliberately outranks the network
        //    URL below: a targeted app link beats an operator homepage, which is
        //    a dead end for someone standing next to a scooter.
        if let synthesized = synthesize(for: rental, network: network, operatorName: operatorName, now: now) {
            return synthesized
        }

        // 3. The operator's web page, when the feed published one.
        if let webURL {
            return Target(url: webURL, storeFallback: nil, operatorName: operatorName)
        }

        // 4. Nothing to open; the caller hides the button.
        return nil
    }

    // MARK: - Synthesis

    private static func synthesize(
        for rental: VehicleRental,
        network: RentalNetwork,
        operatorName: String?,
        now: Date
    ) -> Target? {
        // Lowercasing OTPKit's own `displayName` rather than re-splitting the
        // network id keeps the operator token single-sourced, so the button's
        // operator and the sheet header's can't drift apart.
        //
        // Not a perfect round-trip: `displayName` uppercases the first character,
        // and a few characters expand when uppercased (ß -> SS, ﬁ -> FI), which
        // lowercasing does not undo. Harmless here — every key in `operators` is
        // an ASCII slug, and a miss just falls through to the web-page branch.
        guard let op = operators[network.displayName.lowercased()] else { return nil }

        var components = URLComponents()
        components.scheme = op.scheme

        // Stations carry a station id, never a vehicle id, so they only ever
        // get the app-launch form.
        if case .vehicle(let vehicle) = rental,
           let host = op.vehicleHost,
           let key = op.vehicleIDKey,
           let id = rawVehicleID(vehicle.vehicleId) {
            components.host = host
            components.queryItems = [
                URLQueryItem(name: key, value: id),
                // Epoch seconds is an inference: the documented format carries an
                // untyped <timestamp>. Built as a string because "%d" via
                // String(format:) is a 32-bit specifier.
                //
                // `generated_at` is Lime's, not a general rule. Bird never reaches
                // here (no `vehicleHost`), so a shared line is honest today — but a
                // third vehicle-targeting operator with different query quirks
                // should move this onto `Operator` rather than branch on scheme.
                URLQueryItem(name: "generated_at", value: String(Int(now.timeIntervalSince1970)))
            ]
        } else {
            components.host = op.appHost
        }

        guard let url = components.url else { return nil }
        return Target(
            url: url,
            storeFallback: URL(string: "https://apps.apple.com/app/id\(op.appStoreID)"),
            operatorName: operatorName
        )
    }

    /// OTP returns `network:id`. Strip through the first colon to recover the raw
    /// GBFS `bike_id`. Nil when nothing usable remains, so the caller drops to the
    /// app-launch form rather than emitting an empty parameter.
    private static func rawVehicleID(_ vehicleId: String) -> String? {
        let raw = vehicleId.firstIndex(of: ":").map { String(vehicleId[vehicleId.index(after: $0)...]) } ?? vehicleId
        return raw.isEmpty ? nil : raw
    }
}
