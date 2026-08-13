//
//  SearchResultsController.swift
//  OBANext
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import Combine
import OBAKitCore
import MapKit

public class SearchResultsController: UIViewController, AppContext, OBAListViewDataSource {
    var scrollView: UIScrollView { listView }

    private weak var delegate: ModalDelegate?

    let application: Application

    private let viewModel: SearchViewModel

    private let listView = OBAListView()
    private let titleView = StackedTitleView.autolayoutNew()
    private var cancellables = Set<AnyCancellable>()

    public init(searchResponse: SearchResponse, application: Application, delegate: ModalDelegate?) {
        self.viewModel = SearchViewModel(searchResponse: searchResponse, application: application)
        self.application = application
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)

        title = OBALoc("search_results_controller.title", value: "Search Results", comment: "The title of the Search Results controller.")
        titleView.titleLabel.text = title
        titleView.subtitleLabel.text = viewModel.subtitle

        listView.obaDataSource = self
        view.addSubview(listView)
        listView.pinToSuperview(.edges)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UIViewController Lifecycle

    override public func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.titleView = titleView
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: Strings.close, style: .plain, target: self, action: #selector(close))

        view.backgroundColor = ThemeColors.shared.systemBackground

        bindViewModel()
    }

    private func bindViewModel() {
        viewModel.$vehicleSearchResponse
            .compactMap { $0 }
            .sink { [weak self] response in
                guard let self else { return }
                self.application.mapRegionManager.searchResponse = response
                self.delegate?.dismissModalController(self)
            }
            .store(in: &cancellables)

        // Sink on the full optional (not `.compactMap`): an explicit reset to nil at the
        // start of `selectVehicle(...)` is a valid signal that the previous error is no
        // longer current. Filtering nils leaves a retry's alert state stale.
        viewModel.$vehicleError
            .sink { [weak self] error in
                guard let self, let error else { return }
                Task { await self.application.displayError(error) }
            }
            .store(in: &cancellables)
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        listView.applyData()
    }

    // MARK: - Actions

    @objc private func close() {
        delegate?.dismissModalController(self)
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
        return OBAListRowView.SubtitleViewModel(title: vehicleID, subtitle: agencyVehicle.agencyName, accessoryType: .none) { [weak self] _ in
            guard let self else { return }
            Task(priority: .userInitiated) { await self.viewModel.selectVehicle(vehicleID: vehicleID) }
        }.typeErased
    }

    private func listViewItem(for item: Any) -> AnyOBAListViewItem? {
        let tapHandler: VoidBlock = { [weak self] in
            guard let self else { return }
            self.application.mapRegionManager.searchResponse = self.viewModel.response(substituting: item)
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
        let rows = viewModel.results.compactMap { listViewItem(for: $0) }
        return [OBAListViewSection(id: "results", contents: rows)]
    }
}
