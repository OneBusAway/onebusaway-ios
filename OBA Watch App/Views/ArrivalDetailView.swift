import SwiftUI
import OBAKitCore

struct ArrivalDetailView: View {
    let arrival: OBAArrival

    @State private var showTripProblem = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // Route badge
                Text(arrival.routeShortName ?? arrival.routeID)
                    .font(.system(size: 22, weight: .bold))
                    .padding(.vertical, 4)

                if let headsign = arrival.headsign, !headsign.isEmpty {
                    Text(headsign)
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                }

                HStack(spacing: 6) {
                    if arrival.isPredicted {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                        Text("Real-time")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if let status = arrival.scheduleStatusLabel {
                        Text(status)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Route details
                if let routeShortName = arrival.routeShortName {
                    NavigationLink {
                        RouteDetailView(route: OBARoute(
                            id: arrival.routeID,
                            shortName: routeShortName,
                            longName: nil,
                            agencyName: nil
                        ))
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "bus.fill")
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Route \(routeShortName)")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("View route details")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Trip Schedule Link
                NavigationLink {
                    TripDetailsView(
                        tripID: arrival.tripID,
                        vehicleID: arrival.vehicleID,
                        routeShortName: arrival.routeShortName,
                        headsign: arrival.headsign,
                        initialTrip: arrival.toTripForLocation()
                    )
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet.rectangle.portrait")
                            .foregroundColor(.blue)
                        Text("View Trip Schedule")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                
                Button {
                    showTripProblem = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.bubble")
                            .foregroundColor(.red)
                        Text("Report Trip Problem")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                
                NavigationLink(isActive: $showTripProblem) {
                    ProblemReportView(mode: .trip(tripID: arrival.tripID, vehicleID: arrival.vehicleID, stopID: arrival.stopID))
                } label: {
                    EmptyView()
                }
                
                // Vehicle Details Link
                if let vehicleID = arrival.vehicleID {
                    NavigationLink {
                        VehicleSearchView(initialQuery: vehicleID)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "bus")
                                .foregroundColor(.orange)
                            Text("View Vehicle \(vehicleID.components(separatedBy: "_").last ?? vehicleID)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }

                Divider()
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Departure in")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(timeString(for: arrival))
                        .font(.title3)
                        .fontWeight(.semibold)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(arrival.routeShortName ?? "Trip")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func timeString(for arrival: OBAArrival) -> String {
        let minutes = arrival.minutesFromNow
        if minutes <= 0 {
            return "Now"
        } else if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = Double(minutes) / 60.0
            return String(format: "%.1f h", hours)
        }
    }
}

//#Preview {
//    ArrivalDetailView(arrival: OBAArrival(
//        id: "demo",
//        stopID: "1",
//        routeID: "10", tripID: <#OBATripID#>,
//        routeShortName: "10",
//        headsign: "Downtown",
//        minutesFromNow: 5,
//        isPredicted: true
//    ))
//}
