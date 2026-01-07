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
            apiClientProvider: { WatchAppState.shared.apiClient },
            stopID: stopID
        ))
    }
    
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    if let stopName = viewModel.stopName ?? stopName {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stopName)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(2)
                            Text("Stop \(stopID)")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    if let updated = viewModel.lastUpdated {
                        Text("Updated: \(relativeUpdateString(from: updated))")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.1))
            )

            if viewModel.isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
            } else if let error = viewModel.errorMessage {
                Section {
                    ErrorView(message: error)
                }
                .listRowBackground(Color.clear)
            } else if viewModel.upcomingArrivals.isEmpty {
                Section {
                    EmptyArrivalsView()
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(displayedArrivals) { arrival in
                        NavigationLink {
                            ArrivalDetailView(arrival: arrival)
                        } label: {
                            ArrivalRowView(arrival: arrival)
                        }
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.1))
                        )
                    }
                    
                    if viewModel.upcomingArrivals.count > 5 {
                        Button(showAllArrivals ? "Show Fewer" : "Load More") {
                            showAllArrivals.toggle()
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.blue)
                        .listRowBackground(Color.clear)
                    }
                }
            }

            if !viewModel.routes.isEmpty {
                Section("Routes") {
                    ForEach(viewModel.routes) { route in
                        HStack(spacing: 12) {
                            Text(route.shortName ?? "??")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.blue.gradient)
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(route.longName ?? "Unknown Route")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                
                                if let agency = route.agencyName {
                                    Text(agency)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.1))
                        )
                    }
                }
            }
            
            // Hidden navigation links for sheet actions
            Group {
                NavigationLink(isActive: $showNearbyStops) {
                    NearbyStopsView()
                } label: { EmptyView() }
                NavigationLink(isActive: $showStopDetails) {
                    StopDetailView(stopID: stopID)
                } label: { EmptyView() }
                NavigationLink(isActive: $showStopSchedule) {
                    StopScheduleView(stopID: stopID)
                } label: { EmptyView() }
                NavigationLink(isActive: $showStopProblem) {
                    ProblemReportView(mode: .stop(stopID: stopID))
                } label: { EmptyView() }
            }
            .frame(height: 0)
            .opacity(0)
            .listRowBackground(Color.clear)
        }
        .navigationTitle("Arrivals")
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
            Text(arrival.routeShortName ?? "?")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(minWidth: 38)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(routeColor)
                )
            
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
