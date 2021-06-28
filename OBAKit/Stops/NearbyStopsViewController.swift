//
//  NearbyStopsViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import CoreLocation
import OBAKitCore

class NearbyStopsViewController: OperationController<DecodableOperation<RESTAPIResponse<[Stop]>>, [Stop]>,
    OBAListViewDataSource,
    UISearchResultsUpdating {

    private let coordinate: CLLocationCoordinate2D

    private var searchFilter: String? {
        didSet {
            guard oldValue != searchFilter else { return }
            let animated = searchFilter != nil
            listView.applyData(animated: animated)
        }
    }

    private let listView = OBAListView()

    // MARK: - Init

    public init(coordinate: CLLocationCoordinate2D, application: Application) {
        self.coordinate = coordinate

        super.init(application: application)

        title = OBALoc("nearby_stops_controller.title", value: "Nearby Stops", comment: "The title of the Nearby Stops controller.")
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UIViewController

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = ThemeColors.shared.systemBackground
        view.addSubview(listView)
        listView.pinToSuperview(.edges)
        listView.obaDataSource = self

        configureSearchController()
    }

    func startLoading() {
        navigationItem.rightBarButtonItem = UIActivityIndicatorView.asNavigationItem()
    }

    func finishLoading() {
        navigationItem.rightBarButtonItem = nil
    }

    // MARK: - Operation Controller Overrides
    override func loadData() -> DecodableOperation<RESTAPIResponse<[Stop]>>? {
        guard let apiService = application.restAPIService else { return nil }

        startLoading()
        let op = apiService.getStops(coordinate: coordinate)
        op.complete { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.finishLoading()
            }

            switch result {
            case .failure(let error):
                self.application.displayError(error)
            case .success(let response):
                self.data = response.list
            }
        }

        return op
    }

    override func updateUI() {
        searchFilter = nil
        listView.applyData()
    }

    // MARK: - Search
    private lazy var searchController = UISearchController(searchResultsController: nil)

    func updateSearchResults(for searchController: UISearchController) {
        searchFilter = searchController.searchBar.text
    }

    private func configureSearchController() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController
        definesPresentationContext = true
    }

    // MARK: - Data and Collection Controller
    func items(for listView: OBAListView) -> [OBAListViewSection] {
        guard let data = data, data.count > 0 else { return [] }

        let filter = String.nilifyBlankValue(searchFilter?.localizedLowercase.trimmingCharacters(in: .whitespacesAndNewlines)) ?? nil

        var directions: [Direction: [Stop]] = [:]

        for stop in data {
            if !stop.matchesQuery(filter) {
                continue
            }
            var list = directions[stop.direction, default: [Stop]()]
            list.append(stop)
            directions[stop.direction] = list
        }

        let tapHandler = { (vm: NearbyStopViewModel) -> Void in
            self.application.viewRouter.navigateTo(stopID: vm.id, from: self)
        }

        return directions.sorted(by: \.key).map { (direction, _) -> OBAListViewSection in
            let stops = directions[direction] ?? []
            let cells = stops.map { NearbyStopViewModel(stop: $0, onSelectAction: tapHandler) }
            let header = Formatters.adjectiveFormOfCardinalDirection(direction) ?? ""
            return OBAListViewSection(id: "\(direction.rawValue)", title: header, contents: cells)
        }
    }

    func emptyData(for listView: OBAListView) -> OBAListView.EmptyData? {
        let title = OBALoc("nearby_stops_controller.empty_set.title", value: "No Nearby Stops", comment: "Title for the empty set indicator on the Nearby Stops controller.")
        let body = OBALoc("nearby_stops_controller.empty_set.body", value: "There are no other stops in the vicinity.", comment: "Body for the empty set indicator on the Nearby Stops controller.")

        return .standard(.init(title: title, body: body))
    }
}

struct NearbyStopViewModel: OBAListViewItem {
    let id: String
    let title: String
    let subtitle: String?

    let onSelectAction: OBAListViewAction<NearbyStopViewModel>?

    var configuration: OBAListViewItemConfiguration {
        return .custom(OBAListRowConfiguration(text: .string(title), secondaryText: .string(subtitle), appearance: .subtitle, accessoryType: .disclosureIndicator))
    }

    init(stop: Stop, onSelectAction: @escaping OBAListViewAction<NearbyStopViewModel>) {
        self.onSelectAction = onSelectAction

        self.id = stop.id
        self.title = Formatters.formattedTitle(stop: stop)
        self.subtitle = Formatters.formattedRoutes(stop.routes)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(subtitle)
    }

    static func == (lhs: NearbyStopViewModel, rhs: NearbyStopViewModel) -> Bool {
        return lhs.title == rhs.title && lhs.subtitle == rhs.subtitle
    }
}
