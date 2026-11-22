//
//  GTFSRealtimeTripUpdateParser.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import SwiftProtobuf

// MARK: - Schedule Relationships

/// Relationship between a GTFS-RT trip and the static GTFS schedule.
public enum GTFSRTTripScheduleRelationship: String, Sendable, CaseIterable, Codable, Equatable {
    case scheduled = "SCHEDULED"
    case added = "ADDED"
    case unscheduled = "UNSCHEDULED"
    case canceled = "CANCELED"
    case replacement = "REPLACEMENT"
    case duplicated = "DUPLICATED"
    case deleted = "DELETED"
    case newTrip = "NEW"

    public init(protobuf: TransitRealtime_TripDescriptor.ScheduleRelationship) {
        switch protobuf {
        case .scheduled: self = .scheduled
        case .added: self = .added
        case .unscheduled: self = .unscheduled
        case .canceled: self = .canceled
        case .replacement: self = .replacement
        case .duplicated: self = .duplicated
        case .deleted: self = .deleted
        case .new: self = .newTrip
        }
    }

    /// Whether this trip has been canceled or removed.
    public var isCanceledOrDeleted: Bool {
        self == .canceled || self == .deleted
    }
}

/// Relationship between a stop time update and the static GTFS schedule.
public enum GTFSRTStopTimeScheduleRelationship: String, Sendable, CaseIterable, Codable, Equatable {
    case scheduled = "SCHEDULED"
    case skipped = "SKIPPED"
    case noData = "NO_DATA"
    case unscheduled = "UNSCHEDULED"

    public init(protobuf: TransitRealtime_TripUpdate.StopTimeUpdate.ScheduleRelationship) {
        switch protobuf {
        case .scheduled: self = .scheduled
        case .skipped: self = .skipped
        case .noData: self = .noData
        case .unscheduled: self = .unscheduled
        }
    }

    /// Whether this stop is skipped by the transit vehicle.
    public var isSkipped: Bool {
        self == .skipped
    }

    /// Whether real-time prediction data is withheld for this stop.
    public var isNoData: Bool {
        self == .noData
    }
}

// MARK: - Stop Time Event

/// Predicted or actual timing for a stop arrival or departure event.
public struct GTFSRTStopTimeEvent: Sendable, Equatable, Hashable {
    /// Delay in seconds relative to schedule (positive = late, negative = early).
    public let delay: Int?
    /// Event timestamp as `Date`.
    public let time: Date?
    /// Uncertainty window in seconds (0 = completely certain).
    public let uncertainty: Int?
    /// Scheduled time if explicitly provided for added/duplicated trips.
    public let scheduledTime: Date?

    public init(
        delay: Int? = nil,
        time: Date? = nil,
        uncertainty: Int? = nil,
        scheduledTime: Date? = nil
    ) {
        self.delay = delay
        self.time = time
        self.uncertainty = uncertainty
        self.scheduledTime = scheduledTime
    }

    public init(protobuf: TransitRealtime_TripUpdate.StopTimeEvent) {
        self.delay = protobuf.hasDelay ? Int(protobuf.delay) : nil
        self.time = protobuf.hasTime && protobuf.time > 0
            ? Date(timeIntervalSince1970: TimeInterval(protobuf.time))
            : nil
        self.uncertainty = protobuf.hasUncertainty ? Int(protobuf.uncertainty) : nil
        self.scheduledTime = protobuf.hasScheduledTime && protobuf.scheduledTime > 0
            ? Date(timeIntervalSince1970: TimeInterval(protobuf.scheduledTime))
            : nil
    }
}

// MARK: - Stop Time Update

/// Real-time arrival and departure updates for a specific stop along a trip.
public struct GTFSRTStopTimeUpdate: Sendable, Equatable, Hashable {
    /// Stop sequence number matching `stop_times.txt`.
    public let stopSequence: UInt32?
    /// Stop identifier matching `stops.txt`.
    public let stopID: String?
    /// Arrival event predictions.
    public let arrival: GTFSRTStopTimeEvent?
    /// Departure event predictions.
    public let departure: GTFSRTStopTimeEvent?
    /// Relationship between this stop event and the schedule.
    public let scheduleRelationship: GTFSRTStopTimeScheduleRelationship
    /// Occupancy status after departing this stop.
    public let departureOccupancyStatus: TransitRealtime_VehiclePosition.OccupancyStatus?
    /// Realtime updated headsign at this stop.
    public let stopHeadsign: String?

