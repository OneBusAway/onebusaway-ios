//
//  StopArrivalsViewModel.swift
//  OBAWatch Watch App
//
//  Created by Prince Yadav on 31/12/25.
//

import Foundation
import SwiftUI
import Combine
import OBAKitCore

@MainActor
class StopArrivalsViewModel: ObservableObject {
    @Published var arrivals: [OBAArrival] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?
    @Published var routes: [OBARoute] = []
    @Published var stopName: String?
    
    private let apiClientProvider: () -> OBAAPIClient
    private let stopID: OBAStopID
    private var updateTimer: Timer?
    
    init(apiClientProvider: @escaping () -> OBAAPIClient, stopID: OBAStopID) {
        self.apiClientProvider = apiClientProvider
        self.stopID = stopID
        
        // Load arrivals asynchronously
        Task { @MainActor in
            await loadArrivals()
            await loadRoutes()
        }
        
        // Auto-refresh every 30 seconds
        updateTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.loadArrivals()
            }
        }
    }
    
    deinit {
        updateTimer?.invalidate()
    }
    
    func loadArrivals() async {
        let apiClient = apiClientProvider()
        isLoading = true
        errorMessage = nil
        
        do {
            let result = try await apiClient.fetchArrivals(for: stopID)
            arrivals = result.arrivals
            
            // Update routes if we got them from the arrivals response
            if !result.routes.isEmpty {
                routes = result.routes
            }
            
            // Update stop name if we got it
            if let fetchedName = result.stopName {
                stopName = fetchedName
                
                // Save to recent stops
                saveToRecentStops(
                    name: fetchedName,
                    code: result.stopCode,
                    direction: result.stopDirection
                )
            }
            
            lastUpdated = Date()
        } catch let apiError as OBAAPIError {
            errorMessage = apiError.errorDescription ?? "API Error"
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }

    private func saveToRecentStops(name: String, code: String? = nil, direction: String? = nil) {
        let routeNames = routes.compactMap { $0.shortName }.joined(separator: ", ")
        
        let stop = OBAStop(
            id: stopID,
            name: name,
            latitude: 0, // We don't have lat/lon here but it's okay for recent list
            longitude: 0,
            code: code,
            direction: direction,
            routeNames: routeNames.isEmpty ? nil : routeNames
        )
        
        let recentViewModel = RecentStopsViewModel()
        recentViewModel.addRecentStop(stop)
        
        // Notify other views
        NotificationCenter.default.post(name: NSNotification.Name("RecentStopsUpdated"), object: nil)
    }

    func loadRoutes() async {
        let apiClient = apiClientProvider()
        do {
            let fetched = try await apiClient.fetchRoutesForStop(stopID: stopID)
            routes = fetched
        } catch let apiError as OBAAPIError {
            print("API Error loading routes: \(apiError.errorDescription ?? "unknown") for stop \(stopID)")
        } catch {
            // We don't want to show an error message here, as it might
            // overwrite a more important error from `loadArrivals`.
            print("Error loading routes: \(error.localizedDescription)")
        }
    }
    
    var upcomingArrivals: [OBAArrival] { arrivals }
}

