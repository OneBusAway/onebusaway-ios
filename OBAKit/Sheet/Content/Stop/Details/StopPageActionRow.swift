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
    /// Whether the stop itself has loaded. Every action but Filter needs the
    /// `Stop` to do anything at all, and when the first fetch fails they would
    /// otherwise render enabled and silently do nothing — indistinguishable, to
    /// the rider, from the app being broken.
    let hasStop: Bool
    let routeCount: Int
    let hasHiddenRoutes: Bool
    let isListFiltered: Bool
    /// The Departure Type filter, which is app-wide rather than per-stop: it
    /// carries a Settings-level default, so it can be holding rows back on a
    /// stop the rider has never filtered.
    let departureFilter: ArrivalDepartureFilter
    let hasServiceAlerts: Bool

    /// Whether the route half of the Filter menu has anything to offer: a
    /// single-route stop has nothing to filter down to. The Departure Type half
    /// is unaffected — it applies to any stop — so this no longer gates the menu
    /// itself, only the route choices inside it.
    var canFilter: Bool { routeCount > 1 }

    /// Gates Bookmark, Nearby Stops, Walking Directions and Report a Problem,
    /// which all resolve against the loaded `Stop`. Schedule is not among them:
    /// it goes through `stopID`, which is known before the first fetch returns.
    var canActOnStop: Bool { hasStop }

    /// Which of the two route choices is checked. Saved hidden routes only count
    /// while the filter is actually applied.
    var isRouteFilterOn: Bool { hasHiddenRoutes && isListFiltered }

    /// Whether *anything* is holding departures back, which is what the glyph
    /// and the VoiceOver value report. Both halves of the menu count, matching
    /// the bar button this row replaces (`configureBarButtons()`): a rider whose
    /// Departure Type default is not `.all` is looking at a filtered list, and
    /// the glyph has to say so.
    var isFilterOn: Bool { isRouteFilterOn || departureFilter != .all }

    var filterSystemImage: String {
        isFilterOn ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
    }

    var canShowServiceAlerts: Bool { hasServiceAlerts }
}

/// Schedule, Filter, Bookmark and More, as circular buttons in a glass capsule
/// fixed at the bottom of the stop sheet.
///
/// Filter is promoted out of the More menu into its own button, so More carries
/// only the four remaining actions. A plain-value view: every action is a
/// closure supplied by `StopDetailsSheetView`.
struct StopPageActionRow: View {
    let state: StopPageActionRowState

    let onSchedule: () -> Void
    /// `true` applies the saved route filter, `false` shows all routes.
    let onSetListFiltered: (Bool) -> Void
    let onSetDepartureFilter: (ArrivalDepartureFilter) -> Void
    let onBookmark: () -> Void
    let onServiceAlerts: () -> Void
    let onNearbyStops: () -> Void
    let onWalkingDirections: () -> Void
    let onReportProblem: () -> Void

    /// No horizontal scrolling accommodation, unlike `StopPageToolbar`: that
    /// exists because captions grow with Dynamic Type until four of them stop
    /// fitting on one line. These glyphs are a fixed 34pt on a fixed 44pt hit
    /// region and do not scale, so four always fit on the narrowest device.
    var body: some View {
        HStack(spacing: 0) { items }
            .padding(.vertical, Self.verticalPadding)
            .regularGlassEffectIfAvailable(in: Capsule())
            // Outside the surface, so this is the gap between the capsule and
            // the sheet's edges rather than internal padding.
            .padding(.horizontal, 12)
            .padding(.bottom, Self.bottomInset)
    }

    // MARK: - Metrics

    private static let verticalPadding: CGFloat = 8

    /// Gap between the capsule and the bottom of the sheet. Rides on top of the
    /// device's own bottom safe area, which the enclosing `safeAreaInset`
    /// already accounts for — this is breathing room above the home indicator,
    /// not clearance of it.
    private static let bottomInset: CGFloat = 20

    /// Everything this view occupies at the bottom of the sheet, including the
    /// gap beneath it.
    ///
    /// Published because the scroll-to-top button has to clear it and cannot
    /// discover it: that button is an `.overlay(alignment: .bottomTrailing)`
    /// applied *after* the `safeAreaInset` this view is mounted in, so it aligns
    /// to the sheet's full frame and would otherwise land directly on top of the
    /// capsule. A constant rather than a measured height on purpose — nothing
    /// here depends on scroll position, and measuring it back into a position is
    /// how this screen once fed geometry into itself and pegged the main thread.
    static var occupiedHeight: CGFloat { glyphSize + verticalPadding * 2 + bottomInset }

    /// Four circular glass controls, evenly spread.
    ///
    /// Uncaptioned by design: the capsule floats over the departures it acts on,
    /// so every point of height it takes is a departure the rider cannot see.
    /// Each control names itself to VoiceOver through `.accessibilityLabel`, so
    /// dropping the visible text costs nothing to a screen reader.
    @ViewBuilder
    private var items: some View {
        scheduleItem
        filterItem
        bookmarkItem
        moreItem
    }

    // MARK: - Items

    private var scheduleItem: some View {
        item {
            Button(action: onSchedule) { glyph("calendar") }
                .glassCircleSurface()
                .accessibilityLabel(Strings.schedules)
        }
    }

    private var filterItem: some View {
        item {
            Menu { filterMenu } label: { glyph(state.filterSystemImage) }
                .glassCircleSurface()
                .accessibilityLabel(Strings.filter)
                .accessibilityValue(state.isFilterOn
                    ? OBALoc("stop_page.filter.a11y_on", value: "on", comment: "VoiceOver value of the route-filter bar button when the filter is active.")
                    : OBALoc("stop_page.filter.a11y_off", value: "off", comment: "VoiceOver value of the route-filter bar button when the filter is inactive."))
        }
    }

