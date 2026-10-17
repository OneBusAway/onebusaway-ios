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
/// installs it as the window's root (switching to the app's root controller when the user
/// finishes) or installs the root controller immediately when no onboarding is needed.
enum RootInterfaceLauncher {

    /// Reloads every connected scene's window, or `fallbackWindow` when no scene has one
    /// yet. Backs `ApplicationDelegate.applicationReloadRootInterface(_:)`.
    static func reloadAllScenes(application: Application, fallbackWindow: UIWindow?) {
        var reloadedAnyScene = false

        for case let windowScene as UIWindowScene in UIApplication.shared.connectedScenes {
            guard let window = (windowScene.delegate as? SceneDelegate)?.window ?? windowScene.windows.first else {
                continue
            }

            reloadedAnyScene = true
            reloadRootInterface(application: application, window: window)
        }

        if !reloadedAnyScene, let fallbackWindow {
            reloadRootInterface(application: application, window: fallbackWindow)
        }
    }

    static func reloadRootInterface(application: Application, window: UIWindow) {
        let showRootController = {
            window.rootViewController = ApplicationRootControllerFactory.make(application: application)
        }

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
