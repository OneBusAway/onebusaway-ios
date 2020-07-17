//
//  RouteStopsViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import MapKit
import Contacts
import SafariServices
import OBAKitCore
import IGListKit

class RouteStopsViewController: VisualEffectViewController,
    AppContext,
    ListAdapterDataSource,
    Scrollable {

    /// The OBA application object
    let application: Application

    lazy var titleView = FloatingPanelTitleView.autolayoutNew()

    var scrollView: UIScrollView { collectionController.collectionView }

    private let stopsForRoute: StopsForRoute

    public weak var delegate: ModalDelegate?

    init(application: Application, stopsForRoute: StopsForRoute, delegate: ModalDelegate?) {
        self.application = application
        self.stopsForRoute = stopsForRoute
        self.delegate = delegate

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func close() {
        delegate?.dismissModalController(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        titleView.titleLabel.text = stopsForRoute.route.shortName
        titleView.subtitleLabel.text = stopsForRoute.route.longName
        titleView.closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)

        prepareChildController(collectionController) {
            let stack = UIStackView.verticalStack(arrangedSubviews: [
                titleView, collectionController.view
            ])
            visualEffectView.contentView.addSubview(stack)
            stack.pinToSuperview(.edges)
        }
    }

    // MARK: - IGListKit

    func objects(for listAdapter: ListAdapter) -> [ListDiffable] {
        let rows = stopsForRoute.stops.map { stop -> TableRowData in
            return TableRowData(title: stop.name, subtitle: Formatters.adjectiveFormOfCardinalDirection(stop.direction) ?? "", accessoryType: .disclosureIndicator) { [weak self] _ in
                guard let self = self else { return }
                self.application.viewRouter.navigateTo(stop: stop, from: self)
            }
        }

        return [TableSectionData(rows: rows)]
    }

    func listAdapter(_ listAdapter: ListAdapter, sectionControllerFor object: Any) -> ListSectionController {
        return defaultSectionController(for: object)
    }

    func emptyView(for listAdapter: ListAdapter) -> UIView? {
        return nil
    }

    private lazy var collectionController: CollectionController = {
        let controller = CollectionController(application: application, dataSource: self)
        controller.collectionView.showsVerticalScrollIndicator = false
        controller.collectionView.backgroundColor = nil
        return controller
    }()
}
