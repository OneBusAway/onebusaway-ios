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
import TipKit
import SwiftUI

protocol MapPanelDelegate: NSObjectProtocol {
    func mapPanelController(_ controller: MapFloatingPanelController, didSelectStop stopID: Stop.ID)
    func mapPanelController(_ controller: MapFloatingPanelController, didSelectMapItem mapItem: MKMapItem)
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
    UIPopoverPresentationControllerDelegate,
    UISheetPresentationControllerDelegate {

    let mapRegionManager: MapRegionManager

    public weak var mapPanelDelegate: MapPanelDelegate?

    public let application: Application

    // Nearby Stops
    private var nearbyStopsListViewController: NearbyStopsListViewController!
    var highSeverityAlerts: [AgencyAlert] {
        application.alertsStore.recentHighSeverityAlerts
    }

    private var resetFudgeFactorWorkItem: DispatchWorkItem?

    private(set) var stops = [Stop]() {
        didSet {
            nearbyStopsListViewController.updateList()
        }
    }

    // Search
    private var searchListViewController: UIHostingController<SearchListView>!
    var searchBarText: String = ""

    // Search Sheet (SwiftUI)
    let searchSheetViewModel = MapSearchSheetViewModel()
    private var searchSheetHostingController: UIHostingController<MapSearchSheet>?

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
        resetFudgeFactorWorkItem?.cancel()
        mapRegionManager.removeDelegate(self)
        application.regionsService.removeDelegate(self)
        application.alertsStore.removeDelegate(self)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UI

    /// Used to hide or show content when the floating panel is collapsed to tip state.
    func didCollapse(_ collapsed: Bool) {
        childContentContainerView.isHidden = collapsed
        nearbyStopsListViewController.view.isHidden = collapsed
    }

    private var childContentContainerView: UIView!

    // MARK: - Search Sheet

    /// Converts the current SearchInteractor results into SwiftUI-renderable sections
    /// and pushes them onto the view model.
    private func refreshSearchSheetSections() {
        searchInteractor.searchModeObjects(text: searchBarText)
        let rawSections = searchInteractor.sections
        searchSheetViewModel.sections = rawSections.map { section in
            let rows = section.content.compactMap { row -> SearchResultRow? in
                let title: AttributedString
                if let attributed = row.attributedTitle {
                    title = (try? AttributedString(attributed, including: \.uiKit)) ?? AttributedString(attributed.string)
                } else {
                    title = AttributedString(row.title ?? "")
                }

                let image: UIImage?
                switch row.icon {
                case .system(let name): image = UIImage(systemName: name)
                case .uiImage(let img): image = img
                case nil:               image = nil
                }

                return SearchResultRow(
                    id: row.id,
                    title: title,
                    subtitle: row.subtitle,
                    image: image,
                    action: { [weak self] in
                        row.action?()
                        if case .clearRecents = row.kind { } else {
                            self?.exitSearchMode()
                        }
                    }
                )
            }
            return SearchResultSection(id: section.id.rawValue, title: section.title, rows: rows)
        }.filter { !$0.rows.isEmpty }
    }

    private func presentSearchSheet() {
        guard searchSheetHostingController == nil else { return }

        searchSheetViewModel.searchText = searchBarText
        searchSheetViewModel.sections = []

        searchSheetViewModel.onSearchTextChanged = { [weak self] text in
            guard let self else { return }
            self.searchBarText = text
            self.refreshSearchSheetSections()
        }
        searchSheetViewModel.onCancel = { [weak self] in
            self?.exitSearchMode()
        }

        // Populate immediately so recent searches show before the user types.
        refreshSearchSheetSections()

        let sheet = MapSearchSheet(viewModel: searchSheetViewModel)
        let hostingController = UIHostingController(rootView: sheet)
        hostingController.modalPresentationStyle = .pageSheet
        hostingController.view.backgroundColor = .clear

        if let sheetPresentation = hostingController.sheetPresentationController {
            // Small detent: just tall enough to show the search bar row (~100pt),
            // matching the Apple Maps "pill expands into sheet" behaviour.
            let searchBarDetent = UISheetPresentationController.Detent.custom(identifier: .init("searchBar")) { context in
                return 100
            }
            sheetPresentation.detents = [searchBarDetent, .medium(), .large()]
            sheetPresentation.selectedDetentIdentifier = .init("searchBar")
            sheetPresentation.prefersGrabberVisible = true
            sheetPresentation.prefersScrollingExpandsWhenScrolledToEdge = true
            sheetPresentation.largestUndimmedDetentIdentifier = .medium
            sheetPresentation.prefersEdgeAttachedInCompactHeight = true
            // Detect interactive swipe-to-dismiss so we can reset state.
            sheetPresentation.delegate = self
        }

        searchSheetHostingController = hostingController

        // Find the topmost presented VC that isn't already presenting something else,
        // so the search sheet always stacks correctly above the persistent bottom sheet
        // in mapsStyleMode without being blocked by it.
        let root = sequence(first: self as UIViewController, next: { $0.parent })
            .first(where: { $0.parent == nil }) ?? self
        var presenter: UIViewController = root
        while let next = presenter.presentedViewController, !next.isBeingDismissed {
            presenter = next
        }
        presenter.present(hostingController, animated: true)
    }

    private func dismissSearchSheet() {
        guard let hostingController = searchSheetHostingController else { return }
        hostingController.dismiss(animated: true)
        searchSheetHostingController = nil
    }

    // MARK: - UI/Search

    public private(set) var inSearchMode = false {
        didSet {
            if inSearchMode {
                application.analytics?.reportEvent(pageURL: "app://localhost/map", label: AnalyticsLabels.searchSelected, value: nil)
                presentSearchSheet()
            } else {
                dismissSearchSheet()
                mapPanelDelegate?.mapPanelController(self, moveTo: .tip, animated: true)
            }
        }
    }

    /// Programmatically enters search mode — used by MapsStyleRootController's search pill.
    public func enterSearchMode() {
        guard !inSearchMode else { return }
        inSearchMode = true
    }

    /// When `true`, the built-in search bar is hidden and the content list
    /// fills the full panel height. Set this when the host controller (e.g.
    /// `MapsStyleRootController`) provides its own search entry point.
    var hidesSearchBar: Bool = false

    private lazy var searchBar: UISearchBar = {
        let searchBar = UISearchBar.autolayoutNew()
        searchBar.searchBarStyle = .minimal
        searchBar.delegate = self
        return searchBar
    }()

    // MARK: - UIViewController

    public override func viewDidLoad() {
        super.viewDidLoad()

        // Add search bar — hidden when the host provides its own search UI.
        visualEffectView.contentView.addSubview(searchBar)
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.isHidden = hidesSearchBar

        // Add child content container view
        childContentContainerView = UIView.autolayoutNew()
        visualEffectView.contentView.addSubview(childContentContainerView)

        if hidesSearchBar {
            // Pin content directly to the top — no search bar above it.
            NSLayoutConstraint.activate([
                childContentContainerView.topAnchor.constraint(equalTo: visualEffectView.contentView.topAnchor),
                childContentContainerView.leadingAnchor.constraint(equalTo: visualEffectView.contentView.leadingAnchor),
                childContentContainerView.trailingAnchor.constraint(equalTo: visualEffectView.contentView.trailingAnchor),
                childContentContainerView.bottomAnchor.constraint(equalTo: visualEffectView.contentView.bottomAnchor)
            ])
        } else {
            NSLayoutConstraint.activate([
                searchBar.topAnchor.constraint(equalTo: visualEffectView.contentView.safeAreaLayoutGuide.topAnchor, constant: ThemeMetrics.floatingPanelTopInset),
                searchBar.leadingAnchor.constraint(equalTo: visualEffectView.contentView.safeAreaLayoutGuide.leadingAnchor),
                searchBar.trailingAnchor.constraint(equalTo: visualEffectView.contentView.safeAreaLayoutGuide.trailingAnchor),
                childContentContainerView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
                childContentContainerView.leadingAnchor.constraint(equalTo: visualEffectView.contentView.leadingAnchor),
                childContentContainerView.trailingAnchor.constraint(equalTo: visualEffectView.contentView.trailingAnchor),
                childContentContainerView.bottomAnchor.constraint(equalTo: visualEffectView.contentView.bottomAnchor)
            ])
        }

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
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
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
        // Dismiss the search sheet — results will be shown on the map.
        exitSearchMode()

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
            guard let self else { return }
            self.application.userDataStore.deleteAllRecentMapItems()
            self.refreshSearchSheetSections()
        }

        present(alertController, animated: true, completion: nil)
    }

    var isVehicleSearchAvailable: Bool {
        application.features.obaco == .running
    }

    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        searchBarText = searchText
        refreshSearchSheetSections()
    }

    public func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        inSearchMode = true
        // The sheet has its own Cancel button; hide the search bar's to avoid duplication.
        searchBar.showsCancelButton = false
    }

    /// Cancels searching and exits search mode
    public func exitSearchMode() {
        searchBar.text = nil
        searchBar.resignFirstResponder()
        searchBar.showsCancelButton = false
        inSearchMode = false
        searchSheetViewModel.searchText = ""
        searchSheetViewModel.onDismiss?()
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

// MARK: - UISheetPresentationControllerDelegate

extension MapFloatingPanelController {
    /// Called when the user swipe-dismisses the search sheet interactively.
    /// Resets search state so the sheet can be opened again.
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard presentationController.presentedViewController === searchSheetHostingController else { return }
        searchSheetHostingController = nil
        // Reset without triggering dismissSearchSheet (sheet is already gone).
        searchBar.text = nil
        searchBar.resignFirstResponder()
        searchBar.showsCancelButton = false
        inSearchMode = false
        searchSheetViewModel.searchText = ""
        searchSheetViewModel.onDismiss?()
    }
}
