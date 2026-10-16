//
//  AppDelegate.swift
//  App
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKit
import OBAKitCore

final class AppDelegate: UIResponder, UIApplicationDelegate, ApplicationDelegate {

    /// Set by the `SceneDelegate` once its window is created. The root view
    /// controller is attached to this window in `applicationReloadRootInterface(_:)`.
    var window: UIWindow?

    /// The application stack. Created in `init()` and consumed by the `SceneDelegate`.
    let app: Application

    /// Launch options captured in `application(_:didFinishLaunchingWithOptions:)`, so the
    /// `SceneDelegate` can forward them when it finishes launching the app.
    var launchOptions: [AnyHashable: Any] = [:]

    /// Tracks whether the app stack has been launched by a scene delegate.
    var hasFinishedLaunching = false

    private let userDefaults: UserDefaults
    private var rootController: UIViewController?

    override init() {
        URLCache.shared = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 20 * 1024 * 1024, diskPath: nil)

        let appGroup = Bundle.main.appGroup
        assert(appGroup != nil, "OBAKitConfig.AppGroup is missing from Info.plist")

        userDefaults = UserDefaults(suiteName: appGroup) ?? .standard
        userDefaults.register(defaults: [
            AnalyticsKeys.reportingEnabledUserDefaultsKey: true
        ])

        // If you need to debug a user's UserDefaults data, drop the XML file they provide into Xcode's Project Navigator
        // with the name "userdefaults.xml". Then, uncomment this section.
        // if let url = Bundle.main.url(forResource: "userdefaults", withExtension: "xml"),
        //    let data = try? Data(contentsOf: url),
        //    let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
        //     userDefaults.register(defaults: plist)
        // }

        let appConfig = AppConfig(appBundle: .main, userDefaults: userDefaults, analytics: nil)
        appConfig.appShortcutsProvider = OBAAppShortcuts.self

        app = Application(config: appConfig)

        super.init()

        app.delegate = self
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // The window, root interface, and active/resign lifecycle now live in
        // SceneDelegate, which forwards these launch options to the app stack.
        self.launchOptions = launchOptions ?? [:]

        return true
    }

    // MARK: - ApplicationDelegate

    var uiApplication: UIApplication? {
        UIApplication.shared
    }

    var isIdleTimerDisabled: Bool {
        get { UIApplication.shared.isIdleTimerDisabled }
        set { UIApplication.shared.isIdleTimerDisabled = newValue }
    }

    var isRegisteredForRemoteNotifications: Bool {
        UIApplication.shared.isRegisteredForRemoteNotifications
    }

    func applicationReloadRootInterface(_ application: Application) {
        var reloadedAnyScene = false

        for case let windowScene as UIWindowScene in UIApplication.shared.connectedScenes {
            guard let window = (windowScene.delegate as? SceneDelegate)?.window ?? windowScene.windows.first else {
                continue
            }

            reloadedAnyScene = true
            RootInterfaceLauncher.reloadRootInterface(application: application, window: window) { [weak self] in
                let controller = ApplicationRootControllerFactory.make(application: application)
                window.rootViewController = controller
                if window === self?.window {
                    self?.rootController = controller
                }
            }
        }

        if !reloadedAnyScene, let window {
            RootInterfaceLauncher.reloadRootInterface(application: application, window: window) { [weak self] in
                let controller = ApplicationRootControllerFactory.make(application: application)
                self?.rootController = controller
                window.rootViewController = controller
            }
        }
    }

    func canOpenURL(_ url: URL) -> Bool {
        UIApplication.shared.canOpenURL(url)
    }

    func open(_ url: URL, options: [UIApplication.OpenExternalURLOptionsKey: Any], completionHandler completion: ((Bool) -> Void)?) {
        // `completion` comes through an Objective-C-era protocol that doesn't mark it
        // `@Sendable`, so it can't go to UIKit's completion handler directly. The
        // task stays on the main actor, where the callback has always run.
        Task {
            let opened = await UIApplication.shared.open(url, options: options)
            completion?(opened)
        }
    }
}
