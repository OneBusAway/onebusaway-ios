//
//  AgencyAlertsViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import Combine
import OBAKitCore
import SafariServices

/// Displays `AgencyAlert` objects loaded from a Protobuf feed.
class AgencyAlertsViewController: UIViewController,
    AgencyAlertListViewConverters,
    AppContext,
    OBAListViewCollapsibleSectionsDelegate,
    OBAListViewContextMenuDelegate,
    OBAListViewDataSource {

    // MARK: - Stores
    public let application: Application
    private let viewModel: AgencyAlertsViewModel
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UI state
    let selectionFeedbackGenerator: UISelectionFeedbackGenerator? = UISelectionFeedbackGenerator()

    /// Forwards to the VM. Required by `OBAListViewCollapsibleSectionsDelegate`.
    var collapsedSections: Set<String> {
        get { viewModel.collapsedSections }
        set { viewModel.collapsedSections = newValue }
    }

    // MARK: - UI elements
    let listView = OBAListView()
    let refreshControl = UIRefreshControl()

    // MARK: - Init
    public init(application: Application) {
        self.application = application
        self.viewModel = AgencyAlertsViewModel(application: application)

        super.init(nibName: nil, bundle: nil)

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

        viewModel.$alerts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.listView.applyData(animated: false)
            }
            .store(in: &cancellables)

        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                guard let self else { return }
                if isLoading {
                    self.navigationItem.rightBarButtonItem = UIActivityIndicatorView.asNavigationItem()
                } else {
                    self.refreshControl.endRefreshing()
                    self.navigationItem.rightBarButtonItem = nil
                }
            }
            .store(in: &cancellables)

        reloadServerData()
    }

    // MARK: - Data Loading

    @objc private func reloadServerData() {
        viewModel.reloadServerData()
        refreshControl.beginRefreshing()
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
        let activityItems = viewModel.shareActivityItems(for: alert)

        return UIAction(title: Strings.share, image: Icons.share) { [weak self] _ in
            let vc = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
            self?.present(vc, animated: true, completion: nil)
        }
    }

    // MARK: - List data

    func items(for listView: OBAListView) -> [OBAListViewSection] {
        return listSections(agencyAlerts: viewModel.alerts)
    }

    func emptyData(for listView: OBAListView) -> OBAListView.EmptyData? {
        let regionName = application.currentRegion?.name
        return .standard(.init(title: Strings.emptyAlertTitle, body: regionName))
    }
}
