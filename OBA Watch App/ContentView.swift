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
        VStack(spacing: 0) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)
                .cornerRadius(12)
                .shadow(color: .green.opacity(0.3), radius: 4)
                .padding(.top, 24)
            
            VStack(spacing: 2) {
                Text("Nearby Transit")
                    .font(.system(size: 17, weight: .bold))
                    .multilineTextAlignment(.center)
                
                Text("Find stops and schedules based on where you are.")
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

                    Text("Allow Access")
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
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("More")
        }
    }
}

/// Simple map showing the selected region from onboarding, with nearby stops.
struct RegionPreviewMapView: View {
    @EnvironmentObject var appState: WatchAppState
    @AppStorage("watch_selected_region_id", store: WatchAppState.userDefaults) private var selectedRegionID: String = "mta-new-york"
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
            // For the preview map, we silently ignore errors and leave the base map.
        }
    }
}

/// Main menu shown after permission has been handled.
struct MainMenuView: View {
    @AppStorage("watch_selected_region_id", store: WatchAppState.userDefaults) private var selectedRegionID: String = "mta-new-york"
    
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
