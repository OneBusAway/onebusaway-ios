//
//  SearchResultsSheetView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// `AppSheetRoute.searchResults` — disambiguation for a search that matched several
/// things. Native replacement for `SearchResultsController`, on the stacked layer so
/// the search sheet stays alive beneath with its query intact.
struct SearchResultsSheetView: View {
    let application: Application
    let router: SearchResultRouter

    @StateObject private var viewModel: SearchViewModel
    @EnvironmentObject var coordinator: SheetCoordinator<AppSheetRoute>
    @Environment(\.dismiss) private var dismiss

    init(application: Application, response: SearchResponse, router: SearchResultRouter) {
        self.application = application
        self.router = router
        _viewModel = StateObject(wrappedValue: SearchViewModel(searchResponse: response, application: application))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text(OBALoc(
                    "search_results_controller.title",
                    value: "Search Results",
                    comment: "The title of the Search Results controller."
                )))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(Strings.close) { dismiss() }
                    }
                }
        }
        .searchSheetBackground()
        .onChange(of: viewModel.vehicleSearchResponse) { _, response in
            guard let result = response?.results.first else { return }
            Task { await select(result) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.results.isEmpty {
            EmptyStateView(
                title: OBALoc(
                    "search_results_sheet.empty.title",
                    value: "No results",
                    comment: "Title shown when a disambiguation sheet has no results to show."
                ),
                systemImage: AppSymbol.error
            )
        } else {
            List {
                Section {
                    ForEach(rows) { row in
                        SearchListRowView(row: row)
                    }
                } header: {
                    // "12 results · Route 44" — the count is the enhancement over
                    // `SearchResultsController`, which showed the subtitle alone.
                    Text("\(resultCountText) · \(viewModel.subtitle)")
                        .font(.headline)
                }

                if let error = viewModel.vehicleError {
                    // Inline rather than a modal alert: the sheet is already the
                    // user's context, and a bulletin over it hides what failed.
                    Section {
                        SearchListRowView(row: SearchListRow(
                            kind: .error(error.localizedDescription, systemImage: "exclamationmark.triangle"),
                            title: error.localizedDescription,
                            subtitle: Strings.retry,
                            icon: .system("exclamationmark.triangle"),
                            // `SearchListRowView.errorRow` renders a retry badge and
                            // enables the row only when there's an action, so a
                            // failure the user can re-attempt isn't a dead end.
                            action: viewModel.failedVehicleID.map { vehicleID in
                                { Task { await viewModel.selectVehicle(vehicleID: vehicleID) } }
                            }
                        ))
                    }
                }
            }
            .searchListChrome()
        }
    }

    private var resultCountText: String {
        let format = OBALoc(
            "search_results_sheet.result_count_fmt",
            value: "%d results",
            comment: "Header showing how many results a search matched, e.g. '12 results'. %d is the number of results. Plural forms live in Localizable.stringsdict; the value above is only the not-found fallback."
        )
        return String(format: format, viewModel.results.count)
    }

    private var rows: [SearchListRow] {
        viewModel.results.compactMap { result in
            if let vehicle = result as? AgencyVehicle, let vehicleID = vehicle.vehicleID {
                // Vehicles need a second request before they can be routed, so the
                // row shows progress in place instead of navigating immediately.
                if viewModel.loadingVehicleID == vehicleID {
                    return SearchListRow(kind: .loading, title: vehicleID, icon: .system("bus"))
                }
                return SearchResultRow.row(for: result, application: application) {
                    Task { await viewModel.selectVehicle(vehicleID: vehicleID) }
                }
            }

            return SearchResultRow.row(for: result, application: application) {
                Task { await select(result) }
            }
        }
    }

    /// Unwinds back to home and opens the result — the SwiftUI equivalent of the UIKit
    /// path's `exitSearchMode()`.
    ///
    /// Resolution comes first so this sheet stays up while the request runs: a failure
    /// leaves the user on their results rather than dropping them on home, and the
    /// stacked layer isn't emptied and refilled around a network call.
    ///
    /// `popToRoot()` rather than `dismiss()` + `pop()`: two layers have to come off
    /// (this stacked sheet and the `.search` route beneath it), and `pop()` acts on
    /// whichever layer is topmost *at the moment it runs* — racing the SwiftUI
    /// binding write that `dismiss()` triggers. `popToRoot()` clears both
    /// deterministically in one step.
    private func select(_ result: Any) async {
        guard let resolved = await router.resolve(result: result) else { return }
        coordinator.popToRoot()
        router.present(resolved)
    }
}