    public init(
        stopSequence: UInt32? = nil,
        stopID: String? = nil,
        arrival: GTFSRTStopTimeEvent? = nil,
        departure: GTFSRTStopTimeEvent? = nil,
        scheduleRelationship: GTFSRTStopTimeScheduleRelationship = .scheduled,
        departureOccupancyStatus: TransitRealtime_VehiclePosition.OccupancyStatus? = nil,
        stopHeadsign: String? = nil
    ) {
        self.stopSequence = stopSequence
        self.stopID = stopID
        self.arrival = arrival
        self.departure = departure
        self.scheduleRelationship = scheduleRelationship
        self.departureOccupancyStatus = departureOccupancyStatus
        self.stopHeadsign = stopHeadsign
    }

    public init(protobuf: TransitRealtime_TripUpdate.StopTimeUpdate) {
        self.stopSequence = protobuf.hasStopSequence ? protobuf.stopSequence : nil
        self.stopID = protobuf.hasStopID ? protobuf.stopID : nil
        self.arrival = protobuf.hasArrival ? GTFSRTStopTimeEvent(protobuf: protobuf.arrival) : nil
        self.departure = protobuf.hasDeparture ? GTFSRTStopTimeEvent(protobuf: protobuf.departure) : nil
        self.scheduleRelationship = GTFSRTStopTimeScheduleRelationship(protobuf: protobuf.scheduleRelationship)
        self.departureOccupancyStatus = protobuf.hasDepartureOccupancyStatus ? protobuf.departureOccupancyStatus : nil
        self.stopHeadsign = protobuf.hasStopTimeProperties && protobuf.stopTimeProperties.hasStopHeadsign
            ? protobuf.stopTimeProperties.stopHeadsign
            : nil
    }

    /// Arrival delay in seconds if specified.
    public var arrivalDelay: Int? {
        arrival?.delay
    }

    /// Departure delay in seconds if specified.
    public var departureDelay: Int? {
        departure?.delay
    }

    /// Predicted arrival date if specified.
    public var arrivalTime: Date? {
        arrival?.time
    }

    /// Predicted departure date if specified.
    public var departureTime: Date? {
        departure?.time
    }
}

// MARK: - Trip Update Domain Model

/// Real-time progress and stop time predictions for a transit vehicle trip.
public struct GTFSRTTripUpdate: Sendable, Equatable {
    /// Feed entity ID enclosing this update.
    public let entityID: String?
    /// Trip identifier.
    public let tripID: String
    /// Source trip identifier if this update represents a DUPLICATED trip.
    public let sourceTripID: String?
    /// Route identifier.
    public let routeID: String?
    /// Direction identifier.
    public let directionID: UInt32?
    /// Scheduled start time (HH:MM:SS format).
    public let startTime: String?
    /// Scheduled start date (YYYYMMDD format).
    public let startDate: String?
    /// Relationship of this trip to the static schedule.
    public let scheduleRelationship: GTFSRTTripScheduleRelationship
    /// ID of the vehicle serving this trip.
    public let vehicleID: String?
    /// User-visible label of the vehicle serving this trip.
    public let vehicleLabel: String?
    /// Moment real-time progress was measured.
    public let timestamp: Date?
    /// Trip-level schedule deviation in seconds.
    public let tripDelay: Int?
    /// Stop-by-stop time updates sorted by stop sequence.
    public let stopTimeUpdates: [GTFSRTStopTimeUpdate]

