//
//  TripViewModel.swift
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

/// Shared ViewModel for the trip map/details screen.
///
/// Consumed by `TripViewController` (UIKit, via Combine `sink`) and by
/// future `TripSheetView` (SwiftUI, via `@StateObject`).
/// Contains no UIKit or MapKit imports.
@MainActor
class TripViewModel: ObservableObject {

    // MARK: - Published State

    /// The trip convertible (ArrivalDeparture or Trip) being displayed.
    @Published private(set) var tripConvertible: TripConvertible

    /// Full trip details including stop sequence and vehicle status.
    @Published private(set) var tripDetails: TripDetails?

    /// The live arrival at `destinationStopID`, which the trip panel's progress
    /// header counts down to. `nil` when no shared destination was named, until
    /// it first loads, and after a refresh that failed to load it.
    @Published private(set) var destinationArrivalDeparture: ArrivalDeparture?

    /// Decoded route shape coordinates; nil until first loaded. UI layer converts to MKPolyline.
    @Published private(set) var routePolylineCoordinates: [CLLocationCoordinate2D]?

    /// `true` while any data request is in-flight. Set the moment a load is
    /// asked for, not when its task first runs, so the refresh button disables
    /// on the tap that started it.
    @Published private(set) var isLoading = false

    /// When a load last brought the trip back: its details, or its arrival at
    /// the rider's stop. `nil` until one has. A load that fails leaves it alone,
    /// because the page is still showing what that earlier load fetched (#1581).
    @Published private(set) var lastUpdated: Date?

    /// Non-nil when a network error occurred.
    @Published private(set) var operationError: Error?

    /// `true` when the running load's `tripDetails` fetch failed. Reset when a
    /// load starts, so a retry reads as loading again.
    @Published private(set) var stopListLoadFailed = false

    /// What the trip page can say about the stop list.
    enum StopListState {
        case loaded
        /// Not loaded yet, and nothing has failed, or a retry is running.
        case loading
        /// The last load failed. A retry may well work: the list exists.
        case failed
        /// The trip came back with no stops.
        case unavailable
    }

    var stopListState: StopListState {
        if let tripDetails { return tripDetails.stopTimes.isEmpty ? .unavailable : .loaded }
        // Not gated on `isLoading`: that waits on the route line and the
        // destination's arrival too, and a slow one would hold back the Retry.
        return stopListLoadFailed ? .failed : .loading
    }

    // MARK: - Configuration

    /// The stop a shared trip link named as the sharer's exit, or `nil` for
    /// every other way into the trip screen. See #449.
    let destinationStopID: StopID?

    /// Set by the UI layer to gate programmatic auto-refreshes.
    /// e.g. `viewModel.shouldSkipProgrammaticRefresh = { UIAccessibility.isVoiceOverRunning }`
    var shouldSkipProgrammaticRefresh: (() -> Bool)?

    // MARK: - Private

    private let application: Application
    private static let refreshInterval: TimeInterval = 30.0
    private var refreshTimer: Timer?

    /// The in-flight load started by `loadData()`.
    ///
    /// Held so a newer load or teardown can cancel it, and so tests have a
    /// completion to await instead of polling for its side effects.
    private(set) var loadDataTask: Task<Void, Never>?

    // MARK: - Init

    /// - Parameter destinationStopID: Where the sharer said they will step off,
    ///   when the trip was opened from a shared link that named one. See #449.
    init(application: Application, tripConvertible: TripConvertible, destinationStopID: StopID? = nil) {
        self.application = application
        self.tripConvertible = tripConvertible
        self.destinationStopID = destinationStopID
    }

    isolated deinit {
        refreshTimer?.invalidate()
        loadDataTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Call from `viewWillAppear`.
    func start() {
        startRefreshTimer()
        loadData()
    }

    /// Call from `viewWillDisappear`.
    func deactivate() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        loadDataTask?.cancel()
        loadDataTask = nil
        isLoading = false
    }

    // MARK: - Refresh

    func refresh() {
        loadData()
    }

    // MARK: - Data Loading

    func loadData() {
        loadDataTask?.cancel()
        isLoading = true
        loadDataTask = Task { [weak self] in
            await self?.performLoad()
        }
    }

