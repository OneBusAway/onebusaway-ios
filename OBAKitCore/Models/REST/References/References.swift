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
    let situations: [SituationREST]
    public let stops: [Stop]
    public let trips: [Trip]

    static var regionIdentifierUserInfoKey: CodingUserInfoKey {
        return CodingUserInfoKey(rawValue: "regionIdentifier")!
    }

    // MARK: - Initialization

    private enum CodingKeys: String, CodingKey {
        case agencies, routes, stops, trips, situations
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Sort entries for binary search.

        let situations = try container.decodeIfPresent([SituationREST].self, forKey: .situations) ?? []
        self.situations = situations.sorted(by: \.id)

        let agencies = try container.decodeIfPresent([Agency].self, forKey: .agencies) ?? []
        self.agencies = agencies.sorted(by: \.id)

        let routes = try container.decodeIfPresent([Route].self, forKey: .routes) ?? []
        self.routes = routes.sorted(by: \.id)

        let stops = try container.decodeIfPresent([Stop].self, forKey: .stops) ?? []
        self.stops = stops.sorted(by: \.id)

        let trips = try container.decodeIfPresent([Trip].self, forKey: .trips) ?? []
        self.trips = trips.sorted(by: \.id)

        super.init()
    }
}

// MARK: - HasReferences

public protocol HasReferences {
    func loadReferences(_ references: References, regionIdentifier: Int?)
    var regionIdentifier: Int? { get }
}

extension Array: HasReferences where Element: HasReferences {
    public var regionIdentifier: Int? { first?.regionIdentifier }

    public func loadReferences(_ references: References, regionIdentifier: Int?) {
        for elt in self {
            elt.loadReferences(references, regionIdentifier: regionIdentifier)
        }
    }
}

// MARK: - Finders
extension References {

    // MARK: - Agencies

    public func agencyWithID(_ id: String?) -> Agency? {
        guard let id = id else { return nil }
        return agencies.binarySearch(sortedBy: \.id, element: id)?.element
    }

    // MARK: - Routes

    public func routeWithID(_ id: String?) -> Route? {
        guard let id = id else { return nil }
        return routes.binarySearch(sortedBy: \.id, element: id)?.element
    }

    public func routesWithIDs(_ ids: [String]) -> [Route] {
        return routes.filter { ids.contains($0.id) }
    }

    // MARK: - Stops

    public func stopWithID(_ id: String?) -> Stop? {
        guard let id = id else { return nil }
        return stops.binarySearch(sortedBy: \.id, element: id)?.element
    }

    public func stopsWithIDs(_ ids: [String]) -> [Stop] {
        return stops.filter { ids.contains($0.id) }
    }

    // MARK: - Trips

    public func tripWithID(_ id: String?) -> Trip? {
        guard let id = id else { return nil }
        return trips.binarySearch(sortedBy: \.id, element: id)?.element
    }
}
