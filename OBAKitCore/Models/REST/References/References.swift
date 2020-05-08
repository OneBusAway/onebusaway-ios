//
//  References.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/20/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CocoaLumberjackSwift

public class References: NSObject, Decodable {
    public let agencies: [Agency]
    public let routes: [Route]
    public let situations: [Situation]
    public let stops: [Stop]
    public let trips: [Trip]

    // MARK: - Initialization

    private enum CodingKeys: String, CodingKey {
        case agencies, routes, situations, stops, trips
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        situations = try container.decodeIfPresent([Situation].self, forKey: .situations) ?? []
        agencies = try container.decodeIfPresent([Agency].self, forKey: .agencies) ?? []
        routes = try container.decodeIfPresent([Route].self, forKey: .routes) ?? []
        stops = try container.decodeIfPresent([Stop].self, forKey: .stops) ?? []
        trips = try container.decodeIfPresent([Trip].self, forKey: .trips) ?? []

        super.init()

        // depends: Agency, Route, Stop, Trip
        situations.loadReferences(self)

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

    // MARK: - Situations

    public func situationWithID(_ id: String?) -> Situation? {
        guard let id = id else {
            return nil
        }
        return situations.first { $0.id == id }
    }

    public func situationsWithIDs(_ ids: [String]) -> [Situation] {
        return situations.filter { ids.contains($0.id) }
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
