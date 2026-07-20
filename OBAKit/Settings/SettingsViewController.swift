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
            +++ experimentalSection
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
            FeatureFlags.useMapPanelExperienceKey: application.userDefaults.bool(forKey: FeatureFlags.useMapPanelExperienceKey),
            FeatureFlags.useNewStopPageKey: FeatureFlags.isNewStopPageEnabled(userDefaults: application.userDefaults),
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

        saveExperimentalValues(values)
        saveAlertsValues(values)

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

        saveWalkingSpeedValues(values)
    }

    private func saveExperimentalValues(_ values: [String: Any?]) {
        if let useMapPanel = values[FeatureFlags.useMapPanelExperienceKey] as? Bool {
            application.userDefaults.set(useMapPanel, forKey: FeatureFlags.useMapPanelExperienceKey)
        }

        if let useNewStopPage = values[FeatureFlags.useNewStopPageKey] as? Bool {
            application.userDefaults.set(useNewStopPage, forKey: FeatureFlags.useNewStopPageKey)
        }
    }

    private func saveAlertsValues(_ values: [String: Any?]) {
        if let testAlerts = values[AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts] as? Bool {
            application.userDefaults.set(testAlerts, forKey: AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts)
        }
    }

    private func saveWalkingSpeedValues(_ values: [String: Any?]) {
        let store = application.userDataStore
        let decision = WalkingSpeedSettingsDecision.compute(
            currentSource: store.walkingSpeedSource,
            currentSpeed: store.walkingSpeedMetersPerSecond,
            useHealthKit: values[walkingSpeedUseHealthKitKey] as? Bool,
            segmentSpeed: values[walkingSpeedMetersPerSecondKey] as? Double
        )
        store.walkingSpeedSource = decision.source
        store.walkingSpeedMetersPerSecond = decision.speed
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

    // MARK: - Experimental Section

    private lazy var experimentalSection: Section = {
        let section = Section(
            header: OBALoc("settings_controller.experimental_section.title", value: "Experimental", comment: "Settings > Experimental section title"),
            footer: OBALoc("settings_controller.experimental_section.map_panel.footer", value: "Restart the app to apply.", comment: "Settings > Experimental section > Footer indicating changes apply on relaunch")
        )

        section <<< SwitchRow {
            $0.tag = FeatureFlags.useMapPanelExperienceKey
            $0.title = OBALoc("settings_controller.experimental_section.map_panel", value: "Use map panel experience", comment: "Settings > Experimental section > Map panel toggle")
        }

        section <<< SwitchRow {
            $0.tag = FeatureFlags.useNewStopPageKey
            $0.title = OBALoc("settings_controller.experimental_section.new_stop_page", value: "Use new stop page", comment: "Settings > Experimental section > New stop page toggle")
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

    private let walkingSpeedMetersPerSecondKey = "walkingSpeedMetersPerSecond"
    private let walkingSpeedUseHealthKitKey = "walkingSpeedUseHealthKit"

    private func snapToPreset(_ speed: Double) -> Double {
        WalkingSpeedPreset.nearest(to: speed).rawValue
    }

    private lazy var walkingSpeedSection: Section = {
        let section = Section(OBALoc("settings_controller.walking_speed_section.title", value: "Walking Speed", comment: "Settings > Walking Speed section title"))

        section <<< SegmentedRow<Double> {
            $0.tag = walkingSpeedMetersPerSecondKey
            $0.title = OBALoc("settings_controller.walking_speed.title",
                              value: "Walking speed",
                              comment: "Settings > Walking Speed section > Speed picker")
            $0.options = WalkingSpeedPreset.allCases.map { $0.rawValue }
            $0.displayValueFor = { speed in
                WalkingSpeedPreset.nearest(to: speed ?? WalkingSpeed.defaultMetersPerSecond).localizedTitle
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
                    // Eureka's onChange closure is nonisolated (pre-concurrency
                    // library), so `row` can't cross into the main-actor task;
                    // re-fetch it by tag inside instead.
                    Task { @MainActor in
                        let granted = await self.application.walkingSpeedManager.requestHealthKitAuthorizationAndSync()
                        if !granted {
                            if let row: SwitchRow = self.form.rowBy(tag: self.walkingSpeedUseHealthKitKey) {
                                row.value = false
                                row.reload()
                            } else {
                                // Should be unreachable (the row is created with this tag
                                // above); if it ever fires, the toggle stays on and the
                                // HealthKit source would be persisted despite the denial.
                                Logger.error("HealthKit toggle row not found by tag; cannot revert after authorization failure.")
                            }
                            self.showErrorToast(
                                OBALoc(
                                    "settings_controller.walking_speed.healthkit_unavailable",
                                    value: "Couldn't sync walking speed from Health. Check Settings > Privacy & Security > Health to allow access.",
                                    comment: "Settings > Walking Speed > HealthKit denial or no-data toast"
                                ),
                                using: self.application.toastManager
                            )
                        }
                    }
                }
            }
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

    /// Hides a row unless the Debug Mode switch is on.
    ///
    /// Captures only the tag string: a `Condition` is stored on its row for the lifetime
    /// of the form the controller owns, so capturing `self` in one retains the controller
    /// in a cycle and it never deallocates after dismissal.
    private static func hiddenUnlessDebugMode(_ debugModeTag: String) -> Condition {
        Condition.function([debugModeTag]) { form in
            !((form.rowBy(tag: debugModeTag) as? SwitchRow)?.value ?? false)
        }
    }
    private let crashAppKey = "crashAppKey"
    private let pushIDKey = "pushIDKey"
    private let testDeviceDescriptionKey = "testDeviceDescriptionKey"

    private lazy var debugSection: Section = makeDebugSection()

    // swiftlint:disable:next function_body_length
    private func makeDebugSection() -> Section {
        let section = Section(OBALoc("settings_controller.debug_section.title", value: "Debug", comment: "Settings > Debug section title"))

        section <<< SwitchRow {
            $0.tag = debugModeEnabled
            $0.title = OBALoc("settings_controller.debug_section.debug_mode", value: "Debug Mode", comment: "Settings > Debug section > Debug mode")
            $0.onChange { [weak self] row in
                guard let self, let value = row.value, value == false else { return }

                // Turning Debug Mode off also turns off the debug-only behaviors it exposed.
                if let refreshRegionsRow = form.rowBy(tag: RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey) as? SwitchRow {
                    refreshRegionsRow.value = false
                }
                if let testAlertsRow = form.rowBy(tag: AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts) as? SwitchRow {
                    testAlertsRow.value = false
                }
            }
        }

        section <<< SwitchRow {
            $0.tag = RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey
            $0.title = OBALoc("settings_controller.debug_section.always_refresh_regions", value: "Refresh regions on every launch", comment: "Settings > Debug section > Refresh regions on every launch")
            $0.hidden = Self.hiddenUnlessDebugMode(debugModeEnabled)
        }

        section <<< LabelRow {
            $0.tag = crashAppKey
            $0.title = OBALoc("more_controller.debug_section.crash_row", value: "Crash the app", comment: "Title for a button that will crash the app.")
            $0.hidden = Condition.function([debugModeEnabled], { [debugModeEnabled, application] form in
                return !((form.rowBy(tag: debugModeEnabled) as? SwitchRow)?.value ?? false) && application.shouldShowCrashButton
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
            $0.hidden = Self.hiddenUnlessDebugMode(debugModeEnabled)
            $0.disabled = true
            $0.onCellSelection { [weak self] _, row in
                guard let self, let pushUserID = application.pushService?.pushUserID else { return }
                UIPasteboard.general.string = pushUserID

                // Sets the text to a "copied to clipboard" confirmation message, then after 2 seconds, shows the push ID again.
                row.value = OBALoc("clipboard.copied_text_confirmation", value: "Copied to clipboard", comment: "This is displayed to confirm that something has been copied to clipboard.")
                row.reload()

                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    row.value = self.application.pushService?.pushUserID ?? OBALoc("more_controller.debug_section.push_id.not_available", value: "Not available", comment: "This is displayed instead of the user's push ID if the value is not available.")
                    row.reload()
                }
            }
            $0.cellUpdate { cell, _ in
                cell.titleLabel?.textColor = .label
            }
        }

        section <<< TextRow {
            $0.tag = testDeviceDescriptionKey
            $0.title = OBALoc("settings_controller.debug_section.test_device_description", value: "Test Device Name", comment: "Settings > Debug section > Name identifying this device for test push notifications")
            $0.placeholder = OBALoc("settings_controller.debug_section.test_device_description.placeholder", value: "e.g. Aaron's iPhone", comment: "Placeholder example for the test device name field")
            $0.value = application.userDefaults.string(forKey: PushRegistrationManager.testDeviceDescriptionDefaultsKey)
            $0.hidden = Self.hiddenUnlessDebugMode(debugModeEnabled)
            $0.onChange { [weak self] row in
                guard let self else { return }
                application.userDefaults.set(row.value, forKey: PushRegistrationManager.testDeviceDescriptionDefaultsKey)

                // Clearing the name revokes test-device status, so test alerts go with it.
                let trimmed = row.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if trimmed.isEmpty, let testAlertsRow = form.rowBy(tag: AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts) as? SwitchRow {
                    testAlertsRow.value = false
                }
            }
        }

        section <<< SwitchRow {
            $0.tag = AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts
            $0.title = OBALoc("settings_controller.alerts_section.display_test_alerts", value: "Display test alerts", comment: "Settings > Debug section > Display test alerts")
            $0.hidden = Self.hiddenUnlessDebugMode(debugModeEnabled)
            // Test alerts only display for a named test device (see
            // AgencyAlertsStore.shouldDisplayTestAlerts), so the switch is inert without a name.
            $0.disabled = Condition.function([testDeviceDescriptionKey], { [testDeviceDescriptionKey] form in
                let name = (form.rowBy(tag: testDeviceDescriptionKey) as? TextRow)?.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return name.isEmpty
            })
        }

        return section
    }

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

        section.hidden = application.hasDataToMigrate ? false : Self.hiddenUnlessDebugMode(debugModeEnabled)

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
