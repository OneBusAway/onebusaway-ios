//
//  BikeSpeedTests.swift
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

@Suite(.serialized)
final class BikeSpeedTests: OBATestCase {

    @Test func `BikeSpeed default and valid bounds constants`() {
        #expect(BikeSpeed.defaultMetersPerSecond == 4.2)
        #expect(BikeSpeed.validRange.lowerBound == 2.0)
        #expect(BikeSpeed.validRange.upperBound == 20.0)
        #expect(BikeSpeed.validRange.contains(BikeSpeed.defaultMetersPerSecond))
    }

    @Test func `BikeSpeedSource enum raw integer values are stable for persistence`() {
        #expect(BikeSpeedSource.manual.rawValue == 0)
        #expect(BikeSpeedSource.synced.rawValue == 1)
    }
}
