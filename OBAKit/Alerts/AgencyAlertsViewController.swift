//
//  AgencyAlertsViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import IGListKit
import OBAKitCore

/// Displays `AgencyAlert` objects loaded from a Protobuf feed.
class AgencyAlertsViewController: UIViewController,
    AgencyAlertsDelegate,
    AgencyAlertListKitConverters,
    AppContext,
    ListAdapterDataSource,
    AgencyAlertsSectionControllerDelegate {
    public let application: Application
    private let alertsStore: AgencyAlertsStore

    var collapsedSections: [String] = []

    // MARK: - Init

    public init(application: Application) {
        self.application = application

        self.alertsStore = application.alertsStore

        super.init(nibName: nil, bundle: nil)

        self.alertsStore.addDelegate(self)

        title = OBALoc("agency_alerts_controller.title", value: "Alerts", comment: "The title of the Agency Alerts controller.")
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UIViewController

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = ThemeColors.shared.systemBackground
        addChildController(collectionController)
        collectionController.view.pinToSuperview(.edges)
        collectionController.collectionView.addSubview(refreshControl)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        collectionController.reload(animated: false)
    }

    // MARK: - Data and Collection Controller

    private lazy var collectionController = CollectionController(application: application, dataSource: self)

    private lazy var refreshControl: UIRefreshControl = {
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(reloadServerData), for: .valueChanged)
        return refresh
    }()

    // MARK: - Agency Alerts Delegate

    func agencyAlertsUpdated() {
        collectionController.reload(animated: false)
        refreshControl.endRefreshing()
        navigationItem.rightBarButtonItem = nil
    }

    // MARK: - Data Loading

    @objc private func reloadServerData() {
        alertsStore.checkForUpdates()
        refreshControl.beginRefreshing()
        navigationItem.rightBarButtonItem = UIActivityIndicatorView.asNavigationItem()
    }

    // MARK: - IGListKit

    func objects(for listAdapter: ListAdapter) -> [ListDiffable] {
        return tableSections(agencyAlerts: alertsStore.agencyAlerts, collapsedSections: collapsedSections)
    }

    func listAdapter(_ listAdapter: ListAdapter, sectionControllerFor object: Any) -> ListSectionController {
        let controller = defaultSectionController(for: object)

        if let agencyAlertsSectionController = controller as? AgencyAlertsSectionController {
            agencyAlertsSectionController.delegate = self
        }

        return controller
    }

    func emptyView(for listAdapter: ListAdapter) -> UIView? {
        return nil
    }

    // MARK: - AgencyAlertsSectionControllerDelegate methods

    func agencyAlertsSectionController(_ controller: AgencyAlertsSectionController, didSelectAlert alert: AgencyAlert) {
        self.presentAlert(alert)
    }

    func agencyAlertsSectionControllerDidTapHeader(_ controller: AgencyAlertsSectionController) {
        let agency = controller.sectionData!.agencyName
        if let index = collapsedSections.firstIndex(of: agency) {
            collapsedSections.remove(at: index)
        } else {
            collapsedSections.append(agency)
        }

        self.collectionController.reload(animated: true)
    }
}
