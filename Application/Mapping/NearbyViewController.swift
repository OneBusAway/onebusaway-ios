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

@objc(OBANearbyDelegate)
public protocol NearbyDelegate {
    func nearbyController(_ nearbyController: NearbyViewController, didSelectStopID stopID: String)
    func nearbyControllerRequestFullScreen(_ nearbyController: NearbyViewController)
    func nearbyControllerRequestDefaultLayout(_ nearbyController: NearbyViewController)
}

@objc(OBANearbyViewController)
public class NearbyViewController: VisualEffectViewController, ListProvider {
    let mapRegionManager: MapRegionManager

    public weak var nearbyDelegate: (FloatingPanelContainer & NearbyDelegate)?

    private let application: Application

    private var stops = [Stop]() {
        didSet {
            collectionController.listAdapter.performUpdates(animated: false)
        }
    }

    // MARK: - Init/Deinit

    init(application: Application, mapRegionManager: MapRegionManager, delegate: FloatingPanelContainer & NearbyDelegate) {
        self.application = application
        self.mapRegionManager = mapRegionManager
        self.nearbyDelegate = delegate

        super.init(nibName: nil, bundle: nil)

        self.mapRegionManager.addDelegate(self)
    }

    deinit {
        mapRegionManager.removeDelegate(self)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UI

    private lazy var stackView = UIStackView.verticalStack(arangedSubviews: [searchBar, collectionController.view])

    public lazy var collectionController = CollectionController(application: application, dataSource: self)

    // MARK: - UI/Search
    
    private lazy var searchBar: UISearchBar = {
        let searchBar = TapPresenterSearchBar.autolayoutNew()
        searchBar.searchBarStyle = .minimal
        if let region = application.regionsService.currentRegion {
            searchBar.placeholder = SearchViewController.searchPlaceholderText(region: region)
        }
        searchBar.tapped = { [weak self] in
            guard let self = self else { return }
            self.nearbyDelegate?.presentFloatingPanel(contentController: self.searchController, scrollView: self.searchController.collectionController.collectionView, animated: true, position: .full)
        }
        return searchBar
    }()
    
    private lazy var searchController: SearchViewController = {
        let ctl = SearchViewController(application: application, floatingPanelDelegate: nearbyDelegate!)
        ctl.searchDelegate = self
        return ctl
    }()

    // MARK: - UIViewController

    public override func viewDidLoad() {
        super.viewDidLoad()
        prepareChildController(collectionController) {
            visualEffectView.contentView.addSubview(stackView)
            stackView.pinToSuperview(.edges, insets: FloatingPanelSurfaceView.searchBarEdgeInsets)
        }
    }
}

// MARK: - Search Delegate

extension NearbyViewController: SearchDelegate {
    public func searchController(_ searchController: SearchViewController, request: SearchRequest) {
        nearbyDelegate?.closePanel(containing: searchController, model: nil)
        application.searchManager.search(request: request)
    }
}

// MARK: - ListAdapterDataSource (Data Loading)

extension NearbyViewController: ListAdapterDataSource {
    public func objects(for listAdapter: ListAdapter) -> [ListDiffable] {
        var sections: [ListDiffable] = []

        // Nearby Stops

        if stops.count > 0 {
            let stopViewModels: [StopViewModel] = Array(stops.prefix(5)).map {
                return StopViewModel(stop: $0)
            }

            sections.append(contentsOf: stopViewModels)
        }

        return sections
    }

    public func listAdapter(_ listAdapter: ListAdapter, sectionControllerFor object: Any) -> ListSectionController {
        let sectionController = createSectionController(for: object)
        sectionController.inset = .zero
        return sectionController
    }

    public func emptyView(for listAdapter: ListAdapter) -> UIView? { return nil }

    private func createSectionController(for object: Any) -> ListSectionController {
        switch object {
        case is StopViewModel: return StopSectionController()
        default:
            fatalError()

            // handy utilities for debugging:
            //        default:
            //            return LabelSectionController()
            //        case is String: return LabelSectionController()
        }
    }
}

// MARK: - MapRegionDelegate

extension NearbyViewController: MapRegionDelegate, FloatingPanelContent {

    public var bottomScrollInset: CGFloat {
        get {
            return collectionController.collectionView.contentInset.bottom
        }
        set {
            collectionController.collectionView.contentInset.bottom = newValue
        }
    }

    public func mapRegionManager(_ manager: MapRegionManager, stopsUpdated stops: [Stop]) {
        self.stops = stops
    }

    public func mapRegionManagerDataLoadingStarted(_ manager: MapRegionManager) {
        surfaceView()?.showProgressBar()
    }

    public func mapRegionManagerDataLoadingFinished(_ manager: MapRegionManager) {
        surfaceView()?.hideProgressBar()
    }
}

// MARK: - Actions

extension NearbyViewController {
    public func selectedStopViewModel(_ stopViewModel: StopViewModel) {
        nearbyDelegate?.nearbyController(self, didSelectStopID: stopViewModel.stopID)
    }
}