    public init(
        entityID: String? = nil,
        tripID: String,
        sourceTripID: String? = nil,
        routeID: String? = nil,
        directionID: UInt32? = nil,
        startTime: String? = nil,
        startDate: String? = nil,
        scheduleRelationship: GTFSRTTripScheduleRelationship = .scheduled,
        vehicleID: String? = nil,
        vehicleLabel: String? = nil,
        timestamp: Date? = nil,
        tripDelay: Int? = nil,
        stopTimeUpdates: [GTFSRTStopTimeUpdate] = []
    ) {
        self.entityID = entityID
        self.tripID = tripID
        self.sourceTripID = sourceTripID
        self.routeID = routeID
        self.directionID = directionID
        self.startTime = startTime
        self.startDate = startDate
        self.scheduleRelationship = scheduleRelationship
        self.vehicleID = vehicleID
        self.vehicleLabel = vehicleLabel
        self.timestamp = timestamp
        self.tripDelay = tripDelay
        self.stopTimeUpdates = stopTimeUpdates
    }

    public init(protobuf: TransitRealtime_TripUpdate, entityID: String? = nil) {
        self.entityID = entityID
        let rel = protobuf.hasTrip
            ? GTFSRTTripScheduleRelationship(protobuf: protobuf.trip.scheduleRelationship)
            : .scheduled
        self.scheduleRelationship = rel

        let rawTripID = protobuf.hasTrip && protobuf.trip.hasTripID ? protobuf.trip.tripID : ""
        if rel == .duplicated && protobuf.hasTripProperties && protobuf.tripProperties.hasTripID {
            self.tripID = protobuf.tripProperties.tripID
            self.sourceTripID = rawTripID.isEmpty ? nil : rawTripID
        } else {
            self.tripID = rawTripID
            self.sourceTripID = nil
        }

        let startD = protobuf.hasTrip && protobuf.trip.hasStartDate ? protobuf.trip.startDate : nil
        let startT = protobuf.hasTrip && protobuf.trip.hasStartTime ? protobuf.trip.startTime : nil
        if rel == .duplicated && protobuf.hasTripProperties {
            self.startDate = (protobuf.tripProperties.hasStartDate ? protobuf.tripProperties.startDate : nil) ?? startD
            self.startTime = (protobuf.tripProperties.hasStartTime ? protobuf.tripProperties.startTime : nil) ?? startT
        } else {
            self.startDate = startD
            self.startTime = startT
        }

        self.routeID = protobuf.hasTrip && protobuf.trip.hasRouteID ? protobuf.trip.routeID : nil
        self.directionID = protobuf.hasTrip && protobuf.trip.hasDirectionID ? protobuf.trip.directionID : nil
        self.vehicleID = protobuf.hasVehicle && protobuf.vehicle.hasID ? protobuf.vehicle.id : nil
        self.vehicleLabel = protobuf.hasVehicle && protobuf.vehicle.hasLabel ? protobuf.vehicle.label : nil
        self.timestamp = protobuf.hasTimestamp && protobuf.timestamp > 0
            ? Date(timeIntervalSince1970: TimeInterval(protobuf.timestamp))
            : nil
        self.tripDelay = protobuf.hasDelay ? Int(protobuf.delay) : nil
        self.stopTimeUpdates = protobuf.stopTimeUpdate.map(GTFSRTStopTimeUpdate.init(protobuf:))
    }
}

// MARK: - GTFSRealtimeTripUpdateParser

/// Unified parser for GTFS-Realtime TripUpdate Protobuf feeds.
public struct GTFSRealtimeTripUpdateParser: Sendable {
    /// Feed parser used for raw Protobuf decoding and header validation.
    public let feedParser: GTFSRealtimeFeedParser

    public init(feedParser: GTFSRealtimeFeedParser = .standard) {
        self.feedParser = feedParser
    }

    /// Standard parser using default header validation rules.
    public static let standard = GTFSRealtimeTripUpdateParser()

    /// Deserializes raw Protobuf data, validates header/incrementality, and extracts `GTFSRTTripUpdate` models.
    /// - Parameters:
    ///   - data: Raw Protobuf binary data.
    ///   - referenceDate: Reference time for staleness checking.
    /// - Returns: An array of extracted `GTFSRTTripUpdate` objects.
    public func parse(
        data: Data,
        referenceDate: Date = Date()
    ) throws -> [GTFSRTTripUpdate] {
        let message = try feedParser.parse(data: data, referenceDate: referenceDate)
        return extractTripUpdates(from: message)
    }

