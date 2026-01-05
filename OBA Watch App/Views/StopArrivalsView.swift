//
//  StopArrivalsView.swift
//  OBAWatch Watch App
//
//  Created by Prince Yadav on 31/12/25.
//

import SwiftUI
import OBASharedCore
import WatchKit

struct StopArrivalsView: View {
    let stopID: OBAStopID
    let stopName: String?
    
    @StateObject private var viewModel: StopArrivalsViewModel
    @State private var showActions: Bool = false
    @State private var showNearbyStops: Bool = false
    @State private var infoMessage: String?
    @State private var showAllArrivals: Bool = false
    @State private var showStopDetails: Bool = false
    @State private var showStopSchedule: Bool = false
    @State private var showStopProblem: Bool = false
    
    init(stopID: OBAStopID, stopName: String? = nil) {
        self.stopID = stopID
        self.stopName = stopName
        _viewModel = StateObject(wrappedValue: StopArrivalsViewModel(
            apiClient: WatchAppState.shared.apiClient,
            stopID: stopID
        ))
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let stopName = stopName {
                    StopHeaderView(title: stopName, subtitle: "Stop \(stopID)")
                }

                if let updated = viewModel.lastUpdated {
                    Text("Updated: \(relativeUpdateString(from: updated))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // Data provided by date range (matching iOS app)
                if !viewModel.upcomingArrivals.isEmpty {
                    let minutesBefore = 5
                    let minutesAfter = 125
                    let dataDateRangeBeforeTime = Date().addingTimeInterval(Double(minutesBefore) * -60.0)
                    let dataDateRangeAfterTime = Date().addingTimeInterval(Double(minutesAfter) * 60.0)
                    let dataDateRangeText = DateFormatterHelper.formattedDateRange(from: dataDateRangeBeforeTime, to: dataDateRangeAfterTime)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Data provided by")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(dataDateRangeText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }

                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if let error = viewModel.errorMessage {
                    ErrorView(message: error)
                } else if viewModel.upcomingArrivals.isEmpty {
                    EmptyArrivalsView()
                } else {
                    ArrivalsListView(
                        arrivals: Array(displayedArrivals.prefix(20))
                    )
                    if viewModel.upcomingArrivals.count > 5 {
                        Button(showAllArrivals ? "Show Fewer" : "Load More") {
                            showAllArrivals.toggle()
                        }
                        .font(.caption)
                        .padding(.top, 4)
                    }
                }

                if !viewModel.routes.isEmpty {
                    Section(header: Text("Routes").font(.headline)) {
                        RoutesListView(routes: viewModel.routes)
                    }
                }

                NavigationLink(isActive: $showNearbyStops) {
                    NearbyStopsView()
                } label: {
                    EmptyView()
                }
                NavigationLink(isActive: $showStopDetails) {
                    StopDetailView(stopID: stopID)
                } label: {
                    EmptyView()
                }
                NavigationLink(isActive: $showStopSchedule) {
                    StopScheduleView(stopID: stopID)
                } label: {
                    EmptyView()
                }
                NavigationLink(isActive: $showStopProblem) {
                    ProblemReportView(mode: .stop(stopID: stopID))
                } label: {
                    EmptyView()
                }
            }
            .padding()
        }
        .navigationTitle(stopName ?? "Stop")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadArrivals()
        }
        .refreshable {
            await viewModel.loadArrivals()
            WKInterfaceDevice.current().play(.success)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showActions = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showActions) {
            List {
                Section {
                    Button("Add Bookmark") {
                        infoMessage = "Use the iPhone app to add bookmarks for this stop."
                        showActions = false
                    }
                    NavigationLink {
                        ServiceAlertsView()
                    } label: {
                        Text("Service Alerts")
                    }
                    Button("Stop Details") {
                        showStopDetails = true
                        showActions = false
                    }
                    Button("Schedules") {
                        showStopSchedule = true
                        showActions = false
                    }
                    Button("Nearby Stops") {
                        showNearbyStops = true
                        showActions = false
                    }
                    Button("Report a Problem") {
                        showStopProblem = true
                        showActions = false
                    }
                    Button("Open on iPhone") {
                        DeepLinkSyncManager.shared.openStopOnPhone(stopID: stopID)
                        showActions = false
                    }
                }

                Section {
                    Button("Close", role: .cancel) {
                        showActions = false
                    }
                }
            }
        }
        .alert("Info", isPresented: Binding(
            get: { infoMessage != nil },
            set: { newValue in
                if !newValue { infoMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(infoMessage ?? "")
        }
    }

    private var displayedArrivals: [OBAArrival] {
        if showAllArrivals {
            return viewModel.upcomingArrivals
        } else {
            return Array(viewModel.upcomingArrivals.prefix(5))
        }
    }

    private func relativeUpdateString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 30 {
            return "Just now"
        } else if interval < 60 {
            return "Less than a minute ago"
        } else {
            let minutes = Int(interval / 60)
            if minutes == 1 {
                return "1 minute ago"
            } else {
                return "\(minutes) minutes ago"
            }
        }
    }
}

struct RoutesListView: View {
    let routes: [OBARoute]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(routes) { route in
                HStack {
                    Text(route.shortName ?? "Unknown")
                        .font(.headline)
                    Spacer()
                    Text(route.longName ?? "")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct StopHeaderView: View {
    let title: String
    let subtitle: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .lineLimit(2)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ArrivalsListView: View {
    let arrivals: [OBAArrival]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(arrivals.prefix(5))) { arrival in
                NavigationLink {
                    ArrivalDetailView(arrival: arrival)
                } label: {
                    ArrivalRowView(arrival: arrival)
                }
            }
        }
    }
}

struct ArrivalRowView: View {
    let arrival: OBAArrival
    
    var body: some View {
        HStack(spacing: 8) {
            // Route badge
            VStack {
                Text(arrival.routeShortName ?? "?")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(minWidth: 40)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(routeColor)
                    .cornerRadius(6)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(arrival.headsign ?? "Unknown")
                    .font(.subheadline)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    if arrival.isPredicted {
                        Image(systemName: "location.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.green)
                    }
                    Text(timeString(for: arrival))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let statusLabel = arrival.scheduleStatusLabel {
                        Text(statusLabel)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private var routeColor: Color {
        // Use a consistent color based on route ID
        let hash = abs(arrival.routeID.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.7, brightness: 0.8)
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

struct EmptyArrivalsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.badge.xmark")
                .font(.system(size: 30))
                .foregroundColor(.secondary)
            Text("No Upcoming Arrivals")
                .font(.headline)
            Text("Check back later")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

struct ErrorView: View {
    let message: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundColor(.orange)
            Text("Error")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

#Preview {
    NavigationStack {
        StopArrivalsView(stopID: "1_12345", stopName: "Preview Stop")
    }
}
