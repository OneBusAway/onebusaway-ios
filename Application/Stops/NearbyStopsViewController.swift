//
//  NearbyStopsViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 7/7/19.
//

import UIKit
import IGListKit
import SVProgressHUD

class NearbyStopsViewController: OperationController<StopsModelOperation, [Stop]>, ModelViewModelConverters, ListAdapterDataSource {

    private let stop: Stop

    // MARK: - Init

    public init(stop: Stop, application: Application) {
        self.stop = stop

        super.init(application: application)

        title = NSLocalizedString("nearby_stops_controller.title", value: "Nearby Stops", comment: "The title of the Nearby Stops controller.")
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UIViewController

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = application.theme.colors.systemBackground
        addChildController(collectionController)
        collectionController.view.pinToSuperview(.edges)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        collectionController.reload(animated: false)
    }

    // MARK: - Operation Controller Overrides

    override func loadData() -> StopsModelOperation? {
        guard let modelService = application.restAPIModelService else { return nil }

        SVProgressHUD.show()

        let op = modelService.getStops(coordinate: stop.coordinate)
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
        collectionController.reload(animated: false)
    }

    // MARK: - Data and Collection Controller

    private lazy var collectionController = CollectionController(application: application, dataSource: self)

    // MARK: - ListAdapterDataSource

    public func objects(for listAdapter: ListAdapter) -> [ListDiffable] {
        guard let data = data, data.count > 0 else {
            return []
        }

        var directions = [Direction: [Stop]]()

        for stop in data {
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
            let section = tableSection(from: data, tapped: tapHandler, deleted: nil)
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
        emptyView.titleLabel.text = NSLocalizedString("nearby_stops_controller.empty_set.title", value: "No Nearby Stops", comment: "Title for the empty set indicator on the Nearby Stops controller.")
        emptyView.bodyLabel.text = NSLocalizedString("nearby_stops_controller.empty_set.body", value: "There are no other stops in the vicinity.", comment: "Body for the empty set indicator on the Nearby Stops controller.")

        return emptyView
    }

    private func createSectionController(for object: Any) -> ListSectionController {
        return defaultSectionController(for: object)
    }
}
