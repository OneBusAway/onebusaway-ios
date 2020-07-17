//
//  References.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

public class References: NSObject, Decodable {
    public let agencies: [Agency]
    public let routes: [Route]
    public let serviceAlerts: [ServiceAlert]
    public let stops: [Stop]
    public let trips: [Trip]

    // MARK: - Initialization

    private enum CodingKeys: String, CodingKey {
        case agencies, routes, stops, trips
        case alerts = "situations"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        serviceAlerts = try container.decodeIfPresent([ServiceAlert].self, forKey: .alerts) ?? []
        agencies = try container.decodeIfPresent([Agency].self, forKey: .agencies) ?? []
        routes = try container.decodeIfPresent([Route].self, forKey: .routes) ?? []
        stops = try container.decodeIfPresent([Stop].self, forKey: .stops) ?? []
        trips = try container.decodeIfPresent([Trip].self, forKey: .trips) ?? []

        super.init()

        // depends: Agency, Route, Stop, Trip
        serviceAlerts.loadReferences(self)

        // depends: Agency
        routes.loadReferences(self)

        // depends: Route
        stops.loadReferences(self)
        trips.loadReferences(self)
    }
}

// MARK: - HasReferences

public protocol HasReferences {
    func loadReferences(_ references: References)
}

extension Array: HasReferences where Element: HasReferences {
    public func loadReferences(_ references: References) {
        for elt in self {
            elt.loadReferences(references)
        }
    }
}

// MARK: - Finders
extension References {

    // MARK: - Agencies

    public func agencyWithID(_ id: String?) -> Agency? {
        guard let id = id else {
            return nil
        }
        return agencies.first { $0.id == id }
    }

    // MARK: - Routes

    public func routeWithID(_ id: String?) -> Route? {
        guard let id = id else {
            return nil
        }
        return routes.first { $0.id == id }
    }

    public func routesWithIDs(_ ids: [String]) -> [Route] {
        return routes.filter { ids.contains($0.id) }
    }

    // MARK: - Service Alerts

    public func alertWithID(_ id: String?) -> ServiceAlert? {
        guard let id = id else {
            return nil
        }
        return serviceAlerts.first { $0.id == id }
    }

    public func serviceAlertsWithIDs(_ ids: [String]) -> [ServiceAlert] {
        return serviceAlerts.filter { ids.contains($0.id) }
    }

    // MARK: - Stops

    public func stopWithID(_ id: String?) -> Stop? {
        guard let id = id else {
            return nil
        }
        return stops.first { $0.id == id }
    }

    public func stopsWithIDs(_ ids: [String]) -> [Stop] {
        return stops.filter { ids.contains($0.id) }
    }

    // MARK: - Trips

    public func tripWithID(_ id: String?) -> Trip? {
        guard let id = id else {
            return nil
        }
        return trips.first { $0.id == id }
    }
}
