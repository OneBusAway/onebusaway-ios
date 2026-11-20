//
//  NearbyRoutesModel.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Observation

/// Cadence policy governing active, low-power, and offline polling intervals.
public struct NearbyPollingCadencePolicy: Sendable, Equatable {
    public var activeInterval: Duration
    public var lowPowerInterval: Duration
    public var offlineInterval: Duration

    public static let standard = NearbyPollingCadencePolicy(
        activeInterval: .seconds(60),
        lowPowerInterval: .seconds(180),
        offlineInterval: .seconds(60)
    )

    public init(
        activeInterval: Duration = .seconds(60),
        lowPowerInterval: Duration = .seconds(180),
        offlineInterval: Duration = .seconds(60)
    ) {
        self.activeInterval = activeInterval
        self.lowPowerInterval = lowPowerInterval
        self.offlineInterval = offlineInterval
    }

    public func interval(isLowPower: Bool, isOffline: Bool) -> Duration {
        if isOffline {
            return offlineInterval
        }
        return isLowPower ? lowPowerInterval : activeInterval
    }
}

/// Drives the Nearby screen: one location fix → region check → nearby stops'
/// arrivals → route directions.
///
/// Power-aware polling: automatically adjusts cadence when low power mode is active,
/// backs off on offline/network errors, and cancels polling completely when inactive.
@MainActor
@Observable
public final class NearbyRoutesModel {
    public enum Phase: Equatable {
        case awaitingAuthorization
        case locationDenied
        case locating
        case loading
        case noRegion
        case failed(String)
        case empty
        case loaded([NearbyRouteDirection])
    }

    public typealias LocationRequester = @MainActor () async throws -> CLLocation
    public typealias AuthorizationProvider = @MainActor () -> CLAuthorizationStatus
    public typealias AuthorizationRequester = @MainActor () -> Void
    public typealias RegionChecker = @MainActor () -> Bool
    public typealias APIServiceProvider = @MainActor () -> RESTAPIService?
    public typealias DirectionsLoader = @MainActor (CLLocation, RESTAPIService) async throws -> [NearbyRouteDirection]
    public typealias PowerStateProvider = @MainActor () -> Bool

    public private(set) var phase: Phase
    /// The fix the current list was built around; the route screen measures
    /// stop distances from it.
    public private(set) var origin: CLLocation?
    /// When the loaded list's arrivals were fetched; the route screen's
    /// "Updated at" until its first poll lands.
    public private(set) var loadedAt: Date?
    /// True when a background refresh failed while a previous list was showing.
    public private(set) var isStale = false

    /// The API service used to fetch the current `directions` snapshot, if any.
    public private(set) var apiService: RESTAPIService?

    public var isPolling: Bool { pollTask != nil }

    @ObservationIgnored private let authorizationProvider: AuthorizationProvider
    @ObservationIgnored private let requestAuthorizationAction: AuthorizationRequester
    @ObservationIgnored private let locationRequester: LocationRequester
    @ObservationIgnored private let hasRegion: RegionChecker
    @ObservationIgnored private let apiServiceProvider: APIServiceProvider
    @ObservationIgnored private let directionsLoader: DirectionsLoader
    @ObservationIgnored private let powerStateProvider: PowerStateProvider
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored public let cadencePolicy: NearbyPollingCadencePolicy

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var isLastRefreshOffline = false
    @ObservationIgnored private var currentRefreshID = 0

