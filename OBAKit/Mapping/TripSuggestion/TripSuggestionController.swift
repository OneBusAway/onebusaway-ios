//
//  TripSuggestionController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import UIKit
import OBAKitCore

/// A real-time vehicle the rider might be on.
nonisolated struct TripSuggestionCandidate: Identifiable, Hashable {
    /// One row per vehicle: a feed can put two vehicles on one trip.
    let id: String
    let tripID: String
    let vehicleID: String?
    let routeShortName: String
    let headsign: String?
    let routeType: Route.RouteType
    let agencyName: String?
    let routeColor: UIColor?
    let routeTextColor: UIColor?
    let serviceDate: Date?
    /// The vehicle's latest position.
    var sighting: VehicleSighting
    /// From the rider to the vehicle's estimated position, at the last check.
    var distance: CLLocationDistance = 0
    /// What the trip page opens with. `nil` only in tests.
    let arrivalDeparture: ArrivalDeparture?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.tripID == rhs.tripID && lhs.distance == rhs.distance
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(tripID)
    }
}

/// Where trip suggestions get vehicles from. A protocol so tests can supply them.
protocol TripSuggestionDataSource: AnyObject {
    /// Real-time vehicles serving the stops near `coordinate`, one per vehicle.
    func nearbyVehicles(around coordinate: CLLocationCoordinate2D) async throws -> [TripSuggestionCandidate]
    /// The vehicle's position now, for the second reading.
    func currentSighting(of candidate: TripSuggestionCandidate) async throws -> VehicleSighting?
}

/// Watches the rider's movement while the map is on screen and suggests the trip
/// they appear to be riding.
///
/// The whole flow is in the design's "Detection logic" diagram:
/// 1. Nothing happens until `RiderMotionGate` says the rider is moving at bus speed.
/// 2. Real-time vehicles near the rider, on every route serving the nearest stops,
///    are kept if close and heading the same way (`TripSuggestionMatcher`).
/// 3. About 20 s later each is checked again, and kept only if still with the rider.
/// 4. The survivors become `suggestion`. It never opens a trip itself.
///
/// It reads the location stream the map already runs, so it needs no extra
/// permission and keeps no extra hardware on.
@MainActor
final class TripSuggestionController: NSObject, ObservableObject {

    struct Timing {
        /// The wait between the first reading and the confirming one.
        var confirmationDelay: Duration = .seconds(20)
        /// Least time between searches, so a rider on a bus no feed tracks doesn't
        /// fetch arrivals with every fix.
        var searchInterval: TimeInterval = 60
        /// A suggestion nobody acts on hides after this, and its trips are snoozed.
        var idleTimeout: TimeInterval = 120
        /// How long a dismissed trip stays out of suggestions. A trip has ended by
        /// then in all but a few cases, and the snooze is only ever about that trip.
        var snoozeDuration: TimeInterval = 2 * 60 * 60
        /// At most this many vehicles get the confirming reading.
        var maximumCandidates = 3
    }

    /// The vehicles to suggest, closest first. Empty when nothing should show.
    @Published private(set) var suggestion: [TripSuggestionCandidate] = []

    private let locationService: LocationService
    private let userDefaults: UserDefaults
    private let dataSource: () -> TripSuggestionDataSource?
    private let timing: Timing
    private let matcherThresholds: TripSuggestionMatcher.Thresholds
    private let now: () -> Date
    private let sleep: (Duration) async throws -> Void
    /// Whether the app is in the foreground. Location can keep arriving in the
    /// background (proximity alerts hold Always access), and nothing should be
    /// fetched for a map nobody can see.
    private let isAppActive: () -> Bool

    private var gate: RiderMotionGate
    private var isActive = false
    private var searchTask: Task<Void, Never>?
    private var nextSearchAllowed = Date.distantPast
    private var shownAt: Date?
    /// Trip ID → when its snooze ends.
    private var snoozedTrips: [String: Date] = [:]

    init(
        locationService: LocationService,
        userDefaults: UserDefaults,
        dataSource: @escaping () -> TripSuggestionDataSource?,
        gateThresholds: RiderMotionGate.Thresholds = .init(),
        matcherThresholds: TripSuggestionMatcher.Thresholds = .init(),
        timing: Timing = Timing(),
        now: @escaping () -> Date = Date.init,
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        isAppActive: @escaping () -> Bool = { UIApplication.shared.applicationState == .active }
    ) {
        self.locationService = locationService
        self.userDefaults = userDefaults
        self.dataSource = dataSource
        self.gate = RiderMotionGate(thresholds: gateThresholds)
        self.matcherThresholds = matcherThresholds
        self.timing = timing
        self.now = now
        self.sleep = sleep
        self.isAppActive = isAppActive
        super.init()
        locationService.addDelegate(self)
    }

    isolated deinit {
        searchTask?.cancel()
    }

    // MARK: - Activity

