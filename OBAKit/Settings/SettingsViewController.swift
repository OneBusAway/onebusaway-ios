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
import HealthKit
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
            +++ walkingSpeedSection
            +++ surveySection
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
            privacySectionReportingEnabled: application.analytics?.reportingEnabled() ?? false,
            DataLoadFeedbackGenerator.EnabledUserDefaultsKey: application.userDefaults.bool(forKey: DataLoadFeedbackGenerator.EnabledUserDefaultsKey),
            AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts: application.userDefaults.bool(forKey: AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts),
            RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey: application.userDefaults.bool(forKey: RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey),
            MapRegionManager.mapViewShowsStopAnnotationLabelsDefaultsKey: application.userDefaults.bool(forKey: MapRegionManager.mapViewShowsStopAnnotationLabelsDefaultsKey),
            debugModeEnabled: application.userDataStore.debugMode,
            alwaysShowSurveysOnStops: application.userDataStore.alwaysShowSurveysOnStops,
            walkingSpeedMetersPerSecondKey: snapToPreset(application.userDataStore.walkingSpeedMetersPerSecond),
            walkingSpeedUseHealthKitKey: application.userDataStore.walkingSpeedSource == .healthKit
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
            application.analytics?.setReportingEnabled(reportingEnabled)
        }

        if let debugEnabled = values[debugModeEnabled] as? Bool {
            application.userDataStore.debugMode = debugEnabled
        }

        if let alwaysShowSurveys = values[alwaysShowSurveysOnStops] as? Bool {
            application.userDataStore.alwaysShowSurveysOnStops = alwaysShowSurveys
        }

        if let alwaysRefreshRegions = values[RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey] as? Bool {
            application.userDefaults.set(alwaysRefreshRegions, forKey: RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey)
        } else {
            application.userDefaults.set(false, forKey: RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey)
        }

        // Walking Speed — save source first to avoid race condition
        if let useHK = values[walkingSpeedUseHealthKitKey] as? Bool {
            application.userDataStore.walkingSpeedSource = useHK ? .healthKit : .manual
        }

        if let speed = values[walkingSpeedMetersPerSecondKey] as? Double,
           application.userDataStore.walkingSpeedSource == .manual {
            application.userDataStore.walkingSpeedMetersPerSecond = speed
        }

        // Snap to nearest preset when toggling HealthKit OFF
        if let useHK = values[walkingSpeedUseHealthKitKey] as? Bool, !useHK {
            application.userDataStore.walkingSpeedMetersPerSecond = snapToPreset(
                application.userDataStore.walkingSpeedMetersPerSecond
            )
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

    // MARK: - Walking Speed

    private let walkingSpeedPresets: [Double] = [0.9, 1.4, 1.8]

    private func snapToPreset(_ speed: Double) -> Double {
        walkingSpeedPresets.min(by: { abs($0 - speed) < abs($1 - speed) }) ?? 1.4
    }

    private lazy var walkingSpeedSection: Section = {
        let section = Section(OBALoc("settings_controller.walking_speed_section.title", value: "Walking Speed", comment: "Settings > Walking Speed section title"))

        section <<< SegmentedRow<Double> {
            $0.tag = walkingSpeedMetersPerSecondKey
            $0.title = OBALoc("settings_controller.walking_speed.title",
                              value: "Walking speed",
                              comment: "Settings > Walking Speed section > Speed picker")
            $0.options = walkingSpeedPresets
            $0.displayValueFor = { speed in
                switch speed {
                case 0.9: return OBALoc("settings_controller.walking_speed.slow", value: "Slow (~2 mph)", comment: "")
                case 1.8: return OBALoc("settings_controller.walking_speed.fast", value: "Fast (~4 mph)", comment: "")
                default:  return OBALoc("settings_controller.walking_speed.avg", value: "Average (~3 mph)", comment: "")
                }
            }
            $0.disabled = Condition.function([walkingSpeedUseHealthKitKey], { [weak self] form in
                guard let self = self else { return false }
                return (form.rowBy(tag: self.walkingSpeedUseHealthKitKey) as? SwitchRow)?.value ?? false
            })
        }

        if HKHealthStore.isHealthDataAvailable() {
            section <<< SwitchRow {
                $0.tag = walkingSpeedUseHealthKitKey
                $0.title = OBALoc("settings_controller.walking_speed.use_healthkit",
                                  value: "Use Health app data",
                                  comment: "Settings > Walking Speed section > HealthKit toggle")
                $0.onChange { [weak self] row in
                    guard let self, row.value == true else { return }
                    Task {
                        let granted = await self.application.walkingSpeedManager.requestHealthKitAuthorizationAndSync()
                        if !granted {
                            row.value = false
                            row.reload()
                            self.application.userDataStore.walkingSpeedSource = .manual
                        }
                    }
                }
            }
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
    private let alwaysShowSurveysOnStops = "alwaysShowSurveysOnStops"
    
    // MARK: - Walking Speed Keys
    private let walkingSpeedMetersPerSecondKey = "walkingSpeedMetersPerSecond"
    private let walkingSpeedUseHealthKitKey = "walkingSpeedUseHealthKit"

    private lazy var privacySection: Section = {
        let section = Section(OBALoc("settings_controller.privacy_section.title", value: "Privacy", comment: "Settings > Privacy section title"))

        section <<< SwitchRow {
            $0.tag = privacySectionReportingEnabled
            $0.title = OBALoc("settings_controller.privacy_section.reporting_enabled", value: "Send usage data to developer", comment: "Settings > Privacy section > Send usage data")
        }

        return section
    }()

    // MARK: - Surveys Section

    private let alwaysShowSurveysOnStops = "alwaysShowSurveysOnStops"

    private lazy var surveySection: Section = {
        let section = Section(OBALoc("settings_controller.survey_section.title", value: "Surveys", comment: "Settings > Surveys section title"))

        section <<< SwitchRow {
            $0.tag = alwaysShowSurveysOnStops
            $0.title = OBALoc("settings_controller.survey_section.always_show_on_stops", value: "Always show on stops", comment: "Settings > Surveys section > Always show surveys on stops")
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

                // Sets the text to a "copied to clipboard" confirmation message, then after 2 seconds, shows the push ID again.
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
