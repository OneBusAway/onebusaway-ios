//
//  StopArrivals.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

public struct StopArrivals: Identifiable, Codable {
    public var id: String {
        return self.stopID
    }

    /// Upcoming and just-passed vehicle arrivals and departures.
    public let arrivalsAndDepartures: [ArrivalDeparture]

    /// A list of nearby stop IDs.
    public let nearbyStopIDs: [StopID]

    /// A list of active service alert IDs.
    public let situationIDs: [String]

    /// Returns this model's list of service alerts, if any exist. If this model does not have any, then it returns a flattened list of its `ArrivalDepartures` objects' service alerts.
//    public var serviceAlerts: [ServiceAlert] {
//        if _serviceAlerts.count > 0 {
//            return _serviceAlerts
//        }
//        else {
//            fatalError("\(#function) unimplemented.")
//            return arrivalsAndDepartures.flatMap { $0.serviceAlerts }
//        }
//    }

    /// The stop ID for the stop this represents.
    public let stopID: StopID

    enum CodingKeys: String, CodingKey {
        case arrivalsAndDepartures
        case nearbyStopIDs = "nearbyStopIds"
        case situationIDs = "situationIds"
        case stopID = "stopId"
    }
}
