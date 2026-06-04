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
            searchModeObjects(text: lastQuery)
        }
    }

    private var lastQuery: String = ""

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
    deinit {
        debounceTimer?.invalidate()
        localSearch?.cancel()
    }

    func searchModeObjects(text: String?) {
        isUpdatingSections = true
        defer { isUpdatingSections = false }

        lastQuery = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Show recent map items when search is empty
        if lastQuery.isEmpty {
            lastSearchText = ""
            self.sections = [buildRecentMapItemsSection()].compactMap { $0 }
            return
        }

        var newSections: [SearchListSection?] = [
            quickSearchSection(searchText: lastQuery),
            buildRecentStopsSection(searchText: lastQuery),
            buildBookmarksSection(searchText: lastQuery)
        ]

        if let mapRect = application.mapRegionManager.lastVisibleMapRect {
            placemarkSearch(searchText: lastQuery, mapRect: mapRect)
            newSections.append(buildPlacemarksSection())
        }

        self.sections = newSections.compactMap { $0 }
    }

    // MARK: - Recent Stops
    private func buildRecentStopsSection(searchText: String) -> SearchListSection? {
        let recentStops = userDataStore.findRecentStops(matching: searchText).map { stop in
            SearchListRow(kind: .recentStop, title: stop.name, accessory: .disclosureIndicator) { [weak self] in
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
        let bookmarks = userDataStore.findBookmarks(matching: searchText).map { bookmark in
            SearchListRow(kind: .bookmark, title: bookmark.name, accessory: .disclosureIndicator) { [weak self] in
                guard let self else { return }
                self.delegate?.searchInteractor(self, showStop: bookmark.stop)
            }
        }

        guard !bookmarks.isEmpty else {
            return nil
        }

        return .init(
            id: .bookmarks,
            title: OBALoc("search_controller.bookmarks.header", value: "Bookmarks", comment: "Title of the Bookmarks search header"),
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

        debounceTimer = Timer.scheduledTimer(
            withTimeInterval: debounceInterval,
            repeats: false
        ) { [weak self] _ in
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
            search.start { [weak self] response, error in
                DispatchQueue.main.async {
                    guard let self else { return }
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
        searchModeObjects(text: lastQuery)
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

    private func quickSearchSection(searchText: String) -> SearchListSection {

        // swiftlint:disable large_tuple

        var quickSearchTypes: [(SearchType, String, UIImage)] = [
            (.route, OBALoc("search_interactor.quick_search.route_prefix", value: "Route:", comment: "Quick search prefix for Route."), Icons.route),
            (.address, OBALoc("search_interactor.quick_search.address_prefix", value: "Address:", comment: "Quick search prefix for Address."), Icons.place),
            (.stopNumber, OBALoc("search_interactor.quick_search.stop_prefix", value: "Stop:", comment: "Quick search prefix for Stop."), Icons.stop)
        ]

        // swiftlint:enable large_tuple

        if let delegate = delegate, delegate.isVehicleSearchAvailable {
            quickSearchTypes.append((.vehicleID, OBALoc("search_interactor.quick_search.vehicle_prefix", value: "Vehicle:", comment: "Quick search prefix for Vehicle."), Icons.busTransport))
        }

        let items = quickSearchTypes.map { (searchType, prefix, icon) in
            SearchListRow(
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
