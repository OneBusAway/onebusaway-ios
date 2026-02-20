//
//  CachedStop.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import GRDB

/// A lightweight database record representing a cached transit stop.
/// This is separate from the API `Stop` model — it only serves as a persistence layer.
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/62
struct CachedStop: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cachedStop"

    let id: String
    let regionId: Int
    let code: String
    let name: String
    let latitude: Double
    let longitude: Double
    let direction: String?
    let locationType: Int
    let wheelchairBoarding: String?
    let routeIDs: String
    let lastUpdated: Double

    /// Creates a cache record from an API `Stop` model.
    init(stop: Stop, regionId: Int) {
        self.id = stop.id
        self.regionId = regionId
        self.code = stop.code
        self.name = stop.name
        self.latitude = stop.location.coordinate.latitude
        self.longitude = stop.location.coordinate.longitude
        self.locationType = stop.locationType.rawValue
        self.wheelchairBoarding = stop.wheelchairBoarding.rawValue
        self.lastUpdated = Date().timeIntervalSince1970

        // Store direction as the raw string for round-trip fidelity.
        // The Stop model's _direction is private, so we convert back from the enum.
        self.direction = CachedStop.directionString(from: stop.direction)

        // Encode routeIDs as a JSON array string for simple storage without a junction table.
        do {
            let data = try JSONEncoder().encode(stop.routeIDs)
            self.routeIDs = String(data: data, encoding: .utf8) ?? "[]"
        } catch {
            Logger.error("Failed to encode routeIDs for stop \(stop.id): \(error)")
            self.routeIDs = "[]"
        }
    }

    /// Reconstructs an API `Stop` by decoding this record through Stop's Codable conformance.
    func toStop() -> Stop? {
        let decodedRouteIDs: [String]
        do {
            guard let data = routeIDs.data(using: .utf8) else {
                Logger.error("Failed to convert routeIDs string to data for stop \(id)")
                return nil
            }
            decodedRouteIDs = try JSONDecoder().decode([String].self, from: data)
        } catch {
            Logger.error("Failed to decode routeIDs for stop \(id): \(error)")
            return nil
        }

        // Build a dictionary matching Stop's CodingKeys, then decode through Stop's Codable init.
        // NOTE: We include an empty "routes" array so that Stop.routes (which is [Route]!)
        // decodes as [] instead of nil. Without this, any access to stop.routes,
        // stop.routeTypes, or stop.prioritizedRouteTypeForDisplay would crash
        // because routes is an implicitly unwrapped optional.
        let stopDict: [String: Any] = [
            "id": id,
            "code": code,
            "name": name,
            "lat": latitude,
            "lon": longitude,
            "direction": direction as Any,
            "locationType": locationType,
            "wheelchairBoarding": wheelchairBoarding as Any,
            "routeIds": decodedRouteIDs,
            "regionIdentifier": regionId,
            "routes": [] as [[String: Any]]
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: stopDict)
            let stop = try JSONDecoder().decode(Stop.self, from: data)
            return stop
        } catch {
            Logger.error("Failed to reconstruct Stop from cache for \(id): \(error)")
            return nil
        }
    }

    // MARK: - Direction Helpers

    private static func directionString(from direction: Direction) -> String? {
        switch direction {
        case .n: return "N"
        case .ne: return "NE"
        case .e: return "E"
        case .se: return "SE"
        case .s: return "S"
        case .sw: return "SW"
        case .w: return "W"
        case .nw: return "NW"
        case .unknown: return nil
        }
    }
}
