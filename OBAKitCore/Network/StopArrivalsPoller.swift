//
//  StopArrivalsPoller.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Scene phase representation for poller lifecycle coordination.
public enum PollerScenePhase: Sendable, Equatable {
    case active
    case inactive
    case background

    public var isForeground: Bool {
        self == .active
    }
}

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

    /// Emits immediately, then after every `interval` (adapted for Low Power Mode)
    /// measured on `clock`, pausing when inactive/backgrounded, and refreshing
    /// immediately when `refreshSignal` emits, until the consumer stops iterating.
    public func arrivals(
        for stopID: StopID,
        every interval: Duration,
        using apiService: RESTAPIService,
        clock: some Clock<Duration>,
        powerStateProvider: @escaping @Sendable () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled },
        lowPowerMultiplier: Double = 2.0,
        scenePhaseStream: AsyncStream<PollerScenePhase>? = nil,
        refreshSignal: AsyncStream<Void>? = nil,
        notificationCenter: NotificationCenter = .default
    ) -> AsyncStream<Result<[ArrivalDeparture], Error>> {
        let loader = BookmarkArrivalsLoader(minutesAfter: minutesAfter)
        let request = BookmarkArrivalsRequest(stopID: stopID)

        let (stream, continuation) = AsyncStream<Result<[ArrivalDeparture], Error>>.makeStream()

        let coordinator = PollerCoordinator(
            initialForeground: true,
            isLowPower: powerStateProvider()
        )

        let task = Task {
            let (powerChanges, powerChangeContinuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
            let observer = notificationCenter.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: nil) { _ in
                powerChangeContinuation.yield()
            }
            defer { notificationCenter.removeObserver(observer) }

            let subtasks = Task {
                await withTaskGroup(of: Void.self) { group in
                    if let scenePhaseStream {
                        group.addTask {
                            for await phase in scenePhaseStream {
                                await coordinator.setScenePhase(phase.isForeground)
                            }
                        }
                    }
                    if let refreshSignal {
                        group.addTask {
                            for await _ in refreshSignal {
                                await coordinator.triggerRefresh()
                            }
                        }
                    }
                    group.addTask {
                        for await _ in powerChanges {
                            await coordinator.setLowPower(powerStateProvider())
                        }
                    }
                }
            }
            defer { subtasks.cancel() }

            while !Task.isCancelled {
                do {
                    try await coordinator.waitUntilActive()
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }

                for await (_, result) in loader.arrivals(for: [request], using: apiService) {
                    guard !Task.isCancelled else { break }
                    continuation.yield(result.map { request.matching($0) })
                }

                guard !Task.isCancelled else { break }

                do {
                    let isLowPower = await coordinator.currentLowPower()
                    let effectiveInterval = isLowPower ? (interval * lowPowerMultiplier) : interval
                    try await coordinator.sleep(for: effectiveInterval, clock: clock)
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

// MARK: - PollerCoordinator

private actor PollerCoordinator {
    private var isForeground: Bool
    private var isLowPower: Bool
    private var refreshTriggered: Bool = false
    private let wakeContinuation: AsyncStream<Void>.Continuation
    private let wakeStream: AsyncStream<Void>

    init(initialForeground: Bool = true, isLowPower: Bool = false) {
        self.isForeground = initialForeground
        self.isLowPower = isLowPower
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.wakeStream = stream
        self.wakeContinuation = continuation
    }

    func setScenePhase(_ isForeground: Bool) {
        let old = self.isForeground
        self.isForeground = isForeground
        if !old && isForeground {
            wakeContinuation.yield()
        } else if old && !isForeground {
            wakeContinuation.yield()
        }
    }

    func triggerRefresh() {
        refreshTriggered = true
        wakeContinuation.yield()
    }

    func setLowPower(_ lowPower: Bool) {
        if isLowPower != lowPower {
            isLowPower = lowPower
            wakeContinuation.yield()
        }
    }

    func currentLowPower() -> Bool {
        isLowPower
    }

    func waitUntilActive() async throws {
        if isForeground {
            return
        }
        for await _ in wakeStream {
            try Task.checkCancellation()
            if isForeground {
                return
            }
        }
    }

    func sleep(for interval: Duration, clock: some Clock<Duration>) async throws {
        if refreshTriggered {
            refreshTriggered = false
            return
        }

        let stream = wakeStream
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await clock.sleep(for: interval)
            }
            group.addTask {
                for await _ in stream {
                    return
                }
            }

            try await group.next()
            group.cancelAll()
        }

        refreshTriggered = false
    }
}