    private var bookmarkItem: some View {
        item {
            Button(action: onBookmark) { glyph("bookmark") }
                .glassCircleSurface()
                .disabled(!state.canActOnStop)
                .accessibilityLabel(Self.bookmarkTitle)
        }
    }

    /// More stays tappable even before the stop loads: Service Alerts already
    /// carries its own gate, and a menu whose every item is disabled still tells
    /// the rider more than a button that refuses to open.
    private var moreItem: some View {
        item {
            Menu { moreMenu } label: { glyph("ellipsis") }
                .glassCircleSurface()
                .accessibilityLabel(Strings.more)
        }
    }

    // MARK: - Menu contents

    /// The route choices and the Departure Type submenu, the same two sections
    /// the pushed page's `filterMenu()` carries. The route section is dropped on
    /// a stop with nothing to filter, rather than the whole menu being disabled:
    /// Departure Type still applies there.
    @ViewBuilder
    private var filterMenu: some View {
        if state.canFilter {
            Section {
                filterChoice(
                    title: OBALoc(
                        "stops_controller.filter.all_routes",
                        value: "All Routes",
                        comment: "A menu item on a Stop page that toggles the visible list of transit vehicles from a filtered list to all of the list items. e.g. a stop serves routes 1, 2, and 3. The user has filtered the stop to only show route 3. Chooosing this item will show 1, 2, and 3 again."
                    ),
                    isSelected: !state.isRouteFilterOn,
                    filtered: false
                )
                filterChoice(
                    title: OBALoc(
                        "stops_controller.filter.filtered_routes",
                        value: "Filtered Routes",
                        comment: "A menu item on a Stop page that toggles the visible list of transit vehicles from a list of all items to a filtered list. e.g. a stop serves routes 1, 2, and 3. The user wants to only view route 3. Choosing this item would show that subset of routes."
                    ),
                    isSelected: state.isRouteFilterOn,
                    filtered: true
                )
            }
        }

        departureFilterMenu
    }

    /// Everything, real-time only, or scheduled only — the same choices as the
    /// pushed page's `departureFilterMenu()` and `StopPageToolbar`, persisted
    /// app-wide through the shared view model.
    private var departureFilterMenu: some View {
        Menu {
            ForEach(ArrivalDepartureFilter.allCases, id: \.self) { filter in
                let isSelected = filter == state.departureFilter
                Button {
                    onSetDepartureFilter(filter)
                } label: {
                    menuChoiceLabel(filter.displayTitle, isSelected: isSelected)
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        } label: {
            Label(
                OBALoc(
                    "stop_controller.arrival_filter.menu_title",
                    value: "Departure Type",
                    comment: "Title for the menu that filters departures by data type"
                ),
                systemImage: "antenna.radiowaves.left.and.right"
            )
        }
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
            .disabled(!state.canActOnStop)

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
            .disabled(!state.canActOnStop)
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
            .disabled(!state.canActOnStop)
        }
    }

    private static let bookmarkTitle = OBALoc("stop_page.toolbar.bookmark", value: "Bookmark", comment: "Bottom-toolbar item on the Stop page that opens the Add Bookmark screen.")

    @ViewBuilder
    private func filterChoice(title: String, isSelected: Bool, filtered: Bool) -> some View {
        Button {
            onSetListFiltered(filtered)
        } label: {
            menuChoiceLabel(title, isSelected: isSelected)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// A menu row in a set of mutually exclusive choices. The checkmark is what
    /// a sighted rider reads the selection from — without it these are two
    /// identical plain rows — and it is why the label has to be a `Label` only
    /// when selected: an unselected `Label` with a blank image would indent the
    /// title away from its neighbour.
    @ViewBuilder
    private func menuChoiceLabel(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    /// One slot: the caller's glass control, given an equal share of the width.
    ///
    /// A disabled control dims itself, but only because nothing here pins its
    /// `foregroundStyle`: SwiftUI greys disabled content *through* the
    /// foreground style, so hard-coding `.primary` anywhere above the control
    /// would leave a disabled button looking identical to an enabled one while
    /// still refusing taps. With the captions gone this dimming is the only
    /// signal that an action is unavailable, so it must not be defeated.
    private func item(@ViewBuilder control: () -> some View) -> some View {
        control()
            .frame(maxWidth: .infinity)
    }

    /// The glyph a glass control wraps. `glassCircleLabel` draws it at
    /// `glyphSize` while claiming a 44pt hit region.
    private func glyph(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .glassCircleLabel(diameter: Self.glyphSize)
            .accessibilityHidden(true)
    }

    private static let glyphSize: CGFloat = 34
}

#Preview("Action row") {
    StopPageActionRow(
        state: StopPageActionRowState(hasStop: true, routeCount: 4, hasHiddenRoutes: true, isListFiltered: true, departureFilter: .all, hasServiceAlerts: true),
        onSchedule: {}, onSetListFiltered: { _ in }, onSetDepartureFilter: { _ in }, onBookmark: {},
        onServiceAlerts: {}, onNearbyStops: {}, onWalkingDirections: {}, onReportProblem: {}
    )
}

/// The first fetch failed: everything that needs the `Stop` dims, Schedule and
/// More stay live.
#Preview("Action row — stop not loaded") {
    StopPageActionRow(
        state: StopPageActionRowState(hasStop: false, routeCount: 0, hasHiddenRoutes: false, isListFiltered: false, departureFilter: .all, hasServiceAlerts: false),
        onSchedule: {}, onSetListFiltered: { _ in }, onSetDepartureFilter: { _ in }, onBookmark: {},
        onServiceAlerts: {}, onNearbyStops: {}, onWalkingDirections: {}, onReportProblem: {}
    )
}
