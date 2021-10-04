//
//  SettingsViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Eureka
import Foundation
import OBAKitCore
import UIKit

class SettingsViewController: FormViewController {
    private let application: Application

    init(application: Application) {
        self.application = application

        super.init(style: .insetGrouped)

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
            +++ accessibilitySection

        if application.analytics != nil {
            form +++ privacySection
        }

        if application.userDataStore.debugMode {
            form +++ debugSection
        }

        if application.hasDataToMigrate {
            form +++ migrateDataSection
        }

        form +++ exportDataSection

        form.setValues([
            mapSectionShowsScale: application.mapRegionManager.mapViewShowsScale,
            mapSectionShowsTraffic: application.mapRegionManager.mapViewShowsTraffic,
            mapSectionShowsHeading: application.mapRegionManager.mapViewShowsHeading,
            privacySectionReportingEnabled: application.analytics?.reportingEnabled?() ?? false,
            DataLoadFeedbackGenerator.EnabledUserDefaultsKey: application.userDefaults.bool(forKey: DataLoadFeedbackGenerator.EnabledUserDefaultsKey),
            AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts: application.userDefaults.bool(forKey: AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts),
            RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey: application.userDefaults.bool(forKey: RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey)
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

        if let hapticFeedbackOnDataLoad = values[DataLoadFeedbackGenerator.EnabledUserDefaultsKey] as? Bool {
            application.userDefaults.set(hapticFeedbackOnDataLoad, forKey: DataLoadFeedbackGenerator.EnabledUserDefaultsKey)
        }

        if let testAlerts = values[AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts] as? Bool {
            application.userDefaults.set(testAlerts, forKey: AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts)
        }

        if let reportingEnabled = values[privacySectionReportingEnabled] as? Bool {
            application.analytics?.setReportingEnabled?(reportingEnabled)
        }

        if let alwaysRefreshRegions = values[RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey] as? Bool {
            application.userDefaults.set(alwaysRefreshRegions, forKey: RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey)
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

    private lazy var accessibilitySection: Section = {
        let section = Section() /* Untitled section */

        section <<< SwitchRow {
            $0.tag = DataLoadFeedbackGenerator.EnabledUserDefaultsKey
            $0.title = OBALoc("settings_controller.accessibility_section.enable_reload_haptic", value: "Haptic feedback on reload", comment: "Settings > Accessibility section > Haptic feedback on reload")
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

    // MARK: - Debug Section

    private lazy var debugSection: Section = {
        let section = Section(OBALoc("settings_controller.debug_section.title", value: "Debug", comment: "Settings > Debug section title"))

        section <<< SwitchRow {
            $0.tag = RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey
            $0.title = OBALoc("settings_controller.debug_section.always_refresh_regions", value: "Refresh regions on every launch", comment: "Settings > Debug section > Refresh regions on every launch")
        }

        return section
    }()

    // MARK: - Migrate Data Section

    private lazy var migrateDataSection: Section = {
        let section = Section(header: nil, footer: Strings.migrateDataDescription)

        section <<< ButtonRow("migrate_tag") {
            $0.title = Strings.migrateData
            $0.onCellSelection { [weak self] _, _ in
                guard let self = self else { return }
                self.application.performDataMigration()
            }
        }

        return section
    }()

    // MARK: - Exports Defaults Section

    private lazy var exportDataSection: Section = {
        let section = Section(header: nil, footer: nil)

        section <<< ButtonRow("export_data") {
            $0.title = Strings.exportData
            $0.onCellSelection { [weak self] _, _ in
                guard let self = self else { return }

                let dict = self.application.userDefaults.dictionaryRepresentation()

                do {
                    let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
                    let tmpDirURL = FileManager.default.temporaryDirectory
                    let xmlPath = tmpDirURL.appendingPathComponent("userdefaults.xml")
                    try data.write(to: xmlPath)
                    let activity = UIActivityViewController(activityItems: [xmlPath], applicationActivities: nil)
                    self.present(activity, animated: true, completion: nil)
                } catch let ex {
                    AlertPresenter.show(error: ex, presentingController: self)
                }
            }
        }

        return section
    }()

    // MARK: - Actions

    @objc private func dismissModal() {
        dismiss(animated: true, completion: nil)
    }
}
