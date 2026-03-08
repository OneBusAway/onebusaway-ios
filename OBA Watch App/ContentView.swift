//
//  ContentView.swift
//  OBAWatch Watch App
//
//  Created by Prince Yadav on 31/12/25.
//

import SwiftUI
import MapKit
import CoreLocation
import Combine
import OBAKitCore

struct ContentView: View {
    @EnvironmentObject var appState: WatchAppState
    @AppStorage("watch_has_completed_region_onboarding", store: WatchAppState.userDefaults) private var hasCompletedRegionOnboarding: Bool = false
    @State private var showingMore = false
    
    var body: some View {
        NavigationStack {
            Group {
                if appState.authorizationStatus == .notDetermined {
                    LocationOnboardingView()
                } else if !hasCompletedRegionOnboarding {
                    RegionOnboardingView(onContinue: {
                        hasCompletedRegionOnboarding = true
                    })
                } else {
                    MainMenuView()
                }
            }
            .navigationTitle(OBALoc("common.app_name", value: "OneBusAway", comment: "The name of the application"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showingMore = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(isPresented: $showingMore) {
                MoreView()
            }
        }
    }
}

/// Simple first-run screen that encourages the user to enable location
/// so that Nearby Stops works as expected.
struct LocationOnboardingView: View {
    @EnvironmentObject var appState: WatchAppState
    
    var body: some View {
        VStack(spacing: 0) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)
                .cornerRadius(12)
                .shadow(color: .green.opacity(0.3), radius: 4)
                .padding(.top, 24)
            
            VStack(spacing: 2) {
                Text(OBALoc("location_onboarding.nearby_transit", value: "Nearby Transit", comment: "Title for the location onboarding screen"))
                    .font(.system(size: 17, weight: .bold))
                    .multilineTextAlignment(.center)
                
                Text(OBALoc("location_onboarding.description", value: "Find stops and schedules based on where you are.", comment: "Description for the location onboarding screen"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
            
            Spacer(minLength: 4)
            
            Button {
                appState.requestLocationPermission()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 14, weight: .semibold))

                    Text(OBALoc("location_onboarding.allow_access", value: "Allow Access", comment: "Button title to request location permission"))
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Color.green)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .modifier(GlassCapsuleModifier())
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
        }
        .containerBackground(Color.black.gradient, for: .navigation)
    }
}

// MARK: - Region Selection Onboarding

/// Second step of onboarding: lets the user pick a service region in a
/// watch-appropriate way, inspired by the iOS "Choose Region" screen.
struct RegionOnboardingView: View {
    @EnvironmentObject var appState: WatchAppState
    
    @AppStorage("watch_selected_region_id", store: WatchAppState.userDefaults) private var selectedRegionID: String = "mta-new-york"
    @AppStorage("watch_share_current_location", store: WatchAppState.userDefaults) private var shareCurrentLocation: Bool = true

    let onContinue: () -> Void

    @State private var mapRegion: MKCoordinateRegion

    init(onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
        
        // Use the saved region if available, otherwise fall back to MTA New York.
        let savedRegionID = WatchAppState.userDefaults.string(forKey: "watch_selected_region_id") ?? "mta-new-york"
        
        let region = WatchAppState.shared.regions.first(where: { $0.id == savedRegionID })
        let initialCoordinate = region?.coordinate ?? CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        
        _mapRegion = State(initialValue: MKCoordinateRegion(
            center: initialCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 3.0, longitudeDelta: 3.0)
        ))
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: $shareCurrentLocation) {
                    HStack {
                        Image(systemName: "globe")
                            .foregroundColor(.green)
                        Text(OBALoc("region_onboarding.share_location", value: "Share Current Location", comment: "Option to share current location"))
                            .font(.headline)
                    }
                }
            }

            Section {
                ForEach(appState.regions.filter { $0.obaBaseURL != nil }) { region in
                    Button {
                        appState.updateRegion(id: region.id)
                        mapRegion.center = region.coordinate
                    } label: {
                        HStack {
                            Text(region.name)
                            Spacer()
                            if region.id == selectedRegionID {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }
            }

            Section {
                Map(coordinateRegion: $mapRegion)
                    .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .listRowInsets(EdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2))
                    .listRowBackground(Color.clear)
            }

            Section {
                Button(action: onContinue) {
                    Text(OBALoc("common.continue", value: "Continue", comment: "Button title to continue"))
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .modifier(GlassCapsuleModifier())
                .foregroundStyle(shareCurrentLocation ? Color.green : Color.gray)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .padding(.horizontal, 4)
                .padding(.bottom, 10)
            }
        }
    }
}

// MARK: - Settings

struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label(OBALoc("common.settings", value: "Settings", comment: "Title for settings menu item"), systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle(OBALoc("common.more", value: "More", comment: "Title for the More screen"))
        }
    }
}

/// Simple map showing the selected region from onboarding, with nearby stops.
struct RegionPreviewMapView: View {
    @EnvironmentObject var appState: WatchAppState
    @AppStorage("watch_selected_region_id", store: WatchAppState.userDefaults) private var selectedRegionID: String = "mta-new-york"
    @StateObject private var viewModel = RegionPreviewMapViewModel()

    private var centerCoordinate: CLLocationCoordinate2D {
        if let region = appState.regions.first(where: { $0.id == selectedRegionID }) {
            return region.coordinate
        }
        return .init(latitude: 40.7128, longitude: -74.0060)
    }

