//
//  StopIconFactoryTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import UIKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class StopIconFactoryTests: OBATestCase {

    private func makeFactory() -> StopIconFactory {
        StopIconFactory(iconSize: 44, themeColors: ThemeColors.shared)
    }

    private let lightTraits = UITraitCollection(userInterfaceStyle: .light)
    private let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

    @Test func `Build squircle icon returns a cached instance for the same stop`() throws {
        let factory = makeFactory()
        let stop = try #require(Fixtures.loadSomeStops().first)

        let first = factory.buildSquircleIcon(for: stop, isBookmarked: false, traits: lightTraits)
        let second = factory.buildSquircleIcon(for: stop, isBookmarked: false, traits: lightTraits)

        // Same (routeType, direction, bookmarked, appearance) key → cache hit → identical instance.
        #expect(first === second)
    }

    @Test func `Build squircle icon produces an icon at the configured size`() throws {
        let factory = makeFactory()
        let stop = try #require(Fixtures.loadSomeStops().first)

        let icon = factory.buildSquircleIcon(for: stop, isBookmarked: false, traits: lightTraits)

        #expect(icon.size.width == 44)
        #expect(icon.size.height == 44)
    }

    @Test func `Build squircle icon renders separately per appearance`() throws {
        let factory = makeFactory()
        let stop = try #require(Fixtures.loadSomeStops().first)

        let light = factory.buildSquircleIcon(for: stop, isBookmarked: false, traits: lightTraits)
        let dark = factory.buildSquircleIcon(for: stop, isBookmarked: false, traits: darkTraits)

        // Different appearance keys → distinct cached instances, so a light-mode
        // render is never served after the user switches to dark.
        #expect(light !== dark)
    }

    @Test func `Build squircle icon renders separately for bookmarked stops`() throws {
        let factory = makeFactory()
        let stop = try #require(Fixtures.loadSomeStops().first)

        let plain = factory.buildSquircleIcon(for: stop, isBookmarked: false, traits: lightTraits)
        let bookmarked = factory.buildSquircleIcon(for: stop, isBookmarked: true, traits: lightTraits)

        // Bookmarked stops use the brand fill and regular stops a neutral fill, so
        // they must render (and cache) as distinct instances.
        #expect(plain !== bookmarked)
    }
}
