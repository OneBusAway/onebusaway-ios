//
//  StopPageActionRow.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The action row's enabled/filled predicates, as a value so they can be
/// tested without inspecting a view — the precedent set by
/// `SheetDetentConfiguration.shouldDisableBackgroundForFullScreen`.
nonisolated struct StopPageActionRowState {
    let routeCount: Int
    let hasHiddenRoutes: Bool
    let isListFiltered: Bool
    let hasServiceAlerts: Bool

    /// A single-route stop has nothing to filter down to.
    var canFilter: Bool { routeCount > 1 }

    /// Saved hidden routes only count while the filter is actually applied.
    var isFilterOn: Bool { hasHiddenRoutes && isListFiltered }

    var filterSystemImage: String {
        isFilterOn ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
    }

    var canShowServiceAlerts: Bool { hasServiceAlerts }
}

/// Schedule, Filter, Bookmark and More, as circular buttons under the stop
/// sheet's map header.
///
/// Filter is promoted out of the More menu into its own button, so More carries
/// only the four remaining actions. A plain-value view: every action is a
/// closure supplied by `StopDetailsSheetView`.
struct StopPageActionRow: View {
    let state: StopPageActionRowState

    let onSchedule: () -> Void
    /// `true` applies the saved route filter, `false` shows all routes.
    let onSetListFiltered: (Bool) -> Void
    let onBookmark: () -> Void
    let onServiceAlerts: () -> Void
    let onNearbyStops: () -> Void
    let onWalkingDirections: () -> Void
    let onReportProblem: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// At accessibility sizes four icon-and-label items can't share one line
    /// legibly, so the row scrolls instead of shrinking the labels into
    /// illegibility — the accommodation `StopPageToolbar` makes.
    private var scrollsHorizontally: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        Group {
            if scrollsHorizontally {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 8) { items }
                        .padding(.horizontal, 12)
                }
            } else {
                HStack(alignment: .top, spacing: 0) { items }
            }
        }
        .padding(.vertical, 10)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    /// Each column is a circular glass control with its caption underneath.
    ///
    /// The caption deliberately sits OUTSIDE the button. `liquidGlassButtonStyle`
    /// turns the whole button into one glass surface, so a button wrapping both
    /// the glyph and the text would render as an oval blob around the pair
    /// instead of a circle around the glyph.
    @ViewBuilder
    private var items: some View {
        scheduleItem
        filterItem
        bookmarkItem
        moreItem
    }

    // MARK: - Items

    private var scheduleItem: some View {
        item(title: Strings.schedules) {
            Button(action: onSchedule) { glyph("calendar") }
                .liquidGlassButtonStyle(borderShape: .circle, fallbackShape: Circle())
                .accessibilityLabel(Strings.schedules)
        }
    }

    private var filterItem: some View {
        item(title: Strings.filter, isEnabled: state.canFilter) {
            Menu { filterMenu } label: { glyph(state.filterSystemImage) }
                .liquidGlassButtonStyle(borderShape: .circle, fallbackShape: Circle())
                .disabled(!state.canFilter)
                .accessibilityLabel(Strings.filter)
                .accessibilityValue(state.isFilterOn
                    ? OBALoc("stop_page.filter.a11y_on", value: "on", comment: "VoiceOver value of the route-filter bar button when the filter is active.")
                    : OBALoc("stop_page.filter.a11y_off", value: "off", comment: "VoiceOver value of the route-filter bar button when the filter is inactive."))
        }
    }

    private var bookmarkItem: some View {
        item(title: Self.bookmarkTitle) {
            Button(action: onBookmark) { glyph("bookmark") }
                .liquidGlassButtonStyle(borderShape: .circle, fallbackShape: Circle())
                .accessibilityLabel(Self.bookmarkTitle)
        }
    }

    private var moreItem: some View {
        item(title: Strings.more) {
            Menu { moreMenu } label: { glyph("ellipsis") }
                .liquidGlassButtonStyle(borderShape: .circle, fallbackShape: Circle())
                .accessibilityLabel(Strings.more)
        }
    }

    // MARK: - Menu contents

    @ViewBuilder
    private var filterMenu: some View {
        filterChoice(
            title: OBALoc(
                "stops_controller.filter.all_routes",
                value: "All Routes",
                comment: "A menu item on a Stop page that toggles the visible list of transit vehicles from a filtered list to all of the list items. e.g. a stop serves routes 1, 2, and 3. The user has filtered the stop to only show route 3. Chooosing this item will show 1, 2, and 3 again."
            ),
            isSelected: !state.isFilterOn,
            filtered: false
        )
        filterChoice(
            title: OBALoc(
                "stops_controller.filter.filtered_routes",
                value: "Filtered Routes",
                comment: "A menu item on a Stop page that toggles the visible list of transit vehicles from a list of all items to a filtered list. e.g. a stop serves routes 1, 2, and 3. The user wants to only view route 3. Choosing this item would show that subset of routes."
            ),
            isSelected: state.isFilterOn,
            filtered: true
        )
    }

    @ViewBuilder
    private var moreMenu: some View {
        Button(action: onServiceAlerts) {
            Label(Strings.serviceAlerts, systemImage: "exclamationmark.circle")
        }
        .disabled(!state.canShowServiceAlerts)

        Section {
            Button(action: onNearbyStops) {
                Label(
                    OBALoc(
                        "stops_controller.nearby_stops",
                        value: "Nearby Stops",
                        comment: "Title of the row that will show stops that are near this one."
                    ),
                    systemImage: "location"
                )
            }
            Button(action: onWalkingDirections) {
                Label(
                    OBALoc(
                        "stops_controller.walking_directions",
                        value: "Walking Directions",
                        comment: "Button that launches a maps app with walking directions to this stop"
                    ),
                    systemImage: "figure.walk"
                )
            }
        }

        Section {
            Button(action: onReportProblem) {
                Label(
                    OBALoc(
                        "stops_controller.report_problem",
                        value: "Report a Problem",
                        comment: "Button that launches the 'Report Problem' UI."
                    ),
                    systemImage: "exclamationmark.bubble"
                )
            }
        }
    }

    private static let bookmarkTitle = OBALoc("stop_page.toolbar.bookmark", value: "Bookmark", comment: "Bottom-toolbar item on the Stop page that opens the Add Bookmark screen.")

    @ViewBuilder
    private func filterChoice(title: String, isSelected: Bool, filtered: Bool) -> some View {
        Button {
            onSetListFiltered(filtered)
        } label: {
            Text(title)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// One column: the caller's glass control, captioned beneath.
    ///
    /// `isEnabled` drives the caption's colour. The glyph dims on its own — but
    /// only because nothing here pins its `foregroundStyle`: SwiftUI greys
    /// disabled content *through* the foreground style, so hard-coding
    /// `.primary` anywhere above the control leaves a disabled button looking
    /// identical to an enabled one while still refusing taps.
    private func item(title: String, isEnabled: Bool = true, @ViewBuilder control: () -> some View) -> some View {
        VStack(spacing: 6) {
            control()
            Text(title)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                // The caption sits outside the button, so it is not covered by
                // the control's own disabled dimming.
                .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
        }
        // `.tint`, not `.foregroundStyle`: the glass button style colours its
        // content from the tint, so the row reads as neutral chrome rather than
        // four tinted calls to action — and disabled dimming still applies.
        .tint(.primary)
        .frame(maxWidth: scrollsHorizontally ? nil : .infinity)
        .frame(minWidth: scrollsHorizontally ? 84 : nil)
        .padding(.horizontal, 2)
    }

    /// The glyph a glass control wraps. Sized so the control lands on a 44pt
    /// tap target.
    private func glyph(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .frame(width: 34, height: 34)
            .contentShape(Circle())
            .accessibilityHidden(true)
    }
}

#Preview("Action row") {
    StopPageActionRow(
        state: StopPageActionRowState(routeCount: 4, hasHiddenRoutes: true, isListFiltered: true, hasServiceAlerts: true),
        onSchedule: {}, onSetListFiltered: { _ in }, onBookmark: {},
        onServiceAlerts: {}, onNearbyStops: {}, onWalkingDirections: {}, onReportProblem: {}
    )
}
