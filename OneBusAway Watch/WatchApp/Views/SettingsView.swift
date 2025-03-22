//
//  SettingsView.swift
//  OBAKit
//
//  Created by Prince Yadav on 06/03/25.
//


import SwiftUI
import WatchKit

struct SettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval = 30
    @AppStorage("enableNotifications") private var enableNotifications = true
    @AppStorage("enableHapticFeedback") private var enableHapticFeedback = true
    @AppStorage("syncWithPhone") private var syncWithPhone = true
    @AppStorage("darkMode") private var darkMode = false
    @AppStorage("showSeconds") private var showSeconds = false
    @AppStorage("useMockData") private var useMockData = false
    
    @EnvironmentObject private var connectivityService: WatchConnectivityService
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ScrollView {
            VStack {
                // Display Settings
                Section {
                    Toggle("Dark Mode", isOn: $darkMode)
                    Toggle("Show Seconds", isOn: $showSeconds)
                        .onChange(of: showSeconds) { newValue in
                            UserDefaults.standard.set(newValue, forKey: "showSeconds")
                        }
                } header: {
                    Text("Display").font(.headline)
                }

                // Refresh Interval
                Section {
                    Picker("Interval", selection: $refreshInterval) {
                        Text("15 sec").tag(15)
                        Text("30 sec").tag(30)
                        Text("1 min").tag(60)
                        Text("2 min").tag(120)
                    }
                    .pickerStyle(WheelPickerStyle())
                    .frame(height: 80) // Fixes layout on small watch screens
                } header: {
                    Text("Refresh Interval").font(.headline)
                }

                // Notifications Settings
                Section {
                    Toggle("Enable Notifications", isOn: $enableNotifications)
                    Toggle("Haptic Feedback", isOn: $enableHapticFeedback)
                        .disabled(!enableNotifications)
                } header: {
                    Text("Notifications").font(.headline)
                }

                // Sync Settings
                Section {
                    Toggle("Sync with iPhone", isOn: $syncWithPhone)
                        .onChange(of: syncWithPhone) { newValue in
                            if newValue {
                                connectivityService.requestFavoritesFromPhone()
                            }
                        }
                    
                    Button("Sync Now") {
                        connectivityService.requestFavoritesFromPhone()
                        WKInterfaceDevice.current().play(.click)
                    }
                    .disabled(!syncWithPhone || !connectivityService.isReachable)
                } header: {
                    Text("Sync").font(.headline)
                }

                // Development
                Section {
                    Toggle("Use Mock Data", isOn: $useMockData)
                        .onChange(of: useMockData) { newValue in
                            UserDefaults.standard.set(newValue, forKey: "useMockData")
                        }
                } header: {
                    Text("Development").font(.headline)
                }

                // About Section
                Section {
                    VStack {
                        Text("OneBusAway Watch").font(.headline)
                        Text("Version 1.0.0").font(.footnote).foregroundColor(.secondary)
                        
                        Link(destination: URL(string: "https://onebusaway.org")!) {
                            HStack {
                                Text("Visit Website")
                                Image(systemName: "arrow.up.right.square")
                            }
                        }
                    }
                } header: {
                    Text("About").font(.headline)
                }
            }
        }
        .navigationTitle("Settings")
        .environment(\.colorScheme, darkMode ? .dark : colorScheme)
    }
}

// MARK: - Preview
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(WatchConnectivityService.shared)
            .previewDevice("Apple Watch Series 7 (45mm)")
    }
}

