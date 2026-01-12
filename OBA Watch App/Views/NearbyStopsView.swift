//
//  NearbyStopsView.swift
//  OBAWatch Watch App
//
//  Created by Prince Yadav on 31/12/25.
//

import SwiftUI
import CoreLocation
import MapKit
import OBAKitCore

struct NearbyStopsView: View {
    @EnvironmentObject private var appState: WatchAppState
    @StateObject private var viewModel: NearbyStopsViewModel
    @State private var searchText: String = ""
    
    @AppStorage("watch_map_style_standard") private var useStandardMapStyle: Bool = true
    
    init() {
        _viewModel = StateObject(wrappedValue: NearbyStopsViewModel(
            apiClientProvider: { WatchAppState.shared.apiClient },
            locationProvider: { WatchAppState.shared.effectiveLocation }
        ))
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage {
                    ErrorView(message: error)
                } else if viewModel.stops.isEmpty {
                    emptyStateView
                } else {
                    stopsList
                }
            }
            .navigationTitle("Nearby Stops")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        useStandardMapStyle.toggle()
                    } label: {
                        Image(systemName: useStandardMapStyle ? "map" : "globe")
                    }
                }
            }
            .refreshable {
                await viewModel.loadNearbyStops()
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "location.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No Stops Found")
                .font(.headline)
            Text("0 stops found near this location")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private var stopsList: some View {
        let filtered = viewModel.stops.filter { stop in
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            if stop.name.localizedCaseInsensitiveContains(query) { return true }
            if let code = stop.code, code.localizedCaseInsensitiveContains(query) { return true }
            return false
        }

        // Show a reasonable number of nearby stops while keeping the
        // list performant on watchOS.
        let limitedStops = Array(filtered.prefix(50))

        let grouped = Dictionary(grouping: limitedStops, by: directionLabel)
        let allKeys = grouped.keys
        let preferredOrder = ["Northbound", "Southbound", "Eastbound", "Westbound", "Nearby"]
        let sortedKeys = allKeys.sorted { lhs, rhs in
            let lhsIndex = preferredOrder.firstIndex(of: lhs) ?? preferredOrder.count
            let rhsIndex = preferredOrder.firstIndex(of: rhs) ?? preferredOrder.count
            if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
            return lhs < rhs
        }

        return List {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                    TextField("Search nearby stops", text: $searchText)
                        .font(.system(size: 16))
                        .padding(.vertical, 8)
                }
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.15))
            )

            if !limitedStops.isEmpty {
                NearbyMapView(
                    stops: limitedStops,
                    currentLocation: appState.currentLocation,
                    mapStyle: useStandardMapStyle ? .standard : .imagery
                )
                .frame(maxWidth: .infinity)
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            ForEach(sortedKeys, id: \.self) { key in
                let title = key.isEmpty ? "Nearby" : key
                if let stopsForDirection = grouped[key] {
                    Section(title) {
                        ForEach(stopsForDirection) { stop in
                            NavigationLink {
                                StopArrivalsView(stopID: stop.id, stopName: stop.name)
                            } label: {
                                NearbyStopRow(
                                    stop: stop,
                                    currentLocation: appState.currentLocation,
                                    routesSummary: viewModel.routeSummaryByStopID[stop.id]
                                )
                            }
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

    private func directionLabel(for stop: OBAStop) -> String {
        guard let dir = stop.direction?.lowercased() else { return "" }
        switch dir {
        case "n": return "Northbound"
        case "s": return "Southbound"
        case "e": return "Eastbound"
        case "w": return "Westbound"
        case "ne": return "Northeast"
        case "nw": return "Northwest"
        case "se": return "Southeast"
        case "sw": return "Southwest"
        default: return ""
        }
    }
}

struct NearbyStopRow: View {
    let stop: OBAStop
    let currentLocation: CLLocation?
    let routesSummary: String?
    
    var body: some View {
        HStack(spacing: 12) {
            let icon = stop.locationType == 1 ? "train.side.front.car" : "signpost.right.fill"
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(Color.green.gradient)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(stop.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    if let code = stop.code {
                        Text("#\(code)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    if let location = currentLocation {
                        let stopLocation = CLLocation(latitude: stop.latitude, longitude: stop.longitude)
                        let distance = stopLocation.distance(from: location)
                        
                        Text(formatDistance(distance))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                if let routesSummary {
                    Text(routesSummary)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return String(format: "%.0f m", meters)
        } else {
            return String(format: "%.1f km", meters / 1000.0)
        }
    }
}

/// Simple map-based view of nearby stops.
struct NearbyMapView: View {
    let stops: [OBAStop]
    let currentLocation: CLLocation?
    var mapStyle: MapStyle = .standard

    var body: some View {
        Map {
            UserAnnotation()
            
            ForEach(stops.prefix(20)) { stop in
                let icon = stop.locationType == 1 ? "train.side.front.car" : "bus"
                Marker(stop.name, systemImage: icon, coordinate: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude))
                    .tint(.green)
            }
        }
        .mapStyle(mapStyle)
    }
}

#Preview {
    NearbyStopsView()
}
