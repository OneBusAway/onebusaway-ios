//
//  StopArrivalsPoller.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Scene lifecycle phases for adapting poller cadence.
public enum PollerScenePhase: Sendable {
    case active
    case inactive
    case background

    var isForeground: Bool {
        switch self {
        case .active:
            return true
        case .inactive, .background:
            return false
        }
    }
}

/// A periodic arrivals stream for a single stop, built atop `BookmarkArrivalsLoader`.
///
/// Designed to drive a stop details screen: emits an initial fetch immediately on subscription,
/// then fetches again on every tick of `clock`.
///
/// Supports power-aware and lifecycle-adaptive polling:
/// - Scales cadence interval by `lowPowerMultiplier` when Low Power Mode is active.
/// - Pauses polling when the scene transitions to background and resumes with an immediate fetch on foregrounding.
/// - Supports an external pull-to-refresh signal to trigger an immediate fetch without waiting for the timer.
public struct StopArrivalsPoller: Sendable {

    public let minutesAfter: UInt

    /// Test-only hook, called with the coordinator `arrivals(for:...)` creates.
    /// A test can use it to observe the coordinator the poller actually built —
    /// for example, waiting for it to reach its background wait — without
    /// bypassing the `initialScenePhase` seeding the coordinator is created
    /// with. Production code never sets it.
    var onCoordinatorCreated: (@Sendable (PollerCoordinator) -> Void)?

    public init(minutesAfter: UInt = 60) {
        self.minutesAfter = minutesAfter
        self.onCoordinatorCreated = nil
    }

    /// Returns an `AsyncStream` delivering arrivals updates on every tick of `clock`.
    ///
    /// `initialScenePhase` seeds the coordinator so a poll started while
    /// backgrounded begins paused instead of racing the first forwarded phase
    /// value and fetching once while backgrounded.
    ///
    /// Pass fresh `scenePhaseStream` / `refreshSignal` streams on every call:
    /// cancelling the poller ends the iteration of the streams it was given,
    /// and an `AsyncStream` whose iteration was cancelled cannot be iterated
    /// again, so a stream must never be reused across a retry().
    public func arrivals(
        for stopID: StopID,
        every interval: Duration,
        using apiService: RESTAPIService,
        clock: any Clock<Duration> & Sendable = ContinuousClock(),
        powerStateProvider: @escaping @Sendable () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled },
        lowPowerMultiplier: Double = 2.0,
        scenePhaseStream: AsyncStream<PollerScenePhase>? = nil,
        refreshSignal: AsyncStream<Void>? = nil,
        notificationCenter: NotificationCenter = .default,
        initialScenePhase: PollerScenePhase = .active
    ) -> AsyncStream<Result<[ArrivalDeparture], Error>> {
        let coordinator = PollerCoordinator(
            initialForeground: initialScenePhase.isForeground,
            isLowPower: powerStateProvider()
        )
        onCoordinatorCreated?(coordinator)
        return arrivals(
            for: stopID,
            every: interval,
            using: apiService,
            clock: clock,
            powerStateProvider: powerStateProvider,
            lowPowerMultiplier: lowPowerMultiplier,
            scenePhaseStream: scenePhaseStream,
            refreshSignal: refreshSignal,
            notificationCenter: notificationCenter,
            coordinator: coordinator
        )
    }

    func arrivals(
        for stopID: StopID,
        every interval: Duration,
        using apiService: RESTAPIService,
        clock: any Clock<Duration> & Sendable,
        powerStateProvider: @escaping @Sendable () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled },
        lowPowerMultiplier: Double = 2.0,
        scenePhaseStream: AsyncStream<PollerScenePhase>? = nil,
        refreshSignal: AsyncStream<Void>? = nil,
        notificationCenter: NotificationCenter = .default,
        coordinator: PollerCoordinator
    ) -> AsyncStream<Result<[ArrivalDeparture], Error>> {
        let loader = BookmarkArrivalsLoader(minutesAfter: minutesAfter)
        let request = BookmarkArrivalsRequest(stopID: stopID)

        let (stream, continuation) = AsyncStream<Result<[ArrivalDeparture], Error>>.makeStream()

        let task = Task {
            let (powerChanges, powerChangeContinuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
            let observer = notificationCenter.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: nil) { _ in
                powerChangeContinuation.yield()
            }
            defer { notificationCenter.removeObserver(observer) }

            // The subtasks iterate the caller's streams directly. The bridging
            // layer this replaced added no protection: cancelling the poller
            // ends the iteration of the streams it was given either way, so
            // callers must still pass fresh streams per call (see
            // arrivals(for:)). Iterating directly behaves the same with
            // less code.
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

actor PollerCoordinator {
    private var isForeground: Bool
    private var isLowPower: Bool
    private var refreshTriggered: Bool = false
    private var wakeGeneration: UInt64 = 0
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    /// Whether the poll started in the foreground, as seeded at creation.
    /// Immutable after creation, so a test can assert the seeding even after
    /// later phase changes — unlike `isForeground`, which the scene-phase
    /// stream may already have flipped.
    let initialForeground: Bool

    init(initialForeground: Bool = true, isLowPower: Bool = false) {
        self.isForeground = initialForeground
        self.isLowPower = isLowPower
        self.initialForeground = initialForeground
    }

    var waiterCount: Int {
        waiters.count
    }

    func waitForWaiters(count target: Int) async {
        while waiters.count < target {
            await Task.yield()
        }
    }

    func setScenePhase(_ isForeground: Bool) {
        let changed = self.isForeground != isForeground
        self.isForeground = isForeground
        if changed {
            wakeAll()
        }
    }

    func triggerRefresh() {
        refreshTriggered = true
        wakeAll()
    }

    func setLowPower(_ lowPower: Bool) {
        // Update power state without waking running sleep to avoid triggering an immediate
        // network fetch when entering Low Power Mode; the new cadence multiplier applies on the next interval.
        isLowPower = lowPower
    }

    func currentLowPower() -> Bool {
        isLowPower
    }

    private func wakeAll() {
        wakeGeneration &+= 1
        let currentWaiters = waiters
        waiters.removeAll()
        for (_, continuation) in currentWaiters {
            continuation.resume()
        }
    }

    func waitForWake(after generation: UInt64) async {
        if self.wakeGeneration != generation {
            return
        }
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled || self.wakeGeneration != generation {
                    continuation.resume()
                } else {
                    waiters[id] = continuation
                }
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(id: id)
            }
        }
    }

    private func cancelWaiter(id: UUID) {
        if let cont = waiters.removeValue(forKey: id) {
            cont.resume()
        }
    }

    func waitUntilActive() async throws {
        while !isForeground {
            try Task.checkCancellation()
            let generation = wakeGeneration
            await waitForWake(after: generation)
        }
        // A refresh that arrived while backgrounded is consumed by the fetch
        // that follows immediately: clear it here so sleep() doesn't see the
        // stale flag and fetch a second time.
        refreshTriggered = false
    }

    func sleep(for interval: Duration, clock: any Clock<Duration> & Sendable) async throws {
        if refreshTriggered {
            refreshTriggered = false
            return
        }

        let generation = self.wakeGeneration

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await clock.sleep(for: interval)
            }
            group.addTask {
                await self.waitForWake(after: generation)
            }

            try await group.next()
            group.cancelAll()
        }

        refreshTriggered = false
    }
}
