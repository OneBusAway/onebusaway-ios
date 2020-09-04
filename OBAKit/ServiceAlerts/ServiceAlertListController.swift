//
//  ServiceAlertListController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore
import IGListKit

/// Displays a list of `ServiceAlert` objects.
final class ServiceAlertListController: UIViewController,
    AppContext,
    ListAdapterDataSource,
    Previewable,
    SectionDataBuilders {

    private let serviceAlerts: [ServiceAlert]

    public let application: Application

    init(application: Application, serviceAlerts: [ServiceAlert]) {
        self.application = application
        self.serviceAlerts = serviceAlerts
        super.init(nibName: nil, bundle: nil)

        title = Strings.serviceAlerts
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = ThemeColors.shared.systemBackground
        addChildController(collectionController)
        collectionController.view.pinToSuperview(.edges)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        collectionController.reload(animated: false)
    }

    // MARK: - Previewable

    func enterPreviewMode() {
        // nop.
    }

    func exitPreviewMode() {
        // nop.
    }

    // MARK: - Collection Controller

    private lazy var collectionController = CollectionController(application: application, dataSource: self)

    // MARK: - IGListKit

    public func objects(for listAdapter: ListAdapter) -> [ListDiffable] {
        return [sectionData(from: serviceAlerts, collapsedState: .alwaysExpanded)]
    }

    public func listAdapter(_ listAdapter: ListAdapter, sectionControllerFor object: Any) -> ListSectionController {
        return defaultSectionController(for: object)
    }

    func emptyView(for listAdapter: ListAdapter) -> UIView? {
        nil
    }
}
