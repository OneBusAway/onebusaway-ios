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

/// Displays a list of `ServiceAlert` objects.
final class ServiceAlertListController: UIViewController,
    AppContext,
    AgencyAlertListViewConverters,
    OBAListViewDataSource,
    Previewable {

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
    public override func loadView() {
        super.loadView()
        self.view = listView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = ThemeColors.shared.systemBackground

        listView.obaDataSource = self
        listView.pinToSuperview(.edges)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        listView.applyData()
    }

    // MARK: - Previewable

    func enterPreviewMode() {
        // nop.
    }

    func exitPreviewMode() {
        // nop.
    }

    // MARK: - ListView
    private let listView = OBAListView()

    func items(for listView: OBAListView) -> [OBAListViewSection] {
        return [listSection(serviceAlerts: serviceAlerts, showSectionTitle: true)]
    }
}
