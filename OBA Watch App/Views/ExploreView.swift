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
                        Text("Vehicles")
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
                        Text("Trip Planning")
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
        .navigationTitle("Explore")
    }
}
