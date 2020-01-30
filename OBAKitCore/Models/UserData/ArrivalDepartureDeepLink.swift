//
//  ArrivalDepartureDeepLink.swift
//  OBAKitCore
//
//  Created by Aaron Brethorst on 1/29/20.
//

import Foundation

@objc(OBAArrivalDepartureDeepLink)
public class ArrivalDepartureDeepLink: NSObject, Codable {
    public let title: String
    public let stopID: String
    public let tripID: TripIdentifier
    public let serviceDate: Date
    public let stopSequence: Int
    public let vehicleID: String?

    public convenience init(arrivalDeparture: ArrivalDeparture) {
        self.init(title: arrivalDeparture.routeAndHeadsign, stopID: arrivalDeparture.stopID, tripID: arrivalDeparture.tripID, serviceDate: arrivalDeparture.serviceDate, stopSequence: arrivalDeparture.stopSequence, vehicleID: arrivalDeparture.vehicleID)
    }

    public init(title: String, stopID: String, tripID: String, serviceDate: Date, stopSequence: Int, vehicleID: String?) {
        self.title = title
        self.stopID = stopID
        self.tripID = tripID
        self.serviceDate = serviceDate
        self.stopSequence = stopSequence
        self.vehicleID = vehicleID
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let rhs = object as? ArrivalDepartureDeepLink else { return false }
        return
            title == rhs.title &&
            stopID == rhs.stopID &&
            tripID == rhs.tripID &&
            serviceDate == rhs.serviceDate &&
            stopSequence == rhs.stopSequence &&
            vehicleID == rhs.vehicleID
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(title)
        hasher.combine(stopID)
        hasher.combine(tripID)
        hasher.combine(serviceDate)
        hasher.combine(stopSequence)
        hasher.combine(vehicleID)
        return hasher.finalize()
    }
}