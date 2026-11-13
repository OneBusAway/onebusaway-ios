//
//  MapPanelScreenshotStopTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

#if DEBUG
import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// `TEST_SCREENSHOT_STOP_ID` on the map panel: the App Store screenshots open
/// their stop as the panel's stop sheet, the way a tap on its pin does.
@MainActor
@Suite(.serialized)
final class MapPanelScreenshotStopTests: OBATestCase {

    private var application: Application!
    private let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)

    override init() async throws {
        try await super.init()
        application = buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: name))
    }

    @Test func `The screenshot stop opens as the stop sheet, once`() throws {
        try #require(application.currentRegion != nil)
        application.screenshotStopID = "40_99610"

        coordinator.showScreenshotStopIfNeeded(application: application)
        // The panel calls this on appearing and on every region change.
        coordinator.showScreenshotStopIfNeeded(application: application)

        #expect(coordinator.stackedRoutes.map(\.id) == ["stopDetails-40_99610"])
        #expect(coordinator.stackedDetents == [.medium])
        #expect(application.screenshotStopID == nil)
    }

    /// A first launch has no region when the map appears, which is why the
    /// panel asks again on every region change.
    @Test func `Before there is a region the panel waits, then opens the stop`() throws {
        let regionKey = RegionsService.currentRegionIdentifierUserDefaultsKey
        let regionID = try #require(application.currentRegion?.regionIdentifier)
        userDefaults.removeObject(forKey: regionKey)
        try #require(application.currentRegion == nil)
        application.screenshotStopID = "40_99610"

        coordinator.showScreenshotStopIfNeeded(application: application)
        #expect(coordinator.stackedRoutes.isEmpty)

        userDefaults.set(regionID, forKey: regionKey)
        coordinator.showScreenshotStopIfNeeded(application: application)
        #expect(coordinator.stackedRoutes.map(\.id) == ["stopDetails-40_99610"])
    }
}
#endif // DEBUG
