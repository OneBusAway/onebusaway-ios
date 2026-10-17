//
//  SceneDelegate.swift
//  App
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    /// The real `AppDelegate` owns the `Application` stack. When running unit
    /// tests, the host uses a bare `TestAppDelegate`, so this is nil and the
    /// scene simply provides an empty window.
    private var appDelegate: AppDelegate? {
        UIApplication.shared.delegate as? AppDelegate
    }

    private var obaApplication: Application? {
        appDelegate?.app
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        self.window = window
        window.makeKeyAndVisible()

        // Unit test host: no application stack to attach.
        guard let appDelegate else { return }

        let app = appDelegate.app

        if !appDelegate.hasFinishedLaunching {
            appDelegate.hasFinishedLaunching = true
            // Hand the initial scene's window to the app delegate so that single-window
            // fallbacks and legacy references continue to work.
            appDelegate.window = window

            // This builds the application's UI by calling back into applicationReloadRootInterface(_:),
            // which attaches the root view controller to the window created above.
            app.application(UIApplication.shared, didFinishLaunching: appDelegate.launchOptions)
        } else {
            // The application stack has already launched (e.g. secondary scene on iPad).
            // Directly initialize the root interface for this window.
            RootInterfaceLauncher.reloadRootInterface(application: app, window: window)
        }

        // Handle any URLs or user activities this scene was launched to handle.
        for context in connectionOptions.urlContexts {
            _ = app.application(UIApplication.shared, open: context.url, options: [:])
        }

        for activity in connectionOptions.userActivities {
            _ = app.application(UIApplication.shared, continue: activity) { _ in }
        }

        // Restore state from a preserved session user activity if no connection activities were passed.
        if connectionOptions.userActivities.isEmpty, let activity = session.stateRestorationActivity {
            _ = app.application(UIApplication.shared, continue: activity) { _ in }
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // If the disconnected scene's window was tracked by appDelegate.window,
        // point appDelegate.window to another connected window if available.
        guard let appDelegate, appDelegate.window === window else { return }

        appDelegate.window = UIApplication.shared.connectedScenes
            .lazy
            .filter { $0 !== scene }
            .compactMap { ($0 as? UIWindowScene)?.delegate as? SceneDelegate }
            .compactMap(\.window)
            .first
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Only trigger application-level activation when this is the first scene to
        // become active; skip if another scene is already in the foreground-active state.
        guard !anotherSceneIsForegroundActive(than: scene) else { return }
        obaApplication?.applicationDidBecomeActive(UIApplication.shared)
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Only resign active for the application if no other connected scenes remain active.
        guard !anotherSceneIsForegroundActive(than: scene) else { return }
        obaApplication?.applicationWillResignActive(UIApplication.shared)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let app = obaApplication else { return }
        for context in URLContexts {
            _ = app.application(UIApplication.shared, open: context.url, options: [:])
        }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        _ = obaApplication?.application(UIApplication.shared, continue: userActivity) { _ in }
    }

    func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
        userActivity(for: window?.rootViewController)
    }

    // MARK: - Private

    private func anotherSceneIsForegroundActive(than scene: UIScene) -> Bool {
        UIApplication.shared.connectedScenes.contains {
            $0 !== scene && $0.activationState == .foregroundActive
        }
    }

    private func userActivity(for viewController: UIViewController?) -> NSUserActivity? {
        guard let viewController else { return nil }

        if let activity = userActivity(for: viewController.presentedViewController) {
            return activity
        }

        if let tabBar = viewController as? UITabBarController,
           let activity = userActivity(for: tabBar.selectedViewController) {
            return activity
        }

        if let nav = viewController as? UINavigationController {
            for child in nav.viewControllers.reversed() {
                if let activity = userActivity(for: child) {
                    return activity
                }
            }
        }

        return viewController.userActivity
    }
}
