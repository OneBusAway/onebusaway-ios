//
//  StopIconFactoryTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
@testable import OBAKit
@testable import OBAKitCore

final class StopIconFactoryTests: OBATestCase {

    private func makeFactory() -> StopIconFactory {
        StopIconFactory(iconSize: 44, themeColors: ThemeColors.shared)
    }

    func test_buildSquircleIcon_returnsCachedInstanceForSameStop() throws {
        let factory = makeFactory()
        let stop = try XCTUnwrap(Fixtures.loadSomeStops().first)

        let first = factory.buildSquircleIcon(for: stop)
        let second = factory.buildSquircleIcon(for: stop)

        // Same (routeType, direction) key → cache hit → identical instance.
        expect(first) === second
    }

    func test_buildSquircleIcon_producesIconAtConfiguredSize() throws {
        let factory = makeFactory()
        let stop = try XCTUnwrap(Fixtures.loadSomeStops().first)

        let icon = factory.buildSquircleIcon(for: stop)

        expect(icon.size.width) == 44
        expect(icon.size.height) == 44
    }
}
