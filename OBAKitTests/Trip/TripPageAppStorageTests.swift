//
//  TripPageAppStorageTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

/// Compact mode (and reduced colors) on the trip page only work when
/// `@AppStorage` is pointed at the app-group suite via `.defaultAppStorage`.
/// Settings writes that suite; a bare `@AppStorage` reads
/// `UserDefaults.standard` and stays `false` forever.
@MainActor
@Suite(.serialized)
struct TripPageAppStorageTests {

    /// Nested the same way `TripPageRootView` wraps `TripPageView`: the modifier
    /// only reaches `@AppStorage` *below* the view it decorates.
    private struct SuiteRoot: View {
        let userDefaults: UserDefaults
        let onRead: (Bool) -> Void

        var body: some View {
            CompactModeProbe(onRead: onRead)
                .defaultAppStorage(userDefaults)
        }
    }

    private struct CompactModeProbe: View {
        @AppStorage(UserDefaultsStore.stopTripCompactModeKey) private var compactMode = false
        let onRead: (Bool) -> Void

        var body: some View {
            Color.clear
                .onAppear { onRead(compactMode) }
        }
    }

    @Test func `Compact mode AppStorage reads true from the app-group suite`() async throws {
        let suiteName = "test.stopTripCompact.\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }

        suite.set(true, forKey: UserDefaultsStore.stopTripCompactModeKey)
        UserDefaults.standard.removeObject(forKey: UserDefaultsStore.stopTripCompactModeKey)

        var seenFromSuite: Bool?
        let suiteHost = UIHostingController(rootView: SuiteRoot(userDefaults: suite) { seenFromSuite = $0 })

        var seenFromStandard: Bool?
        let standardHost = UIHostingController(rootView: CompactModeProbe { seenFromStandard = $0 })

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let parent = UIViewController()
        window.rootViewController = parent
        window.makeKeyAndVisible()

        parent.addChild(suiteHost)
        parent.view.addSubview(suiteHost.view)
        suiteHost.view.frame = CGRect(x: 0, y: 0, width: 160, height: 240)
        suiteHost.didMove(toParent: parent)

        parent.addChild(standardHost)
        parent.view.addSubview(standardHost.view)
        standardHost.view.frame = CGRect(x: 160, y: 0, width: 160, height: 240)
        standardHost.didMove(toParent: parent)

        parent.view.layoutIfNeeded()
        await Task.yield()
        await Task.yield()

        #expect(seenFromSuite == true)
        #expect(seenFromStandard == false)

        window.isHidden = true
    }
}
