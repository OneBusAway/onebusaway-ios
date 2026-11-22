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
public enum GTFSRealtimeError: Error, Sendable, LocalizedError {
    case emptyData
    case malformedData(any Error & Sendable)
    case unsupportedIncrementality(TransitRealtime_FeedHeader.Incrementality)
    case staleFeed(timestamp: Date, age: TimeInterval)
    case futureFeed(timestamp: Date, aheadBy: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .emptyData:
            return OBALoc(
                "gtfs_realtime.error.empty_data",
                value: "GTFS-Realtime feed payload is empty.",
                comment: "Error message when feed payload contains zero bytes."
            )
        case .malformedData(let error):
            let format = OBALoc(
                "gtfs_realtime.error.malformed_data_fmt",
                value: "Failed to parse GTFS-Realtime Protobuf message: %@",
                comment: "Error message when feed payload cannot be decoded as protobuf. %@ is the error description."
            )
            return String(format: format, error.localizedDescription)
        case .unsupportedIncrementality(let mode):
            let format = OBALoc(
                "gtfs_realtime.error.unsupported_incrementality_fmt",
                value: "Unsupported GTFS-Realtime incrementality mode: %@.",
                comment: "Error message when feed uses unsupported incrementality like differential. %@ is the mode name."
            )
            return String(format: format, String(describing: mode))
        case .staleFeed(let timestamp, let age):
            let format = OBALoc(
                "gtfs_realtime.error.stale_feed_fmt",
                value: "GTFS-Realtime feed is stale (timestamp: %1$@, age: %2$@).",
                comment: "Error message when feed timestamp is older than allowed staleness threshold. %1$@ is formatted date, %2$@ is duration."
            )
            let dateStr = timestamp.formatted(.iso8601)
            let ageStr = Self.formatDuration(age)
            return String(format: format, dateStr, ageStr)
        case .futureFeed(let timestamp, let aheadBy):
            let format = OBALoc(
                "gtfs_realtime.error.future_feed_fmt",
                value: "GTFS-Realtime feed timestamp is too far in the future (timestamp: %1$@, ahead by: %2$@).",
                comment: "Error message when feed timestamp exceeds allowable future clock skew. %1$@ is formatted date, %2$@ is duration."
            )
            let dateStr = timestamp.formatted(.iso8601)
            let aheadStr = Self.formatDuration(aheadBy)
            return String(format: format, dateStr, aheadStr)
        }
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        guard duration.isFinite else { return "—" }
        return String(format: "%.0fs", max(0, duration))
    }
}

extension GTFSRealtimeError: Equatable {
    public static func == (lhs: GTFSRealtimeError, rhs: GTFSRealtimeError) -> Bool {
        switch (lhs, rhs) {
        case (.emptyData, .emptyData):
            return true
        case (.unsupportedIncrementality(let l), .unsupportedIncrementality(let r)):
            return l == r
        case (.staleFeed(let lDate, let lAge), .staleFeed(let rDate, let rAge)):
            return lDate == rDate && lAge == rAge
        case (.futureFeed(let lDate, let lAhead), .futureFeed(let rDate, let rAhead)):
            return lDate == rDate && lAhead == rAhead
        case (.malformedData(let lErr), .malformedData(let rErr)):
            return (lErr as NSError) == (rErr as NSError) || String(describing: lErr) == String(describing: rErr)
        default:
            return false
        }
    }
}

/// Unified decoder and header validator for GTFS-Realtime Protobuf feeds.
///
/// Validates Protobuf structure, feed incrementality (rejecting unsupported `.differential` feeds),
/// and timestamp staleness / future drift when configured.
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
        maxFutureTolerance: TimeInterval? = nil,
        allowedIncrementalities: Set<TransitRealtime_FeedHeader.Incrementality> = [.fullDataset]
    ) {
        self.maxStaleness = maxStaleness
        self.maxFutureTolerance = maxFutureTolerance
        self.allowedIncrementalities = allowedIncrementalities
    }

    /// Default parser with standard validation rules. Validates Protobuf structure and incrementality only;
    /// does not reject feeds on clock skew.
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
            throw GTFSRealtimeError.malformedData(error)
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
            } else if age < 0 {
                let skewSeconds = String(format: "%.1f", -age)
                Logger.warn("GTFSRealtimeFeedParser: feed timestamp \(feedDate) is in the future relative to device clock (skew: \(skewSeconds)s)")
            }
        }
    }
}
