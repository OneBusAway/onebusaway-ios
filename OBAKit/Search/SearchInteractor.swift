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

protocol SearchDelegate: NSObjectProtocol {
    func performSearch(request: SearchRequest)
    func showMapItem(_ mapItem: MKMapItem)
    func searchInteractor(_ searchInteractor: SearchInteractor, showStop stop: Stop)
    func searchInteractorNewResultsAvailable(_ searchInteractor: SearchInteractor)
    var isVehicleSearchAvailable: Bool { get }
}

/// This class is responsible for building all of the data objects that power the search experience without actually creating the UI.
/// In other words, use an object of this class to power your `IGListKit` data source.
///
/// The intention behind making `SearchInteractor` responsible for creating data and not a UI is that the default app
/// experience does not provide an easy path for building out a separate search view controller. Thus, in order to avoid having
/// to duplicate the data elements in order to provide different search experiences, `SearchInteractor` was born.
class SearchInteractor: NSObject {
    enum ListSection: String {
        case recentStops
        case bookmarks
        case quickSearch
        case placemarks
    }

    enum PlacemarkSearchState {
        case idle
        case loading
        case success
        case error(Error)
        case noResults
    }

    private let application: Application
    private let userDataStore: UserDataStore
    public weak var delegate: SearchDelegate?

    /// Creates a new `SearchInteractor`
    /// - Parameter application: The global Application object
    /// - Parameter delegate: A delegate that will receive callbacks when events occur
    init(application: Application, delegate: SearchDelegate) {
        self.application = application
        self.userDataStore = application.userDataStore
        self.delegate = delegate
    }

    func searchModeObjects(text: String?) -> [OBAListViewSection] {
        guard
            let searchText = text?.trimmingCharacters(in: .whitespacesAndNewlines),
            searchText.count > 0
        else {
            return []
        }

        var sections: [OBAListViewSection?] = []

        sections.append(quickSearchSection(searchText: searchText))
        sections.append(buildRecentStopsSection(searchText: searchText))
        sections.append(buildBookmarksSection(searchText: searchText))

        if let mapRect = application.mapRegionManager.lastVisibleMapRect {
            placemarkSearch(searchText: searchText, mapRect: mapRect)
            sections.append(buildPlacemarksSection())
        }

        return sections.compactMap { $0 }
    }

    // MARK: - Private
    private func listSection<Item: OBAListViewItem>(for section: ListSection, title: String? = nil, contents: [Item]) -> OBAListViewSection {
        return OBAListViewSection(id: section.rawValue, title: title, contents: contents)
    }

    private func buildRecentStopsSection(searchText: String) -> OBAListViewSection? {
        let recentStops = userDataStore.findRecentStops(matching: searchText).map { stop in
            OBAListRowView.DefaultViewModel(title: stop.name, accessoryType: .disclosureIndicator) { _ in
                self.delegate?.searchInteractor(self, showStop: stop)
            }
        }

        guard recentStops.count > 0 else {
            return nil
        }

        return listSection(for: .recentStops, title: Strings.recentStops, contents: recentStops)
    }

    private func buildBookmarksSection(searchText: String) -> OBAListViewSection? {
        let bookmarks = userDataStore.findBookmarks(matching: searchText).map { bookmark in
            OBAListRowView.DefaultViewModel(title: bookmark.name, accessoryType: .disclosureIndicator) { _ in
                self.delegate?.searchInteractor(self, showStop: bookmark.stop)
            }
        }

        guard bookmarks.count > 0 else {
            return nil
        }

        return listSection(for: .bookmarks, title: OBALoc("search_controller.bookmarks.header", value: "Bookmarks", comment: "Title of the Bookmarks search header"), contents: bookmarks)
    }

    // MARK: - Placemarks Section