    public init(
        authorizationProvider: @escaping AuthorizationProvider,
        requestAuthorization: @escaping AuthorizationRequester,
        locationRequester: @escaping LocationRequester,
        hasRegion: @escaping RegionChecker,
        apiServiceProvider: @escaping APIServiceProvider,
        directionsLoader: @escaping DirectionsLoader = { origin, apiService in
            try await NearbyRoutesLoader().directions(near: origin, using: apiService)
        },
        cadencePolicy: NearbyPollingCadencePolicy = .standard,
        powerStateProvider: @escaping PowerStateProvider = { ProcessInfo.processInfo.isLowPowerModeEnabled },
        clock: any Clock<Duration> = ContinuousClock(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.authorizationProvider = authorizationProvider
        self.requestAuthorizationAction = requestAuthorization
        self.locationRequester = locationRequester
        self.hasRegion = hasRegion
        self.apiServiceProvider = apiServiceProvider
        self.directionsLoader = directionsLoader
        self.cadencePolicy = cadencePolicy
        self.powerStateProvider = powerStateProvider
        self.clock = clock
        self.notificationCenter = notificationCenter
        self.phase = .locating
    }

    /// For previews and tests: a fixed phase, no services.
    public init(phase: Phase, origin: CLLocation? = nil, isStale: Bool = false, apiService: RESTAPIService? = nil) {
        self.authorizationProvider = { .authorizedWhenInUse }
        self.requestAuthorizationAction = {}
        self.locationRequester = { origin ?? CLLocation(latitude: 47.6097, longitude: -122.3378) }
        self.hasRegion = { true }
        self.apiServiceProvider = { apiService }
        self.directionsLoader = { _, _ in [] }
        self.cadencePolicy = .standard
        self.powerStateProvider = { false }
        self.clock = ContinuousClock()
        self.notificationCenter = .default
        self.phase = phase
        self.origin = origin
        self.loadedAt = Date()
        self.isStale = isStale
        self.apiService = apiService
    }

    /// The loaded directions, or none.
    public var directions: [NearbyRouteDirection] {
        if case .loaded(let directions) = phase { return directions }
        return []
    }

    public func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            await self?.runPollingLoop(userInitiated: false)
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Re-requests location and reloads. If a poll is running, restarts it
    /// to immediately fetch and reset the cadence timer.
    public func refresh() {
        if pollTask != nil {
            pollTask?.cancel()
            pollTask = Task { [weak self] in
                await self?.runPollingLoop(userInitiated: true)
            }
        } else {
            refreshTask?.cancel()
            refreshTask = Task { [weak self] in
                await self?.performRefresh(userInitiated: true)
            }
        }
    }

    /// Only the first pass can be user-initiated; the passes after it are
    /// background polls.
    private func runPollingLoop(userInitiated: Bool) async {
        var userInitiated = userInitiated
        while !Task.isCancelled {
            await performRefresh(userInitiated: userInitiated)
            userInitiated = false
            guard !Task.isCancelled else { break }

            do {
                try await sleepForCadence()
            } catch {
                break
            }
        }
    }

    /// Sleeps until the cadence interval has passed since the sleep began. A
    /// Low Power Mode change re-reads the interval against that same start, so
    /// turning it off doesn't leave a 180s wait running. Throws when cancelled.
    private func sleepForCadence() async throws {
        let stopwatch = clock.stopwatch()
        while true {
            let interval = cadencePolicy.interval(isLowPower: powerStateProvider(), isOffline: isLastRefreshOffline)
            guard interval > stopwatch.elapsed() else { return }
            guard try await sleep(untilElapsed: interval, on: stopwatch) == .powerStateChanged else { return }
        }
    }

    private enum SleepOutcome: Sendable {
        case finished, powerStateChanged
    }

    private func sleep(untilElapsed interval: Duration, on stopwatch: Stopwatch) async throws -> SleepOutcome {
        // Observe before sleeping, so a change can't land between the two.
        let (changes, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let observer = notificationCenter.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: nil) { _ in
            continuation.yield()
        }
        defer { notificationCenter.removeObserver(observer) }

        return try await withThrowingTaskGroup(of: SleepOutcome.self) { group in
            group.addTask {
                try await stopwatch.sleepUntilElapsed(interval)
                return .finished
            }
            group.addTask {
                for await _ in changes {
                    return .powerStateChanged
                }
                throw CancellationError()
            }
            defer { group.cancelAll() }
            return try await group.next() ?? .finished
        }
    }

    /// Shows a progress phase, except over a loaded list. A background poll
    /// also keeps the empty, failed and no-region screens until the new result
    /// lands; only a user-initiated refresh shows progress over them.
    private func showProgress(_ progress: Phase, userInitiated: Bool) {
        switch phase {
        case .loaded:
            return
        case .empty, .failed, .noRegion:
            guard userInitiated else { return }
        default:
            break
        }
        phase = progress
    }

    public func performRefresh(userInitiated: Bool = true) async {
        guard !Task.isCancelled else { return }

        currentRefreshID += 1
        let refreshID = currentRefreshID

        guard ensureAuthorized() else { return }

        showProgress(.locating, userInitiated: userInitiated)

        let fix: CLLocation
        do {
            fix = try await locationRequester()
        } catch {
            handleLocationError(error, refreshID: refreshID)
            return
        }

        guard !Task.isCancelled, currentRefreshID == refreshID else { return }

        // `currentRegion` keeps the previous launch's region when a fix lands
        // outside every region, so the rule keys off where the watch *is*.
        guard hasRegion() else {
            phase = .noRegion
            return
        }

        // The fix above set currentLocation → RegionsService selected the
        // region → StandaloneAPIServiceProvider rebuilt the service, all
        // synchronously on the main actor; the host reads the provider directly.
        guard let apiService = apiServiceProvider() else {
            phase = .noRegion
            return
        }

        await loadDirections(near: fix, using: apiService, userInitiated: userInitiated, refreshID: refreshID)
    }

    private func ensureAuthorized() -> Bool {
        switch authorizationProvider() {
        case .notDetermined:
            phase = .awaitingAuthorization
            isStale = false
            requestAuthorizationAction()
            return false
        case .denied, .restricted:
            phase = .locationDenied
            isStale = false
            return false
        default:
            return true
        }
    }

    private func handleLocationError(_ error: Error, refreshID: Int) {
        guard !Task.isCancelled, currentRefreshID == refreshID else { return }
        if error is LocationServiceError {
            phase = .locationDenied
            isStale = false
        } else {
            let isOffline = ErrorClassifier.category(for: error) == .offline
            isLastRefreshOffline = isOffline
            if case .loaded = phase, isOffline {
                // Retain loaded state when offline during background poll
                isStale = true
            } else if isOffline {
                phase = .failed(Strings.nearbyOffline)
            } else {
                phase = .failed(Strings.locationFailed)
            }
        }
    }

    private func loadDirections(near fix: CLLocation, using apiService: RESTAPIService, userInitiated: Bool, refreshID: Int) async {
        showProgress(.loading, userInitiated: userInitiated)

        do {
            let directions = try await directionsLoader(fix, apiService)
            guard !Task.isCancelled, currentRefreshID == refreshID else { return }
            origin = fix
            self.apiService = apiService
            isLastRefreshOffline = false
            loadedAt = Date()
            isStale = false
            phase = directions.isEmpty ? .empty : .loaded(directions)
        } catch {
            guard !Task.isCancelled, currentRefreshID == refreshID else { return }
            let isOffline = ErrorClassifier.category(for: error) == .offline
            isLastRefreshOffline = isOffline
            if case .loaded = phase {
                // Preserve loaded directions across transient background fetch failures
                isStale = true
            } else {
                phase = .failed(isOffline ? Strings.nearbyOffline : error.localizedDescription)
            }
        }
    }
}

/// Time measured from one starting instant on a clock. Lets callers holding
/// `any Clock<Duration>` measure and sleep against that instant without naming
/// the clock's `Instant` type.
private struct Stopwatch: Sendable {
    /// The time passed since the start.
    let elapsed: @Sendable () -> Duration
    /// Sleeps until the given time has passed since the start. The deadline
    /// is fixed at the start, so it doesn't move with when the sleep begins.
    let sleepUntilElapsed: @Sendable (Duration) async throws -> Void
}

private extension Clock where Duration == Swift.Duration {
    func stopwatch() -> Stopwatch {
        let start = now
        return Stopwatch(
            elapsed: { start.duration(to: self.now) },
            sleepUntilElapsed: { try await self.sleep(until: start.advanced(by: $0), tolerance: nil) }
        )
    }
}
