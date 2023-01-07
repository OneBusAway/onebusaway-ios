//
//  MapFloatingPanelController.swift
//  OBANext
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import FloatingPanel
import OBAKitCore

protocol MapPanelDelegate: NSObjectProtocol {
    func mapPanelController(_ controller: MapFloatingPanelController, didSelectStop stopID: Stop.ID)
    func mapPanelControllerDisplaySearch(_ controller: MapFloatingPanelController)
    func mapPanelController(_ controller: MapFloatingPanelController, moveTo position: FloatingPanelPosition, animated: Bool)
}

/// This is the view controller that powers the drawer on the `MapViewController`.
class MapFloatingPanelController: VisualEffectViewController,
    AgencyAlertsDelegate,
    AgencyAlertListViewConverters,
    AppContext,
    RegionsServiceDelegate,
    SearchDelegate,
    OBAListViewDataSource,
    OBAListViewContextMenuDelegate,
    UISearchBarDelegate {

    let mapRegionManager: MapRegionManager

    public weak var mapPanelDelegate: MapPanelDelegate?

    public let application: Application

    private var stops = [Stop]() {
        didSet {
            listView.applyData()
        }
    }

    // MARK: - Init/Deinit

    init(application: Application, mapRegionManager: MapRegionManager, delegate: MapPanelDelegate) {
        self.application = application
        self.mapRegionManager = mapRegionManager
        self.mapPanelDelegate = delegate

        super.init(nibName: nil, bundle: nil)

        self.listView.obaDataSource = self
        self.listView.contextMenuDelegate = self
        self.listView.backgroundColor = nil

        self.mapRegionManager.addDelegate(self)
        self.application.regionsService.addDelegate(self)
        self.application.alertsStore.addDelegate(self)
    }

    deinit {
        mapRegionManager.removeDelegate(self)
        application.regionsService.removeDelegate(self)
        application.alertsStore.removeDelegate(self)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UI
    let listView = OBAListView()
    private lazy var stackView = UIStackView.verticalStack(arrangedSubviews: [searchBar, listView])

    // MARK: - UI/Search

    public private(set) var inSearchMode = false {
        didSet {
            if inSearchMode {
                application.analytics?.reportEvent?(.userAction, label: AnalyticsLabels.searchSelected, value: nil)
                mapPanelDelegate?.mapPanelControllerDisplaySearch(self)
            }
            else {
                mapPanelDelegate?.mapPanelController(self, moveTo: .tip, animated: true)
            }
            listView.applyData()
        }
    }

    private lazy var searchBar: UISearchBar = {
        let searchBar = UISearchBar.autolayoutNew()
        searchBar.searchBarStyle = .minimal
        searchBar.delegate = self
        return searchBar
    }()

    // MARK: - UIViewController

    public override func viewDidLoad() {
        super.viewDidLoad()

        updateSearchBarPlaceholderText()

        visualEffectView.contentView.addSubview(stackView)
        stackView.pinToSuperview(.edges, insets: NSDirectionalEdgeInsets(top: ThemeMetrics.floatingPanelTopInset, leading: 0, bottom: 0, trailing: 0))
    }

    // MARK: - Agency Alerts

    public func agencyAlertsUpdated() {
        listView.applyData()
    }

    // MARK: - Search UI and Data

    private func updateSearchBarPlaceholderText() {
        if let region = application.regionsService.currentRegion {
            searchBar.placeholder = Formatters.searchPlaceholderText(region: region)
        }
    }

    func performSearch(request: SearchRequest) {
        if let searchText = searchBar.text {
            application.analytics?.reportSearchQuery?(searchText)
        }

        searchBar.resignFirstResponder()
        mapPanelDelegate?.mapPanelController(self, moveTo: .half, animated: true)
        application.searchManager.search(request: request)
    }

    func searchInteractor(_ searchInteractor: SearchInteractor, showStop stop: Stop) {
        mapPanelDelegate?.mapPanelController(self, didSelectStop: stop.id)
    }

    var isVehicleSearchAvailable: Bool {
        application.features.obaco == .running
    }

    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        listView.applyData()
    }

    public func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        inSearchMode = true
        searchBar.showsCancelButton = true
    }

    public func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        exitSearchMode()
    }

    /// Cancels searching and exits search mode
    public func exitSearchMode() {
        searchBar.text = nil
        searchBar.resignFirstResponder()
        searchBar.showsCancelButton = false
        inSearchMode = false
    }

    public func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        inSearchMode = false
    }

    var searchModeEmptyData: OBAListView.EmptyData {
        let image = UIImage(systemName: "magnifyingglass")
        let title = OBALoc("search_controller.empty_set.title", value: "Search", comment: "Title for the empty set indicator on the Search controller.")
        let body = OBALoc("search_controller.empty_set.body", value: "Type in an address, route name, stop number, or vehicle here to search.", comment: "Body for the empty set indicator on the Search controller.")

        return .standard(.init(alignment: .top, title: title, body: body, image: image))
    }

    private lazy var searchInteractor = SearchInteractor(userDataStore: application.userDataStore, delegate: self)

    // MARK: - OBAListViewDataSource (Data Loading)
    func items(for listView: OBAListView) -> [OBAListViewSection] {
        var sections: [OBAListViewSection]
        if inSearchMode {
            sections = searchInteractor.searchModeObjects(text: searchBar.text)
        } else {
            sections = nearbyModeObjects()
        }

        for idx in sections.indices {
            sections[idx].configuration.backgroundColor = .clear
        }
        return sections
    }

    // MARK: - Nearby Mode

    var nearbyModeEmptyData: OBAListView.EmptyData {
        let title = OBALoc("nearby_controller.empty_set.title", value: "No Nearby Stops", comment: "Title for the empty set indicator on the Nearby controller")
        let body = OBALoc("nearby_controller.empty_set.body", value: "Zoom out or pan around to find some stops.", comment: "Body for the empty set indicator on the Nearby controller.")

        return .standard(.init(alignment: .top, title: title, body: body))
    }

    private func nearbyModeObjects() -> [OBAListViewSection] {
        var sections: [OBAListViewSection] = []

        let highSeverityAlerts = application.alertsStore.recentHighSeverityAlerts
        if highSeverityAlerts.count > 0 {
            sections.append(contentsOf: listSections(agencyAlerts: highSeverityAlerts))
        }

        if stops.count > 0 {
            let rows = stops.map { stop -> StopViewModel in
                let onSelect: OBAListViewAction<StopViewModel> = { [unowned self] viewModel in
                    self.mapPanelDelegate?.mapPanelController(self, didSelectStop: viewModel.stopID)
                }

                return StopViewModel(withStop: stop, onSelect: onSelect, onDelete: nil)
            }

            let section = OBAListViewSection(id: "nearby_stops", title: OBALoc("nearby_stops_controller.title", value: "Nearby Stops", comment: "The title of the Nearby Stops controller."), contents: rows)
            sections.append(section)
        }

        return sections
    }

    public func emptyData(for listView: OBAListView) -> OBAListView.EmptyData? {
        if inSearchMode {
            return searchModeEmptyData
        } else {
            return nearbyModeEmptyData
        }
    }

    fileprivate var currentPreviewingViewController: UIViewController?
    func contextMenu(_ listView: OBAListView, for item: AnyOBAListViewItem) -> OBAListViewMenuActions? {
        guard let stopViewModel = item.as(StopViewModel.self) else { return nil }

        let previewProvider: OBAListViewMenuActions.PreviewProvider = { [unowned self] () -> UIViewController? in
            let stopVC = StopViewController(application: self.application, stopID: stopViewModel.stopID)
            self.currentPreviewingViewController = stopVC
            return stopVC
        }

        let commitPreviewAction: VoidBlock = { [unowned self] in
            guard let vc = self.currentPreviewingViewController else { return }
            (vc as? Previewable)?.exitPreviewMode()
            self.application.viewRouter.navigate(to: vc, from: self)
        }

        return OBAListViewMenuActions(previewProvider: previewProvider, performPreviewAction: commitPreviewAction, contextMenuProvider: nil)
    }
}

// MARK: - MapRegionDelegate

extension MapFloatingPanelController: MapRegionDelegate {
    public var bottomScrollInset: CGFloat {
        get {
            return listView.contentInset.bottom
        }
        set {
            listView.contentInset.bottom = newValue
        }
    }

    public func mapRegionManager(_ manager: MapRegionManager, showSearchResult response: SearchResponse) {
        exitSearchMode()
    }

    public func mapRegionManager(_ manager: MapRegionManager, stopsUpdated stops: [Stop]) {
        self.stops = stops
    }

    // MARK: - RegionsServiceDelegate

    public func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        updateSearchBarPlaceholderText()
    }
}
