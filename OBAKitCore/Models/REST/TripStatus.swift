//
//  TripStatus.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/20/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation

/// The `tripStatus` element captures information about the current status of a transit vehicle serving a trip. It is returned as a sub-element in a number of REST API calls.
public class TripStatus: NSObject, Decodable {

    /// the trip id of the trip the vehicle is actively serving. All trip-specific values will be in reference to this active trip
    let activeTripID: String

    /// the trip the vehicle is actively serving. All trip-specific values will be in reference to this active trip
    public let activeTrip: Trip

    /// the index of the active trip into the sequence of trips for the active block. Compare to `blockTripSequence`
    /// in `ArrivalAndDeparture` to determine where the active block location is relative to an arrival-and-departure.
    public let blockTripSequence: Int

    /// the id of the closest stop to the current location of the transit vehicle, whether from schedule or
    /// real-time predicted location data
    public let closestStopID: String

    /// The closest stop to the current location of the transit vehicle, whether from schedule or
    /// real-time predicted location data
    public let closestStop: Stop

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
    public let lastKnownDistanceAlongTrip: Int

    /// Last known location of the transit vehicle. This differs from the existing position field,
    /// in that the position field is potential extrapolated forward from the last known position and other data.
    public let lastKnownLocation: CLLocation?

    /// The last known orientation value received in real-time from the transit vehicle.
    public let lastKnownOrientation: CLLocationDirection

    /// The last known real-time location update from the transit vehicle. This is different
    /// from lastUpdateTime in that it reflects the last know location update. An update from
    /// a vehicle might not contain location info, which means this field will not be updated.
    /// Will be zero if we haven't had a location update from the vehicle.
    public let lastLocationUpdateTime: Int

    /// The last known real-time update from the transit vehicle. Will be `nil` if we haven't heard anything from the vehicle.
    public let lastUpdate: Date?

    /// Similar to `closestStopID`, except that it always captures the next stop, not the closest stop.
    /// Optional, as a vehicle may have progressed past the last stop in a trip.
    let nextStopID: String?

    /// Similar to `closestStop`, except that it always captures the next stop, not the closest stop.
    /// Optional, as a vehicle may have progressed past the last stop in a trip.
    public let nextStop: Stop?

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
    public let position: CLLocation?

    /// True if we have real-time arrival info available for this trip
    public let isRealTime: Bool

    /// If real-time arrival info is available, this lists the deviation from the schedule in seconds, where positive number indicates the trip is running late and negative indicates the trips is running early. If not real-time arrival info is available, this will be zero.
    public let scheduleDeviation: TimeInterval

    /// The distance, in meters, the transit vehicle is scheduled to have progress along the active trip. This is an optional value, and will only be present if the trip is in progress.
    public let scheduledDistanceAlongTrip: Double

    /// Time of midnight for start of the service date for the trip.
    public let serviceDate: Date

    /// References to `Situation`s for active service alerts applicable to this trip.
    let situationIDs: [String]

    /// Active service alerts applicable to this trip.
    public let situations: [Situation]

    /// status modifiers for the trip
    public let status: String

    /// The total length of the trip, in meters
    public let totalDistanceAlongTrip: Double

    /// If real-time arrival info is available, this lists the id of the transit vehicle currently running the trip.
    public let vehicleID: String?

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

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let references = decoder.userInfo[CodingUserInfoKey.references] as! References // swiftlint:disable:this force_cast

        activeTripID = try container.decode(String.self, forKey: .activeTripID)
        activeTrip = references.tripWithID(activeTripID)!

        blockTripSequence = try container.decode(Int.self, forKey: .blockTripSequence)

        closestStopID = try container.decode(String.self, forKey: .closestStopID)
        closestStop = references.stopWithID(closestStopID)!

        closestStopTimeOffset = try container.decode(Int.self, forKey: .closestStopTimeOffset)
        distanceAlongTrip = try container.decode(Double.self, forKey: .distanceAlongTrip)
        frequency = try? container.decodeIfPresent(Frequency.self, forKey: .frequency)
        lastKnownDistanceAlongTrip = try container.decode(Int.self, forKey: .lastKnownDistanceAlongTrip)
        lastKnownLocation = try? CLLocation(container: container, key: .lastKnownLocation)
        lastKnownOrientation = try container.decode(CLLocationDirection.self, forKey: .lastKnownOrientation)
        lastLocationUpdateTime = try container.decode(Int.self, forKey: .lastLocationUpdateTime)

