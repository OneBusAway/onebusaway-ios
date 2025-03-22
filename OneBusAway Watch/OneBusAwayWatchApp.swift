//
//  OneBusAwayWatchApp.swift
//  OBAKit
//
//  Created by Prince Yadav on 06/03/25.
//

import SwiftUI
import UserNotifications

@main
struct OneBusAwayWatchApp: App {
    @StateObject private var stopsViewModel = StopsViewModel()
    @StateObject private var favoritesViewModel = FavoritesViewModel()
    @StateObject private var connectivityService = WatchConnectivityService.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var locationManager = LocationManager.shared

    @SceneBuilder var body: some Scene {
        WindowGroup {
            NavigationView {
                HomeView()
                    .environmentObject(stopsViewModel)
                    .environmentObject(favoritesViewModel)
                    .environmentObject(connectivityService)
                    .environmentObject(networkMonitor)
                    .environmentObject(locationManager)
                    .tint(AppColors.primaryText) // Apply global tint color
                    .toolbarBackground(Color(.black).opacity(0.8), for: .navigationBar) // Updated appearance
            }
        }
    }

    init() {
        registerBackgroundTasks()
        importIconsFromIOSApp()
    }

    private func registerBackgroundTasks() {
        // Request notification authorization
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                print("Notification authorization granted")
            } else if let error = error {
                print("Notification authorization denied: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Removed `configureAppearance()`, Replaced with SwiftUI Styling

private func importIconsFromIOSApp() {
    print("Icons imported from iOS app")
}
