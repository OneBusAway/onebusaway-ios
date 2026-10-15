//
//  RouteDirectionArrowsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreGraphics
import Testing
import UIKit
@testable import OBAKit

/// The placement rules from the redesign (#1545). Lines here are in screen points
/// at `scale: 1` unless a test says otherwise, so the numbers read straight off the
/// rules: a candidate every 64 pt from 30 pt in, shifted up to 8 pt, on segments
/// of at least 40 pt, 12 pt clear of corners and 22 pt clear of stop markers.
@Suite(.serialized)
struct RouteDirectionArrowsTests {

    private func layout(_ points: [CGPoint]) -> RouteArrowLayout {
        RouteArrowLayout(points: points)
    }

    /// Positions come out of an interpolation, so compare them to a tenth of a point.
    private func rounded(_ point: CGPoint?) -> CGPoint? {
        point.map { CGPoint(x: ($0.x * 10).rounded() / 10, y: ($0.y * 10).rounded() / 10) }
    }

    // MARK: - Spacing

    @Test func `A straight line gets a chevron every 64 points from 30 points in`() {
        let arrows = layout([CGPoint(x: 0, y: 0), CGPoint(x: 400, y: 0)]).arrows(scale: 1)

        #expect(arrows.map { rounded($0.point)!.x } == [30, 94, 158, 222, 286, 350])
        #expect(arrows.allSatisfy { $0.angle == 0 && $0.point.y == 0 })
    }

    /// Spacing is on screen, so zooming in on the same line fits more chevrons.
    @Test func `Spacing is in screen points, not line units`() {
        let line = layout([CGPoint(x: 0, y: 0), CGPoint(x: 400, y: 0)])

        #expect(line.arrows(scale: 1).count == 6)
        #expect(line.arrows(scale: 2).count == 12)
    }

    @Test func `A line too short for the first candidate has no chevrons`() {
        #expect(layout([CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0)]).arrows(scale: 1).isEmpty)
        #expect(layout([CGPoint(x: 0, y: 0)]).arrows(scale: 1).isEmpty)
        #expect(layout([]).arrows(scale: 1).isEmpty)
    }

    // MARK: - Corners and short segments

    /// The 94 pt candidate is 6 pt short of the corner; it backs off to 88, the
    /// nearest spot 12 pt clear.
    @Test func `A chevron near a corner shifts back to clear it`() {
        let arrows = layout([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 200)]).arrows(scale: 1)

        #expect(arrows.map(\.index) == [0, 1, 2, 3, 4])
        #expect(rounded(arrows[1].point) == CGPoint(x: 88, y: 0))
        // Past the corner the line runs down the screen, and so does the chevron.
        #expect(abs(arrows[2].angle - .pi / 2) < 0.0001)
    }

    @Test func `No chevron sits on a segment shorter than 40 points`() {
        // A zigzag of 30 pt legs: every candidate lands on one.
        let zigzag = (0...20).map { CGPoint(x: CGFloat($0) * 30, y: $0.isMultiple(of: 2) ? 0 : 1) }

        #expect(layout(zigzag).arrows(scale: 1).isEmpty)
    }

    // MARK: - Stop markers

    /// 15 pt from the marker at 94; 7 pt back is the nearest spot 22 pt clear.
    @Test func `A chevron near a stop marker shifts to clear it`() {
        let arrows = layout([CGPoint(x: 0, y: 0), CGPoint(x: 400, y: 0)])
            .arrows(scale: 1, avoiding: [CGPoint(x: 109, y: 0)])

        #expect(rounded(arrows.first { $0.index == 1 }?.point) == CGPoint(x: 87, y: 0))
    }

    /// No spot within 8 pt either way is 22 pt from a marker sitting on the
    /// candidate, so it is dropped — never pushed further.
    @Test func `A chevron with no clear spot within reach is dropped`() {
        let arrows = layout([CGPoint(x: 0, y: 0), CGPoint(x: 400, y: 0)])
            .arrows(scale: 1, avoiding: [CGPoint(x: 94, y: 0)])

        #expect(arrows.map(\.index) == [0, 2, 3, 4, 5])
    }

    // MARK: - Tiles

    /// MapKit draws a line one tile at a time. A chevron near a tile edge has to be
    /// placed identically from both sides of it, or it draws twice or broken.
    @Test func `Asking about part of the line gives the same chevrons there`() {
        let points = [
            CGPoint(x: 0, y: 0), CGPoint(x: 300, y: 0), CGPoint(x: 300, y: 250),
            CGPoint(x: 620, y: 250), CGPoint(x: 620, y: 700)
        ]
        let line = layout(points)
        let markers = [CGPoint(x: 310, y: 120)]
        let whole = line.arrows(scale: 1, avoiding: markers)

        var fromTiles: [Int: RouteArrowLayout.Arrow] = [:]
        for column in 0..<4 {
            for row in 0..<4 {
                let tile = CGRect(x: CGFloat(column) * 200 - 10, y: CGFloat(row) * 200 - 10, width: 200, height: 200)
                for arrow in line.arrows(scale: 1, avoiding: markers, in: tile, margin: RouteArrowStyle.extent) {
                    #expect(fromTiles[arrow.index] == nil || fromTiles[arrow.index] == arrow)
                    fromTiles[arrow.index] = arrow
                }
            }
        }

        #expect(whole.count > 10)
        #expect(fromTiles.values.sorted { $0.index < $1.index } == whole)
    }

    // MARK: - Style

    @Test func `Chevrons are white on a dark route color and near-black on a pale one`() {
        let crimson = UIColor(red: 0x9B / 255, green: 0x1B / 255, blue: 0x30 / 255, alpha: 1)
        let pale = UIColor(red: 1, green: 0.9, blue: 0.3, alpha: 1)

        #expect(RouteArrowStyle.chevronColor(on: crimson) == .white)
        #expect(RouteArrowStyle.chevronColor(on: pale) != .white)
        #expect(RouteArrowStyle.chevronColor(on: pale).wcagContrastRatio(against: pale) >= 3)
    }

    /// The brief's example: #9b1b30 darkens to about #6e0f20.
    @Test func `The casing is the route color about 30 percent darker`() {
        let crimson = UIColor(red: 0x9B / 255, green: 0x1B / 255, blue: 0x30 / 255, alpha: 1)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        RouteArrowStyle.casingColor(for: crimson).getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        #expect(abs(red * 255 - 0x6E) < 4)
        #expect(abs(green * 255 - 0x0F) < 5)
        #expect(abs(blue * 255 - 0x20) < 3)
        #expect(alpha == 1)
    }

    @Test func `Marker updates report whether anything moved`() {
        let markers = RouteArrowMarkers()

        #expect(markers.update([CGPoint(x: 1, y: 2)]))
        #expect(!markers.update([CGPoint(x: 1, y: 2)]))
        #expect(markers.points == [CGPoint(x: 1, y: 2)])
    }
}
