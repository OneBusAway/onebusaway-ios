//
//  NearbyStopEntityLoader.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import OBAKitCore

/// The stops nearest the rider, as stop entities, for visual intelligence:
/// a rider points the camera at a stop and the app offers the stops around
/// them (#1555). `StopVisualIntelligenceQuery` is the only caller.
///
/// Reads the app-group suite like `NextDeparturesLoader`, never `Application`:
/// the system can launch the app in the background just to run the query. It
/// sends the rider's location to the region's server, as the Nearby list does,
/// and nothing else.
nonisolated struct NearbyStopEntityLoader {
    /// How long the stops fetch may take. The camera waits on the answer.
    static let requestTimeout: TimeInterval = 10

    static let defaultDataLoader: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout
        return URLSession(configuration: configuration)
    }()

    let userDefaults: UserDefaults
    let bundledRegionsFilePath: String?
    let apiKey: String?
    let appVersion: String
    let dataLoader: URLDataLoader
    /// The rider's location, or nil when the app can't have it.
    let currentLocation: @Sendable () async -> CLLocation?

    init(
        userDefaults: UserDefaults,
        bundledRegionsFilePath: String?,
        apiKey: String?,
        appVersion: String,
        dataLoader: URLDataLoader = NearbyStopEntityLoader.defaultDataLoader,
        currentLocation: @escaping @Sendable () async -> CLLocation? = RiderLocation.current
    ) {
        self.userDefaults = userDefaults
        self.bundledRegionsFilePath = bundledRegionsFilePath
        self.apiKey = apiKey
        self.appVersion = appVersion
        self.dataLoader = dataLoader
        self.currentLocation = currentLocation
    }

    init?(bundle: Bundle) {
        guard let suite = bundle.appGroup,
              let defaults = UserDefaults(suiteName: suite) else { return nil }
        self.init(
            userDefaults: defaults,
            bundledRegionsFilePath: bundle.bundledRegionsFilePath,
            apiKey: bundle.restServerAPIKey,
            appVersion: bundle.appVersion
        )
    }

    /// The nearest stops, closest first, with the one whose code `recognizedText`
    /// shows moved to the top. Empty, never an error, when the camera isn't on a
    /// transit sign (see `TransitSignGate`), or without a region, a location or an
    /// answer from the server: the camera would show an error.
    ///
    /// The sign check comes first, so an unrelated search never asks for the
    /// rider's location or calls the server.
    func entities(labels: [String], recognizedText: [String]) async -> [StopEntity] {
        guard TransitSignGate.looksLikeTransitSign(labels: labels, recognizedText: recognizedText) else {
            Logger.info("Visual intelligence stops: not a transit sign; offering no stops.")
            return []
        }
        guard let region = ResolvedRegionStore(userDefaults: userDefaults).region(bundledRegionsFilePath: bundledRegionsFilePath) else {
            Logger.warn("Visual intelligence stops: no region selected; offering no stops.")
            return []
        }
        guard let apiKey else {
            Logger.error("Visual intelligence stops: no REST API key in Info.plist.")
            return []
        }
        guard let location = await currentLocation() else {
            Logger.warn("Visual intelligence stops: no location; offering no stops.")
            return []
        }

        let service = RESTAPIService.standalone(
            region: region,
            apiKey: apiKey,
            appVersion: appVersion,
            uuid: UserUUID.value(in: userDefaults),
            dataLoader: dataLoader
        )

        let stops: [Stop]
        do {
            stops = try await service.getStops(coordinate: location.coordinate).list
        } catch {
            Logger.error("Visual intelligence stops: nearby stops fetch failed: \(error)")
            return []
        }

        return NearbyStopRanking.rank(stops, from: location, recognizedText: recognizedText)
            .map { StopEntityMapping.entity(for: $0, regionID: region.regionIdentifier, includesImage: true) }
    }
}

