//
//  MapStopLabelLayoutTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import CoreGraphics
@testable import OBAKit
@testable import OBAKitCore

/// Placement of route pills on the panel map: below the pin by default, the
/// curbside side only when below would overlap, hidden when both would.
@Suite(.serialized)
struct MapStopLabelLayoutTests {
    private let layout = MapStopLabelLayout(pinSize: 48, gap: 2)
    private let pill = CGSize(width: 90, height: 18)
    private let center = CGPoint(x: 200, y: 400)

    private func candidate(
        _ id: StopID,
        at point: CGPoint,
        direction: Direction = .unknown,
        required: Bool = false,
        size: CGSize? = nil
    ) -> MapStopLabelLayout.Candidate {
        .init(id: id, center: point, labelSize: size ?? pill, direction: direction, isRequired: required)
    }

    // MARK: - Default

    @Test func `A lone stop's label goes below its pin`() {
        let result = layout.layout([candidate("a", at: center, direction: .n)], viewportCenter: center)
        #expect(result["a"] == .below)
    }

    @Test func `Stops far apart all keep the default spot`() {
        let result = layout.layout([
            candidate("a", at: CGPoint(x: 100, y: 100), direction: .n),
            candidate("b", at: CGPoint(x: 300, y: 300), direction: .s),
            candidate("c", at: CGPoint(x: 100, y: 500), direction: .e)
        ], viewportCenter: center)
        #expect(result.values.allSatisfy { $0 == .below })
    }

    // MARK: - Collisions

    /// The pin just below `b` covers the spot under `b`, so `b` moves to its
    /// curbside side. Northbound: vehicles keep right, so the curb is east.
    @Test func `An overlapping label moves to its curbside side`() {
        let result = layout.layout([
            candidate("a", at: CGPoint(x: 200, y: 460)),
            candidate("b", at: CGPoint(x: 200, y: 400), direction: .n)
        ], viewportCenter: CGPoint(x: 200, y: 460))
        #expect(result["a"] == .below)
        #expect(result["b"] == .right)
    }

    @Test func `An overlapping label with no direction is hidden`() {
        let result = layout.layout([
            candidate("a", at: CGPoint(x: 200, y: 460)),
            candidate("b", at: CGPoint(x: 200, y: 400))
        ], viewportCenter: CGPoint(x: 200, y: 460))
        #expect(result["b"] == .hidden)
    }

    @Test func `A label hides when both below and curbside are blocked`() {
        let result = layout.layout([
            candidate("b", at: CGPoint(x: 200, y: 400), direction: .n)
        ], obstaclePins: [CGPoint(x: 200, y: 460), CGPoint(x: 290, y: 400)], viewportCenter: center)
        #expect(result["b"] == .hidden)
    }

    @Test func `Labels never cover another pin`() {
        let result = layout.layout([
            candidate("b", at: CGPoint(x: 200, y: 400))
        ], obstaclePins: [CGPoint(x: 200, y: 460)], viewportCenter: center)
        #expect(result["b"] == .hidden)
    }

    @Test func `The stop nearer the center keeps the default spot`() {
        // Side by side, so their pills under the pins overlap.
        let near = candidate("near", at: CGPoint(x: 190, y: 400))
        let far = candidate("far", at: CGPoint(x: 250, y: 400))
        let result = layout.layout([far, near], viewportCenter: CGPoint(x: 190, y: 400))
        #expect(result["near"] == .below)
        #expect(result["far"] == .hidden)
    }

    @Test func `Required labels are placed first and never hidden`() {
        let near = candidate("near", at: CGPoint(x: 190, y: 400))
        let selected = candidate("selected", at: CGPoint(x: 250, y: 400), required: true)
        let result = layout.layout([near, selected], viewportCenter: CGPoint(x: 190, y: 400))
        #expect(result["selected"] == .below)
        #expect(result["near"] == .hidden)
    }

    @Test func `A required label stays below even when everything is blocked`() {
        let result = layout.layout([
            candidate("a", at: center, required: true)
        ], obstaclePins: [CGPoint(x: 200, y: 460)], viewportCenter: center)
        #expect(result["a"] == .below)
    }

    // MARK: - Stability

