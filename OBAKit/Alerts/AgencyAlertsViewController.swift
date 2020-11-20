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
    public override func viewDidLoad() {
        super.viewDidLoad()

        refreshControl.addTarget(self, action: #selector(reloadServerData), for: .valueChanged)

        listView.obaDataSource = self
        listView.collapsibleSectionsDelegate = self
        listView.contextMenuDelegate = self
        listView.refreshControl = refreshControl
        view.addSubview(listView)
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
        guard let alert = item.as(AgencyAlert.ListViewModel.self) else { return nil }

        let preview: OBAListViewMenuActions.PreviewProvider = {
            return self.previewAlert(alert)
        }

        let performPreview: VoidBlock = {
            self.performPreviewActionAlert(alert)
        }

        let menuProvider: OBAListViewMenuActions.MenuProvider = { _ in
            guard let copyLink = self.copyLink(alert) else { return nil }
            return UIMenu(title: "", image: nil, identifier: nil, options: [], children: [copyLink])
        }

        return OBAListViewMenuActions(previewProvider: preview, performPreviewAction: performPreview, contextMenuProvider: menuProvider)
    }

    // MARK: - Preview

    var previewingVC: (identifier: String, vc: UIViewController)?

    func previewAlert(_ alert: AgencyAlert.ListViewModel) -> UIViewController? {
        let viewController: UIViewController
        if let url = alert.localizedURL {
            viewController = SFSafariViewController(url: url)
        } else {
            viewController = AgencyAlertDetailViewController(alert)
        }

        self.previewingVC = (alert.id, viewController)
        return viewController
    }

    func performPreviewActionAlert(_ alert: AgencyAlert.ListViewModel) {
        if let previewingVC = self.previewingVC, previewingVC.identifier == alert.id {
            if previewingVC.vc is AgencyAlertDetailViewController {
                application.viewRouter.navigate(to: previewingVC.vc, from: self)
            } else {
                application.viewRouter.present(previewingVC.vc, from: self, isModal: true)
            }
        } else {
            presentAlert(alert)
        }
    }

    // MARK: - Menu actions

    func copyLink(_ alert: AgencyAlert.ListViewModel) -> UIAction? {
        guard let url = alert.localizedURL else { return nil }
        let copyLink = OBALoc("copy_link.title", value: "Copy Link", comment: "Copy a link to the user's clipboard")
        return UIAction(title: copyLink, image: UIImage(systemName: "link")) { _ in
            UIPasteboard.general.string = url.absoluteString
        }
    }

    // MARK: - List data

    func items(for listView: OBAListView) -> [OBAListViewSection] {
        return alertsStore.listViewSections(onSelectAction: { [weak self] alert in
            self?.presentAlert(alert)
        })
    }

    func didSelect(_ listView: OBAListView, item: AnyOBAListViewItem) {
        guard let agencyAlert = item.as(AgencyAlert.ListViewModel.self) else { return }
        presentAlert(agencyAlert)
    }

    func presentAlert(_ alert: AgencyAlert.ListViewModel) {
        if let url = alert.localizedURL {
            let safari = SFSafariViewController(url: url)
            application.viewRouter.present(safari, from: self, isModal: true)
        } else {
            application.viewRouter.navigate(to: AgencyAlertDetailViewController(alert), from: self)
        }
    }
}
