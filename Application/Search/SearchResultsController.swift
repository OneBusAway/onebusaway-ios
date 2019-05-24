//
//  SearchResultsController.swift
//  OBANext
//
//  Created by Aaron Brethorst on 1/23/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import UIKit
import IGListKit
import FloatingPanel

public protocol SearchResultsDelegate: NSObjectProtocol {
    func searchResults(controller: SearchResultsController?, showRoute route: Route)
    func searchResults(controller: SearchResultsController?, showMapItem mapItem: MKMapItem)
    func searchResults(controller: SearchResultsController?, showStop stop: Stop)
    func searchResults(controller: SearchResultsController?, showVehicleStatus vehicleStatus: VehicleStatus)
}

public class SearchResultsController: VisualEffectViewController, ListProvider {
    private let titleBar = FloatingPanelTitleView.autolayoutNew()
    public lazy var collectionController = CollectionController(application: application, dataSource: self)

    private lazy var stackView: UIStackView = {
        let stack = UIStackView.verticalStack(arangedSubviews: [titleBar, collectionController.view])
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = application.theme.metrics.collectionViewLayoutMargins

        return stack
    }()

    private let application: Application
    public weak var floatingPanelDelegate: FloatingPanelContainer?
    public weak var delegate: SearchResultsDelegate?

    private let searchResponse: SearchResponse

    public init(searchResponse: SearchResponse, application: Application, floatingPanelDelegate: FloatingPanelContainer, delegate: SearchResultsDelegate) {
        self.searchResponse = searchResponse
        self.application = application
        self.floatingPanelDelegate = floatingPanelDelegate
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UIViewController Lifecycle

    override public func viewDidLoad() {
        super.viewDidLoad()

        prepareChildController(collectionController) {
            visualEffectView.contentView.addSubview(stackView)
            stackView.pinToSuperview(.edges, insets: FloatingPanelSurfaceView.searchBarEdgeInsets)
        }

        // Configure title bar
        titleBar.closeButton.addTarget(self, action: #selector(closePanel), for: .touchUpInside)
        titleBar.titleLabel.text = NSLocalizedString("search_results_controller.title", value: "Search Results", comment: "The title of the Search Results controller.")
        titleBar.subtitleLabel.text = subtitleText(from: searchResponse)
    }

    // MARK: - Actions

    @objc private func closePanel() {
        floatingPanelDelegate?.closePanel(containing: self, model: nil)
    }

    /// Used in conjunction with the `search` and `delegate` to sidestep displaying
    /// the search results UI when an unambiguous search response has been retrieved.
    ///
    /// - Parameters:
    ///   - search: The search response.
    ///   - delegate: The delegate capable of displaying results.
    public class func presentResult(from search: SearchResponse, delegate: SearchResultsDelegate) {
        switch search.request.searchType {
        case .address:
            delegate.searchResults(controller: nil, showMapItem: search.results.first as! MKMapItem)
        case .route:
            delegate.searchResults(controller: nil, showRoute: search.results.first as! Route)
        case .stopNumber:
            delegate.searchResults(controller: nil, showStop: search.results.first as! Stop)
        case .vehicleID:
            delegate.searchResults(controller: nil, showVehicleStatus: search.results.first as! VehicleStatus)
        }
    }

    // MARK: - Private

    private func subtitleText(from response: SearchResponse) -> String {
        let subtitleFormat: String
        switch searchResponse.request.searchType {
        case .address:
            subtitleFormat = NSLocalizedString("search_results_controller.subtitle.address_fmt", value: "%@", comment: "A format string for address searches. In English, this is just the address itself without any adornment.")
        case .route:
            subtitleFormat = NSLocalizedString("search_results_controller.subtitle.route_fmt", value: "Route %@", comment: "A format string for address searches. e.g. in english: Route search: \"{SEARCH TEXT}\"")
        case .stopNumber:
            subtitleFormat = NSLocalizedString("search_results_controller.subtitle.stop_number_fmt", value: "Stop number %@", comment: "A format string for stop number searches. e.g. in english: Stop number: \"{SEARCH TEXT}\"")
        case .vehicleID:
            subtitleFormat = NSLocalizedString("search_results_controller.subtitle.vehicle_id_fmt", value: "Vehicle ID %@", comment: "A format string for stop number searches. e.g. in english: Stop number: \"{SEARCH TEXT}\"")
        }
        return String(format: subtitleFormat, searchResponse.request.query)
    }
}

extension SearchResultsController: ListAdapterDataSource {
    public func objects(for listAdapter: ListAdapter) -> [ListDiffable] {

        let rows: [TableRowData]

        switch searchResponse.request.searchType {
        case .address:
            let data = searchResponse.results as! [MKMapItem]
            rows = data.map { item in
                return TableRowData(title: item.name ?? "???", accessoryType: .none) { [weak self] _ in
                    guard let self = self else { return }
                    self.delegate?.searchResults(controller: self, showMapItem: item)
                }
            }
        case .route:
            let data = searchResponse.results as! [Route]
            rows = data.map { route in
                return TableRowData(title: route.shortName, subtitle: route.agency.name, accessoryType: .none) { [weak self] _ in
                    guard let self = self else { return }
                    self.delegate?.searchResults(controller: self, showRoute: route)
                }
            }
        case .stopNumber:
            let data = searchResponse.results as! [Stop]
            rows = data.map { stop in
                return TableRowData(title: stop.name, accessoryType: .none) { [weak self] _ in
                    guard let self = self else { return }
                    self.delegate?.searchResults(controller: self, showStop: stop)
                }
            }
        case .vehicleID:
            let data = searchResponse.results as! [VehicleStatus]
            rows = data.map { status in
                return TableRowData(title: status.vehicleID, accessoryType: .none) { [weak self] _ in
                    guard let self = self else { return }
                    self.delegate?.searchResults(controller: self, showVehicleStatus: status)
                }
            }
        }

        let tableSection = TableSectionData(title: nil, rows: rows)
        return [tableSection]
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
