//
//  SearchSheetViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import OBAKitCore

/// Owns a search session: the query, the `SearchInteractor` that turns it into
/// sections, and the `SearchDelegate` callbacks those sections fire.
///
/// This is the role `MapFloatingPanelController` plays for the UIKit panel. It's a
/// class (not view state) because `SearchDelegate` is a class protocol that
/// `SearchInteractor` holds weakly — the view retains this via `@StateObject`.
@MainActor
final class SearchSheetViewModel: NSObject, ObservableObject, SearchDelegate {

    @Published var query: String = ""

    /// Set when a search returns nothing, so the sheet can say so in place rather
    /// than popping the alert the UIKit path shows.
    @Published private(set) var showsNoResults = false

    /// Set when resolving a result fails, rendered inline for the same reason.
    @Published private(set) var errorMessage: String?

    @Published private(set) var isSearching = false

    private(set) lazy var searchInteractor = SearchInteractor(application: application, delegate: self)

    private let application: Application
    private let coordinator: SheetCoordinator<AppSheetRoute>
    private let router: SearchResultRouter
    private var searchTask: Task<Void, Never>?

    init(application: Application, coordinator: SheetCoordinator<AppSheetRoute>, router: SearchResultRouter) {
        self.application = application
        self.coordinator = coordinator
        self.router = router
        super.init()
    }

    isolated deinit {
        searchTask?.cancel()
        pendingPresentation?.cancel()
    }

    // MARK: - Session

    /// Reported once per entry into search, matching the UIKit panel's
    /// `inSearchMode` analytics.
    func reportSearchOpened() {
        application.analytics?.reportEvent(
            pageURL: "app://localhost/map",
            label: AnalyticsLabels.searchSelected,
            value: nil
        )
    }

    func updateQuery(_ text: String) {
        query = text
        showsNoResults = false
        errorMessage = nil
        searchInteractor.searchModeObjects(text: text)
    }

    /// Leaves search and returns the base sheet to home.
    func close() {
        searchTask?.cancel()
        searchTask = nil
        coordinator.pop()
    }

    // MARK: - SearchDelegate

    func performSearch(request: SearchRequest) {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            await self?.performSearchAndWait(request: request)
        }
    }

    /// The awaitable body of `performSearch`, so tests don't have to poll a
    /// fire-and-forget task.
    func performSearchAndWait(request: SearchRequest) async {
        application.analytics?.reportSearchQuery(request.query)

        isSearching = true
        showsNoResults = false
        errorMessage = nil
        defer { isSearching = false }

        let response: SearchResponse?
        do {
            response = try await application.searchManager.fetchResults(for: request)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        guard let response, !response.results.isEmpty else {
            showsNoResults = true
            return
        }

        guard response.results.count == 1 else {
            coordinator.push(.searchResults(response))
            return
        }

        // Leave search before opening the result, so Close on the detail sheet lands
        // back on home rather than on a stale search screen.
        coordinator.pop()
        _ = await router.presentSingleResult(from: response)
        if let error = router.lastError {
            errorMessage = error.localizedDescription
        }
    }

    /// The in-flight `router.present(...)` kicked off by a delegate callback.
    /// `SearchDelegate`'s methods are synchronous, so presentation has to be
    /// detached — this handle lets tests await it instead of polling.
    private(set) var pendingPresentation: Task<Void, Never>?

    func showMapItem(_ mapItem: MKMapItem) {
        application.userDataStore.addRecentMapItem(mapItem)
        coordinator.pop()
        pendingPresentation = Task { [router] in await router.present(result: mapItem) }
    }

    func searchInteractor(_ searchInteractor: SearchInteractor, showStop stop: Stop) {
        coordinator.pop()
        pendingPresentation = Task { [router] in await router.present(result: stop) }
    }

    /// The interactor asks; the view presents the confirmation and calls
    /// `confirmClearRecentSearches()` if the user agrees.
    @Published var isConfirmingClearRecents = false

    func searchInteractorClearRecentSearches(_ searchInteractor: SearchInteractor) {
        isConfirmingClearRecents = true
    }

    func confirmClearRecentSearches() {
        application.userDataStore.deleteAllRecentMapItems()
        searchInteractor.searchModeObjects(text: query)
    }

    var isVehicleSearchAvailable: Bool {
        application.features.obaco == .running
    }
}
