//
//  OnboardingFlowControllerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import SwiftUI
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

/// Tests for `OnboardingFlowController`. `evaluate(application:completion:)` is
/// covered in `ApplicationTests`.
@MainActor
@Suite(.serialized)
final class OnboardingFlowControllerTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    /// The flow view calls its completion from the last step's button, which a
    /// double-tap can press twice before the controller goes away. The test calls
    /// the completion the controller handed its hosted view, so it runs through the
    /// same closure a real tap does.
    @Test func `Finishing the flow twice calls onFinished once`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let controller = OnboardingFlowController(
            application: application,
            steps: OnboardingRegistry.steps,
            store: OnboardingStepStore(userDefaults: application.userDefaults)
        )
        var finishedCount = 0
        controller.onFinished = { finishedCount += 1 }

        controller.loadViewIfNeeded()
        let host = try #require(controller.children.first as? UIHostingController<OnboardingFlowView>)

        // The completion captures the controller weakly, and Swift doesn't promise
        // a local outlives its last use.
        withExtendedLifetime(controller) {
            host.rootView.onFinished()
            #expect(finishedCount == 1)

            host.rootView.onFinished()
            #expect(finishedCount == 1)
        }
    }
}
