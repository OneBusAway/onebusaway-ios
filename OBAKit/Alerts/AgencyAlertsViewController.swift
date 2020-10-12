//
//  AgencyAlertsViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore
import SafariServices

/// Displays `AgencyAlert` objects loaded from a Protobuf feed.
class AgencyAlertsViewController: UIViewController,
    AgencyAlertsDelegate,
    AppContext,
    OBAListViewCollapsibleSectionsDelegate,
    OBAListViewDataSource {

    // MARK: - Stores
    public let application: Application
    private let alertsStore: AgencyAlertsStore

    // MARK: - UI state
    let selectionFeedbackGenerator: UISelectionFeedbackGenerator? = UISelectionFeedbackGenerator()
    var collapsedSections: Set<String> = []

    // MARK: - UI elements
    var listView = OBAListView()
    var refreshControl = UIRefreshControl()

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

        refreshControl.addTarget(self, action: #selector(reloadServerData), for: .valueChanged)

        listView.obaDataSource = self
        listView.collapsibleSectionsDelegate = self
        listView.refreshControl = refreshControl
        view.addSubview(listView)
        listView.pinToSuperview(.edges)

        view.backgroundColor = ThemeColors.shared.systemBackground
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.reloadServerData()
    }

    // MARK: - Agency Alerts Delegate

    func agencyAlertsUpdated() {
        listView.applyData(animated: false)
        refreshControl.endRefreshing()
        navigationItem.rightBarButtonItem = nil
    }

    // MARK: - Data Loading

    @objc private func reloadServerData() {
        alertsStore.checkForUpdates()
        refreshControl.beginRefreshing()
        navigationItem.rightBarButtonItem = UIActivityIndicatorView.asNavigationItem()
    }

    // MARK: - List data

    func items(for listView: OBAListView) -> [OBAListViewSection] {
        return alertsStore.listViewSections(onSelectAction: { [weak self] alert in
            self?.presentAlert(alert)
        })
    }

    func didSelect(_ listView: OBAListView, item: AnyOBAListViewItem) {
        guard let agencyAlert = item.as(AgencyAlert.ListViewModel.self) else { return }
        self.presentAlert(agencyAlert)
    }

    func presentAlert(_ alert: AgencyAlert.ListViewModel) {
        if let url = alert.localizedURL {
            let safari = SFSafariViewController(url: url)
            application.viewRouter.present(safari, from: self, isModal: true)
        } else {
            let title = alert.title
            let body = alert.body
            AlertPresenter.showDismissableAlert(title: title, message: body, presentingController: self)
        }
    }
}
