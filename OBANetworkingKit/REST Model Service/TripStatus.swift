//
//  TripStatus.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/20/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation

/// The `tripStatus` element captures information about the current status of a transit vehicle serving a trip. It is returned as a sub-element in a number of api calls.
@objc(OBATripStatus)
public class TripStatus: NSObject, Decodable {
    let activeTripID: String
    let blockTripSequence: Int
    let closestStop: String
    let closestStopTimeOffset: Int
    let distanceAlongTrip: Double
//    let frequency: Frequency
    let lastKnownDistanceAlongTrip: Int
    let lastKnownLocation: CLLocation?
    let lastKnownOrientation: Int
    let lastLocationUpdateTime: Int
    let lastUpdateTime: Int
    let nextStop: String
    let nextStopTimeOffset: Int
    let orientation: Double
    let phase: String
    let position: CLLocation?
    let predicted: Bool
    let scheduleDeviation: Int
    let scheduledDistanceAlongTrip: Double
    let serviceDate: Date
    let situationIDs: [String]
    let status: String
    let totalDistanceAlongTrip: Double
    let vehicleID: String

    enum CodingKeys: String, CodingKey {
        case activeTripID = "activeTripId"
        case blockTripSequence, closestStop, closestStopTimeOffset, distanceAlongTrip, lastKnownDistanceAlongTrip, lastKnownLocation, lastKnownOrientation, lastLocationUpdateTime, lastUpdateTime, nextStop, nextStopTimeOffset, orientation, phase, position, predicted, scheduleDeviation, scheduledDistanceAlongTrip, serviceDate
        case situationIDs = "situationIds"
        case status, totalDistanceAlongTrip
        case vehicleID = "vehicleId"
//        case frequency
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        activeTripID = try container.decode(String.self, forKey: .activeTripID)
        blockTripSequence = try container.decode(Int.self, forKey: .blockTripSequence)
        closestStop = try container.decode(String.self, forKey: .closestStop)
        closestStopTimeOffset = try container.decode(Int.self, forKey: .closestStopTimeOffset)
        distanceAlongTrip = try container.decode(Double.self, forKey: .distanceAlongTrip)
//        frequency = try container.decode(Frequency.self, forKey: .frequency)
        lastKnownDistanceAlongTrip = try container.decode(Int.self, forKey: .lastKnownDistanceAlongTrip)
        lastKnownLocation = try? CLLocation(container: container, key: .lastKnownLocation)
        lastKnownOrientation = try container.decode(Int.self, forKey: .lastKnownOrientation)
        lastLocationUpdateTime = try container.decode(Int.self, forKey: .lastLocationUpdateTime)
        lastUpdateTime = try container.decode(Int.self, forKey: .lastUpdateTime)
        nextStop = try container.decode(String.self, forKey: .nextStop)
        nextStopTimeOffset = try container.decode(Int.self, forKey: .nextStopTimeOffset)
        orientation = try container.decode(Double.self, forKey: .orientation)
        phase = try container.decode(String.self, forKey: .phase)
        position = try? CLLocation(container: container, key: .position)
        predicted = try container.decode(Bool.self, forKey: .predicted)
        scheduleDeviation = try container.decode(Int.self, forKey: .scheduleDeviation)
        scheduledDistanceAlongTrip = try container.decode(Double.self, forKey: .scheduledDistanceAlongTrip)
        serviceDate = try container.decode(Date.self, forKey: .serviceDate)
        situationIDs = try container.decode([String].self, forKey: .situationIDs)
        status = try container.decode(String.self, forKey: .status)
        totalDistanceAlongTrip = try container.decode(Double.self, forKey: .totalDistanceAlongTrip)
        vehicleID = try container.decode(String.self, forKey: .vehicleID)
    }
}
