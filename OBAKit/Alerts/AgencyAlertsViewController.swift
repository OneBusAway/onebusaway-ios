//
//  AgencyAlertsViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 8/14/19.
//

import UIKit
import IGListKit
import OBAKitCore

/// Displays `AgencyAlert` objects loaded from a Protobuf feed.
class AgencyAlertsViewController: UIViewController,
    AgencyAlertsDelegate,
    AgencyAlertListKitConverters,
    AppContext,
    ListAdapterDataSource {
    public let application: Application
    private let alertsStore: AgencyAlertsStore

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
    }

    // MARK: - Data Loading

    @objc private func reloadServerData() {
        alertsStore.checkForUpdates()
        refreshControl.beginRefreshing()
    }

    // MARK: - IGListKit

    func objects(for listAdapter: ListAdapter) -> [ListDiffable] {
        return tableSections(agencyAlerts: alertsStore.agencyAlerts) { [weak self] model in
            guard
                let self = self,
                let alert = model.object as? AgencyAlert
            else { return }

            self.presentAlert(alert)
        }
    }

    func listAdapter(_ listAdapter: ListAdapter, sectionControllerFor object: Any) -> ListSectionController {
        return defaultSectionController(for: object)
    }

    func emptyView(for listAdapter: ListAdapter) -> UIView? {
        return nil
    }
}
