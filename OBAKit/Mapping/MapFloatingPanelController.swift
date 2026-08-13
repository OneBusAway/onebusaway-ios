//
//  MapFloatingPanelController.swift
//  OBANext
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import Combine
import FloatingPanel
import OBAKitCore
import MapKit
import TipKit
import SwiftUI

protocol MapPanelDelegate: NSObjectProtocol {
    func mapPanelController(_ controller: MapFloatingPanelController, didSelectStop stopID: Stop.ID)
    func mapPanelController(_ controller: MapFloatingPanelController, didSelectMapItem mapItem: MKMapItem)
    func mapPanelControllerDidChangeChildViewController(_ controller: MapFloatingPanelController)
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
    UISearchBarDelegate,
    UIPopoverPresentationControllerDelegate {

    let mapRegionManager: MapRegionManager

    public weak var mapPanelDelegate: MapPanelDelegate?
    public private(set) var currentScrollView: UIScrollView?

    public let application: Application

    let viewModel: MapPanelViewModel
    private var cancellables = Set<AnyCancellable>()

    // Nearby Stops
    private var nearbyStopsListViewController: NearbyStopsListViewController!

    // NearbyStopsListDataSource — forwarded from ViewModel
    var highSeverityAlerts: [AgencyAlert] { viewModel.highSeverityAlerts }
    var stops: [Stop] { viewModel.nearbyStops }

    private var resetFudgeFactorWorkItem: DispatchWorkItem?

    // Search
    private var searchListViewController: UIHostingController<SearchListView>!
    var searchBarText: String = ""

    // MARK: - Init/Deinit
    init(application: Application, mapRegionManager: MapRegionManager, delegate: MapPanelDelegate) {
        self.application = application
        self.mapRegionManager = mapRegionManager
        self.mapPanelDelegate = delegate
        self.viewModel = MapPanelViewModel(application: application)

        super.init(nibName: nil, bundle: nil)

        self.mapRegionManager.addDelegate(self)
        self.application.regionsService.addDelegate(self)
        self.application.alertsStore.addDelegate(self)
    }

    // isolated: the body touches main-actor state (delegate lists).
    isolated deinit {
        resetFudgeFactorWorkItem?.cancel()
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
                viewModel.enterSearchMode()
            }
            else {
                viewModel.exitSearchMode()
                // Panel move to .tip is handled by viewModel.$requestedPanelDetent binding.
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

        nearbyStopsListViewController.onExpandSearchTapped = { [weak self] in
            guard let self else { return }

            self.resetFudgeFactorWorkItem?.cancel()

            self.mapRegionManager.preferredLoadDataRegionFudgeFactor = 3.0

            // Force a data reload by simulating a region change event.
            self.mapRegionManager.mapView(self.mapRegionManager.mapView, regionDidChangeAnimated: false)

            // Create a new work item to reset the value
            let workItem = DispatchWorkItem { [weak self] in
                // This ensures that the next time the user pans the map normally,
                // the app goes back to its standard, efficient search radius.
                self?.mapRegionManager.preferredLoadDataRegionFudgeFactor =
                    UIAccessibility.isVoiceOverRunning ? 1.5 : MapRegionManager.DefaultLoadDataRegionFudgeFactor
            }

            self.resetFudgeFactorWorkItem = workItem

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
        }

        let searchListView = UIHostingController(rootView: SearchListView(searchInteractor: searchInteractor))
        searchListViewController = searchListView
        searchListViewController.view.translatesAutoresizingMaskIntoConstraints = false
        searchListViewController.view.backgroundColor = .clear

        bindViewModel()
    }

    private func bindViewModel() {
        bindNearbyContent()
        bindPanelDetent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        toggleSearch(showingSearch: false)
        updateSearchBarPlaceholderText()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        tripPlannerTipPresenter.showIfNeeded(sourceItem: searchBar, sourceRect: searchBar.bounds) { [weak self] vc in
            guard let self else { return }
            self.present(vc, animated: animated)
        } presentedController: { [weak self] in
            guard let self else { return nil }
            return self.presentedViewController
        } dismiss: { vc in
            vc.dismiss(animated: animated)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        tripPlannerTipPresenter.stop()
    }

    // MARK: - Tips

    private let tripPlannerTipPresenter = TipPresenter(tip: TripPlannerTip())

    // MARK: - Agency Alerts

    public func agencyAlertsUpdated() {
        viewModel.refreshAlerts()
    }

    // MARK: - NearbyStopsListViewControllerDelegate methods
    func didSelect(stopID: Stop.ID) {
        mapPanelDelegate?.mapPanelController(self, didSelectStop: stopID)
    }

    func didSelect(agencyAlert: AgencyAlert) {
        self.application.viewRouter.navigateTo(alert: agencyAlert, from: self)
    }

    func previewViewController(for stopID: Stop.ID) -> UIViewController? {
        return application.viewRouter.makeStopController(stopID: stopID)
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

    func searchInteractorClearRecentSearches(_ searchInteractor: SearchInteractor) {
        let alertController = UIAlertController.deletionAlert(title: Strings.clearRecentSearchesConfirmation) { [weak self] _ in
            guard let self = self else { return }
            self.application.userDataStore.deleteAllRecentMapItems()
            self.searchInteractor.searchModeObjects(text: searchBarText)
        }

        present(alertController, animated: true, completion: nil)
    }

    var isVehicleSearchAvailable: Bool {
        application.features.obaco == .running
    }

    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        searchBarText = searchText
        searchInteractor.searchModeObjects(text: searchBarText)
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
        guard let stopViewModel = item.as(StopRowItem.self) else { return nil }

        let previewProvider: OBAListViewMenuActions.PreviewProvider = { [unowned self] () -> UIViewController? in
            let stopVC = self.application.viewRouter.makeStopController(stopID: stopViewModel.stopID)
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

// MARK: - ViewModel Binding

private extension MapFloatingPanelController {
    func bindNearbyContent() {
        viewModel.$nearbyStops
            .sink { [weak self] _ in self?.nearbyStopsListViewController.updateList() }
            .store(in: &cancellables)

        viewModel.$highSeverityAlerts
            .sink { [weak self] _ in self?.nearbyStopsListViewController.updateList() }
            .store(in: &cancellables)
    }

    func bindPanelDetent() {
        // EC11: map PanelDetent to FloatingPanel state so UIKit and future SwiftUI share the same source of truth.
        viewModel.$requestedPanelDetent
            .dropFirst()
            // Re-publishing the same detent shouldn't re-trigger a `move(to:)` animation.
            .removeDuplicates()
            .sink { [weak self] detent in
                guard let self else { return }
                let state: FloatingPanelState
                switch detent {
                case .tip:  state = .tip
                case .half: state = .half
                case .full: state = .full
                }
                mapPanelDelegate?.mapPanelController(self, moveTo: state, animated: true)
            }
            .store(in: &cancellables)
    }
}

// MARK: - MapRegionDelegate

extension MapFloatingPanelController: MapRegionDelegate {
    public func mapRegionManager(_ manager: MapRegionManager, showSearchResult response: SearchResponse) {
        exitSearchMode()
    }

    public func mapRegionManager(_ manager: MapRegionManager, stopsUpdated stops: [Stop]) {
        viewModel.updateNearbyStops(stops)
    }

    // MARK: - RegionsServiceDelegate

    public func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        updateSearchBarPlaceholderText()
    }
}
