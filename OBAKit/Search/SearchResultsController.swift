//
//  SearchResultsController.swift
//  OBANext
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore
import MapKit

public class SearchResultsController: UIViewController, AppContext, OBAListViewDataSource {
    var scrollView: UIScrollView { listView }

    private weak var delegate: ModalDelegate?

    let application: Application

    private let searchResponse: SearchResponse

    private let listView = OBAListView()
    private let titleView = StackedTitleView.autolayoutNew()

    public init(searchResponse: SearchResponse, application: Application, delegate: ModalDelegate?) {
        self.searchResponse = searchResponse
        self.application = application
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)

        title = OBALoc("search_results_controller.title", value: "Search Results", comment: "The title of the Search Results controller.")
        titleView.titleLabel.text = title
        titleView.subtitleLabel.text = subtitleText(from: searchResponse)

        listView.obaDataSource = self
        listView.pinToSuperview(.edges)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UIViewController Lifecycle
    public override func loadView() {
        super.loadView()
        self.view = listView
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.titleView = titleView
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: Strings.close, style: .plain, target: self, action: #selector(close))

        view.backgroundColor = ThemeColors.shared.systemBackground
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        listView.applyData()
    }

    // MARK: - Actions

    @objc private func close() {
        delegate?.dismissModalController(self)
    }

    // MARK: - Private

    private func subtitleText(from response: SearchResponse) -> String {
        let subtitleFormat: String
        switch searchResponse.request.searchType {
        case .address:
            subtitleFormat = OBALoc("search_results_controller.subtitle.address_fmt", value: "%@", comment: "A format string for address searches. In English, this is just the address itself without any adornment.")
        case .route:
            subtitleFormat = OBALoc("search_results_controller.subtitle.route_fmt", value: "Route %@", comment: "A format string for route searches. e.g. in english: Route \"{SEARCH TEXT}\"")
        case .stopNumber:
            subtitleFormat = OBALoc("search_results_controller.subtitle.stop_number_fmt", value: "Stop number %@", comment: "A format string for stop number searches. e.g. in english: Stop number \"{SEARCH TEXT}\"")
        case .vehicleID:
            subtitleFormat = OBALoc("search_results_controller.subtitle.vehicle_id_fmt", value: "Vehicle ID %@", comment: "A format string for vehicle ID searches. e.g. in english: Vehicle ID \"{SEARCH TEXT}\"")
        }
        return String(format: subtitleFormat, searchResponse.request.query)
    }

    // MARK: - Rows

    private func row(for mapItem: MKMapItem, tapHandler: VoidBlock?) -> AnyOBAListViewItem? {
        guard let name = mapItem.name else { return nil }
        return OBAListRowView.DefaultViewModel(title: name, accessoryType: .none) { _ in
            tapHandler?()
        }.typeErased
    }

    private func row(for route: Route, tapHandler: VoidBlock?) -> AnyOBAListViewItem? {
        return OBAListRowView.SubtitleViewModel(title: route.shortName, subtitle: route.agency.name, accessoryType: .none) { _ in
            tapHandler?()
        }.typeErased
    }

    private func row(for stop: Stop, tapHandler: VoidBlock?) -> AnyOBAListViewItem? {
        return OBAListRowView.DefaultViewModel(title: stop.name, accessoryType: .none) { _ in
            tapHandler?()
        }.typeErased
    }

    private func row(for agencyVehicle: AgencyVehicle) -> AnyOBAListViewItem? {
        guard let vehicleID = agencyVehicle.vehicleID, application.apiService != nil else { return nil }
        return OBAListRowView.SubtitleViewModel(title: vehicleID, subtitle: agencyVehicle.agencyName, accessoryType: .none) { _ in
            self.didSelectAgencyVehicle(vehicleID: vehicleID)
        }.typeErased
    }

    private func didSelectAgencyVehicle(vehicleID: String) {
        guard let apiService = application.apiService else { return }

        Task(priority: .userInitiated) {
            do {
                let vehicle = try await apiService.getVehicle(vehicleID: vehicleID).entry
                await MainActor.run {
                    let response = SearchResponse(response: self.searchResponse, substituteResult: vehicle)
                    self.application.mapRegionManager.searchResponse = response
                    self.delegate?.dismissModalController(self)
                }
            } catch {
                await self.application.displayError(error)
            }
        }
    }

    private func listViewItem(for item: Any) -> AnyOBAListViewItem? {
        let tapHandler: VoidBlock = {
            let mgr = self.application.mapRegionManager
            mgr.searchResponse = SearchResponse(response: self.searchResponse, substituteResult: item)
            self.delegate?.dismissModalController(self)
        }

        switch item {
        case let mapItem as MKMapItem:
            return row(for: mapItem, tapHandler: tapHandler)
        case let route as Route:
            return row(for: route, tapHandler: tapHandler)
        case let stop as Stop:
            return row(for: stop, tapHandler: tapHandler)
        case let vehicle as AgencyVehicle:
            return row(for: vehicle)
        default:
            return nil
        }
    }

    // MARK: - OBAListView
    public func items(for listView: OBAListView) -> [OBAListViewSection] {
        let rows = searchResponse.results.compactMap { listViewItem(for: $0) }
        return [OBAListViewSection(id: "results", contents: rows)]
    }
}