    /// Whether the suggestion may show: the map is in the foreground with nothing
    /// covering it but the home sheet. Leaving cancels any search in flight and
    /// hides the suggestion, without snoozing it.
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if !active {
            stop()
        }
    }

    /// Whether the rider's setting and their location access allow suggestions.
    var isAllowed: Bool {
        TripSuggestionSettings.isEnabled(userDefaults: userDefaults)
            && locationService.isLocationUseAuthorized
            && locationService.accuracyAuthorization == .fullAccuracy
    }

    // MARK: - Rider actions

    /// The rider closed the suggestion. Its trips stay out of suggestions until the
    /// snooze ends.
    func dismiss() {
        hide(snoozing: true)
    }

    // MARK: - Location

    func handle(location: CLLocation) {
        guard isAllowed else {
            gate.reset()
            stop()
            return
        }

        gate.record(location)
        guard isActive, isAppActive() else {
            // Hidden without a snooze: a card left up while the app was away would
            // be stale when the rider comes back.
            stop()
            return
        }

        guard gate.isMoving else {
            stop()
            return
        }

        let date = now()
        if let shownAt {
            if date.timeIntervalSince(shownAt) >= timing.idleTimeout {
                hide(snoozing: true)
            }
            return
        }

        guard searchTask == nil, date >= nextSearchAllowed else { return }
        nextSearchAllowed = date.addingTimeInterval(timing.searchInterval)
        let rider = RiderSample(location: location)
        searchTask = Task { [weak self] in
            await self?.search(from: rider)
            // A cancelled search was already cleared by `cancelSearch()`, and may
            // finish after a newer one started; clearing here would drop that one.
            guard !Task.isCancelled else { return }
            self?.searchTask = nil
        }
    }

    // MARK: - Search

    private func search(from rider: RiderSample) async {
        guard let dataSource = dataSource() else { return }

        let vehicles: [TripSuggestionCandidate]
        do {
            vehicles = try await dataSource.nearbyVehicles(around: rider.coordinate)
        } catch {
            if !(error is CancellationError), !Task.isCancelled {
                Logger.error("Trip suggestions: nearby vehicles failed: \(error)")
            }
            return
        }
        guard !Task.isCancelled else { return }

        let candidates = Array(candidates(in: vehicles, rider: rider).prefix(timing.maximumCandidates))
        guard !candidates.isEmpty else { return }

        guard (try? await sleep(timing.confirmationDelay)) != nil, shouldContinueSearch,
              let location = locationService.currentLocation else { return }

        let later = RiderSample(location: location).fillingMotion(from: rider)
        let confirmed = await confirm(candidates, rider: later, using: dataSource)
        guard shouldContinueSearch, !confirmed.isEmpty else { return }

        suggestion = confirmed
        shownAt = now()
    }

    /// Whether a search that has been waiting on the network may still go on.
    private var shouldContinueSearch: Bool {
        !Task.isCancelled && isActive && isAppActive() && isAllowed && gate.isMoving
    }

    /// Vehicles close to the rider and heading their way, closest first. The data
    /// source already gives one entry per vehicle.
    func candidates(in vehicles: [TripSuggestionCandidate], rider: RiderSample) -> [TripSuggestionCandidate] {
        purgeExpiredSnoozes()
        return vehicles
            .compactMap { vehicle -> TripSuggestionCandidate? in
                guard snoozedTrips[vehicle.tripID] == nil,
                      let distance = TripSuggestionMatcher.candidateDistance(of: vehicle.sighting, rider: rider, thresholds: matcherThresholds)
                else { return nil }
                var candidate = vehicle
                candidate.distance = distance
                return candidate
            }
            .sorted { $0.distance < $1.distance }
    }

    private func confirm(
        _ candidates: [TripSuggestionCandidate],
        rider: RiderSample,
        using dataSource: TripSuggestionDataSource
    ) async -> [TripSuggestionCandidate] {
        var confirmed = [TripSuggestionCandidate]()
        for candidate in candidates {
            guard !Task.isCancelled else { return [] }
            guard let sighting = try? await dataSource.currentSighting(of: candidate),
                  let distance = TripSuggestionMatcher.confirmedDistance(
                      of: sighting, earlier: candidate.sighting, rider: rider, thresholds: matcherThresholds
                  )
            else { continue }
            var updated = candidate
            updated.sighting = sighting
            updated.distance = distance
            confirmed.append(updated)
        }
        return confirmed.sorted { $0.distance < $1.distance }
    }

    // MARK: - Helpers

    /// Waits for a search in flight to finish. For tests.
    func waitForSearch() async {
        await searchTask?.value
    }

    /// Cancels any search and hides the suggestion without snoozing it.
    private func stop() {
        cancelSearch()
        hide(snoozing: false)
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
    }

    private func hide(snoozing: Bool) {
        if snoozing {
            snooze(suggestion)
        }
        shownAt = nil
        if !suggestion.isEmpty {
            suggestion = []
        }
    }

    private func snooze(_ candidates: [TripSuggestionCandidate]) {
        let until = now().addingTimeInterval(timing.snoozeDuration)
        for candidate in candidates {
            snoozedTrips[candidate.tripID] = until
        }
    }

    private func purgeExpiredSnoozes() {
        let date = now()
        snoozedTrips = snoozedTrips.filter { $0.value > date }
    }
}

// MARK: - LocationServiceDelegate

extension TripSuggestionController: LocationServiceDelegate {
    func locationService(_ service: LocationService, locationChanged location: CLLocation) {
        handle(location: location)
    }
}
