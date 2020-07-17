//
//  SearchInteractor.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import IGListKit
import OBAKitCore

protocol SearchDelegate: NSObjectProtocol {
    func performSearch(request: SearchRequest)
    func searchInteractor(_ searchInteractor: SearchInteractor, showStop stop: Stop)
    var isVehicleSearchAvailable: Bool { get }
}

/// This class is responsible for building all of the data objects that power the search experience without actually creating the UI.
/// In other words, use an object of this class to power your `IGListKit` data source.
///
/// The intention behind making `SearchInteractor` responsible for creating data and not a UI is that the default app
/// experience does not provide an easy path for building out a separate search view controller. Thus, in order to avoid having
/// to duplicate the data elements in order to provide different search experiences, `SearchInteractor` was born.
class SearchInteractor: NSObject {
    private let userDataStore: UserDataStore
    public weak var delegate: SearchDelegate?

    /// Creates a new `SearchInteractor`
    /// - Parameter userDataStore: A concrete object that conforms to the `UserDataStore` protocol
    /// - Parameter delegate: A delegate that will receive callbacks when events occur
    init(userDataStore: UserDataStore, delegate: SearchDelegate) {
        self.userDataStore = userDataStore
        self.delegate = delegate
    }

    func searchModeObjects(text: String?, listAdapter: ListAdapter) -> [ListDiffable] {
        guard
            let searchText = text?.trimmingCharacters(in: .whitespacesAndNewlines),
            searchText.count > 0
        else { return [] }

        var sections: [ListDiffable] = []

        sections.append(contentsOf: quickSearchSection(searchText: searchText))
        sections.append(contentsOf: buildRecentStopsSection(searchText: searchText))
        sections.append(contentsOf: buildBookmarksSection(searchText: searchText))

        return sections
    }

    // MARK: - Private

    private func buildRecentStopsSection(searchText: String) -> [ListDiffable] {
        let recentStops = userDataStore.findRecentStops(matching: searchText).map { stop in
            TableRowData(title: stop.name, accessoryType: .disclosureIndicator) { _ in
                self.delegate?.searchInteractor(self, showStop: stop)
            }
        }

        guard recentStops.count > 0 else {
            return []
        }

        return [TableHeaderData(title: Strings.recentStops), TableSectionData(rows: recentStops)]
    }

    private func buildBookmarksSection(searchText: String) -> [ListDiffable] {
        let bookmarks = userDataStore.findBookmarks(matching: searchText).map { bookmark in
            TableRowData(title: bookmark.name, accessoryType: .disclosureIndicator) { _ in
                self.delegate?.searchInteractor(self, showStop: bookmark.stop)
            }
        }

        guard bookmarks.count > 0 else {
            return []
        }

        return [
            TableHeaderData(title: OBALoc("search_controller.bookmarks.header", value: "Bookmarks", comment: "Title of the Bookmarks search header")),
            TableSectionData(rows: bookmarks)
        ]
    }

    // MARK: - Private/Quick Search

    private func quickSearchLabel(prefix: String, searchText: String) -> NSAttributedString {
        let string = NSMutableAttributedString(string: "\(prefix) ")
        let boldFont = UIFont.preferredFont(forTextStyle: .body).bold
        let boldSearchText = NSAttributedString(string: searchText, attributes: [NSAttributedString.Key.font: boldFont])
        string.append(boldSearchText)

        return string
    }

    /// Creates a Quick Search section
    /// - Parameter searchText: The text that the user is searching for
    private func quickSearchSection(searchText: String) -> [ListDiffable] {
        var quickSearchTypes: [(SearchType, String, UIImage)] = [
            (.route, OBALoc("search_interactor.quick_search.route_prefix", value: "Route:", comment: "Quick search prefix for Route."), Icons.route),
            (.address, OBALoc("search_interactor.quick_search.address_prefix", value: "Address:", comment: "Quick search prefix for Address."), Icons.place),
            (.stopNumber, OBALoc("search_interactor.quick_search.stop_prefix", value: "Stop:", comment: "Quick search prefix for Stop."), Icons.stop)
        ]

        if let delegate = delegate, delegate.isVehicleSearchAvailable {
            quickSearchTypes.append((.vehicleID, OBALoc("search_interactor.quick_search.vehicle_prefix", value: "Vehicle:", comment: "Quick search prefix for Vehicle."), Icons.busTransport))
        }

        var rows = [TableRowData]()

        let badgeRenderer = ImageBadgeRenderer(fillColor: .white, backgroundColor: ThemeColors.shared.brand, badgeSize: 20.0)

        for (searchType, title, image) in quickSearchTypes {
            let row = TableRowData(attributedTitle: quickSearchLabel(prefix: title, searchText: searchText), accessoryType: .disclosureIndicator) { [weak self] _ in
                guard let self = self else { return }
                let request = SearchRequest(query: searchText, type: searchType)
                self.delegate?.performSearch(request: request)
            }

            row.image = badgeRenderer.drawImageOnRoundedRect(image)
            row.imageSize = badgeRenderer.badgeSize
            rows.append(row)
        }

        return [
            TableHeaderData(title: OBALoc("search_controller.quick_search.header", value: "Quick Search", comment: "Quick Search section header in search")),
            TableSectionData(rows: rows)
        ]
    }
}
