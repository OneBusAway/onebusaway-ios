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

/// A one-shot search outcome, surfaced by the view as an alert.
///
/// Identity is fresh per message, so two identical failures in a row are two
/// distinct values. A plain `String?` or `Bool` would coalesce when the reset and
/// the re-set land in the same update pass, silently swallowing the second alert.
struct SearchSheetMessage: Identifiable, Equatable {
    enum Kind: Equatable {
        /// The search ran and matched nothing.
        case noResults
        /// The search failed, or could not be attempted.
        case error
    }

    let id = UUID()
    let kind: Kind
    let text: String
}

/// Owns a search session: the query, the `SearchInteractor` that turns it into
/// sections, and the `SearchDelegate` callbacks those sections fire.
///
/// This is the role `MapFloatingPanelController` plays for the UIKit panel. It's a
/// class (not view state) because `SearchDelegate` is a class protocol that
/// `SearchInteractor` holds weakly — the view retains this via `@StateObject`.
@MainActor
final class SearchSheetViewModel: NSObject, ObservableObject, SearchDelegate {

    @Published var query: String = ""

    @Published private(set) var message: SearchSheetMessage?

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
        message = nil
        searchInteractor.searchModeObjects(text: text)
    }

    /// Called when the view dismisses the alert, so a repeat of the same failing
    /// search presents again rather than being swallowed as "no change".
    func dismissMessage() {
        message = nil
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

    /// What a finished `fetchResults` call means for the screen.
    ///
    /// Split out as a pure function because the interesting distinction —
    /// `nil` (the search never ran) versus an empty result set (it ran and matched
    /// nothing) — isn't reachable through the test `Application`, which always has a
    /// region, an API service, and an Obaco service.
    enum SearchOutcome: Equatable {
        /// No API service, no Obaco service, or no map rect. The query was never sent.
        case unavailable
        /// The search ran and matched nothing.
        case noResults
        case single(SearchResponse)
        case disambiguate(SearchResponse)

        init(response: SearchResponse?) {
            guard let response else {
                self = .unavailable
                return
            }
            if response.results.isEmpty {
                self = .noResults
            } else if response.results.count == 1 {
                self = .single(response)
            } else {
                self = .disambiguate(response)
            }
        }
    }

    /// The awaitable body of `performSearch`, so tests don't have to poll a
    /// fire-and-forget task.
    func performSearchAndWait(request: SearchRequest) async {
        application.analytics?.reportSearchQuery(request.query)

        isSearching = true
        message = nil
        defer { isSearching = false }

        let response: SearchResponse?
        do {
            response = try await application.searchManager.fetchResults(for: request)
        } catch {
            message = SearchSheetMessage(kind: .error, text: error.localizedDescription)
            return
        }

        switch SearchOutcome(response: response) {
        case .unavailable:
            // The query was never sent. Saying "no results" would send the user off
            // rewording a search that never left the device.
            message = SearchSheetMessage(kind: .error, text: APIError.noRegionSelected.localizedDescription)

        case .noResults:
            message = SearchSheetMessage(kind: .noResults, text: Self.noResultsText)

        case .disambiguate(let response):
            coordinator.push(.searchResults(response))

        case .single(let response):
            // Resolve first, leave search second. Popping before the result was
            // resolved tore this view — and the alert it hosts — down mid-request, so
            // a failure had nowhere to surface and the user landed on home with no
            // explanation. It also left the stacked sheet layer empty across the call.
            guard let resolved = await router.resolveSingleResult(from: response) else {
                if let error = router.lastError {
                    message = SearchSheetMessage(kind: .error, text: error.localizedDescription)
                }
                return
            }
            // Leave search before opening the result, so Close on the detail sheet
            // lands back on home rather than on a stale search screen.
            coordinator.pop()
            router.present(resolved)
        }
    }

    static let noResultsText = OBALoc(
        "map_controller.no_search_results_found",
        value: "No search results were found.",
        comment: "A generic message shown when the user's search query produces no search results."
    )

    /// The in-flight `router.present(...)` kicked off by a delegate callback.
    /// `SearchDelegate`'s methods are synchronous, so presentation has to be
    /// detached — this handle lets tests await it instead of polling.
    private(set) var pendingPresentation: Task<Void, Never>?

    func showMapItem(_ mapItem: MKMapItem) {
        application.userDataStore.addRecentMapItem(mapItem)
        pendingPresentation = Task { [weak self] in await self?.leaveSearchAndPresent(mapItem) }
    }

    func searchInteractor(_ searchInteractor: SearchInteractor, showStop stop: Stop) {
        pendingPresentation = Task { [weak self] in await self?.leaveSearchAndPresent(stop) }
    }

    /// Same order as the single-result path: resolve, then unwind, then present — so
    /// search is only left once there's something to show.
    private func leaveSearchAndPresent(_ result: Any) async {
        guard let resolved = await router.resolve(result: result) else {
            if let error = router.lastError {
                message = SearchSheetMessage(kind: .error, text: error.localizedDescription)
            }
            return
        }
        coordinator.pop()
        router.present(resolved)
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
