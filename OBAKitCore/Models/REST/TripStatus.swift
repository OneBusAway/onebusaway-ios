//
//  TripStatus.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MetaCodable
import CoreLocation

/// The `tripStatus` element captures information about the current status of a transit vehicle serving a trip. It is returned as a sub-element in a number of REST API calls.
@Codable
public struct TripStatus: Identifiable, Hashable {
    public var id: String {
        return self.activeTripID
    }

    /// the trip id of the trip the vehicle is actively serving. All trip-specific values will be in reference to this active trip
    @CodedAt("activeTripId")
    public let activeTripID: String

    /// the trip the vehicle is actively serving. All trip-specific values will be in reference to this active trip
//    public private(set) var activeTrip: Trip!

    /// the index of the active trip into the sequence of trips for the active block. Compare to `blockTripSequence`
    /// in `ArrivalAndDeparture` to determine where the active block location is relative to an arrival-and-departure.
    public let blockTripSequence: Int

    /// the id of the closest stop to the current location of the transit vehicle, whether from schedule or
    /// real-time predicted location data
    @CodedAt("closestStop")
    public let closestStopID: StopID

    /// The closest stop to the current location of the transit vehicle, whether from schedule or
    /// real-time predicted location data
//    public private(set) var closestStop: Stop!

    /// the time offset, in seconds, from the closest stop to the current position of the transit vehicle
    /// among the stop times of the current trip. If the number is positive, the stop is coming up.
    /// If negative, the stop has already been passed.
    public let closestStopTimeOffset: Int

    /// the distance, in meters, the transit vehicle has progressed along the active trip.
    /// This is an optional value that will only be present if the underlying AVL system
    /// supplies it and is potential extrapolated from the last known reading to the current time.
    public let distanceAlongTrip: Double

    /// information about frequency based scheduling, if applicable to the trip
    public let frequency: Frequency?

    /// The last known distance along trip value received in real-time from the transit vehicle.
    public let lastKnownDistanceAlongTrip: Int?

    /// Last known location of the transit vehicle. This differs from the existing position field,
    /// in that the position field is potential extrapolated forward from the last known position and other data.
    public let lastKnownLocation: LocationModel?

    /// The last known orientation value received in real-time from the transit vehicle.
    public let lastKnownOrientation: CLLocationDirection?

    /// The last known real-time location update from the transit vehicle. This is different
    /// from lastUpdateTime in that it reflects the last known location update. An update from
    /// a vehicle might not contain location info, which means this field will not be updated.
    /// Will be zero if we haven't had a location update from the vehicle.
    public let lastLocationUpdateTime: Int

    /// The last known real-time update from the transit vehicle. Will be `nil` if we haven't heard anything from the vehicle.
    @CodedAt("lastUpdateTime") @CodedBy(Date.EpochMilliseconds())
    public let lastUpdate: Date?

    /// Similar to `closestStopID`, except that it always captures the next stop, not the closest stop.
    /// Optional, as a vehicle may have progressed past the last stop in a trip.
    @CodedAt("nextStop")
    let nextStopID: StopID?

    /// Similar to `closestStop`, except that it always captures the next stop, not the closest stop.
    /// Optional, as a vehicle may have progressed past the last stop in a trip.
//    public private(set) var nextStop: Stop?

    /// Similar to `closestStopTimeOffset`, except that it always captures the next stop, not the closest stop.
    /// Optional, as a vehicle may have progressed past the last stop in a trip.
    public let nextStopTimeOffset: Int

    /// The orientation of the transit vehicle, as an angle in degrees.
    /// Here, 0º is east, 90º is north, 180º is west, and 270º is south.
    /// This is an optional value that may be extrapolated from other data.
    public let orientation: CLLocationDirection

    /// The current journey phase of the trip
    public let phase: String

    /// Current position of the transit vehicle. This element is optional, and will only be
    /// present if the trip is actively running. If real-time arrival data is available,
    /// the position will take that into account, otherwise the position reflects the
    /// scheduled position of the vehicle.
    public let position: LocationModel?

    /// True if we have real-time arrival info available for this trip
    @CodedAt("predicted")
    public let isRealTime: Bool

    /// If real-time arrival info is available, this lists the deviation from the schedule in seconds, where positive number indicates the trip is running late and negative indicates the trips is running early. If not real-time arrival info is available, this will be zero.
    public let scheduleDeviation: TimeInterval

    /// The distance, in meters, the transit vehicle is scheduled to have progress along the active trip. This is an optional value, and will only be present if the trip is in progress.
    public let scheduledDistanceAlongTrip: Double

    /// Time of midnight for start of the service date for the trip.
    public let serviceDate: Date

    /// References to `Situation`s for active service alerts applicable to this trip.
    @CodedAt("situationIds")
    public let situationIDs: [String]

    /// Active service alerts applicable to this trip.
//    public private(set) var serviceAlerts = [ServiceAlert]()

    /// Status modifier for the trip
    @CodedAt("status")
    public let statusModifier: StatusModifier

    public enum StatusModifier: Codable, Hashable {
        case `default`, scheduled, canceled
        case other(String)

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let status = try container.decode(String.self)

            self = switch status.uppercased() {
            case "DEFAULT": .default
            case "SCHEDULED": .scheduled
            case "CANCELED": .canceled
            default: .other(status)
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()

            let value = switch self {
            case .default: "default"
            case .scheduled: "scheduled"
            case .canceled: "canceled"
            case .other(let status): status
            }

            try container.encode(value)
        }
    }

    /// The total length of the trip, in meters
    public let totalDistanceAlongTrip: Double

    /// If real-time arrival info is available, this lists the id of the transit vehicle currently running the trip.
    public let vehicleID: String?

//    public private(set) var regionIdentifier: Int?

//    public func loadReferences(_ references: References, regionIdentifier: Int?) {
//        activeTrip = references.tripWithID(activeTripID)!
//        closestStop = references.stopWithID(closestStopID)!
//        nextStop = references.stopWithID(nextStopID)
//        serviceAlerts = references.serviceAlertsWithIDs(situationIDs)
//        self.regionIdentifier = regionIdentifier
//    }
}

/// :nodoc:
public func == (lhs: TripStatus.StatusModifier, rhs: TripStatus.StatusModifier) -> Bool {
    switch (lhs, rhs) {
    case (.default, .default),
         (.scheduled, .scheduled),
         (.canceled, .canceled): return true
    case let (.other(a), .other(b)): return a == b
    default: return false
    }
}
