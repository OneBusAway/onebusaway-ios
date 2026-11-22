//
//  HostedScenePhaseTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import Testing
@testable import OBAKit

@MainActor
@Suite(.serialized)
struct HostedScenePhaseTests {
    private let center = NotificationCenter()

    @Test(arguments: [
        (UIScene.didActivateNotification, ScenePhase.active),
        (UIScene.willDeactivateNotification, ScenePhase.inactive),
        (UIScene.didEnterBackgroundNotification, ScenePhase.background),
        (UIScene.willEnterForegroundNotification, ScenePhase.inactive)
    ])
    func `scene notifications set the phase`(name: Notification.Name, phase: ScenePhase) {
        let tracker = HostedScenePhase(notificationCenter: center, initialPhase: phase == .active ? .background : .active)
        center.post(name: name, object: nil)
        #expect(tracker.phase == phase)
    }

    @Test func `a round trip through the background ends active`() {
        let tracker = HostedScenePhase(notificationCenter: center, initialPhase: .active)
        for name in [UIScene.willDeactivateNotification, UIScene.didEnterBackgroundNotification,
                     UIScene.willEnterForegroundNotification, UIScene.didActivateNotification] {
            center.post(name: name, object: nil)
        }
        #expect(tracker.phase == .active)
    }

    @Test func `another scene's notifications are ignored once attached`() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first)
        let tracker = HostedScenePhase(notificationCenter: center, initialPhase: .active)
        tracker.attach(to: scene)
        let phaseAfterAttach = tracker.phase

        // Some other object posing as another window's scene.
        center.post(name: UIScene.didEnterBackgroundNotification, object: NSObject())
        #expect(tracker.phase == phaseAfterAttach)

        center.post(name: UIScene.didEnterBackgroundNotification, object: scene)
        #expect(tracker.phase == .background)
    }

    @Test(arguments: [
        (UIScene.ActivationState.foregroundActive, ScenePhase.active),
        (.foregroundInactive, .inactive),
        (.background, .background),
        (.unattached, .background)
    ])
    func `activation states map to phases`(state: UIScene.ActivationState, phase: ScenePhase) {
        #expect(HostedScenePhase.phase(for: state) == phase)
    }

    /// The bug this fixes: a SwiftUI view in a `UIHostingController` under the UIKit
    /// life cycle reads `.background` forever. Through the modifier it reads the
    /// tracker's phase, and follows it.
    @Test func `views under the modifier read the tracked phase`() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let tracker = HostedScenePhase(notificationCenter: center, initialPhase: .active)
        let recorder = PhaseRecorder()
        let host = UIHostingController(rootView: PhaseReader(recorder: recorder).hostedScenePhase(tracker))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }

        try await waitUntil { recorder.last == .active }
        #expect(recorder.last == .active)

        center.post(name: UIScene.didEnterBackgroundNotification, object: nil)
        try await waitUntil { recorder.last == .background }
        #expect(recorder.last == .background)

        center.post(name: UIScene.didActivateNotification, object: nil)
        try await waitUntil { recorder.last == .active }
        #expect(recorder.last == .active)
    }

    /// The cause, kept as a control: without the modifier a hosted view reads
    /// `.background` even in a foreground scene. If this ever fails, SwiftUI has
    /// started supplying the phase itself and `HostedScenePhase` can go.
    @Test func `without the modifier a hosted view reads background`() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let recorder = PhaseRecorder()
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: PhaseReader(recorder: recorder))
        window.isHidden = false
        defer { window.isHidden = true }

        try await waitUntil { recorder.last != nil }
        #expect(recorder.last == .background)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
private final class PhaseRecorder {
    var last: ScenePhase?
}

private struct PhaseReader: View {
    @Environment(\.scenePhase) private var scenePhase
    let recorder: PhaseRecorder

    var body: some View {
        Color.clear.onChange(of: scenePhase, initial: true) { _, phase in
            recorder.last = phase
        }
    }
}
