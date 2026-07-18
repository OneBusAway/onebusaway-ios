//
//  OnboardingDoneView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UserNotifications

/// Final recap screen. Rows reflect the user's actual choices.
struct OnboardingDoneView: View {
    var progress: (index: Int, total: Int)?
    var regionName: String?
    var locationEnabled: Bool
    var advance: () -> Void

    @State private var alertsEnabled = false

    private var onLabel: String { OBALoc("onboarding.done.value_on", value: "On", comment: "Recap value for an enabled setting") }
    private var offLabel: String { OBALoc("onboarding.done.value_off", value: "Off", comment: "Recap value for a disabled setting") }

    var body: some View {
        OnboardingScaffold(
            progress: progress,
            title: OBALoc("onboarding.done.title", value: "You're all set", comment: "Title of the final onboarding screen"),
            bodyText: regionName.map {
                String(format: OBALoc("onboarding.done.body_fmt", value: "%@ is ready. Let's find your bus.", comment: "Body of the final onboarding screen; the argument is a region name"), $0)
            },
            primaryTitle: OBALoc("onboarding.done.primary_button", value: "Start Exploring", comment: "Primary button on the final onboarding screen"),
            primaryAction: advance
        ) {
            OnboardingHeroCircle(systemImageName: "checkmark")
                .padding(.vertical, 30)

            VStack(spacing: 0) {
                recapRow(
                    label: OBALoc("onboarding.done.region_row", value: "Region", comment: "Recap row label for the chosen region"),
                    value: regionName ?? offLabel)
                Divider()
                recapRow(
                    label: OBALoc("onboarding.done.location_row", value: "Location", comment: "Recap row label for location permission"),
                    value: locationEnabled ? onLabel : offLabel)
                Divider()
                recapRow(
                    label: OBALoc("onboarding.done.alerts_row", value: "Alerts", comment: "Recap row label for notification permission"),
                    value: alertsEnabled ? onLabel : offLabel)
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
            .padding(.top, 10)
        }
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            alertsEnabled = settings.authorizationStatus == .authorized
        }
    }

    private func recapRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .accessibilityElement(children: .combine)
    }
}
