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
                Button("Plan From My Location") {
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
                }
                .alert("Location Access Required", isPresented: $showingLocationAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Please enable location access in the Watch app settings to plan a trip from your current location.")
                }
                NavigationLink {
                    AddressSearchView()
                } label: {
                    Text("Plan From Searched Address")
                }
            }
        }
        .navigationTitle("Trip Planning")
    }
}
