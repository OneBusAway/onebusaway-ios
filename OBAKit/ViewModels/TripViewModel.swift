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

    /// Decoded route shape coordinates; nil until first loaded. UI layer converts to MKPolyline.
    @Published private(set) var routePolylineCoordinates: [CLLocationCoordinate2D]?

    /// `true` while any data request is in-flight.
    @Published private(set) var isLoading = false

    /// Non-nil when a network error occurred.
    @Published private(set) var operationError: Error?

    // MARK: - Configuration

    /// Set by the UI layer to gate programmatic auto-refreshes.
    /// e.g. `viewModel.shouldSkipProgrammaticRefresh = { UIAccessibility.isVoiceOverRunning }`
    var shouldSkipProgrammaticRefresh: (() -> Bool)?

    // MARK: - Private

    private let application: Application
    private static let refreshInterval: TimeInterval = 30.0
    private var refreshTimer: Timer?
    private var loadDataTask: Task<Void, Never>?

    // MARK: - Init

    init(application: Application, tripConvertible: TripConvertible) {
        self.application = application
        self.tripConvertible = tripConvertible
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
        loadDataTask = Task { [weak self] in
            guard let self else { return }
            isLoading = true
            do {
                async let convertible = fetchTripConvertible()
                async let details = fetchTripDetails()
                async let polyline = fetchMapPolyline()

                // `try await` rethrows the first failure and cancels the sibling
                // async-lets. No @Published state has been mutated up to this point.
                let (newConvertible, newDetails, newPolyline) = try await (convertible, details, polyline)

                // All three fetches succeeded — apply atomically.
                if let newConvertible { tripConvertible = newConvertible }
                if let newDetails { tripDetails = newDetails }
                if let newPolyline { routePolylineCoordinates = newPolyline }
                operationError = nil
            } catch {
                // A cancelled load (e.g. dismissing a context menu preview)
                // should never surface an error to the user. The view is being
                // torn down, so leaving `isLoading` as-is is fine.
                if Task.isCancelled {
                    return
                }
                // URLSession can also report NSURLErrorCancelled without the
                // enclosing Task being cancelled (e.g. a lower layer cancelled
                // the request). Swallow the error, but clear the spinner — the
                // view is still alive and waiting.
                if error.isCancellation {
                    isLoading = false
                    return
                }
                operationError = error
            }
            isLoading = false
        }
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

        let response = try await apiService.getShape(id: tripConvertible.trip.shapeID)
        return Polyline(encodedPolyline: response.entry.points).coordinates
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
