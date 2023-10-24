//
//  VehicleStatus.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MetaCodable
import CoreLocation

extension CLLocation {
    class OBALocationCoder: HelperCoder {
        private enum CodingKeys: String, CodingKey {
            case lat, lon
        }

        func decode(from decoder: Decoder) throws -> CLLocation {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let lat = try container.decode(Double.self, forKey: .lat)
            let lon = try container.decode(Double.self, forKey: .lon)

            return CLLocation(latitude: lat, longitude: lon)
        }

        func encode(_ value: CLLocation, to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(value.coordinate.latitude, forKey: .lat)
            try container.encode(value.coordinate.longitude, forKey: .lon)
        }
    }
}

@Codable
public struct VehicleStatus: Identifiable, Hashable/*, HasReferences*/ {
    /// The id of the vehicle
    @CodedAt("vehicleId")
    public let id: String

    /// The last known real-time update from the transit vehicle
    public let lastUpdateTime: Date?

    /// The last known real-time update from the transit vehicle containing a location update
    @CodedBy(Date.NillifyDate(ifEarlierThan: Date(timeIntervalSinceReferenceDate: 1)))
    public let lastLocationUpdateTime: Date?

    /// The last known location of the vehicle
    @CodedBy(CLLocation.OBALocationCoder())
    public let location: CLLocation?

    /// The id of the vehicle's current trip, which can be used to look up the referenced `trip` element in the `references` section of the data.
    @CodedAt("tripId") @CodedBy(String.NillifyEmptyString())
    public let tripID: TripIdentifier?

    /// The vehicle's current trip
//    public private(set) var trip: Trip?

    /// the current journey phase of the vehicle
    public let phase: String

    /// status modifiers for the vehicle
    public let status: String

    /// Provides additional status information for the vehicle's trip.
    public let tripStatus: TripStatus

//    public private(set) var regionIdentifier: Int?

//    public func loadReferences(_ references: References, regionIdentifier: Int?) {
//        trip = references.tripWithID(tripID)
////        tripStatus.loadReferences(references, regionIdentifier: regionIdentifier)
//        self.regionIdentifier = regionIdentifier
//    }
}
