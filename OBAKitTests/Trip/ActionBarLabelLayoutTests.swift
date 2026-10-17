//
//  ActionBarLabelLayoutTests.swift
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

/// The frosted action buttons at the foot of the trip page and the stop page (#1551).
///
/// Two things went wrong with the trip page's icon-over-caption labels:
/// - A caption as wide as its button ran under the capsule's rounded ends, so its
///   first and last letters sat outside the shape.
/// - Each label sat wherever its SF Symbol's height put it, so a short glyph like
///   `ellipsis` pulled "More" up off the others' baseline.
///
/// The bars are rendered for real and read back as pixels: the frosted fill is
/// measurably darker than the bar behind it, and the glyphs are near black, so
/// each button's shape and its label's ink can be told apart row by row.
@MainActor
@Suite(.serialized)
struct ActionBarLabelLayoutTests {

    /// Ink must clear the button's edge by this much, in points.
    private static let minimumInset: CGFloat = 4

    @Test func `trip page action bar labels sit inside their buttons, on one baseline`() throws {
        let bar = TripActionBar(
            canStartLiveActivity: false, isTrackingLiveActivity: false,
            canSchedule: true, canAlarm: true, hasAlarm: false, canReportGhostBus: true,
            onLiveActivity: {}, onBookmark: {}, onSchedule: {}, onAlarm: {}, onReportGhostBus: {}
        )
        try expectWellFormedButtons(in: bar, count: 4)
    }

    /// At the default text size every caption fits on one line, even with all four
    /// buttons showing (#1577). "Add Bookmark" and "View schedule" wrapped; the
    /// fuller wording stays in their VoiceOver labels.
    @Test func `trip page action bar captions fit on one line with all four buttons`() throws {
        let bar = TripActionBar(
            canStartLiveActivity: false, isTrackingLiveActivity: false,
            canSchedule: true, canAlarm: true, hasAlarm: false, canReportGhostBus: true,
            onLiveActivity: {}, onBookmark: {}, onSchedule: {}, onAlarm: {}, onReportGhostBus: {}
        )
        // 375 pt is the narrowest width that still lays the four out in one row.
        for width: CGFloat in [402, 375] {
            let buttons = try measuredButtons(in: bar, size: CGSize(width: width, height: 260)).buttons
            try #require(buttons.count == 4, "\(width) pt: found \(buttons.count) buttons")
            #expect(buttons.map(\.captionLines) == [1, 1, 1, 1], "\(width) pt: caption line counts \(buttons.map(\.captionLines))")
        }
    }

    /// The captions are short; what VoiceOver says is not.
    @Test func `trip page action captions are short and their VoiceOver labels are not`() {
        #expect(TripActionBar.bookmarkTitle == "Bookmark")
        #expect(TripActionBar.bookmarkAccessibilityLabel == Strings.addBookmark)
        #expect(TripActionBar.scheduleTitle == "Schedule")
        #expect(TripActionBar.scheduleAccessibilityLabel == "View schedule")
    }

    /// The stop page's toolbar never had the bug — it pins its icon height and shrinks
    /// its captions to fit — so this one is a guard, not a fix.
    @Test func `stop page toolbar labels sit inside their buttons, on one baseline`() throws {
        let toolbar = StopPageToolbar(
            statusText: "Updated: Just Now", isRefreshing: false,
            isFilterOn: false, canFilter: true, isListFiltered: false,
            activeDepartureFilter: .all, hasServiceAlerts: true,
            onRefresh: {}, onSetListFiltered: { _ in }, onSetDepartureFilter: { _ in },
            onBookmark: {}, onSchedule: {},
            onServiceAlerts: {}, onNearbyStops: {}, onWalkingDirections: {},
            onDirectionsToHere: nil, onDirectionsFromHere: nil,
            isProximityAlertActive: false, onToggleProximityAlert: {},
            onReportProblem: {}
        )
        try expectWellFormedButtons(in: toolbar, count: 4)
    }

    // MARK: - Columns

    /// Four across while a button is wide enough for its caption, then two, then one —
    /// decided by the width the bar actually gets, not by text size alone, so a
    /// 320 pt Display Zoom screen drops to two columns at the default text size and a
    /// wide one keeps four at larger sizes.
    @Test func `the action grid drops columns as its buttons get too narrow`() {
        let grid = ActionButtonGrid(minimumColumnWidth: 74, spacing: 10)

        #expect(grid.columnCount(for: 4, width: 402 - 32) == 4)
        #expect(grid.columnCount(for: 4, width: 375 - 32) == 4)
        #expect(grid.columnCount(for: 4, width: 320 - 32) == 2)
        #expect(grid.columnCount(for: 4, width: 100) == 1)
        #expect(grid.columnCount(for: 3, width: 375 - 32) == 3)
        #expect(grid.columnCount(for: 1, width: 375 - 32) == 1)

        // A larger text size scales the minimum: xLarge on a 375 pt screen is the
        // first size at which "Bookmark" no longer fits four across.
        let larger = ActionButtonGrid(minimumColumnWidth: 80, spacing: 10)
        #expect(larger.columnCount(for: 4, width: 375 - 32) == 2)
        #expect(larger.columnCount(for: 4, width: 402 - 32) == 4)
    }

    // MARK: - Measuring

