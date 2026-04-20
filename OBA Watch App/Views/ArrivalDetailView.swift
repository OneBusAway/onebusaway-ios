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
                        Text(OBALoc("arrival_detail.real_time", value: "Real-time", comment: "Real-time arrival status"))
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
                                Text(String(format: OBALoc("common.route_fmt", value: "Route %@", comment: "Route name format"), routeShortName))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text(OBALoc("arrival_detail.view_route_details", value: "View route details", comment: "Action to view route details"))
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
                        Text(OBALoc("arrival_detail.view_trip_schedule", value: "View Trip Schedule", comment: "Action to view trip schedule"))
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
                        Text(OBALoc("arrival_detail.report_trip_problem", value: "Report Trip Problem", comment: "Action to report a trip problem"))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                
                // Vehicle Details Link
                if let vehicleID = arrival.vehicleID {
                    NavigationLink {
                        VehicleSearchView(initialQuery: vehicleID)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "bus")
                                .foregroundColor(.orange)
                            Text(String(format: OBALoc("arrival_detail.view_vehicle_fmt", value: "View Vehicle %@", comment: "Action to view vehicle details"), vehicleID.components(separatedBy: "_").last ?? vehicleID))
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
                    Text(OBALoc("arrival_detail.departure_in", value: "Departure in", comment: "Label for departure time"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(arrival.timeString)
                        .font(.title3)
                        .fontWeight(.semibold)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(arrival.routeShortName ?? OBALoc("common.trip", value: "Trip", comment: "Default title for a trip"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showTripProblem) {
            ProblemReportView(mode: .trip(tripID: arrival.tripID, vehicleID: arrival.vehicleID, stopID: arrival.stopID))
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
