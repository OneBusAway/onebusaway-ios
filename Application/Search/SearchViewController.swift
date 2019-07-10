//
//  SearchViewController.swift
//  OBANext
//
//  Created by Aaron Brethorst on 1/12/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import UIKit
import IGListKit
import FloatingPanel

public protocol SearchDelegate: NSObjectProtocol {
    func searchController(_ searchController: SearchViewController, request: SearchRequest)
}

public class SearchViewController: VisualEffectViewController, ListProvider {
    public weak var searchDelegate: SearchDelegate?
    public weak var floatingPanelDelegate: FloatingPanelContainer?

    private let application: Application

    public lazy var collectionController = CollectionController(application: application, dataSource: self)
    private lazy var stackView = UIStackView.verticalStack(arangedSubviews: [searchBar, collectionController.view])

    public init(application: Application, floatingPanelDelegate: FloatingPanelContainer?) {
        self.application = application
        self.floatingPanelDelegate = floatingPanelDelegate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UIViewController Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        prepareChildController(collectionController) {
            visualEffectView.contentView.addSubview(stackView)
            stackView.pinToSuperview(.edges, insets: FloatingPanelSurfaceView.searchBarEdgeInsets)
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchBar.becomeFirstResponder()
    }

    // MARK: - Search Controller Properties

    public lazy var searchBar: UISearchBar = {
        let searchBar = UISearchBar.autolayoutNew()
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal

        if let region = application.regionsService.currentRegion {
            searchBar.placeholder = SearchViewController.searchPlaceholderText(region: region)
        }

        return searchBar
    }()

    /// Creates placeholder text for the search bar.
    ///
    /// - Parameter region: The user's current region.
    /// - Returns: A formatted string to be used in the `placeholder` property.
    public static func searchPlaceholderText(region: Region) -> String {
        let fmt = NSLocalizedString("search_controller.search_bar_placeholder_fmt", value: "Search in %@", comment: "Placeholder text for the search bar: 'Search in {REGION NAME}'")
        return String(format: fmt, region.name)
    }

    public var rawSearchText: String? {
        return searchBar.text
    }

    public var cleanedSearchText: String? {
        return rawSearchText?.trimmingCharacters(in: .whitespaces)
    }
}

extension SearchViewController: ListAdapterDataSource {
    public func objects(for listAdapter: ListAdapter) -> [ListDiffable] {
        guard let text = cleanedSearchText, text.count > 0 else {
            return []
        }

        return [quickSearchSection(term: text)]
    }

    private func quickSearchSection(term: String) -> TableSectionData {
        var rows = [TableRowData]()

        // Route
        let route = TableRowData(attributedTitle: buildAttributedQuickSearchString(kind: NSLocalizedString("search_controller.quick_search.route", value: "Route", comment: "Prefix for 'Route' quick search"), value: term), accessoryType: .disclosureIndicator) { _ in
            self.searchDelegate?.searchController(self, request: SearchRequest(query: term, type: .route))
        }
        rows.append(route)

        // Address
        let address = TableRowData(attributedTitle: buildAttributedQuickSearchString(kind: NSLocalizedString("search_controller.quick_search.address", value: "Address", comment: "Prefix for 'Address' quick search"), value: term), accessoryType: .disclosureIndicator) { _ in
            self.searchDelegate?.searchController(self, request: SearchRequest(query: term, type: .address))
        }
        rows.append(address)

        // Stop Number
        let stopNumber = TableRowData(attributedTitle: buildAttributedQuickSearchString(kind: NSLocalizedString("search_controller.quick_search.stop_number", value: "Stop number", comment: "Prefix for 'Stop number' quick search"), value: term), accessoryType: .disclosureIndicator) { _ in
            self.searchDelegate?.searchController(self, request: SearchRequest(query: term, type: .stopNumber))
        }
        rows.append(stopNumber)

        // Vehicle ID
        let vehicleID = TableRowData(attributedTitle: buildAttributedQuickSearchString(kind: NSLocalizedString("search_controller.quick_search.vehicle_id", value: "Vehicle ID", comment: "Prefix for 'Vehicle ID' quick search"), value: term), accessoryType: .disclosureIndicator) { _ in
            self.searchDelegate?.searchController(self, request: SearchRequest(query: term, type: .vehicleID))
        }
        rows.append(vehicleID)

        return TableSectionData(title: NSLocalizedString("search_controller.quick_search.section_title", value: "Quick Search", comment: "Table section title for Quick Search"), rows: rows, backgroundColor: UIColor.clear)
    }

    private func buildAttributedQuickSearchString(kind: String, value: String) -> NSAttributedString {
        let str = NSMutableAttributedString()
        str.append(NSAttributedString(string: "\(kind): ", attributes: [NSAttributedString.Key.font: application.theme.fonts.boldBody]))
        str.append(NSAttributedString(string: value, attributes: [NSAttributedString.Key.font: application.theme.fonts.body]))
        return str
    }

    public func listAdapter(_ listAdapter: ListAdapter, sectionControllerFor object: Any) -> ListSectionController {
        switch object {
        case is TableSectionData: return TableSectionController()
        default:
            fatalError()
        }
    }

    public func emptyView(for listAdapter: ListAdapter) -> UIView? {
        return nil
    }
}

// MARK: - UISearchBarDelegate
extension SearchViewController: UISearchBarDelegate {
    public func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(true, animated: true)
    }

    public func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(false, animated: true)
    }

    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        collectionController.reload(animated: false)
    }

    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
    }

    public func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        floatingPanelDelegate?.closePanel(containing: self, model: nil)
    }
}
