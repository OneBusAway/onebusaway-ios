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

    @ViewBuilder
    private var items: some View {
        button(title: Strings.schedules, systemImage: "calendar", action: onSchedule)

        filterItem

        button(
            title: OBALoc("stop_page.toolbar.bookmark", value: "Bookmark", comment: "Bottom-toolbar item on the Stop page that opens the Add Bookmark screen."),
            systemImage: "bookmark",
            action: onBookmark
        )

        moreItem
    }

    private var filterItem: some View {
        Menu {
            filterChoice(
                title: OBALoc("stops_controller.filter.all_routes", value: "All Routes", comment: "A menu item on a Stop page that toggles the visible list of transit vehicles from a filtered list to all of the list items. e.g. a stop serves routes 1, 2, and 3. The user has filtered the stop to only show route 3. Chooosing this item will show 1, 2, and 3 again."),
                isSelected: !state.isFilterOn,
                filtered: false
            )
            filterChoice(
                title: OBALoc("stops_controller.filter.filtered_routes", value: "Filtered Routes", comment: "A menu item on a Stop page that toggles the visible list of transit vehicles from a list of all items to a filtered list. e.g. a stop serves routes 1, 2, and 3. The user wants to only view route 3. Choosing this item would show that subset of routes."),
                isSelected: state.isFilterOn,
                filtered: true
            )
        } label: {
            label(title: Strings.filter, systemImage: state.filterSystemImage)
        }
        .buttonStyle(.plain)
        .disabled(!state.canFilter)
        .accessibilityLabel(Strings.filter)
        .accessibilityValue(state.isFilterOn
            ? OBALoc("stop_page.filter.a11y_on", value: "on", comment: "VoiceOver value of the route-filter bar button when the filter is active.")
            : OBALoc("stop_page.filter.a11y_off", value: "off", comment: "VoiceOver value of the route-filter bar button when the filter is inactive."))
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
            Button(action: onServiceAlerts) {
                Label(Strings.serviceAlerts, systemImage: "exclamationmark.circle")
            }
            .disabled(!state.canShowServiceAlerts)

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
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.more)
    }

    private func button(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label(title: title, systemImage: systemImage)
        }
        // Without `.plain` the button style tints its label with the accent
        // colour, overriding the neutral `foregroundStyle` in `label(...)`.
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    /// A glass circle with the glyph, captioned beneath.
    private func label(title: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .modifier(GlassCircleBackground())
                .accessibilityHidden(true)
            Text(title)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        // `.primary`, not `.tint`: the row reads as neutral chrome rather than
        // four tinted calls to action. That is black in light mode, and stays
        // legible in dark mode where a literal black would disappear against
        // the sheet's background.
        .foregroundStyle(.primary)
        .frame(maxWidth: scrollsHorizontally ? nil : .infinity)
        .frame(minWidth: scrollsHorizontally ? 84 : nil)
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
    }
}

/// The circular button backdrop: real Liquid Glass on iOS 26+, an
/// ultra-thin-material circle with a hairline rim on earlier versions. Mirrors
/// the treatment `GlassContainerBackground` gives the mode toggle and the
/// Load-more capsule, which is private to `StopPageView.swift`.
private struct GlassCircleBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: Circle())
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color(uiColor: .separator).opacity(0.5), lineWidth: 0.5))
        }
    }
}

#Preview("Action row") {
    StopPageActionRow(
        state: StopPageActionRowState(routeCount: 4, hasHiddenRoutes: true, isListFiltered: true, hasServiceAlerts: true),
        onSchedule: {}, onSetListFiltered: { _ in }, onBookmark: {},
        onServiceAlerts: {}, onNearbyStops: {}, onWalkingDirections: {}, onReportProblem: {}
    )
}