/// Whether a visual intelligence search is of a transit sign, from what the
/// system labelled the image and the text read off it. Anything else gets no
/// stops, and no location or network request is made for it.
nonisolated enum TransitSignGate {
    /// Words on, or labels for, a stop sign or a station. Matched as whole
    /// words, ignoring case. Not "stop" or "route" alone: a traffic stop sign
    /// or a highway sign would match.
    static let transitWords: Set<String> = [
        "bus", "buses", "busstop", "station", "transit", "tram", "streetcar", "trolley",
        "train", "rail", "railway", "metro", "subway", "ferry"
    ]

    /// Stop codes are numbers, and stops' codes run from three digits (the
    /// shortest `NearbyStopRanking` matches) to about seven.
    static let stopCodeDigits = NearbyStopRanking.minimumCodeLength...8

    /// Words a sign puts between "Stop" and its code: "Stop #75403", "Stop ID 1121",
    /// "Stop No. 99610". ("#" and "." are dropped when the line is split.)
    static let stopCodeLeadIns: Set<String> = ["id", "no", "number"]

    static func looksLikeTransitSign(labels: [String], recognizedText: [String]) -> Bool {
        let labelWords = Set(labels.flatMap(words(in:)))
        if !labelWords.isDisjoint(with: transitWords) { return true }

        let lines = recognizedText.map(words(in:))
        return lines.contains { !Set($0).isDisjoint(with: transitWords) } || lines.contains(where: hasStopCode)
    }

    /// A number alone is on nearly anything with text (phone numbers, years,
    /// prices, street numbers), so it counts only right after "Stop".
    static func hasStopCode(_ line: [String]) -> Bool {
        for (index, word) in line.enumerated() where word == "stop" {
            let following = line.dropFirst(index + 1).drop { stopCodeLeadIns.contains($0) }
            if let code = following.first, isPlausibleStopCode(code) { return true }
        }
        return false
    }

    static func isPlausibleStopCode(_ word: String) -> Bool {
        stopCodeDigits.contains(word.count) && word.allSatisfy(\.isNumber)
    }

    /// One line's words, lowercased, in order.
    static func words(in line: String) -> [String] {
        line.split { !$0.isLetter && !$0.isNumber }.map { $0.lowercased() }
    }
}

/// How the camera's stops are ordered, as pure functions so they can be tested.
nonisolated enum NearbyStopRanking {
    /// At most this many stops. A rider pointing at a stop is standing near it.
    static let resultLimit = 10

    /// A stop code shorter than this isn't matched against the sign: the
    /// route numbers on the same sign would match it.
    static let minimumCodeLength = 3

    /// Closest first and capped, with the stop whose code the sign shows first,
    /// even if it is farther than the cap.
    static func rank(_ stops: [Stop], from location: CLLocation, recognizedText: [String], limit: Int = resultLimit) -> [Stop] {
        var ranked = stops.sorted { $0.location.distance(from: location) < $1.location.distance(from: location) }
        if let signed = stop(matching: recognizedText, in: ranked),
           let index = ranked.firstIndex(where: { $0.id == signed.id }) {
            ranked.remove(at: index)
            ranked.insert(signed, at: 0)
        }
        return Array(ranked.prefix(limit))
    }

    /// The first of `stops` whose code appears as a whole word in the text read
    /// off the sign, ignoring case. "Stop #99610" matches the code 99610.
    static func stop(matching recognizedText: [String], in stops: [Stop]) -> Stop? {
        let words = Set(recognizedText.flatMap { line in
            line.split { !$0.isLetter && !$0.isNumber }.map { $0.lowercased() }
        })
        guard !words.isEmpty else { return nil }
        return stops.first { stop in
            stop.code.count >= minimumCodeLength && words.contains(stop.code.lowercased())
        }
    }
}

/// The rider's location for a query the system runs, which may be in the
/// background with no map open: Core Location's last fix if it is recent,
/// otherwise the first new one, within a few seconds.
nonisolated enum RiderLocation {
    /// An older fix may be from another street.
    static let maximumAge: TimeInterval = 120

    /// The camera waits on the answer.
    static let timeout: Duration = .seconds(5)

    @Sendable static func current() async -> CLLocation? {
        let manager = CLLocationManager()
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            break
        default:
            return nil
        }
        if let last = manager.location, -last.timestamp.timeIntervalSinceNow < maximumAge {
            return last
        }

        return await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if let location = update.location { return location }
                    }
                } catch {
                    Logger.error("Visual intelligence stops: location updates failed: \(error)")
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
