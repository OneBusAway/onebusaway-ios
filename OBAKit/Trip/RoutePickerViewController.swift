//
//  RoutePickerViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

// MARK: - RoutePickerDelegate

/// Delegate informed when the user selects a route from the picker.
@MainActor
protocol RoutePickerDelegate: AnyObject {
    func routePicker(_ picker: RoutePickerViewController, didSelectRoute route: Route)
}

// MARK: - RoutePickerViewController

/// Modal route selection screen with an auto-focused search field and a list of nearby routes.
class RoutePickerViewController: UIViewController,
    AppContext,
    OBAListViewDataSource,
    UISearchResultsUpdating {

    let application: Application

    private weak var delegate: RoutePickerDelegate?

    private let listView = OBAListView()

    private lazy var searchController: UISearchController = {
        let sc = UISearchController(searchResultsController: nil)
        sc.searchResultsUpdater = self
        sc.obscuresBackgroundDuringPresentation = false
        sc.searchBar.placeholder = OBALoc(
            "route_picker.search_placeholder",
            value: "Search routes…",
            comment: "Placeholder text in the route search field."
        )
        return sc
    }()

    /// All routes available for selection, sorted alphabetically.
    private var allRoutes = [Route]()

    /// Routes matching the current search filter.
    private var filteredRoutes = [Route]()

    // MARK: - Init

    init(application: Application, delegate: RoutePickerDelegate) {
        self.application = application
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)

        title = OBALoc(
            "route_picker.title",
            value: "Select Your Route",
            comment: "Title for the route picker screen where the user selects their transit route."
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UIViewController Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = ThemeColors.shared.systemBackground

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: Strings.close,
            style: .plain,
            target: self,
            action: #selector(close)
        )

        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        listView.obaDataSource = self
        view.addSubview(listView)
        listView.pinToSuperview(.edges)

        loadRoutes()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchController.searchBar.becomeFirstResponder()
    }

    // MARK: - Actions

    @objc private func close() {
        dismiss(animated: true)
    }

    // MARK: - Data Loading

    private func loadRoutes() {
        // Primary: extract routes from stops already loaded by MapRegionManager (instant, no network call).
        let cachedStops = application.mapRegionManager.stops
        if !cachedStops.isEmpty {
            applyRoutes(from: cachedStops)
            return
        }

        // Fallback: fetch nearby stops from the API, then extract routes.
        guard
            let apiService = application.apiService,
            let location = application.locationService.currentLocation
        else {
            return
        }

        Task { [weak self] in
            do {
                let stops = try await apiService.getStops(coordinate: location.coordinate).list
                await MainActor.run {
                    self?.applyRoutes(from: stops)
                }
            } catch {
                if error is CancellationError { return }
                Logger.error("Failed to load routes for picker: \(error)")
            }
        }
    }

    /// Extracts unique routes from stops, sorts them, and refreshes the list.
    private func applyRoutes(from stops: [Stop]) {
        var seen = Set<RouteID>()
        var uniqueRoutes = [Route]()

        for stop in stops {
            for route in stop.routes where seen.insert(route.id).inserted {
                uniqueRoutes.append(route)
            }
        }

        allRoutes = uniqueRoutes.localizedCaseInsensitiveSort()
        filteredRoutes = allRoutes
        listView.applyData()
    }

    // MARK: - UISearchResultsUpdating

    func updateSearchResults(for searchController: UISearchController) {
        let searchText = searchController.searchBar.text ?? ""

        if searchText.isEmpty {
            filteredRoutes = allRoutes
        } else {
            let query = searchText.lowercased()
            filteredRoutes = allRoutes.filter { route in
                route.shortName.lowercased().contains(query)
                    || (route.longName?.lowercased().contains(query) ?? false)
            }
        }
        listView.applyData()
    }

    // MARK: - OBAListViewDataSource

    func items(for listView: OBAListView) -> [OBAListViewSection] {
        let rows: [AnyOBAListViewItem] = filteredRoutes.map { route in
            let subtitle = route.longName ?? route.agency.name
            return OBAListRowView.SubtitleViewModel(
                title: route.shortName,
                subtitle: subtitle,
                accessoryType: .disclosureIndicator
            ) { [weak self] _ in
                self?.didSelectRoute(route)
            }.typeErased
        }

        return [OBAListViewSection(id: "routes", contents: rows)]
    }

    // MARK: - Selection

    private func didSelectRoute(_ route: Route) {
        delegate?.routePicker(self, didSelectRoute: route)
    }
}
