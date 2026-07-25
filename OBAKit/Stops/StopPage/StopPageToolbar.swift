//
//  StopPageToolbar.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The bottom toolbar shown when the Stop page is presented as a sheet over the map.
///
/// It carries the chrome that the pushed presentation puts in the navigation bar's right-hand
/// items, plus refresh. The sheet has no usable navigation bar — its top edge is a grabber, and
/// the space beside it is too narrow for four controls — so the chrome moves to the bottom, where
/// it is also easier to reach one-handed.
///
/// Only ever installed by `StopPageView` when `showToolbarOnBottom` is set. The pushed
/// presentation keeps `StopPageViewController.configureBarButtons()` and never sees this view, so
/// the two presentations don't have to agree on layout.
///
/// A plain-value view: every action is a closure supplied by `StopPageView`, and the freshness
/// label is passed in as already-formatted text.
struct StopPageToolbar: View {
    /// "Updated: Just Now" — the refresh item's VoiceOver value only. The visible label is the
    /// fixed word "Refresh"; freshness is not shown in the sheet's chrome.
    let statusText: String
    let isRefreshing: Bool
    /// Drives the filter glyph's filled/unfilled state, so an active filter is visible without
    /// opening the menu.
    let isFilterOn: Bool
    /// `false` for a single-route stop, where filtering can't do anything useful.
    let canFilter: Bool
    let isListFiltered: Bool
    let hasServiceAlerts: Bool

    let onRefresh: () -> Void
    /// `true` applies the saved route filter, `false` shows all routes.
    let onSetListFiltered: (Bool) -> Void
    let onBookmark: () -> Void
    let onSchedule: () -> Void
    let onServiceAlerts: () -> Void
    let onNearbyStops: () -> Void
    let onWalkingDirections: () -> Void
    let onReportProblem: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// At accessibility sizes the five stacked icon+label items can't share one line legibly, so
    /// the whole bar scrolls horizontally instead of shrinking the labels into illegibility.
    private var scrollsHorizontally: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        Group {
            if scrollsHorizontally {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 4) { items }
                        .padding(.horizontal, 8)
                }
            } else {
                HStack(alignment: .top, spacing: 0) { items }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private var items: some View {
        refreshItem

        button(
            title: OBALoc("stop_page.toolbar.bookmark", value: "Bookmark", comment: "Bottom-toolbar item on the Stop page that opens the Add Bookmark screen."),
            systemImage: "bookmark",
            action: onBookmark
        )

        button(title: Strings.schedules, systemImage: "calendar", action: onSchedule)

        moreItem
    }

    /// Refresh. The label names the action and stays put — a label that rewrites itself every few
    /// seconds ("Just Now" → "29 sec. ago") makes the bar feel restless and pushed the item wider
    /// than its slot. Freshness survives as the VoiceOver value, which costs nothing visually.
    private var refreshItem: some View {
        button(
            title: isRefreshing ? Strings.updating : Strings.refresh,
            systemImage: "arrow.clockwise",
            accessibilityLabel: Strings.refresh,
            accessibilityValue: statusText,
            action: onRefresh
        )
        .disabled(isRefreshing)
    }

    @ViewBuilder
    private func filterChoice(title: String, isSelected: Bool, filtered: Bool) -> some View {
        Button {
            onSetListFiltered(filtered)
        } label: {
            Text(title)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var moreItem: some View {
        Menu {
            Menu {
                filterChoice(
                    title: OBALoc("stops_controller.filter.all_routes", value: "All Routes", comment: "A menu item on a Stop page that toggles the visible list of transit vehicles from a filtered list to all of the list items. e.g. a stop serves routes 1, 2, and 3. The user has filtered the stop to only show route 3. Chooosing this item will show 1, 2, and 3 again."),
                    isSelected: !isFilterOn,
                    filtered: false
                )
                filterChoice(
                    title: OBALoc("stops_controller.filter.filtered_routes", value: "Filtered Routes", comment: "A menu item on a Stop page that toggles the visible list of transit vehicles from a list of all items to a filtered list. e.g. a stop serves routes 1, 2, and 3. The user wants to only view route 3. Choosing this item would show that subset of routes."),
                    isSelected: isFilterOn,
                    filtered: true
                )
            } label: {
                Label(
                    Strings.filter,
                    systemImage: isFilterOn ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
                )
            }
            .disabled(!canFilter)

            Button(action: onServiceAlerts) {
                Label(Strings.serviceAlerts, systemImage: "exclamationmark.circle")
            }
            .disabled(!hasServiceAlerts)

            Section {
                Button(action: onNearbyStops) {
                    Label(OBALoc("stops_controller.nearby_stops", value: "Nearby Stops", comment: "Title of the row that will show stops that are near this one."), systemImage: "location")
                }
                Button(action: onWalkingDirections) {
                    Label(OBALoc("stops_controller.walking_directions", value: "Walking Directions", comment: "Button that launches a maps app with walking directions to this stop"), systemImage: "figure.walk")
                }
            }

            Section {
                Button(action: onReportProblem) {
                    Label(OBALoc("stops_controller.report_problem", value: "Report a Problem", comment: "Button that launches the 'Report Problem' UI."), systemImage: "exclamationmark.bubble")
                }
            }
        } label: {
            label(title: Strings.more, systemImage: "ellipsis")
        }
        .accessibilityLabel(Strings.more)
    }

    // MARK: - Item Building

    private func button(
        title: String,
        systemImage: String,
        accessibilityLabel: String? = nil,
        accessibilityValue: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            label(title: title, systemImage: systemImage)
        }
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityValue(accessibilityValue ?? "")
    }

    /// Icon above label, the shape the mockup calls for and the shape a tab-bar-adjacent strip
    /// reads as. `UIToolbar` can't do this without custom item views, which is part of why this
    /// bar is built in SwiftUI rather than handed to the wrapping navigation controller.
    private func label(title: String, systemImage: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .regular))
                .frame(height: 22)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption2)
                // The freshness label changes width as time passes. Shrink and truncate inside
                // the slot rather than letting it size the item — an unbounded label overflows
                // into its neighbours, since the VStack centers text wider than its frame.
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.tint)
        .frame(maxWidth: scrollsHorizontally ? nil : .infinity)
        .frame(minWidth: scrollsHorizontally ? 84 : nil)
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
    }
}

#Preview("Toolbar") {
    VStack {
        Spacer()
        StopPageToolbar(
            statusText: "Updated: Just Now",
            isRefreshing: false,
            isFilterOn: false,
            canFilter: true,
            isListFiltered: false,
            hasServiceAlerts: true,
            onRefresh: {}, onSetListFiltered: { _ in }, onBookmark: {}, onSchedule: {},
            onServiceAlerts: {}, onNearbyStops: {}, onWalkingDirections: {}, onReportProblem: {}
        )
    }
}
