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
    
    init() {
        _viewModel = StateObject(wrappedValue: NearbyStopsViewModel(
            apiClientProvider: { WatchAppState.shared.apiClient },
            locationProvider: { WatchAppState.shared.effectiveLocation }
        ))
    }
    
    var body: some View {
        NearbyStopsContainerView(
            isLoading: viewModel.isLoading,
            errorMessage: viewModel.errorMessage,
            hasStops: !viewModel.stops.isEmpty,
            title: OBALoc("nearby_stops.title", value: "Nearby Stops", comment: "Title for nearby stops screen"),
            refreshAction: { await viewModel.loadNearbyStops() }
        ) {
            NearbyStopsListView(
                stops: viewModel.stops,
                currentLocation: appState.currentLocation,
                mapStyle: appState.mapStyle,
                routeSummaryByStopID: viewModel.routeSummaryByStopID,
                searchText: $searchText
            )
        } emptyState: {
            emptyStateView
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "location.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(OBALoc("nearby_stops.no_stops", value: "No Stops Found", comment: "Empty state title for nearby stops"))
                .font(.headline)
            Text(OBALoc("nearby_stops.no_stops_description", value: "0 stops found near this location", comment: "Empty state description for nearby stops"))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

/// Shared list view for displaying nearby stops with search and filtering
struct NearbyStopsListView: View {
    let stops: [OBAStop]
    let currentLocation: CLLocation?
    let mapStyle: MapStyle
    let routeSummaryByStopID: [String: String]?
    
    @Binding var searchText: String
    
    var body: some View {
        let filtered = stops.filter { stop in
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            if stop.name.localizedCaseInsensitiveContains(query) { return true }
            if let code = stop.code, code.localizedCaseInsensitiveContains(query) { return true }
            return false
        }

        // Show a reasonable number of nearby stops while keeping the
        // list performant on watchOS.
        let limitedStops = Array(filtered.prefix(50))

        let grouped = Dictionary(grouping: limitedStops, by: Self.directionLabel)
        let allKeys = grouped.keys
        let preferredOrder = [
            OBALoc("direction.northbound", value: "Northbound", comment: "Direction: Northbound"),
            OBALoc("direction.southbound", value: "Southbound", comment: "Direction: Southbound"),
            OBALoc("direction.eastbound", value: "Eastbound", comment: "Direction: Eastbound"),
            OBALoc("direction.westbound", value: "Westbound", comment: "Direction: Westbound"),
            OBALoc("common.nearby", value: "Nearby", comment: "Nearby section title")
        ]
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
                    TextField(OBALoc("common.search_nearby_stops", value: "Search nearby stops", comment: "Placeholder text for search field"), text: $searchText)
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
                    currentLocation: currentLocation,
                    mapStyle: mapStyle
                )
                .frame(maxWidth: .infinity)
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            ForEach(sortedKeys, id: \.self) { key in
                let title = key.isEmpty ? OBALoc("common.nearby", value: "Nearby", comment: "Nearby section title") : key
                if let stopsForDirection = grouped[key] {
                    Section(title) {
                        ForEach(stopsForDirection) { stop in
                            NavigationLink {
                                StopArrivalsView(stopID: stop.id, stopName: stop.name)
                            } label: {
                                NearbyStopRow(
                                    stop: stop,
                                    currentLocation: currentLocation,
                                    routesSummary: routeSummaryByStopID?[stop.id]
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

    static func directionLabel(for stop: OBAStop) -> String {
        guard let dir = stop.direction?.lowercased() else { return "" }
        switch dir {
        case "n": return OBALoc("direction.northbound", value: "Northbound", comment: "Direction: Northbound")
        case "s": return OBALoc("direction.southbound", value: "Southbound", comment: "Direction: Southbound")
        case "e": return OBALoc("direction.eastbound", value: "Eastbound", comment: "Direction: Eastbound")
        case "w": return OBALoc("direction.westbound", value: "Westbound", comment: "Direction: Westbound")
        case "ne": return OBALoc("direction.northeast", value: "Northeast", comment: "Direction: Northeast")
        case "nw": return OBALoc("direction.northwest", value: "Northwest", comment: "Direction: Northwest")
        case "se": return OBALoc("direction.southeast", value: "Southeast", comment: "Direction: Southeast")
        case "sw": return OBALoc("direction.southwest", value: "Southwest", comment: "Direction: Southwest")
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
                        Text(String(format: OBALoc("nearby_stops.stop_code_fmt", value: "#%@", comment: "Stop code format"), code))
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
            return String(format: OBALoc("distance.meters_fmt", value: "%.0f m", comment: "Distance in meters"), meters)
        } else {
            return String(format: OBALoc("distance.kilometers_fmt", value: "%.1f km", comment: "Distance in kilometers"), meters / 1000.0)
        }
    }
}

/// Simple map-based view of nearby stops.
struct NearbyMapView: View {
    let stops: [OBAStop]
    let currentLocation: CLLocation?
    let mapStyle: MapStyle

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

/// A shared container view for displaying nearby stops with consistent loading, error, and empty states.
struct NearbyStopsContainerView<Content: View, EmptyView: View>: View {
    let isLoading: Bool
    let errorMessage: String?
    let hasStops: Bool
    let title: String
    let refreshAction: () async -> Void
    @ViewBuilder let content: () -> Content
    @ViewBuilder let emptyState: () -> EmptyView
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ErrorView(message: errorMessage)
            } else if !hasStops {
                emptyState()
            } else {
                content()
            }
        }
        .navigationTitle(title)
        .refreshable {
            await refreshAction()
        }
    }
}