    /// The body of `loadData()`'s task.
    private func performLoad() async {
        stopListLoadFailed = false

        // One failing loses none of the others (#1548). The stop list used to
        // wait on the route line and the arrival, and go down with either of
        // them: the page then said the list "isn't available" until a refresh
        // 30 seconds later. A throw caught inside this scope leaves the other
        // fetches running.
        async let details = fetchTripDetails()
        async let convertible = fetchTripConvertible()
        async let polyline = fetchMapPolyline()
        var failure: Error?
        // The first failure the rider should hear about. A lower-layer
        // cancellation never is, so it must not hide a real error after it.
        func record(_ error: Error) {
            if failure == nil || failure?.isCancellation == true { failure = error }
        }

        // The stop list first: it is most of the page, and the others run
        // alongside it rather than ahead of it.
        //
        // After each wait, cancellation is checked before anything applies. It
        // is cooperative: a load cancelled by a newer one or by `deactivate()`
        // can still get its responses back, and applying them could overwrite
        // the newer load's trip. Nor does a cancelled load (e.g. dismissing a
        // context menu preview) surface an error; it leaves `isLoading` to the
        // load that replaced it, or to `deactivate()`.
        do {
            let newDetails = try await details
            guard !Task.isCancelled else { return }
            apply(newDetails)
        } catch {
            guard !Task.isCancelled else { return }
            // Even for a lower-layer cancellation: there is still no list, and
            // without this the page would say "Loading" with nothing loading.
            stopListLoadFailed = true
            record(error)
        }
        do {
            let newConvertible = try await convertible
            guard !Task.isCancelled else { return }
            apply(newConvertible)
        } catch {
            guard !Task.isCancelled else { return }
            record(error)
        }
        do {
            let newPolyline = try await polyline
            guard !Task.isCancelled else { return }
            apply(newPolyline)
        } catch {
            guard !Task.isCancelled else { return }
            record(error)
        }

        // URLSession can report NSURLErrorCancelled without this task being
        // cancelled, when a lower layer cancelled the request. Never a
        // rider-facing error.
        operationError = failure?.isCancellation == true ? nil : failure

        // After the details are applied, because the destination's row is
        // read from them.
        await loadDestinationArrival()
        // Same for a load cancelled while it waited for the destination's
        // arrival: the load that replaced it may still be running.
        guard !Task.isCancelled else { return }
        isLoading = false
    }

    private func apply(_ newDetails: TripDetails?) {
        if let newDetails {
            tripDetails = newDetails
            lastUpdated = Date()
        }
        stopListLoadFailed = false
    }

    private func apply(_ newConvertible: TripConvertible?) {
        guard let newConvertible else { return }
        tripConvertible = newConvertible
        lastUpdated = Date()
    }

    private func apply(_ newPolyline: [CLLocationCoordinate2D]?) {
        if let newPolyline { routePolylineCoordinates = newPolyline }
    }

    private func fetchTripConvertible() async throws -> TripConvertible? {
        guard let apiService = application.apiService,
              let arrivalDeparture = tripConvertible.arrivalDeparture else { return nil }

        let newArrDep = try await apiService.getTripArrivalDepartureAtStop(
            stopID: arrivalDeparture.stopID,
            tripID: arrivalDeparture.tripID,
            serviceDate: arrivalDeparture.serviceDate,
            vehicleID: arrivalDeparture.vehicleID,
            stopSequence: arrivalDeparture.stopSequence
        ).entry

        return TripConvertible(arrivalDeparture: newArrDep)
    }

    private func fetchTripDetails() async throws -> TripDetails? {
        guard let apiService = application.apiService else { return nil }

        return try await apiService.getTrip(
            tripID: tripConvertible.trip.id,
            vehicleID: tripConvertible.vehicleID,
            serviceDate: tripConvertible.serviceDate
        ).entry
    }

    private func fetchMapPolyline() async throws -> [CLLocationCoordinate2D]? {
        guard let apiService = application.apiService,
              routePolylineCoordinates == nil else { return nil }

        // No shape ID means the agency doesn't publish shape data for this trip.
        // Degrade quietly: the trip map simply draws no route line.
        guard let shapeID = tripConvertible.trip.shapeID, !shapeID.isEmpty else { return nil }

        let response = try await apiService.getShape(id: shapeID)
        return Polyline(encodedPolyline: response.entry.points).coordinates
    }

    /// Loads the live arrival at the shared destination, for the progress
    /// header's countdown.
    ///
    /// A failure is logged and clears the countdown rather than leave an old
    /// prediction on screen. It does not set `operationError`: the trip itself
    /// loaded, and an error alert over one supplementary time would be out of
    /// proportion.
    private func loadDestinationArrival() async {
        // Every trip without a shared destination stops here: there is nothing
        // to count down to.
        guard let destinationStopID,
              let apiService = application.apiService,
              let arrivalDeparture = tripConvertible.arrivalDeparture,
              let tripDetails else { return }

        // The same resolution the stop list uses, so the countdown targets the
        // row that carries the destination marker. When the trip never reaches
        // the destination after boarding, the list leaves the marker on the
        // boarding stop, and there is no destination to count down to.
        guard let destinationIndex = TripStopListModel.riderStops(
            in: tripDetails.stopTimes,
            arrivalDeparture: arrivalDeparture,
            sharedDestinationStopID: destinationStopID
        ).destinationIndex else {
            destinationArrivalDeparture = nil
            return
        }

        do {
            let arrival = try await apiService.getTripArrivalDepartureAtStop(
                stopID: destinationStopID,
                tripID: arrivalDeparture.tripID,
                serviceDate: arrivalDeparture.serviceDate,
                vehicleID: arrivalDeparture.vehicleID,
                // The row, not just the stop: a loop route can call at the
                // destination more than once.
                stopSequence: destinationIndex
            ).entry
            // Cancellation is cooperative: a request already answered when this
            // load was cancelled, by a newer refresh or `deactivate()`, still
            // returns. Publishing it could overwrite the newer refresh's arrival.
            guard !Task.isCancelled else { return }
            destinationArrivalDeparture = arrival
        } catch {
            if Task.isCancelled || error.isCancellation { return }
            Logger.error("Failed to load the arrival at shared destination \(destinationStopID) on trip \(arrivalDeparture.tripID): \(error)")
            destinationArrivalDeparture = nil
        }
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
                self.loadData()
            }
        }
    }
}
