//
//  CurrentTripViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Combine
import CoreLocation
import OBAKitCore

/// Shared ViewModel for the "find my current trip on a selected route" screen.
///
/// Consumed by `CurrentTripViewController` (UIKit, via Combine `sink`) and by
/// future SwiftUI consumers (via `@StateObject`).
/// Contains no UIKit imports.
@MainActor
class CurrentTripViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var state: State = .loading

    /// Matches found near the user. Empty unless `state == .multipleResults` or a
    /// single match has just produced a `pendingNavigation` event.
    @Published private(set) var matchResults: [NearbyTripMatcher.MatchResult] = []

    /// Set when exactly one match is found. UIKit consumers sink this and perform
    /// the navigation push; SwiftUI consumers bind it to `.navigationDestination(item:)`.
    /// Settable so consumers can clear it after acting (and so SwiftUI bindings can
    /// drive it to `nil` on pop).
    @Published var pendingNavigation: ArrivalDeparture?

    // MARK: - Configuration

    /// Set by the UI layer to gate programmatic auto-refreshes.
    /// e.g. `viewModel.shouldSkipProgrammaticRefresh = { UIAccessibility.isVoiceOverRunning }`
    var shouldSkipProgrammaticRefresh: (() -> Bool)?

    // MARK: - Private

    private let application: Application
    private let route: Route
    private static let refreshInterval: TimeInterval = 20.0
    private var refreshTimer: Timer?
    private var findVehicleTask: Task<Void, Never>?
    /// Trip ID we last handed to the consumer via `pendingNavigation`. Prevents
    /// the 20-second background refresh from re-firing navigation for the trip
    /// the user just dismissed. Cleared on user-initiated retry / `start()`.
    private var lastFiredTripID: TripIdentifier?

    // MARK: - Init

    init(application: Application, route: Route) {
        self.application = application
        self.route = route
    }

    isolated deinit {
        refreshTimer?.invalidate()
        findVehicleTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Call from `viewWillAppear`. Starts the refresh timer and kicks off an initial find.
    func start() {
        startRefreshTimer()
        findVehicle()
    }

    /// Call from `viewWillDisappear`. Stops the timer and cancels any in-flight find.
    func deactivate() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        findVehicleTask?.cancel()
        findVehicleTask = nil
    }

    // MARK: - Intent

    /// Cancels any in-flight find, then starts a new search.
    ///
    /// - Parameter resetState: When `true` (user-initiated retry or `start()`),
    ///   force the UI back to `.loading` so the tap surfaces a state change and
    ///   the "already presented" latch is cleared. When `false` (background
    ///   auto-refresh from `startRefreshTimer`), keep the existing state so the
    ///   user's screen isn't wiped every 20 seconds — updates happen in place.
    func findVehicle(resetState: Bool = true) {
        findVehicleTask?.cancel()
        if resetState {
            state = .loading
            // Fresh explicit retry: allow re-navigation for the same trip ID.
            lastFiredTripID = nil
        }

        findVehicleTask = Task { [weak self] in
            guard let self else { return }
            // `deactivate()` cancels the task. Bail out before the synchronous early-return
            // paths so a cancelled task can't still publish a final `.noLocation` / `.error`.
            if Task.isCancelled { return }

            guard let userLocation = self.application.locationService.currentLocation else {
                Logger.error("CurrentTripViewModel: no user location available for route \(self.route.id)")
                self.state = .noLocation
                return
            }

            guard let apiService = self.application.apiService else {
                Logger.error("CurrentTripViewModel: no apiService available for route \(self.route.id)")
                self.state = .error(Self.noServiceError())
                return
            }

            let cachedStops = self.application.mapRegionManager.stops

            do {
                let results = try await NearbyTripMatcher.findTrips(
                    for: self.route,
                    near: userLocation,
                    using: apiService,
                    stops: cachedStops
                )
                if Task.isCancelled { return }
                self.handle(results: results)
            } catch is CancellationError {
                return
            } catch {
                self.handle(error: error)
            }
        }
    }

    /// Routes a fresh set of matches into the appropriate state transition:
    /// empty → `.noResults`, one → `pendingNavigation` (once per trip) plus a
    /// `.multipleResults` fallback so the underlying view isn't a frozen
    /// spinner, more → `.multipleResults`.
    func handle(results: [NearbyTripMatcher.MatchResult]) {
        matchResults = results

        switch results.count {
        case 0:
            state = .noResults
        case 1:
            let arrival = results[0].arrivalDeparture
            // Only fire pendingNavigation once per trip. The consumer clears it
            // after presenting; a background refresh that finds the same trip
            // shouldn't re-fire the modal after a user-initiated dismiss.
            if lastFiredTripID != arrival.tripID {
                pendingNavigation = arrival
                lastFiredTripID = arrival.tripID
            }
            // Move to a terminal, tappable state so the underlying view shows
            // the match as a single-row list instead of a permanent spinner.
            state = .multipleResults
        default:
            state = .multipleResults
        }
    }

    /// Maps a matcher error onto VM state. `MatchError.noRealtimeData` gets its own
    /// `.noRealtime` state; everything else surfaces as `.error(error)`.
    func handle(error: Error) {
        if let matchError = error as? NearbyTripMatcher.MatchError, matchError == .noRealtimeData {
            state = .noRealtime
        } else {
            Logger.error("Failed to find trips: \(error)")
            state = .error(error)
        }
    }

    /// Called by a UIKit consumer that cannot perform the single-match navigation
    /// (e.g. the VC isn't embedded in a `UINavigationController`). Falls back to
    /// the disambiguation list so the user can still act on the match. `matchResults`
    /// already holds the single result from `handle(results:)`.
    func pendingNavigationUnavailable() {
        state = .multipleResults
        pendingNavigation = nil
    }

    // MARK: - Refresh Timer

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: Self.refreshInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !(self.shouldSkipProgrammaticRefresh?() ?? false) else { return }
                // Background refresh: don't reset UI state, and preserve the
                // "already presented" latch so we don't re-fire pendingNavigation
                // for a trip the user just dismissed.
                self.findVehicle(resetState: false)
            }
        }
    }

    // MARK: - Helpers

    /// Builds the localized "transit service unavailable" error used when no
    /// `apiService` is resolved (e.g. the user has no region selected).
    private static func noServiceError() -> NSError {
        NSError(
            domain: "CurrentTripViewModel",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: OBALoc(
                "current_trip_controller.error_no_service",
                value: "Unable to connect to the transit service.",
                comment: "Error when the API service is unavailable."
            )]
        )
    }
}

// MARK: - State
extension CurrentTripViewModel {
    /// Loading / error / result state for the screen.
    enum State: Equatable {
        /// Initial state, and while a find is in flight.
        case loading
        /// No user location is available — the location service returned `nil`.
        case noLocation
        /// The matcher returned an empty array — no active vehicle is currently
        /// on the selected route near the user.
        case noResults
        /// The selected route has no real-time tracking data.
        case noRealtime
        /// Two or more vehicles matched; the UI shows a disambiguation list.
        case multipleResults
        /// A network or service error surfaced from the matcher.
        case error(Error)

        // Manual `==` because `case error(Error)` blocks synthesis (Swift's
        // `Error` existential isn't `Equatable`). Two `.error` cases compare
        // equal when their `localizedDescription`s match — the only error
        // surface SwiftUI consumers render, so this matches what the View's
        // `.onChange(of: state)` actually cares about.
        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading),
                 (.noLocation, .noLocation),
                 (.noResults, .noResults),
                 (.noRealtime, .noRealtime),
                 (.multipleResults, .multipleResults):
                return true
            case let (.error(lhsErr), .error(rhsErr)):
                return lhsErr.localizedDescription == rhsErr.localizedDescription
            default:
                return false
            }
        }
    }
}
