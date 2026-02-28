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
        defer { isLoading = false }
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

                // Save to recent stops using real coordinates if the server returned them.
                saveToRecentStops(
                    name: fetchedName,
                    code: result.stopCode,
                    direction: result.stopDirection,
                    latitude: result.stopLatitude,
                    longitude: result.stopLongitude
                )
            }
            
            lastUpdated = Date()
        } catch {
            errorMessage = error.watchOSUserFacingMessage
        }
        
    }

    private func saveToRecentStops(
        name: String,
        code: String? = nil,
        direction: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        let routeNames = routes.compactMap { $0.shortName }.joined(separator: ", ")

        // Use real server coordinates when available; fall back to 0,0 only as a
        // last resort. Views that show distance should check for the zero sentinel
        // and suppress the distance label in that case.
        let lat = latitude ?? 0.0
        let lon = longitude ?? 0.0
        if lat == 0.0 && lon == 0.0 {
            Logger.warn("saveToRecentStops: No coordinates available for stop \(stopID) — distance display will be suppressed in views.")
        }

        let stop = OBAStop(
            id: stopID,
            name: name,
            latitude: lat,
            longitude: lon,
            code: code,
            direction: direction,
            routeNames: routeNames.isEmpty ? nil : routeNames
        )

        RecentStopsViewModel.shared.addRecentStop(stop)

        // Notify other views
        NotificationCenter.default.post(name: NSNotification.Name("RecentStopsUpdated"), object: nil)
    }

    func loadRoutes() async {
        let apiClient = apiClientProvider()
        do {
            let fetched = try await apiClient.fetchRoutesForStop(stopID: stopID)
            routes = fetched
        } catch let apiError as OBAAPIError {
            Logger.error("loadRoutes failed: \(apiError)")
        } catch {
            Logger.error("loadRoutes failed with unknown error: \(error)")
            // We don't want to show an error message here, as it might
            // overwrite a more important error from `loadArrivals`.
        }
    }
    
    var upcomingArrivals: [OBAArrival] { arrivals }
}

