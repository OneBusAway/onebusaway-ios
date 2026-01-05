//
//  TripDetailsView.swift
//  OBAWatch Watch App
//
//  Created by Prince Yadav on 31/12/25.
//

import SwiftUI
import OBASharedCore

struct TripDetailsView: View {
    @StateObject private var viewModel: TripDetailsViewModel
    @EnvironmentObject var appState: WatchAppState
    
    let tripID: String
    let vehicleID: String?
    let routeShortName: String?
    let headsign: String?
    
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
            } else if let details = viewModel.tripDetails {
                
                // Header
                Section {
                    VStack(alignment: .leading) {
                        Text(routeShortName ?? details.tripId ?? "")
                            .font(.title3)
                            .bold()
                        if let headsign = headsign ?? details.schedule?.nextTripId { // fallback to next trip ID as a proxy for destination if needed, or just empty
                             Text(headsign)
                                .font(.headline)
                        }
                    }
                }
                
                // Vehicle Status
                if let status = details.status {
                    Section("Vehicle Status") {
                        if let lastUpdate = status.lastUpdateTime {
                             LabeledContent("Last Update", value: relativeTime(for: lastUpdate))
                        }
                        
                        if let occupancy = status.scheduleDeviation {
                             // Using schedule deviation as a proxy for "status" (Early/Late)
                             LabeledContent("Status", value: deviationString(seconds: occupancy))
                        }
                    }
                }
                
                // Stops
                if let schedule = details.schedule {
                    Section("Stops") {
                        ForEach(schedule.stopTimes, id: \.stopId) { stopTime in
                            VStack(alignment: .leading) {
                                Text(stopTime.stopHeadsign ?? "Stop")
                                    .font(.headline)
                                HStack {
                                    if let arrival = stopTime.arrivalTime {
                                        Text(formatTime(seconds: arrival, serviceDate: details.serviceDate))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Trip Details")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ServiceAlertsView()
                } label: {
                    Image(systemName: "exclamationmark.triangle")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    DeepLinkSyncManager.shared.openTripOnPhone(tripID: tripID)
                } label: {
                    Image(systemName: "iphone")
                }
            }
        }
        .task {
            await viewModel.loadDetails()
        }
    }
    
    func formatTime(seconds: Int, serviceDate: Date?) -> String {
        guard let serviceDate = serviceDate else { return "" }
        let date = serviceDate.addingTimeInterval(TimeInterval(seconds))
        // Adjust for server time offset? 
        // serviceDate is usually midnight in the agency's timezone.
        // The seconds are seconds from that midnight.
        // So the resulting date is the absolute time of arrival.
        // We should display this in the user's local time (or agency time).
        // For simplicity, let's use the standard formatter which uses local time.
        
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    func relativeTime(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    func deviationString(seconds: Int) -> String {
        if seconds > 0 {
            return "\(seconds / 60) min late"
        } else if seconds < 0 {
            return "\(abs(seconds) / 60) min early"
        } else {
            return "On time"
        }
    }
}
