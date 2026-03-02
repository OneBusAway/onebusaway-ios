//
//  TripDetailsView.swift
//  OBAWatch Watch App
//
//  Created by Prince Yadav on 31/12/25.
//

import SwiftUI
import OBAKitCore
import MapKit

struct TripDetailsView: View {
    @StateObject private var viewModel: TripDetailsViewModel
    @EnvironmentObject var appState: WatchAppState
    
    let tripID: String
    let vehicleID: String?
    let routeShortName: String?
    let headsign: String?
    let initialTrip: OBATripForLocation?
    
    @State private var mapPosition: MapCameraPosition = .automatic
    
    init(tripID: String, vehicleID: String? = nil, routeShortName: String? = nil, headsign: String? = nil, initialTrip: OBATripForLocation? = nil) {
        self.tripID = tripID
        self.vehicleID = vehicleID
        self.routeShortName = routeShortName
        self.headsign = headsign
        self.initialTrip = initialTrip
        _viewModel = StateObject(wrappedValue: TripDetailsViewModel(
            apiClient: WatchAppState.shared.apiClient,
            tripID: tripID,
            vehicleID: vehicleID,
            initialTrip: initialTrip
        ))
    }
    
    var body: some View {
        List {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
            } else {
                mapSection
                
                if let details = viewModel.tripDetails {
                    headerSection(details)
                    vehicleStatusSection(details)
                    stopsSection(details)
                }
            }
        }
        .navigationTitle(routeShortName ?? OBALoc("trip_details.title", value: "Trip Details", comment: "Trip details title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadDetails()
        }
    }

