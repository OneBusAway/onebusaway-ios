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

    /// Mirrors `AlertPresenter.show(errorMessage:)`, which the UIKit map uses for
    /// both search failures and the no-results case: `Strings.error` as the title,
    /// the message as the body, one dismiss button.
    private var messageAlert: Binding<Bool> {
        Binding(
            get: { viewModel.message != nil },
            set: { if !$0 { viewModel.dismissMessage() } }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            SearchListView(searchInteractor: viewModel.searchInteractor)
        }
        .searchSheetBackground()
        .onAppear {
            viewModel.reportSearchOpened()
            isFieldFocused = true
            // `onDisappear` dismisses the HUD, and the sheet system rebuilds a sheet's
            // content view without the user going anywhere — see
            // `MapSearchDisplayModel.owner`. `isSearching` doesn't change across that
            // rebuild, so `onChange` won't fire and the HUD has to be restored here or
            // an in-flight search runs with nothing on screen.
            if viewModel.isSearching {
                ProgressHUD.show()
            }
        }
        // The app-wide HUD rather than a spinner of our own: it centres itself over
        // everything, which is what the rest of the app does for an in-flight
        // request, and it's already what `SearchManager` shows on the UIKit path.
        .onChange(of: viewModel.isSearching) { _, isSearching in
            if isSearching {
                ProgressHUD.show()
            } else {
                ProgressHUD.dismiss()
            }
        }
        // The HUD lives in its own window, so leaving search mid-request would
        // otherwise strand it on screen with nothing left to dismiss it.
        .onDisappear { ProgressHUD.dismiss() }
        // Outcomes go to an alert rather than a banner above the list: the banner
        // pushed the list down on every failed search, and it sat in the one place
        // the user is looking while typing.
        .alert(Strings.error, isPresented: messageAlert, presenting: viewModel.message) { _ in
            Button(Strings.dismiss, role: .cancel) { }
        } message: { message in
            Text(message.text)
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
                            // `Color.secondary`, not the `.secondary` shape style:
                            // inside a `Button` the latter resolves against the
                            // button's tint, which rendered a washed-out accent
                            // colour rather than grey. `.plain` keeps the tint off
                            // the label for good measure.
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
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

}
