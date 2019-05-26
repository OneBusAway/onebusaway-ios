//
//  RecentStopsViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/20/19.
//

import UIKit
import IGListKit

/// Provides an interface to browse recently-viewed information, mostly `Stop`s.
@objc(OBARecentStopsViewController) public class RecentStopsViewController: UIViewController {

    let application: Application

    public init(application: Application) {
        self.application = application

        super.init(nibName: nil, bundle: nil)

        title = NSLocalizedString("recent_stops_controller.title", value: "Recent Stops", comment: "The title of the Recent Stops controller.")
        tabBarItem.image = Icons.recentTabIcon
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UIViewController

    public override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .white
        addChildController(collectionController)
        collectionController.view.pinToSuperview(.edges)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // abxoxo - todo reload data.
    }

    // MARK: - Data and Collection Controller

    private lazy var collectionController = CollectionController(application: application, dataSource: self)
}

extension RecentStopsViewController: ListAdapterDataSource {
    public func objects(for listAdapter: ListAdapter) -> [ListDiffable] {
        var sections: [ListDiffable] = []

        let stops = application.userDataStore.recentStops

        if stops.count > 0 {
            let stopViewModels: [StopViewModel] = Array(stops).map {
                StopViewModel(stop: $0) { vm in
                    guard let viewModel = vm as? StopViewModel else { return }
                    let stopController = StopViewController(application: self.application, stopID: viewModel.stopID, delegate: nil)
                    self.application.viewRouter.navigateTo(viewController: stopController, from: self)
                }
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
