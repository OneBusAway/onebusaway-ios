//
//  StopArrivals.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MetaCodable

@Codable
public struct StopArrivals: Identifiable/*, HasReferences*/ {
    public var id: String {
        return self.stopID
    }

    /// Upcoming and just-passed vehicle arrivals and departures.
    public let arrivalsAndDepartures: [ArrivalDeparture]

    /// A list of nearby stop IDs.
    @CodedAt("nearbyStopIds")
    public let nearbyStopIDs: [StopID]

    /// A list of nearby `Stop`s.
//    public private(set) var nearbyStops = [Stop]()

    /// A list of active service alert IDs.
    @CodedAt("situationIds")
    public let situationIDs: [String]

    /// Active service alerts tied to the `StopArrivals` model.
//    private var _serviceAlerts = [ServiceAlert]()

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
    @CodedAt("stopId")
    public let stopID: StopID

    /// The stop to which this object refers.
//    public var stop: Stop!

//    public private(set) var regionIdentifier: Int?

//    public func loadReferences(_ references: References, regionIdentifier: Int?) {
//        nearbyStops = references.stopsWithIDs(nearbyStopIDs)
//        _serviceAlerts = references.serviceAlertsWithIDs(situationIDs)
//        stop = references.stopWithID(stopID)!
//        arrivalsAndDepartures.loadReferences(references, regionIdentifier: regionIdentifier)
//        self.regionIdentifier = regionIdentifier
//    }
}
