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
                .navigationTitle(Text(Strings.routePickerTitle))
                .navigationBarTitleDisplayMode(.inline)
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text(Strings.routePickerSearchPlaceholder)
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
            startLoad()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    /// Kicks off a fresh `loadRoutes()` unless one is already in flight. Re-entrant
    /// safe: SwiftUI can re-attach on scenePhase changes, and the retry button
    /// funnels through the same entry point.
    private func startLoad() {
        guard loadTask == nil else { return }
        loadTask = Task { [viewModel] in
            await viewModel.loadRoutes()
        }
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.didFinishLoading {
            EmptyStateView(title: Strings.routePickerLoading, systemImage: AppSymbol.loading)
        } else if let error = viewModel.loadError {
            EmptyStateView(title: error.localizedDescription, systemImage: AppSymbol.error) { retryButton }
        } else if viewModel.allRoutes.isEmpty {
            EmptyStateView(title: Strings.routePickerNoRoutes, systemImage: AppSymbol.search)
        } else {
            routesList
        }
    }

    private var retryButton: some View {
        Button {
            // A completed load leaves `loadTask` non-nil; drop it first so
            // `startLoad()` doesn't guard-return.
            loadTask?.cancel()
            loadTask = nil
            startLoad()
        } label: {
            Label(Strings.currentTripTryAgain, systemImage: AppSymbol.retry)
        }
        .padding(.top, 8)
    }

    private var routesList: some View {
        List(viewModel.filteredRoutes, id: \.id) { route in
            routeRow(route)
        }
        .listStyle(.insetGrouped)
    }

    private func routeRow(_ route: Route) -> some View {
        Button {
            coordinator.push(.currentTrip(route: route))
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(route.shortName)
                    .font(.body)
                    .foregroundStyle(Color(ThemeColors.shared.label))
                Text(route.longName ?? route.agency.name)
                    .font(.subheadline)
                    .foregroundStyle(Color(ThemeColors.shared.secondaryLabel))
            }
        }
        .accessibilityElement(children: .combine)
    }
}
