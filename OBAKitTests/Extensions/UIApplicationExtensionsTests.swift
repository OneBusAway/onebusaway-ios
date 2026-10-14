//
//  UIApplicationExtensionsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UIKit
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class UIApplicationExtensionsTests {

    @Test func `Active windows only includes windows from foreground active window scenes`() {
        let app = UIApplication.shared
        let expectedWindows = app.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap { $0.windows }

        #expect(app.activeWindows == expectedWindows)
    }

    @Test func `Key window from scene matches key window from active or connected scenes`() {
        let app = UIApplication.shared
        let expectedKeyWindow = app.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap { $0.windows }
            .first(where: \.isKeyWindow)
            ?? app.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: \.isKeyWindow)

        #expect(app.keyWindowFromScene == expectedKeyWindow)
    }
}
