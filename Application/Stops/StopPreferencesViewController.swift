//
//  StopPreferencesViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 8/13/19.
//

import UIKit
import Eureka
import OBAKitCore

protocol StopPreferencesDelegate: NSObjectProtocol {
    func stopPreferences(_ controller: StopPreferencesViewController, updated stopPreferences: StopPreferences)
}

/// Allows the user to toggle which `Route`s are displayed and change grouping on the `StopViewController` for an individual `Stop`.
class StopPreferencesViewController: FormViewController {
    private let application: Application
    private let stop: Stop
    private weak var delegate: (ModalDelegate & StopPreferencesDelegate)?

    init(application: Application, stop: Stop, delegate: (ModalDelegate & StopPreferencesDelegate)?) {
        self.application = application
        self.stop = stop
        self.delegate = delegate

        super.init(nibName: nil, bundle: nil)

        title = NSLocalizedString("stop_preferences_controller.title", value: "Sort & Filter Routes", comment: "Title of the Edit Stop preferences controller")

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        form
            +++ sortingSection
            +++ routesSection
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
        guard
            let rawSortValue = sortingSection.selectedRow()?.value,
            let sort = StopSort(rawValue: rawSortValue)
        else { return StopPreferences() }

        let selectedRoutes = routesSection.selectedRows().compactMap { $0.value }
        let hiddenRoutes = Set(stop.routeIDs).subtracting(selectedRoutes)

        return StopPreferences(sortType: sort, hiddenRoutes: hiddenRoutes.allObjects)
    }

    // MARK: - Form

    private let selectedSortTag = "sortTag"
    private let routesTag = "routesTag"

    private lazy var sortingSection: SelectableSection<ListCheckRow<String>> = {
        guard let region = application.currentRegion else {
            fatalError()
        }

        let preferences = application.stopPreferencesDataStore.preferences(stopID: stop.id, region: region)
        let sortType = preferences.sortType.rawValue
        form.setValues([selectedSortTag: sortType])

        let section = SelectableSection<ListCheckRow<String>>(
            NSLocalizedString("stop_preferences_controller.sorting_section.header_title", value: "Sorting", comment: "Title of the Sorting section"),
            selectionType: .singleSelection(enableDeselection: false)
        )

        section <<< ListCheckRow<String>(StopSort.time.rawValue) {
            $0.tag = selectedSortTag
            $0.title = NSLocalizedString("stop_preferences_controller.sorting_section.sort_by_time", value: "Sort by time", comment: "Sort by time option")
            $0.selectableValue = StopSort.time.rawValue
            $0.value = preferences.sortType == .time ? StopSort.time.rawValue : nil
        }

        section <<< ListCheckRow<String>(StopSort.route.rawValue) {
            $0.tag = selectedSortTag
            $0.title = NSLocalizedString("stop_preferences_controller.sorting_section.sort_by_route", value: "Sort by route", comment: "Sort by route option")
            $0.selectableValue = StopSort.route.rawValue
            $0.value = preferences.sortType == .route ? StopSort.route.rawValue : nil
        }

        return section
    }()

    private lazy var routesSection: SelectableSection<ListCheckRow<String>> = {
        guard let region = application.currentRegion else { fatalError() }

        let stopPreferences = application.stopPreferencesDataStore.preferences(stopID: stop.id, region: region)

        let section = SelectableSection<ListCheckRow<String>>(
            NSLocalizedString("stop_preferences_controller.routes_section.header_title", value: "Routes", comment: "Title of the Routes section"),
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
