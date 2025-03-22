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
    AgencyAlertListViewConverters,
    AppContext,
    OBAListViewCollapsibleSectionsDelegate,
    OBAListViewContextMenuDelegate,
    OBAListViewDataSource {

    // MARK: - Stores
    public let application: Application
    private let alertsStore: AgencyAlertsStore

    // MARK: - UI state
    let selectionFeedbackGenerator: UISelectionFeedbackGenerator? = UISelectionFeedbackGenerator()
    var collapsedSections: Set<String> = []

    // MARK: - UI elements
    let listView = OBAListView()
    let refreshControl = UIRefreshControl()

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
    public override func loadView() {
        super.loadView()
        self.view = listView
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()

        refreshControl.addTarget(self, action: #selector(reloadServerData), for: .valueChanged)

        listView.obaDataSource = self
        listView.collapsibleSectionsDelegate = self
        listView.contextMenuDelegate = self
        listView.refreshControl = refreshControl
        listView.pinToSuperview(.edges)

        view.backgroundColor = ThemeColors.shared.systemBackground

        reloadServerData()
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

    func contextMenu(_ listView: OBAListView, for item: AnyOBAListViewItem) -> OBAListViewMenuActions? {
        guard let alert = item.as(TransitAlertDataListViewModel.self) else { return nil }

        let preview: OBAListViewMenuActions.PreviewProvider = {
            return self.previewAlert(alert)
        }

        let performPreview: VoidBlock = {
            self.performPreviewActionAlert(alert)
        }

        let menuProvider: OBAListViewMenuActions.MenuProvider = { _ in
            return UIMenu(title: "", image: nil, identifier: nil, options: [], children: [self.shareAlertAction(alert)])
        }

        return OBAListViewMenuActions(previewProvider: preview, performPreviewAction: performPreview, contextMenuProvider: menuProvider)
    }

    // MARK: - Preview

    var previewingVC: (identifier: UUID, vc: UIViewController)?

    func previewAlert(_ alert: TransitAlertDataListViewModel) -> UIViewController? {
        let viewController: UIViewController
        if let url = alert.localizedURL {
            viewController = SFSafariViewController(url: url)
        } else {
            viewController = TransitAlertDetailViewController(alert.transitAlert)
        }

        self.previewingVC = (alert.id, viewController)
        return viewController
    }

    func performPreviewActionAlert(_ alert: TransitAlertDataListViewModel) {
        if let previewingVC = self.previewingVC, previewingVC.identifier == alert.id {
            if previewingVC.vc is TransitAlertDetailViewController {
                application.viewRouter.navigate(to: previewingVC.vc, from: self)
            } else {
                application.viewRouter.present(previewingVC.vc, from: self, isModal: true)
            }
        } else {
            presentAlert(alert)
        }
    }

    // MARK: - Menu actions
    /// Returns a UIAction that presents a `UIActivityViewController` for sharing the URL
    /// (or title and body, if no URL) of the provided alert.
    func shareAlertAction(_ alert: TransitAlertDataListViewModel) -> UIAction {
        let activityItems: [Any]
        if let url = alert.localizedURL {
            activityItems = [url]
        } else {
            activityItems = [alert.title, alert.body]
        }

        return UIAction(title: Strings.share, image: Icons.share) { [weak self] _ in
            let vc = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
            self?.present(vc, animated: true, completion: nil)
        }
    }

    // MARK: - List data

    func items(for listView: OBAListView) -> [OBAListViewSection] {
        return listSections(agencyAlerts: alertsStore.agencyAlerts)
    }

    func emptyData(for listView: OBAListView) -> OBAListView.EmptyData? {
        let regionName = application.currentRegion?.name
        return .standard(.init(title: Strings.emptyAlertTitle, body: regionName))
    }
}
