//
//  References.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

public struct References: Decodable {
    public let agencies: [Agency]
    public let routes: [Route]
    let situations: [SituationREST]
    public let stops: [Stop]
    public let trips: [Trip]

    static var regionIdentifierUserInfoKey: CodingUserInfoKey {
        return CodingUserInfoKey(rawValue: "regionIdentifier")!
    }

    internal enum CodingKeys: String, CodingKey {
        case agencies, routes, stops, trips, situations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.situations = try container.decodeIfPresent([SituationREST].self, forKey: .situations) ?? []
        self.agencies = try container.decodeIfPresent([Agency].self, forKey: .agencies) ?? []
        self.routes = try container.decodeIfPresent([Route].self, forKey: .routes) ?? []
        self.stops = try container.decodeIfPresent([Stop].self, forKey: .stops) ?? []
        self.trips = try container.decodeIfPresent([Trip].self, forKey: .trips) ?? []
    }
}
