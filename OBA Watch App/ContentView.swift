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
    @AppStorage("watch_has_completed_region_onboarding") private var hasCompletedRegionOnboarding: Bool = false
    @AppStorage("watch_map_style_standard") private var useStandardMapStyle: Bool = true
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
            .navigationTitle("OneBusAway")
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
        VStack(spacing: 12) {
            Image(systemName: "location.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(.green)
            Text("Enable Location")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Allow access to your location to find nearby transit stops.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button {
                appState.requestLocationPermission()
            } label: {
                Label("Use Current Location", systemImage: "location.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Region Selection Onboarding

/// Second step of onboarding: lets the user pick a service region in a
/// watch-appropriate way, inspired by the iOS "Choose Region" screen.
struct RegionOnboardingView: View {
    @EnvironmentObject var appState: WatchAppState
    
    @AppStorage("watch_selected_region_id") private var selectedRegionID: String = "mta-new-york"
    @AppStorage("watch_share_current_location") private var shareCurrentLocation: Bool = true

    let onContinue: () -> Void

    @State private var mapRegion: MKCoordinateRegion

    init(onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
        
        // Use the saved region if available, otherwise fall back to MTA New York.
        let savedRegionID = UserDefaults.standard.string(forKey: "watch_selected_region_id") ?? "mta-new-york"
        
        let initialCoordinate = WatchAppState.regionCoordinates[savedRegionID] ?? CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        
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
                        Text("Share Current Location")
                            .font(.headline)
                    }
                }
            }

            Section {
                ForEach(WatchAppState.regions) { region in
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
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(shareCurrentLocation ? .green : .gray)
            }
        }
    }
}

// MARK: - Settings

/// Compact "More" screen for watchOS, inspired by the iOS More tab.
struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("OneBusAway")
                            .font(.headline)
                        Text("This app is made and supported by volunteers.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("More")
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var appState: WatchAppState
    @AppStorage("watch_selected_region_id") private var selectedRegionID: String = "mta-new-york"
    
    // Map
    @AppStorage("watch_map_style_standard") private var useStandardMapStyle: Bool = true
    @AppStorage("watch_map_shows_scale") private var showsScale: Bool = false
    @AppStorage("watch_map_shows_traffic") private var showsTraffic: Bool = false
    @AppStorage("watch_map_shows_heading") private var showsCurrentHeading: Bool = true

    // Location
    @AppStorage("watch_share_current_location") private var shareCurrentLocation: Bool = true

    // Agency Alerts
    @AppStorage("watch_display_test_alerts") private var displayTestAlerts: Bool = false

    // Accessibility
    @AppStorage("watch_haptic_on_reload") private var hapticOnReload: Bool = false
    @AppStorage("watch_always_show_full_sheet_voice") private var alwaysShowFullSheetVoice: Bool = false
    @AppStorage("watch_show_route_labels") private var showRouteLabels: Bool = true

    // Debug
    @AppStorage("watch_debug_mode") private var debugMode: Bool = false

    // Privacy
    @AppStorage("watch_send_usage_data") private var sendUsageData: Bool = true

    var body: some View {
        List {
            Section("Region") {
                NavigationLink {
                    ChooseRegionView()
                } label: {
                    HStack {
                        Text("Choose Region")
                        Spacer()
                        Text(WatchAppState.regions.first(where: { $0.id == selectedRegionID })?.name ?? "Unknown")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section("Map") {
                Toggle("Standard map style", isOn: $useStandardMapStyle)
                Toggle("Shows scale", isOn: $showsScale)
                Toggle("Shows traffic", isOn: $showsTraffic)
                Toggle("Show my current heading", isOn: $showsCurrentHeading)
            }

            Section("Location") {
                Toggle("Share current location", isOn: $shareCurrentLocation)
            }

            Section("Agency Alerts") {
                Toggle("Display test alerts", isOn: $displayTestAlerts)
            }

            Section("Accessibility") {
                Toggle("Haptic feedback on reload", isOn: $hapticOnReload)
                Toggle("Always show full sheet on VoiceOver", isOn: $alwaysShowFullSheetVoice)
                Toggle("Show route labels on the map", isOn: $showRouteLabels)
            }

            Section("Debug") {
                Toggle("Debug Mode", isOn: $debugMode)
            }

            Section("Privacy") {
                Toggle("Send usage data to developer", isOn: $sendUsageData)
            }
        }
        .navigationTitle("Settings")
    }
}

struct ChooseRegionView: View {
    @EnvironmentObject var appState: WatchAppState
    @AppStorage("watch_selected_region_id") private var selectedRegionID: String = "mta-new-york"
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        List {
            ForEach(WatchAppState.regions) { region in
                Button {
                    appState.updateRegion(id: region.id)
                    dismiss()
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
        .navigationTitle("Choose Region")
    }
}

/// Simple map showing the selected region from onboarding, with nearby stops.
struct RegionPreviewMapView: View {
    @AppStorage("watch_selected_region_id") private var selectedRegionID: String = "mta-new-york"
    @AppStorage("watch_map_style_standard") private var useStandardMapStyle: Bool = true
    @StateObject private var viewModel = RegionPreviewMapViewModel()

    private var centerCoordinate: CLLocationCoordinate2D {
        switch selectedRegionID {
        case "tampa-bay":
            return .init(latitude: 27.9506, longitude: -82.4572)
        case "puget-sound":
            return .init(latitude: 47.6062, longitude: -122.3321)
        case "washington-dc":
            return .init(latitude: 38.9072, longitude: -77.0369)
        case "san-diego":
            return .init(latitude: 32.7157, longitude: -117.1611)
        default: // "mta-new-york" and fallback
            return .init(latitude: 40.7128, longitude: -74.0060)
        }
    }

    var body: some View {
        let region = MKCoordinateRegion(
            center: centerCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
        )

        let style: MapStyle = useStandardMapStyle ? .standard : .imagery

        ZStack(alignment: .topTrailing) {
            if !viewModel.stops.isEmpty {
                let previewLocation = CLLocation(latitude: centerCoordinate.latitude, longitude: centerCoordinate.longitude)
                NearbyMapView(
                    stops: Array(viewModel.stops.prefix(60)),
                    currentLocation: previewLocation,
                    mapStyle: style
                )
            } else {
                Map(coordinateRegion: .constant(region))
                    .mapStyle(style)
            }

            Button {
                useStandardMapStyle.toggle()
            } label: {
                Image(systemName: useStandardMapStyle ? "globe.americas.fill" : "map")
                    .font(.system(size: 12, weight: .medium))
                    .padding(6)
                    .background(.thinMaterial)
                    .clipShape(Circle())
            }
            .padding(8)
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
            // For the preview map, we silently ignore errors and leave the base map.
        }
    }
}

/// Main menu shown after permission has been handled.
struct MainMenuView: View {
    @AppStorage("watch_selected_region_id") private var selectedRegionID: String = "mta-new-york"
    
    private var regionName: String {
        switch selectedRegionID {
        case "tampa-bay": return "Tampa Bay"
        case "puget-sound": return "Puget Sound"
        case "mta-new-york": return "MTA New York"
        case "washington-dc": return "Washington, D.C."
        case "san-diego": return "San Diego"
        default: return "OneBusAway"
        }
    }
    
    var body: some View {
        List {
            // Search & Map at the top
            Section {
                NavigationLink {
                    SearchView()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
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
                    Label("Bookmarks", systemImage: "bookmark.fill")
                        .foregroundColor(.blue)
                }
            }

            // Trip Planning Section - Make this prominent
            Section {
                NavigationLink {
                    TripPlanningEntryView()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Trip Planner", systemImage: "figure.walk")
                            .font(.headline)
                            .foregroundColor(.green)
                        Text("Plan your journey")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Plan")
            }
            
            // Other useful actions but minimized
            Section {
                NavigationLink {
                    NearbyStopsView()
                } label: {
                    Label("Nearby", systemImage: "location.fill")
                }

                NavigationLink {
                    RecentStopsView()
                } label: {
                    Label("Recents", systemImage: "clock.fill")
                }
                
                NavigationLink {
                    VehiclesView()
                } label: {
                    Label("Vehicles", systemImage: "bus.fill")
                }
            } header: {
                Text("Explore")
            }
        }
        .navigationTitle(regionName)
    }
}

#Preview {
    ContentView()
        .environmentObject(WatchAppState.shared)
}
