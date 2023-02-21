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

class NearbyStopsViewController: UIViewController,
    AppContext,
    OBAListViewDataSource,
    UISearchResultsUpdating {

    let application: Application
    private let coordinate: CLLocationCoordinate2D

    private var searchFilter: String? {
        didSet {
            guard oldValue != searchFilter else { return }
            let animated = searchFilter != nil
            listView.applyData(animated: animated)
        }
    }

    private let listView = OBAListView()
    private var stops: [Stop] = []

    // MARK: - Init

    public init(coordinate: CLLocationCoordinate2D, application: Application) {
        self.coordinate = coordinate
        self.application = application

        super.init(nibName: nil, bundle: nil)

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

        Task(priority: .userInitiated) {
            await loadStops()
        }
    }

    func startLoading() {
        navigationItem.rightBarButtonItem = UIActivityIndicatorView.asNavigationItem()
    }

    func finishLoading() {
        navigationItem.rightBarButtonItem = nil
    }

    func loadStops() async {
        guard let apiService = application.apiService else {
            return
        }

        await MainActor.run {
            self.startLoading()
        }

        defer {
            Task { @MainActor in
                self.finishLoading()
            }
        }

        try? await Task.sleep(nanoseconds: 3_000_000_000)
        do {
            let stops = try await apiService.getStops(coordinate: coordinate).list
            await MainActor.run {
                self.stops = stops
                self.searchFilter = nil
                self.listView.applyData()
            }
        } catch {
            // TODO: (ualch9) Show error inline instead of presenting an ugly error.
            self.application.displayError(error)
        }
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
        guard !stops.isEmpty else { return [] }

        let filter = String.nilifyBlankValue(searchFilter?.localizedLowercase.trimmingCharacters(in: .whitespacesAndNewlines)) ?? nil

        var directions: [Direction: [Stop]] = [:]

        for stop in stops {
            if !stop.matchesQuery(filter) {
                continue
            }
            var list = directions[stop.direction, default: [Stop]()]
            list.append(stop)
            directions[stop.direction] = list
        }

        let tapHandler = { [unowned self] (vm: StopViewModel) -> Void in
            self.application.viewRouter.navigateTo(stopID: vm.stopID, from: self)
        }

        return directions.sorted(by: \.key).map { (direction, _) -> OBAListViewSection in
            let stops = directions[direction] ?? []
            let cells = stops.map { StopViewModel(withStop: $0, showDirectionInTitle: false, onSelect: tapHandler, onDelete: nil) }
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
