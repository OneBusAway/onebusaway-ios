//
//  SettingsViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 7/6/19.
//

import Eureka
import OBAKitCore

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

        view.tintColor = ThemeColors.shared.brand

        form
            +++ mapSection
            +++ alertsSection

        if application.analytics != nil {
            form +++ privacySection
        }

        form.setValues([
            mapSectionShowsScale: application.mapRegionManager.mapViewShowsScale,
            mapSectionShowsTraffic: application.mapRegionManager.mapViewShowsTraffic,
            mapSectionShowsHeading: application.mapRegionManager.mapViewShowsHeading,
            privacySectionReportingEnabled: application.analytics?.reportingEnabled?() ?? false,
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

        if let heading = values[mapSectionShowsHeading] as? Bool {
            application.mapRegionManager.mapViewShowsHeading = heading
        }

        if let testAlerts = values[AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts] as? Bool {
            application.userDefaults.set(testAlerts, forKey: AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts)
        }

        if let reportingEnabled = values[privacySectionReportingEnabled] as? Bool {
            application.analytics?.setReportingEnabled?(reportingEnabled)
        }
    }

    // MARK: - Map Section

    private let mapSectionShowsScale = "mapSectionShowsScale"
    private let mapSectionShowsTraffic = "mapSectionShowsTraffic"
    private let mapSectionShowsHeading = "mapSectionShowsHeading"

    private lazy var mapSection: Section = {
        let section = Section(OBALoc("settings_controller.map_section.title", value: "Map", comment: "Settings > Map section title"))

        section <<< SwitchRow {
            $0.tag = mapSectionShowsScale
            $0.title = OBALoc("settings_controller.map_section.shows_scale", value: "Shows scale", comment: "Settings > Map section > Shows scale")
        }

        section <<< SwitchRow {
            $0.tag = mapSectionShowsTraffic
            $0.title = OBALoc("settings_controller.map_section.shows_traffic", value: "Shows traffic", comment: "Settings > Map section > Shows traffic")
        }

        section <<< SwitchRow {
            $0.tag = mapSectionShowsHeading
            $0.title = OBALoc("settings_controller.map_section.shows_heading", value: "Show my current heading", comment: "Settings > Map section > Show my current heading")
        }

        return section
    }()

    // MARK: - Agency Alerts

    private lazy var alertsSection: Section = {
        let section = Section(OBALoc("settings_controller.alerts_section.title", value: "Agency Alerts", comment: "Settings > Alerts section title"))

        section <<< SwitchRow {
            $0.tag = AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts
            $0.title = OBALoc("settings_controller.alerts_section.display_test_alerts", value: "Display test alerts", comment: "Settings > Alerts section > Display test alerts")
        }

        return section
    }()

   // MARK: - Privacy

    private let privacySectionReportingEnabled = "privacySectionReportingEnabled"

    private lazy var privacySection: Section = {
        let section = Section(OBALoc("settings_controller.privacy_section.title", value: "Privacy", comment: "Settings > Privacy section title"))

        section <<< SwitchRow {
            $0.tag = privacySectionReportingEnabled
            $0.title = OBALoc("settings_controller.privacy_section.reporting_enabled", value: "Send usage data to developer", comment: "Settings > Privacy section > Send usage data")
        }

        return section
    }()

    // MARK: - Actions

    @objc private func dismissModal() {
        dismiss(animated: true, completion: nil)
    }
}
