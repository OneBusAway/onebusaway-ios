//
//  NearbyStopsViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 7/7/19.
//

import UIKit
import IGListKit
import SVProgressHUD
import CoreLocation
import OBAKitCore

class NearbyStopsViewController: OperationController<StopsModelOperation, [Stop]>, ListKitStopConverters, ListAdapterDataSource, UISearchResultsUpdating {

    private let coordinate: CLLocationCoordinate2D

    private var searchFilter: String? {
        didSet {
            guard oldValue != searchFilter else { return }
            let animated = searchFilter != nil
            collectionController.reload(animated: animated)
        }
    }

    // MARK: - Init

    public init(coordinate: CLLocationCoordinate2D, application: Application) {
        self.coordinate = coordinate

        super.init(application: application)

        title = OBALoc("nearby_stops_controller.title", value: "Nearby Stops", comment: "The title of the Nearby Stops controller.")
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UIViewController

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = ThemeColors.shared.systemBackground
        addChildController(collectionController)
        collectionController.view.pinToSuperview(.edges)

        configureSearchController()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        collectionController.reload(animated: false)
    }

    // MARK: - Operation Controller Overrides

    override func loadData() -> StopsModelOperation? {
        guard let modelService = application.restAPIModelService else { return nil }

        SVProgressHUD.show()

        let op = modelService.getStops(coordinate: coordinate)
        op.then { [weak self] in
            guard let self = self else {
                SVProgressHUD.dismiss()
                return
            }
            self.data = op.stops
            SVProgressHUD.dismiss()
        }

        return op
    }

    override func updateUI() {
        searchFilter = nil
        collectionController.reload(animated: false)
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

    private lazy var collectionController = CollectionController(application: application, dataSource: self)

    // MARK: - ListAdapterDataSource

    public func objects(for listAdapter: ListAdapter) -> [ListDiffable] {
        guard let data = data, data.count > 0 else {
            return []
        }

        let filter = ModelHelpers.nilifyBlankValue(searchFilter?.localizedLowercase.trimmingCharacters(in: .whitespacesAndNewlines)) ?? nil

        var directions = [Direction: [Stop]]()

        for stop in data {
            if !stop.matchesQuery(filter) {
                continue
            }
            var list = directions[stop.direction, default: [Stop]()]
            list.append(stop)
            directions[stop.direction] = list
        }

        let tapHandler = { (vm: ListViewModel) -> Void in
            guard let stop = vm.object as? Stop else { return }
            self.application.viewRouter.navigateTo(stop: stop, from: self)
        }

        var sections: [ListDiffable] = []
        for dir in directions.keys {
            let stops = directions[dir] ?? []
            let section = tableSection(stops: stops, tapped: tapHandler, deleted: nil)
            section.title = Formatters.adjectiveFormOfCardinalDirection(dir)
            sections.append(section)
        }

        return sections
    }

    public func listAdapter(_ listAdapter: ListAdapter, sectionControllerFor object: Any) -> ListSectionController {
        let sectionController = createSectionController(for: object)
        sectionController.inset = .zero
        return sectionController
    }

    public func emptyView(for listAdapter: ListAdapter) -> UIView? {
        let emptyView = EmptyDataSetView(frame: view.bounds)
        emptyView.titleLabel.text = OBALoc("nearby_stops_controller.empty_set.title", value: "No Nearby Stops", comment: "Title for the empty set indicator on the Nearby Stops controller.")
        emptyView.bodyLabel.text = OBALoc("nearby_stops_controller.empty_set.body", value: "There are no other stops in the vicinity.", comment: "Body for the empty set indicator on the Nearby Stops controller.")

        return emptyView
    }

    private func createSectionController(for object: Any) -> ListSectionController {
        return defaultSectionController(for: object)
    }
}
