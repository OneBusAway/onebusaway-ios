//
//  OnboardingScaffold.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// The ringed hero circle used at the top of onboarding screens.
struct OnboardingHeroCircle: View {
    let systemImageName: String

    var body: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.08)).frame(width: 168, height: 168)
            Circle().fill(Color.accentColor.opacity(0.14)).frame(width: 132, height: 132)
            Circle().fill(Color.accentColor).frame(width: 108, height: 108)
            Image(systemName: systemImageName)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }
}

/// Shared chrome for onboarding steps: segmented progress bar, centered
/// title/body, optional badge and footnote, and a fixed bottom button dock.
struct OnboardingScaffold<Content: View>: View {
    /// `nil` hides the progress bar (single-step mode for returning users).
    var progress: (index: Int, total: Int)?
    var badge: String?
    var title: String
    var bodyText: String?
    var footnote: String?
    var primaryTitle: String
    var primaryDisabled: Bool
    var primaryAction: () -> Void
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?
    @ViewBuilder var content: Content

    init(
        progress: (index: Int, total: Int)? = nil,
        badge: String? = nil,
        title: String,
        bodyText: String? = nil,
        footnote: String? = nil,
        primaryTitle: String,
        primaryDisabled: Bool = false,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.progress = progress
        self.badge = badge
        self.title = title
        self.bodyText = bodyText
        self.footnote = footnote
        self.primaryTitle = primaryTitle
        self.primaryDisabled = primaryDisabled
        self.primaryAction = primaryAction
        self.secondaryTitle = secondaryTitle
        self.secondaryAction = secondaryAction
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            if let progress {
                HStack(spacing: 6) {
                    ForEach(0..<progress.total, id: \.self) { index in
                        Capsule()
                            .fill(index <= progress.index ? Color.accentColor : Color(.systemGray5))
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 12)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(OBALoc("onboarding.progress.accessibility_label", value: "Onboarding progress", comment: "Accessibility label for the onboarding progress bar")))
                .accessibilityValue(Text("\(progress.index + 1)/\(progress.total)"))
            }

            ScrollView {
                VStack(spacing: 0) {
                    if let badge {
                        Text(badge)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                            .padding(.bottom, 14)
                    }

                    Text(title)
                        .font(.system(size: 32, weight: .heavy))
                        .multilineTextAlignment(.center)

                    if let bodyText {
                        Text(bodyText)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 14)
                    }

                    content
                }
                .padding(.horizontal, 28)
                .padding(.top, 40)
                .frame(maxWidth: .infinity)
            }

            VStack(spacing: 6) {
                if let footnote {
                    Text(footnote)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 10)
                }

                Button(action: primaryAction) {
                    Text(primaryTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(primaryDisabled)

                if let secondaryTitle, let secondaryAction {
                    Button(action: secondaryAction) {
                        Text(secondaryTitle)
                            .font(.headline)
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }
}

#if DEBUG
#Preview("Full flow step") {
    OnboardingScaffold(
        progress: (index: 0, total: 4),
        // swiftlint:disable:next hardcoded_app_name
        title: "Welcome to OneBusAway",
        bodyText: "Real-time arrivals for the buses, trains, and ferries you ride.",
        footnote: "Available in dozens of transit regions worldwide",
        primaryTitle: "Get Started",
        primaryAction: {}
    // swiftlint:disable:next multiple_closures_with_trailing_closure
    ) {
        OnboardingHeroCircle(systemImageName: "mappin")
            .padding(.vertical, 34)
    }
}

#Preview("Single step") {
    OnboardingScaffold(
        badge: "NEW",
        title: "Stay ahead of disruptions",
        primaryTitle: "Turn On Notifications",
        primaryAction: {},
        secondaryTitle: "Maybe Later",
        secondaryAction: {}
    // swiftlint:disable:next multiple_closures_with_trailing_closure
    ) {
        OnboardingHeroCircle(systemImageName: "bell.fill")
            .padding(.vertical, 22)
    }
}
#endif