    /// Extracts all `GTFSRTTripUpdate` elements from a decoded `TransitRealtime_FeedMessage`.
    public func extractTripUpdates(from message: TransitRealtime_FeedMessage) -> [GTFSRTTripUpdate] {
        message.entity.compactMap { entity in
            guard entity.hasTripUpdate else { return nil }
            return GTFSRTTripUpdate(protobuf: entity.tripUpdate, entityID: entity.hasID ? entity.id : nil)
        }
    }

    /// Parses a single protobuf `TransitRealtime_TripUpdate` message.
    public func parse(tripUpdate: TransitRealtime_TripUpdate, entityID: String? = nil) -> GTFSRTTripUpdate {
        GTFSRTTripUpdate(protobuf: tripUpdate, entityID: entityID)
    }
}

// MARK: - Reconcilable Protocols and Models

/// A protocol representing a scheduled trip event that can be reconciled with GTFS-RT updates.
public protocol GTFSRTReconcilableSchedule {
    var reconcilableTripID: String { get }
    var reconcilableStopID: String? { get }
    var reconcilableStopSequence: Int? { get }
    var scheduledArrivalDate: Date? { get }
    var scheduledDepartureDate: Date? { get }
}

/// Standalone lightweight schedule event conforming to `GTFSRTReconcilableSchedule`.
public struct GTFSRTScheduleItem: GTFSRTReconcilableSchedule, Sendable, Equatable {
    public let reconcilableTripID: String
    public let reconcilableStopID: String?
    public let reconcilableStopSequence: Int?
    public let scheduledArrivalDate: Date?
    public let scheduledDepartureDate: Date?

    public init(
        tripID: String,
        stopID: String? = nil,
        stopSequence: Int? = nil,
        scheduledArrival: Date? = nil,
        scheduledDeparture: Date? = nil
    ) {
        self.reconcilableTripID = tripID
        self.reconcilableStopID = stopID
        self.reconcilableStopSequence = stopSequence
        self.scheduledArrivalDate = scheduledArrival
        self.scheduledDepartureDate = scheduledDeparture
    }
}

/// Reconciled result combining a scheduled item with GTFS-RT real-time deviations and cancellations.
public struct GTFSRTReconciledSchedule<Item: GTFSRTReconcilableSchedule> {
    public let item: Item
    public let tripUpdate: GTFSRTTripUpdate?
    public let matchedStopTimeUpdate: GTFSRTStopTimeUpdate?

    public let isCanceled: Bool
    public let isSkipped: Bool
    public let isNoData: Bool

    public let tripScheduleRelationship: GTFSRTTripScheduleRelationship
    public let stopScheduleRelationship: GTFSRTStopTimeScheduleRelationship?

    public let arrivalDelay: Int?
    public let departureDelay: Int?

    public let reconciledArrival: Date?
    public let reconciledDeparture: Date?

    /// True if real-time delay or prediction information is active.
    public var isLive: Bool {
        tripUpdate != nil &&
            !isCanceled &&
            !isSkipped &&
            !isNoData &&
            (reconciledArrival != nil || reconciledDeparture != nil || arrivalDelay != nil || departureDelay != nil)
    }
}

extension GTFSRTReconciledSchedule: Sendable where Item: Sendable {}

// MARK: - Delay Reconciler Helper

/// Reconciles GTFS-RT TripUpdate data with REST models and schedules.
public struct GTFSRealtimeDelayReconciler: Sendable {
    public init() {}

    public static let standard = GTFSRealtimeDelayReconciler()

