//
//  TripConvertible.swift
//  OBAKitCore
//
//  Created by Aaron Brethorst on 12/26/19.
//

import Foundation

/// Wraps `ArrivalDeparture` and `VehicleStatus` to provide a uniform way to populate
/// user interfaces that display trip information, like the `TripViewController` in `OBAKit`.
public class TripConvertible: NSObject {
    public var arrivalDeparture: ArrivalDeparture?
    public var vehicleStatus: VehicleStatus?

    public init(arrivalDeparture: ArrivalDeparture) {
        self.arrivalDeparture = arrivalDeparture
    }

    public init?(vehicleStatus: VehicleStatus) {
        guard vehicleStatus.trip != nil else {
            return nil
        }
        self.vehicleStatus = vehicleStatus
    }

    public var vehicleID: String? {
        arrivalDeparture?.vehicleID ?? vehicleStatus?.vehicleID
    }

    public var tripStatus: TripStatus? {
        return arrivalDeparture?.tripStatus ?? vehicleStatus!.tripStatus
    }

    public var trip: Trip {
        return arrivalDeparture?.trip ?? vehicleStatus!.trip!
    }

    public var serviceDate: Date {
        return arrivalDeparture?.serviceDate ?? vehicleStatus!.tripStatus.serviceDate
    }
}
