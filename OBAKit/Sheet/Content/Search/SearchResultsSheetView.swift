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
    @StateObject private var selection: SearchResultsSelection
    @EnvironmentObject var coordinator: SheetCoordinator<AppSheetRoute>
    @Environment(\.dismiss) private var dismiss

    init(application: Application, response: SearchResponse, router: SearchResultRouter) {
        self.application = application
        self.router = router
        _viewModel = StateObject(wrappedValue: SearchViewModel(searchResponse: response, application: application))
        _selection = StateObject(wrappedValue: SearchResultsSelection(router: router))
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

                if let errorRow {
                    Section {
                        SearchListRowView(row: errorRow)
                    }
                }
            }
            .searchListChrome()
        }
    }

    private var errorRow: SearchListRow? {
        SearchResultRow.inlineErrorRow(
            vehicleError: viewModel.vehicleError,
            failedVehicleID: viewModel.failedVehicleID,
            selectionError: selection.error,
            failedResult: selection.failedResult,
            onRetryVehicle: { vehicleID in
                Task { await viewModel.selectVehicle(vehicleID: vehicleID) }
            },
            onRetrySelect: { result in
                Task { await select(result) }
            }
        )
    }

    private var resultCountText: String {
        let format = OBALoc(
            "search_results_sheet.result_count_fmt",
            value: "%d results",
            comment: "Header showing how many results a search matched, e.g. '12 results'. %d is the number of results. Plural forms live in Localizable.stringsdict; the value above is only the not-found fallback."
        )
        // `localizedStringWithFormat`, not `String(format:)`: the latter expands
        // `%#@count@` but always resolves it against the root plural rule, so the
        // `few`/`many`/`zero`/`two` forms in the ar, pl, and ru entries could never
        // be selected. Invisible in English; wrong everywhere with more than two.
        return String.localizedStringWithFormat(format, viewModel.results.count)
    }

    private var rows: [SearchListRow] {
        SearchResultRow.rows(
            for: viewModel.results,
            loadingVehicleID: viewModel.loadingVehicleID,
            application: application,
            onSelectVehicle: { vehicleID in
                Task { await viewModel.selectVehicle(vehicleID: vehicleID) }
            },
            onSelect: { result in
                Task { await select(result) }
            }
        )
    }

    private func select(_ result: Any) async {
        await selection.select(result, coordinator: coordinator)
    }
}