        let lastUpdateTime = try container.decode(TimeInterval.self, forKey: .lastUpdate)
        if lastUpdateTime == 0 {
            lastUpdate = nil
        }
        else {
            lastUpdate = Date(timeIntervalSince1970: (lastUpdateTime / 1000.0))
        }

        nextStopID = try? container.decodeIfPresent(String.self, forKey: .nextStopID)
        nextStop = references.stopWithID(nextStopID)

        nextStopTimeOffset = try container.decode(Int.self, forKey: .nextStopTimeOffset)
        orientation = try container.decode(CLLocationDirection.self, forKey: .orientation)
        phase = try container.decode(String.self, forKey: .phase)
        position = try? CLLocation(container: container, key: .position)
        isRealTime = try container.decode(Bool.self, forKey: .isRealTime)
        scheduleDeviation = try container.decode(TimeInterval.self, forKey: .scheduleDeviation)
        scheduledDistanceAlongTrip = try container.decode(Double.self, forKey: .scheduledDistanceAlongTrip)
        serviceDate = try container.decode(Date.self, forKey: .serviceDate)

        situationIDs = try container.decode([String].self, forKey: .situationIDs)
        situations = references.situationsWithIDs(situationIDs)

        status = try container.decode(String.self, forKey: .status)
        totalDistanceAlongTrip = try container.decode(Double.self, forKey: .totalDistanceAlongTrip)
        vehicleID = try? container.decodeIfPresent(String.self, forKey: .vehicleID)
    }

    // MARK: - Equality

    public override func isEqual(_ object: Any?) -> Bool {
        guard let rhs = object as? TripStatus else { return false }
        return
            activeTripID == rhs.activeTripID &&
            activeTrip == rhs.activeTrip &&
            blockTripSequence == rhs.blockTripSequence &&
            closestStopID == rhs.closestStopID &&
            closestStop == rhs.closestStop &&
            closestStopTimeOffset == rhs.closestStopTimeOffset &&
            distanceAlongTrip == rhs.distanceAlongTrip &&
            frequency == rhs.frequency &&
            lastKnownDistanceAlongTrip == rhs.lastKnownDistanceAlongTrip &&
            lastKnownLocation == rhs.lastKnownLocation &&
            lastKnownOrientation == rhs.lastKnownOrientation &&
            lastLocationUpdateTime == rhs.lastLocationUpdateTime &&
            lastUpdate == rhs.lastUpdate &&
            nextStopID == rhs.nextStopID &&
            nextStop == rhs.nextStop &&
            nextStopTimeOffset == rhs.nextStopTimeOffset &&
            orientation == rhs.orientation &&
            phase == rhs.phase &&
            position == rhs.position &&
            isRealTime == rhs.isRealTime &&
            scheduleDeviation == rhs.scheduleDeviation &&
            scheduledDistanceAlongTrip == rhs.scheduledDistanceAlongTrip &&
            serviceDate == rhs.serviceDate &&
            situationIDs == rhs.situationIDs &&
            situations == rhs.situations &&
            status == rhs.status &&
            totalDistanceAlongTrip == rhs.totalDistanceAlongTrip &&
            vehicleID == rhs.vehicleID
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(activeTripID)
        hasher.combine(activeTrip)
        hasher.combine(blockTripSequence)
        hasher.combine(closestStopID)
        hasher.combine(closestStop)
        hasher.combine(closestStopTimeOffset)
        hasher.combine(distanceAlongTrip)
        hasher.combine(frequency)
        hasher.combine(lastKnownDistanceAlongTrip)
        hasher.combine(lastKnownLocation)
        hasher.combine(lastKnownOrientation)
        hasher.combine(lastLocationUpdateTime)
        hasher.combine(lastUpdate)
        hasher.combine(nextStopID)
        hasher.combine(nextStop)
        hasher.combine(nextStopTimeOffset)
        hasher.combine(orientation)
        hasher.combine(phase)
        hasher.combine(position)
        hasher.combine(isRealTime)
        hasher.combine(scheduleDeviation)
        hasher.combine(scheduledDistanceAlongTrip)
        hasher.combine(serviceDate)
        hasher.combine(situationIDs)
        hasher.combine(situations)
        hasher.combine(status)
        hasher.combine(totalDistanceAlongTrip)
        hasher.combine(vehicleID)

        return hasher.finalize()
    }
}
