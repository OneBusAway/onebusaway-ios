//
//  TaskControllerTests.swift
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
@testable import OBAKitCore

private struct LoadFailure: Error, Equatable {
    let reason: String
}

/// A `TaskController` whose load is a closure, and which records what
/// `updateUI` could see each time it ran.
private final class ProbeController: TaskController<[String]> {
    var load: () async throws -> [String] = { [] }
    var onUpdateUI: (() -> Void)?
    private(set) var seenByUpdateUI: [(data: [String]?, error: Error?)] = []

    override func loadData() async throws -> [String] {
        try await load()
    }

    override func updateUI() {
        seenByUpdateUI.append((data, error))
        onUpdateUI?()
    }
}

/// The base loader behind the Agencies, Add Bookmark and Report Problem screens.
/// Each test awaits the load the controller itself starts in `viewDidLoad`.
@Suite(.serialized, .timeLimit(.minutes(1)))
final class TaskControllerTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    private func buildController() -> ProbeController {
        let loader = MockDataLoader(testName: name)
        Fixtures.stubAllAgencyAlerts(dataLoader: loader)
        return ProbeController(application: buildApplication(queue: queue, dataLoader: loader))
    }

    /// Loads the view, which starts the controller's load, and returns once `updateUI` runs.
    private func loadViewAndAwaitUpdate(_ controller: ProbeController) async {
        await withCheckedContinuation { continuation in
            controller.onUpdateUI = {
                controller.onUpdateUI = nil
                continuation.resume()
            }
            controller.loadViewIfNeeded()
        }
    }

    @Test func `A successful load exposes the data and updates the UI once, with the data in place`() async throws {
        let controller = buildController()
        controller.load = { ["Metro Transit", "Sound Transit"] }
        #expect(controller.data == nil)

        await loadViewAndAwaitUpdate(controller)

        #expect(controller.data == ["Metro Transit", "Sound Transit"])
        #expect(controller.error == nil)

        let update = try #require(controller.seenByUpdateUI.only)
        #expect(update.data == ["Metro Transit", "Sound Transit"])
        #expect(update.error == nil)
    }

    @Test func `A failed load exposes the error and no data`() async throws {
        let controller = buildController()
        controller.load = { throw LoadFailure(reason: "offline") }

        await loadViewAndAwaitUpdate(controller)

        #expect(controller.data == nil)
        #expect(controller.error as? LoadFailure == LoadFailure(reason: "offline"))

        let update = try #require(controller.seenByUpdateUI.only)
        #expect(update.data == nil)
        #expect(update.error as? LoadFailure == LoadFailure(reason: "offline"))
    }
}

private extension Array {
    /// The single element, or `nil` if there are zero or several.
    var only: Element? { count == 1 ? first : nil }
}
