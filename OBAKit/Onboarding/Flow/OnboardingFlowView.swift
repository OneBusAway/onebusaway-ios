//
//  OnboardingFlowView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Renders a computed onboarding flow. Advancing past a step marks it seen (unless the
/// step opted out via `tracksSeen`); finishing the last step calls `onFinished`, which
/// hands control back to the app's root UI.
struct OnboardingFlowView: View {
    let application: Application
    let steps: [OnboardingStep]
    let store: OnboardingStepStore
    let onFinished: () -> Void

    @StateObject private var regionPickerCoordinator: RegionPickerCoordinator
    @State private var index = 0

    init(application: Application, steps: [OnboardingStep], store: OnboardingStepStore, onFinished: @escaping () -> Void) {
        self.application = application
        self.steps = steps
        self.store = store
        self.onFinished = onFinished
        self._regionPickerCoordinator = StateObject(wrappedValue: RegionPickerCoordinator(regionsService: application.regionsService))
    }

    /// Single-step mode: no progress bar; step views may adapt further
    /// (see `OnboardingNotificationsView`'s NEW badge and "Maybe Later" copy).
    private var isSingleStep: Bool { steps.count == 1 }

    private var progress: (index: Int, total: Int)? {
        isSingleStep ? nil : (index: index, total: steps.count)
    }

    var body: some View {
        NavigationStack {
            stepView(for: steps[index])
                .toolbar(.hidden, for: .navigationBar)
        }
        .environment(\.coreApplication, application)
        .id(steps[index].id)
        .animation(.default, value: index)
    }

    @ViewBuilder
    private func stepView(for step: OnboardingStep) -> some View {
        switch step.id {
        case .migration:
            DataMigrationView(dismissBlock: { advance() })
        case .welcome:
            OnboardingWelcomeView(progress: progress, advance: { advance() })
        case .location:
            OnboardingLocationView(progress: progress, regionProvider: regionPickerCoordinator, advance: { advance() })
        case .region:
            OnboardingRegionView(progress: progress, regionProvider: regionPickerCoordinator, advance: { advance() })
        case .notifications:
            OnboardingNotificationsView(progress: progress, advance: { advance() })
        case .done:
            OnboardingDoneView(
                progress: progress,
                regionName: regionPickerCoordinator.currentRegion?.name,
                locationEnabled: application.locationService.isLocationUseAuthorized,
                advance: { advance() })
        }
    }

    private func advance() {
        let step = steps[index]
        if step.tracksSeen {
            store.markSeen(step.id, version: step.version)
        }

        if index + 1 < steps.count {
            index += 1
        } else {
            onFinished()
        }
    }
}
