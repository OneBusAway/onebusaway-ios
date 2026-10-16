//
//  StopPageHeaderTravelChipTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import SwiftUI
import UIKit
@testable import OBAKit
@testable import OBAKitCore

/// The pushed stop page's walk and bike chips must draw their minutes, not just
/// their glyphs (#1550).
///
/// The header sits in a `.plain` `List` row, and a `Label` with `.fixedSize` in
/// a `List` row drew only its icon: the chip kept its full width, but the title
/// never drew. The test renders the header the way `StopPageView` hosts it and
/// looks for title glyphs in each chip past its icon.
@MainActor
@Suite(.serialized)
struct StopPageHeaderTravelChipTests {

    @Test func `walk and bike chips draw their minutes inside a List row`() throws {
        let stop = try #require(Fixtures.loadSomeStops().first)
        let view = List {
            Section {
                StopPageHeaderView(
                    stop: stop,
                    walkTime: WalkTimeInfo(walkMinutes: 36, distance: 2800),
                    bikeTime: WalkTimeInfo(walkMinutes: 11, distance: 2800),
                    statusText: "",
                    snapshotLoader: { _ in nil },
                    pillDirections: .none
                )
                .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.plain)
        let render = try HostedRender(view, size: CGSize(width: 402, height: 300))

        let light = UITraitCollection(userInterfaceStyle: .light)
        for (name, fill) in [("walk", ThemeColors.shared.departureOnTimeFill), ("bike", ThemeColors.shared.blue)] {
            let chip = try #require(try render.boundingBox(of: fill.resolvedColor(with: light)), "\(name) chip not found")
            // A band past the glyph (the bicycle reaches beyond the chip's midpoint)
            // and short of the rounded end. With no title it is solid fill; with one,
            // it is the middle of the title.
            let titleBand = CGRect(x: chip.minX + chip.width * 0.6, y: chip.minY, width: chip.width * 0.25, height: chip.height)
            // The title is white on the fill; its glyphs leave a few hundred light pixels at 3x.
            #expect(render.lightPixelCount(in: titleBand) > 100, "\(name) chip drew no title")
        }
    }
}
