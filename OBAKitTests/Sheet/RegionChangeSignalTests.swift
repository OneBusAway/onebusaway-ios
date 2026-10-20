//
//  RegionChangeSignalTests.swift
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

@MainActor
@Suite(.serialized)
final class RegionChangeSignalTests: OBATestCase {

    /// The panel's map moves on this. Before it, picking a region in More left
    /// the map, and the stops request, on the old city.
    @Test func `Changing region tells the panel which region it is now`() {
        let queue = OperationQueue()
        let app = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let signal = RegionChangeSignal(regionsService: app.regionsService)
        #expect(signal.region == nil)

        // Called as `RegionsService` calls it: setting `currentRegion` for real
        // would rebuild the API service and fetch from the new region.
        let region = Fixtures.pugetSoundRegion
        signal.regionsService(app.regionsService, updatedRegion: region)

        #expect(signal.region?.regionIdentifier == region.regionIdentifier)
    }
}
