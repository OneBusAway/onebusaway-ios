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
import MapKit

protocol MapPanelDelegate: NSObjectProtocol {
    func mapPanelController(_ controller: MapFloatingPanelController, didSelectStop stopID: Stop.ID)
    func mapPanelController(_ controller: MapFloatingPanelController, didSelectMapItem mapItem: MKMapItem)
    func mapPanelControllerDidChangeChildViewController(_ controller: MapFloatingPanelController)
    func mapPanelControllerDisplaySearch(_ controller: MapFloatingPanelController)
    func mapPanelController(_ controller: MapFloatingPanelController, moveTo state: FloatingPanelState, animated: Bool)
}

/// This is the view controller that powers the drawer on the `MapViewController`.
class MapFloatingPanelController: VisualEffectViewController,
    AgencyAlertsDelegate,
    AgencyAlertListViewConverters,
    AppContext,
    RegionsServiceDelegate,
    SearchDelegate,
    OBAListViewContextMenuDelegate,
    NearbyStopsListDataSource,
    NearbyStopsListDelegate,
    SearchListViewControllerDelegate,
    UISearchBarDelegate {

    let mapRegionManager: MapRegionManager

    public weak var mapPanelDelegate: MapPanelDelegate?
    public private(set) var currentScrollView: UIScrollView?

    public let application: Application

    // Nearby Stops
    private var nearbyStopsListViewController: NearbyStopsListViewController!
    var highSeverityAlerts: [AgencyAlert] {
        application.alertsStore.recentHighSeverityAlerts
    }

    private(set) var stops = [Stop]() {
        didSet {
            nearbyStopsListViewController.updateList()
        }
    }

    // Search
    private var searchListViewController: SearchListViewController!
    var searchBarText: String = ""

    // MARK: - Init/Deinit
    init(application: Application, mapRegionManager: MapRegionManager, delegate: MapPanelDelegate) {
        self.application = application
        self.mapRegionManager = mapRegionManager
        self.mapPanelDelegate = delegate

        super.init(nibName: nil, bundle: nil)

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

    /// Used to hide or show content when the floating panel disappears behind the tab bar on iOS 26.
    func didCollapse(_ collapsed: Bool) {
        childContentContainerView.isHidden = collapsed
        nearbyStopsListViewController.view.isHidden = collapsed
    }

    private var childContentContainerView: UIView!

    func toggleSearch(showingSearch: Bool) {
        let oldViewController: UIViewController = showingSearch ? nearbyStopsListViewController : searchListViewController
        let newViewController: UIViewController = showingSearch ? searchListViewController : nearbyStopsListViewController

        oldViewController.willMove(toParent: nil)
        oldViewController.view.removeFromSuperview()
        oldViewController.removeFromParent()

        newViewController.willMove(toParent: self)
        addChild(newViewController)
        childContentContainerView.addSubview(newViewController.view)
        newViewController.view.pinToSuperview(.edges)
        newViewController.didMove(toParent: self)

        // Update the current scroll view, so FloatingPanel can track the newly installed view.
        if let scrollableViewController = newViewController as? Scrollable {
            currentScrollView = scrollableViewController.scrollView
        } else {
            currentScrollView = nil
        }

        mapPanelDelegate?.mapPanelControllerDidChangeChildViewController(self)
    }

    // MARK: - UI/Search

    public private(set) var inSearchMode = false {
        didSet {
            if inSearchMode {
                application.analytics?.reportEvent(pageURL: "app://localhost/map", label: AnalyticsLabels.searchSelected, value: nil)
                mapPanelDelegate?.mapPanelControllerDisplaySearch(self)
            }
            else {
                mapPanelDelegate?.mapPanelController(self, moveTo: .tip, animated: true)
            }

            toggleSearch(showingSearch: inSearchMode)
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

        // Add search bar
        visualEffectView.contentView.addSubview(searchBar)
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: visualEffectView.contentView.safeAreaLayoutGuide.topAnchor, constant: ThemeMetrics.floatingPanelTopInset),
            searchBar.leadingAnchor.constraint(equalTo: visualEffectView.contentView.safeAreaLayoutGuide.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: visualEffectView.contentView.safeAreaLayoutGuide.trailingAnchor)
        ])

        // Add child content container view
        childContentContainerView = UIView.autolayoutNew()
        visualEffectView.contentView.addSubview(childContentContainerView)
        NSLayoutConstraint.activate([
            childContentContainerView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 0),
            childContentContainerView.leadingAnchor.constraint(equalTo: visualEffectView.contentView.leadingAnchor),
            childContentContainerView.trailingAnchor.constraint(equalTo: visualEffectView.contentView.trailingAnchor),
            childContentContainerView.bottomAnchor.constraint(equalTo: visualEffectView.contentView.bottomAnchor)
        ])

        // Initialize view controllers
        nearbyStopsListViewController = NearbyStopsListViewController()
        nearbyStopsListViewController.view.translatesAutoresizingMaskIntoConstraints = false
        nearbyStopsListViewController.dataSource = self
        nearbyStopsListViewController.delegate = self

        searchListViewController = SearchListViewController()
        searchListViewController.view.translatesAutoresizingMaskIntoConstraints = false
        searchListViewController.delegate = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        toggleSearch(showingSearch: false)
        updateSearchBarPlaceholderText()
    }

    // MARK: - Agency Alerts

    public func agencyAlertsUpdated() {
        nearbyStopsListViewController.updateList()
    }

    // MARK: - NearbyStopsListViewControllerDelegate methods
    func didSelect(stopID: Stop.ID) {
        mapPanelDelegate?.mapPanelController(self, didSelectStop: stopID)
    }

    func didSelect(agencyAlert: AgencyAlert) {
        self.application.viewRouter.navigateTo(alert: agencyAlert, from: self)
    }

    func previewViewController(for stopID: Stop.ID) -> UIViewController? {
        return StopViewController(application: application, stopID: stopID)
    }

    func commitPreviewViewController(_ viewController: UIViewController) {
        self.application.viewRouter.navigate(to: viewController, from: self, animated: false)
    }

    // MARK: - Search UI and Data

    private func updateSearchBarPlaceholderText() {
        guard let region = application.regionsService.currentRegion else {
            searchBar.placeholder = nil
            return
        }

        if application.features.tripPlanning == .running {
            searchBar.placeholder = OBALoc("map_floating_panel.where_are_you_going", value: "Where are you going?", comment: "Search bar placeholder on the map floating panel when the trip planner is enabled.")
        }
        else {
            searchBar.placeholder = Formatters.searchPlaceholderText(region: region)
        }
    }

    func performSearch(request: SearchRequest) {
        if let searchText = searchBar.text {
            application.analytics?.reportSearchQuery(searchText)
        }

        searchBar.resignFirstResponder()
        mapPanelDelegate?.mapPanelController(self, moveTo: .half, animated: true)

        Task {
            await application.searchManager.search(request: request)
        }
    }

    func showMapItem(_ mapItem: MKMapItem) {
        // Save to recent map items
        application.userDataStore.addRecentMapItem(mapItem)

        searchBar.resignFirstResponder()
        mapPanelDelegate?.mapPanelController(self, didSelectMapItem: mapItem)
    }

    func searchInteractor(_ searchInteractor: SearchInteractor, showStop stop: Stop) {
        mapPanelDelegate?.mapPanelController(self, didSelectStop: stop.id)
    }

    func searchInteractorNewResultsAvailable(_ searchInteractor: SearchInteractor) {
        searchListViewController.updateSearch()
    }

    func searchInteractorClearRecentSearches(_ searchInteractor: SearchInteractor) {
        let alertController = UIAlertController.deletionAlert(title: Strings.clearRecentSearchesConfirmation) { [weak self] _ in
            guard let self = self else { return }
            self.application.userDataStore.deleteAllRecentMapItems()
            self.searchListViewController.updateSearch()
        }

        present(alertController, animated: true, completion: nil)
    }

    var isVehicleSearchAvailable: Bool {
        application.features.obaco == .running
    }

    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        searchBarText = searchText
        searchListViewController.updateSearch()
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

    lazy var searchInteractor = SearchInteractor(application: application, delegate: self)

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
