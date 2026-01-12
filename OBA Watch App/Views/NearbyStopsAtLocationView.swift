import SwiftUI
import CoreLocation
import MapKit
import OBAKitCore

/// Shows nearby stops for a fixed coordinate selected from address search,
/// mirroring the iOS "Nearby Stops" sheet but in a simplified watch layout.
struct NearbyStopsAtLocationView: View {
    let title: String
    let coordinate: CLLocationCoordinate2D

    @StateObject private var viewModel: NearbyStopsViewModel
    @State private var searchText: String = ""

    init(title: String, coordinate: CLLocationCoordinate2D) {
        self.title = title
        self.coordinate = coordinate
        _viewModel = StateObject(wrappedValue: NearbyStopsViewModel(
            apiClientProvider: { WatchAppState.shared.apiClient },
            locationProvider: {
                CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            }
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
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        DeepLinkSyncManager.shared.planTripOnPhone(
                            originLat: coordinate.latitude,
                            originLon: coordinate.longitude,
                            destLat: nil,
                            destLon: nil
                        )
                    } label: {
                        Image(systemName: "figure.walk")
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
            Text(viewModel.locationStatus)
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

        let limitedStops = Array(filtered.prefix(20))
        let grouped = Dictionary(grouping: limitedStops, by: directionLabel)
        let sortedKeys = grouped.keys.sorted()

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
                    currentLocation: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                    mapStyle: mapStyle
                )
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
                                    currentLocation: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                                    routesSummary: nil
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

    private var mapStyle: MapStyle {
        if UserDefaults.standard.bool(forKey: "watch_map_style_standard") {
            return .standard
        } else {
            return .imagery
        }
    }
}
