//
//  SearchInteractor.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore
import MapKit
import Observation

/// Scoping tags for filtering search suggestions and results.
enum SearchScope: String, CaseIterable, Identifiable, Hashable {
    case all
    case stops
    case routes
    case places

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            return OBALoc("search_scope.all", value: "All", comment: "Search scope tag showing all search result types.")
        case .stops:
            return Strings.stops
        case .routes:
            return OBALoc("search_scope.routes", value: "Routes", comment: "Search scope tag filtering results to transit routes.")
        case .places:
            return OBALoc("search_scope.places", value: "Places", comment: "Search scope tag filtering results to places and addresses.")
        }
    }

    /// Quick-search rows offered under this scope, in display order.
    func quickSearchTypes(includeVehicle: Bool) -> [SearchType] {
        switch self {
        case .all:
            var types: [SearchType] = [.route, .address, .stopNumber]
            if includeVehicle {
                types.append(.vehicleID)
            }
            return types
        case .stops:
            return [.stopNumber]
        case .routes:
            return [.route]
        case .places:
            return [.address]
        }
    }

    /// Direct search type executed on keyboard submission, or `nil` when
    /// multiple types apply and the rider picks from quick-search suggestions.
    var submitSearchType: SearchType? {
        switch self {
        case .all: nil
        case .stops: .stopNumber
        case .routes: .route
        case .places: .address
        }
    }

    var includesStops: Bool {
        self == .all || self == .stops
    }

    var includesPlaces: Bool {
        self == .all || self == .places
    }
}

protocol SearchDelegate: NSObjectProtocol {
    func performSearch(request: SearchRequest)
    func showMapItem(_ mapItem: MKMapItem)
    func searchInteractor(_ searchInteractor: SearchInteractor, showStop stop: Stop)
    func searchInteractorClearRecentSearches(_ searchInteractor: SearchInteractor)
    var isVehicleSearchAvailable: Bool { get }
}

/// This class is responsible for building all of the data objects that power the search experience without actually creating the UI.
/// The intention behind making `SearchInteractor` responsible for creating data and not a UI is that the default app
/// experience does not provide an easy path for building out a separate search view. Thus, in order to avoid having
/// to duplicate the data elements in order to provide different search experiences, `SearchInteractor` was born.

@Observable
class SearchInteractor: NSObject {

    private enum PlacemarkSearchState {
        case idle
        case loading
        case success
        case error(Error)
        case noResults
    }

    // MARK: - Properties

    private let application: Application
    private let userDataStore: UserDataStore
    weak var delegate: SearchDelegate?

    private var isUpdatingSections = false

    private var placemarkSearchState: PlacemarkSearchState = .idle {
        didSet {
            guard !isUpdatingSections else { return }
            searchModeObjects(text: lastQuery, scope: lastScope)
        }
    }

    private var lastQuery: String = ""
    private var lastScope: SearchScope = .all

    private var lastSearchText: String = ""
    private var localSearch: MKLocalSearch?
    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 0.35

    private var cachedPlacemarks: [MKMapItem] = []

    private(set) var sections: [SearchListSection] = []

    // MARK: - Init
    /// Creates a new `SearchInteractor`
    /// - Parameter application: The global Application object
    /// - Parameter delegate: A delegate that will receive callbacks when events occur
    init(application: Application, delegate: SearchDelegate) {
        self.application = application
        self.userDataStore = application.userDataStore
        self.delegate = delegate
    }

    // MARK: - Deinit
    isolated deinit {
        debounceTimer?.invalidate()
        localSearch?.cancel()
    }

    func searchModeObjects(text: String?, scope: SearchScope = .all) {
        isUpdatingSections = true
        defer { isUpdatingSections = false }

        lastQuery = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        lastScope = scope

        if !scope.includesPlaces || lastQuery.isEmpty {
            cancelPendingPlacemarkSearch()
        }

        if lastQuery.isEmpty {
            self.sections = emptyQuerySections(for: scope)
            return
        }

        var newSections: [SearchListSection?] = [
            quickSearchSection(searchText: lastQuery, scope: scope)
        ]

        if scope.includesStops {
            newSections.append(buildRecentStopsSection(searchText: lastQuery))
            newSections.append(buildBookmarksSection(searchText: lastQuery))
        }

        if scope.includesPlaces, let mapRect = application.mapRegionManager.lastVisibleMapRect {
            placemarkSearch(searchText: lastQuery, mapRect: mapRect)
            newSections.append(buildPlacemarksSection())
        }

        self.sections = newSections.compactMap { $0 }
    }

    private func emptyQuerySections(for scope: SearchScope) -> [SearchListSection] {
        switch scope {
        case .all, .places:
            return [buildRecentMapItemsSection()].compactMap { $0 }
        case .stops:
            return [
                buildRecentStopsSection(searchText: ""),
                buildBookmarksSection(searchText: "")
            ].compactMap { $0 }
        case .routes:
            return []
        }
    }

