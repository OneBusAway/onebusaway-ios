//
//  StopArrivals.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 11/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class StopArrivals: NSObject, Decodable, HasReferences {
    let arrivalsAndDepartures: [ArrivalDeparture]

    let nearbyStopIDs: [String]
    var nearbyStops = [Stop]()

    let situationIDs: [String]

    let stopID: String

    private enum CodingKeys: String, CodingKey {
        case arrivalsAndDepartures
        case nearbyStopIDs = "nearbyStopIds"
        case situationIDs = "situationIds"
        case stopID = "stopId"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        arrivalsAndDepartures = try container.decode([ArrivalDeparture].self, forKey: .arrivalsAndDepartures)
        nearbyStopIDs = try container.decode([String].self, forKey: .nearbyStopIDs)
        situationIDs = try container.decode([String].self, forKey: .situationIDs)
        stopID = try container.decode(String.self, forKey: .stopID)
    }

    func loadReferences(_ references: References) {
        nearbyStops = references.stops.filter { nearbyStopIDs.contains($0.id) }
        // abxoxo todo:
        // situationIDs
        // stopID
    }
}
