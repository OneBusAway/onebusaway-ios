//
//  SearchSheetView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// `AppSheetRoute.search` — search in the same base sheet as home, with a Close
/// button back to the home sections.
struct SearchSheetView: View {
    @StateObject private var viewModel: SearchSheetViewModel
    @FocusState private var isFieldFocused: Bool

    let placeholder: String

    init(viewModel: @autoclosure @escaping () -> SearchSheetViewModel, placeholder: String) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.placeholder = placeholder
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            statusBanner
            SearchListView(searchInteractor: viewModel.searchInteractor)
        }
        .onAppear {
            viewModel.reportSearchOpened()
            isFieldFocused = true
        }
        .alert(
            Strings.clearRecentSearchesConfirmation,
            isPresented: $viewModel.isConfirmingClearRecents
        ) {
            Button(Strings.cancel, role: .cancel) { }
            Button(Strings.delete, role: .destructive) {
                viewModel.confirmClearRecentSearches()
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(placeholder, text: Binding(
                    get: { viewModel.query },
                    set: { viewModel.updateQuery($0) }
                ))
                .focused($isFieldFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                // Matches UIKit, where the search bar's search button is unhandled:
                // Return just dismisses the keyboard; the quick-search rows are the
                // way to run a search.
                .onSubmit { isFieldFocused = false }

                if !viewModel.query.isEmpty {
                    Button {
                        viewModel.updateQuery("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(OBALoc(
                        "search_sheet.clear_query",
                        value: "Clear",
                        comment: "Accessibility label for the button that clears the search query."
                    ))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background { Capsule().fill(Color(.tertiarySystemFill)) }

            Button(Strings.close) {
                isFieldFocused = false
                viewModel.close()
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
    }

    @ViewBuilder
    private var statusBanner: some View {
        if viewModel.isSearching {
            ProgressView()
                .padding(.top, 12)
        } else if let errorMessage = viewModel.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
        } else if viewModel.showsNoResults {
            Label(
                OBALoc(
                    "map_controller.no_search_results_found",
                    value: "No search results were found.",
                    comment: "A generic message shown when the user's search query produces no search results."
                ),
                systemImage: "magnifyingglass"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 12)
        }
    }
}