    private static let serviceDateFormatterUTC: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let serviceDateFormatterCurrent: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Matches a feed trip ID against a REST trip ID, handling optional agency ID prefixes (e.g., "1_12345" vs "12345").
    public static func tripIDsMatch(feedTripID: String, restTripID: String) -> Bool {
        if feedTripID == restTripID { return true }
        if let idx = restTripID.firstIndex(of: "_") {
            let strippedREST = String(restTripID[restTripID.index(after: idx)...])
            if strippedREST == feedTripID { return true }
        }
        if let idx = feedTripID.firstIndex(of: "_") {
            let strippedFeed = String(feedTripID[feedTripID.index(after: idx)...])
            if strippedFeed == restTripID { return true }
        }
        return false
    }

    /// Matches a feed stop ID against a REST stop ID, handling optional agency ID prefixes.
    public static func stopIDsMatch(feedStopID: String?, restStopID: String?) -> Bool {
        guard let feedStopID, let restStopID, !feedStopID.isEmpty, !restStopID.isEmpty else { return false }
        if feedStopID == restStopID { return true }
        if let idx = restStopID.firstIndex(of: "_") {
            let strippedREST = String(restStopID[restStopID.index(after: idx)...])
            if strippedREST == feedStopID { return true }
        }
        if let idx = feedStopID.firstIndex(of: "_") {
            let strippedFeed = String(feedStopID[feedStopID.index(after: idx)...])
            if strippedFeed == restStopID { return true }
        }
        return false
    }

    /// Reconciles an arbitrary `GTFSRTReconcilableSchedule` with an optional matching `GTFSRTTripUpdate`.
    public func reconcile<Schedule: GTFSRTReconcilableSchedule>(
        schedule: Schedule,
        with tripUpdate: GTFSRTTripUpdate?
    ) -> GTFSRTReconciledSchedule<Schedule> {
        guard let tripUpdate else {
            return GTFSRTReconciledSchedule(
                item: schedule,
                tripUpdate: nil,
                matchedStopTimeUpdate: nil,
                isCanceled: false,
                isSkipped: false,
                isNoData: false,
                tripScheduleRelationship: .scheduled,
                stopScheduleRelationship: nil,
                arrivalDelay: nil,
                departureDelay: nil,
                reconciledArrival: nil,
                reconciledDeparture: nil
            )
        }

        let isTripCanceled = tripUpdate.scheduleRelationship.isCanceledOrDeleted
        let matchedStop = findMatchingStopTimeUpdate(for: schedule, in: tripUpdate)
        let isStopSkipped = matchedStop?.scheduleRelationship.isSkipped ?? false
        let isDirectNoData = matchedStop?.scheduleRelationship.isNoData ?? false

        // Determine upstream stop updates for propagation of delay and NO_DATA
        let upstreamUpdates: [GTFSRTStopTimeUpdate]
        if let schedSeq = schedule.reconcilableStopSequence {
            upstreamUpdates = tripUpdate.stopTimeUpdates
                .filter { ($0.stopSequence ?? 0) < UInt32(schedSeq) && $0.stopSequence != nil }
                .sorted { ($0.stopSequence ?? 0) < ($1.stopSequence ?? 0) }
        } else if let matched = matchedStop, let idx = tripUpdate.stopTimeUpdates.firstIndex(where: { $0 == matched }) {
            upstreamUpdates = Array(tripUpdate.stopTimeUpdates[0..<idx])
        } else {
            upstreamUpdates = []
        }

        // Propagate upstream delay and NO_DATA state
        var propagatedDelay: Int? = tripUpdate.tripDelay
        var isUpstreamNoData = false

        for u in upstreamUpdates {
            if u.scheduleRelationship.isNoData {
                isUpstreamNoData = true
                propagatedDelay = nil
            } else if let dep = u.departureDelay {
                isUpstreamNoData = false
                propagatedDelay = dep
            } else if let arr = u.arrivalDelay {
                isUpstreamNoData = false
                propagatedDelay = arr
            }
        }

        // Determine NO_DATA state for this stop
        let isNoData: Bool
        if isTripCanceled {
            isNoData = false
        } else if isDirectNoData {
            isNoData = true
        } else if matchedStop == nil {
            isNoData = isUpstreamNoData
        } else if matchedStop?.departureDelay == nil && matchedStop?.arrivalDelay == nil && matchedStop?.departureTime == nil && matchedStop?.arrivalTime == nil {
            isNoData = isUpstreamNoData
        } else {
            isNoData = false
        }

        let arrDelay: Int?
        let depDelay: Int?
        if isTripCanceled || isStopSkipped || isNoData {
            arrDelay = nil
            depDelay = nil
        } else {
            arrDelay = matchedStop?.arrivalDelay ?? propagatedDelay
            depDelay = matchedStop?.departureDelay ?? matchedStop?.arrivalDelay ?? propagatedDelay
        }

        let recArrival: Date?
        if isTripCanceled || isStopSkipped || isNoData {
            recArrival = nil
        } else if let exactArrival = matchedStop?.arrivalTime {
            recArrival = exactArrival
        } else if let arrDelay, let schedArr = schedule.scheduledArrivalDate {
            recArrival = schedArr.addingTimeInterval(TimeInterval(arrDelay))
        } else {
            recArrival = nil
        }

        let recDeparture: Date?
        if isTripCanceled || isStopSkipped || isNoData {
            recDeparture = nil
        } else if let exactDeparture = matchedStop?.departureTime {
            recDeparture = exactDeparture
        } else if let depDelay, let schedDep = schedule.scheduledDepartureDate {
            recDeparture = schedDep.addingTimeInterval(TimeInterval(depDelay))
        } else {
            recDeparture = nil
        }

        return GTFSRTReconciledSchedule(
            item: schedule,
            tripUpdate: tripUpdate,
            matchedStopTimeUpdate: matchedStop,
            isCanceled: isTripCanceled,
            isSkipped: isStopSkipped,
            isNoData: isNoData,
            tripScheduleRelationship: tripUpdate.scheduleRelationship,
            stopScheduleRelationship: matchedStop?.scheduleRelationship,
            arrivalDelay: arrDelay,
            departureDelay: depDelay,
            reconciledArrival: recArrival,
            reconciledDeparture: recDeparture
        )
    }

