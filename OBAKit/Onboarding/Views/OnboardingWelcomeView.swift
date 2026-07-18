//
//  OnboardingWelcomeView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// First-run brand moment. Marked seen on "Get Started".
struct OnboardingWelcomeView: View {
    var progress: (index: Int, total: Int)?
    var advance: () -> Void

    var body: some View {
        OnboardingScaffold(
            progress: progress,
            title: String(format: OBALoc("onboarding.welcome.title_fmt", value: "Welcome to %@", comment: "Title of the first onboarding screen; the argument is the app name"), Bundle.main.appName),
            bodyText: OBALoc("onboarding.welcome.body", value: "Real-time arrivals for the buses, trains, and ferries you ride — built by transit riders, free and open source.", comment: "Body of the first onboarding screen"),
            footnote: OBALoc("onboarding.welcome.footnote", value: "Available in dozens of transit regions worldwide", comment: "Footnote of the first onboarding screen"),
            primaryTitle: OBALoc("onboarding.welcome.primary_button", value: "Get Started", comment: "Primary button on the first onboarding screen"),
            primaryAction: advance
        ) {
            OnboardingHeroCircle(systemImageName: "mappin")
                .padding(.vertical, 34)
        }
    }
}
