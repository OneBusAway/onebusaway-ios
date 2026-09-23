//
//  StopArrivalsPoller.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Upcoming departures for one stop, refetched on a fixed cadence for as long
/// as the consumer keeps reading. The watch's stop screen runs one while the
/// scene is active and cancels it when the scene leaves the foreground.
///
/// A fetch failure is delivered as a `.failure` value, never thrown, so one
/// bad tick does not end the stream — the same convention as
/// `BookmarkArrivalsLoader`, which does the fetching. The consumer keeps its
/// last good value.
public struct StopArrivalsPoller: Sendable {
    private let minutesAfter: UInt

    public init(minutesAfter: UInt = 60) {
        self.minutesAfter = minutesAfter
    }

    /// Emits immediately, then after every `interval` measured on `clock`,
    /// until the consumer stops iterating.
    public func arrivals(
        for stopID: StopID,
        every interval: Duration,
        using apiService: RESTAPIService,
        clock: some Clock<Duration>
    ) -> AsyncStream<Result<[ArrivalDeparture], Error>> {
        let loader = BookmarkArrivalsLoader(minutesAfter: minutesAfter)
        let request = BookmarkArrivalsRequest(stopID: stopID)

        let (stream, continuation) = AsyncStream<Result<[ArrivalDeparture], Error>>.makeStream()

        let task = Task {
            while !Task.isCancelled {
                for await (_, result) in loader.arrivals(for: [request], using: apiService) {
                    continuation.yield(result.map { request.matching($0) })
                }

                do {
                    try await clock.sleep(for: interval)
                } catch {
                    break
                }
            }
            continuation.finish()
        }

        continuation.onTermination = { _ in task.cancel() }

        return stream
    }
}