    /// Finds matching `GTFSRTStopTimeUpdate` by stop ID or stop sequence, rejecting conflicting sequences.
    public func findMatchingStopTimeUpdate<Schedule: GTFSRTReconcilableSchedule>(
        for schedule: Schedule,
        in tripUpdate: GTFSRTTripUpdate
    ) -> GTFSRTStopTimeUpdate? {
        // 1. If stopID is present, find by stopID while rejecting sequence conflicts
        if let schedStopID = schedule.reconcilableStopID, !schedStopID.isEmpty {
            for update in tripUpdate.stopTimeUpdates {
                guard Self.stopIDsMatch(feedStopID: update.stopID, restStopID: schedStopID) else {
                    continue
                }
                // Reject fallback if both sides provide comparable sequences and they conflict
                if let schedSeq = schedule.reconcilableStopSequence,
                   let updateSeq = update.stopSequence {
                    if UInt32(schedSeq) != updateSeq {
                        continue
                    }
                }
                return update
            }
        }

        // 2. If stopSequence is present on schedule, match by stopSequence
        if let schedSeq = schedule.reconcilableStopSequence {
            if let match = tripUpdate.stopTimeUpdates.first(where: { $0.stopSequence == UInt32(schedSeq) }) {
                if let schedStopID = schedule.reconcilableStopID,
                   let updateStopID = match.stopID,
                   !schedStopID.isEmpty,
                   !updateStopID.isEmpty,
                   !Self.stopIDsMatch(feedStopID: updateStopID, restStopID: schedStopID) {
                    return nil
                }
                return match
            }
        }

        return nil
    }

    /// Reconciles an `ArrivalDeparture` instance with an optional matching `GTFSRTTripUpdate`.
    public func reconcile(
        arrivalDeparture: ArrivalDeparture,
        with tripUpdate: GTFSRTTripUpdate?
    ) -> ReconciledArrivalDeparture {
        reconcile(schedule: arrivalDeparture, with: tripUpdate)
    }

