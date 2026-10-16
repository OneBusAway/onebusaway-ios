//
//  RootInterfaceLauncher.swift
//  App
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKit

/// Shared launch glue for all white-label apps: evaluates the onboarding flow and either
/// installs it as the window's root (handing off to `showRootController` when the user
/// finishes) or calls `showRootController` immediately when no onboarding is needed.
enum RootInterfaceLauncher {
    static func reloadRootInterface(
        application: Application,
        window: UIWindow,
        showRootController: @escaping () -> Void
    ) {
        OnboardingFlowController.evaluate(application: application) { onboarding in
            guard let onboarding else {
                showRootController()
                application.rootUserInterfaceDidLoad()
                return
            }

            onboarding.onFinished = {
                // The hierarchy change belongs inside the animations block so the
                // transition captures the correct before/after snapshots.
                UIView.transition(with: window, duration: 0.5, options: .transitionFlipFromLeft) {
                    showRootController()
                } completion: { _ in
                    application.rootUserInterfaceDidLoad()
                }
            }
            window.rootViewController = onboarding
        }
    }
}
