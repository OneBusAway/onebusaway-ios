//
//  NearbyViewController.swift
//  OBANext
//
//  Created by Aaron Brethorst on 11/29/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit
import IGListKit
import FloatingPanel
import OBAKitCore

public protocol NearbyDelegate: NSObjectProtocol {
    func nearbyController(_ nearbyController: NearbyViewController, didSelectStop stop: Stop)
    func nearbyControllerDisplaySearch(_ nearbyController: NearbyViewController)
    func nearbyController(_ nearbyController: NearbyViewController, moveTo position: FloatingPanelPosition, animated: Bool)
}

/// This is the view controller that powers the drawer on the `MapViewController`.
public class NearbyViewController: VisualEffectViewController,
    ListAdapterDataSource,
    ListProvider,
    ModelViewModelConverters,
    SearchDelegate,
    RegionsServiceDelegate,
    UISearchBarDelegate {

    let mapRegionManager: MapRegionManager

    public weak var nearbyDelegate: NearbyDelegate?

    private let application: Application

    private var stops = [Stop]() {
        didSet {
            collectionController.reload(animated: false)
        }
    }

    // MARK: - Init/Deinit

    init(application: Application, mapRegionManager: MapRegionManager, delegate: NearbyDelegate) {
        self.application = application
        self.mapRegionManager = mapRegionManager
        self.nearbyDelegate = delegate

        super.init(nibName: nil, bundle: nil)

        self.mapRegionManager.addDelegate(self)

        self.application.regionsService.addDelegate(self)
    }

    deinit {
        mapRegionManager.removeDelegate(self)
        application.regionsService.removeDelegate(self)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UI

    private lazy var stackView = UIStackView.verticalStack(arangedSubviews: [searchBar, collectionController.view])

    public lazy var collectionController = CollectionController(application: application, dataSource: self)
    var scrollView: UIScrollView { collectionController.collectionView }

    // MARK: - UI/Search

    public private(set) var inSearchMode = false {
        didSet {
            if inSearchMode {
                nearbyDelegate?.nearbyControllerDisplaySearch(self)
            }
            else {
                nearbyDelegate?.nearbyController(self, moveTo: .tip, animated: true)
            }
            collectionController.reload(animated: false)
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

        prepareChildController(collectionController) {
            visualEffectView.contentView.addSubview(stackView)
            stackView.pinToSuperview(.edges, insets: NSDirectionalEdgeInsets(top: ThemeMetrics.floatingPanelTopInset, leading: 0, bottom: 0, trailing: 0))
        }
    }

    // MARK: - Search UI and Data

    private func updateSearchBarPlaceholderText() {
        if let region = application.regionsService.currentRegion {
            searchBar.placeholder = Formatters.searchPlaceholderText(region: region)
        }
    }

    func performSearch(request: SearchRequest) {
        searchBar.resignFirstResponder()
        nearbyDelegate?.nearbyController(self, moveTo: .half, animated: true)
        application.searchManager.search(request: request)
    }

    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        collectionController.reload(animated: false)
    }

    public func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        inSearchMode = true
        searchBar.showsCancelButton = true
    }

    public func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        exitSearchMode()
    }

    private func exitSearchMode() {
        searchBar.text = nil
        searchBar.resignFirstResponder()
        searchBar.showsCancelButton = false
        inSearchMode = false
    }

    public func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        inSearchMode = false
    }

    private lazy var searchModeEmptyView: EmptyDataSetView = {
        let emptyView = EmptyDataSetView(frame: view.bounds)
        emptyView.titleLabel.text = NSLocalizedString("search_controller.empty_set.title", value: "Search", comment: "Title for the empty set indicator on the Search controller.")
        emptyView.bodyLabel.text = NSLocalizedString("search_controller.empty_set.body", value: "Type in an address, route name, stop number, or vehicle here to search.", comment: "Body for the empty set indicator on the Search controller.")

        return emptyView
    }()

    private lazy var searchInteractor = SearchInteractor(userDataStore: application.userDataStore, delegate: self)

    // MARK: - ListAdapterDataSource (Data Loading)

    public func objects(for listAdapter: ListAdapter) -> [ListDiffable] {
        if inSearchMode {
            return searchInteractor.searchModeObjects(text: searchBar.text, listAdapter: listAdapter)
        }
        else {
            return nearbyModeObjects(for: listAdapter)
        }
    }

    private func nearbyModeObjects(for listAdapter: ListAdapter) -> [ListDiffable] {
        var sections: [ListDiffable] = []

        if stops.count > 0 {
            let section = tableSection(from: Array(stops.prefix(5))) { [weak self] vm in
                guard
                    let self = self,
                    let stop = vm.object as? Stop
                else { return }

                self.nearbyDelegate?.nearbyController(self, didSelectStop: stop)
            }
            sections.append(section)
        }

        return sections
    }

    public func listAdapter(_ listAdapter: ListAdapter, sectionControllerFor object: Any) -> ListSectionController {
        let sectionController = defaultSectionController(for: object)
        return sectionController
    }

    public func emptyView(for listAdapter: ListAdapter) -> UIView? {
        if inSearchMode {
            return searchModeEmptyView
        }
        else {
            return nil
        }
    }
}

// MARK: - MapRegionDelegate

extension NearbyViewController: MapRegionDelegate {

    public var bottomScrollInset: CGFloat {
        get {
            return collectionController.collectionView.contentInset.bottom
        }
        set {
            collectionController.collectionView.contentInset.bottom = newValue
        }
    }

    public func mapRegionManager(_ manager: MapRegionManager, showSearchResult response: SearchResponse) {
        // abxoxo
        exitSearchMode()
    }

    public func mapRegionManager(_ manager: MapRegionManager, stopsUpdated stops: [Stop]) {
        self.stops = stops
    }

    public func mapRegionManagerDataLoadingStarted(_ manager: MapRegionManager) {
//        surfaceView()?.showProgressBar()
    }

    public func mapRegionManagerDataLoadingFinished(_ manager: MapRegionManager) {
//        surfaceView()?.hideProgressBar()
    }

    // MARK: - RegionsServiceDelegate

    public func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        updateSearchBarPlaceholderText()
    }
}
