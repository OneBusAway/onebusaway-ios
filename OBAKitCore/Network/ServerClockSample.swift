//
//  ServerClockSample.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// What time the server thought it was, paired with when the device received the
/// answer. Vehicle position estimation measures how old a fix is against the
/// device clock, and uses these to correct that clock for skew.
public struct ServerClockSample: Sendable, Equatable {
    /// The envelope's `currentTime`, advanced by the response's `Age` header: a
    /// response served from a cache was generated that long before it arrived.
    /// maglev marks its realtime endpoints `max-age=30`.
    public let serverTime: Date

    /// Device time when the response arrived.
    public let receivedAt: Date

    public init(serverTime: Date, receivedAt: Date) {
        self.serverTime = serverTime
        self.receivedAt = receivedAt
    }

    /// - Parameters:
    ///   - currentTime: The envelope's epoch milliseconds. `nil` or `0` yields no sample.
    ///   - age: The `Age` header, in whole seconds. Absent or malformed counts as zero.
    public init?(currentTime: Int64?, age: String?, receivedAt: Date) {
        guard let currentTime, currentTime > 0 else { return nil }
        let ageSeconds = age.flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) }.map { max($0, 0) } ?? 0
        self.serverTime = Date(timeIntervalSince1970: TimeInterval(currentTime) / 1000 + ageSeconds)
        self.receivedAt = receivedAt
    }

    /// `receivedAt − serverTime`: positive when the device clock runs ahead of the server's.
    public var deviceOffset: TimeInterval {
        receivedAt.timeIntervalSince(serverTime)
    }
}
