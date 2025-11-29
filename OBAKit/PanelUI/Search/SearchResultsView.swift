//
//  SearchResultsView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import MapKit
import OBAKitCore

/// Shows search results based on search type
struct SearchResultsView: View {
    @ObservedObject var viewModel: SearchViewModel
    let application: Application
    let brandColor: Color
    let onRouteSelected: (Route) -> Void
    let onStopSelected: (Stop) -> Void
    let onMapItemSelected: (MKMapItem) -> Void
    let onVehicleSelected: (AgencyVehicle) -> Void

    private var sectionHeader: String {
        switch viewModel.searchState {
        case .results(let type):
            switch type {
            case .route: return OBALoc("search_results.routes_header", value: "Routes", comment: "Header for route search results")
            case .stopNumber: return OBALoc("search_results.stops_header", value: "Stops", comment: "Header for stop search results")
            case .address: return OBALoc("search_results.places_header", value: "Places", comment: "Header for place/address search results")
            case .vehicleID: return OBALoc("search_results.vehicles_header", value: "Vehicles", comment: "Header for vehicle search results")
            }
        default:
            return ""
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            switch viewModel.searchState {
            case .idle:
                EmptyView()

            case .searching:
                loadingView

            case .results(let type):
                resultsContent(for: type)

            case .error(let message):
                errorView(message: message)
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Searching...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Results Content

    @ViewBuilder
    private func resultsContent(for type: SearchType) -> some View {
        if viewModel.hasResults {
            VStack(spacing: 0) {
                // Section header with count
                HStack {
                    Text(sectionHeader)
                        .font(.headline)
                    Spacer()
                    Text("\(viewModel.resultsCount)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                // Results list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        switch type {
                        case .route:
                            ForEach(viewModel.routeResults) { route in
                                RouteRowView(route: route, brandColor: brandColor) {
                                    onRouteSelected(route)
                                }
                                Divider().padding(.leading, 56)
                            }
                        case .stopNumber:
                            ForEach(viewModel.stopResults) { stop in
                                StopRowView(stop: stop) {
                                    onStopSelected(stop)
                                }
                                Divider().padding(.leading, 56)
                            }
                        case .address:
                            ForEach(viewModel.mapItemResults, id: \.self) { mapItem in
                                MapItemRowView(
                                    mapItem: mapItem,
                                    currentLocation: application.locationService.currentLocation,
                                    distanceFormatter: application.formatters.distanceFormatter,
                                    brandColor: brandColor
                                ) {
                                    onMapItemSelected(mapItem)
                                }
                                Divider().padding(.leading, 56)
                            }
                        case .vehicleID:
                            ForEach(viewModel.vehicleResults, id: \.vehicleID) { vehicle in
                                VehicleRowView(vehicle: vehicle, brandColor: brandColor) {
                                    onVehicleSelected(vehicle)
                                }
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                }
            }
        } else {
            emptyResultsView
        }
    }

    // MARK: - Empty Results View

    private var emptyResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(OBALoc("search_results.no_results", value: "No Results Found", comment: "Title shown when search returns no results"))
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(OBALoc("search_results.try_different_query", value: "Try a different search term", comment: "Suggestion when search returns no results"))
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Search Error")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 16)
    }
}

// MARK: - Route Row View

/// A row displaying a single route with colored badge and name
struct RouteRowView: View {
    let route: Route
    let brandColor: Color
    let onTap: () -> Void

    private var routeColor: Color {
        if let color = route.color {
            return Color(color)
        }
        return brandColor
    }

    private var routeTextColor: Color {
        if let color = route.textColor {
            return Color(color)
        }
        return .white
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Route badge
                Text(route.shortName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(routeTextColor)
                    .frame(minWidth: 32, minHeight: 32)
                    .padding(.horizontal, 4)
                    .background(routeColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                // Route name and agency
                VStack(alignment: .leading, spacing: 2) {
                    if let longName = route.longName {
                        Text(longName)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    if let agency = route.agency {
                        Text(agency.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Vehicle Row View

/// A row displaying a vehicle search result
struct VehicleRowView: View {
    let vehicle: AgencyVehicle
    let brandColor: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Bus icon badge
                Image(systemName: "bus")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(brandColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                // Vehicle ID and agency
                VStack(alignment: .leading, spacing: 2) {
                    Text(vehicle.vehicleID ?? "Unknown Vehicle")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(vehicle.agencyName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
