//
//  OnboardingLocationView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Primes the user before the OS location prompt.
///
/// One button, and it always raises the system prompt: App Review rejects a
/// pre-permission screen that lets the user dismiss it without reaching the
/// prompt (guideline 5.1.1(iv); 24.3 and 26.4 were both rejected for it). The
/// rider declines in the system prompt instead, and the region step that
/// follows lets them pick a region by hand.
struct OnboardingLocationView<Provider: RegionProvider>: View {
    var progress: (index: Int, total: Int)?
    @ObservedObject var regionProvider: Provider
    var advance: () -> Void

    @Environment(\.coreApplication) var application

    var body: some View {
        OnboardingScaffold(
            progress: progress,
            title: OBALoc("onboarding.location.title", value: "See transit around you", comment: "Title of the location onboarding screen"),
            footnote: String(format: OBALoc("onboarding.location.footnote_fmt", value: "%@ only uses your location while the app is open. Change this anytime in Settings.", comment: "Footnote of the location onboarding screen; the argument is the app name"), Bundle.main.appName),
            primaryTitle: Strings.continue,
            primaryAction: {
                regionProvider.automaticallySelectRegion = true
                application.locationService.requestInUseAuthorization()
                advance()
            }
        // swiftlint:disable:next multiple_closures_with_trailing_closure
        ) {
            OnboardingHeroCircle(systemImageName: "location.fill")
                .padding(.vertical, 30)

            VStack(alignment: .leading, spacing: 14) {
                benefitRow(
                    heading: OBALoc("onboarding.location.benefit_nearby_title", value: "See nearby stops", comment: "Heading for a benefit of granting location access"),
                    detail: OBALoc("onboarding.location.benefit_nearby_body", value: "Buses and trains around you, ranked by distance.", comment: "Detail for the nearby-stops benefit"))
                benefitRow(
                    heading: OBALoc("onboarding.location.benefit_map_title", value: "Center the map on you", comment: "Heading for a benefit of granting location access"),
                    detail: OBALoc("onboarding.location.benefit_map_body", value: "Open straight to your surroundings — no searching.", comment: "Detail for the map-centering benefit"))
            }
            .padding(.top, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func benefitRow(heading: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 30, height: 30)
                .overlay(Circle().fill(Color.accentColor).frame(width: 8, height: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(heading).font(.callout.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
