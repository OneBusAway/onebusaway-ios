//
//  TripActionBar.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The pinned actions at the foot of the trip page.
///
/// Pinned rather than scrolled with the content: on a sixty-stop trip these
/// would otherwise be a long scroll away, and tracking a bus is the thing a
/// rider most often opens this page to do.
struct TripActionBar: View {
    /// Live Activities need a real-time trip to report on, and the platform has
    /// to allow them. Hidden rather than disabled when unavailable — a dead
    /// primary button is worse than no primary button.
    let canStartLiveActivity: Bool
    let isTrackingLiveActivity: Bool
    let canSchedule: Bool
    let canAlarm: Bool
    let hasAlarm: Bool
    let canReportGhostBus: Bool

    /// Ceiling on the bar's height at accessibility sizes, past which it scrolls. Supplied by the
    /// page, because the page is the only thing that knows how much room there actually is.
    ///
    /// The bar is pinned as a bottom `safeAreaInset`, so every point it takes is a point the trip's
    /// stop list doesn't get. Left to size itself it reaches 496 pt at AX3 and 746 pt at AX5 —
    /// measured — which on an 874 pt screen is 57% and 85% of the page, for a page whose whole
    /// purpose is the list above it.
    ///
    /// A constant can't express the limit: this page is pushed into a sheet whose `.half` detent is
    /// half the safe-area height (FloatingPanel's stock `fractionalInset`, which
    /// `StopSheetLayout.halfDetentInset` reports for callers that can't read the live surface). On
    /// the shortest supported device that detent is roughly 330 pt, so any fixed cap generous
    /// enough to be useful at `.full` is nearly the whole sheet at `.half`.
    var maxHeight: CGFloat?

    let onLiveActivity: () -> Void
    let onBookmark: () -> Void
    let onSchedule: () -> Void
    let onAlarm: () -> Void
    let onReportGhostBus: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Every icon gets this much height, whatever its symbol's own height, so the
    /// captions under them start on one line (#1551).
    @ScaledMetric(relativeTo: .body) private var iconHeight: CGFloat = 22

    /// Less round than a capsule; see `FrostedBackground`.
    private static let buttonShape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    /// Used until the page's first geometry reading lands, and if it ever reads zero.
    private static let fallbackMaxHeight: CGFloat = 300

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .background(.bar)
    }

    private var stack: some View {
        VStack(spacing: 10) {
            if canStartLiveActivity {
                liveActivityButton
            }
            secondaryActions
        }
    }

    @ViewBuilder
    private var content: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // Capped and scrollable rather than truncated or shrunk: at these sizes the buttons
            // stack full-width (see `secondaryActions`), and every one of them has to stay
            // reachable at its full label size. Scrolling gives up nothing — it just stops the bar
            // from swallowing the page.
            ScrollView(.vertical) { stack }
                .frame(maxHeight: resolvedMaxHeight)
                // The bar is one of two scrollable regions stacked vertically, which is
                // ambiguous to drag. Bouncing only when it actually overflows keeps the
                // gesture predictable at the sizes where the content already fits.
                .scrollBounceBehavior(.basedOnSize)
        } else {
            stack
        }
    }

    /// Never more than the page's share, never less than something usable.
    private var resolvedMaxHeight: CGFloat {
        guard let maxHeight, maxHeight > 0 else { return Self.fallbackMaxHeight }
        return maxHeight
    }

    private var liveActivityButton: some View {
        Button(action: onLiveActivity) {
            Label {
                Text(isTrackingLiveActivity
                     ? OBALoc("trip_page.live_activity_tracking", value: "Tracking on Lock Screen", comment: "Trip page button state once a Live Activity is running for this trip.")
                     : OBALoc("trip_page.live_activity_start", value: "Live Activity — track on Lock Screen", comment: "Trip page button that starts a Live Activity for this trip."))
                .font(.body.weight(.semibold))
            } icon: {
                Image(systemName: "waveform.path.ecg")
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(uiColor: ThemeColors.shared.departureOnTimeFill))
        .foregroundStyle(.white)
        .disabled(isTrackingLiveActivity)
    }

    /// As many columns as leave each button room for its caption: all in one row, then
    /// two across, then one, rather than truncating or shrinking the captions. A word like "Bookmark"
    /// can't wrap, so the room needed grows with the text size, and the room available
    /// with the screen. Stacked full-width at accessibility sizes, as ever.
    private var secondaryActions: some View {
        ActionButtonGrid(
            minimumColumnWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : minimumColumnWidth,
            spacing: 10
        ) {
            secondaryButtons
        }
    }

    /// Room for "Bookmark" at caption size plus the label's padding, with a little to
    /// spare; scales with the caption.
    @ScaledMetric(relativeTo: .caption) private var minimumColumnWidth: CGFloat = 74

    // Captions short enough that all four fit on one line at the default text size;
    // VoiceOver keeps the fuller wording, which costs it nothing (#1577).

    static var bookmarkTitle: String {
        OBALoc("trip_page.bookmark", value: "Bookmark", comment: "Short caption on the trip page button that bookmarks this trip. Keep it to one short word: it shares a row with three other buttons.")
    }

    static var bookmarkAccessibilityLabel: String { Strings.addBookmark }

    static var scheduleTitle: String {
        OBALoc("trip_page.schedule", value: "Schedule", comment: "Short caption on the trip page button opening the route's schedule. Keep it to one short word: it shares a row with three other buttons.")
    }

    static var scheduleAccessibilityLabel: String {
        OBALoc("trip_page.view_schedule", value: "View schedule", comment: "VoiceOver label for the trip page button opening the route's schedule.")
    }

    @ViewBuilder
    private var secondaryButtons: some View {
        secondaryButton(
            title: Self.bookmarkTitle,
            accessibilityLabel: Self.bookmarkAccessibilityLabel,
            systemImage: "bookmark",
            action: onBookmark
        )

        if canSchedule {
            secondaryButton(
                title: Self.scheduleTitle,
                accessibilityLabel: Self.scheduleAccessibilityLabel,
                systemImage: "calendar",
                action: onSchedule
            )
        }

        if canAlarm {
            secondaryButton(
                title: hasAlarm
                    ? OBALoc("trip_page.remove_alarm", value: "Remove alarm", comment: "Trip page button cancelling this trip's arrival alarm.")
                    : Strings.addAlarm,
                systemImage: hasAlarm ? "bell.fill" : "bell",
                action: onAlarm
            )
        }

        if canReportGhostBus {
            moreMenu
        }
    }

    /// Modeled on `StopPageToolbar.moreItem`, including its documented workaround: a `Menu` can't
    /// take `FrostedActionButtonStyle`, so the label is styled directly.
    private var moreMenu: some View {
        Menu {
            Section {
                Button(action: onReportGhostBus) {
                    Label(
                        OBALoc("trip_page.report_ghost_bus", value: "Report Ghost Bus", comment: "Trip page menu item for reporting a scheduled vehicle that never arrived."),
                        systemImage: "clock.badge.questionmark"
                    )
                }
            }
        } label: {
            // Forgoes the pressed dimming the real buttons get; a menu opening over
            // the tap is its own feedback. See `FrostedBackground` for why a
            // `Menu` can't take the button style.
            actionLabel(title: Strings.more, systemImage: "ellipsis")
                .foregroundStyle(Color(uiColor: .label))
                .modifier(FrostedBackground(shape: Self.buttonShape))
        }
        .accessibilityLabel(Strings.more)
    }

    private func secondaryButton(
        title: String,
        accessibilityLabel: String? = nil,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            actionLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(FrostedActionButtonStyle(shape: Self.buttonShape))
        .accessibilityLabel(accessibilityLabel ?? title)
    }

    /// The shared icon-over-caption layout for everything in the bar's secondary row —
    /// plain buttons and the More menu's label alike.
    ///
    /// Top-aligned under a fixed-height icon, so every caption's first line sits on
    /// one baseline whatever the symbol. A caption too wide for its button wraps to a
    /// second line rather than shrinking or running under the button's ends; the
    /// button grows to hold it (#1551).
    private func actionLabel(title: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .frame(height: iconHeight)
                .accessibilityHidden(true) // the caption names the action
            Text(title)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity, alignment: .top)
    }
}

