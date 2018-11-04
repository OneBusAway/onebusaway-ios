//
//  StopArrivals.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 11/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class StopArrivals: NSObject, Decodable {
    public let arrivalsAndDepartures: [ArrivalDeparture]

    let nearbyStopIDs: [String]
    public let nearbyStops: [Stop]

    let situationIDs: [String]
    public let situations: [Situation]

    let stopID: String
    public let stop: Stop

    private enum CodingKeys: String, CodingKey {
        case arrivalsAndDepartures
        case nearbyStopIDs = "nearbyStopIds"
        case situationIDs = "situationIds"
        case stopID = "stopId"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let references = decoder.userInfo[CodingUserInfoKey.references] as! References

        arrivalsAndDepartures = try container.decode([ArrivalDeparture].self, forKey: .arrivalsAndDepartures)

        nearbyStopIDs = try container.decode([String].self, forKey: .nearbyStopIDs)
        nearbyStops = references.stopsWithIDs(nearbyStopIDs)

        situationIDs = try container.decode([String].self, forKey: .situationIDs)
        situations = references.situationsWithIDs(situationIDs)

        stopID = try container.decode(String.self, forKey: .stopID)
        stop = references.stopWithID(stopID)!
    }
}