    /// The bar's buttons, and the render's pixels per point.
    private func measuredButtons<V: View>(in bar: V, size: CGSize) throws -> (buttons: [ActionBarPixels.MeasuredButton], scale: CGFloat) {
        let render = try HostedRender(VStack { Spacer(); bar }, size: size)
        let scale = CGFloat(render.width) / size.width
        return (try #require(ActionBarPixels(render: render, scale: scale).buttons()), scale)
    }

    private func expectWellFormedButtons<V: View>(in bar: V, count: Int) throws {
        let size = CGSize(width: 402, height: 200)
        let (buttons, scale) = try measuredButtons(in: bar, size: size)
        try #require(buttons.count == count, "found \(buttons.count) buttons")

        for (index, button) in buttons.enumerated() {
            #expect(button.tightestInset >= Int(Self.minimumInset * scale), "button \(index): ink is \(button.tightestInset)px from its edge")
        }

        // One baseline: every caption's first line ends on the same row.
        let baselines = buttons.map(\.firstLineBottom)
        #expect(baselines.max()! - baselines.min()! <= 1, "caption baselines differ: \(baselines)")

        // One icon line: glyphs of different heights share a center.
        let iconCenters = buttons.map(\.iconCenter)
        #expect(iconCenters.max()! - iconCenters.min()! <= Int(scale), "icon centers differ: \(iconCenters)")
    }
}

/// Finds the frosted buttons in a light-mode render of an action bar.
@MainActor
private struct ActionBarPixels {
    let render: HostedRender
    /// Pixels per point.
    let scale: CGFloat

    struct MeasuredButton {
        /// Fewest pixels between any ink pixel and the shape's edge on its row.
        let tightestInset: Int
        /// Last row of the caption's first line.
        let firstLineBottom: Int
        let iconCenter: Int
        /// Lines of caption under the icon.
        let captionLines: Int
    }

    /// The bar is ~247; the frosted fill and its rim ~215–232.
    private func isFill(_ x: Int, _ y: Int) -> Bool { (200...238).contains(render.luminance(x: x, y: y)) }
    /// Glyph ink, antialiased edges excluded.
    private func isInk(_ x: Int, _ y: Int) -> Bool { render.luminance(x: x, y: y) < 120 }
    /// Anything that is not the bar or the window behind it.
    private func isButton(_ x: Int, _ y: Int) -> Bool { render.luminance(x: x, y: y) <= 238 }

    func buttons() -> [MeasuredButton]? {
        // The row the buttons' fills cover most of: their vertical middle.
        let counts = (0..<render.height).map { (row: $0, fill: fillCount(row: $0)) }
        guard let row = counts.max(by: { $0.fill < $1.fill })?.row else { return nil }

        // Horizontal runs of button pixels on that row, one per button.
        var runs: [ClosedRange<Int>] = []
        var start: Int?
        for x in 0...render.width {
            let inside = x < render.width && isButton(x, row)
            if inside, start == nil { start = x }
            if !inside, let s = start { if CGFloat(x - s) > 7 * scale { runs.append(s...(x - 1)) }; start = nil }
        }

        return runs.compactMap { button(columns: $0, middleRow: row) }
    }

    private func fillCount(row: Int) -> Int {
        (0..<render.width).reduce(0) { $0 + (isFill($1, row) ? 1 : 0) }
    }

    private func button(columns: ClosedRange<Int>, middleRow: Int) -> MeasuredButton? {
        let centerX = (columns.lowerBound + columns.upperBound) / 2
        // Vertical extent: walk up and down the center column through fill and ink.
        var top = middleRow, bottom = middleRow
        while top > 0, isButton(centerX, top - 1) { top -= 1 }
        while bottom < render.height - 1, isButton(centerX, bottom + 1) { bottom += 1 }

        // The search window reaches past the shape so ink that escaped it is still seen.
        let margin = Int(10 * scale)
        let xs = max(0, columns.lowerBound - margin)...min(render.width - 1, columns.upperBound + margin)

        var inkRows: [Int] = []
        var tightest = Int.max
        for y in top...bottom {
            guard let leftInk = xs.first(where: { isInk($0, y) }),
                  let rightInk = xs.last(where: { isInk($0, y) }) else { continue }
            inkRows.append(y)
            // The shape's edge on this row: the outermost fill pixels. Ink lying over
            // the edge itself is skipped, which moves the measured edge inward — so
            // escaped ink reads as a negative inset rather than hiding.
            guard let leftEdge = xs.first(where: { isFill($0, y) }),
                  let rightEdge = xs.last(where: { isFill($0, y) }) else { continue }
            tightest = min(tightest, leftInk - leftEdge, rightEdge - rightInk)
        }

        // Ink rows split into blocks at blank bands: icon first, then caption lines.
        // A band of up to 2pt is within one glyph (the bell's clapper); the gap
        // between icon and caption, and between caption lines, is several points.
        let withinGlyph = Int(2 * scale)
        var blocks: [ClosedRange<Int>] = []
        for y in inkRows {
            if let last = blocks.last, y - last.upperBound <= withinGlyph {
                blocks[blocks.count - 1] = last.lowerBound...y
            } else {
                blocks.append(y...y)
            }
        }
        // No row with both ink and fill means the shape was never found, and the inset
        // check would pass on `Int.max`.
        guard blocks.count >= 2, tightest != Int.max else { return nil }
        let icon = blocks[0]
        return MeasuredButton(
            tightestInset: tightest,
            firstLineBottom: blocks[1].upperBound,
            iconCenter: (icon.lowerBound + icon.upperBound) / 2,
            captionLines: blocks.count - 1
        )
    }
}
