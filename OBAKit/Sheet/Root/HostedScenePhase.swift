//
//  HostedScenePhase.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit

/// The `scenePhase` SwiftUI can't supply in this app.
///
/// SwiftUI sets `EnvironmentValues.scenePhase` for the scenes it declares itself
/// (`App`, `WindowGroup`). This app runs the UIKit life cycle, so a view inside a
/// `UIHostingController` reads the default, `.background`, for good: `onChange(of:
/// scenePhase)` never fires, and nothing keyed to returning to the app runs. That
/// silently disabled the map panel's recenter after a long absence and its weather
/// refresh, and `RefreshesOnForeground` / `KeepsScreenAwake` in its sheets.
///
/// This follows the hosting scene through UIKit's `UIScene` notifications instead;
/// `hostedScenePhase(_:)` writes it into the environment, which is settable.
@MainActor
final class HostedScenePhase: ObservableObject {
    @Published private(set) var phase: ScenePhase

    /// Notifications from other scenes (another iPad window) are ignored once a scene
    /// is attached. Weak: the scene owns the window that owns the host.
    private weak var scene: UIScene?
    private let notificationCenter: NotificationCenter
    private var observers: [NSObjectProtocol] = []

    init(notificationCenter: NotificationCenter = .default, initialPhase: ScenePhase) {
        self.notificationCenter = notificationCenter
        self.phase = initialPhase

        let transitions: [(Notification.Name, ScenePhase)] = [
            (UIScene.didActivateNotification, .active),
            (UIScene.willDeactivateNotification, .inactive),
            (UIScene.didEnterBackgroundNotification, .background),
            (UIScene.willEnterForegroundNotification, .inactive)
        ]
        observers = transitions.map { name, phase in
            notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let sender = (note.object as AnyObject?).map(ObjectIdentifier.init)
                MainActor.assumeIsolated { self?.receive(phase, from: sender) }
            }
        }
    }

    isolated deinit {
        for observer in observers { notificationCenter.removeObserver(observer) }
    }

    /// Follows only `scene` from now on, starting from its current state.
    func attach(to scene: UIScene?) {
        self.scene = scene
        if let scene {
            phase = Self.phase(for: scene.activationState)
        }
    }

    /// The phase to start from before a scene is attached.
    static func phase(for state: UIApplication.State) -> ScenePhase {
        switch state {
        case .active: .active
        case .inactive: .inactive
        case .background: .background
        @unknown default: .background
        }
    }

    static func phase(for state: UIScene.ActivationState) -> ScenePhase {
        switch state {
        case .foregroundActive: .active
        case .foregroundInactive: .inactive
        case .background, .unattached: .background
        @unknown default: .background
        }
    }

    private func receive(_ newPhase: ScenePhase, from sender: ObjectIdentifier?) {
        if let scene, let sender, sender != ObjectIdentifier(scene) { return }
        if phase != newPhase {
            phase = newPhase
        }
    }
}

struct HostedScenePhaseModifier: ViewModifier {
    @ObservedObject var tracker: HostedScenePhase

    func body(content: Content) -> some View {
        content.environment(\.scenePhase, tracker.phase)
    }
}

extension View {
    /// Gives this view tree the hosting scene's real `scenePhase`. Apply it at the root
    /// of a `UIHostingController`; see `HostedScenePhase`.
    func hostedScenePhase(_ tracker: HostedScenePhase) -> some View {
        modifier(HostedScenePhaseModifier(tracker: tracker))
    }
}
