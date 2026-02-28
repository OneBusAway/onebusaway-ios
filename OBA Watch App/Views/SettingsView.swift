import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: WatchAppState
    @AppStorage("watch_selected_region_id", store: WatchAppState.userDefaults) private var selectedRegionID: String = "mta-new-york"
    
    // Location
    @AppStorage("watch_share_current_location", store: WatchAppState.userDefaults) private var shareCurrentLocation: Bool = true

    // Agency Alerts
    @AppStorage("watch_display_test_alerts", store: WatchAppState.userDefaults) private var displayTestAlerts: Bool = false

    // Accessibility
    @AppStorage("watch_haptic_on_reload", store: WatchAppState.userDefaults) private var hapticOnReload: Bool = false
    @AppStorage("watch_always_show_full_sheet_voice", store: WatchAppState.userDefaults) private var alwaysShowFullSheetVoice: Bool = false

    // Debug
    @AppStorage("watch_debug_mode", store: WatchAppState.userDefaults) private var debugMode: Bool = false

    // Privacy
    @AppStorage("watch_send_usage_data", store: WatchAppState.userDefaults) private var sendUsageData: Bool = true

    var body: some View {
        List {
            Section(OBALoc("settings.section.region", value: "Region", comment: "Settings section: Region")) {
                NavigationLink {
                    ChooseRegionView()
                } label: {
                    HStack {
                        Text(OBALoc("settings.choose_region", value: "Choose Region", comment: "Choose region button"))
                        Spacer()
                        Text(WatchAppState.regions.first(where: { $0.id == selectedRegionID })?.name ?? OBALoc("common.unknown", value: "Unknown", comment: "Unknown value"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section(OBALoc("settings.section.map", value: "Map", comment: "Settings section: Map")) {
                Toggle(OBALoc("settings.map.shows_scale", value: "Shows scale", comment: "Toggle label"), isOn: $appState.showsScale)
                Toggle(OBALoc("settings.map.shows_traffic", value: "Shows traffic", comment: "Toggle label"), isOn: $appState.showsTraffic)
                Toggle(OBALoc("settings.map.current_heading", value: "Show my current heading", comment: "Toggle label"), isOn: $appState.showsCurrentHeading)
            }

            Section(OBALoc("settings.section.location", value: "Location", comment: "Settings section: Location")) {
                Toggle(OBALoc("settings.location.share_current", value: "Share current location", comment: "Toggle label"), isOn: $shareCurrentLocation)
            }

            Section(OBALoc("settings.section.agency_alerts", value: "Agency Alerts", comment: "Settings section: Agency Alerts")) {
                Toggle(OBALoc("settings.alerts.display_test", value: "Display test alerts", comment: "Toggle label"), isOn: $displayTestAlerts)
            }

            Section(OBALoc("settings.section.accessibility", value: "Accessibility", comment: "Settings section: Accessibility")) {
                Toggle(OBALoc("settings.accessibility.haptic_on_reload", value: "Haptic feedback on reload", comment: "Toggle label"), isOn: $hapticOnReload)
                Toggle(OBALoc("settings.accessibility.full_sheet_voice", value: "Always show full sheet on VoiceOver", comment: "Toggle label"), isOn: $alwaysShowFullSheetVoice)
                Toggle(OBALoc("settings.accessibility.route_labels", value: "Show route labels on the map", comment: "Toggle label"), isOn: $appState.showRouteLabels)
            }

            Section(OBALoc("settings.section.debug", value: "Debug", comment: "Settings section: Debug")) {
                Toggle(OBALoc("settings.debug.mode", value: "Debug Mode", comment: "Toggle label"), isOn: $debugMode)
            }

            Section(OBALoc("settings.section.privacy", value: "Privacy", comment: "Settings section: Privacy")) {
                Toggle(OBALoc("settings.privacy.send_usage", value: "Send usage data to developer", comment: "Toggle label"), isOn: $sendUsageData)
            }
        }
        .navigationTitle(OBALoc("common.settings", value: "Settings", comment: "Settings title"))
    }
}

struct ChooseRegionView: View {
    @EnvironmentObject var appState: WatchAppState
    @AppStorage("watch_selected_region_id", store: WatchAppState.userDefaults) private var selectedRegionID: String = "mta-new-york"
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        List {
            ForEach(WatchAppState.regions.filter { $0.obaBaseURL != nil }) { region in
                Button {
                    appState.updateRegion(id: region.id)
                    dismiss()
                } label: {
                    HStack {
                        Text(region.name)
                        Spacer()
                        if region.id == selectedRegionID {
                            Image(systemName: "checkmark")
                                .foregroundColor(.green)
                        }
                    }
                }
            }
        }
        .navigationTitle(OBALoc("settings.choose_region", value: "Choose Region", comment: "Choose region title"))
    }
}

#Preview {
    SettingsView()
        .environmentObject(WatchAppState.shared)
}
