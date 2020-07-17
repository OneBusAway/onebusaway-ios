//
//  StopArrivals.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

public class StopArrivals: NSObject, Decodable, HasReferences {

    /// Upcoming and just-passed vehicle arrivals and departures.
    public let arrivalsAndDepartures: [ArrivalDeparture]

    /// A list of nearby stop IDs.
    let nearbyStopIDs: [StopID]

    /// A list of nearby `Stop`s.
    public private(set) var nearbyStops = [Stop]()

    /// A list of active service alert IDs.
    private let situationIDs: [String]

    /// Active service alerts tied to the `StopArrivals` model.
    private var _serviceAlerts = [ServiceAlert]()

    /// Returns this model's list of service alerts, if any exist. If this model does not have any, then it returns a flattened list of its `ArrivalDepartures` objects' service alerts.
    public var serviceAlerts: [ServiceAlert] {
        if _serviceAlerts.count > 0 {
            return _serviceAlerts
        }
        else {
            return arrivalsAndDepartures.flatMap { $0.serviceAlerts }
        }
    }

    /// The stop ID for the stop this represents.
    let stopID: StopID

    /// The stop to which this object refers.
    public var stop: Stop!

    private enum CodingKeys: String, CodingKey {
        case arrivalsAndDepartures
        case nearbyStopIDs = "nearbyStopIds"
        case situationIDs = "situationIds"
        case stopID = "stopId"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        arrivalsAndDepartures = try container.decode([ArrivalDeparture].self, forKey: .arrivalsAndDepartures)
        nearbyStopIDs = try container.decode([StopID].self, forKey: .nearbyStopIDs)
        situationIDs = try container.decode([String].self, forKey: .situationIDs)
        stopID = try container.decode(StopID.self, forKey: .stopID)
    }

    public func loadReferences(_ references: References) {
        nearbyStops = references.stopsWithIDs(nearbyStopIDs)
        _serviceAlerts = references.serviceAlertsWithIDs(situationIDs)
        stop = references.stopWithID(stopID)!
        arrivalsAndDepartures.loadReferences(references)
    }
}
