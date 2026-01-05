//
//  OBAWatchApp.swift
//  OBAWatch Watch App
//
//  Created by Prince Yadav on 31/12/25.
//

import SwiftUI
import WatchKit
import CoreLocation
import Combine
import OBASharedCore

@main
struct OBAWatch_App: App {
    @StateObject private var appState = WatchAppState.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}

// MARK: - Watch App State

@MainActor
class WatchAppState: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WatchAppState()

    /// Shared, platform-agnostic API client.
    var apiClient: OBAAPIClient

    /// Simple location manager used only on watch.
    private let locationManager: CLLocationManager

    /// Published authorization status so views can react to changes
    /// and show onboarding when needed.
    @Published var authorizationStatus: CLAuthorizationStatus
    
    /// Offset between server time and local time (server - local).
    /// Positive value means server is ahead.
    @Published var serverTimeOffset: TimeInterval = 0

    /// Last known location, if available.
    /// On the simulator, CoreLocation may not provide a real location unless a
    /// simulated location is configured. To make development easier, we fall
    /// back to a fixed test coordinate when running in the simulator.
    var currentLocation: CLLocation? {
        #if targetEnvironment(simulator)
        if let realLocation = locationManager.location {
            return realLocation
        } else {
            // Midtown Manhattan, for testing.
            return CLLocation(latitude: 40.7580, longitude: -73.9855)
        }
        #else
        return locationManager.location
        #endif
    }

    private var configCancellable: AnyCancellable?

    private override init() {
        // Create local manager and API configuration first, so all stored
        // properties can be initialized before calling super.init().
        let manager = CLLocationManager()

        // Configure shared API client.
        // For now, mirror the iOS app's MTA New York configuration so that
        // arrivals/nearby behavior matches the phone: same region base URL
        // and arrivals time window.
        let baseURL = URL(string: "https://bustime.mta.info")!
        let obaConfig = Bundle.main.object(forInfoDictionaryKey: "OBAKitConfig") as? [String: Any]
        let apiKeyFromPlist = (obaConfig?["RESTServerAPIKey"] as? String) ?? "org.onebusaway.iphone"
        let config = OBAURLSessionAPIClient.Configuration(
            baseURL: baseURL,
            apiKey: apiKeyFromPlist,
            minutesBeforeArrivals: 5,
            minutesAfterArrivals: 125
        )

        // Initialize stored properties.
        self.locationManager = manager
        self.authorizationStatus = CLLocationManager.authorizationStatus()
        self.apiClient = OBAURLSessionAPIClient(configuration: config)

        super.init()

        // Finish configuring the location manager.
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        
        // Sync time with server
        Task {
            await syncTime()
        }

        configCancellable = WatchConnectivityService.shared.$currentConfiguration.sink { [weak self] configuration in
            guard let self = self, let configuration = configuration else { return }
            self.apiClient = OBAURLSessionAPIClient(configuration: configuration)
        }
    }

    /// Syncs local time with server time to ensure accurate predictions.
    func syncTime() async {
        do {
            let serverTime = try await apiClient.fetchCurrentTime()
            let localTime = Date()
            // serverTimeOffset = serverTime - localTime
            // Adjusted Time = Date() + offset
            self.serverTimeOffset = serverTime.timeIntervalSince(localTime)
        } catch {
            print("Failed to sync time: \(error)")
        }
    }
    
    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
        }
    }

    /// Explicitly re-requests location authorization. On watchOS, if the user
    /// has previously denied access, they may need to enable it from Settings.
    /// This is still useful for the initial prompt from the onboarding screen.
    func requestLocationPermission() {
        #if targetEnvironment(simulator)
        // In the simulator, CoreLocation prompts can be unreliable. To allow
        // UI testing of the rest of the watch app, optimistically mark the
        // status as authorized so the onboarding screen can dismiss.
        authorizationStatus = .authorizedWhenInUse
        #endif
        locationManager.requestWhenInUseAuthorization()
    }
}
