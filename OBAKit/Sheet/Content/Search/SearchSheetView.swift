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
    @State private var isSearchPresented = false

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

    private var queryBinding: Binding<String> {
        Binding(
            get: { viewModel.query },
            set: { newValue in
                guard newValue != viewModel.query else { return }
                viewModel.updateQuery(newValue)
            }
        )
    }

    var body: some View {
        NavigationStack {
            searchBody
                .navigationTitle(Text(OBALoc(
                    "search_controller.empty_set.title",
                    value: "Search",
                    comment: "Title for the empty set indicator on the Search controller."
                )))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        SheetDismissButton(.close) {
                            isSearchPresented = false
                            viewModel.close()
                        }
                    }

                    if viewModel.isVoiceSearchAvailable {
                        ToolbarItem(placement: .topBarTrailing) {
                            voiceSearchButton
                        }
                    }
                }
                .searchable(
                    text: queryBinding,
                    isPresented: $isSearchPresented,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text(placeholder)
                )
                .searchPresentationToolbarBehavior(.avoidHidingContent)
                .searchScopes($viewModel.scope, activation: .onSearchPresentation) {
                    ForEach(SearchScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .searchSuggestions {
                    if !viewModel.searchInteractor.sections.isEmpty {
                        SearchListSectionsView(
                            sections: viewModel.searchInteractor.sections,
                            onRowActivated: { isSearchPresented = false }
                        )
                    }
                }
                .searchListChrome()
                .autocorrectionDisabled()
                .onSubmit(of: .search) {
                    viewModel.submitSearch()
                }
                .onChange(of: isSearchPresented) { wasPresented, isPresented in
                    if wasPresented && !isPresented {
                        viewModel.scope = .all
                    }
                }
        }
        .onAppear {
            viewModel.reportSearchOpened()
            isSearchPresented = true
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

    @ViewBuilder
    private var searchBody: some View {
        // `.searchSuggestions` draws on the sheet's own background (its glass,
        // or grouped gray; see `AppSheetRoute.sheetBackground`) via
        // `.searchListChrome()`. Suppress
        // `SearchListView` while suggestions are presented so its list doesn't
        // show through behind them.
        if isSearchPresented && !viewModel.searchInteractor.sections.isEmpty {
            Color.clear
        } else {
            SearchListView(searchInteractor: viewModel.searchInteractor)
        }
    }

    private var voiceSearchButton: some View {
        Button {
            viewModel.toggleVoiceSearch()
        } label: {
            Image(systemName: viewModel.isListening ? "mic.fill" : "mic")
                .foregroundStyle(viewModel.isListening ? Color.accentColor : Color.secondary)
                .symbolEffect(.pulse, isActive: viewModel.isListening)
        }
        .accessibilityLabel(viewModel.isListening
            ? OBALoc(
                "search_sheet.voice_search.stop",
                value: "Stop listening",
                comment: "Accessibility label for the mic button while voice search is listening."
            )
            : OBALoc(
                "search_sheet.voice_search.start",
                value: "Voice search",
                comment: "Accessibility label for the mic button that starts voice search."
            )
        )
    }

}
