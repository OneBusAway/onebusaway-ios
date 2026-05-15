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

    // MARK: - Private

    let application: Application
    private static let refreshInterval: TimeInterval = 20.0
    private var refreshTimer: Timer?
    private var loadDataTask: Task<Void, Never>?

    // MARK: - Init

    init(application: Application, tripConvertible: TripConvertible) {
        self.application = application
        self.tripConvertible = tripConvertible
    }

    deinit {
        refreshTimer?.invalidate()
        loadDataTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Call from `viewWillAppear`.
    func start() {
        startRefreshTimer()
        loadData(isProgrammatic: true)
    }

    /// Call from `viewWillDisappear`.
    func deactivate() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Refresh

    func refresh() {
        loadData(isProgrammatic: false)
    }

    // MARK: - Data Loading

    func loadData(isProgrammatic: Bool) {
        loadDataTask?.cancel()
        loadDataTask = Task { [weak self] in
            guard let self else { return }
            isLoading = true
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { [weak self] in
                        guard let self else { return }
                        try await self.loadTripDetails(isProgrammatic: isProgrammatic)
                    }
                    group.addTask { [weak self] in
                        guard let self else { return }
                        try await self.loadTripConvertible(isProgrammatic: isProgrammatic)
                    }
                    group.addTask { [weak self] in
                        guard let self else { return }
                        try await self.loadMapPolyline(isProgrammatic: isProgrammatic)
                    }
                    try await group.waitForAll()
                }
                operationError = nil
            } catch is CancellationError {
                return
            } catch {
                operationError = error
            }
            isLoading = false
        }
    }

    private func loadTripConvertible(isProgrammatic: Bool) async throws {
        guard let apiService = application.apiService else { return }
        guard let arrivalDeparture = tripConvertible.arrivalDeparture else { return }

        let newArrDep = try await apiService.getTripArrivalDepartureAtStop(
            stopID: arrivalDeparture.stopID,
            tripID: arrivalDeparture.tripID,
            serviceDate: arrivalDeparture.serviceDate,
            vehicleID: arrivalDeparture.vehicleID,
            stopSequence: arrivalDeparture.stopSequence
        ).entry

        tripConvertible = TripConvertible(arrivalDeparture: newArrDep)
    }

    private func loadTripDetails(isProgrammatic: Bool) async throws {
        guard let apiService = application.apiService else { return }

        let trip = try await apiService.getTrip(
            tripID: tripConvertible.trip.id,
            vehicleID: tripConvertible.vehicleID,
            serviceDate: tripConvertible.serviceDate
        ).entry

        tripDetails = trip
    }

    private func loadMapPolyline(isProgrammatic: Bool) async throws {
        guard let apiService = application.apiService,
              routePolylineCoordinates == nil else { return }

        let response = try await apiService.getShape(id: tripConvertible.trip.shapeID)
        routePolylineCoordinates = Polyline(encodedPolyline: response.entry.points).coordinates
    }

    // MARK: - Refresh Timer

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: Self.refreshInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.loadData(isProgrammatic: true)
            }
        }
    }
}
