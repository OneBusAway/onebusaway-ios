//
//  RoutePickerViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
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

    private let viewModel: RoutePickerViewModel
    private var cancellables = Set<AnyCancellable>()

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

    // MARK: - Init

    init(application: Application, delegate: RoutePickerDelegate) {
        self.application = application
        self.delegate = delegate
        self.viewModel = RoutePickerViewModel(application: application)
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

        bindViewModel()
        Task { await viewModel.loadRoutes() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchController.searchBar.becomeFirstResponder()
    }

    // MARK: - View Model

    private func bindViewModel() {
        // `@Published` publishes in `willSet`; hop to main so the sink reads the post-update value.
        Publishers.CombineLatest3(
            viewModel.$filteredRoutes,
            viewModel.$didFinishLoading,
            viewModel.$loadError
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _ in
            self?.listView.applyData()
        }
        .store(in: &cancellables)
    }

    // MARK: - Actions

    @objc private func close() {
        dismiss(animated: true)
    }

    // MARK: - UISearchResultsUpdating

    func updateSearchResults(for searchController: UISearchController) {
        viewModel.updateSearch(searchController.searchBar.text ?? "")
    }

    // MARK: - OBAListViewDataSource

    func items(for listView: OBAListView) -> [OBAListViewSection] {
        if viewModel.loadError != nil { return [] }

        let rows: [AnyOBAListViewItem] = viewModel.filteredRoutes.map { route in
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

    func emptyData(for listView: OBAListView) -> OBAListView.EmptyData? {
        if let loadError = viewModel.loadError {
            return .standard(.init(
                alignment: .center,
                title: loadError.localizedDescription,
                body: nil
            ))
        }

        if !viewModel.didFinishLoading {
            return .standard(.init(
                alignment: .center,
                title: OBALoc(
                    "route_picker.loading",
                    value: "Loading routes…",
                    comment: "Loading message while fetching nearby routes."
                ),
                body: nil
            ))
        }

        if viewModel.allRoutes.isEmpty {
            return .standard(.init(
                alignment: .center,
                title: OBALoc(
                    "route_picker.no_routes",
                    value: "No routes found nearby.",
                    comment: "Message when no routes are found near the user's location."
                ),
                body: nil
            ))
        }

        return nil
    }

    // MARK: - Selection

    private func didSelectRoute(_ route: Route) {
        delegate?.routePicker(self, didSelectRoute: route)
    }
}