    private func cancelPendingPlacemarkSearch() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        localSearch?.cancel()
        localSearch = nil
        lastSearchText = ""
        placemarkSearchState = .idle
    }

    // MARK: - Recent Stops
    private func buildRecentStopsSection(searchText: String) -> SearchListSection? {
        let matchingStops = searchText.isEmpty
            ? userDataStore.recentStops
            : userDataStore.findRecentStops(matching: searchText)
        let recentStops = matchingStops.map { stop in
            SearchListRow(kind: .recentStop(id: stop.id), title: stop.name, accessory: .disclosureIndicator) { [weak self] in
                guard let self else { return }
                self.delegate?.searchInteractor(self, showStop: stop)
            }
        }

        guard !recentStops.isEmpty else {
            return nil
        }

        return .init(id: .recentStops, title: Strings.recentStops, content: recentStops)
    }

    // MARK: - Bookmarks
    private func buildBookmarksSection(searchText: String) -> SearchListSection? {
        let matchingBookmarks = searchText.isEmpty
            ? userDataStore.bookmarks
            : userDataStore.findBookmarks(matching: searchText)
        let bookmarks = matchingBookmarks.map { bookmark in
            SearchListRow(kind: .bookmark(id: bookmark.id.uuidString), title: bookmark.name, accessory: .disclosureIndicator) { [weak self] in
                guard let self else { return }
                self.delegate?.searchInteractor(self, showStop: bookmark.stop)
            }
        }

        guard !bookmarks.isEmpty else {
            return nil
        }

        return .init(
            id: .bookmarks,
            title: Strings.bookmarks,
            content: bookmarks
        )
    }

    private func buildRecentMapItemsSection() -> SearchListSection? {
        let recentItems = userDataStore.recentMapItems

        guard !recentItems.isEmpty else {
            return nil
        }

        var items: [SearchListRow] = mapPlacemarkItems(recentItems)

        // Add clear button at the end
        let clearButton: SearchListRow = .init(kind: .clearRecents, title: Strings.clearRecentSearches, icon: .system("trash")) { [weak self] in
            guard let self = self else { return }
            self.delegate?.searchInteractorClearRecentSearches(self)
        }

        items.append(clearButton)

        return .init(id: .recentMapItems, title: Strings.recentSearches, content: items)
    }

    // MARK: - Placemarks Section

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func placemarkSearch(searchText: String, mapRect: MKMapRect) {
        guard
            searchText != lastSearchText,
            searchText.count >= 2
        else {
            return
        }

        lastSearchText = searchText

        debounceTimer?.invalidate()
        debounceTimer = nil

        debounceTimer = Timer.scheduledMainActorTimer(
            withTimeInterval: debounceInterval,
            repeats: false
        ) { [weak self] in
            guard let self = self else { return }

            if let localSearch = self.localSearch {
                localSearch.cancel()
            }

            // Set loading state when search starts
            self.placemarkSearchState = .loading

            let searchRequest = MKLocalSearch.Request()
            searchRequest.naturalLanguageQuery = searchText
            // Use the current OBA region's service bounds instead of the visible map area
            // to constrain search results to the transit agency's coverage area
            let searchRegion: MKCoordinateRegion
            if let currentRegion = self.application.currentRegion {
                searchRegion = MKCoordinateRegion(currentRegion.serviceRect)
            } else {
                // Fallback to visible map area if no region is set
                searchRegion = MKCoordinateRegion(mapRect)
            }
            searchRequest.region = searchRegion
            let search = MKLocalSearch(request: searchRequest)
            self.localSearch = search
            search.start { [weak self, weak search] response, error in
                DispatchQueue.main.async {
                    guard let self, let search, self.localSearch === search else { return }
                    if let error {
                        if (error as? URLError)?.code == .cancelled {
                            return
                        }
                        self.placemarkSearchState = .error(error)
                        return
                    }

                    guard let response else {
                        let unknownError = NSError(domain: "SearchInteractor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Local search response is nil"])
                        self.placemarkSearchState = .error(unknownError)
                        return
                    }

                    // Filter results to only include items within the current region's bounds
                    var filteredItems = response.mapItems
                    if let currentRegion = self.application.currentRegion {
                        filteredItems = response.mapItems.filter { mapItem in
                            guard let location = mapItem.placemark.location else { return false }
                            return currentRegion.contains(location: location)
                        }
                    }

                    if filteredItems.isEmpty {
                        self.placemarkSearchState = .noResults
                    } else {
                        self.cachedPlacemarks = filteredItems
                        self.placemarkSearchState = .success
                    }

                }
            }
        }
    }

    private func buildPlacemarksSection() -> SearchListSection? {
        let sectionTitle = OBALoc("search_controller.placemarks.header", value: "Results", comment: "Placemark search header")

        var items: [SearchListRow] = []

        switch placemarkSearchState {
        case .idle:
            return nil

        case .loading:
            items = [
                .init(
                    kind: .loading,
                    title: OBALoc("search_controller.placemarks.loading", value: "Searching for places...", comment: "Loading message for placemark search"),
                    icon: .system("magnifyingglass")
                )
            ]
        case .error(let error):
            let classified = ErrorClassifier.classify(error, regionName: application.currentRegionName)
            let icon = systemImageForError(classified)
            let errorMessage = classified.localizedDescription
            items = [SearchListRow(
                kind: .error(errorMessage, systemImage: icon),
                title: errorMessage,
                subtitle: OBALoc("search_controller.placemarks.error_retry", value: "Tap to retry", comment: "Subtitle on search error row prompting the user to retry."),
                icon: .system(icon),
                action: { [weak self] in self?.retryPlacemarkSearch() }
            )]

        case .noResults:
            items = [
                .init(
                    kind: .noResults,
                    title: OBALoc("search_controller.placemarks.no_results", value: "No results found", comment: "No results message for placemark search"),
                    icon: .system("magnifyingglass")
                )
            ]

        case .success:
            items = mapPlacemarkItems(cachedPlacemarks)
        }

        return .init(id: .placemarks, title: sectionTitle, content: items)
    }

    private func retryPlacemarkSearch() {
        lastSearchText = ""
        searchModeObjects(text: lastQuery, scope: lastScope)
    }

    private func systemImageForError(_ error: Error) -> String {
        guard let apiError = error as? APIError else {
            return "exclamationmark.triangle"
        }
        switch apiError {
        case .networkFailure, .cellularDataRestricted:
            return "wifi.slash"
        case .captivePortal:
            return "wifi.exclamationmark"
        case .serverError, .serverUnavailable:
            return "server.rack"
        default:
            return "exclamationmark.triangle"
        }
    }

    // MARK: - Private/Quick Search

    private func quickSearchLabel(prefix: String, searchText: String) -> NSAttributedString {
        let string = NSMutableAttributedString(string: "\(prefix) ")
        let boldFont = UIFont.preferredFont(forTextStyle: .body).bold
        let boldSearchText = NSAttributedString(string: searchText, attributes: [.font: boldFont])
        string.append(boldSearchText)

        return string
    }

    private func quickSearchPresentation(for searchType: SearchType) -> (prefix: String, icon: UIImage) {
        switch searchType {
        case .route:
            return (OBALoc("search_interactor.quick_search.route_prefix", value: "Route:", comment: "Quick search prefix for Route."), Icons.route)
        case .address:
            return (OBALoc("search_interactor.quick_search.address_prefix", value: "Address:", comment: "Quick search prefix for Address."), Icons.place)
        case .stopNumber:
            return (OBALoc("search_interactor.quick_search.stop_prefix", value: "Stop:", comment: "Quick search prefix for Stop."), Icons.stop)
        case .vehicleID:
            return (OBALoc("search_interactor.quick_search.vehicle_prefix", value: "Vehicle:", comment: "Quick search prefix for Vehicle."), Icons.busTransport)
        }
    }

    private func quickSearchSection(searchText: String, scope: SearchScope) -> SearchListSection? {
        let includeVehicle = delegate?.isVehicleSearchAvailable ?? false
        let items = scope.quickSearchTypes(includeVehicle: includeVehicle).map { searchType in
            let (prefix, icon) = quickSearchPresentation(for: searchType)
            return SearchListRow(
                kind: .quickSearch(searchType),
                attributedTitle: quickSearchLabel(prefix: prefix, searchText: searchText),
                icon: .uiImage(icon),
                accessory: .disclosureIndicator,
                action: { [weak self] in
                    let request = SearchRequest(query: searchText, type: searchType)
                    self?.delegate?.performSearch(request: request)
                }
            )
        }

        guard !items.isEmpty else {
            return nil
        }

        return .init(
            id: .quickSearch,
            title: OBALoc("search_controller.quick_search.header", value: "Quick Search", comment: "Quick Search section header in search"),
            content: items
        )
    }

    // MARK: - Helpers

    private func mapPlacemarkItems(_ items: [MKMapItem]) -> [SearchListRow] {
        items.compactMap { [weak self] mapItem -> SearchListRow? in
            guard let self else { return nil }
            guard let title = mapItem.name ?? mapItem.placemark.title, !title.isEmpty else { return nil }
            return SearchListRow(
                kind: .placemark(mapItem),
                title: title,
                subtitle: SearchListRow.subtitleForMapItem(self.application, mapItem),
                icon: SearchListRow.systemImageForMapItem(mapItem),
                accessory: .none
            ) { [weak self] in
                self?.delegate?.showMapItem(mapItem)
            }
        }
    }

}
