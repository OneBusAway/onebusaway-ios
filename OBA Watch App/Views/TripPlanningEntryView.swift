import SwiftUI
import CoreLocation

struct TripPlanningEntryView: View {
    @EnvironmentObject private var appState: WatchAppState
    @State private var planningFromLocation = false
    @State private var planningFromAddress = false
    @State private var showingLocationAlert = false
    
    var body: some View {
        List {
            Section {
                Button {
                    if let loc = appState.currentLocation?.coordinate {
                        DeepLinkSyncManager.shared.planTripOnPhone(
                            originLat: loc.latitude,
                            originLon: loc.longitude,
                            destLat: nil,
                            destLon: nil
                        )
                    } else {
                        showingLocationAlert = true
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "location.fill")
                            .font(.headline)
                            .foregroundColor(.blue)
                        VStack(alignment: .leading) {
                            Text("Current Location")
                                .font(.headline)
                            Text("Start trip from here")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .alert("Location Access Required", isPresented: $showingLocationAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Please enable location access in the Watch app settings to plan a trip from your current location.")
                }

                NavigationLink {
                    AddressSearchView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.headline)
                            .foregroundColor(.purple)
                        VStack(alignment: .leading) {
                            Text("Search Address")
                                .font(.headline)
                            Text("Enter a destination")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Plan a Trip")
            } footer: {
                Text("Selecting an option will open the trip planner on your iPhone.")
            }
        }
        .navigationTitle("Trip Planning")
    }
}
