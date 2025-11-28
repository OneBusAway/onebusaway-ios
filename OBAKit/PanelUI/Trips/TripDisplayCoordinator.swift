//
//  TripDisplayCoordinator.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Combine
import MapKit
import SwiftUI
import OBAKitCore

/// Coordinates trip display state and API calls for VehiclesMapView
@MainActor
class TripDisplayCoordinator: ObservableObject {

    // MARK: - Published Properties

    /// The arrival/departure that initiated this trip display
    @Published var selectedArrivalDeparture: ArrivalDeparture?

    /// Full trip details including all stops
    @Published var tripDetails: TripDetails?

    /// Coordinates for the route polyline
    @Published var routePolylineCoordinates: [CLLocationCoordinate2D]?

    /// Current vehicle location on the trip
    @Published var vehicleLocation: CLLocationCoordinate2D?

    /// Whether trip data is currently loading
    @Published var isLoadingTrip: Bool = false

    /// Whether the trip view should be presented
    @Published var isTripViewPresented: Bool = false

    /// Any error that occurred during loading
    @Published var tripLoadError: Error?

    // MARK: - Internal Properties

    let application: Application

    // MARK: - Initialization

    init(application: Application) {
        self.application = application
    }

    // MARK: - Public Methods

    /// Selects an arrival/departure and loads the associated trip data
    func selectArrivalDeparture(_ arrivalDeparture: ArrivalDeparture) async {
        // Clear any previous error
        tripLoadError = nil

        // Set the selected arrival/departure
        selectedArrivalDeparture = arrivalDeparture

        // Show the trip view immediately (loading state)
        isTripViewPresented = true
        isLoadingTrip = true

        // Load the trip data
        await loadTripData(for: arrivalDeparture)

        isLoadingTrip = false
    }

    /// Navigates to an adjacent trip (previous or next)
    func navigateToAdjacentTrip(_ trip: Trip) async {
        guard let apiService = application.apiService else { return }

        isLoadingTrip = true
        tripLoadError = nil

        do {
            // Fetch the new trip details
            let tripResponse = try await apiService.getTrip(
                tripID: trip.id,
                vehicleID: tripDetails?.status?.vehicleID,
                serviceDate: tripDetails?.serviceDate
            )

            tripDetails = tripResponse.entry

            // Update vehicle location from new trip status
            if let position = tripResponse.entry.status?.position {
                vehicleLocation = position.coordinate
            }

            // Load the shape for the new trip
            if let shapeID = tripResponse.entry.trip?.shapeID {
                await loadRouteShape(shapeID: shapeID)
            }
        } catch {
            tripLoadError = error
            print("[TripCoordinator] ERROR loading adjacent trip: \(error)")
        }

        isLoadingTrip = false
    }

    /// Dismisses the trip view and clears all trip state
    func dismissTrip() {
        isTripViewPresented = false
        selectedArrivalDeparture = nil
        tripDetails = nil
        routePolylineCoordinates = nil
        vehicleLocation = nil
        tripLoadError = nil
    }

    // MARK: - Private Methods

    private func loadTripData(for arrivalDeparture: ArrivalDeparture) async {
        guard let apiService = application.apiService else {
            tripLoadError = NSError(domain: "TripCoordinator", code: -1, userInfo: [NSLocalizedDescriptionKey: "No API service available"])
            return
        }

        do {
            // Fetch trip details
            let tripResponse = try await apiService.getTrip(
                tripID: arrivalDeparture.tripID,
                vehicleID: arrivalDeparture.vehicleID,
                serviceDate: arrivalDeparture.serviceDate
            )

            tripDetails = tripResponse.entry

            // Update vehicle location from trip status
            if let position = tripResponse.entry.status?.position {
                vehicleLocation = position.coordinate
            }

            // Load the shape/polyline
            if let shapeID = tripResponse.entry.trip?.shapeID {
                await loadRouteShape(shapeID: shapeID)
            }
        } catch {
            tripLoadError = error
            print("[TripCoordinator] ERROR loading trip data: \(error)")
        }
    }

    private func loadRouteShape(shapeID: String) async {
        guard let apiService = application.apiService else { return }

        do {
            let shapeResponse = try await apiService.getShape(id: shapeID)

            // Extract coordinates from the MKPolyline
            guard let mkPolyline = shapeResponse.entry.polyline else { return }

            let pointCount = mkPolyline.pointCount
            var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
            mkPolyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))

            routePolylineCoordinates = coordinates
        } catch {
            print("[TripCoordinator] ERROR loading route shape: \(error)")
            // Don't set tripLoadError for shape failures - the trip data is still valid
        }
    }

    // MARK: - Computed Properties

    /// The route color for the current trip, or accent color if unavailable
    var routeColor: Color {
        if let uiColor = tripDetails?.trip?.route?.color {
            return Color(uiColor)
        }
        return Color.accentColor
    }

    /// The stop that the user originally selected (their destination)
    var userDestinationStopID: String? {
        selectedArrivalDeparture?.stopID
    }

    /// The stop where the vehicle is currently located
    var currentVehicleStopID: String? {
        tripDetails?.status?.closestStopID
    }
}