    private var mapSection: some View {
        Section {
            Map(position: $mapPosition) {
                if !viewModel.polyline.isEmpty {
                    MapPolyline(coordinates: viewModel.polyline)
                        .stroke(.green, lineWidth: 3)
                }
                
                if let schedule = viewModel.tripDetails?.schedule {
                    ForEach(Array(schedule.stopTimes.enumerated()), id: \.offset) { _, stopTime in
                        if let lat = stopTime.latitude, let lon = stopTime.longitude {
                            Annotation("", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                                ZStack {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 20, height: 20)
                                        .shadow(radius: 2)
                                    
                                    Image(systemName: "bus.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                    }
                }
            }
            .mapStyle(appState.mapStyle)
            .id("standard")
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    private func headerSection(_ details: OBATripExtendedDetails) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                let tripFallback = OBALoc("trip_details.trip_fallback", value: "Trip", comment: "Trip fallback")
                Text("\(routeShortName ?? details.tripId ?? "") - \(headsign ?? details.schedule?.nextTripId ?? tripFallback)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                if let serviceDate = details.serviceDate {
                    HStack(spacing: 4) {
                        Text(serviceDate, style: .time)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("•")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text(OBALoc("status.scheduled", value: "Scheduled", comment: "Scheduled status"))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .listRowBackground(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.12))
        )
    }

    @ViewBuilder
    private func vehicleStatusSection(_ details: OBATripExtendedDetails) -> some View {
        if let status = details.status {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "bus.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                        
                        Text(status.vehicleID != nil ? String(format: OBALoc("trip_details.vehicle_fmt", value: "Vehicle %@", comment: "Vehicle format"), status.vehicleID!) : OBALoc("trip_details.vehicle_status", value: "Vehicle Status", comment: "Vehicle status title"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    HStack(spacing: 4) {
                        if let deviation = status.scheduleDeviation {
                            Text(deviationString(seconds: deviation))
                                .font(.system(size: 12))
                                .foregroundColor(deviationColor(seconds: deviation))
                        } else if status.predicted == true || status.lastUpdateTime != nil {
                            Text(OBALoc("status.on_time", value: "On time", comment: "On time status"))
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                        } else {
                            Text(OBALoc("status.scheduled", value: "Scheduled", comment: "Scheduled status"))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        
                        if (status.scheduleDeviation != nil || status.predicted != nil || status.lastUpdateTime != nil) && status.lastUpdateTime != nil {
                            Text("•")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        
                        if let lastUpdate = status.lastUpdateTime {
                            Text(relativeTime(for: lastUpdate))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.12))
            )
        }
    }

    private func deviationColor(seconds: Int) -> Color {
        if seconds <= 0 { return .green }
        if seconds < 300 { return .yellow }
        return .red
    }

    @ViewBuilder
    private func stopsSection(_ details: OBATripExtendedDetails) -> some View {
        if let schedule = details.schedule {
            Section(OBALoc("trip_details.section.stops", value: "Stops", comment: "Stops section header")) {
                ForEach(Array(schedule.stopTimes.enumerated()), id: \.offset) { index, stopTime in
                    StopRow(
                        stopTime: stopTime,
                        isFirst: index == 0,
                        isLast: index == schedule.stopTimes.count - 1,
                        serviceDate: details.serviceDate
                    )
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.12))
                    )
                }
            }
        }
    }
    
    private func relativeTime(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func deviationString(seconds: Int) -> String {
        let minutes = abs(seconds) / 60
        if seconds == 0 { return OBALoc("status.on_time", value: "On time", comment: "On time status") }
        let label = seconds > 0 ? OBALoc("status.late", value: "late", comment: "Late status") : OBALoc("status.early", value: "early", comment: "Early status")
        return "\(minutes)m \(label)"
    }
    
    private func formatTime(seconds: Int, serviceDate: Date?) -> String {
        let date = (serviceDate ?? Date()).addingTimeInterval(TimeInterval(seconds))
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct StopRow: View {
    let stopTime: OBATripExtendedDetails.StopTime
    let isFirst: Bool
    let isLast: Bool
    let serviceDate: Date?
    
    var body: some View {
        HStack(spacing: 12) {
            // Timeline indicator
            VStack(spacing: 0) {
                if !isFirst {
                    Rectangle()
                        .fill(Color.green.opacity(0.5))
                        .frame(width: 2, height: 12)
                } else {
                    Color.clear.frame(width: 2, height: 12)
                }
                
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 12, height: 12)
                    Circle()
                        .strokeBorder(Color.green, lineWidth: 2)
                        .frame(width: 12, height: 12)
                }
                
                if !isLast {
                    Rectangle()
                        .fill(Color.green.opacity(0.5))
                        .frame(width: 2)
                } else {
                    Color.clear.frame(width: 2)
                }
            }
            .frame(width: 12)
            
            // Content Card
             VStack(alignment: .leading, spacing: 2) {
                 HStack(alignment: .top) {
                     let displayName: String = {
                         if let name = stopTime.stopHeadsign, !name.isEmpty {
                             return name
                         }
                         return "Stop \(stopTime.stopId?.components(separatedBy: "_").last ?? "Unknown")"
                     }()
                     
                     Text(displayName)
                         .font(.system(size: 15, weight: .semibold))
                         .foregroundColor(.white)
                         .lineLimit(2)
                         .fixedSize(horizontal: false, vertical: true)
                     
                     Spacer()
                     
                     if let arrival = stopTime.arrivalTime {
                         Text(formatTime(seconds: arrival, serviceDate: serviceDate))
                             .font(.system(size: 13, weight: .bold))
                             .foregroundColor(.green)
                     }
                 }
                 
                 HStack {
                     if let stopId = stopTime.stopId {
                         Text(String(format: OBALoc("trip_details.stop_id_format", value: "ID: %@", comment: "Stop ID format"), stopId.components(separatedBy: "_").last ?? stopId))
                             .font(.system(size: 11))
                             .foregroundColor(.secondary)
                     }
                     
                     if let distance = stopTime.distanceAlongTrip, distance > 0 {
                         Spacer()
                         Text(String(format: OBALoc("trip_details.distance_format", value: "%.1f mi", comment: "Distance format"), distance / 1609.34))
                             .font(.system(size: 11))
                             .foregroundColor(.secondary)
                     }
                 }
             }
             .padding(.vertical, 8)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
    }
    
    private func formatTime(seconds: Int, serviceDate: Date?) -> String {
        let date = (serviceDate ?? Date()).addingTimeInterval(TimeInterval(seconds))
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
