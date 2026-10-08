//
//  SettingsView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The Settings form. Every switch writes through `SettingsViewModel` as it
/// changes; the Done button and the share sheet belong to `SettingsViewController`.
struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    let exportData: () -> Void

    var body: some View {
        Form {
            mapSection
            arrivalDisplaySection
            experimentalSection
            accessibilitySection
            walkingSpeedSection
            bikeModeSection
            surveySection
            if viewModel.debugMode {
                feedbackSection
            }
            debugSection
            if viewModel.hasAnalytics {
                privacySection
            }
            if viewModel.hasDataToMigrate || viewModel.debugMode {
                Section {
                    Button(Strings.migrateData, action: viewModel.migrateData)
                } footer: {
                    Text(Strings.migrateDataDescription)
                }
            }
            Section {
                Button(Strings.exportData, action: exportData)
            }
        }
        .tint(Color(ThemeColors.shared.brand))
    }

    // MARK: - Map

    private var mapSection: some View {
        Section(OBALoc("settings_controller.map_section.title", value: "Map", comment: "Settings > Map section title")) {
            Toggle(OBALoc("settings_controller.map_section.shows_scale", value: "Shows scale", comment: "Settings > Map section > Shows scale"), isOn: $viewModel.mapShowsScale)
            Toggle(OBALoc("settings_controller.map_section.shows_traffic", value: "Shows traffic", comment: "Settings > Map section > Shows traffic"), isOn: $viewModel.mapShowsTraffic)
            Toggle(OBALoc("settings_controller.map_section.shows_heading", value: "Show my current heading", comment: "Settings > Map section > Show my current heading"), isOn: $viewModel.mapShowsHeading)
            Toggle(OBALoc("settings_controller.map_section.shows_points_of_interest", value: "Points of Interest", comment: "Settings > Map section > Show Apple MapKit Points of Interest"), isOn: $viewModel.mapShowsPointsOfInterest)
            ForEach(viewModel.mapLayers, id: \.id) { layer in
                Toggle(layer.title, isOn: Binding(
                    get: { viewModel.mapLayerEnabled[layer.id] ?? false },
                    set: { viewModel.setMapLayer(layer.id, enabled: $0) }
                ))
            }
        }
    }

    // MARK: - Arrival & Departure Display

    private var arrivalDisplaySection: some View {
        Section {
            Picker(OBALoc("settings_controller.arrival_filter.title", value: "Show Departures", comment: "Title for the departure filter setting row"), selection: $viewModel.arrivalDepartureFilter) {
                ForEach(ArrivalDepartureFilter.allCases, id: \.self) { filter in
                    Text(filter.displayTitle).tag(filter)
                }
            }
            Toggle(
                OBALoc("settings_controller.arrival_display_section.transfer_banner", value: "Show transfer arrival banner", comment: "Settings > Arrival & Departure Display > Toggle that shows the Arriving at XX:XX via route banner when opening a stop from a trip"),
                isOn: $viewModel.showsTransferArrivalBanner
            )
            Toggle(
                OBALoc("settings_controller.arrival_display_section.region_time_zone", value: "Show times in region time zone", comment: "Settings > Arrival & Departure Display > Opt-in toggle for displaying arrival clocks in the transit region's time zone"),
                isOn: $viewModel.showsRegionTimeZone
            )
        } header: {
            Text(OBALoc("settings_controller.arrival_display_section.title", value: "Arrival & Departure Display", comment: "Settings section title for controlling which arrivals/departures are shown"))
        } footer: {
            Text(OBALoc(
                "settings_controller.arrival_display_section.footer",
                value: "Transfer banner: opening a stop from a trip shows times relative to when you arrive. Region time zone: clock times use the transit region's zone, with a short badge when your phone differs. Both are independent.",
                comment: "Settings > Arrival & Departure Display > Footer describing the transfer banner and region time zone toggles"
            ))
        }
    }

    // MARK: - Experimental

    private var experimentalSection: some View {
        Section {
            Toggle(OBALoc("settings_controller.experimental_section.map_panel", value: "Use map panel experience", comment: "Settings > Experimental section > Map panel toggle"), isOn: $viewModel.usesMapPanelExperience)
            Toggle(OBALoc("settings_controller.experimental_section.new_stop_page", value: "Use new stop page", comment: "Settings > Experimental section > New stop page toggle"), isOn: $viewModel.usesNewStopPage)
        } header: {
            Text(OBALoc("settings_controller.experimental_section.title", value: "Experimental", comment: "Settings > Experimental section title"))
        } footer: {
            Text(OBALoc("settings_controller.experimental_section.map_panel.footer", value: "Restart the app to apply.", comment: "Settings > Experimental section > Footer indicating changes apply on relaunch"))
        }
    }

    // MARK: - Accessibility

    private var accessibilitySection: some View {
        Section(OBALoc("settings_controller.accessibility_section.title", value: "Accessibility", comment: "Settings > Accessibility section title")) {
            Toggle(OBALoc("settings_controller.accessibility_section.enable_reload_haptic", value: "Haptic feedback on reload", comment: "Settings > Accessibility section > Haptic feedback on reload"), isOn: $viewModel.hapticFeedbackOnReload)
            Toggle(OBALoc("settings_controller.accessibility_section.default_full_sheet_voiceover", value: "Always show full sheet on Voiceover", comment: "Settings > Accessibility section > Always show full sheet on Voiceover"), isOn: $viewModel.alwaysShowsFullSheetOnVoiceOver)
            Toggle(OBALoc("settings_controller.accessibility_section.show_stop_annotation_labels", value: "Show route labels on the map", comment: "Settings > Accessibility section > Show route labels on the map"), isOn: $viewModel.showsStopAnnotationLabels)
            Toggle(OBALoc("settings_controller.accessibility_section.reduce_stop_colors", value: "Reduce colors on stop page", comment: "Settings > Accessibility section > Toggle that renders stop page route badges as a thin color bar beside plain text instead of a colored square"), isOn: $viewModel.reducesStopColors)
            Toggle(OBALoc("settings_controller.accessibility_section.compact_stop_trip", value: "Compact stop and trip pages", comment: "Settings > Accessibility > Toggle that tightens spacing on the new stop and trip screens"), isOn: $viewModel.compactsStopAndTripPages)
        }
    }

    // MARK: - Walking Speed

    private var walkingSpeedSection: some View {
        Section(OBALoc("settings_controller.walking_speed_section.title", value: "Walking Speed", comment: "Settings > Walking Speed section title")) {
            Picker(OBALoc("settings_controller.walking_speed.title", value: "Walking speed", comment: "Settings > Walking Speed section > Speed picker"), selection: $viewModel.walkingSpeed) {
                ForEach(WalkingSpeedPreset.allCases, id: \.self) { preset in
                    Text(preset.localizedTitle).tag(preset)
                }
            }
            .disabled(viewModel.walkingSpeedUsesHealthKit)
            if viewModel.isHealthKitAvailable {
                Toggle(OBALoc("settings_controller.walking_speed.use_healthkit", value: "Use Health app data", comment: "Settings > Walking Speed section > HealthKit toggle"), isOn: $viewModel.walkingSpeedUsesHealthKit)
            }
        }
    }

    // MARK: - Bike Mode

    private var bikeModeSection: some View {
        Section {
            Toggle(OBALoc("settings_controller.bike_mode.title", value: "Bike Mode", comment: "Settings > Bike Mode > on/off toggle"), isOn: $viewModel.bikeModeEnabled)
            if viewModel.isHealthKitAvailable {
                Toggle(OBALoc("settings_controller.bike_mode.use_healthkit", value: "Use Health app data", comment: "Settings > Bike Mode section > HealthKit toggle"), isOn: $viewModel.bikeSpeedUsesHealthKit)
            }
        } header: {
            Text(OBALoc("settings_controller.bike_mode_section.title", value: "Bike Mode", comment: "Settings > Bike Mode section title"))
        } footer: {
            Text(OBALoc("settings_controller.bike_mode_section.footer", value: "Uses a faster travel speed for walk-time estimates, arrival ETAs, and the Stop page.", comment: "Settings > Bike Mode section footer"))
        }
    }

    // MARK: - Surveys and Privacy

    private var surveySection: some View {
        Section(OBALoc("settings_controller.survey_section.title", value: "Surveys", comment: "Settings > Surveys section title")) {
            Toggle(OBALoc("settings_controller.survey_section.always_show_on_stops", value: "Always show on stops", comment: "Settings > Surveys section > Always show surveys on stops"), isOn: $viewModel.alwaysShowsSurveysOnStops)
        }
    }

    private var privacySection: some View {
        Section(OBALoc("settings_controller.privacy_section.title", value: "Privacy", comment: "Settings > Privacy section title")) {
            Toggle(OBALoc("settings_controller.privacy_section.reporting_enabled", value: "Send usage data to developer", comment: "Settings > Privacy section > Send usage data"), isOn: $viewModel.reportingEnabled)
        }
    }

    // MARK: - Feedback (debug only)

    private var feedbackSection: some View {
        Section {
            Toggle(OBALoc("settings_controller.feedback_section.always_show", value: "Always show feedback prompt", comment: "Settings > Feedback section > Debug toggle that bypasses the prompt's gating"), isOn: $viewModel.alwaysShowsFeedbackPrompt)
            Button(OBALoc("settings_controller.feedback_section.reset", value: "Reset feedback prompt state", comment: "Settings > Feedback section > Clears all feedback prompt bookkeeping"), action: viewModel.resetFeedbackPrompt)
        } header: {
            Text(OBALoc("settings_controller.feedback_section.title", value: "Feedback", comment: "Settings > Feedback section title"))
        } footer: {
            Text(OBALoc(
                "settings_controller.feedback_section.footer",
                value: "Resetting clears the saved prompt state but leaves this toggle turned on.",
                comment: "Settings > Feedback section > Footer noting that resetting the prompt state does not turn the debug toggle off"
            ))
        }
    }

    // MARK: - Debug

    private var debugSection: some View {
        Section(OBALoc("settings_controller.debug_section.title", value: "Debug", comment: "Settings > Debug section title")) {
            Toggle(OBALoc("settings_controller.debug_section.debug_mode", value: "Debug Mode", comment: "Settings > Debug section > Debug mode"), isOn: $viewModel.debugMode)

            if viewModel.debugMode {
                Toggle(OBALoc("settings_controller.debug_section.always_refresh_regions", value: "Refresh regions on every launch", comment: "Settings > Debug section > Refresh regions on every launch"), isOn: $viewModel.alwaysRefreshesRegionsOnLaunch)

                if viewModel.canCrash {
                    Button(action: viewModel.crashApp) {
                        HStack {
                            Text(OBALoc("more_controller.debug_section.crash_row", value: "Crash the app", comment: "Title for a button that will crash the app."))
                            Spacer()
                            Image(systemName: "chevron.forward")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }

                let pushIDTitle = OBALoc("more_controller.debug_section.push_id.title", value: "Push ID", comment: "Title for the Push Notification ID row in the More Controller")
                if let pushUserID = viewModel.pushUserID {
                    CopyableValueRow(title: pushIDTitle, value: pushUserID)
                } else {
                    LabeledContent(pushIDTitle, value: OBALoc("more_controller.debug_section.push_id.not_available", value: "Not available", comment: "This is displayed instead of the user's push ID if the value is not available."))
                }

                LabeledContent(OBALoc("settings_controller.debug_section.test_device_description", value: "Test Device Name", comment: "Settings > Debug section > Name identifying this device for test push notifications")) {
                    TextField(
                        OBALoc("settings_controller.debug_section.test_device_description.placeholder", value: "e.g. Aaron's iPhone", comment: "Placeholder example for the test device name field"),
                        text: $viewModel.testDeviceName
                    )
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                }

                Toggle(OBALoc("settings_controller.alerts_section.display_test_alerts", value: "Display test alerts", comment: "Settings > Debug section > Display test alerts"), isOn: $viewModel.displaysTestAlerts)
                    .disabled(!viewModel.hasTestDeviceName)
            }
        }
    }
}
