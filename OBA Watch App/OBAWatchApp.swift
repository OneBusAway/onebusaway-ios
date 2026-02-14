//
//  OBAWatchApp.swift
//  OBAWatch Watch App
//
//  Created by Prince Yadav on 31/12/25.
//

import SwiftUI
import WatchKit
import MapKit
import CoreLocation
import Combine
import WatchConnectivity
import OBAKitCore

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
class WatchAppState: NSObject, ObservableObject, CLLocationManagerDelegate, WCSessionDelegate {
    static let shared = WatchAppState()

    /// Shared, platform-agnostic API client.
    var apiClient: OBAAPIClient

    /// The API key retrieved from Info.plist.
    private let apiKey: String

    /// Simple location manager used only on watch.
    private let locationManager: CLLocationManager

    /// Published authorization status so views can react to changes
    /// and show onboarding when needed.
    @Published var authorizationStatus: CLAuthorizationStatus
    
    /// Offset between server time and local time (server - local).
    /// Positive value means server is ahead.
    @Published var serverTimeOffset: TimeInterval = 0

    /// Watch Connectivity Session
    private let session: WCSession = .default

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

    struct RegionOption: Identifiable {
        let id: String
        let name: String
        let coordinate: CLLocationCoordinate2D
    }

    static let regions: [RegionOption] = [
        .init(id: "tampa-bay", name: "Tampa Bay", coordinate: .init(latitude: 27.9506, longitude: -82.4572)),
        .init(id: "puget-sound", name: "Puget Sound", coordinate: .init(latitude: 47.6062, longitude: -122.3321)),
        .init(id: "mta-new-york", name: "MTA New York", coordinate: .init(latitude: 40.7128, longitude: -74.0060)),
        .init(id: "washington-dc", name: "Washington, D.C.", coordinate: .init(latitude: 38.9072, longitude: -77.0369)),
        .init(id: "san-diego", name: "San Diego", coordinate: .init(latitude: 32.7157, longitude: -117.1611))
    ]

    /// Coordinates for regions defined in RegionOnboardingView
    static let regionCoordinates: [String: CLLocationCoordinate2D] = [
        "tampa-bay": .init(latitude: 27.9506, longitude: -82.4572),
        "puget-sound": .init(latitude: 47.6062, longitude: -122.3321),
        "mta-new-york": .init(latitude: 40.7128, longitude: -74.0060),
        "washington-dc": .init(latitude: 38.9072, longitude: -77.0369),
        "san-diego": .init(latitude: 32.7157, longitude: -117.1611)
    ]

    /// Base URLs for regions defined in RegionOnboardingView
    static let regionBaseURLs: [String: String] = [
        "tampa-bay": "https://api.tampa.onebusawaycloud.com/",
        "puget-sound": "https://api.pugetsound.onebusaway.org/",
        "mta-new-york": "https://bustime.mta.info/",
        "washington-dc": "https://buseta.wmata.com/onebusaway-api-webapp/",
        "san-diego": "https://realtime.sdmts.com/api/"
    ]

    /// Base URLs for OTP regions defined in RegionOnboardingView
    static let regionOTPBaseURLs: [String: String] = [
        "tampa-bay": "https://otp.prod.obahart.org/otp/",
        "puget-sound": "https://otp.prod.sound.obaweb.org/otp/routers/default/",
        "atlanta": "https://opentrip.atlantaregion.com/otp",
        "san-diego": "https://realtime.sdmts.com:9091/otp",
        "adelaide-metro": "https://otp.nautilus-tech.com.au/otp/"
    ]

    var currentOTPBaseURL: URL? {
        let regionID = Self.userDefaults.string(forKey: "watch_selected_region_id") ?? "mta-new-york"
        if let urlString = Self.regionOTPBaseURLs[regionID] {
            return URL(string: urlString)
        }
        return nil
    }

    /// Returns the location to use for nearby stops, taking into account
    /// the user's preference for sharing current location vs. using a
    /// manually selected region.
    var effectiveLocation: CLLocation {
        let shareLocation = Self.userDefaults.bool(forKey: "watch_share_current_location")
        
        if shareLocation, let loc = currentLocation {
            return loc
        }
        
        // Fallback to selected region
        let regionID = Self.userDefaults.string(forKey: "watch_selected_region_id") ?? "mta-new-york"
        if let coord = Self.regionCoordinates[regionID] {
            return CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        }
        
        return CLLocation(latitude: 40.7128, longitude: -74.0060)
    }

