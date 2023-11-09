//
//  TripStatus.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

/// The `tripStatus` element captures information about the current status of a transit vehicle serving a trip. It is returned as a sub-element in a number of REST API calls.
public struct TripStatus: Identifiable, Codable, Hashable {
    public var id: String {
        return self.activeTripID
    }

    /// the trip id of the trip the vehicle is actively serving. All trip-specific values will be in reference to this active trip
    public let activeTripID: String

    /// the index of the active trip into the sequence of trips for the active block. Compare to `blockTripSequence`
    /// in `ArrivalAndDeparture` to determine where the active block location is relative to an arrival-and-departure.
    public let blockTripSequence: Int

    /// the id of the closest stop to the current location of the transit vehicle, whether from schedule or
    /// real-time predicted location data
    public let closestStopID: StopID

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
    public let lastUpdate: Date?

    /// Similar to `closestStopID`, except that it always captures the next stop, not the closest stop.
    /// Optional, as a vehicle may have progressed past the last stop in a trip.
    public let nextStopID: StopID?

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
    public let isRealTime: Bool

    /// If real-time arrival info is available, this lists the deviation from the schedule in seconds, where positive number indicates the trip is running late and negative indicates the trips is running early. If not real-time arrival info is available, this will be zero.
    public let scheduleDeviation: TimeInterval

    /// The distance, in meters, the transit vehicle is scheduled to have progress along the active trip. This is an optional value, and will only be present if the trip is in progress.
    public let scheduledDistanceAlongTrip: Double

    /// Time of midnight for start of the service date for the trip.
    public let serviceDate: Date

    /// References to `Situation`s for active service alerts applicable to this trip.
    public let situationIDs: [String]

    /// Status modifier for the trip
    public let statusModifier: StatusModifier

    public enum StatusModifier: Equatable, Hashable {
        case `default`, scheduled, canceled
        case other(String)

        /// Converts a `String` into a `StatusModifier` enum value.
        /// - Parameter status: The status string.
        /// - Returns: An enum value.
        fileprivate static func decode(_ status: String) -> StatusModifier {
            switch status.uppercased() {
            case "DEFAULT": return .default
            case "SCHEDULED": return .scheduled
            case "CANCELED": return .canceled
            default: return .other(status)
            }
        }

        func encode() -> String {
            switch self {
            case .default: return "DEFAULT"
            case .scheduled: return "SCHEDULED"
            case .canceled: return "CANCELED"
            case .other(let status): return status
            }
        }
    }

    /// The total length of the trip, in meters
    public let totalDistanceAlongTrip: Double

    /// If real-time arrival info is available, this lists the id of the transit vehicle currently running the trip.
    public let vehicleID: String?

    public private(set) var regionIdentifier: Int?

    private enum CodingKeys: String, CodingKey {
        case activeTripID = "activeTripId"
        case blockTripSequence
        case closestStopID = "closestStop"
        case closestStopTimeOffset, distanceAlongTrip, lastKnownDistanceAlongTrip, lastKnownLocation, lastKnownOrientation, lastLocationUpdateTime
        case lastUpdate = "lastUpdateTime"
        case nextStopID = "nextStop"
        case nextStopTimeOffset, orientation, phase, position
        case isRealTime = "predicted"
        case scheduleDeviation, scheduledDistanceAlongTrip, serviceDate
        case situationIDs = "situationIds"
        case status, totalDistanceAlongTrip
        case vehicleID = "vehicleId"
        case frequency
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        activeTripID = try container.decode(String.self, forKey: .activeTripID)

        blockTripSequence = try container.decode(Int.self, forKey: .blockTripSequence)

        closestStopID = try container.decode(StopID.self, forKey: .closestStopID)

        closestStopTimeOffset = try container.decode(Int.self, forKey: .closestStopTimeOffset)
        distanceAlongTrip = try container.decode(Double.self, forKey: .distanceAlongTrip)
        frequency = try container.decodeIfPresent(Frequency.self, forKey: .frequency)
        lastKnownDistanceAlongTrip = try container.decodeIfPresent(Int.self, forKey: .lastKnownDistanceAlongTrip)
        lastKnownLocation = try container.decodeIfPresent(LocationModel.self, forKey: .lastKnownLocation)
        lastKnownOrientation = try container.decodeIfPresent(CLLocationDirection.self, forKey: .lastKnownOrientation)
        lastLocationUpdateTime = try container.decode(Int.self, forKey: .lastLocationUpdateTime)

        let lastUpdateTime = try container.decode(TimeInterval.self, forKey: .lastUpdate)
        lastUpdate = ModelHelpers.epochMillisecondsToDate(lastUpdateTime)

        nextStopID = try container.decodeIfPresent(StopID.self, forKey: .nextStopID)

        nextStopTimeOffset = try container.decode(Int.self, forKey: .nextStopTimeOffset)
        orientation = try container.decode(CLLocationDirection.self, forKey: .orientation)
        phase = try container.decode(String.self, forKey: .phase)
        position = try container.decodeIfPresent(LocationModel.self, forKey: .position)
        isRealTime = try container.decode(Bool.self, forKey: .isRealTime)
        scheduleDeviation = try container.decode(TimeInterval.self, forKey: .scheduleDeviation)
        scheduledDistanceAlongTrip = try container.decode(Double.self, forKey: .scheduledDistanceAlongTrip)
        serviceDate = try container.decode(Date.self, forKey: .serviceDate)

        situationIDs = try container.decode([String].self, forKey: .situationIDs)

        let status = try container.decode(String.self, forKey: .status)
        statusModifier = StatusModifier.decode(status)

        totalDistanceAlongTrip = try container.decode(Double.self, forKey: .totalDistanceAlongTrip)
        vehicleID = try container.decodeIfPresent(String.self, forKey: .vehicleID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(activeTripID, forKey: .activeTripID)
        try container.encode(blockTripSequence, forKey: .blockTripSequence)

        try container.encode(closestStopID, forKey: .closestStopID)
        try container.encode(closestStopTimeOffset, forKey: .closestStopTimeOffset)
        try container.encode(distanceAlongTrip, forKey: .distanceAlongTrip)
        try container.encodeIfPresent(frequency, forKey: .frequency)
        try container.encode(lastKnownDistanceAlongTrip, forKey: .lastKnownDistanceAlongTrip)
        try container.encode(lastKnownOrientation, forKey: .lastKnownOrientation)
        try container.encode(lastLocationUpdateTime, forKey: .lastLocationUpdateTime)

        try container.encodeIfPresent(lastKnownLocation, forKey: .lastKnownLocation)
        try container.encode(situationIDs, forKey: .situationIDs)

        try container.encode(statusModifier.encode(), forKey: .status)
        try container.encode(totalDistanceAlongTrip, forKey: .totalDistanceAlongTrip)
        try container.encode(vehicleID, forKey: .vehicleID)
    }
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
