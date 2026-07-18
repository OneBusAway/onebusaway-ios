//
//  OnboardingNotificationsView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import UserNotifications
import OBAKitCore

/// Pitches region-wide service-alert notifications, then triggers the OS permission prompt.
///
/// Requests authorization directly (not via `PushService.pushID()`, whose callback never fires
/// on denial and would hang the flow). On grant it calls `registerForRemoteNotifications()`;
/// the resulting device token still flows through the existing AppDelegate → PushService wiring.
struct OnboardingNotificationsView: View {
    var progress: (index: Int, total: Int)?
    var advance: () -> Void

    /// The flow container passes `progress: nil` exactly when this step appears alone
    /// (returning-user mode), so single-step presentation is derived, not a second flag.
    private var isSingleStep: Bool { progress == nil }

    @State private var isRequesting = false

    private struct ExampleAlert: Identifiable {
        let id = UUID()
        let color: Color
        let text: String
    }

    private var exampleAlerts: [ExampleAlert] {
        [
            ExampleAlert(color: .red, text: OBALoc("onboarding.notifications.example_storm", value: "Winter storm — reduced service on 12 routes", comment: "Example service alert shown on the notifications onboarding screen")),
            ExampleAlert(color: .blue, text: OBALoc("onboarding.notifications.example_ferry", value: "Ferry delays: up to 40 minute waits", comment: "Example service alert shown on the notifications onboarding screen")),
            ExampleAlert(color: .orange, text: OBALoc("onboarding.notifications.example_event", value: "Big game today: extra trains to the stadium", comment: "Example service alert shown on the notifications onboarding screen"))
        ]
    }

    var body: some View {
        OnboardingScaffold(
            progress: progress,
            badge: isSingleStep ? OBALoc("onboarding.notifications.new_badge", value: "NEW", comment: "Badge shown when the notifications step appears alone for existing users") : nil,
            title: OBALoc("onboarding.notifications.title", value: "Stay ahead of disruptions", comment: "Title of the notifications onboarding screen"),
            bodyText: OBALoc("onboarding.notifications.body", value: "Get notified about region-wide service alerts — ice storms, flooding, and major events that change how transit runs.", comment: "Body of the notifications onboarding screen"),
            footnote: isSingleStep ? nil : OBALoc("onboarding.notifications.footnote", value: "Only major, region-wide alerts. No spam — you control the rest in Settings.", comment: "Footnote of the notifications onboarding screen"),
            primaryTitle: OBALoc("onboarding.notifications.primary_button", value: "Turn On Notifications", comment: "Primary button on the notifications onboarding screen"),
            primaryAction: requestAuthorization,
            secondaryTitle: isSingleStep
                ? OBALoc("onboarding.notifications.maybe_later_button", value: "Maybe Later", comment: "Decline button when the notifications step appears alone")
                : OBALoc("onboarding.notifications.not_now_button", value: "Not Now", comment: "Decline button on the notifications onboarding screen"),
            secondaryAction: advance
        ) {
            OnboardingHeroCircle(systemImageName: "bell.fill")
                .padding(.vertical, 22)

            VStack(spacing: 9) {
                ForEach(exampleAlerts) { alert in
                    HStack(spacing: 11) {
                        Circle().fill(alert.color).frame(width: 9, height: 9)
                        Text(alert.text)
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 13))
                }
            }
            .padding(.top, 22)
        }
        .disabled(isRequesting)
    }

    private func requestAuthorization() {
        isRequesting = true
        Task { @MainActor in
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } catch {
                Logger.error("Onboarding notification authorization failed: \(error)")
            }
            isRequesting = false
            advance()
        }
    }
}