/// Equal-width columns of buttons, as many as `minimumColumnWidth` allows, each row as
/// tall as its tallest button so the frosted shapes line up.
///
/// A `Layout` rather than an `HStack` or a grid view, because the column count depends
/// on the width the bar is offered — which only a layout knows — and because neither
/// `LazyVGrid` nor an `HStack` stretches its cells to a shared row height on its own.
struct ActionButtonGrid: Layout {
    var minimumColumnWidth: CGFloat
    var spacing: CGFloat

    /// All of them, two, or one: the largest that keeps every column at least
    /// `minimumColumnWidth` wide.
    func columnCount(for count: Int, width: CGFloat) -> Int {
        let fits = { columnWidth(columns: $0, width: width) >= minimumColumnWidth }
        if count > 1, fits(count) { return count }
        if count > 2, fits(2) { return 2 }
        return 1
    }

    private func columnWidth(columns: Int, width: CGFloat) -> CGFloat {
        (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
    }

    private struct Grid {
        let columns: Int
        let columnWidth: CGFloat
        let rowHeights: [CGFloat]
    }

    /// Column count, column width and per-row heights for a given offered width.
    private func grid(width: CGFloat, subviews: Subviews) -> Grid {
        let columns = columnCount(for: subviews.count, width: width)
        let columnWidth = columnWidth(columns: columns, width: width)
        let rowHeights = stride(from: 0, to: subviews.count, by: columns).map { start in
            subviews[start..<min(start + columns, subviews.count)]
                .map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }
                .max() ?? 0
        }
        return Grid(columns: columns, columnWidth: columnWidth, rowHeights: rowHeights)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // Without a finite offered width, fall back to one row at the buttons' own widths:
        // answering an `.infinity` probe with an infinite width would hand it back unchanged.
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? subviews.reduce(spacing * CGFloat(max(subviews.count - 1, 0))) {
            $0 + $1.sizeThatFits(.unspecified).width
        }
        let rows = grid(width: width, subviews: subviews).rowHeights
        return CGSize(width: width, height: rows.reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let grid = grid(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for (row, height) in grid.rowHeights.enumerated() {
            for column in 0..<grid.columns {
                let index = row * grid.columns + column
                guard index < subviews.count else { break }
                let x = bounds.minX + CGFloat(column) * (grid.columnWidth + spacing)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: grid.columnWidth, height: height)
                )
            }
            y += height + spacing
        }
    }
}
