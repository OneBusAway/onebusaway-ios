//
//  MoreSheetHostTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Smoke-tests for the UIKit wiring wrapper around `MoreViewController`.
/// The wrapping is the entire product surface of `MoreSheetHost`, so these
/// tests drive the representable through its `internal`
/// `makeNavigationController(application:)` factory seam and inspect the
/// resulting controller hierarchy — no `UIHostingController` needed.
@Suite(.serialized)
final class MoreSheetHostTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    @Test @MainActor
    func `Make navigation controller wraps more view controller in nav`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let nav = MoreSheetHost.makeNavigationController(application: application)

        #expect(nav.viewControllers.count == 1)
        #expect(nav.topViewController is MoreViewController)
    }

    /// On iOS 26 the sheet's Liquid Glass shows through the screen, as it does
    /// behind the SwiftUI sheets; earlier systems keep its opaque backgrounds.
    @Test @MainActor
    func `The More screen lets the sheet's glass show through on iOS 26`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))

        let nav = MoreSheetHost.makeNavigationController(application: application)
        let more = try #require(nav.topViewController as? MoreViewController)

        if #available(iOS 26.0, *) {
            #expect(more.view.backgroundColor == .clear)
            #expect(more.listView.backgroundColor == .clear)
        } else {
            #expect(more.view.backgroundColor != .clear)
        }
    }

    /// The More sheet could only be swiped away; the other index sheets close
    /// from a button.
    @Test @MainActor
    func `The More sheet has a Close button beside Settings`() {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        var closes = 0

        let nav = MoreSheetHost.makeNavigationController(application: application) { closes += 1 }
        let items = nav.topViewController?.navigationItem.rightBarButtonItems ?? []

        #expect(items.count == 2)
        #expect(items.last?.title == Strings.settings)
        #expect(items.first?.primaryAction != nil)
    }

    /// As the home sheet's More tab there's no sheet of its own to close: the tab
    /// bar is the way out.
    @Test @MainActor
    func `The More tab has no Close button`() {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))

        let nav = MoreSheetHost.makeNavigationController(application: application, onClose: nil)
        let items = nav.topViewController?.navigationItem.rightBarButtonItems ?? []

        #expect(items.count == 1)
        #expect(items.first?.title == Strings.settings)
    }
}
