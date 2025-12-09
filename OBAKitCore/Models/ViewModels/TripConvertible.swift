//
//  TripConvertible.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Wraps `ArrivalDeparture`, `VehicleStatus`, and `TripDetails` to provide a uniform way to populate
/// user interfaces that display trip information, like the `TripViewController` in `OBAKit`.
public class TripConvertible: NSObject {
    public var arrivalDeparture: ArrivalDeparture?
    public var vehicleStatus: VehicleStatus?
    public var tripDetails: TripDetails?

    public init(arrivalDeparture: ArrivalDeparture) {
        self.arrivalDeparture = arrivalDeparture
    }

    public init?(vehicleStatus: VehicleStatus) {
        guard vehicleStatus.trip != nil else {
            return nil
        }
        self.vehicleStatus = vehicleStatus
    }

    public init(tripDetails: TripDetails) {
        self.tripDetails = tripDetails
    }

    public var vehicleID: String? {
        arrivalDeparture?.vehicleID ?? vehicleStatus?.vehicleID ?? tripDetails?.status?.vehicleID
    }

    public var tripStatus: TripStatus? {
        return arrivalDeparture?.tripStatus ?? vehicleStatus?.tripStatus ?? tripDetails?.status
    }

    public var trip: Trip {
        return arrivalDeparture?.trip ?? vehicleStatus?.trip ?? tripDetails!.trip
    }

    public var serviceDate: Date {
        return arrivalDeparture?.serviceDate ?? vehicleStatus?.tripStatus.serviceDate ?? tripDetails!.serviceDate
    }
}
