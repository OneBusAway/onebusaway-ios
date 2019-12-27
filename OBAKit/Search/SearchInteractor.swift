//
//  SearchInteractor.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 7/19/19.
//

import Foundation
import IGListKit
import OBAKitCore

protocol SearchDelegate: NSObjectProtocol {
    func performSearch(request: SearchRequest)
    func searchInteractor(_ searchInteractor: SearchInteractor, showStop stop: Stop)
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

        sections.append(quickSearchSection(searchText: searchText))

        if let recentStopsSection = buildRecentStopsSection(searchText: searchText) {
            sections.append(recentStopsSection)
        }

        if let bookmarksSection = buildBookmarksSection(searchText: searchText) {
            sections.append(bookmarksSection)
        }

        return sections
    }

    // MARK: - Private

    private func buildRecentStopsSection(searchText: String) -> TableSectionData? {
        let recentStops = userDataStore.findRecentStops(matching: searchText).map { stop in
            TableRowData(title: stop.name, accessoryType: .disclosureIndicator) { _ in
                self.delegate?.searchInteractor(self, showStop: stop)
            }
        }

        guard recentStops.count > 0 else {
            return nil
        }

        return TableSectionData(title: NSLocalizedString("search_controller.recent_stops.header", value: "Recent Stops", comment: "Title of the Recent Stops search header"), rows: recentStops)
    }

    private func buildBookmarksSection(searchText: String) -> TableSectionData? {
        let bookmarks = userDataStore.findBookmarks(matching: searchText).map { bookmark in
            TableRowData(title: bookmark.name, accessoryType: .disclosureIndicator) { _ in
                self.delegate?.searchInteractor(self, showStop: bookmark.stop)
            }
        }

        guard bookmarks.count > 0 else {
            return nil
        }

        return TableSectionData(title: NSLocalizedString("search_controller.bookmarks.header", value: "Bookmarks", comment: "Title of the Bookmarks search header"), rows: bookmarks)
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
    private func quickSearchSection(searchText: String) -> ListDiffable {
        let quickSearchTypes: [(SearchType, String)] = [
            (.route, NSLocalizedString("search_interactor.quick_search.route_prefix", value: "Route:", comment: "Quick search prefix for Route.")),
            (.address, NSLocalizedString("search_interactor.quick_search.address_prefix", value: "Address:", comment: "Quick search prefix for Address.")),
            (.stopNumber, NSLocalizedString("search_interactor.quick_search.stop_prefix", value: "Stop:", comment: "Quick search prefix for Stop.")),
            (.vehicleID, NSLocalizedString("search_interactor.quick_search.vehicle_prefix", value: "Vehicle:", comment: "Quick search prefix for Vehicle."))
        ]

        var rows = [TableRowData]()

        for (searchType, title) in quickSearchTypes {
            let row = TableRowData(attributedTitle: quickSearchLabel(prefix: title, searchText: searchText), accessoryType: .disclosureIndicator) { [weak self] _ in
                guard let self = self else { return }
                let request = SearchRequest(query: searchText, type: searchType)
                self.delegate?.performSearch(request: request)
            }
            rows.append(row)
        }

        let quickSearchSection = TableSectionData(title: NSLocalizedString("search_controller.quick_search.header", value: "Quick Search", comment: "Quick Search section header in search"), rows: rows)

        return quickSearchSection
    }

}