    /// Reconciles an array of `ArrivalDeparture` instances with an array of `GTFSRTTripUpdate` models.
    ///
    /// Matches trip updates by `tripID` (supporting agency prefix differences such as "1_123" vs "123").
    /// If multiple trip updates match the trip ID, matches by `startDate` against the arrival departure's `serviceDate`.
    public func reconcile(
        arrivalDepartures: [ArrivalDeparture],
        with tripUpdates: [GTFSRTTripUpdate]
    ) -> [ReconciledArrivalDeparture] {
        return arrivalDepartures.map { arrDep in
            let matchingUpdates = tripUpdates.filter { update in
                Self.tripIDsMatch(feedTripID: update.tripID, restTripID: arrDep.tripID)
            }
            let selectedUpdate: GTFSRTTripUpdate?
            if matchingUpdates.isEmpty {
                selectedUpdate = nil
            } else if matchingUpdates.count == 1 {
                selectedUpdate = matchingUpdates[0]
            } else {
                let utcDateStr = Self.serviceDateFormatterUTC.string(from: arrDep.serviceDate)
                let curDateStr = Self.serviceDateFormatterCurrent.string(from: arrDep.serviceDate)
                selectedUpdate = matchingUpdates.first { update in
                    guard let startDate = update.startDate else { return false }
                    return startDate == utcDateStr || startDate == curDateStr
                } ?? matchingUpdates[0]
            }
            return reconcile(arrivalDeparture: arrDep, with: selectedUpdate)
        }
    }
}

// MARK: - ArrivalDeparture Extensions

public typealias ReconciledArrivalDeparture = GTFSRTReconciledSchedule<ArrivalDeparture>

extension ArrivalDeparture: GTFSRTReconcilableSchedule {
    public var reconcilableTripID: String { tripID }
    public var reconcilableStopID: String? { stopID }
    public var reconcilableStopSequence: Int? { nil }
    public var scheduledArrivalDate: Date? { scheduledArrival }
    public var scheduledDepartureDate: Date? { scheduledDeparture }

    /// Applies a reconciled update, creating an updated `ArrivalDeparture` instance.
    public func applying(reconciliation: ReconciledArrivalDeparture) -> ArrivalDeparture {
        let updatedPredicted: Bool
        let updatedPredictedArrival: Date?
        let updatedPredictedDeparture: Date?

        if reconciliation.isNoData {
            updatedPredicted = false
            updatedPredictedArrival = nil
            updatedPredictedDeparture = nil
        } else if reconciliation.isLive {
            updatedPredicted = true
            updatedPredictedArrival = reconciliation.reconciledArrival ?? predictedArrival
            updatedPredictedDeparture = reconciliation.reconciledDeparture ?? predictedDeparture
        } else {
            // Unmatched or no live prediction: preserve existing predictions
            updatedPredicted = predicted
            updatedPredictedArrival = predictedArrival
            updatedPredictedDeparture = predictedDeparture
        }

        let updatedStatus: String
        let updatedArrivalEnabled: Bool
        let updatedDepartureEnabled: Bool

        if reconciliation.isCanceled {
            updatedStatus = "canceled"
            updatedArrivalEnabled = arrivalEnabled
            updatedDepartureEnabled = departureEnabled
        } else if reconciliation.isSkipped {
            updatedStatus = "skipped"
            updatedArrivalEnabled = false
            updatedDepartureEnabled = false
        } else if reconciliation.tripUpdate != nil && (status == "canceled" || status == "skipped") {
            updatedStatus = "default"
            updatedArrivalEnabled = true
            updatedDepartureEnabled = true
        } else {
            updatedStatus = status
            updatedArrivalEnabled = arrivalEnabled
            updatedDepartureEnabled = departureEnabled
        }

        return ArrivalDeparture(
            arrivalEnabled: updatedArrivalEnabled,
            blockTripSequence: blockTripSequence,
            departureEnabled: updatedDepartureEnabled,
            distanceFromStop: distanceFromStop,
            frequency: frequency,
            lastUpdated: reconciliation.tripUpdate?.timestamp ?? lastUpdated,
            numberOfStopsAway: numberOfStopsAway,
            predicted: updatedPredicted,
            predictedArrival: updatedPredictedArrival,
            predictedDeparture: updatedPredictedDeparture,
            routeID: routeID,
            route: route,
            routeLongName: _routeLongName,
            routeShortName: _routeShortName,
            scheduledArrival: scheduledArrival,
            scheduledDeparture: scheduledDeparture,
            serviceDate: serviceDate,
            situationIDs: situationIDs,
            serviceAlerts: serviceAlerts,
            status: updatedStatus,
            stopID: stopID,
            stop: stop,
            stopSequence: stopSequence,
            totalStopsInTrip: totalStopsInTrip,
            tripHeadsign: _tripHeadsign,
            tripID: tripID,
            trip: trip,
            tripStatus: tripStatus,
            vehicleID: reconciliation.tripUpdate?.vehicleID ?? vehicleID,
            regionIdentifier: regionIdentifier,
            occupancyStatus: reconciliation.matchedStopTimeUpdate?.departureOccupancyStatus.flatMap(OccupancyStatus.init(protobuf:)) ?? occupancyStatus,
            historicalOccupancyStatus: historicalOccupancyStatus
        )
    }
}