    @Test func `A label keeps its previous spot while it still fits`() {
        let result = layout.layout(
            [candidate("a", at: center, direction: .n)],
            viewportCenter: center,
            previous: ["a": .right]
        )
        #expect(result["a"] == .right)
    }

    /// After the map turns, an old curbside spot no longer faces the curb.
    @Test func `A previous spot that is no longer curbside is dropped`() {
        let result = layout.layout(
            [candidate("a", at: center, direction: .n)],
            viewportCenter: center,
            heading: 180,
            previous: ["a": .right]
        )
        #expect(result["a"] == .below)
    }

    @Test func `A previously hidden label comes back below when there's room`() {
        let result = layout.layout(
            [candidate("a", at: center, direction: .n)],
            viewportCenter: center,
            previous: ["a": .hidden]
        )
        #expect(result["a"] == .below)
    }

    // MARK: - Curbside

    @Test func `Curbside is right of travel, snapped to a screen side`() {
        let expected: [(Direction, MapStopLabelPlacement?)] = [
            (.n, .right),
            (.s, .left),
            (.e, nil),          // curb is south: the same as the default spot
            (.w, .above),
            (.ne, .right),      // diagonals snap left or right
            (.nw, .right),
            (.se, .left),
            (.sw, .left),
            (.unknown, nil)
        ]
        for (direction, placement) in expected {
            #expect(MapStopLabelLayout.curbside(for: direction, heading: 0) == placement, "\(direction)")
        }
    }

    /// With the map turned so east is up, a northbound stop's curb (east) is at the top.
    @Test func `Curbside follows the camera heading`() {
        #expect(MapStopLabelLayout.curbside(for: .n, heading: 90) == .above)
        #expect(MapStopLabelLayout.curbside(for: .n, heading: 180) == .left)
    }

    // MARK: - Geometry

    @Test func `Label rects sit just outside the pin`() {
        let stop = candidate("a", at: center)
        let below = layout.labelRect(for: stop, placement: .below)
        #expect(below.minY == center.y + 26)
        #expect(below.midX == center.x)
        let right = layout.labelRect(for: stop, placement: .right)
        #expect(right.minX == center.x + 26)
        #expect(right.midY == center.y)
        let left = layout.labelRect(for: stop, placement: .left)
        #expect(left.maxX == center.x - 26)
        let above = layout.labelRect(for: stop, placement: .above)
        #expect(above.maxY == center.y - 26)
    }

    // MARK: - Obstacle rects (#1753)

    /// A trip planner card covering the spot below a pin pushes the stop's
    /// label to its curbside side, as another pin would.
    @Test func `A label avoids an obstacle rect below its pin`() {
        let card = CGRect(x: 150, y: 430, width: 100, height: 30)
        let result = layout.layout(
            [candidate("a", at: center, direction: .n)],
            obstacleRects: [card],
            viewportCenter: center
        )
        #expect(result["a"] == .right)
    }

    @Test func `A label is hidden when obstacle rects block every spot`() {
        let card = CGRect(x: 100, y: 380, width: 220, height: 80)
        let result = layout.layout(
            [candidate("a", at: center, direction: .n)],
            obstacleRects: [card],
            viewportCenter: center
        )
        #expect(result["a"] == .hidden)
    }

    // MARK: - Extended Collision & Priority Arbitration

    @Test func `Deterministic tie-breaking sorts identical distances by StopID`() {
        // Two stops equidistant from viewportCenter with overlapping label footprints
        let stopAlpha = candidate("stop_alpha", at: CGPoint(x: 180, y: 400))
        let stopBeta = candidate("stop_beta", at: CGPoint(x: 220, y: 400))

        let result = layout.layout([stopBeta, stopAlpha], viewportCenter: center)
        #expect(result["stop_alpha"] == .below)
        #expect(result["stop_beta"] == .hidden)
    }

    @Test func `Curbside rotates symmetrically across full 360-degree compass headings`() {
        // Northbound direction (bearing 0):
        // heading 0 => curb at east (dx > 0) => .right
        #expect(MapStopLabelLayout.curbside(for: .n, heading: 0) == .right)
        // heading 90 => curb at north (dy < 0) => .above
        #expect(MapStopLabelLayout.curbside(for: .n, heading: 90) == .above)
        // heading 180 => curb at west (dx < 0) => .left
        #expect(MapStopLabelLayout.curbside(for: .n, heading: 180) == .left)
        // heading 270 => curb at south (dy > 0) => nil (curbside collides with default below)
        #expect(MapStopLabelLayout.curbside(for: .n, heading: 270) == nil)
        // heading 360 => returns to .right
        #expect(MapStopLabelLayout.curbside(for: .n, heading: 360) == .right)
    }

