//
//  RoutePickerView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// SwiftUI route picker surfaced by `AppSheetRoute.routePicker`. Drives the
/// already-merged `RoutePickerViewModel`; on selection, pushes
/// `.currentTrip(route:)` onto the sheet stack.
struct RoutePickerView: View {
    @StateObject private var viewModel: RoutePickerViewModel
    @EnvironmentObject var coordinator: SheetCoordinator<AppSheetRoute>

    @State private var searchText: String = ""
    @State private var loadTask: Task<Void, Never>?

    init(viewModel: @autoclosure @escaping () -> RoutePickerViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text(OBALoc(
                    "route_picker.title",
                    value: "Select Your Route",
                    comment: "Title for the route picker screen where the user selects their transit route."
                )))
                .navigationBarTitleDisplayMode(.inline)
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text(OBALoc(
                        "route_picker.search_placeholder",
                        value: "Search routes…",
                        comment: "Placeholder text in the route search field."
                    ))
                )
                .onChange(of: searchText) { _, newValue in
                    viewModel.updateSearch(newValue)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(Strings.close) { coordinator.pop() }
                    }
                }
        }
        .onAppear {
            // Re-entrant guard: SwiftUI re-attaches on scenePhase changes; only
            // kick a load if no Task is already in flight.
            guard loadTask == nil else { return }
            loadTask = Task { [viewModel] in
                await viewModel.loadRoutes()
            }
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.didFinishLoading {
            ContentUnavailableView(
                OBALoc("route_picker.loading", value: "Loading routes…", comment: "Loading message while fetching nearby routes."),
                systemImage: "arrow.clockwise"
            )
        } else if let error = viewModel.loadError {
            ContentUnavailableView(
                error.localizedDescription,
                systemImage: "exclamationmark.triangle"
            )
        } else if viewModel.allRoutes.isEmpty {
            ContentUnavailableView(
                OBALoc("route_picker.no_routes", value: "No routes found nearby.", comment: "Message when no routes are found near the user's location."),
                systemImage: "magnifyingglass"
            )
        } else {
            List(viewModel.filteredRoutes, id: \.id) { route in
                Button {
                    coordinator.push(.currentTrip(route: route))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(route.shortName)
                            .font(.body)
                            .foregroundStyle(.primary)
                        Text(route.longName ?? route.agency.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .listStyle(.plain)
        }
    }
}
