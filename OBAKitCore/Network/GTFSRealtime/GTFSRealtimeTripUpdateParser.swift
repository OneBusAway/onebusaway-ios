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
