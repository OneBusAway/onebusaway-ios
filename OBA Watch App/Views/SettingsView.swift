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
            Section("Region") {
                NavigationLink {
                    ChooseRegionView()
                } label: {
                    HStack {
                        Text("Choose Region")
                        Spacer()
                        Text(WatchAppState.regions.first(where: { $0.id == selectedRegionID })?.name ?? "Unknown")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section("Map") {
                Toggle("Shows scale", isOn: $appState.showsScale)
                Toggle("Shows traffic", isOn: $appState.showsTraffic)
                Toggle("Show my current heading", isOn: $appState.showsCurrentHeading)
            }

            Section("Location") {
                Toggle("Share current location", isOn: $shareCurrentLocation)
            }

            Section("Agency Alerts") {
                Toggle("Display test alerts", isOn: $displayTestAlerts)
            }

            Section("Accessibility") {
                Toggle("Haptic feedback on reload", isOn: $hapticOnReload)
                Toggle("Always show full sheet on VoiceOver", isOn: $alwaysShowFullSheetVoice)
                Toggle("Show route labels on the map", isOn: $appState.showRouteLabels)
            }

            Section("Debug") {
                Toggle("Debug Mode", isOn: $debugMode)
            }

            Section("Privacy") {
                Toggle("Send usage data to developer", isOn: $sendUsageData)
            }
        }
        .navigationTitle("Settings")
    }
}

struct ChooseRegionView: View {
    @EnvironmentObject var appState: WatchAppState
    @AppStorage("watch_selected_region_id", store: WatchAppState.userDefaults) private var selectedRegionID: String = "mta-new-york"
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        List {
            ForEach(WatchAppState.regions) { region in
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
        .navigationTitle("Choose Region")
    }
}

#Preview {
    SettingsView()
        .environmentObject(WatchAppState.shared)
}
