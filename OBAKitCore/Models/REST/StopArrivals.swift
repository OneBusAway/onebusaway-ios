//
//  StopArrivals.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class StopArrivals: NSObject, Decodable {

    /// Upcoming and just-passed vehicle arrivals and departures.
    public let arrivalsAndDepartures: [ArrivalDeparture]

    /// A list of nearby stop IDs.
    let nearbyStopIDs: [String]

    /// A list of nearby `Stop`s.
    public let nearbyStops: [Stop]

    /// A list of active service alert IDs.
    private let situationIDs: [String]

    /// Active service alerts tied to the `StopArrivals` model.
    private let _situations: [Situation]

    /// Returns this model's list of service alerts, if any exist. If this model does not have any, then it returns a flattened list of its `ArrivalDepartures` objects' service alerts.
    public var situations: [Situation] {
        if _situations.count > 0 {
            return _situations
        }
        else {
            return arrivalsAndDepartures.flatMap { $0.situations }
        }
    }

    /// The stop ID for the stop this represents.
    let stopID: String

    /// The stop to which this object refers.
    public let stop: Stop

    private enum CodingKeys: String, CodingKey {
        case arrivalsAndDepartures
        case nearbyStopIDs = "nearbyStopIds"
        case situationIDs = "situationIds"
        case stopID = "stopId"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let references = decoder.references

        arrivalsAndDepartures = try container.decode([ArrivalDeparture].self, forKey: .arrivalsAndDepartures)

        nearbyStopIDs = try container.decode([String].self, forKey: .nearbyStopIDs)
        nearbyStops = references.stopsWithIDs(nearbyStopIDs)

        situationIDs = try container.decode([String].self, forKey: .situationIDs)
        _situations = references.situationsWithIDs(situationIDs)

        stopID = try container.decode(String.self, forKey: .stopID)
        stop = references.stopWithID(stopID)!
    }
}