    /// Map settings
    @Published var showsScale: Bool {
        didSet { Self.userDefaults.set(showsScale, forKey: "watch_map_shows_scale") }
    }
    @Published var showsTraffic: Bool {
        didSet { Self.userDefaults.set(showsTraffic, forKey: "watch_map_shows_traffic") }
    }
    @Published var showsCurrentHeading: Bool {
        didSet { Self.userDefaults.set(showsCurrentHeading, forKey: "watch_map_shows_heading") }
    }
    @Published var showRouteLabels: Bool {
        didSet { Self.userDefaults.set(showRouteLabels, forKey: "watch_show_route_labels") }
    }

    var mapStyle: MapStyle {
        return .standard(elevation: .realistic)
    }

    /// Updates the current region and API client.
    func updateRegion(id: String) {
         Self.userDefaults.set(id, forKey: "watch_selected_region_id")
         
         if let urlString = Self.regionBaseURLs[id], let url = URL(string: urlString) {
             let config = OBAURLSessionAPIClient.Configuration(
                 baseURL: url,
                 apiKey: self.apiKey,
                 minutesBeforeArrivals: 5,
                 minutesAfterArrivals: 125
             )
             self.apiClient = OBAURLSessionAPIClient(configuration: config)
         }
        
        // Notify listeners that location/region might have changed
        NotificationCenter.default.post(name: NSNotification.Name("LocationUpdated"), object: nil)
    }

    private var configCancellable: AnyCancellable?

    /// Shared user defaults for the app group
    static let userDefaults: UserDefaults = {
        if let appGroup = Bundle.main.object(forInfoDictionaryKey: "OBAKitConfig") as? [String: Any],
           let suiteName = appGroup["AppGroup"] as? String {
            return UserDefaults(suiteName: suiteName) ?? .standard
        }
        return .standard
    }()

    private override init() {
        // Create local manager and API configuration first, so all stored
        // properties can be initialized before calling super.init().
        let manager = CLLocationManager()
        
        let defaults = Self.userDefaults

        // Use the saved region if available, otherwise fall back to MTA New York.
        let savedRegionID = defaults.string(forKey: "watch_selected_region_id") ?? "mta-new-york"
        let baseURLString = Self.regionBaseURLs[savedRegionID] ?? "https://bustime.mta.info"
        let baseURL = URL(string: baseURLString)!
        
        let obaConfig = Bundle.main.object(forInfoDictionaryKey: "OBAKitConfig") as? [String: Any]
        let apiKeyFromPlist = (obaConfig?["RESTServerAPIKey"] as? String) ?? "org.onebusaway.iphone"
        self.apiKey = apiKeyFromPlist
        
        let config = OBAURLSessionAPIClient.Configuration(
            baseURL: baseURL,
            apiKey: apiKeyFromPlist,
            minutesBeforeArrivals: 5,
            minutesAfterArrivals: 125
        )

        // Initialize map settings from UserDefaults
        self.showsScale = defaults.bool(forKey: "watch_map_shows_scale")
        self.showsTraffic = defaults.bool(forKey: "watch_map_shows_traffic")
        self.showsCurrentHeading = defaults.object(forKey: "watch_map_shows_heading") as? Bool ?? true
        self.showRouteLabels = defaults.object(forKey: "watch_show_route_labels") as? Bool ?? true

        // Initialize stored properties.
        self.locationManager = manager
        self.authorizationStatus = CLLocationManager.authorizationStatus()
        
        // Initialize sync managers so they start listening for updates.
        _ = BookmarksSyncManager.shared
        _ = AlarmsSyncManager.shared

        self.apiClient = OBAURLSessionAPIClient(configuration: config)

        super.init()

        // Configure Watch Connectivity
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        }

        // Finish configuring the location manager.
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        
        // Sync time with server
        Task {
            await syncTime()
        }
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            Logger.error("WCSession activation failed: \(error.localizedDescription)")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        // Forward to managers
        Task { @MainActor in
            if let bookmarks = userInfo["bookmarks"] as? [[String: Any]] {
                BookmarksSyncManager.shared.updateBookmarks(bookmarks)
            }
            if let alerts = userInfo["alerts"] as? [[String: Any]] {
                ServiceAlertsSyncManager.shared.updateAlerts(alerts)
            }
            if let alarms = userInfo["alarms"] as? [[String: Any]] {
                AlarmsSyncManager.shared.updateAlarms(alarms)
            }
        }
    }

    /// Sends a request to the paired iPhone to perform an action.
    func sendMessageToPhone(_ message: [String: Any]) {
        guard session.activationState == .activated else { return }
        session.transferUserInfo(message)
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
            Logger.error("syncTime failed: \(error.localizedDescription)")
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
