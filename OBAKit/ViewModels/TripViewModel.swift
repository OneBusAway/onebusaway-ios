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
/// Consumed by `TripPageViewController`, whose SwiftUI `TripPageView` observes
/// it. Contains no UIKit or MapKit imports.
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

    /// The server clocks the last load's responses carried, for vehicle position
    /// estimation's skew correction.
    @Published private(set) var serverClocks: [ServerClockSample] = []

    /// When a load last brought the trip back: its details, or its arrival at
    /// the rider's stop. `nil` until one has. A load that fails leaves it alone,
    /// because the page is still showing what that earlier load fetched (#1581).
    @Published private(set) var lastUpdated: Date?

    /// Non-nil when a network error occurred.
    @Published private(set) var operationError: Error?

    /// `true` when the running load's `tripDetails` fetch failed. Reset when a
    /// load starts, so a retry reads as loading again.
    @Published private(set) var stopListLoadFailed = false

    /// The trip on either side of this one that `openAdjacentTrip(_:then:)` is
    /// fetching, for its row's spinner. `nil` when none is.
    @Published private(set) var loadingAdjacentTrip: TripAdjacentTrips.Order?

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

    /// The stops the trip page lists, read from this model's current values.
    ///
    /// Not for a `@Published` sink, which runs before the new value is stored:
    /// one builds from the sink's own values with
    /// `TripStopListModel.make(convertible:details:sharedDestinationStopID:)`,
    /// as `TripPageViewController.publishMapFocus` does.
    var stopList: TripStopListModel {
        TripStopListModel.make(
            convertible: tripConvertible,
            details: tripDetails,
            sharedDestinationStopID: destinationStopID
        )
    }

    /// What this trip starts as and continues as, from the same details as
    /// `stopList`, so the rows appear with the stops.
    var adjacentTrips: TripAdjacentTrips {
        TripAdjacentTrips(details: tripDetails)
    }

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

    /// The fetch started by `openAdjacentTrip(_:then:)`. Held so `deactivate()`
    /// can cancel it, and so tests have a completion to await.
    private(set) var adjacentTripTask: Task<Void, Never>?

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
        adjacentTripTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Call from `viewWillAppear`.
    func start() {
        startRefreshTimer()
        loadData()
    }

    /// Call from `viewWillDisappear`.
    ///
    /// Also drops a trip `openAdjacentTrip(_:then:)` is still fetching. Opened
    /// after the page has gone, it would cover whatever the rider went to instead.
    func deactivate() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        loadDataTask?.cancel()
        loadDataTask = nil
        isLoading = false
        adjacentTripTask?.cancel()
        adjacentTripTask = nil
        loadingAdjacentTrip = nil
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
        let cachePolicy = FeatureFlags.realtimeCachePolicy(userDefaults: application.userDefaults)
        var detailsClock: ServerClockSample?
        var convertibleClock: ServerClockSample?
        async let details = fetchTripDetails(cachePolicy: cachePolicy)
        async let convertible = fetchTripConvertible(cachePolicy: cachePolicy)
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
            let (newDetails, clock) = try await details
            guard !Task.isCancelled else { return }
            detailsClock = clock
            applyTripDetails(newDetails)
        } catch {
            guard !Task.isCancelled else { return }
            // Even for a lower-layer cancellation: there is still no list, and
            // without this the page would say "Loading" with nothing loading.
            stopListLoadFailed = true
            record(error)
        }
        do {
            let (newConvertible, clock) = try await convertible
            guard !Task.isCancelled else { return }
            convertibleClock = clock
            applyTripConvertible(newConvertible)
        } catch {
            guard !Task.isCancelled else { return }
            record(error)
        }
        do {
            let newPolyline = try await polyline
            guard !Task.isCancelled else { return }
            applyRoutePolyline(newPolyline)
        } catch {
            guard !Task.isCancelled else { return }
            record(error)
        }

        serverClocks = [detailsClock, convertibleClock].compactMap { $0 }

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

    private func applyTripDetails(_ newDetails: TripDetails?) {
        if let newDetails {
            tripDetails = newDetails
            lastUpdated = Date()
        }
        stopListLoadFailed = false
    }

    private func applyTripConvertible(_ newConvertible: TripConvertible?) {
        guard let newConvertible else { return }
        tripConvertible = newConvertible
        lastUpdated = Date()
    }

    private func applyRoutePolyline(_ newPolyline: [CLLocationCoordinate2D]?) {
        if let newPolyline { routePolylineCoordinates = newPolyline }
    }

    private func fetchTripConvertible(cachePolicy: URLRequest.CachePolicy) async throws -> (TripConvertible?, ServerClockSample?) {
        guard let apiService = application.apiService,
              let arrivalDeparture = tripConvertible.arrivalDeparture else { return (nil, nil) }

        let response = try await apiService.getTripArrivalDepartureAtStop(
            stopID: arrivalDeparture.stopID,
            tripID: arrivalDeparture.tripID,
            serviceDate: arrivalDeparture.serviceDate,
            vehicleID: arrivalDeparture.vehicleID,
            stopSequence: arrivalDeparture.stopSequence,
            cachePolicy: cachePolicy
        )

        return (TripConvertible(arrivalDeparture: response.entry), response.serverClock)
    }

    private func fetchTripDetails(cachePolicy: URLRequest.CachePolicy) async throws -> (TripDetails?, ServerClockSample?) {
        guard let apiService = application.apiService else { return (nil, nil) }

        let response = try await apiService.getTrip(
            tripID: tripConvertible.trip.id,
            vehicleID: tripConvertible.vehicleID,
            serviceDate: tripConvertible.serviceDate,
            cachePolicy: cachePolicy
        )
        return (response.entry, response.serverClock)
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

    // MARK: - Adjacent Trips

    /// Fetches the trip the vehicle runs before or after this one, and hands it
    /// to `open`.
    ///
    /// With this trip's vehicle and service date, as `fetchTripDetails()` uses:
    /// the trips in a vehicle's block share both, and the vehicle lets OBA report
    /// where it is on the trip that opens.
    ///
    /// Ignored while a fetch is running, so a second tap can't open a second
    /// trip over the first. A failure goes to the app's error toast and leaves
    /// the row ready for another try.
    func openAdjacentTrip(_ order: TripAdjacentTrips.Order, then open: @escaping (TripConvertible) -> Void) {
        guard loadingAdjacentTrip == nil else { return }
        guard let row = adjacentTrips.row(order) else {
            Logger.warn("Trip \(tripConvertible.tripID) has no \(order) trip to open.")
            return
        }
        // Can't happen: the rows come from details this service loaded, and a
        // region change replaces the service rather than clearing it.
        guard let apiService = application.apiService else {
            Logger.error("Can't open the \(order) trip of \(tripConvertible.tripID): no API service.")
            assertionFailure("Trip \(tripConvertible.tripID) shows an adjacent trip with no API service to fetch it.")
            return
        }

        let tripID = row.trip.id
        let vehicleID = tripConvertible.vehicleID
        let serviceDate = tripConvertible.serviceDate
        loadingAdjacentTrip = order

        // `deactivate()` clears `loadingAdjacentTrip` as it cancels this task, so
        // the cancelled paths leave it alone.
        adjacentTripTask = Task { [weak self] in
            do {
                let details = try await apiService.getTrip(tripID: tripID, vehicleID: vehicleID, serviceDate: serviceDate).entry
                // Cancellation is cooperative: the response can arrive after the
                // page has gone.
                guard let self, !Task.isCancelled else { return }
                loadingAdjacentTrip = nil
                open(TripConvertible(tripDetails: details))
            } catch {
                guard let self, !Task.isCancelled else { return }
                loadingAdjacentTrip = nil
                // A lower layer can cancel the request without cancelling this task.
                // Nothing the rider did, so nothing to tell them.
                guard !error.isCancellation else { return }
                await application.displayError(error)
            }
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
