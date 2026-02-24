import SwiftUI

struct ExploreView: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    VehiclesView()
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
                    TripPlanningEntryView()
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
