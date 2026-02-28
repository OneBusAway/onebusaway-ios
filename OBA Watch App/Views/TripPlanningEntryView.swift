import SwiftUI
import CoreLocation

struct TripPlanningEntryView: View {
    @EnvironmentObject private var appState: WatchAppState
    @State private var planningFromLocation = false
    @State private var planningFromAddress = false
    @State private var showingLocationAlert = false
    @State private var infoMessage: String?
    
    var body: some View {
        List {
            Section {
                Button {
                    if let loc = appState.currentLocation?.coordinate {
                        let ok = DeepLinkSyncManager.shared.planTripOnPhone(
                            originLat: loc.latitude,
                            originLon: loc.longitude,
                            destLat: nil,
                            destLon: nil
                        )
                        if !ok {
                            infoMessage = OBALoc("deeplink.failure", value: "Unable to contact iPhone. Make sure your devices are connected.", comment: "Deep link failure")
                        }
                    } else {
                        showingLocationAlert = true
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "location.fill")
                            .font(.headline)
                            .foregroundColor(.blue)
                        VStack(alignment: .leading) {
                            Text(OBALoc("trip_planning.current_location", value: "Current Location", comment: "Current location option"))
                                .font(.headline)
                            Text(OBALoc("trip_planning.start_here", value: "Start trip from here", comment: "Start trip from here"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .alert(OBALoc("trip_planning.location_required.title", value: "Location Access Required", comment: "Alert title"), isPresented: $showingLocationAlert) {
                    Button(OBALoc("common.ok", value: "OK", comment: "OK button"), role: .cancel) {}
                } message: {
                    Text(OBALoc("trip_planning.location_required.message", value: "Please enable location access in the Watch app settings to plan a trip from your current location.", comment: "Location required message"))
                }

                NavigationLink {
                    AddressSearchView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.headline)
                            .foregroundColor(.purple)
                        VStack(alignment: .leading) {
                            Text(OBALoc("trip_planning.search_address", value: "Search Address", comment: "Search address option"))
                                .font(.headline)
                            Text(OBALoc("trip_planning.enter_destination", value: "Enter a destination", comment: "Enter destination"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text(OBALoc("trip_planning.header", value: "Plan a Trip", comment: "Plan a Trip header"))
            } footer: {
                Text(OBALoc("trip_planning.footer", value: "Selecting an option will open the trip planner on your iPhone.", comment: "Footer hint"))
            }
        }
        .navigationTitle(OBALoc("trip_planning.title", value: "Trip Planning", comment: "Trip Planning title"))
        .alert(OBALoc("common.info", value: "Info", comment: "Alert title for information"), isPresented: Binding(
            get: { infoMessage != nil },
            set: { if !$0 { infoMessage = nil } }
        )) {
            Button(OBALoc("common.ok", value: "OK", comment: "OK button"), role: .cancel) {}
        } message: {
            Text(infoMessage ?? "")
        }
    }
}
