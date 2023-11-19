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
            +++ debugSection

        if application.analytics != nil {
            form +++ privacySection
        }

        form +++ migrateDataSection
        form +++ exportDataSection

        form.setValues([
            mapSectionShowsScale: application.mapRegionManager.mapViewShowsScale,
            mapSectionShowsTraffic: application.mapRegionManager.mapViewShowsTraffic,
            mapSectionShowsHeading: application.mapRegionManager.mapViewShowsHeading,
            privacySectionReportingEnabled: application.analytics?.reportingEnabled?() ?? false,
            DataLoadFeedbackGenerator.EnabledUserDefaultsKey: application.userDefaults.bool(forKey: DataLoadFeedbackGenerator.EnabledUserDefaultsKey),
            AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts: application.userDefaults.bool(forKey: AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts),
            RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey: application.userDefaults.bool(forKey: RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey),
            MapRegionManager.mapViewShowsStopAnnotationLabelsDefaultsKey: application.userDefaults.bool(forKey: MapRegionManager.mapViewShowsStopAnnotationLabelsDefaultsKey),
            debugModeEnabled: application.userDataStore.debugMode
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

        if let mapViewShowsStopAnnotationLabels = values[MapRegionManager.mapViewShowsStopAnnotationLabelsDefaultsKey] as? Bool {
            application.userDefaults.set(mapViewShowsStopAnnotationLabels, forKey: MapRegionManager.mapViewShowsStopAnnotationLabelsDefaultsKey)
        }

        if let testAlerts = values[AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts] as? Bool {
            application.userDefaults.set(testAlerts, forKey: AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts)
        }

        if let reportingEnabled = values[privacySectionReportingEnabled] as? Bool {
            application.analytics?.setReportingEnabled?(reportingEnabled)
        }

        if let debugEnabled = values[debugModeEnabled] as? Bool {
            application.userDataStore.debugMode = debugEnabled
        }

        if let alwaysRefreshRegions = values[RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey] as? Bool {
            application.userDefaults.set(alwaysRefreshRegions, forKey: RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey)
        } else {
            application.userDefaults.set(false, forKey: RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey)
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
        let section = Section(OBALoc("settings_controller.accessibility_section.title", value: "Accessibility", comment: "Settings > Accessibility section title"))

        section <<< SwitchRow {
            $0.tag = DataLoadFeedbackGenerator.EnabledUserDefaultsKey
            $0.title = OBALoc("settings_controller.accessibility_section.enable_reload_haptic", value: "Haptic feedback on reload", comment: "Settings > Accessibility section > Haptic feedback on reload")
        }

        section <<< SwitchRow {
            $0.tag = OBAFloatingPanelController.AlwaysShowFullSheetOnVoiceoverUserDefaultsKey
            $0.title = OBALoc("settings_controller.accessibility_section.default_full_sheet_voiceover", value: "Always show full sheet on Voiceover", comment: "Settings > Accessibility section > Always show full sheet on Voiceover")
        }

        section <<< SwitchRow {
            $0.tag = MapRegionManager.mapViewShowsStopAnnotationLabelsDefaultsKey
            $0.title = OBALoc("settings_controller.accessibility_section.show_stop_annotation_labels", value: "Show route labels on the map", comment: "Settings > Accessibility section > Show route labels on the map")
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

    private let debugModeEnabled = "debugModeEnabled"
    private let crashAppKey = "crashAppKey"
    private let pushIDKey = "pushIDKey"

    private lazy var debugSection: Section = {
        let section = Section(OBALoc("settings_controller.debug_section.title", value: "Debug", comment: "Settings > Debug section title"))

        section <<< SwitchRow {
            $0.tag = debugModeEnabled
            $0.title = OBALoc("settings_controller.debug_section.debug_mode", value: "Debug Mode", comment: "Settings > Debug section > Debug mode")
            $0.onChange { [weak self] row in
                guard let self, let refreshRegionsRow = form.rowBy(tag: RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey) as? SwitchRow, let value = row.value, value == false else { return }

                refreshRegionsRow.value = false
            }
        }

        section <<< SwitchRow {
            $0.tag = RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey
            $0.title = OBALoc("settings_controller.debug_section.always_refresh_regions", value: "Refresh regions on every launch", comment: "Settings > Debug section > Refresh regions on every launch")
            $0.hidden = Condition.function([debugModeEnabled], { form in
                return !((form.rowBy(tag: self.debugModeEnabled) as? SwitchRow)?.value ?? false)
            })
        }

        section <<< LabelRow {
            $0.tag = crashAppKey
            $0.title = OBALoc("more_controller.debug_section.crash_row", value: "Crash the app", comment: "Title for a button that will crash the app.")
            $0.hidden = Condition.function([debugModeEnabled], { form in
                return !((form.rowBy(tag: self.debugModeEnabled) as? SwitchRow)?.value ?? false) && self.application.shouldShowCrashButton
            })
            $0.onCellSelection { [weak self] _, _ in
                guard let self else { return }
                self.application.performTestCrash()
            }
            $0.cellUpdate { cell, _ in
                let imageView = UIImageView(image: UIImage(systemName: "chevron.right"))
                cell.accessoryView = imageView
            }
        }

        section <<< TextRow {
            $0.tag = pushIDKey
            $0.title = OBALoc("more_controller.debug_section.push_id.title", value: "Push ID", comment: "Title for the Push Notification ID row in the More Controller")
            $0.value = application.pushService?.pushUserID ?? OBALoc("more_controller.debug_section.push_id.not_available", value: "Not available", comment: "This is displayed instead of the user's push ID if the value is not available.")
            $0.hidden = Condition.function([debugModeEnabled], { form in
                return !((form.rowBy(tag: self.debugModeEnabled) as? SwitchRow)?.value ?? false)
            })
            $0.disabled = true
            $0.onCellSelection { [weak self] _, row in
                guard let self, let pushUserID = application.pushService?.pushUserID else { return }
                UIPasteboard.general.string = pushUserID

                row.value = OBALoc("clipboard.copied_text_confirmation", value: "Copied to clipboard", comment: "This is displayed to confirm that something has been copied to clipboard.")
                row.reload()

                Task {
                    try await Task.sleep(for: .seconds(2))
                    row.value = self.application.pushService?.pushUserID ?? OBALoc("more_controller.debug_section.push_id.not_available", value: "Not available", comment: "This is displayed instead of the user's push ID if the value is not available.")
                    row.reload()
                }
            }
            $0.cellUpdate { cell, _ in
                cell.titleLabel?.textColor = .label
            }
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

        section.hidden = application.hasDataToMigrate ? false : Condition.function([debugModeEnabled], { form in
            return !((form.rowBy(tag: self.debugModeEnabled) as? SwitchRow)?.value ?? false)
        })

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
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        await AlertPresenter.show(error: ex, presentingController: self)
                    }
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
