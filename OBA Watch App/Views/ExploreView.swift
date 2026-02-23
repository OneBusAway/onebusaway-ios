import SwiftUI

struct ExploreView: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    // TODO: Implement VehiclesView in PR3/PR4
                    // VehiclesView()
                    Text(OBALoc("explore.vehicles_coming_soon", value: "Vehicles Coming Soon", comment: "Placeholder text for vehicles feature"))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bus.fill")
                            .foregroundColor(.blue)
                        Text(OBALoc("explore.vehicles", value: "Vehicles", comment: "Button title for vehicles"))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(12)
                }
                NavigationLink {
                    // TODO: Implement TripPlanningEntryView in PR3/PR4
                    // TripPlanningEntryView()
                    Text(OBALoc("explore.trip_planning_coming_soon", value: "Trip Planning Coming Soon", comment: "Placeholder text for trip planning feature"))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.walk")
                            .foregroundColor(.purple)
                        Text(OBALoc("explore.trip_planning", value: "Trip Planning", comment: "Button title for trip planning"))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.purple.opacity(0.15))
                    .cornerRadius(12)
                }
            }
        }
        .navigationTitle(OBALoc("explore.title", value: "Explore", comment: "Title for explore screen"))
    }
}
