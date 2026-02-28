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
import OBAKitCore
@MainActor
class NearbyStopsViewModel: ObservableObject {
    @Published var stops: [OBAStop] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var locationStatus: String = OBALoc("nearby_stops.getting_location", value: "Getting location...", comment: "Status: getting location")
    @Published var routeSummaryByStopID: [OBAStopID: String] = [:]
    
    private let apiClientProvider: () -> OBAAPIClient
    private let locationProvider: () -> CLLocation
    private var cancellables = Set<AnyCancellable>()
    
    init(apiClientProvider: @escaping () -> OBAAPIClient, locationProvider: @escaping () -> CLLocation) {
        self.apiClientProvider = apiClientProvider
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
        let location = locationProvider()
        let apiClient = apiClientProvider()
        
        isLoading = true
        errorMessage = nil
        locationStatus = OBALoc("nearby_stops.loading_stops", value: "Loading stops...", comment: "Status: loading stops")
        
        defer { isLoading = false }

        do {
            let fetched = try await apiClient.fetchNearbyStops(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                radius: 1000.0 // Request 1km radius explicitly
            )
            routeSummaryByStopID = fetched.stopIDToRouteNames
            stops = fetched.stops
                .sorted { stop1, stop2 in
                    let loc1 = CLLocation(latitude: stop1.latitude, longitude: stop1.longitude)
                    let loc2 = CLLocation(latitude: stop2.latitude, longitude: stop2.longitude)
                    let distance1 = loc1.distance(from: location)
                    let distance2 = loc2.distance(from: location)
                    return distance1 < distance2
                }
            
            if stops.isEmpty {
                locationStatus = OBALoc("nearby_stops.no_stops_near_location", value: "0 stops found near this location", comment: "Status: 0 stops found")
            } else {
                locationStatus = String(format: OBALoc("nearby_stops.stops_found_fmt", value: "%d stops found", comment: "Status: multiple stops found"), stops.count)
            }
        } catch {
            errorMessage = error.watchOSUserFacingMessage
            locationStatus = OBALoc("nearby_stops.error_loading_stops", value: "Error loading stops", comment: "Status: error loading stops")
        }
    }
}
