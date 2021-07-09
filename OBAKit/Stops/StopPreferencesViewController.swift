//
//  StopPreferencesViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import Eureka
import OBAKitCore

protocol StopPreferencesDelegate: NSObjectProtocol {
    func stopPreferences(_ controller: StopPreferencesViewController, updated stopPreferences: StopPreferences)
}

/// Allows the user to toggle which `Route`s are displayed on the `StopViewController` for an individual `Stop`.
class StopPreferencesViewController: FormViewController {
    private let application: Application
    private let stop: Stop
    private weak var delegate: (ModalDelegate & StopPreferencesDelegate)?

    init(application: Application, stop: Stop, delegate: (ModalDelegate & StopPreferencesDelegate)?) {
        self.application = application
        self.stop = stop
        self.delegate = delegate

        super.init(style: .insetGrouped)

        title = OBALoc("stop_preferences_controller.title", value: "Filter Routes", comment: "Title of the Edit Stop preferences controller")

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        form +++ routesSection
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if let currentRegion = application.currentRegion {
            let stopPreferences = generateStopPreferences()
            application.stopPreferencesDataStore.set(stopPreferences: stopPreferences, stop: stop, region: currentRegion)
            delegate?.stopPreferences(self, updated: stopPreferences)
        }
    }

    @objc private func close() {
        delegate?.dismissModalController(self)
    }

    // MARK: - Data

    private func generateStopPreferences() -> StopPreferences {
        guard let region = application.currentRegion else { fatalError() }

        let selectedRoutes = routesSection.selectedRows().compactMap { $0.value }
        let hiddenRoutes = Set(stop.routeIDs).subtracting(selectedRoutes)
        let sort = application.stopPreferencesDataStore.preferences(stopID: stop.id, region: region).sortType

        return StopPreferences(sortType: sort, hiddenRoutes: hiddenRoutes.allObjects)
    }

    // MARK: - Form

    private let routesTag = "routesTag"

    private lazy var routesSection: SelectableSection<ListCheckRow<String>> = {
        guard let region = application.currentRegion else { fatalError() }

        let stopPreferences = application.stopPreferencesDataStore.preferences(stopID: stop.id, region: region)

        let section = SelectableSection<ListCheckRow<String>>(
            OBALoc("stop_preferences_controller.routes_section.header_title", value: "Routes", comment: "Title of the Routes section"),
            selectionType: .multipleSelection
        ) {
            $0.tag = self.routesTag
        }

        for route in stop.routes.localizedCaseInsensitiveSort() {
            section <<< ListCheckRow<String>(route.id) {
                $0.title = route.longName ?? route.shortName
                $0.selectableValue = route.id
                $0.value = stopPreferences.isRouteIDHidden(route.id) ? nil : route.id
            }
        }

        return section
    }()
}