    private var placemarkSearchTask: Task<Void, Never>?
    private var cachedPlacemarks: [MKMapItem] = [] {
        didSet {
            delegate?.searchInteractorNewResultsAvailable(self)
        }
    }
    private var placemarkSearchState: PlacemarkSearchState = .idle {
        didSet {
            delegate?.searchInteractorNewResultsAvailable(self)
        }
    }
    private var lastSearchText: String = ""
    private let placemarkSearchDebounceInterval: TimeInterval = 0.35 // 350ms
    private var localSearch: MKLocalSearch?
    private var debounceTimer: Timer?

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
            withTimeInterval: placemarkSearchDebounceInterval,
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
            searchRequest.region = MKCoordinateRegion(mapRect)
            let search = MKLocalSearch(request: searchRequest)
            search.start { response, error in
                if let error {
                    self.placemarkSearchState = .error(error)
                    return
                }

                guard let response else {
                    let unknownError = NSError(domain: "SearchInteractor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Local search response is nil"])
                    self.placemarkSearchState = .error(unknownError)
                    return
                }

                if response.mapItems.isEmpty {
                    self.placemarkSearchState = .noResults
                } else {
                    self.placemarkSearchState = .success
                    self.cachedPlacemarks = response.mapItems
                }
            }

            self.localSearch = search
        }
    }

    private func buildPlacemarksSection() -> OBAListViewSection? {
        let sectionTitle = OBALoc("search_controller.placemarks.header", value: "Results", comment: "Placemark search header")

        switch placemarkSearchState {
        case .idle:
            return nil

        case .loading:
            let loadingMessage = OBALoc("search_controller.placemarks.loading", value: "Searching for places...", comment: "Loading message for placemark search")
            var item = OBAListRowView.DefaultViewModel(title: loadingMessage, accessoryType: .none)
            item.image = UIImage(systemName: "magnifyingglass")
            return OBAListViewSection(id: ListSection.placemarks.rawValue, title: sectionTitle, contents: [item])

        case .error(let error):
            var item = OBAListRowView.DefaultViewModel(title: error.localizedDescription, accessoryType: .none)
            // Set appropriate error icon based on error type
            if let apiError = error as? APIError {
                switch apiError {
                case .networkFailure:
                    item.image = UIImage(systemName: "wifi.slash")
                case .captivePortal:
                    item.image = UIImage(systemName: "wifi.exclamationmark")
                default:
                    item.image = UIImage(systemName: "exclamationmark.triangle")
                }
            } else {
                item.image = UIImage(systemName: "exclamationmark.triangle")
            }
            return OBAListViewSection(id: ListSection.placemarks.rawValue, title: sectionTitle, contents: [item])

        case .noResults:
            let noResultsMessage = OBALoc("search_controller.placemarks.no_results", value: "No results found", comment: "No results message for placemark search")
            var item = OBAListRowView.DefaultViewModel(title: noResultsMessage, accessoryType: .none)
            item.image = UIImage(systemName: "magnifyingglass")
            return OBAListViewSection(id: ListSection.placemarks.rawValue, title: sectionTitle, contents: [item])

        case .success:
            var items: [SearchPlacemarkViewModel] = []

            for p in cachedPlacemarks {
                let item = SearchPlacemarkViewModel(
                    mapItem: p,
                    currentLocation: application.locationService.currentLocation,
                    distanceFormatter: application.formatters.distanceFormatter
                ) { [weak self] viewModel in
                    guard let self = self else { return }
                    self.delegate?.showMapItem(viewModel.mapItem)
                }
                items.append(item)
            }

            return listSection(for: .placemarks, title: sectionTitle, contents: items)
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

    private func quickSearchSection(searchText: String) -> OBAListViewSection {

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

        var items: [OBAListRowView.DefaultViewModel] = []

        let badgeRenderer = ImageBadgeRenderer(fillColor: .white, backgroundColor: ThemeColors.shared.brand, badgeSize: 20.0)

        for (searchType, title, image) in quickSearchTypes {
            var item = OBAListRowView.DefaultViewModel(title: quickSearchLabel(prefix: title, searchText: searchText), accessoryType: .disclosureIndicator) { [weak self] _ in
                guard let self = self else { return }
                let request = SearchRequest(query: searchText, type: searchType)
                self.delegate?.performSearch(request: request)
            }

            item.image = badgeRenderer.drawImageOnRoundedRect(image)

            items.append(item)
        }

        return listSection(for: .quickSearch, title: OBALoc("search_controller.quick_search.header", value: "Quick Search", comment: "Quick Search section header in search"), contents: items)
    }
}
