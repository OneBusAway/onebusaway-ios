//
//  StopViewModel.swift
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

/// Shared ViewModel for the stop arrivals/departures screen.
///
/// Consumed by `StopViewController` (UIKit, via Combine `sink`) and by
/// future `StopDetailSheet` (SwiftUI, via `@StateObject`).
/// Contains no UIKit or SwiftUI imports.
@MainActor
class StopViewModel: ObservableObject {

    // MARK: - Published State

    /// The stop being displayed.
    @Published private(set) var stop: Stop?

    /// The arrivals/departures fetched from the server.
    @Published private(set) var stopArrivals: StopArrivals?

    /// `true` while a network request is in-flight.
    @Published private(set) var isLoading = false

    /// The last time data was successfully loaded.
    @Published private(set) var lastUpdated: Date?

    /// A human-readable status string (e.g. "Updated 2 min ago").
    @Published private(set) var statusText: String = ""

    /// Non-nil when a network error occurred.
    @Published private(set) var operationError: Error?

    /// `true` when a bookmark's stop ID no longer resolves.
    @Published private(set) var isBrokenBookmark = false

    /// User-saved preferences for this stop (sort order, hidden routes).
    @Published private(set) var stopPreferences: StopPreferences

    /// `true` when the arrival list should be filtered to the user's preferences.
    @Published var isListFiltered: Bool = true

    /// How many minutes of past arrivals to load.
    let minutesBefore: UInt = 5

    /// How many minutes of future arrivals to load. Increased by "Load More".
    @Published private(set) var minutesAfter: UInt

    /// The time window has been extended at least once and there are still no arrivals,
    /// so auto-extension is exhausted (capped at 12 h).
    @Published private(set) var isLoadMoreExhausted = false

    // MARK: - Navigation Intent

    /// Published when the ViewModel wants the UI layer to navigate somewhere.
    /// Consumers must reset this to `nil` after handling.
    @Published var navigationIntent: NavigationIntent?

    // MARK: - Init Context

    /// Optional bookmark that opened this stop view.
    var bookmarkContext: Bookmark?

    /// Transfer context, when the stop was opened as a transfer destination.
    var transferContext: TransferContext?

    // MARK: - Private

    let application: Application
    let stopID: StopID

    private static let defaultMinutesAfter: UInt = 35
    private static let timerInterval: TimeInterval = 15
    private static let refreshThreshold: TimeInterval = 30

    private var refreshTimer: Timer?
    private var statusTimer: Timer?

    // MARK: - Init

    init(
        application: Application,
        stopID: StopID,
        stop: Stop? = nil,
        bookmarkContext: Bookmark? = nil,
        transferContext: TransferContext? = nil
    ) {
        self.application = application
        self.stopID = stopID
        self.stop = stop
        self.bookmarkContext = bookmarkContext
        self.transferContext = transferContext
        self.minutesAfter = StopViewModel.defaultMinutesAfter

        if let currentRegion = application.currentRegion {
            self.stopPreferences = application.stopPreferencesDataStore.preferences(stopID: stopID, region: currentRegion)
        } else {
            self.stopPreferences = StopPreferences()
        }
    }

    deinit {
        refreshTimer?.invalidate()
        statusTimer?.invalidate()
    }

    // MARK: - Lifecycle

    /// Call from `viewWillAppear` / `.task`.
    func start() async {
        startStatusTimer()
        startAutoRefresh()
        await refresh()
    }

    /// Call from `viewWillDisappear` / `.onDisappear`.
    func deactivate() {
        stopAutoRefresh()
        stopStatusTimer()
    }

    // MARK: - Data Loading

    /// Fetches fresh arrivals/departures from the server.
    func refresh() async {
        guard let apiService = application.apiService else { return }
        isLoading = true
        do {
            let result = try await apiService.getArrivalsAndDeparturesForStop(
                id: stopID,
                minutesBefore: minutesBefore,
                minutesAfter: minutesAfter
            ).entry

            operationError = nil
            isBrokenBookmark = false
            lastUpdated = Date()
            updateStatus()
            stopArrivals = result
            let loadedStop = result.stop!
            self.stop = loadedStop
            if let region = application.currentRegion {
                recordRecentStop(loadedStop, region: region)
                reportStopViewed(loadedStop)
            }

            if result.arrivalsAndDepartures.isEmpty {
                autoExtendWindowIfNeeded()
            }
        } catch APIError.requestNotFound {
            isBrokenBookmark = bookmarkContext != nil
        } catch {
            operationError = error
        }
        isLoading = false
    }