    var body: some View {
        let region = MKCoordinateRegion(
            center: centerCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
        )

        ZStack(alignment: .topTrailing) {
            if !viewModel.stops.isEmpty {
                let previewLocation = CLLocation(latitude: centerCoordinate.latitude, longitude: centerCoordinate.longitude)
                NearbyMapView(
                    stops: Array(viewModel.stops.prefix(60)),
                    currentLocation: previewLocation,
                    mapStyle: appState.mapStyle
                )
                .id("standard")
            } else {
                Map(coordinateRegion: .constant(region))
                    .mapStyle(appState.mapStyle)
                    .id("standard")
            }
        }
        .onAppear {
            Task {
                await viewModel.loadStops(around: centerCoordinate, apiClient: WatchAppState.shared.apiClient)
            }
        }
    }
}

@MainActor
final class RegionPreviewMapViewModel: ObservableObject {
    @Published var stops: [OBAStop] = []

    func loadStops(around coordinate: CLLocationCoordinate2D, apiClient: OBAAPIClient) async {
        do {
            let fetched = try await apiClient.fetchNearbyStops(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                radius: 1500.0
            )
            stops = fetched.stops
        } catch {
            Logger.error("Failed to load stops for preview map: \(error)")
            // For the preview map, we silently ignore errors and leave the base map.
        }
    }
}

/// Main menu shown after permission has been handled.
struct MainMenuView: View {
    @EnvironmentObject var appState: WatchAppState
    @AppStorage("watch_selected_region_id", store: WatchAppState.userDefaults) private var selectedRegionID: String = "mta-new-york"
    /// Becomes true only after the debounce window closes without a successful sync,
    /// preventing a flash on normal fast launches.
    @State private var showTimeSyncWarning: Bool = false

    private var regionName: String {
        return appState.regions.first(where: { $0.id == selectedRegionID })?.name ?? OBALoc("common.app_name", value: "OneBusAway", comment: "The name of the application")
    }
    
    var body: some View {
        List {
            // Time sync warning — shown only if all retry attempts failed.
            if showTimeSyncWarning && !appState.timeSyncSucceeded {
                Section {
                    Button {
                        Task { await appState.syncTime() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.badge.exclamationmark")
                                .foregroundColor(.yellow)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(OBALoc("time_sync.warning.title", value: "Clock Sync Failed", comment: "Warning: time sync failed"))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.yellow)
                                Text(OBALoc("time_sync.warning.subtitle", value: "Arrival times may be inaccurate. Tap to retry.", comment: "Warning subtitle for time sync failure"))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.yellow.opacity(0.12))
                )
            }

            // Search & Map at the top
            Section {
                NavigationLink {
                    SearchView()
                } label: {
                    Label(OBALoc("common.search", value: "Search", comment: "Title for search menu item"), systemImage: "magnifyingglass")
                        .font(.headline)
                }
            }

            Section {
                RegionPreviewMapView()
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .listRowInsets(EdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2))
                    .listRowBackground(Color.clear)
            }

            // Bookmarks Section - Keep this because user asked to fix it!
            Section {
                NavigationLink {
                    BookmarksView()
                } label: {
                    Label(OBALoc("common.bookmarks", value: "Bookmarks", comment: "Title for bookmarks menu item"), systemImage: "bookmark.fill")
                        .foregroundColor(.blue)
                }
            }

            // Trip Planning Section - Make this prominent
            Section {
                NavigationLink {
                    TripPlanningEntryView()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(OBALoc("common.trip_planner", value: "Trip Planner", comment: "Title for trip planner menu item"), systemImage: "figure.walk")
                            .font(.headline)
                            .foregroundColor(.green)
                        Text(OBALoc("main_menu.plan_your_journey", value: "Plan your journey", comment: "Subtitle for trip planner menu item"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text(OBALoc("main_menu.section.plan", value: "Plan", comment: "Section header for planning"))
            }
            
            // Other useful actions but minimized
            Section {
                NavigationLink {
                    NearbyStopsView()
                } label: {
                    Label(OBALoc("common.nearby", value: "Nearby", comment: "Title for nearby stops menu item"), systemImage: "location.fill")
                }

                NavigationLink {
                    RecentStopsView()
                } label: {
                    Label(OBALoc("common.recents", value: "Recents", comment: "Title for recent stops menu item"), systemImage: "clock.fill")
                }
                
                NavigationLink {
                    VehiclesView()
                } label: {
                    Label(OBALoc("common.vehicles", value: "Vehicles", comment: "Title for vehicles menu item"), systemImage: "bus.fill")
                }
            } header: {
                Text(OBALoc("main_menu.section.explore", value: "Explore", comment: "Section header for explore"))
            }
        }
        .navigationTitle(regionName)
        .onAppear {
            // Show the warning only after a 15-second window, so it doesn't
            // flash briefly on fast connections where sync completes quickly.
            Task {
                do {
                    try await Task.sleep(nanoseconds: 15 * 1_000_000_000)
                    showTimeSyncWarning = true
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            }
        }
        .onChange(of: appState.timeSyncSucceeded) { _, succeeded in
            if succeeded { showTimeSyncWarning = false }
        }
    }
}


struct GlassCapsuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(watchOS 26.0, *) {
            content
                .glassEffect(in: Capsule())
        } else {
            content
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                )
        }
    }
}



#Preview {
    ContentView()
        .environmentObject(WatchAppState.shared)
}
