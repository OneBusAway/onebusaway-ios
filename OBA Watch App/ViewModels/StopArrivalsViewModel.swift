//
//  StopArrivalsViewModel.swift
//  OBAWatch Watch App
//
//  Created by Prince Yadav on 31/12/25.
//

import Foundation
import SwiftUI
import Combine
import OBASharedCore

@MainActor
class StopArrivalsViewModel: ObservableObject {
    @Published var arrivals: [OBAArrival] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?
    @Published var routes: [OBARoute] = []
    
    private let apiClient: OBAAPIClient
    private let stopID: OBAStopID
    private var updateTimer: Timer?
    
    init(apiClient: OBAAPIClient, stopID: OBAStopID) {
        self.apiClient = apiClient
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
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }

        do {
            let fetched = try await apiClient.fetchArrivals(for: stopID)
            arrivals = fetched
            lastUpdated = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadRoutes() async {
        do {
            let fetched = try await apiClient.fetchRoutesForStop(stopID: stopID)
            routes = fetched
        } catch {
            // We don't want to show an error message here, as it might
            // overwrite a more important error from `loadArrivals`.
            print("Error loading routes: \(error.localizedDescription)")
        }
    }
    
    var upcomingArrivals: [OBAArrival] { arrivals }
}

