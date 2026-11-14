//
//  VehicleFix.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation

/// One real-time position report: where the vehicle was, and when.
public struct VehicleFix: Sendable {
    public let tripID: String
    public let vehicleID: String?
    /// When the vehicle was at `coordinate`, by the AVL clock.
    public let fixTime: Date
    public let coordinate: CLLocationCoordinate2D
    /// Seconds late (positive) or early, as the server judged it.
    public let scheduleDeviation: TimeInterval

    public init(tripID: String, vehicleID: String?, fixTime: Date, coordinate: CLLocationCoordinate2D, scheduleDeviation: TimeInterval) {
        self.tripID = tripID
        self.vehicleID = vehicleID
        self.fixTime = fixTime
        self.coordinate = coordinate
        self.scheduleDeviation = scheduleDeviation
    }

    /// The fix a status reports for `tripID`, or `nil` when it can't anchor an estimate.
    ///
    /// - The location is `lastKnownLocation`, the raw GPS fix. Not `position`: on the
    ///   Java server that is the *schedule's* location at the fix time, which can be
    ///   hundreds of meters from the bus.
    /// - The time is `lastLocationUpdateTime`, falling back to `lastUpdateTime`. Never
    ///   `lastKnownLocation.timestamp`, which is when the response was decoded.
    /// - The status must be for `tripID`. A bus still finishing the previous trip of its
    ///   block reports distances on that trip's shape, not this one's.
    /// - Scheduled-only (`predicted == false`) and canceled trips have no live position.
    public init?(tripStatus: TripStatus, tripID: String) {
        guard
            tripStatus.isRealTime,
            tripStatus.statusModifier != .canceled,
            tripStatus.activeTripID == tripID,
            let coordinate = tripStatus.lastKnownLocation?.coordinate,
            CLLocationCoordinate2DIsValid(coordinate),
            !coordinate.isNullIsland
        else { return nil }

        let fixTime: Date
        if tripStatus.lastLocationUpdateTime > 0 {
            fixTime = Date(timeIntervalSince1970: TimeInterval(tripStatus.lastLocationUpdateTime) / 1000)
        } else if let lastUpdate = tripStatus.lastUpdate, lastUpdate.timeIntervalSince1970 > 0 {
            fixTime = lastUpdate
        } else {
            return nil
        }

        self.init(
            tripID: tripID,
            vehicleID: tripStatus.vehicleID,
            fixTime: fixTime,
            coordinate: coordinate,
            scheduleDeviation: tripStatus.scheduleDeviation
        )
    }
}

/// The device clock's offset from the server's, from recent responses.
///
/// Fix ages are measured as server time minus fix time; the device only has its
/// own clock, so it subtracts this offset. A median over a few samples, so one
/// slow response does not swing it.
public struct ClockSkewEstimator: Sendable {
    private let capacity: Int
    private var offsets: [TimeInterval] = []

    public init(capacity: Int = 5) {
        self.capacity = max(capacity, 1)
    }

    public mutating func record(_ sample: ServerClockSample) {
        offsets.append(sample.deviceOffset)
        if offsets.count > capacity { offsets.removeFirst(offsets.count - capacity) }
    }

    /// Seconds the device clock runs ahead of the server's. Zero with no samples.
    public var deviceOffset: TimeInterval {
        guard !offsets.isEmpty else { return 0 }
        let sorted = offsets.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    public func serverNow(deviceNow: Date) -> Date {
        deviceNow - deviceOffset
    }
}
