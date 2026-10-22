//
//  MapPanelMapSettingsTests.swift
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

/// Settings' Show Scale and Show Traffic switches went to `MapRegionManager`'s
/// `MKMapView` only, which the map panel never shows.
@MainActor
@Suite(.serialized)
final class MapPanelMapSettingsTests: OBATestCase {

    @Test func `The panel map reads the switches Settings writes`() {
        let application = buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: name))

        application.mapRegionManager.mapViewShowsScale = false
        application.mapRegionManager.mapViewShowsTraffic = false

        #expect(application.userDefaults.object(forKey: MapRegionManager.mapViewShowsScaleKey) as? Bool == false)
        #expect(application.userDefaults.object(forKey: MapRegionManager.mapViewShowsTrafficKey) as? Bool == false)
    }

    @Test func `Traffic stays off in the Simulator`() {
        #if targetEnvironment(simulator)
        #expect(!MapRegionManager.effectiveShowsTraffic(true))
        #else
        #expect(MapRegionManager.effectiveShowsTraffic(true))
        #endif
        #expect(!MapRegionManager.effectiveShowsTraffic(false))
    }
}
