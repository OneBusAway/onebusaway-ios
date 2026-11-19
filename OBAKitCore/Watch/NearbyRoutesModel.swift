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
    public init(phase: Phase, origin: CLLocation? = nil) {
        self.authorizationProvider = { .authorizedWhenInUse }
        self.requestAuthorizationAction = {}
        self.locationRequester = { origin ?? CLLocation(latitude: 47.6097, longitude: -122.3378) }
        self.hasRegion = { true }
        self.apiServiceProvider = { nil }
        self.directionsLoader = { _, _ in [] }
        self.cadencePolicy = .standard
        self.powerStateProvider = { false }
        self.clock = ContinuousClock()
        self.notificationCenter = .default
        self.phase = phase
        self.origin = origin
        self.loadedAt = Date()
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
        let elapsed = clock.stopwatch()
        while true {
            let interval = cadencePolicy.interval(isLowPower: powerStateProvider(), isOffline: isLastRefreshOffline)
            let remaining = interval - elapsed()
            guard remaining > .zero else { return }
            guard try await sleep(for: remaining) == .powerStateChanged else { return }
        }
    }

    private enum SleepOutcome: Sendable {
        case finished, powerStateChanged
    }

    private func sleep(for duration: Duration) async throws -> SleepOutcome {
        // Observe before sleeping, so a change can't land between the two.
        let (changes, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let observer = notificationCenter.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: nil) { _ in
            continuation.yield()
        }
        defer { notificationCenter.removeObserver(observer) }

        let clock = clock
        return try await withThrowingTaskGroup(of: SleepOutcome.self) { group in
            group.addTask {
                try await clock.sleep(for: duration)
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

        switch authorizationProvider() {
        case .notDetermined:
            phase = .awaitingAuthorization
            requestAuthorizationAction()
            return
        case .denied, .restricted:
            phase = .locationDenied
            return
        default:
            break
        }

        showProgress(.locating, userInitiated: userInitiated)

        let fix: CLLocation
        do {
            fix = try await locationRequester()
        } catch {
            guard !Task.isCancelled else { return }
            if error is LocationServiceError {
                phase = .locationDenied
            } else {
                let isOffline = ErrorClassifier.category(for: error) == .offline
                isLastRefreshOffline = isOffline
                if case .loaded = phase, isOffline {
                    // Retain loaded state when offline during background poll
                } else if isOffline {
                    phase = .failed(Strings.nearbyOffline)
                } else {
                    phase = .failed(Strings.locationFailed)
                }
            }
            return
        }

        guard !Task.isCancelled else { return }

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

        await loadDirections(near: fix, using: apiService, userInitiated: userInitiated)
    }

    private func loadDirections(near fix: CLLocation, using apiService: RESTAPIService, userInitiated: Bool) async {
        showProgress(.loading, userInitiated: userInitiated)

        do {
            let directions = try await directionsLoader(fix, apiService)
            guard !Task.isCancelled else { return }
            origin = fix
            isLastRefreshOffline = false
            loadedAt = Date()
            phase = directions.isEmpty ? .empty : .loaded(directions)
        } catch {
            guard !Task.isCancelled else { return }
            let isOffline = ErrorClassifier.category(for: error) == .offline
            isLastRefreshOffline = isOffline
            if case .loaded = phase {
                // Preserve loaded directions across transient background fetch failures
            } else {
                phase = .failed(isOffline ? Strings.nearbyOffline : error.localizedDescription)
            }
        }
    }
}

private extension Clock where Duration == Swift.Duration {
    /// Returns a closure that reports the time passed on this clock since the
    /// call. Lets callers holding `any Clock<Duration>` measure elapsed time
    /// without naming the clock's `Instant` type.
    func stopwatch() -> @Sendable () -> Duration {
        let start = now
        return { start.duration(to: self.now) }
    }
}
