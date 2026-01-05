//
//  NearbyStopsViewModel.swift
//  OBAWatch Watch App
//
//  Created by Prince Yadav on 31/12/25.
//

import Foundation
import SwiftUI
import CoreLocation
import Combine
import OBASharedCore
@MainActor
class NearbyStopsViewModel: ObservableObject {
    @Published var stops: [OBAStop] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var locationStatus: String = "Getting location..."
    @Published var routeSummaryByStopID: [OBAStopID: String] = [:]
    
    private let apiClient: OBAAPIClient
    private let locationProvider: () -> CLLocation?
    private var cancellables = Set<AnyCancellable>()
    
    init(apiClient: OBAAPIClient, locationProvider: @escaping () -> CLLocation?) {
        self.apiClient = apiClient
        self.locationProvider = locationProvider
        
        // Listen for location updates
        NotificationCenter.default.publisher(for: NSNotification.Name("LocationUpdated"))
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.loadNearbyStops()
                }
            }
            .store(in: &cancellables)
        
        // Initial load
        Task {
            await loadNearbyStops()
        }
    }
    
    func loadNearbyStops() async {
        var location = locationProvider()
        if location == nil {
            do {
                let agencies = try await apiClient.fetchAgenciesWithCoverage()
                if let first = agencies.first {
                    location = CLLocation(latitude: first.centerLatitude, longitude: first.centerLongitude)
                    locationStatus = "Showing service area"
                } else {
                    locationStatus = "Location not available"
                    return
                }
            } catch {
                locationStatus = "Location not available"
                return
            }
        }
        
        isLoading = true
        errorMessage = nil
        locationStatus = "Loading stops..."
        
        defer { isLoading = false }

        do {
            let fetched = try await apiClient.fetchNearbyStops(
                latitude: location!.coordinate.latitude,
                longitude: location!.coordinate.longitude,
                radius: 5000.0
            )
            routeSummaryByStopID = fetched.stopIDToRouteNames
            stops = fetched.stops
                .sorted { stop1, stop2 in
                    let loc1 = CLLocation(latitude: stop1.latitude, longitude: stop1.longitude)
                    let loc2 = CLLocation(latitude: stop2.latitude, longitude: stop2.longitude)
                    let distance1 = loc1.distance(from: location!)
                    let distance2 = loc2.distance(from: location!)
                    return distance1 < distance2
                }
            locationStatus = "\(stops.count) stops found"
        } catch {
            errorMessage = error.localizedDescription
            locationStatus = "Error loading stops"
        }
    }
}
