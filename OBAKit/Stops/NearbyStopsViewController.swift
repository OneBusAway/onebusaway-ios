//
//  NearbyStopsViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import Combine
import CoreLocation
import OBAKitCore

class NearbyStopsViewController: UIViewController,
    AppContext,
    OBAListViewDataSource,
    UISearchResultsUpdating {

    let application: Application
    private let viewModel: NearbyStopsViewModel

    private var searchFilter: String? {
        didSet {
            guard oldValue != searchFilter else { return }
            let animated = searchFilter != nil
            listView.applyData(animated: animated)
        }
    }

    private let listView = OBAListView()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    public init(coordinate: CLLocationCoordinate2D, application: Application) {
        self.application = application
        self.viewModel = NearbyStopsViewModel(coordinate: coordinate, application: application)

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
        bindViewModel()

        Task(priority: .userInitiated) {
            await viewModel.loadStops()
        }
    }

    private func bindViewModel() {
        viewModel.$isLoading
            .sink { [weak self] isLoading in
                if isLoading {
                    self?.startLoading()
                } else {
                    self?.finishLoading()
                }
            }
            .store(in: &cancellables)

        // `@Published` fires from `willSet`, so a synchronous sink would read the *old*
        // stored value via `items(for:)`. The main-queue hop defers the closure until
        // after the property write completes. Apply directly rather than routing through
        // `searchFilter`, whose `oldValue != searchFilter` guard would swallow the
        // refresh on first load when both are nil.
        viewModel.$stops
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.listView.applyData(animated: false)
            }
            .store(in: &cancellables)

        // Sink on the full optional (not `.compactMap`): an explicit reset to nil at the
        // start of `loadStops()` is a valid signal that the previous error is no longer
        // current. Filtering nils means a retry leaves the prior alert state stale.
        viewModel.$operationError
            .sink { [weak self] error in
                guard let self, let error else { return }
                Task { await self.application.displayError(error) }
            }
            .store(in: &cancellables)
    }

    func startLoading() {
        navigationItem.rightBarButtonItem = UIActivityIndicatorView.asNavigationItem()
    }

    func finishLoading() {
        navigationItem.rightBarButtonItem = nil
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
        let stops = viewModel.stops
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

        let tapHandler = { [unowned self] (vm: StopRowItem) in
            self.application.viewRouter.navigateTo(stopID: vm.stopID, from: self)
        }

        return directions.sorted(by: \.key).map { (direction, _) -> OBAListViewSection in
            let stops = directions[direction] ?? []
            let cells = stops.map { StopRowItem(withStop: $0, showDirectionInTitle: false, onSelect: tapHandler, onDelete: nil) }
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
