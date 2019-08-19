//
//  SettingsViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 7/6/19.
//

import Eureka

class SettingsViewController: FormViewController {
    private let application: Application

    init(application: Application) {
        self.application = application

        super.init(nibName: nil, bundle: nil)

        title = Strings.settings

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissModal))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        form
            +++ mapSection
            +++ alertsSection

        form.setValues([
            mapSectionShowsScale: application.mapRegionManager.mapViewShowsScale,
            mapSectionShowsTraffic: application.mapRegionManager.mapViewShowsTraffic,
            AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts: application.userDefaults.bool(forKey: AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts)
        ])
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        saveFormValues()
    }

    // MARK: - Form Data

    private func saveFormValues() {
        let values = form.values()

        if let scale = values[mapSectionShowsScale] as? Bool {
            application.mapRegionManager.mapViewShowsScale = scale
        }

        if let traffic = values[mapSectionShowsTraffic] as? Bool {
            application.mapRegionManager.mapViewShowsTraffic = traffic
        }

        if let testAlerts = values[AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts] as? Bool {
            application.userDefaults.set(testAlerts, forKey: AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts)
        }
    }

    // MARK: - Map Section

    private let mapSectionShowsScale = "mapSectionShowsScale"
    private let mapSectionShowsTraffic = "mapSectionShowsTraffic"

    private lazy var mapSection: Section = {
        let section = Section(NSLocalizedString("settings_controller.map_section.title", value: "Map", comment: "Settings > Map section title"))

        section <<< SwitchRow {
            $0.tag = mapSectionShowsScale
            $0.title = NSLocalizedString("settings_controller.map_section.shows_scale", value: "Shows scale", comment: "Settings > Map section > Shows scale")
        }

        section <<< SwitchRow {
            $0.tag = mapSectionShowsTraffic
            $0.title = NSLocalizedString("settings_controller.map_section.shows_traffic", value: "Shows traffic", comment: "Settings > Map section > Shows traffic")
        }

        return section
    }()

    // MARK: - Alerts

    private lazy var alertsSection: Section = {
        let section = Section(NSLocalizedString("settings_controller.alerts_section.title", value: "Alerts", comment: "Settings > Alerts section title"))

        section <<< SwitchRow {
            $0.tag = AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts
            $0.title = NSLocalizedString("settings_controller.alerts_section.display_test_alerts", value: "Display test alerts", comment: "Settings > Alerts section > Display test alerts")
        }

        return section
    }()

    // MARK: - Actions

    @objc private func dismissModal() {
        dismiss(animated: true, completion: nil)
    }
}
