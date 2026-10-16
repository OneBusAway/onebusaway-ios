//
//  TestWindowScene.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import UIKit

/// The test host's window scene, for tests that need a window on screen.
///
/// A bare `UIWindow(frame:)` lays out but never reaches the render server in the
/// scene-based host, so animations, `drawHierarchy` and MapKit's annotation views
/// need a scene-attached one.
@MainActor
func testWindowScene() throws -> UIWindowScene {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return try #require(
        scenes.first { $0.activationState == .foregroundActive } ?? scenes.first,
        "No UIWindowScene in the test host."
    )
}