    /// Extends the time window and reloads data. Call when the user taps "Load More".
    func loadMoreDepartures() async {
        await loadMore(minutes: 30)
    }

    // MARK: - Preferences

    /// Persists updated stop preferences and re-renders the list.
    func updateStopPreferences(_ prefs: StopPreferences) {
        stopPreferences = prefs
        guard let stop = stop, let region = application.currentRegion else { return }
        application.stopPreferencesDataStore.set(stopPreferences: prefs, stop: stop, region: region)
        disableFilterIfAllRoutesHidden()
    }

    /// Updates the sort type preference.
    func updateSortType(_ sortType: StopSort) {
        var prefs = stopPreferences
        prefs.sortType = sortType
        updateStopPreferences(prefs)
    }

    /// Saves alarm creation to the user data store.
    func recordAlarmCreated(_ alarm: Alarm) {
        application.userDataStore.add(alarm: alarm)
    }

    /// Returns whether an alarm can be created for the given arrival/departure.
    func canCreateAlarm(for arrivalDeparture: ArrivalDeparture) -> Bool {
        guard
            application.features.obaco == .running,
            application.features.push == .running
        else { return false }
        return arrivalDeparture.arrivalDepartureMinutes > 1
    }

    // MARK: - Private Helpers

    private func loadMore(minutes: UInt) async {
        minutesAfter += minutes
        await refresh()
    }

    private func autoExtendWindowIfNeeded() {
        guard minutesAfter < 720 else {
            isLoadMoreExhausted = true
            return
        }
        let additional: UInt = minutesAfter < 60 ? 60 : minutesAfter < 240 ? 60 : 120
        Task { await loadMore(minutes: additional) }
    }

    private func recordRecentStop(_ stop: Stop, region: Region) {
        application.userDataStore.addRecentStop(stop, region: region)
    }

    private func reportStopViewed(_ stop: Stop) {
        application.analytics?.reportStopViewed(
            name: stop.name,
            id: stop.id,
            stopDistance: analyticsDistanceToStop(stop)
        )
    }

    private func disableFilterIfAllRoutesHidden() {
        guard isListFiltered, let stop = stop else { return }
        let allHidden = stop.routes.allSatisfy { stopPreferences.hiddenRoutes.contains($0.id) }
        if allHidden { isListFiltered = false }
    }

    private func analyticsDistanceToStop(_ stop: Stop) -> String {
        guard let userLocation = application.locationService.currentLocation else {
            return "User Distance: 03200-INFINITY"
        }
        let distance = userLocation.distance(from: stop.location)
        switch distance {
        case ..<50:   return "User Distance: 00000-00050m"
        case ..<100:  return "User Distance: 00050-00100m"
        case ..<200:  return "User Distance: 00100-00200m"
        case ..<400:  return "User Distance: 00200-00400m"
        case ..<800:  return "User Distance: 00400-00800m"
        case ..<1600: return "User Distance: 00800-01600m"
        case ..<3200: return "User Distance: 01600-03200m"
        default:      return "User Distance: 03200-INFINITY"
        }
    }

    // MARK: - Auto-Refresh Timer

    private func startAutoRefresh() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: StopViewModel.timerInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if self.shouldRefresh { await self.refresh() }
            }
        }
    }

    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private var shouldRefresh: Bool {
        guard let lastUpdated else { return true }
        return abs(lastUpdated.timeIntervalSinceNow) > StopViewModel.refreshThreshold
    }

    // MARK: - Status Timer

    private func startStatusTimer() {
        guard statusTimer == nil else { return }
        statusTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
    }

    private func stopStatusTimer() {
        statusTimer?.invalidate()
        statusTimer = nil
    }

    private func updateStatus() {
        guard let lastUpdated else {
            statusText = ""
            return
        }
        statusText = String(format: Strings.updatedAtFormat, application.formatters.timeAgoInWords(date: lastUpdated))
    }
}