    @Test func `Custom pinSize and gap scales placement rect bounds accurately`() {
        let customLayout = MapStopLabelLayout(pinSize: 32, gap: 4)
        let customPill = CGSize(width: 80, height: 20)
        let candidateItem = candidate("scale_test", at: center, size: customPill)

        // reach = 32 / 2 + 4 = 20
        let belowRect = customLayout.labelRect(for: candidateItem, placement: .below)
        #expect(belowRect.minY == center.y + 20)
        #expect(belowRect.width == 80)
        #expect(belowRect.height == 20)

        let rightRect = customLayout.labelRect(for: candidateItem, placement: .right)
        #expect(rightRect.minX == center.x + 20)
        #expect(rightRect.midY == center.y)

        let leftRect = customLayout.labelRect(for: candidateItem, placement: .left)
        #expect(leftRect.maxX == center.x - 20)
        #expect(leftRect.midY == center.y)

        let aboveRect = customLayout.labelRect(for: candidateItem, placement: .above)
        #expect(aboveRect.maxY == center.y - 20)
        #expect(aboveRect.midX == center.x)
    }

    @Test func `Empty candidate array safely yields empty layout dictionary`() {
        let result = layout.layout([], viewportCenter: center)
        #expect(result.isEmpty)
    }

    @Test func `Obstacle pins with no candidates produces empty result without error`() {
        let result = layout.layout([], obstaclePins: [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 200)], viewportCenter: center)
        #expect(result.isEmpty)
    }
}

/// The trip planner's cards hang above their coordinate, so a stop pin drawn at
/// the same spot never covers the name (#1753).
@Suite(.serialized)
struct TripPlannerCardMetricsTests {
    private let center = CGPoint(x: 200, y: 400)

    @Test func `A card's rect sits above a pin at its coordinate without touching it`() {
        let size = CGSize(width: 180, height: 28)
        let rect = TripPlannerCardMetrics.rect(size: size, at: center)
        let pin = MapStopLabelLayout().pinRect(at: center)
        #expect(!rect.intersects(pin))
        #expect(rect.midX == center.x)
        #expect(rect.maxY == center.y - (ThemeMetrics.defaultMapAnnotationSize / 2 + MapStopLabelLayout.gap))
    }

    /// The anchor is the point on the card MapKit pins to the coordinate. It
    /// must land the card where `rect` says, below the card's own bottom edge.
    @Test func `The anchor puts the card where rect says`() {
        let size = CGSize(width: 180, height: 28)
        let anchor = TripPlannerCardMetrics.anchor(cardHeight: size.height)
        let rect = TripPlannerCardMetrics.rect(size: size, at: center)
        #expect(anchor.x == 0.5)
        #expect(abs(center.y - anchor.y * size.height - rect.minY) < 0.0001)
        #expect(anchor.y > 1)
    }

    @Test func `A badge and a subtitle make the card taller`() {
        let plain = TripPlannerCardMetrics.size(title: "Fauntleroy Way & SW Myrtle St", subtitle: nil, routeName: nil)
        let subtitled = TripPlannerCardMetrics.size(title: "Fauntleroy Way & SW Myrtle St", subtitle: "Board here", routeName: nil)
        let badged = TripPlannerCardMetrics.size(title: "Fauntleroy Way & SW Myrtle St", subtitle: "Board here", routeName: "C Line")
        #expect(plain.height > 0 && plain.width > 0)
        #expect(subtitled.height > plain.height)
        #expect(badged.height > subtitled.height)
    }

    @Test func `A longer title makes the card wider`() {
        let short = TripPlannerCardMetrics.size(title: "Start", subtitle: nil, routeName: nil)
        let long = TripPlannerCardMetrics.size(title: "Fauntleroy Way & SW Myrtle St", subtitle: nil, routeName: nil)
        #expect(long.width > short.width)
    }
}
