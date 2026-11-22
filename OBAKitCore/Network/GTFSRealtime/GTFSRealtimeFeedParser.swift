//
//  GTFSRealtimeFeedParser.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import SwiftProtobuf

/// Errors encountered when decoding and validating GTFS-Realtime feeds.
public enum GTFSRealtimeError: Error, Sendable, Equatable, LocalizedError {
    case emptyData
    case malformedData(String)
    case unsupportedIncrementality(TransitRealtime_FeedHeader.Incrementality)
    case staleFeed(timestamp: Date, age: TimeInterval)
    case futureFeed(timestamp: Date, aheadBy: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .emptyData:
            return "GTFS-Realtime feed payload is empty."
        case .malformedData(let details):
            return "Failed to parse GTFS-Realtime Protobuf message: \(details)"
        case .unsupportedIncrementality(let mode):
            return "Unsupported GTFS-Realtime incrementality mode: \(mode)."
        case .staleFeed(let timestamp, let age):
            return "GTFS-Realtime feed is stale (timestamp: \(timestamp), age: \(Int(age))s)."
        case .futureFeed(let timestamp, let aheadBy):
            return "GTFS-Realtime feed timestamp is too far in the future (timestamp: \(timestamp), ahead by: \(Int(aheadBy))s)."
        }
    }
}

/// Unified decoder and header validator for GTFS-Realtime Protobuf feeds.
///
/// Validates Protobuf structure, feed incrementality (rejecting unsupported `.differential` feeds),
/// and timestamp staleness / future drift.
public struct GTFSRealtimeFeedParser: Sendable {

    /// Maximum permitted age in seconds before a feed is rejected as stale.
    /// `nil` disables staleness checking.
    public let maxStaleness: TimeInterval?

    /// Maximum permitted future time difference in seconds before a feed is rejected as having invalid clock skew.
    /// `nil` disables future clock skew checking.
    public let maxFutureTolerance: TimeInterval?

    /// Set of permitted incrementality modes. Defaults to `[.fullDataset]` because `.differential` is unsupported.
    public let allowedIncrementalities: Set<TransitRealtime_FeedHeader.Incrementality>

    public init(
        maxStaleness: TimeInterval? = nil,
        maxFutureTolerance: TimeInterval? = 300,
        allowedIncrementalities: Set<TransitRealtime_FeedHeader.Incrementality> = [.fullDataset]
    ) {
        self.maxStaleness = maxStaleness
        self.maxFutureTolerance = maxFutureTolerance
        self.allowedIncrementalities = allowedIncrementalities
    }

    /// Default parser with standard validation rules.
    public static let standard = GTFSRealtimeFeedParser()

    /// Deserializes raw Protobuf data and validates the feed header.
    /// - Parameters:
    ///   - data: Raw Protobuf binary data.
    ///   - referenceDate: Reference time used for staleness and future timestamp validation (defaults to `Date()`).
    /// - Returns: A decoded, validated `TransitRealtime_FeedMessage`.
    /// - Throws: `GTFSRealtimeError` if data is empty, malformed, incremental, or stale.
    public func parse(
        data: Data,
        referenceDate: Date = Date()
    ) throws -> TransitRealtime_FeedMessage {
        guard !data.isEmpty else {
            throw GTFSRealtimeError.emptyData
        }

        let message: TransitRealtime_FeedMessage
        do {
            message = try TransitRealtime_FeedMessage(serializedBytes: data)
        } catch {
            throw GTFSRealtimeError.malformedData(error.localizedDescription)
        }

        try validateHeader(message.header, referenceDate: referenceDate)
        return message
    }

    /// Validates a `TransitRealtime_FeedHeader` against incrementality and timestamp constraints.
    public func validateHeader(
        _ header: TransitRealtime_FeedHeader,
        referenceDate: Date = Date()
    ) throws {
        if header.hasIncrementality {
            guard allowedIncrementalities.contains(header.incrementality) else {
                throw GTFSRealtimeError.unsupportedIncrementality(header.incrementality)
            }
        }

        if header.hasTimestamp && header.timestamp > 0 {
            let feedDate = Date(timeIntervalSince1970: TimeInterval(header.timestamp))
            let age = referenceDate.timeIntervalSince(feedDate)

            if let maxStaleness, age > maxStaleness {
                throw GTFSRealtimeError.staleFeed(timestamp: feedDate, age: age)
            }

            if let maxFutureTolerance, age < -maxFutureTolerance {
                throw GTFSRealtimeError.futureFeed(timestamp: feedDate, aheadBy: -age)
            }
        }
    }

    /// Parses feed message and returns all valid alert entities.
    public func parseAlertEntities(data: Data, referenceDate: Date = Date()) throws -> [TransitRealtime_FeedEntity] {
        let message = try parse(data: data, referenceDate: referenceDate)
        return message.entity.filter { $0.hasAlert }
    }

    /// Parses feed message and returns all valid vehicle position entities.
    public func parseVehicleEntities(data: Data, referenceDate: Date = Date()) throws -> [TransitRealtime_FeedEntity] {
        let message = try parse(data: data, referenceDate: referenceDate)
        return message.entity.filter { $0.hasVehicle }
    }

    /// Parses feed message and returns all valid trip update entities.
    public func parseTripUpdateEntities(data: Data, referenceDate: Date = Date()) throws -> [TransitRealtime_FeedEntity] {
        let message = try parse(data: data, referenceDate: referenceDate)
        return message.entity.filter { $0.hasTripUpdate }
    }
}
