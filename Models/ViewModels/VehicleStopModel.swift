//
//  VehicleStopModel.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/4/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import Foundation

/// Provides an abstraction to represent a vehicle arriving and departing from a stop, as seen at the end/beginning of a route.
public struct VehicleStopModel {
    public let vehicleID: String
    public var arrival: ArrivalDeparture?
    public var departure: ArrivalDeparture?

    public init(vehicleID: String) {
        self.vehicleID = vehicleID
    }

    public var isComplete: Bool {
        return arrival != nil && departure != nil
    }

    public var date: Date {
        if let departure = departure {
            return departure.arrivalDepartureDate
        }
        else if let arrival = arrival {
            return arrival.arrivalDepartureDate
        }
        else {
            // we should never hit this.
            return Date()
        }
    }
}

public extension Sequence where Element: ArrivalDeparture {

    /// Converts a Sequence of `ArrivalDeparture`s to `VehicleStopModel`s for display in a `StopViewController`.
    ///
    /// - Returns: An array of `VehicleStopModel`s generated from the contents of the receiver.
    func toVehicleStopModels() -> [VehicleStopModel] {
        var filledModels = [VehicleStopModel]()
        var inProgressModels = [String: VehicleStopModel]()

        for arrDep in self {
            let vehicleID = arrDep.vehicleID ?? NSUUID().uuidString
            var entry = inProgressModels[vehicleID, default: VehicleStopModel(vehicleID: vehicleID)]

            if entry.isComplete {
                inProgressModels[vehicleID] = nil
                filledModels.append(entry)
            }

            if arrDep.arrivalDepartureStatus == .arriving {
                entry.arrival = arrDep
            }
            else {
                entry.departure = arrDep
            }

            inProgressModels[vehicleID] = entry
        }

        let allModels = filledModels + inProgressModels.values
        return allModels.sorted { $0.date < $1.date }
    }
}
