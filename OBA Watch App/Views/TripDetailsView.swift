//
//  TripDetailsView.swift
//  OBAWatch Watch App
//
//  Created by Prince Yadav on 31/12/25.
//

import SwiftUI
import OBASharedCore
import MapKit

struct TripDetailsView: View {
    @StateObject private var viewModel: TripDetailsViewModel
    @EnvironmentObject var appState: WatchAppState
    
    let tripID: String
    let vehicleID: String?
    let routeShortName: String?
    let headsign: String?
    
    @State private var mapPosition: MapCameraPosition = .automatic
    
    init(tripID: String, vehicleID: String? = nil, routeShortName: String? = nil, headsign: String? = nil) {
        self.tripID = tripID
        self.vehicleID = vehicleID
        self.routeShortName = routeShortName
        self.headsign = headsign
        _viewModel = StateObject(wrappedValue: TripDetailsViewModel(
            apiClient: WatchAppState.shared.apiClient,
            tripID: tripID,
            vehicleID: vehicleID
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
                Section {
                    Map(position: $mapPosition) {
                        if !viewModel.polyline.isEmpty {
                            MapPolyline(coordinates: viewModel.polyline)
                                .stroke(.green, lineWidth: 3)
                        }
                        
                        if let schedule = viewModel.tripDetails?.schedule {
                            ForEach(schedule.stopTimes, id: \.stopId) { stopTime in
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
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                
                if let details = viewModel.tripDetails {
                    // Header
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(routeShortName ?? details.tripId ?? "") - \(headsign ?? details.schedule?.nextTripId ?? "Trip")")
                                .font(.system(size: 16, weight: .bold))
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
                                    Text("Scheduled")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.1))
                    )
                    
                    // Vehicle Status
                    if let status = details.status {
                        Section("Vehicle Status") {
                            if let lastUpdate = status.lastUpdateTime {
                                 LabeledContent {
                                     Text(relativeTime(for: lastUpdate))
                                         .font(.system(size: 14))
                                         .foregroundColor(.white)
                                 } label: {
                                     Text("Last Update")
                                         .font(.system(size: 14))
                                         .foregroundColor(.secondary)
                                 }
                            }
                            
                            if let deviation = status.scheduleDeviation {
                                 LabeledContent {
                                     Text(deviationString(seconds: deviation))
                                         .font(.system(size: 14))
                                         .foregroundColor(.white)
                                 } label: {
                                     Text("Status")
                                         .font(.system(size: 14))
                                         .foregroundColor(.secondary)
                                 }
                            }
                        }
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.1))
                        )
                    }
                    
                    // Stops
                    if let schedule = details.schedule {
                        Section("Stops") {
                            ForEach(Array(schedule.stopTimes.enumerated()), id: \.element.stopId) { index, stopTime in
                                StopRow(
                                    stopTime: stopTime,
                                    isFirst: index == 0,
                                    isLast: index == schedule.stopTimes.count - 1,
                                    serviceDate: details.serviceDate
                                )
                                .listRowBackground(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.white.opacity(0.1))
                                )
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(routeShortName ?? "Trip Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadDetails()
        }
    }
    
    private func relativeTime(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func deviationString(seconds: Int) -> String {
        let minutes = abs(seconds) / 60
        if seconds == 0 { return "On time" }
        let label = seconds > 0 ? "late" : "early"
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
                     let name = stopTime.stopHeadsign
                     let displayName = (name != nil && !name!.isEmpty) ? name! : "Stop \(stopTime.stopId?.components(separatedBy: "_").last ?? "Unknown")"
                     
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
                         Text("ID: \(stopId.components(separatedBy: "_").last ?? stopId)")
                             .font(.system(size: 11))
                             .foregroundColor(.secondary)
                     }
                     
                     if let distance = stopTime.distanceAlongTrip, distance > 0 {
                         Spacer()
                         Text(String(format: "%.1f mi", distance / 1609.34))
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