extension GTFSRTReconciledSchedule where Item == ArrivalDeparture {
    public var arrivalDeparture: ArrivalDeparture { item }

    /// Reconciled date for display based on arrival/departure status.
    public var reconciledDate: Date {
        if isNoData {
            switch item.arrivalDepartureStatus {
            case .arriving:
                return item.scheduledArrival
            case .departing:
                return item.scheduledDeparture
            }
        }
        if isLive {
            switch item.arrivalDepartureStatus {
            case .arriving:
                return reconciledArrival ?? item.arrivalDepartureDate
            case .departing:
                return reconciledDeparture ?? item.arrivalDepartureDate
            }
        }
        return item.arrivalDepartureDate
    }

    /// Evaluates the real-time schedule deviation into an early, onTime, or delayed status.
    public var scheduleStatus: ScheduleStatus {
        guard isLive else {
            return item.scheduleStatus
        }
        let deviationSeconds: TimeInterval
        switch item.arrivalDepartureStatus {
        case .arriving:
            if let recArr = reconciledArrival {
                deviationSeconds = recArr.timeIntervalSince(item.scheduledArrival)
            } else if let arrDelay = arrivalDelay ?? departureDelay {
                deviationSeconds = TimeInterval(arrDelay)
            } else {
                return item.scheduleStatus
            }
        case .departing:
            if let recDep = reconciledDeparture {
                deviationSeconds = recDep.timeIntervalSince(item.scheduledDeparture)
            } else if let depDelay = departureDelay ?? arrivalDelay {
                deviationSeconds = TimeInterval(depDelay)
            } else {
                return item.scheduleStatus
            }
        }
        let minutesDiff = deviationSeconds / 60.0
        if minutesDiff < -1.5 {
            return .early
        } else if minutesDiff < 1.5 {
            return .onTime
        } else {
            return .delayed
        }
    }
}

// MARK: - ScheduleForStop Extensions

extension ScheduleForStop.StopScheduleStopTime: GTFSRTReconcilableSchedule {
    public var reconcilableTripID: String { tripID }
    public var reconcilableStopID: String? { nil }
    public var reconcilableStopSequence: Int? { nil }
    public var scheduledArrivalDate: Date? { arrivalDate }
    public var scheduledDepartureDate: Date? { departureDate }
}

// MARK: - OccupancyStatus Protobuf Mapping

extension ArrivalDeparture.OccupancyStatus {
    public init?(protobuf: TransitRealtime_VehiclePosition.OccupancyStatus) {
        switch protobuf {
        case .empty: self = .empty
        case .manySeatsAvailable: self = .manySeatsAvailable
        case .fewSeatsAvailable: self = .fewSeatsAvailable
        case .standingRoomOnly: self = .standingRoomOnly
        case .crushedStandingRoomOnly: self = .crushedStandingRoomOnly
        case .full: self = .full
        case .notAcceptingPassengers: self = .notAcceptingPassengers
        case .noDataAvailable: self = .noDataAvailable
        case .notBoardable: self = .notBoardable
        }
    }
}
